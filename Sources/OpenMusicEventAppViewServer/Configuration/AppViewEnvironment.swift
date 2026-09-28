import OpenMusicEventOAuthClient
import ATProto
import ComposableNotifications
import Foundation
import Hummingbird

public extension AppViewConfiguration {
    static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
        let clientName = environment["OME_OAUTH_CLIENT"] ?? "production"
        guard let oauthClient = OpenMusicEventOAuthClient(rawValue: clientName) else {
            throw AppViewConfigurationError.invalidOAuthClient(clientName)
        }
        let databaseURL = URL(
            fileURLWithPath: environment["OME_APPVIEW_DATABASE_PATH"]
                ?? FileManager.default.currentDirectoryPath + "/open-music-event-appview.sqlite"
        )
        let ingestion = environment["OME_APPVIEW_HYDRANT_ENDPOINT"].map {
            AppViewIngestionConfiguration(
                endpoint: $0,
                subscriptionID: environment["OME_APPVIEW_HYDRANT_SUBSCRIPTION_ID"]
                    ?? "hydrant|community.lexicon.calendar.event"
            )
        }

        let notificationProviders = try notificationProviderConfiguration(
            environment: environment
        )
        let notificationDestinationProtection: NotificationDestinationProtection?
        if let encodedKey = environment["OME_NOTIFICATION_DESTINATION_KEY"] {
            let rawKeyVersion = environment["OME_NOTIFICATION_DESTINATION_KEY_VERSION"] ?? "1"
            guard let keyVersion = Int(rawKeyVersion), keyVersion > 0 else {
                throw AppViewConfigurationError.invalidNotificationDestinationKeyVersion(
                    rawKeyVersion
                )
            }
            notificationDestinationProtection = try NotificationDestinationProtection(
                base64EncodedKey: encodedKey,
                keyVersion: keyVersion
            )
        } else {
            guard environment["OME_NOTIFICATION_DESTINATION_KEY_VERSION"] == nil else {
                throw AppViewConfigurationError.notificationDestinationKeyMissing
            }
            notificationDestinationProtection = nil
        }

        let notificationRegistration: AppViewNotificationRegistrationConfiguration?
        if let authorization = environment["OME_NOTIFICATION_REGISTRATION_AUTHORIZATION"] {
            guard authorization == "anonymous" else {
                throw AppViewConfigurationError.unsupportedNotificationAuthorization(
                    authorization
                )
            }
            guard notificationDestinationProtection != nil else {
                throw AppViewConfigurationError.notificationDestinationKeyMissing
            }
            let applicationIDs = Set(
                (environment["OME_NOTIFICATION_APPLICATION_IDS"] ?? "")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .map(Push.ApplicationID.init(rawValue:))
            )
            guard !applicationIDs.isEmpty else {
                throw AppViewConfigurationError.notificationApplicationIDsMissing
            }
            notificationRegistration = AppViewNotificationRegistrationConfiguration(
                authorization: .anonymous,
                allowedApplicationIDs: applicationIDs
            )
        } else {
            notificationRegistration = nil
        }

        if let notificationProviders, let notificationRegistration {
            var configuredApplicationIDs: Set<Push.ApplicationID> = []
            if let apns = notificationProviders.apns {
                configuredApplicationIDs.formUnion(apns.applications.keys)
            }
            if let fcm = notificationProviders.fcm {
                configuredApplicationIDs.formUnion(fcm.applications.keys)
            }
            if let missingApplicationID = notificationRegistration.allowedApplicationIDs
                .first(where: { !configuredApplicationIDs.contains($0) })
            {
                throw AppViewConfigurationError.notificationProviderApplicationMissing(
                    missingApplicationID
                )
            }
        }

        let webhookSecretProtection = try webhookSecretProtection(environment: environment)
        let tangledWebhook = try tangledWebhookConfiguration(environment: environment)
        guard tangledWebhook == nil || webhookSecretProtection != nil else {
            throw AppViewConfigurationError.webhookSecretKeyMissing
        }
        let sourceArtifacts = try sourceArtifactConfiguration(environment: environment)
        guard tangledWebhook == nil || sourceArtifacts != nil else {
            throw AppViewConfigurationError.sourceArtifactConfigurationMissing
        }

        return Self(
            host: environment["OME_APPVIEW_HOST"] ?? "127.0.0.1",
            port: environment["OME_APPVIEW_PORT"].flatMap(Int.init) ?? 8080,
            publicAppViewHost: ATProto.PDSHost(
                environment["OME_APPVIEW_PUBLIC_HOST"] ?? "openmusicevent.app"
            ),
            siteRoot: environment["OME_APPVIEW_SITE_ROOT"].map(URL.init(fileURLWithPath:)),
            oauthClient: oauthClient,
            wellKnownRoot: environment["OME_APPVIEW_WELL_KNOWN_ROOT"].map(URL.init(fileURLWithPath:)),
            brandedEventRouteClaims: try brandedEventRouteClaims(environment: environment),
            databaseURL: databaseURL,
            ingestion: ingestion,
            notificationProviders: notificationProviders,
            notificationDestinationProtection: notificationDestinationProtection,
            notificationRegistration: notificationRegistration,
            webhookSecretProtection: webhookSecretProtection,
            tangledWebhook: tangledWebhook,
            sourceArtifacts: sourceArtifacts
        )
    }

    static func lambda(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
        let taskRoot = URL(
            fileURLWithPath: environment["LAMBDA_TASK_ROOT"]
                ?? FileManager.default.currentDirectoryPath
        )
        let siteRoot = environment["OME_APPVIEW_SITE_ROOT"]
            .map(URL.init(fileURLWithPath:))
            ?? taskRoot.appendingPathComponent("Site", isDirectory: true)
        let wellKnownRoot = environment["OME_APPVIEW_WELL_KNOWN_ROOT"]
            .map(URL.init(fileURLWithPath:))
            ?? taskRoot.appendingPathComponent("WellKnown", isDirectory: true)

        return Self(
            host: environment["OME_APPVIEW_HOST"] ?? "127.0.0.1",
            port: environment["OME_APPVIEW_PORT"].flatMap(Int.init) ?? 8080,
            publicAppViewHost: ATProto.PDSHost(
                environment["OME_APPVIEW_PUBLIC_HOST"] ?? "openmusicevent.app"
            ),
            siteRoot: siteRoot,
            wellKnownRoot: wellKnownRoot,
            brandedEventRouteClaims: try brandedEventRouteClaims(environment: environment)
        )
    }

    var hummingbirdConfiguration: ApplicationConfiguration {
        .init(address: .hostname(host, port: port))
    }
}
