import ATProto
import ATProtoOAuth
import ComposableAtmosphereUserInput
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import HTTPClient
import HTTPTypes
import Sharing
import Synchronization
import TCATProtoAuthentication
import Testing
import WebMetadataClient

@testable import OpenMusicEventAuthentication

@Suite("OpenMusicEvent OAuth configuration", .serialized)
struct OpenMusicEventOAuthTests {
    @Test
    func manifestUsesOpenMusicEventClientMetadata() {
        #expect(
            OpenMusicEventOAuth.appConfiguration.appID.rawValue
                == URL(string: "https://openmusicevent.app/.well-known/oauth-client-metadata.json")!
        )
        #expect(
            OpenMusicEventOAuth.appConfiguration.redirectURI.rawValue
                == URL(string: "app.openmusicevent:/oauth/callback")!
        )
        #expect(OpenMusicEventOAuth.appManifest.appName == "Open Music Event")
    }

    @Test
    func manifestIncludesTangledPullRequestSurface() {
        let permissions = Set(
            OpenMusicEventOAuth.appManifest.maximumPermissions.permissions.map(\.rawValue)
        )

        #expect(permissions.contains("atproto"))
        #expect(permissions.contains("repo:sh.tangled.publicKey?action=create"))
        #expect(permissions.contains("repo:sh.tangled.repo.pull?action=create"))
        #expect(permissions.contains("repo:sh.tangled.repo.pull?action=update"))
        #expect(permissions.contains("repo:sh.tangled.repo.pull?action=delete"))
        #expect(permissions.contains("repo:sh.tangled.repo.pull.status?action=create"))
        #expect(permissions.contains("repo:sh.tangled.repo.pull.status?action=update"))
        #expect(permissions.contains("repo:sh.tangled.repo.pull.status?action=delete"))
        #expect(permissions.contains("rpc:sh.tangled.repo.merge?aud=*"))
        #expect(permissions.contains("repo:sh.tangled.repo?action=create"))
        #expect(permissions.contains("repo:sh.tangled.repo?action=update"))
        #expect(permissions.contains("repo:sh.tangled.repo?action=delete"))
        #expect(permissions.contains("rpc:sh.tangled.repo.create?aud=*"))
        #expect(permissions.contains("rpc:sh.tangled.repo.setContributors"))
        #expect(permissions.contains("repo:app.openmusicevent.source?action=create"))
        #expect(permissions.contains("repo:app.openmusicevent.source?action=update"))
        #expect(permissions.contains("include:app.userinput.authFull"))
        #expect(permissions.contains("blob:image/*"))
        #expect(!permissions.contains("repo:app.userinput.discussion?action=create"))
        #expect(permissions.contains("blob:application/gzip"))
        #expect(permissions.contains("blob:text/x-patch"))
        #expect(
            OpenMusicEventOAuth.proposalAuthRequirement.permissions
                .contains(OpenMusicEventOAuth.tangledPublicKeyCreatePermission)
        )

        #expect(
            OpenMusicEventOAuth.appManifest.maximumPermissions
                .missing(OpenMusicEventOAuth.proposalAuthRequirement.permissions)
                .isEmpty
        )
        #expect(
            OpenMusicEventOAuth.appManifest.maximumPermissions
                .missing(OpenMusicEventOAuth.tangledPullStatusAuthRequirement.permissions)
                .isEmpty
        )
        #expect(
            OpenMusicEventOAuth.appManifest.maximumPermissions
                .missing(OpenMusicEventOAuth.tangledPullDeleteAuthRequirement.permissions)
                .isEmpty
        )
        #expect(
            OpenMusicEventOAuth.appManifest.maximumPermissions
                .missing(OpenMusicEventOAuth.tangledPullMergeAuthRequirement.permissions)
                .isEmpty
        )
        #expect(
            OpenMusicEventOAuth.appManifest.maximumPermissions
                .missing(OpenMusicEventOAuth.tangledRepositoryManagementAuthRequirement.permissions)
                .isEmpty
        )
        #expect(
            OpenMusicEventOAuth.appManifest.maximumPermissions
                .missing(OpenMusicEventOAuth.sourceRecordAuthRequirement.permissions)
                .isEmpty
        )
        #expect(
            OpenMusicEventOAuth.appManifest.maximumPermissions
                .missing(
                    UserInputAuthorization.authFullRequirement.permissions
                )
                .isEmpty
        )
    }

    @Test
    func pullRequestWorkflowAuthorizationCoversTheFullLifecycle() {
        expectNoDifference(
            OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement.permissions,
            OpenMusicEventOAuth.proposalAuthRequirement.permissions
                .union(OpenMusicEventOAuth.tangledPullRequestSurfaceAuthRequirement.permissions)
                .union(OpenMusicEventOAuth.tangledPullMergeAuthRequirement.permissions)
        )
        #expect(
            OpenMusicEventOAuth.appManifest.maximumPermissions
                .missing(
                    OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement.permissions
                )
                .isEmpty
        )
    }

    @Test
    func pullRequestWorkflowAuthorizationSatisfiesEveryLaterAction() {
        let session = openMusicEventTestSession(
            permissions: OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement
                .permissions
                .union([.atproto])
        )
        let requirements = [
            OpenMusicEventOAuth.proposalAuthRequirement,
            OpenMusicEventOAuth.tangledPullStatusAuthRequirement,
            OpenMusicEventOAuth.tangledPullMergeAuthRequirement,
            OpenMusicEventOAuth.tangledPullDeleteAuthRequirement,
        ]

        expectNoDifference(
            requirements.map {
                OAuth.authorizationStatus(
                    for: $0,
                    session: session,
                    manifest: OpenMusicEventOAuth.appManifest
                )
            },
            requirements.map { _ in OAuth.AuthorizationStatus.satisfied(session) }
        )
    }

    @Test
    func tangledWorkspaceManagementRequirementIncludesFullEditSurface() throws {
        let permissions = Set(
            OpenMusicEventOAuth.tangledWorkspaceManagementAuthRequirement
                .permissions
                .map(\.rawValue)
        )

        #expect(permissions.contains("repo:sh.tangled.publicKey?action=create"))
        #expect(permissions.contains("repo:sh.tangled.repo.pull?action=create"))
        #expect(permissions.contains("repo:sh.tangled.repo.pull?action=update"))
        #expect(permissions.contains("repo:sh.tangled.repo.pull?action=delete"))
        #expect(permissions.contains("repo:sh.tangled.repo.pull.status?action=create"))
        #expect(permissions.contains("repo:sh.tangled.repo.pull.status?action=update"))
        #expect(permissions.contains("repo:sh.tangled.repo.pull.status?action=delete"))
        #expect(permissions.contains("blob:application/gzip"))

        let requested = try OAuth.requestedPermissions(
            for: OpenMusicEventOAuth.tangledWorkspaceManagementAuthRequirement,
            currentSession: nil,
            manifest: OpenMusicEventOAuth.appManifest
        )

        #expect(
            requested
                .missing(
                    OpenMusicEventOAuth.tangledWorkspaceManagementAuthRequirement
                        .permissions
                )
                .isEmpty
        )
    }

    @Test
    func manifestRequestsWildcardTangledKnotRPCPermissions() throws {
        let requirement = OAuth.AuthRequirement(
            permissions: [
                OpenMusicEventOAuth.tangledPullMergePermission,
                OpenMusicEventOAuth.tangledRepositoryCreatePermission,
            ]
        )

        let requested = try OAuth.requestedPermissions(
            for: requirement,
            currentSession: nil,
            manifest: OpenMusicEventOAuth.appManifest
        )

        #expect(
            OpenMusicEventOAuth.appManifest.maximumPermissions
                .missing(requirement.permissions)
                .isEmpty
        )
        #expect(
            requested.permissions.contains(
                .rpc("sh.tangled.repo.merge", audience: "*")
            )
        )
        #expect(
            requested.permissions.contains(
                .rpc("sh.tangled.repo.create", audience: "*")
            )
        )
    }

    @Test
    func dpopDiagnosticsIncludeNonceHeaderPresenceAndRawHeaders() throws {
        let message = try #require(
            OpenMusicEventOAuthNetworkDiagnostics.responseMessage(
                method: "POST",
                url: "https://jellybaby.us-east.host.bsky.network/xrpc/com.atproto.repo.createRecord",
                status: "401",
                isError: true,
                headers: [
                    (name: "cache-control", value: "no-store"),
                    (name: "DPoP-Nonce", value: "server-nonce"),
                ],
                responseData: Data(#"{"error":"use_dpop_nonce","message":"DPoP \"nonce\" mismatch"}"#.utf8)
            )
        )

        #expect(message.contains("dpop-nonce: present"))
        #expect(message.contains("error: use_dpop_nonce"))
        #expect(message.contains("cache-control: no-store"))
        #expect(message.contains("DPoP-Nonce: server-nonce"))
    }

    @Test
    func `HTML archive failure remains an HTTP error`() async {
        let archiveURL = URL(
            string: "https://tangled.org/wickedwoods.ca/ome-workspace/archive/ome%2Fproposal-2026.tar.gz"
        )!
        let responseBody = Data(
            "\n    <html><body>Tangled is temporarily unavailable.</body></html>"
                .utf8
        )
        let authFailureMessage = Shared<ErrorMessage?>(value: nil)

        do {
            let _: Data = try await withDependencies {
                $0.httpClient = .liveValue
                $0.requestInterceptors = []
                $0.responseInterceptors = []
                $0.dataForURL = { request, _ in
                    expectNoDifference(request.url, archiveURL)
                    return (
                        responseBody,
                        HTTPResponse(status: .serviceUnavailable)
                    )
                }
                $0.errorInterceptors = [
                    .openMusicEventTokenRefresh(
                        selectedSession: .none,
                        authFailureMessage: authFailureMessage
                    )
                ]
            } operation: {
                @Dependency(\.httpClient) var httpClient

                // The white-label review requests its source branch archive.
                return try await httpClient.get(archiveURL, decodingTo: Data.self)
            }

            Issue.record("Expected the archive request to fail.")
        } catch let HTTPError.httpError(status, body, _) {
            // A public archive outage remains an HTTP failure with its original response intact.
            expectNoDifference(status, .serviceUnavailable)
            expectNoDifference(body, responseBody)
        } catch {
            Issue.record("Expected an HTTP error, but received: \(error)")
        }
    }

    @Test
    func dpopDiagnosticsCallOutMissingNonceHeader() throws {
        let message = try #require(
            OpenMusicEventOAuthNetworkDiagnostics.responseMessage(
                method: "POST",
                url: "https://jellybaby.us-east.host.bsky.network/xrpc/com.atproto.repo.createRecord",
                status: "401",
                isError: true,
                headers: [
                    (name: "cache-control", value: "no-store"),
                ],
                responseData: Data(#"{"error":"use_dpop_nonce","message":"DPoP \"nonce\" mismatch"}"#.utf8)
            )
        )

        #expect(message.contains("dpop-nonce: missing"))
        #expect(message.contains("error: use_dpop_nonce"))
        #expect(message.contains("cache-control: no-store"))
    }

    @Test
    func tangledWorkspaceManagementRequirementDoesNotRequestMergeUpFront() {
        let permissions = Set(
            OpenMusicEventOAuth.tangledWorkspaceManagementAuthRequirement
                .permissions
                .map(\.rawValue)
        )

        #expect(!permissions.contains("rpc:sh.tangled.repo.merge?aud=*"))
        #expect(!permissions.contains("rpc:sh.tangled.repo.create?aud=*"))
        #expect(!permissions.contains("rpc:sh.tangled.repo.setContributors"))
    }

    @Test
    func manifestAcceptsLegacyPatchScopeDuringPublicKeyAuthorization() {
        let previouslyGranted = OAuth.GrantedPermissions([
            .atproto,
            OpenMusicEventOAuth.legacyPatchBlobPermission,
        ])
        let requested = previouslyGranted.union(
            OAuth.GrantedPermissions(
                OpenMusicEventOAuth.tangledPublicKeyAuthRequirement.permissions
            )
        )

        let missing = OpenMusicEventOAuth.appManifest.maximumPermissions
            .missing(requested.permissions)

        #expect(missing.isEmpty)
        #expect(
            !OpenMusicEventOAuth.proposalAuthRequirement.permissions
                .contains(OpenMusicEventOAuth.legacyPatchBlobPermission)
        )
    }

    @Test
    func signUpServerConfigurationIncludesAppCuratedProviders() {
        let configuration = OpenMusicEventOAuth.signUpServerConfiguration

        #expect(configuration.defaultServerHost == "bsky.social")
        #expect(configuration.allowsCustomServerHost)
        #expect(configuration.options == [
            OAuthSignUpServerOption(
                id: "ome",
                title: "Open Music Event",
                subtitle: "ome.social",
                description: "Open Music Event's own hosted account option.",
                imageURL: signUpServerFaviconURL(host: "openmusicevent.app"),
                metadataSource: "community-lexicon-enrichment",
                availability: .comingSoon
            ),
            OAuthSignUpServerOption(
                id: "bsky",
                title: "BlueSky",
                subtitle: "bsky.social",
                description: "The first and largest hosted account provider, with bsky.social handles.",
                imageURL: signUpServerFaviconURL(host: "bsky.social"),
                metadataSource: "community-lexicon-enrichment",
                availability: .available(serverHost: "bsky.social")
            ),
            OAuthSignUpServerOption(
                id: "eurosky",
                title: "Eurosky",
                subtitle: "eurosky.social",
                description: "A Europe-focused community account provider using eurosky.social handles.",
                imageURL: signUpServerFaviconURL(host: "eurosky.social"),
                metadataSource: "community-lexicon-enrichment",
                availability: .available(serverHost: "eurosky.social")
            ),
        ])
    }

    @Test
    func signUpServerConfigurationUsesWebMetadataClient() {
        withDependencies {
            $0.webMetadataClient = WebMetadataClient(
                fetchOEmbed: { _ in throw TestOEmbedFetch() },
                googleS2FaviconURL: { host, size in
                    URL(string: "https://metadata.example/\(host)?size=\(size)")!
                },
                directFaviconURL: { _ in nil }
            )
        } operation: {
            let configuration = OpenMusicEventOAuth.signUpServerConfiguration

            #expect(configuration.options.map(\.imageURL) == [
                URL(string: "https://metadata.example/openmusicevent.app?size=128")!,
                URL(string: "https://metadata.example/bsky.social?size=128")!,
                URL(string: "https://metadata.example/eurosky.social?size=128")!,
            ])
        }
    }

    @Test
    func authorizationRequestsDefaultToOpenMusicEventSignUpServerConfiguration() async throws {
        let center = AuthorizationRequestCenter()
        let configuration = testSignUpServerConfiguration
        let requests = OpenMusicEventAuthorizationRequests(center: center)
            .openMusicEventDefaultingSignUpServerConfiguration(configuration)
        let stream = await requests.requests()
        let observedRequest = Task<AuthorizationRequestCenter.Request?, Never> {
            var iterator = stream.makeAsyncIterator()
            while let yieldedRequest = await iterator.next() {
                if let request = yieldedRequest {
                    return request
                }
            }
            return nil
        }
        let authorization = Task {
            try await requests.broker().authorize(OpenMusicEventOAuth.baseAuthRequirement)
        }

        let request = try #require(await observedRequest.value)
        await requests.cancel()
        _ = await authorization.result

        #expect(request.requirement == OpenMusicEventOAuth.baseAuthRequirement)
        #expect(request.serverHost == configuration.defaultServerHost)
        #expect(request.signUpServerConfiguration == configuration)
    }

    @Test
    func preparedDependenciesPreserveSharedAuthorizationBroker() async throws {
        let recordedRequirements = Mutex([OAuth.AuthRequirement]())
        let broker = OAuth.AuthorizationBroker { requirement in
            recordedRequirements.withLock { $0.append(requirement) }
        }
        var dependencies = DependencyValues()
        dependencies.oauthAuthorizationBroker = broker
        OpenMusicEventOAuth.prepareDependencies(&dependencies)

        try await dependencies.oauthAuthorizationBroker.authorize(
            OpenMusicEventOAuth.proposalAuthRequirement
        )

        expectNoDifference(
            recordedRequirements.withLock { $0 },
            [OpenMusicEventOAuth.proposalAuthRequirement]
        )
    }

    @Test
    func preparedDependenciesExposeSelectedSessionFromAppSelection() {
        OpenMusicEventOAuth.resetStoredSession()
        var dependencies = DependencyValues()
        let sessionStore = OAuth.SessionStore(
            selectedAccountID: nil,
            sessions: [
                OAuth.Session.placeholder.accountID.rawValue: .placeholder,
            ]
        )
        OpenMusicEventOAuth.sessionStore.withLock {
            $0 = sessionStore
        }
        OpenMusicEventOAuth.selectedSessionID.withLock {
            $0 = OAuth.Session.placeholder.accountID
        }
        defer {
            OpenMusicEventOAuth.resetStoredSession()
        }

        OpenMusicEventOAuth.prepareDependencies(&dependencies)

        withDependencies {
            $0 = dependencies
        } operation: {
            @Dependency(\.getOptionalDefaultSession) var getOptionalDefaultSession
            #expect(getOptionalDefaultSession() == .placeholder)
        }
        #expect(OpenMusicEventOAuth.sessionStore.wrappedValue.selectedAccountID == nil)
    }

    @Test
    func selectedOAuthSessionDependencyWritesThroughSelectedSessionStore() async {
        OpenMusicEventOAuth.resetStoredSession()
        var dependencies = DependencyValues()
        let sessionStore = OAuth.SessionStore(
            selectedAccountID: nil,
            sessions: [
                OAuth.Session.placeholder.accountID.rawValue: .placeholder,
            ]
        )
        OpenMusicEventOAuth.sessionStore.withLock {
            $0 = sessionStore
        }
        OpenMusicEventOAuth.selectedSessionID.withLock {
            $0 = OAuth.Session.placeholder.accountID
        }
        defer {
            OpenMusicEventOAuth.resetStoredSession()
        }

        OpenMusicEventOAuth.prepareDependencies(&dependencies)

        let refreshedAccessToken = OAuth.AccessToken(rawValue: "refreshed-access-token")
        await withDependencies {
            $0 = dependencies
        } operation: {
            @Dependency(\.selectedOAuthSession) var selectedOAuthSession
            #expect(selectedOAuthSession.current() == .placeholder)

            await selectedOAuthSession.update {
                $0?.accessToken = refreshedAccessToken
            }
        }

        #expect(
            OpenMusicEventOAuth.sessionStore
                .wrappedValue[OAuth.Session.placeholder.accountID]?
                .accessToken == refreshedAccessToken
        )
        #expect(OpenMusicEventOAuth.sessionStore.wrappedValue.selectedAccountID == nil)
    }

    @Test
    func siteMetadataMatchesManifest() throws {
        let site = try JSONDecoder().decode(
            OAuth.App.Metadata.self,
            from: siteMetadataData()
        )
        let generated = OpenMusicEventOAuth.appManifest.metadata()

        #expect(site.appID == generated.appID)
        #expect(site.appName == generated.appName)
        #expect(site.applicationType == generated.applicationType)
        #expect(site.scope.rawValue == generated.scope.rawValue)
        #expect(site.responseTypes == generated.responseTypes)
        #expect(site.grantTypes == generated.grantTypes)
        #expect(site.redirectURIS == generated.redirectURIS)
        #expect(site.tokenEndpointAuthMethod == generated.tokenEndpointAuthMethod)
        #expect(site.dpopBoundAccessToken == generated.dpopBoundAccessToken)
    }

    @Test
    func callbackURLMatchesConfiguredRedirect() {
        #expect(
            OpenMusicEventOAuth.isCallbackURL(
                URL(string: "app.openmusicevent:/oauth/callback?code=abc&state=def")!
            )
        )
        #expect(
            !OpenMusicEventOAuth.isCallbackURL(
                URL(string: "app.openmusicevent:/organizers/demo/events/event")!
            )
        )
    }

    @Test
    func storedAuthenticationReloadsFromKeychainStorage() async throws {
        let storage = InMemoryKeychainStorage()
        let keychainStorage = KeychainStorageClient.inMemory(storage)
        try await withDependencies {
            $0.keychainStorage = keychainStorage
        } operation: {
            OpenMusicEventOAuth.resetStoredSession()
            defer {
                OpenMusicEventOAuth.resetStoredSession()
            }
            let selectedSessionID = OAuth.Session.placeholder.accountID
            var sessionStore = OAuth.SessionStore(
                selectedAccountID: nil,
                sessions: [
                    selectedSessionID.rawValue: .placeholder,
                ]
            )

            try keychainStorage.setData(
                JSONEncoder().encode(sessionStore),
                OpenMusicEventOAuth.sessionStoreKeychainItem
            )
            try keychainStorage.setData(
                JSONEncoder().encode(selectedSessionID as Atmosphere.Account.ID?),
                OpenMusicEventOAuth.selectedSessionIDKeychainItem
            )

            try await OpenMusicEventOAuth.enforceStoredAuthenticationFreshness()

            var dependencies = DependencyValues()
            OpenMusicEventOAuth.prepareDependencies(&dependencies)

            withDependencies {
                $0 = dependencies
            } operation: {
                @Dependency(\.getOptionalDefaultSession) var getOptionalDefaultSession
                @Dependency(\.getSelectedOAuthSessionID) var getSelectedOAuthSessionID
                expectNoDifference(getSelectedOAuthSessionID(), selectedSessionID)
                expectNoDifference(getOptionalDefaultSession(), .placeholder)
            }
            sessionStore.selectedAccountID = selectedSessionID
            expectNoDifference(OpenMusicEventOAuth.session.wrappedValue, .placeholder)
            expectNoDifference(OpenMusicEventOAuth.sessionStore.wrappedValue, sessionStore)
            expectNoDifference(OpenMusicEventOAuth.selectedSessionID.wrappedValue, selectedSessionID)
        }
    }

    @Test
    func storedAuthenticationReloadsSelectedSessionIDFromKeychainStorage() async throws {
        let storage = InMemoryKeychainStorage()
        let keychainStorage = KeychainStorageClient.inMemory(storage)
        try await withDependencies {
            $0.keychainStorage = keychainStorage
        } operation: {
            OpenMusicEventOAuth.sessionStore.withLock {
                $0 = OAuth.SessionStore()
            }
            OpenMusicEventOAuth.selectedSessionID.withLock {
                $0 = nil
            }
            defer {
                OpenMusicEventOAuth.resetStoredSession()
            }

            let selectedSessionID = OAuth.Session.placeholder.accountID
            var sessionStore = OAuth.SessionStore()
            sessionStore.upsert(.placeholder)
            try keychainStorage.setData(
                JSONEncoder().encode(sessionStore),
                OpenMusicEventOAuth.sessionStoreKeychainItem
            )
            try keychainStorage.setData(
                JSONEncoder().encode(selectedSessionID as Atmosphere.Account.ID?),
                OpenMusicEventOAuth.selectedSessionIDKeychainItem
            )

            try await OpenMusicEventOAuth.enforceStoredAuthenticationFreshness()

            var dependencies = DependencyValues()
            OpenMusicEventOAuth.prepareDependencies(&dependencies)

            withDependencies {
                $0 = dependencies
            } operation: {
                @Dependency(\.getOptionalDefaultSession) var getOptionalDefaultSession
                @Dependency(\.getSelectedOAuthSessionID) var getSelectedOAuthSessionID
                expectNoDifference(getSelectedOAuthSessionID(), selectedSessionID)
                expectNoDifference(getOptionalDefaultSession(), .placeholder)
            }
            sessionStore.selectedAccountID = selectedSessionID
            expectNoDifference(OpenMusicEventOAuth.selectedSessionID.wrappedValue, selectedSessionID)
            expectNoDifference(OpenMusicEventOAuth.sessionStore.wrappedValue, sessionStore)
        }
    }

    @Test
    func storedAuthenticationMigratesSelectedSessionIDFromSessionStore() async throws {
        let storage = InMemoryKeychainStorage()
        let keychainStorage = KeychainStorageClient.inMemory(storage)
        try await withDependencies {
            $0.keychainStorage = keychainStorage
        } operation: {
            OpenMusicEventOAuth.sessionStore.withLock {
                $0 = OAuth.SessionStore()
            }
            OpenMusicEventOAuth.selectedSessionID.withLock {
                $0 = nil
            }
            defer {
                OpenMusicEventOAuth.resetStoredSession()
            }

            let selectedSessionID = OAuth.Session.placeholder.accountID
            let sessionStore = OAuth.SessionStore(
                selectedAccountID: selectedSessionID,
                sessions: [
                    selectedSessionID.rawValue: .placeholder,
                ]
            )
            try keychainStorage.setData(
                JSONEncoder().encode(sessionStore),
                OpenMusicEventOAuth.sessionStoreKeychainItem
            )

            try await OpenMusicEventOAuth.enforceStoredAuthenticationFreshness()

            var dependencies = DependencyValues()
            OpenMusicEventOAuth.prepareDependencies(&dependencies)

            withDependencies {
                $0 = dependencies
            } operation: {
                @Dependency(\.getOptionalDefaultSession) var getOptionalDefaultSession
                @Dependency(\.getSelectedOAuthSessionID) var getSelectedOAuthSessionID
                expectNoDifference(getSelectedOAuthSessionID(), selectedSessionID)
                expectNoDifference(getOptionalDefaultSession(), .placeholder)
            }
            expectNoDifference(OpenMusicEventOAuth.selectedSessionID.wrappedValue, selectedSessionID)
            let savedSelectedSessionIDData = try #require(
                try keychainStorage.data(OpenMusicEventOAuth.selectedSessionIDKeychainItem)
            )
            let savedSelectedSessionID = try JSONDecoder().decode(
                Atmosphere.Account.ID?.self,
                from: savedSelectedSessionIDData
            )
            expectNoDifference(savedSelectedSessionID, selectedSessionID)
        }
    }
}

private func siteMetadataData(filePath: String = #filePath) throws -> Data {
    let testFile = URL(fileURLWithPath: filePath)
    let packageRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try Data(
        contentsOf: packageRoot
            .appendingPathComponent("Deployments", isDirectory: true)
            .appendingPathComponent("ome-under-construction", isDirectory: true)
            .appendingPathComponent("public", isDirectory: true)
            .appendingPathComponent(".well-known", isDirectory: true)
            .appendingPathComponent("oauth-client-metadata.json", isDirectory: false)
    )
}

private let testSignUpServerConfiguration = OAuthSignUpServerConfiguration(
    defaultServerHost: "custom.social",
    options: [
        OAuthSignUpServerOption(
            id: "custom",
            title: "Custom",
            subtitle: "custom.social",
            description: "A test provider.",
            imageURL: nil,
            metadataSource: "test",
            availability: .available(serverHost: "custom.social")
        ),
    ],
    allowsCustomServerHost: false
)

private func signUpServerFaviconURL(host: String) -> URL {
    URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128")!
}

private func openMusicEventTestSession(
    permissions: Set<OAuth.Permission>
) -> OAuth.Session {
    var session = OAuth.Session.placeholder
    session.scope = OAuth.Scope(
        rawValue: permissions
            .map(\.rawValue)
            .sorted()
            .joined(separator: " ")
    )
    return session
}

private struct TestOEmbedFetch: Error {}
