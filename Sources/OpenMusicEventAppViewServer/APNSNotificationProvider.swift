import ComposableNotifications
import ComposableNotificationsHTTP
import Dependencies
import Foundation

public extension AppViewConfiguration {
    /// Builds the host's provider adapters at startup, before the server accepts webhook deliveries.
    ///
    /// The signing key remains deployment-owned. This server module only reads the credential
    /// files named by its configuration and hands the provider-neutral client to notification
    /// dispatch. When no providers are configured, notification delivery remains disabled.
    func notificationProvider() async throws -> NotificationProviderClient? {
        guard let configuration = notificationProviders else {
            return nil
        }

        @Dependency(\.date.now) var now
        let apnsAuthorization: APNSProviderTokenAuthorization?
        if let apns = configuration.apns {
            let privateKeyPEM: String
            do {
                privateKeyPEM = try String(
                    contentsOf: apns.privateKeyURL,
                    encoding: .utf8
                )
            } catch {
                throw AppViewConfigurationError.apnsPrivateKeyUnreadable(
                    apns.privateKeyURL.path(percentEncoded: false)
                )
            }
            apnsAuthorization = try await APNSProviderTokenAuthorization(
                teamID: apns.teamID,
                keyID: apns.keyID,
                privateKeyPEM: privateKeyPEM,
                now: { now }
            )
        } else {
            apnsAuthorization = nil
        }

        let fcmAuthorization: FCMServiceAccountAuthorization?
        if let fcm = configuration.fcm {
            let credentialData: Data
            do {
                credentialData = try Data(contentsOf: fcm.serviceAccountURL)
            } catch {
                throw AppViewConfigurationError.fcmServiceAccountUnreadable(
                    fcm.serviceAccountURL.path(percentEncoded: false)
                )
            }
            let credentials: FCMServiceAccountCredentials
            do {
                credentials = try JSONDecoder().decode(
                    FCMServiceAccountCredentials.self,
                    from: credentialData
                )
            } catch {
                throw AppViewConfigurationError.fcmServiceAccountInvalid(
                    fcm.serviceAccountURL.path(percentEncoded: false)
                )
            }
            let configuredProjectIDs = Set(fcm.applications.values.map(\.projectID))
            guard configuredProjectIDs == [credentials.projectID] else {
                throw AppViewConfigurationError.fcmProjectIDMismatch(
                    configured: configuredProjectIDs.sorted(),
                    credential: credentials.projectID
                )
            }
            fcmAuthorization = try await FCMServiceAccountAuthorization(
                credentials: credentials,
                now: { now }
            )
        } else {
            fcmAuthorization = nil
        }

        return NotificationProviderClient.http(
            configuration: NotificationProviderHTTPConfiguration(
                apns: configuration.apns?.applications.mapValues {
                    .init(
                        environment: $0.environment.providerEnvironment,
                        topic: $0.topic
                    )
                } ?? [:],
                fcm: configuration.fcm?.applications.mapValues {
                    .init(projectID: $0.projectID)
                } ?? [:]
            ),
            authorization: NotificationProviderAuthorization(
                apnsBearerToken: { applicationID in
                    guard let apnsAuthorization else {
                        throw NotificationProviderHTTPError.missingAPNSConfiguration(
                            applicationID
                        )
                    }
                    return try await apnsAuthorization.bearerToken()
                },
                fcmAccessToken: { applicationID in
                    guard let fcmAuthorization else {
                        throw NotificationProviderHTTPError.missingFCMConfiguration(
                            applicationID
                        )
                    }
                    return try await fcmAuthorization.accessToken()
                }
            )
        )
    }
}

private extension AppViewNotificationProviderConfiguration.APNS.Application.Environment {
    var providerEnvironment: NotificationProviderHTTPConfiguration.APNS.Environment {
        switch self {
        case .development:
            .development
        case .production:
            .production
        }
    }
}
