import ATProto
import ATProtoOAuth
import Dependencies
import Foundation
import HTTPClient
import OpenMusicEventSourceClone
#if os(Android)
import SkipSharing
#else
import Sharing
#endif
import TCATProtoAuthentication
import WebMetadataClient
import XRPCClient
#if canImport(OSLog)
import OSLog
#endif

public struct OpenMusicEventStoredAuthenticationClient: Sendable {
    public var enforceFreshness: @Sendable () async throws -> Void

    public init(
        enforceFreshness: @escaping @Sendable () async throws -> Void
    ) {
        self.enforceFreshness = enforceFreshness
    }
}

private enum OpenMusicEventAutomaticStoredAuthenticationRefreshKey: DependencyKey {
    static var liveValue: Bool { true }
    static var testValue: Bool { true }
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
    var openMusicEventAutomaticallyRefreshesStoredAuthentication: Bool {
        get { self[OpenMusicEventAutomaticStoredAuthenticationRefreshKey.self] }
        set { self[OpenMusicEventAutomaticStoredAuthenticationRefreshKey.self] = newValue }
    }

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
    wrappedValue: nil,
    KeychainSharedKey(item: OpenMusicEventOAuth.selectedSessionIDKeychainItem)
)

#if os(Linux)
private let openMusicEventRecentlyUsedAccountIDs = Shared<[Atmosphere.Account.ID]>(value: [])
#else
private let openMusicEventRecentlyUsedAccountIDs = Shared<[Atmosphere.Account.ID]>(
    .openMusicEventRecentlyUsedAccountIDs
)
#endif

private let openMusicEventAuthFailureMessage = Shared<ErrorMessage?>(value: nil)

#if !os(Linux)
private extension SharedKey where Self == AppStorageKey<[Atmosphere.Account.ID]>.Default {
    static var openMusicEventRecentlyUsedAccountIDs: Self {
        Self[.appStorage("openMusicEventRecentlyUsedAccountIDs"), default: []]
    }
}
#endif

public enum OpenMusicEventOAuth {
    public static let sourceRecordCreatePermission =
        OAuth.Permission("repo:app.openmusicevent.source?action=create")

    public static let sourceRecordUpdatePermission =
        OAuth.Permission("repo:app.openmusicevent.source?action=update")

    public static let sourceRecordAuthRequirement = OAuth.AuthRequirement(
        permissions: [
            sourceRecordCreatePermission,
            sourceRecordUpdatePermission,
        ]
    )

    static let sessionStoreKeychainItem = KeychainStorageItem(
        service: "fm.woody.openMusicEvent",
        account: "oauth.sessionStore"
    )

    static let selectedSessionIDKeychainItem = KeychainStorageItem(
        service: "fm.woody.openMusicEvent",
        account: "oauth.selectedSessionID"
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

    public static let tangledPullRequestWorkflowAuthRequirement =
        TangledOAuthRequirements.pullRequestWorkflowAuthRequirement

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
        @Dependency(\DependencyValues.webMetadataClient) var webMetadataClient: WebMetadataClient

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
                    description: "The first and largest hosted account provider, with bsky.social handles.",
                    imageURL: webMetadataClient.googleS2FaviconURL("bsky.social", 128),
                    metadataSource: "community-lexicon-enrichment",
                    availability: .available(serverHost: "bsky.social")
                ),
                OAuthSignUpServerOption(
                    id: "eurosky",
                    title: "Eurosky",
                    subtitle: "eurosky.social",
                    description: "A Europe-focused community account provider using eurosky.social handles.",
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
            sourceRecordAuthRequirement,
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

    public static var recentlyUsedAccountIDs: Shared<[Atmosphere.Account.ID]> {
        openMusicEventRecentlyUsedAccountIDs
    }

    public static func prepareDependencies(_ dependencies: inout DependencyValues) {
        let authorizationRequests = dependencies.openMusicEventAuthorizationRequests
            .openMusicEventDefaultingSignUpServerConfiguration(
                dependencies.openMusicEventSignUpServerConfiguration
        )
        let sessionStore = OpenMusicEventOAuth.sessionStore
        let selectedSessionID = OpenMusicEventOAuth.selectedSessionID
        let selectedSession = OpenMusicEventSelectedOAuthSessionClient.live(
            sessionStore: sessionStore,
            selectedSessionID: selectedSessionID
        )
        let getSelectedOAuthSessionID: @Sendable () -> Atmosphere.Account.ID? = {
            selectedSessionID.wrappedValue
        }
        dependencies.openMusicEventAuthorizationRequests = authorizationRequests
        dependencies.oauthAppConfiguration = appConfiguration
        dependencies.oauthAppManifest = appManifest
        dependencies.getSelectedOAuthSessionID = getSelectedOAuthSessionID
        dependencies.selectedOAuthSession = selectedSession
        dependencies.oauthBrowserStrategy = .webAuthenticationSession
        dependencies.getDefaultSession = {
            selectedSession.current() ?? .placeholder
        }
        dependencies.getOptionalDefaultSession = {
            selectedSession.current()
        }
        dependencies.oauthScopes = appManifest.basePermissions.permissions
            .sorted { $0.rawValue < $1.rawValue }
            .map { OAuth.Scope(rawValue: $0.rawValue) }
        OpenMusicEventOAuthNetworkDiagnostics.install(into: &dependencies)
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

    public static func resetStoredSession() {
        storage.reset()
        selectedSessionID.withLock { $0 = nil }
    }

    public static func enforceStoredAuthenticationFreshness() async throws {
        try await storage.enforceFreshness()
        try await selectedSessionID.load()
        if selectedSessionID.withLock({ $0 == nil }),
           let storedSelectedAccountID = sessionStore.selectedAccountID.withLock({ $0 }) {
            selectedSessionID.withLock {
                $0 = storedSelectedAccountID
            }
            try await selectedSessionID.save()
        }
        syncOpenMusicEventSelectedSessionID(selectedSessionID, into: sessionStore)
    }
}

enum OpenMusicEventOAuthNetworkDiagnostics {
    #if canImport(OSLog)
    private static let logger = Logger(subsystem: "Networking", category: "DPoP")
    #endif

    static func install(into dependencies: inout DependencyValues) {
        dependencies.responseInterceptors.append(
            ResponseInterceptor { request, response, responseData in
                let headers = response.headerFields.map {
                    (name: "\($0.name)", value: $0.value)
                }
                guard let message = responseMessage(
                    method: "\(request.method)",
                    url: request.url?.absoluteString ?? "",
                    status: "\(response.status)",
                    isError: response.status.kind != .successful,
                    headers: headers,
                    responseData: responseData
                ) else { return }

                log(message)
            }
        )
    }

    static func responseMessage(
        method: String,
        url: String,
        status: String,
        isError: Bool,
        headers: [(name: String, value: String)],
        responseData: Data
    ) -> String? {
        let errorCode = responseErrorCode(responseData)
        let nonceHeader = headers.first {
            $0.name.caseInsensitiveCompare("DPoP-Nonce") == .orderedSame
        }

        guard isError || nonceHeader != nil || errorCode == "use_dpop_nonce" else {
            return nil
        }

        let headerSummary = headers
            .map { "\($0.name): \($0.value)" }
            .joined(separator: "\n")

        return """
        DPoP response diagnostics for: \(method) \(url)
        status: \(status)
        dpop-nonce: \(nonceHeader == nil ? "missing" : "present")
        error: \(errorCode ?? "nil")
        headers:
        \(headerSummary)
        """
    }

    private static func responseErrorCode(_ responseData: Data) -> String? {
        guard !responseData.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: responseData),
              let dictionary = object as? [String: Any]
        else { return nil }

        return dictionary["error"] as? String
    }

    private static func log(_ message: String) {
        #if canImport(OSLog)
        logger.log("\(message, privacy: .public)")
        #else
        print(message)
        #endif
    }
}
