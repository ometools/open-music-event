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

public struct AppViewAPNSNotificationProviderConfiguration: Equatable, Sendable {
    public enum Environment: String, Equatable, Sendable {
        case development
        case production
    }

    public init(
        applicationID: Push.ApplicationID,
        environment: Environment,
        topic: String,
        teamID: String,
        keyID: String,
        privateKeyURL: URL
    ) {
        self.applicationID = applicationID
        self.environment = environment
        self.topic = topic
        self.teamID = teamID
        self.keyID = keyID
        self.privateKeyURL = privateKeyURL
    }

    public var applicationID: Push.ApplicationID
    public var environment: Environment
    public var topic: String
    public var teamID: String
    public var keyID: String
    public var privateKeyURL: URL
}

public struct AppViewConfiguration: Sendable {
    public init(
        host: String = "127.0.0.1",
        port: Int = 8080,
        siteRoot: URL? = nil,
        wellKnownRoot: URL? = nil,
        brandedEventRouteClaims: [BrandedEventRouteClaim] = [],
        databaseURL: URL? = nil,
        ingestion: AppViewIngestionConfiguration? = nil,
        apnsNotificationProvider: AppViewAPNSNotificationProviderConfiguration? = nil,
        notificationDestinationProtection: NotificationDestinationProtection? = nil,
        notificationRegistration: AppViewNotificationRegistrationConfiguration? = nil,
        webhookSecretProtection: WebhookSecretProtection? = nil,
        tangledWebhook: TangledWebhookConfiguration? = nil
    ) {
        self.host = host
        self.port = port
        self.siteRoot = siteRoot ?? Bundle.module.resourceURL!.appendingPathComponent("Site")
        self.wellKnownRoot = wellKnownRoot ?? Bundle.module.resourceURL!.appendingPathComponent("WellKnown")
        self.brandedEventRouteClaims = brandedEventRouteClaims
        self.databaseURL = databaseURL
        self.ingestion = ingestion
        self.apnsNotificationProvider = apnsNotificationProvider
        self.notificationDestinationProtection = notificationDestinationProtection
        self.notificationRegistration = notificationRegistration
        self.webhookSecretProtection = webhookSecretProtection
        self.tangledWebhook = tangledWebhook
    }

    public var host: String
    public var port: Int
    public var siteRoot: URL
    public var wellKnownRoot: URL
    public var brandedEventRouteClaims: [BrandedEventRouteClaim]
    public var databaseURL: URL?
    public var ingestion: AppViewIngestionConfiguration?
    public var apnsNotificationProvider: AppViewAPNSNotificationProviderConfiguration?
    public var notificationDestinationProtection: NotificationDestinationProtection?
    public var notificationRegistration: AppViewNotificationRegistrationConfiguration?
    public var webhookSecretProtection: WebhookSecretProtection?
    public var tangledWebhook: TangledWebhookConfiguration?
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
        let apnsNotificationProvider = try apnsNotificationProviderConfiguration(
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
        let webhookSecretProtection = try webhookSecretProtection(environment: environment)
        let tangledWebhook = try tangledWebhookConfiguration(
            environment: environment
        )
        guard tangledWebhook == nil || webhookSecretProtection != nil else {
            throw AppViewConfigurationError.webhookSecretKeyMissing
        }
        let brandedEventRouteClaims = try brandedEventRouteClaims(environment: environment)
        return Self(
            host: environment["OME_APPVIEW_HOST"] ?? "127.0.0.1",
            port: environment["OME_APPVIEW_PORT"].flatMap(Int.init) ?? 8080,
            siteRoot: environment["OME_APPVIEW_SITE_ROOT"].map(URL.init(fileURLWithPath:)),
            wellKnownRoot: environment["OME_APPVIEW_WELL_KNOWN_ROOT"].map(URL.init(fileURLWithPath:)),
            brandedEventRouteClaims: brandedEventRouteClaims,
            databaseURL: databaseURL,
            ingestion: ingestion,
            apnsNotificationProvider: apnsNotificationProvider,
            notificationDestinationProtection: notificationDestinationProtection,
            notificationRegistration: notificationRegistration,
            webhookSecretProtection: webhookSecretProtection,
            tangledWebhook: tangledWebhook
        )
    }

    static func lambda(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
        Self(
            host: environment["OME_APPVIEW_HOST"] ?? "127.0.0.1",
            port: environment["OME_APPVIEW_PORT"].flatMap(Int.init) ?? 8080,
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
            guard let repositoryDID = DID(configuredWatch.repositoryDID) else {
                throw AppViewConfigurationError.invalidTangledWebhookRepositoryDID(
                    configuredWatch.repositoryDID
                )
            }
            let watchID = WebhookInboxDelivery.WatchID(rawValue: configuredWatch.id)
            return TangledWebhookWatch(
                id: watchID,
                hookID: configuredWatch.hookID,
                repositoryDID: repositoryDID,
                repositoryKey: ATProto.Record.Key(rawValue: configuredWatch.repositoryKey),
                ref: configuredWatch.ref,
                sourceID: .init(rawValue: configuredWatch.sourceID)
            )
        }
        return try TangledWebhookConfiguration(watches: watches)
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

    private static func apnsNotificationProviderConfiguration(
        environment: [String: String]
    ) throws -> AppViewAPNSNotificationProviderConfiguration? {
        let keys = [
            "OME_APNS_APPLICATION_ID",
            "OME_APNS_ENVIRONMENT",
            "OME_APNS_KEY_ID",
            "OME_APNS_PRIVATE_KEY_PATH",
            "OME_APNS_TEAM_ID",
            "OME_APNS_TOPIC",
        ]
        guard keys.contains(where: { environment[$0] != nil }) else {
            return nil
        }

        func required(_ key: String) throws -> String {
            guard let value = environment[key]?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !value.isEmpty else {
                throw AppViewConfigurationError.apnsConfigurationValueMissing(key)
            }
            return value
        }

        let applicationID = try required("OME_APNS_APPLICATION_ID")
        let rawEnvironment = try required("OME_APNS_ENVIRONMENT")
        guard let providerEnvironment = AppViewAPNSNotificationProviderConfiguration.Environment(
            rawValue: rawEnvironment
        ) else {
            throw AppViewConfigurationError.invalidAPNSEnvironment(rawEnvironment)
        }
        let topic = environment["OME_APNS_TOPIC"]?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return try AppViewAPNSNotificationProviderConfiguration(
            applicationID: Push.ApplicationID(rawValue: applicationID),
            environment: providerEnvironment,
            topic: topic.flatMap { $0.isEmpty ? nil : $0 } ?? applicationID,
            teamID: required("OME_APNS_TEAM_ID"),
            keyID: required("OME_APNS_KEY_ID"),
            privateKeyURL: URL(
                fileURLWithPath: required("OME_APNS_PRIVATE_KEY_PATH")
            )
        )
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
    case apnsConfigurationValueMissing(String)
    case apnsPrivateKeyUnreadable(String)
    case brandedEventRouteConfigurationInvalid(String)
    case brandedEventRouteConfigurationUnreadable(String)
    case duplicateBrandedEventRoute(host: String, eventClaim: String)
    case invalidAPNSEnvironment(String)
    case invalidBrandedEventRouteClaim(String)
    case invalidBrandedEventRouteHost(String)
    case invalidBrandedEventRouteOrganizerID(String)
    case invalidBrandedEventRouteRKey(String)
    case invalidNotificationDestinationKeyVersion(String)
    case invalidWebhookSecretKeyVersion(String)
    case notificationApplicationIDsMissing
    case notificationDestinationKeyMissing
    case invalidTangledWebhookRepositoryDID(String)
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
        var repositoryDID: String
        var repositoryKey: String
        var ref: String
        var sourceID: String
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
