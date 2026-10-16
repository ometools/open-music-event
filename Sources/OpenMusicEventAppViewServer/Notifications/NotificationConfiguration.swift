import ComposableNotifications
import Foundation
import Tagged

public struct AppViewNotificationRegistrationConfiguration: Equatable, Sendable {
    public enum Authorization: Equatable, Sendable {
        case anonymous
    }

    public init(
        authorization: Authorization,
        allowedApplicationIDs: Set<Push.ApplicationID>
    ) {
        self.authorization = authorization
        self.allowedApplicationIDs = allowedApplicationIDs
    }

    public var authorization: Authorization
    public var allowedApplicationIDs: Set<Push.ApplicationID>
}

public struct AppViewNotificationProviderConfiguration: Equatable, Sendable {
    public struct APNS: Equatable, Sendable {
        public struct Application: Equatable, Sendable {
            public init(
                environment: Push.APNS.Environment,
                allowedEnvironments: Set<Push.APNS.Environment>? = nil,
                topic: String
            ) {
                self.environment = environment
                self.allowedEnvironments = allowedEnvironments ?? [environment]
                self.topic = topic
            }

            /// The trusted fallback used to open registrations written before environments
            /// became part of the destination contract.
            public var environment: Push.APNS.Environment
            public var allowedEnvironments: Set<Push.APNS.Environment>
            public var topic: String
        }

        public init(
            applications: [Push.ApplicationID: Application],
            teamID: String,
            keyID: String,
            privateKeyURL: URL
        ) {
            self.applications = applications
            self.teamID = teamID
            self.keyID = keyID
            self.privateKeyURL = privateKeyURL
        }

        public var applications: [Push.ApplicationID: Application]
        public var teamID: String
        public var keyID: String
        public var privateKeyURL: URL
    }

    public struct FCM: Equatable, Sendable {
        public struct Application: Equatable, Sendable {
            public init(projectID: String, emergencyChannelID: String) {
                self.projectID = projectID
                self.emergencyChannelID = emergencyChannelID
            }

            public var projectID: String
            public var emergencyChannelID: String
        }

        public init(
            applications: [Push.ApplicationID: Application],
            serviceAccountURL: URL
        ) {
            self.applications = applications
            self.serviceAccountURL = serviceAccountURL
        }

        public var applications: [Push.ApplicationID: Application]
        public var serviceAccountURL: URL
    }

    public init(apns: APNS? = nil, fcm: FCM? = nil) {
        self.apns = apns
        self.fcm = fcm
    }

    public var apns: APNS?
    public var fcm: FCM?
}

extension AppViewConfiguration {
    static func notificationProviderConfiguration(
        environment: [String: String]
    ) throws -> AppViewNotificationProviderConfiguration? {
        let keys = [
            "OME_APNS_KEY_ID",
            "OME_APNS_PRIVATE_KEY_PATH",
            "OME_APNS_TEAM_ID",
            "OME_FCM_SERVICE_ACCOUNT_PATH",
            "OME_NOTIFICATION_PROVIDER_CONFIGURATION_PATH",
        ]
        guard keys.contains(where: { environment[$0] != nil }) else {
            return nil
        }

        func required(_ key: String) throws -> String {
            guard let value = environment[key]?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !value.isEmpty else {
                throw AppViewConfigurationError.notificationProviderConfigurationValueMissing(key)
            }
            return value
        }

        let path = try required("OME_NOTIFICATION_PROVIDER_CONFIGURATION_PATH")
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw AppViewConfigurationError.notificationProviderConfigurationUnreadable(path)
        }

        let file: NotificationProviderConfigurationFile
        do {
            file = try JSONDecoder().decode(NotificationProviderConfigurationFile.self, from: data)
        } catch {
            throw AppViewConfigurationError.notificationProviderConfigurationInvalid(path)
        }
        guard !file.apns.isEmpty || !file.fcm.isEmpty else {
            throw AppViewConfigurationError.notificationProviderConfigurationEmpty(path)
        }

        var apnsApplications: [
            Push.ApplicationID: AppViewNotificationProviderConfiguration.APNS.Application
        ] = [:]
        for application in file.apns {
            guard
                isNonemptyConfigurationValue(application.applicationID),
                isNonemptyConfigurationValue(application.topic)
            else {
                throw AppViewConfigurationError.notificationProviderConfigurationInvalid(path)
            }
            let applicationID = Push.ApplicationID(rawValue: application.applicationID)
            guard apnsApplications[applicationID] == nil else {
                throw AppViewConfigurationError.duplicateNotificationProviderApplicationID(
                    provider: "apns",
                    applicationID: applicationID
                )
            }
            let allowedEnvironments = Set(
                application.allowedEnvironments ?? [application.environment]
            )
            guard
                !allowedEnvironments.isEmpty,
                allowedEnvironments.contains(application.environment),
                allowedEnvironments.count
                    == (application.allowedEnvironments ?? [application.environment]).count
            else {
                throw AppViewConfigurationError.notificationProviderConfigurationInvalid(path)
            }
            apnsApplications[applicationID] = .init(
                environment: application.environment,
                allowedEnvironments: allowedEnvironments,
                topic: application.topic
            )
        }

        var fcmApplications: [
            Push.ApplicationID: AppViewNotificationProviderConfiguration.FCM.Application
        ] = [:]
        for application in file.fcm {
            guard
                isNonemptyConfigurationValue(application.applicationID),
                isNonemptyConfigurationValue(application.projectID),
                isNonemptyConfigurationValue(application.emergencyChannelID)
            else {
                throw AppViewConfigurationError.notificationProviderConfigurationInvalid(path)
            }
            let applicationID = Push.ApplicationID(rawValue: application.applicationID)
            guard fcmApplications[applicationID] == nil else {
                throw AppViewConfigurationError.duplicateNotificationProviderApplicationID(
                    provider: "fcm",
                    applicationID: applicationID
                )
            }
            fcmApplications[applicationID] = .init(
                projectID: application.projectID,
                emergencyChannelID: application.emergencyChannelID
            )
        }

        let apns: AppViewNotificationProviderConfiguration.APNS?
        if apnsApplications.isEmpty {
            guard environment["OME_APNS_KEY_ID"] == nil,
                  environment["OME_APNS_PRIVATE_KEY_PATH"] == nil,
                  environment["OME_APNS_TEAM_ID"] == nil
            else {
                throw AppViewConfigurationError.notificationProviderApplicationsMissing("apns")
            }
            apns = nil
        } else {
            apns = try .init(
                applications: apnsApplications,
                teamID: required("OME_APNS_TEAM_ID"),
                keyID: required("OME_APNS_KEY_ID"),
                privateKeyURL: URL(
                    fileURLWithPath: required("OME_APNS_PRIVATE_KEY_PATH")
                )
            )
        }

        let fcm: AppViewNotificationProviderConfiguration.FCM?
        if fcmApplications.isEmpty {
            guard environment["OME_FCM_SERVICE_ACCOUNT_PATH"] == nil else {
                throw AppViewConfigurationError.notificationProviderApplicationsMissing("fcm")
            }
            fcm = nil
        } else {
            fcm = try .init(
                applications: fcmApplications,
                serviceAccountURL: URL(
                    fileURLWithPath: required("OME_FCM_SERVICE_ACCOUNT_PATH")
                )
            )
        }

        return AppViewNotificationProviderConfiguration(apns: apns, fcm: fcm)
    }

    var legacyAPNSEnvironments: [Push.ApplicationID: Push.APNS.Environment] {
        notificationProviders?.apns?.applications.mapValues(\.environment) ?? [:]
    }
}

private struct NotificationProviderConfigurationFile: Decodable {
    var apns: [APNSApplication]
    var fcm: [FCMApplication]

    struct APNSApplication: Decodable {
        var applicationID: String
        var environment: Push.APNS.Environment
        var allowedEnvironments: [Push.APNS.Environment]?
        var topic: String
    }

    struct FCMApplication: Decodable {
        var applicationID: String
        var projectID: String
        var emergencyChannelID: String
    }
}

private func isNonemptyConfigurationValue(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && trimmed == value
}
