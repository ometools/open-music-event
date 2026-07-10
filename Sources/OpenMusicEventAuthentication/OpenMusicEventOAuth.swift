import ATProto
import ATProtoOAuth
import Dependencies
import Foundation
import OpenMusicEventSourceClone
import Sharing
import TCATProtoAuthentication
import WebMetadataClient
import XRPCClient

public struct OpenMusicEventStoredAuthenticationClient: Sendable {
    public var enforceFreshness: @Sendable () async throws -> Void

    public init(
        enforceFreshness: @escaping @Sendable () async throws -> Void
    ) {
        self.enforceFreshness = enforceFreshness
    }
}

private enum OpenMusicEventStoredAuthenticationClientKey: DependencyKey {
    static var liveValue: OpenMusicEventStoredAuthenticationClient {
        OpenMusicEventStoredAuthenticationClient {
            try await OpenMusicEventOAuth.enforceStoredAuthenticationFreshness()
        }
    }

    static var testValue: OpenMusicEventStoredAuthenticationClient {
        OpenMusicEventStoredAuthenticationClient {}
    }
}

public extension DependencyValues {
    var openMusicEventStoredAuthentication: OpenMusicEventStoredAuthenticationClient {
        get { self[OpenMusicEventStoredAuthenticationClientKey.self] }
        set { self[OpenMusicEventStoredAuthenticationClientKey.self] = newValue }
    }
}

private let openMusicEventOAuthSessionStore = Shared(
    wrappedValue: OAuth.SessionStore(),
    KeychainSharedKey(item: OpenMusicEventOAuth.sessionStoreKeychainItem)
)

private let openMusicEventSelectedOAuthSessionID = Shared<Atmosphere.Account.ID?>(
    .appStorage("openMusicEventSelectedOAuthSessionID")
)

private let openMusicEventAuthFailureMessage = Shared<ErrorMessage?>(value: nil)

public enum OpenMusicEventOAuth {
    static let sessionStoreKeychainItem = KeychainStorageItem(
        service: "fm.woody.openMusicEvent",
        account: "oauth.sessionStore"
    )

    public static let clientMetadataURL = URL(
        string: "https://openmusicevent.app/.well-known/oauth-client-metadata.json"
    )!

    public static let redirectURL = URL(string: "app.openmusicevent:/oauth/callback")!

    public static let tangledPullPermission =
        TangledOAuthRequirements.pullPermission

    public static let tangledPullCreatePermission =
        TangledOAuthRequirements.pullCreatePermission

    public static let tangledPullUpdatePermission =
        TangledOAuthRequirements.pullUpdatePermission

    public static let tangledPullDeletePermission =
        TangledOAuthRequirements.pullDeletePermission

    public static let tangledPullStatusPermission =
        TangledOAuthRequirements.pullStatusPermission

    public static let tangledPullStatusCreatePermission =
        TangledOAuthRequirements.pullStatusCreatePermission

    public static let tangledPullStatusUpdatePermission =
        TangledOAuthRequirements.pullStatusUpdatePermission

    public static let tangledPullStatusDeletePermission =
        TangledOAuthRequirements.pullStatusDeletePermission

    public static let tangledPullMergePermission =
        TangledOAuthRequirements.pullMergePermission

    public static let tangledRepositoryRecordCreatePermission =
        TangledOAuthRequirements.repositoryRecordCreatePermission

    public static let tangledRepositoryRecordUpdatePermission =
        TangledOAuthRequirements.repositoryRecordUpdatePermission

    public static let tangledRepositoryRecordDeletePermission =
        TangledOAuthRequirements.repositoryRecordDeletePermission

    public static let tangledRepositoryCreatePermission =
        TangledOAuthRequirements.repositoryCreatePermission

    public static let tangledRepositorySetContributorsPermission =
        TangledOAuthRequirements.repositorySetContributorsPermission

    public static let tangledPublicKeyCreatePermission =
        TangledOAuthRequirements.publicKeyCreatePermission

    public static let patchBlobPermission =
        TangledOAuthRequirements.patchBlobPermission

    public static let legacyPatchBlobPermission =
        TangledOAuthRequirements.legacyPatchBlobPermission

    public static let tangledPublicKeyAuthRequirement =
        TangledOAuthRequirements.publicKeyAuthRequirement

    public static let legacyPatchBlobAuthRequirement =
        TangledOAuthRequirements.legacyPatchBlobAuthRequirement

    public static let proposalAuthRequirement =
        TangledOAuthRequirements.proposalAuthRequirement

    public static let tangledPullDeleteAuthRequirement =
        TangledOAuthRequirements.pullDeleteAuthRequirement

    public static let tangledPullMergeAuthRequirement =
        TangledOAuthRequirements.pullMergeAuthRequirement

    public static let tangledRepositoryCreateAuthRequirement =
        TangledOAuthRequirements.repositoryCreateAuthRequirement

    public static let tangledRepositorySetContributorsAuthRequirement =
        TangledOAuthRequirements.repositorySetContributorsAuthRequirement

    public static let tangledRepositoryManagementAuthRequirement =
        TangledOAuthRequirements.repositoryManagementAuthRequirement

    public static let tangledPullRequestSurfaceAuthRequirement =
        TangledOAuthRequirements.pullRequestSurfaceAuthRequirement

    public static let tangledPullStatusAuthRequirement =
        TangledOAuthRequirements.pullStatusAuthRequirement

    public static let tangledWorkspaceManagementAuthRequirement =
        OAuth.AuthRequirement(
            permissions: tangledPublicKeyAuthRequirement.permissions
                .union(tangledPullRequestSurfaceAuthRequirement.permissions)
        )

    public static let baseAuthRequirement = OAuth.AuthRequirement(
        permissions: [.atproto]
    )

    public static var signUpServerConfiguration: OAuthSignUpServerConfiguration {
        @Dependency(\.webMetadataClient) var webMetadataClient

        return OAuthSignUpServerConfiguration(
            defaultServerHost: "bsky.social",
            options: [
                OAuthSignUpServerOption(
                    id: "ome",
                    title: "Open Music Event",
                    subtitle: "ome.social",
                    description: "Open Music Event's own hosted account option.",
                    imageURL: webMetadataClient.googleS2FaviconURL("openmusicevent.app", 128),
                    metadataSource: "community-lexicon-enrichment",
                    availability: .comingSoon
                ),
                OAuthSignUpServerOption(
                    id: "bsky",
                    title: "BlueSky",
                    subtitle: "bsky.social",
                    description: "The first, and largest hosted AT Protocol entryway, with bsky.social handles.",
                    imageURL: webMetadataClient.googleS2FaviconURL("bsky.social", 128),
                    metadataSource: "community-lexicon-enrichment",
                    availability: .available(serverHost: "bsky.social")
                ),
                OAuthSignUpServerOption(
                    id: "eurosky",
                    title: "Eurosky",
                    subtitle: "eurosky.social",
                    description: "A Europe-focused AT Protocol community server using eurosky.social accounts.",
                    imageURL: webMetadataClient.googleS2FaviconURL("eurosky.social", 128),
                    metadataSource: "community-lexicon-enrichment",
                    availability: .available(serverHost: "eurosky.social")
                ),

            ],
            allowsCustomServerHost: true
        )
    }

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
            tangledPullRequestSurfaceAuthRequirement,
            tangledPullMergeAuthRequirement,
            tangledRepositoryManagementAuthRequirement,
            legacyPatchBlobAuthRequirement,
        ]
    )

    public static let storage = OAuthSessionStorage(
        sessionStore: openMusicEventOAuthSessionStore,
        authFailureMessage: openMusicEventAuthFailureMessage,
        selectedSessionID: openMusicEventSelectedOAuthSessionID
    )

    public static var authFailureMessage: Shared<ErrorMessage?> {
        storage.authFailureMessage
    }

    public static var session: Shared<OAuth.Session?> {
        storage.session
    }

    public static var sessionStore: Shared<OAuth.SessionStore> {
        storage.sessionStore
    }

    public static var selectedSessionID: Shared<Atmosphere.Account.ID?> {
        openMusicEventSelectedOAuthSessionID
    }

    public static func prepareDependencies(_ dependencies: inout DependencyValues) {
        let authorizationRequests = dependencies.openMusicEventAuthorizationRequests
            .openMusicEventDefaultingSignUpServerConfiguration(
                dependencies.openMusicEventSignUpServerConfiguration
        )
        let sessionStore = OpenMusicEventOAuth.sessionStore
        let selectedSessionID = OpenMusicEventOAuth.selectedSessionID
        let selectedSession = OpenMusicEventOAuth.session
        let getSelectedOAuthSessionID: @Sendable () -> Atmosphere.Account.ID? = {
            selectedSessionID.wrappedValue
        }
        syncOpenMusicEventSelectedSessionID(selectedSessionID, into: sessionStore)
        dependencies.openMusicEventAuthorizationRequests = authorizationRequests
        dependencies.oauthAppConfiguration = appConfiguration
        dependencies.oauthAppManifest = appManifest
        dependencies.getSelectedOAuthSessionID = getSelectedOAuthSessionID
        dependencies.oauthAuthorizationBroker = authorizationRequests
            .openMusicEventAutoStartingAuthorizationUpgrades(
                session: { selectedSession.wrappedValue },
                sessionStore: { sessionStore.wrappedValue },
                appManifest: appManifest
            )
            .broker()
        dependencies.oauthBrowserStrategy = .webAuthenticationSession
        dependencies.getDefaultSession = {
            selectedSession.wrappedValue ?? .placeholder
        }
        dependencies.getOptionalDefaultSession = {
            selectedSession.wrappedValue
        }
        dependencies.oauthScopes = appManifest.basePermissions.permissions
            .sorted { $0.rawValue < $1.rawValue }
            .map { OAuth.Scope(rawValue: $0.rawValue) }
        dependencies.errorInterceptors.append(
            .tokenRefresh(
                session: selectedSession,
                authFailureMessage: authFailureMessage
            )
        )
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
        storage.reset()
        selectedSessionID.withLock { $0 = nil }
    }

    public static func enforceStoredAuthenticationFreshness() async throws {
        try await storage.enforceFreshness()
    }
}

public struct MissingBundledMetadata: Error, Equatable, Sendable {
    public init() {}
}
