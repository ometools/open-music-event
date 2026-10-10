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
        let ingestions: [AppViewIngestionConfiguration]
        if let value = environment["OME_APPVIEW_HYDRANT_CONFIGURATIONS"] {
            do {
                ingestions = try JSONDecoder().decode(
                    [AppViewIngestionConfiguration].self,
                    from: Data(value.utf8)
                )
            } catch {
                throw AppViewConfigurationError.invalidIngestionConfigurations(value)
            }
        } else {
            ingestions = environment["OME_APPVIEW_HYDRANT_ENDPOINT"].map {
                [AppViewIngestionConfiguration(
                    endpoint: $0,
                    subscriptionID: environment["OME_APPVIEW_HYDRANT_SUBSCRIPTION_ID"]
                        ?? "hydrant|community.lexicon.calendar.event"
                )]
            } ?? []
        }
        guard Set(ingestions.map(\.subscriptionID)).count == ingestions.count else {
            throw AppViewConfigurationError.invalidIngestionConfigurations(
                "Subscription IDs must be unique."
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
        let geocodingOverrides: [String: CalendarEventGeocodingClient.Coordinates]
        if let value = environment["OME_APPVIEW_GEOCODING_OVERRIDES"] {
            do {
                geocodingOverrides = try JSONDecoder().decode(
                    [String: CalendarEventGeocodingClient.Coordinates].self,
                    from: Data(value.utf8)
                )
            } catch {
                throw AppViewConfigurationError.invalidGeocodingOverrides(value)
            }
            guard geocodingOverrides.values.allSatisfy({ coordinates in
                coordinates.latitude.isFinite
                    && coordinates.longitude.isFinite
                    && (-90...90).contains(coordinates.latitude)
                    && (-180...180).contains(coordinates.longitude)
            }) else {
                throw AppViewConfigurationError.invalidGeocodingOverrides(value)
            }
        } else {
            geocodingOverrides = [:]
        }

        var configuration = Self(
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
            ingestions: ingestions,
            geoapifyAPIKey: environment["GEOAPIFY_API_KEY"].flatMap {
                let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            },
            geocodingOverrides: geocodingOverrides,
            notificationProviders: notificationProviders,
            notificationDestinationProtection: notificationDestinationProtection,
            notificationRegistration: notificationRegistration,
            webhookSecretProtection: webhookSecretProtection,
            tangledWebhook: tangledWebhook,
            sourceArtifacts: sourceArtifacts
        )
        if let bindings = environment["OME_WEB_PDS_HOSTS"] {
            let hosts = try JSONDecoder().decode([String: String].self, from: Data(bindings.utf8))
            for (did, host) in hosts {
                guard did.hasPrefix("did:"), let url = URLComponents(string: "https://" + host),
                      url.host != nil, url.user == nil, url.password == nil, url.path.isEmpty,
                      url.query == nil, url.fragment == nil else { throw WebPDSConfigurationError.invalidBinding }
                configuration.webPDSHosts[did] = ATProto.PDSHost(host)
            }
        }
        return configuration
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

enum WebPDSConfigurationError: Error { case invalidBinding }
