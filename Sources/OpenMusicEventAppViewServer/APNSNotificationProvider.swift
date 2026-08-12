import ComposableNotifications
import ComposableNotificationsHTTP
import Dependencies
import Foundation

public extension AppViewConfiguration {
    /// Builds the host's APNs adapter at startup, before the server accepts webhook deliveries.
    ///
    /// The signing key remains deployment-owned. This server module only reads the credential
    /// file named by its configuration and hands the provider-neutral client to notification
    /// dispatch. When APNs is not configured, notification delivery remains disabled.
    func notificationProvider() async throws -> NotificationProviderClient? {
        guard let configuration = apnsNotificationProvider else {
            return nil
        }

        let privateKeyPEM: String
        do {
            privateKeyPEM = try String(
                contentsOf: configuration.privateKeyURL,
                encoding: .utf8
            )
        } catch {
            throw AppViewConfigurationError.apnsPrivateKeyUnreadable(
                configuration.privateKeyURL.path(percentEncoded: false)
            )
        }

        @Dependency(\.date.now) var now
        let providerTokens = try await APNSProviderTokenAuthorization(
            teamID: configuration.teamID,
            keyID: configuration.keyID,
            privateKeyPEM: privateKeyPEM,
            now: { now }
        )
        return NotificationProviderClient.http(
            configuration: NotificationProviderHTTPConfiguration(
                apns: [
                    configuration.applicationID: .init(
                        environment: configuration.environment.providerEnvironment,
                        topic: configuration.topic
                    )
                ]
            ),
            authorization: .apns(providerTokens: providerTokens)
        )
    }
}

private extension AppViewAPNSNotificationProviderConfiguration.Environment {
    var providerEnvironment: NotificationProviderHTTPConfiguration.APNS.Environment {
        switch self {
        case .development:
            .development
        case .production:
            .production
        }
    }
}
