import ATProtoOAuth
import Dependencies
import Foundation
import OpenMusicEventSourceClone
import Sharing
import TCATProtoAuthentication
import XRPCClient

private let openMusicEventOAuthSession = Shared<OAuth.Session?>(
    wrappedValue: nil,
    KeychainSharedKey(item: OpenMusicEventOAuth.sessionKeychainItem)
)

private let openMusicEventOAuthSessionStore = Shared(
    wrappedValue: OAuth.SessionStore(),
    KeychainSharedKey(item: OpenMusicEventOAuth.sessionStoreKeychainItem)
)

private let openMusicEventAuthFailureMessage = Shared<ErrorMessage?>(value: nil)

public enum OpenMusicEventOAuth {
    static let sessionKeychainItem = KeychainStorageItem(
        service: "fm.woody.openMusicEvent",
        account: "oauth.session"
    )
    static let sessionStoreKeychainItem = KeychainStorageItem(
        service: "fm.woody.openMusicEvent",
        account: "oauth.sessionStore"
    )

    public static let clientMetadataURL = URL(
        string: "https://openmusicevent.app/.well-known/oauth-client-metadata.json"
    )!

    public static let redirectURL = URL(string: "app.openmusicevent:/oauth/callback")!

    public static let tangledPullCreatePermission = OAuth.Permission(
        "repo:sh.tangled.repo.pull?action=create"
    )

    public static let tangledPublicKeyCreatePermission =
        TangledOAuthRequirements.publicKeyCreatePermission

    public static let patchBlobPermission = OAuth.Permission("blob:text/x-patch")

    public static let tangledPublicKeyAuthRequirement =
        TangledOAuthRequirements.publicKeyAuthRequirement

    public static let proposalAuthRequirement = OAuth.AuthRequirement(
        permissions: [
            tangledPullCreatePermission,
            patchBlobPermission,
        ]
    )

    public static let baseAuthRequirement = OAuth.AuthRequirement(
        permissions: [.atproto]
    )

    public static let appConfiguration = OAuth.AppConfiguration(
        appID: OAuth.App.ID(clientMetadataURL),
        redirectURI: OAuth.App.RedirectURI(redirectURL)
    )

    public static let appManifest = OAuth.AppManifest(
        appID: appConfiguration.appID,
        appName: "Open Music Event",
        redirectURIs: [appConfiguration.redirectURI],
        basePermissions: OAuth.GrantedPermissions([.atproto]),
        registeredRequirements: [
            tangledPublicKeyAuthRequirement,
            proposalAuthRequirement,
        ]
    )

    public static var authFailureMessage: Shared<ErrorMessage?> {
        openMusicEventAuthFailureMessage
    }

    public static var session: Shared<OAuth.Session?> {
        openMusicEventOAuthSession
    }

    public static var sessionStore: Shared<OAuth.SessionStore> {
        openMusicEventOAuthSessionStore
    }

    public static func prepareDependencies(_ dependencies: inout DependencyValues) {
        let authorizationRequests = dependencies.openMusicEventAuthorizationRequests
        dependencies.oauthAppConfiguration = appConfiguration
        dependencies.oauthAppManifest = appManifest
        dependencies.oauthAuthorizationBroker = authorizationRequests.broker()
        dependencies.oauthBrowserStrategy = .webAuthenticationSession
        dependencies.oauthScopes = appManifest.basePermissions.permissions
            .sorted { $0.rawValue < $1.rawValue }
            .map { OAuth.Scope(rawValue: $0.rawValue) }
        dependencies.xrpcAuthorizationGate = .defaultSessionAuthorization
    }

    public static func isCallbackURL(_ url: URL) -> Bool {
        let redirectURL = appConfiguration.redirectURI.rawValue
        return url.scheme == redirectURL.scheme
            && url.host == redirectURL.host
            && url.path == redirectURL.path
    }

    public static func metadataData(
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> Data {
        try appManifest.metadataData(encoder: encoder)
    }

    public static func bundledMetadataData() throws -> Data {
        guard let url = Bundle.module.url(
            forResource: "oauth-client-metadata",
            withExtension: "json"
        ) else {
            throw MissingBundledMetadata()
        }
        return try Data(contentsOf: url)
    }

    public static func resetStoredSession() {
        session.withLock { $0 = nil }
        sessionStore.withLock { $0 = OAuth.SessionStore() }
        authFailureMessage.withLock { $0 = nil }
    }

    public static func enforceStoredAuthenticationFreshness() async throws {
        try await session.load()
        try await sessionStore.load()
    }
}

public struct MissingBundledMetadata: Error, Equatable, Sendable {
    public init() {}
}
