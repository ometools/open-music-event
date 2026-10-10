import OpenMusicEventOAuthClient
import ATProto
import Foundation
import OpenMusicEventRouting
import Tagged

public struct AppViewConfiguration: Sendable {
    public init(
        host: String = "127.0.0.1",
        port: Int = 8080,
        publicAppViewHost: ATProto.PDSHost = "openmusicevent.app",
        siteRoot: URL? = nil,
        oauthClient: OpenMusicEventOAuthClient = .production,
        wellKnownRoot: URL? = nil,
        brandedEventRouteClaims: [BrandedEventRouteClaim] = [],
        databaseURL: URL? = nil,
        ingestion: AppViewIngestionConfiguration? = nil,
        ingestions: [AppViewIngestionConfiguration] = [],
        geoapifyAPIKey: String? = nil,
        geocodingOverrides: [String: CalendarEventGeocodingClient.Coordinates] = [:],
        notificationProviders: AppViewNotificationProviderConfiguration? = nil,
        notificationDestinationProtection: NotificationDestinationProtection? = nil,
        notificationRegistration: AppViewNotificationRegistrationConfiguration? = nil,
        webhookSecretProtection: WebhookSecretProtection? = nil,
        tangledWebhook: TangledWebhookConfiguration? = nil,
        sourceArtifacts: SourceArtifactS3Configuration? = nil
    ) {
        self.oauthClient = oauthClient
        self.host = host
        self.port = port
        self.publicAppViewHost = publicAppViewHost
        self.siteRoot = siteRoot ?? Bundle.module.resourceURL!.appendingPathComponent("Site")
        self.wellKnownRoot = wellKnownRoot ?? Bundle.module.resourceURL!.appendingPathComponent("WellKnown")
        self.brandedEventRouteClaims = brandedEventRouteClaims
        self.databaseURL = databaseURL
        self.ingestions = ingestions.isEmpty ? ingestion.map { [$0] } ?? [] : ingestions
        self.geoapifyAPIKey = geoapifyAPIKey
        self.geocodingOverrides = geocodingOverrides
        self.notificationProviders = notificationProviders
        self.notificationDestinationProtection = notificationDestinationProtection
        self.notificationRegistration = notificationRegistration
        self.webhookSecretProtection = webhookSecretProtection
        self.tangledWebhook = tangledWebhook
        self.sourceArtifacts = sourceArtifacts
    }

    public var oauthClient: OpenMusicEventOAuthClient
    public var host: String
    public var port: Int
    /// Explicit repository host bindings for private Atmosphere deployments.
    public var webPDSHosts: [String: ATProto.PDSHost] = [:]

    public var publicAppViewHost: ATProto.PDSHost
    public var siteRoot: URL
    public var wellKnownRoot: URL
    public var brandedEventRouteClaims: [BrandedEventRouteClaim]
    public var databaseURL: URL?
    public var ingestion: AppViewIngestionConfiguration? {
        get { ingestions.first }
        set { ingestions = newValue.map { [$0] } ?? [] }
    }
    public var ingestions: [AppViewIngestionConfiguration]
    public var geoapifyAPIKey: String?
    public var geocodingOverrides: [String: CalendarEventGeocodingClient.Coordinates]
    public var notificationProviders: AppViewNotificationProviderConfiguration?
    public var notificationDestinationProtection: NotificationDestinationProtection?
    public var notificationRegistration: AppViewNotificationRegistrationConfiguration?
    public var webhookSecretProtection: WebhookSecretProtection?
    public var tangledWebhook: TangledWebhookConfiguration?
    public var sourceArtifacts: SourceArtifactS3Configuration?
}
