import ATProtoOAuth
import DependenciesTestSupport
import Foundation
import Testing

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
                == URL(string: "openmusicevent:/oauth/callback")!
        )
        #expect(OpenMusicEventOAuth.appManifest.appName == "Open Music Event")
    }

    @Test
    func manifestIncludesProposalPermissions() {
        let permissions = Set(
            OpenMusicEventOAuth.appManifest.maximumPermissions.permissions.map(\.rawValue)
        )

        #expect(permissions.contains("atproto"))
        #expect(permissions.contains("repo:sh.tangled.publicKey?action=create"))
        #expect(permissions.contains("repo:sh.tangled.repo.pull?action=create"))
        #expect(permissions.contains("blob:text/x-patch"))
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
                URL(string: "openmusicevent:/oauth/callback?code=abc&state=def")!
            )
        )
        #expect(
            !OpenMusicEventOAuth.isCallbackURL(
                URL(string: "openmusicevent:/organizers/demo/events/event")!
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
