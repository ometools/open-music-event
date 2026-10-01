import ComposableNotifications

public enum AppViewConfigurationError: Error, Equatable, Sendable {
    case invalidOAuthClient(String)
    case brandedEventRouteConfigurationInvalid(String)
    case brandedEventRouteConfigurationUnreadable(String)
    case duplicateBrandedEventRoute(host: String, eventClaim: String)
    case invalidBrandedEventRouteClaim(String)
    case invalidBrandedEventRouteHost(String)
    case invalidBrandedEventRouteEventURI(String)

    case apnsPrivateKeyUnreadable(String)
    case duplicateNotificationProviderApplicationID(
        provider: String,
        applicationID: Push.ApplicationID
    )
    case fcmProjectIDMismatch(configured: [String], credential: String)
    case fcmServiceAccountInvalid(String)
    case fcmServiceAccountUnreadable(String)
    case invalidNotificationDestinationKeyVersion(String)
    case notificationApplicationIDsMissing
    case notificationDestinationKeyMissing
    case notificationProviderApplicationMissing(Push.ApplicationID)
    case notificationProviderApplicationsMissing(String)
    case notificationProviderConfigurationEmpty(String)
    case notificationProviderConfigurationInvalid(String)
    case notificationProviderConfigurationUnreadable(String)
    case notificationProviderConfigurationValueMissing(String)
    case unsupportedNotificationAuthorization(String)

    case invalidTangledCanonicalSourceOrganizerID(String)
    case invalidTangledWebhookRepositoryOwnerDID(String)
    case invalidTangledWebhookRepositoryDID(String)
    case invalidTangledWebhookWatchID(String)
    case tangledWebhookConfigurationInvalid(String)
    case tangledWebhookConfigurationUnreadable(String)

    case invalidSourceArtifactPublicOrigin(String)
    case sourceArtifactConfigurationMissing
    case sourceArtifactConfigurationValueMissing(String)

    case invalidWebhookSecretKeyVersion(String)
    case webhookSecretKeyMissing
    case webhookSecretKeyUnreadable(String)
}
