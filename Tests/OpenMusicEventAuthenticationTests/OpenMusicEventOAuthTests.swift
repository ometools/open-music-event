import ATProtoOAuth
import Dependencies
import DependenciesTestSupport
import Foundation
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
        #expect(permissions.contains("repo:sh.tangled.repo.pull"))
        #expect(permissions.contains("repo:sh.tangled.repo.pull.status"))
        #expect(permissions.contains("blob:application/gzip"))
        #expect(permissions.contains("blob:text/x-patch"))

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
                description: "The first, and largest hosted AT Protocol entryway, with bsky.social handles.",
                imageURL: signUpServerFaviconURL(host: "bsky.social"),
                metadataSource: "community-lexicon-enrichment",
                availability: .available(serverHost: "bsky.social")
            ),
            OAuthSignUpServerOption(
                id: "eurosky",
                title: "Eurosky",
                subtitle: "eurosky.social",
                description: "A Europe-focused AT Protocol community server using eurosky.social accounts.",
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
    func preparedDependenciesExposeSelectedSessionStoreFallback() {
        OpenMusicEventOAuth.resetStoredSession()
        var dependencies = DependencyValues()
        var sessionStore = OAuth.SessionStore()
        sessionStore.upsert(.placeholder)
        OpenMusicEventOAuth.sessionStore.withLock {
            $0 = sessionStore
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
    }

    @Test
    func bundledMetadataMatchesManifest() throws {
        let bundled = try JSONDecoder().decode(
            OAuth.App.Metadata.self,
            from: OpenMusicEventOAuth.bundledMetadataData()
        )
        let generated = OpenMusicEventOAuth.appManifest.metadata()

        #expect(bundled.appID == generated.appID)
        #expect(bundled.appName == generated.appName)
        #expect(bundled.applicationType == generated.applicationType)
        #expect(bundled.scope.rawValue == generated.scope.rawValue)
        #expect(bundled.responseTypes == generated.responseTypes)
        #expect(bundled.grantTypes == generated.grantTypes)
        #expect(bundled.redirectURIS == generated.redirectURIS)
        #expect(bundled.tokenEndpointAuthMethod == generated.tokenEndpointAuthMethod)
        #expect(bundled.dpopBoundAccessToken == generated.dpopBoundAccessToken)
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
            var sessionStore = OAuth.SessionStore()
            sessionStore.upsert(.placeholder)

            try keychainStorage.setData(
                JSONEncoder().encode(OAuth.Session.placeholder),
                OpenMusicEventOAuth.sessionKeychainItem
            )
            try keychainStorage.setData(
                JSONEncoder().encode(sessionStore),
                OpenMusicEventOAuth.sessionStoreKeychainItem
            )

            try await OpenMusicEventOAuth.enforceStoredAuthenticationFreshness()

            #expect(OpenMusicEventOAuth.session.wrappedValue == .placeholder)
            #expect(OpenMusicEventOAuth.sessionStore.wrappedValue == sessionStore)
        }
    }
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

private struct TestOEmbedFetch: Error {}
