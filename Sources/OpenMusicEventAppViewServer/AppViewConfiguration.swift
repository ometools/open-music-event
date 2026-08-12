import ATProto
import ComposableNotifications
import Foundation
import Hummingbird
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

public struct AppViewConfiguration: Sendable {
    public init(
        host: String = "127.0.0.1",
        port: Int = 8080,
        siteRoot: URL? = nil,
        wellKnownRoot: URL? = nil,
        databaseURL: URL? = nil,
        ingestion: AppViewIngestionConfiguration? = nil,
        notificationDestinationProtection: NotificationDestinationProtection? = nil,
        notificationRegistration: AppViewNotificationRegistrationConfiguration? = nil,
        webhookSecretProtection: WebhookSecretProtection? = nil,
        tangledWebhook: TangledWebhookConfiguration? = nil
    ) {
        self.host = host
        self.port = port
        self.siteRoot = siteRoot ?? Bundle.module.resourceURL!.appendingPathComponent("Site")
        self.wellKnownRoot = wellKnownRoot ?? Bundle.module.resourceURL!.appendingPathComponent("WellKnown")
        self.databaseURL = databaseURL
        self.ingestion = ingestion
        self.notificationDestinationProtection = notificationDestinationProtection
        self.notificationRegistration = notificationRegistration
        self.webhookSecretProtection = webhookSecretProtection
        self.tangledWebhook = tangledWebhook
    }

    public var host: String
    public var port: Int
    public var siteRoot: URL
    public var wellKnownRoot: URL
    public var databaseURL: URL?
    public var ingestion: AppViewIngestionConfiguration?
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
        return Self(
            host: environment["OME_APPVIEW_HOST"] ?? "127.0.0.1",
            port: environment["OME_APPVIEW_PORT"].flatMap(Int.init) ?? 8080,
            siteRoot: environment["OME_APPVIEW_SITE_ROOT"].map(URL.init(fileURLWithPath:)),
            wellKnownRoot: environment["OME_APPVIEW_WELL_KNOWN_ROOT"].map(URL.init(fileURLWithPath:)),
            databaseURL: databaseURL,
            ingestion: ingestion,
            notificationDestinationProtection: notificationDestinationProtection,
            notificationRegistration: notificationRegistration,
            webhookSecretProtection: webhookSecretProtection,
            tangledWebhook: tangledWebhook
        )
    }

    static func lambda(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        Self(
            host: environment["OME_APPVIEW_HOST"] ?? "127.0.0.1",
            port: environment["OME_APPVIEW_PORT"].flatMap(Int.init) ?? 8080,
            siteRoot: lambdaSiteRoot(environment: environment),
            wellKnownRoot: lambdaWellKnownRoot(environment: environment)
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
