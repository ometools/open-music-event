import ATProto
import ComposableNotifications
import Foundation
import Hummingbird
import OpenMusicEventLexicon
import OpenMusicEventRouting
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
            public init(projectID: String) {
                self.projectID = projectID
            }

            public var projectID: String
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

public struct AppViewConfiguration: Sendable {
    public init(
        host: String = "127.0.0.1",
        port: Int = 8080,
        publicAppViewHost: ATProto.PDSHost = "openmusicevent.app",
        siteRoot: URL? = nil,
        wellKnownRoot: URL? = nil,
        brandedEventRouteClaims: [BrandedEventRouteClaim] = [],
        databaseURL: URL? = nil,
        ingestion: AppViewIngestionConfiguration? = nil,
        notificationProviders: AppViewNotificationProviderConfiguration? = nil,
        notificationDestinationProtection: NotificationDestinationProtection? = nil,
        notificationRegistration: AppViewNotificationRegistrationConfiguration? = nil,
        webhookSecretProtection: WebhookSecretProtection? = nil,
        tangledWebhook: TangledWebhookConfiguration? = nil,
        sourceArtifacts: SourceArtifactS3Configuration? = nil
    ) {
        self.host = host
        self.port = port
        self.publicAppViewHost = publicAppViewHost
        self.siteRoot = siteRoot ?? Bundle.module.resourceURL!.appendingPathComponent("Site")
        self.wellKnownRoot = wellKnownRoot ?? Bundle.module.resourceURL!.appendingPathComponent("WellKnown")
        self.brandedEventRouteClaims = brandedEventRouteClaims
        self.databaseURL = databaseURL
        self.ingestion = ingestion
        self.notificationProviders = notificationProviders
        self.notificationDestinationProtection = notificationDestinationProtection
        self.notificationRegistration = notificationRegistration
        self.webhookSecretProtection = webhookSecretProtection
        self.tangledWebhook = tangledWebhook
        self.sourceArtifacts = sourceArtifacts
    }

    public var host: String
    public var port: Int
    public var publicAppViewHost: ATProto.PDSHost
    public var siteRoot: URL
    public var wellKnownRoot: URL
    public var brandedEventRouteClaims: [BrandedEventRouteClaim]
    public var databaseURL: URL?
    public var ingestion: AppViewIngestionConfiguration?
    public var notificationProviders: AppViewNotificationProviderConfiguration?
    public var notificationDestinationProtection: NotificationDestinationProtection?
    public var notificationRegistration: AppViewNotificationRegistrationConfiguration?
    public var webhookSecretProtection: WebhookSecretProtection?
    public var tangledWebhook: TangledWebhookConfiguration?
    public var sourceArtifacts: SourceArtifactS3Configuration?
}

public struct AppViewIngestionConfiguration: Equatable, Sendable {
    public init(
        endpoint: String,
        subscriptionID: String = "hydrant|community.lexicon.calendar.event"
    ) {
        self.endpoint = endpoint
        self.subscriptionID = subscriptionID
    }

    public var endpoint: String
    public var subscriptionID: String
}

public extension AppViewConfiguration {
    static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
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
        let tangledWebhook = try tangledWebhookConfiguration(
            environment: environment
        )
        guard tangledWebhook == nil || webhookSecretProtection != nil else {
            throw AppViewConfigurationError.webhookSecretKeyMissing
        }
        let sourceArtifacts = try sourceArtifactConfiguration(environment: environment)
        guard tangledWebhook == nil || sourceArtifacts != nil else {
            throw AppViewConfigurationError.sourceArtifactConfigurationMissing
        }
        let brandedEventRouteClaims = try brandedEventRouteClaims(environment: environment)
        return Self(
            host: environment["OME_APPVIEW_HOST"] ?? "127.0.0.1",
            port: environment["OME_APPVIEW_PORT"].flatMap(Int.init) ?? 8080,
            publicAppViewHost: ATProto.PDSHost(
                environment["OME_APPVIEW_PUBLIC_HOST"] ?? "openmusicevent.app"
            ),
            siteRoot: environment["OME_APPVIEW_SITE_ROOT"].map(URL.init(fileURLWithPath:)),
            wellKnownRoot: environment["OME_APPVIEW_WELL_KNOWN_ROOT"].map(URL.init(fileURLWithPath:)),
            brandedEventRouteClaims: brandedEventRouteClaims,
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
        Self(
            host: environment["OME_APPVIEW_HOST"] ?? "127.0.0.1",
            port: environment["OME_APPVIEW_PORT"].flatMap(Int.init) ?? 8080,
            publicAppViewHost: ATProto.PDSHost(
                environment["OME_APPVIEW_PUBLIC_HOST"] ?? "openmusicevent.app"
            ),
            siteRoot: lambdaSiteRoot(environment: environment),
            wellKnownRoot: lambdaWellKnownRoot(environment: environment),
            brandedEventRouteClaims: try brandedEventRouteClaims(environment: environment)
        )
    }

    var hummingbirdConfiguration: ApplicationConfiguration {
        .init(address: .hostname(host, port: port))
    }

    private static func lambdaSiteRoot(environment: [String: String]) -> URL {
        if let siteRoot = environment["OME_APPVIEW_SITE_ROOT"] {
            return URL(fileURLWithPath: siteRoot)
        }

        let taskRoot = environment["LAMBDA_TASK_ROOT"] ?? FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: taskRoot).appendingPathComponent("Site", isDirectory: true)
    }

    private static func lambdaWellKnownRoot(environment: [String: String]) -> URL {
        if let wellKnownRoot = environment["OME_APPVIEW_WELL_KNOWN_ROOT"] {
            return URL(fileURLWithPath: wellKnownRoot)
        }

        let taskRoot = environment["LAMBDA_TASK_ROOT"] ?? FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: taskRoot).appendingPathComponent("WellKnown", isDirectory: true)
    }

    private static func tangledWebhookConfiguration(
        environment: [String: String]
    ) throws -> TangledWebhookConfiguration? {
        guard let path = environment["OME_TANGLED_WEBHOOK_CONFIGURATION_PATH"] else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw AppViewConfigurationError.tangledWebhookConfigurationUnreadable(path)
        }

        let file: TangledWebhookConfigurationFile
        do {
            file = try JSONDecoder().decode(TangledWebhookConfigurationFile.self, from: data)
        } catch {
            throw AppViewConfigurationError.tangledWebhookConfigurationInvalid(path)
        }

        let watches = try file.watches.map { configuredWatch in
            guard let repositoryOwnerDID = DID(configuredWatch.repositoryOwnerDID) else {
                throw AppViewConfigurationError.invalidTangledWebhookRepositoryOwnerDID(
                    configuredWatch.repositoryOwnerDID
                )
            }
            guard let organizerID = OME.Organizer.ID(
                configuredWatch.canonicalSource.organizerID
            ) else {
                throw AppViewConfigurationError.invalidTangledCanonicalSourceOrganizerID(
                    configuredWatch.canonicalSource.organizerID
                )
            }
            let watchID = WebhookInboxDelivery.WatchID(rawValue: configuredWatch.id)
            return TangledWebhookWatch(
                id: watchID,
                hookID: configuredWatch.hookID,
                repositoryOwnerDID: repositoryOwnerDID,
                repositoryKey: ATProto.Record.Key(rawValue: configuredWatch.repositoryKey),
                ref: configuredWatch.ref,
                canonicalSource: CanonicalTangledSource(
                    organizerID: organizerID,
                    repositoryRecordKey: ATProto.Record.Key(
                        rawValue: configuredWatch.canonicalSource.repositoryRecordKey
                    )
                ),
                artifactRepository: SourceArtifactRepository(
                    owner: configuredWatch.artifactRepository.owner,
                    repository: configuredWatch.artifactRepository.repository
                )
            )
        }
        return try TangledWebhookConfiguration(watches: watches)
    }

    private static func sourceArtifactConfiguration(
        environment: [String: String]
    ) throws -> SourceArtifactS3Configuration? {
        let keys = [
            "OME_SOURCE_ARTIFACT_S3_BUCKET",
            "OME_SOURCE_ARTIFACT_S3_REGION",
            "OME_SOURCE_ARTIFACT_PUBLIC_ORIGIN",
        ]
        guard keys.contains(where: { environment[$0] != nil }) else {
            return nil
        }

        func required(_ key: String) throws -> String {
            guard let value = environment[key]?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !value.isEmpty else {
                throw AppViewConfigurationError.sourceArtifactConfigurationValueMissing(key)
            }
            return value
        }

        let rawOrigin = try required("OME_SOURCE_ARTIFACT_PUBLIC_ORIGIN")
        guard let publicOrigin = URL(string: rawOrigin),
              publicOrigin.scheme == "https",
              publicOrigin.host(percentEncoded: false) != nil,
              publicOrigin.user == nil,
              publicOrigin.password == nil,
              publicOrigin.query == nil,
              publicOrigin.fragment == nil,
              publicOrigin.path.isEmpty || publicOrigin.path == "/"
        else {
            throw AppViewConfigurationError.invalidSourceArtifactPublicOrigin(rawOrigin)
        }
        return SourceArtifactS3Configuration(
            bucket: try required("OME_SOURCE_ARTIFACT_S3_BUCKET"),
            region: try required("OME_SOURCE_ARTIFACT_S3_REGION"),
            publicOrigin: publicOrigin,
            credentials: SourceArtifactAWSCredentials(
                accessKeyID: try required("AWS_ACCESS_KEY_ID"),
                secretAccessKey: try required("AWS_SECRET_ACCESS_KEY"),
                sessionToken: environment["AWS_SESSION_TOKEN"]
            )
        )
    }

    private static func brandedEventRouteClaims(
        environment: [String: String]
    ) throws -> [BrandedEventRouteClaim] {
        guard let path = environment["OME_BRANDED_EVENT_ROUTE_CONFIGURATION_PATH"] else {
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw AppViewConfigurationError.brandedEventRouteConfigurationUnreadable(path)
        }

        let file: BrandedEventRouteConfigurationFile
        do {
            file = try JSONDecoder().decode(BrandedEventRouteConfigurationFile.self, from: data)
        } catch {
            throw AppViewConfigurationError.brandedEventRouteConfigurationInvalid(path)
        }

        var routeKeys: Set<String> = []
        return try file.claims.map { configuredClaim in
            let host = configuredClaim.host.lowercased()
            guard isSafeDomainName(host) else {
                throw AppViewConfigurationError.invalidBrandedEventRouteHost(
                    configuredClaim.host
                )
            }
            guard isSafeRouteComponent(configuredClaim.eventClaim) else {
                throw AppViewConfigurationError.invalidBrandedEventRouteClaim(
                    configuredClaim.eventClaim
                )
            }
            guard let organizerID = OME.Organizer.ID(configuredClaim.organizerID) else {
                throw AppViewConfigurationError.invalidBrandedEventRouteOrganizerID(
                    configuredClaim.organizerID
                )
            }
            guard !configuredClaim.eventRKey.isEmpty else {
                throw AppViewConfigurationError.invalidBrandedEventRouteRKey(
                    configuredClaim.eventRKey
                )
            }
            guard routeKeys.insert("\(host)/\(configuredClaim.eventClaim)").inserted else {
                throw AppViewConfigurationError.duplicateBrandedEventRoute(
                    host: host,
                    eventClaim: configuredClaim.eventClaim
                )
            }

            return BrandedEventRouteClaim(
                host: host,
                eventClaim: configuredClaim.eventClaim,
                eventID: OME.Event.ID(
                    organizerID: organizerID,
                    eventID: OME.ID<OME.Event>(.init(configuredClaim.eventRKey))
                )
            )
        }
    }

    private static func notificationProviderConfiguration(
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
                isNonemptyConfigurationValue(application.projectID)
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
            fcmApplications[applicationID] = .init(projectID: application.projectID)
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

    private static func webhookSecretProtection(
        environment: [String: String]
    ) throws -> WebhookSecretProtection? {
        guard let path = environment["OME_WEBHOOK_SECRET_KEY_PATH"] else {
            guard environment["OME_WEBHOOK_SECRET_KEY_VERSION"] == nil else {
                throw AppViewConfigurationError.webhookSecretKeyMissing
            }
            return nil
        }
        let encodedKey: String
        do {
            encodedKey = try String(
                contentsOf: URL(fileURLWithPath: path),
                encoding: .utf8
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw AppViewConfigurationError.webhookSecretKeyUnreadable(path)
        }
        let rawKeyVersion = environment["OME_WEBHOOK_SECRET_KEY_VERSION"] ?? "1"
        guard let keyVersion = Int(rawKeyVersion), keyVersion > 0 else {
            throw AppViewConfigurationError.invalidWebhookSecretKeyVersion(rawKeyVersion)
        }
        return try WebhookSecretProtection(
            base64EncodedKey: encodedKey,
            keyVersion: keyVersion
        )
    }
}

public enum AppViewConfigurationError: Error, Equatable, Sendable {
    case apnsPrivateKeyUnreadable(String)
    case brandedEventRouteConfigurationInvalid(String)
    case brandedEventRouteConfigurationUnreadable(String)
    case duplicateBrandedEventRoute(host: String, eventClaim: String)
    case duplicateNotificationProviderApplicationID(
        provider: String,
        applicationID: Push.ApplicationID
    )
    case fcmProjectIDMismatch(configured: [String], credential: String)
    case fcmServiceAccountInvalid(String)
    case fcmServiceAccountUnreadable(String)
    case invalidBrandedEventRouteClaim(String)
    case invalidBrandedEventRouteHost(String)
    case invalidBrandedEventRouteOrganizerID(String)
    case invalidBrandedEventRouteRKey(String)
    case invalidNotificationDestinationKeyVersion(String)
    case invalidWebhookSecretKeyVersion(String)
    case notificationApplicationIDsMissing
    case notificationDestinationKeyMissing
    case notificationProviderApplicationMissing(Push.ApplicationID)
    case notificationProviderApplicationsMissing(String)
    case notificationProviderConfigurationEmpty(String)
    case notificationProviderConfigurationInvalid(String)
    case notificationProviderConfigurationUnreadable(String)
    case notificationProviderConfigurationValueMissing(String)
    case invalidTangledCanonicalSourceOrganizerID(String)
    case invalidTangledWebhookRepositoryOwnerDID(String)
    case invalidSourceArtifactPublicOrigin(String)
    case sourceArtifactConfigurationMissing
    case sourceArtifactConfigurationValueMissing(String)
    case tangledWebhookConfigurationInvalid(String)
    case tangledWebhookConfigurationUnreadable(String)
    case unsupportedNotificationAuthorization(String)
    case webhookSecretKeyMissing
    case webhookSecretKeyUnreadable(String)
}

private struct TangledWebhookConfigurationFile: Decodable {
    var watches: [Watch]

    struct Watch: Decodable {
        var id: String
        var hookID: Int64
        var repositoryOwnerDID: String
        var repositoryKey: String
        var ref: String
        var canonicalSource: CanonicalSource
        var artifactRepository: ArtifactRepository
    }

    struct CanonicalSource: Decodable {
        var organizerID: String
        var repositoryRecordKey: String
    }

    struct ArtifactRepository: Decodable {
        var owner: String
        var repository: String
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
    }
}

private struct BrandedEventRouteConfigurationFile: Decodable {
    var claims: [Claim]

    struct Claim: Decodable {
        var host: String
        var eventClaim: String
        var organizerID: String
        var eventRKey: String
    }
}

private func isSafeDomainName(_ value: String) -> Bool {
    !value.isEmpty && value.allSatisfy { character in
        character.isASCII
            && (character.isLetter || character.isNumber || character == "." || character == "-")
    }
}

private func isNonemptyConfigurationValue(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && trimmed == value
}

private func isSafeRouteComponent(_ value: String) -> Bool {
    !value.isEmpty && value.allSatisfy { character in
        character.isASCII
            && (
                character.isLetter
                    || character.isNumber
                    || character == "-"
                    || character == "."
                    || character == "_"
                    || character == "~"
            )
    }
}
