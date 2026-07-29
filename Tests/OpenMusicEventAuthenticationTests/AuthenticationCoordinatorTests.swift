import ATProto
import ComposableArchitecture2
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import Sharing
import TCATProtoAuthentication
import Testing

@testable import ATProtoOAuth
@testable import OpenMusicEventAuthentication

@MainActor
@Suite("AuthenticationCoordinator", .serialized, .dependencies { $0.defaultPort = 443 })
struct AuthenticationCoordinatorTests {
    @Test
    func authorizationRequestPresentsAuthorizationFlow() {
        let requirement = OAuth.AuthRequirement(
            permissions: [OpenMusicEventOAuth.tangledPullCreatePermission]
        )
        let store = Store(initialState: AuthenticationCoordinator.State.localTestState()) {
            AuthenticationCoordinator()
        }

        store.send(
            .authorizationRequestChanged(
                AuthorizationRequestCenter.Request(id: UUID(0), requirement: requirement)
            )
        )

        #expect(store.authorization?.requirement == requirement)
        #expect(store.authorization?.loginHint == "")
    }

    @Test
    func signUpAuthorizationRequestPresentsSelectorConfiguration() {
        let store = Store(initialState: AuthenticationCoordinator.State.localTestState()) {
            AuthenticationCoordinator()
        }

        store.send(
            .authorizationRequestChanged(
                AuthorizationRequestCenter.Request(
                    id: UUID(1),
                    mode: .signUp,
                    signUpServerConfiguration: OpenMusicEventOAuth.signUpServerConfiguration,
                    requirement: OpenMusicEventOAuth.baseAuthRequirement
                )
            )
        )

        #expect(store.authorization?.requirement == OpenMusicEventOAuth.baseAuthRequirement)
        #expect(store.authorization?.mode == .signUp)
        #expect(store.authorization?.serverHost == "bsky.social")
        #expect(
            store.authorization?.signUpServerConfiguration
                == OpenMusicEventOAuth.signUpServerConfiguration
        )
        #expect(store.authorization?.selectedSignUpServerOptionID == "bsky")
    }

    @Test
    func routedAuthorizationRequestPresentsAuthorizationFlow() {
        let requirement = OAuth.AuthRequirement(
            permissions: [OpenMusicEventOAuth.tangledPullCreatePermission]
        )
        let request = AuthorizationPresentationRequest(requirement: requirement)
        let store = Store(initialState: AuthenticationCoordinator.State.localTestState()) {
            AuthenticationCoordinator()
        }

        store.send(.authorizationPresentationRequested(request))

        #expect(store.authorization?.requirement == requirement)
        #expect(store.authorization?.loginHint == "")
        #expect(store.routedAuthorizationRequest?.id == request.id)
    }

    @Test
    func successStoresSelectedSessionAndCompletesRequest() async throws {
        let recorder = AuthorizationRequestRecorder()
        let requirement = OAuth.AuthRequirement(
            permissions: [OpenMusicEventOAuth.tangledPullCreatePermission]
        )
        let session = openMusicEventTestSession(permissions: requirement.permissions)
        var state = AuthenticationCoordinator.State.localTestState()
        state.authorization = AuthorizationFlow.State(
            requirement: requirement,
            loginHint: "woody.fm"
        )
        let client = successfulOAuthClient(session: session)
        let store = withDependencies {
            $0[OAuth.Client.self] = client
            $0.oauthAppManifest = OpenMusicEventOAuth.appManifest
            $0.oauthBrowserStrategy = .webAuthenticationSession
            $0.openMusicEventAuthorizationRequests = .recording(recorder)
            $0.webAuthenticationSession.open = { _, _ in testCallbackURL }
        } operation: {
            Store(initialState: state) {
                AuthenticationCoordinator()
            }
        }

        let task = store.send(.authorization(.submit))
        await task?.value

        #expect(store.authorization == nil)
        #expect(store.session == session)
        #expect(await recorder.events == [.succeed])
    }

    @Test
    func routedSuccessStoresSelectedSessionAndCompletesResponder() async throws {
        let recorder = AuthorizationRequestRecorder()
        let requirement = OAuth.AuthRequirement(
            permissions: [OpenMusicEventOAuth.tangledPullCreatePermission]
        )
        let session = openMusicEventTestSession(permissions: requirement.permissions)
        let request = AuthorizationPresentationRequest(
            loginHint: "woody.fm",
            requirement: requirement
        )
        var state = AuthenticationCoordinator.State.localTestState()
        state.routedAuthorizationRequest = request
        state.authorization = OpenMusicEventOAuth.authorizationFlowState(
            for: request,
            session: state.session,
            sessionStore: state.sessionStore
        )
        let client = successfulOAuthClient(session: session)
        let store = withDependencies {
            $0[OAuth.Client.self] = client
            $0.oauthAppManifest = OpenMusicEventOAuth.appManifest
            $0.oauthBrowserStrategy = .webAuthenticationSession
            $0.openMusicEventAuthorizationRequests = .recording(recorder)
            $0.webAuthenticationSession.open = { _, _ in testCallbackURL }
        } operation: {
            Store(initialState: state) {
                AuthenticationCoordinator()
            }
        }
        let waiter = Task {
            try await request.responder.wait()
        }

        let task = store.send(.authorization(.submit))
        await task?.value
        try await waiter.value

        #expect(store.authorization == nil)
        #expect(store.routedAuthorizationRequest == nil)
        #expect(store.session == session)
        #expect(await recorder.events == [])
    }

    @Test
    func mergePermissionUpgradePersistsSelectedSessionForNextLaunch() async throws {
        let keychainStorage = InMemoryKeychainStorage()

        try await withDependencies {
            $0.keychainStorage = .inMemory(keychainStorage)
        } operation: {
            // The user is already signed in, but the current token is missing merge permission.
            var baseSession = openMusicEventTestSession(
                permissions: OpenMusicEventOAuth.appManifest.basePermissions.permissions
            )
            baseSession.accessToken = OAuth.AccessToken(rawValue: "base-access-token")
            baseSession.refreshToken = OAuth.RefreshToken(rawValue: "base-refresh-token")
            var initialSessionStore = OAuth.SessionStore()
            initialSessionStore.upsert(baseSession)
            let sessionStoreItem = KeychainStorageItem(
                service: "fm.woody.openMusicEvent.tests",
                account: "mergePermissionUpgrade.sessionStore"
            )
            let sessionStore = Shared(
                wrappedValue: initialSessionStore,
                KeychainSharedKey(item: sessionStoreItem)
            )
            let selectedSessionID = Shared(
                value: baseSession.accountID as Atmosphere.Account.ID?
            )
            let authFailureMessage = Shared<ErrorMessage?>(value: nil)
            let storage = OAuthSessionStorage(
                sessionStore: sessionStore,
                authFailureMessage: authFailureMessage,
                selectedSessionID: selectedSessionID
            )
            try #require(
                OAuth.authorizationStatus(
                    for: OpenMusicEventOAuth.tangledPullMergeAuthRequirement,
                    session: storage.session.wrappedValue,
                    manifest: OpenMusicEventOAuth.appManifest
                ) == .upgradeAvailable(
                    missing: OpenMusicEventOAuth.tangledPullMergeAuthRequirement.permissions,
                    requirement: OpenMusicEventOAuth.tangledPullMergeAuthRequirement
                )
            )

            // The authorization callback returns the same account with the merge token added.
            var upgradedSession = openMusicEventTestSession(
                permissions: OpenMusicEventOAuth.appManifest.basePermissions.permissions
                    .union(OpenMusicEventOAuth.tangledPullMergeAuthRequirement.permissions)
            )
            upgradedSession.accessToken = OAuth.AccessToken(rawValue: "merge-access-token")
            upgradedSession.refreshToken = OAuth.RefreshToken(rawValue: "merge-refresh-token")
            let upgradedAccessToken = upgradedSession.accessToken

            var state = AuthenticationCoordinator.State(storage: storage)
            state.directAuthorization = OpenMusicEventOAuth.authorizationFlowState(
                for: AuthorizationPresentationRequest(
                    loginHint: baseSession.accountID.rawValue.description,
                    startsImmediately: true,
                    requirement: OpenMusicEventOAuth.tangledPullMergeAuthRequirement
                ),
                session: baseSession,
                sessionStore: initialSessionStore
            )
            let store = withDependencies {
                $0[OAuth.Client.self] = successfulOAuthClient(session: upgradedSession)
                $0.defaultPort = 443
                $0.oauthAppConfiguration = OpenMusicEventOAuth.appConfiguration
                $0.oauthAppManifest = OpenMusicEventOAuth.appManifest
                $0.oauthBrowserStrategy = .webAuthenticationSession
                $0.webAuthenticationSession.open = { _, _ in testCallbackURL }
            } operation: {
                Store(initialState: state) {
                    AuthenticationCoordinator()
                }
            }

            await store.send(.directAuthorization(.submit))?.value
            try await waitForCondition {
                storage.session.wrappedValue?.accessToken == upgradedAccessToken
            }
            #expect(store.directAuthorization == nil)

            // The upgraded selected session is saved to the same keychain-backed store the app
            // reloads on launch.
            try await waitForCondition {
                keychainStorage.data(for: sessionStoreItem) != nil
            }
            let savedSessionStore = try JSONDecoder().decode(
                OAuth.SessionStore.self,
                from: try #require(
                    keychainStorage.data(for: sessionStoreItem)
                )
            )
            let savedSession = try #require(savedSessionStore[baseSession.accountID])
            #expect(savedSessionStore.selectedAccountID == baseSession.accountID)
            #expect(savedSession.accessToken == upgradedSession.accessToken)
            #expect(savedSession.refreshToken == upgradedSession.refreshToken)
            expectNoDifference(
                savedSession.grantedPermissions
                    .missing(OpenMusicEventOAuth.tangledPullMergeAuthRequirement.permissions),
                []
            )

            // A fresh launch binds new shared state to the same keychain item and reloads the
            // upgraded selected session from disk.
            let relaunchedStorage = OAuthSessionStorage(
                sessionStore: Shared(
                    wrappedValue: OAuth.SessionStore(),
                    KeychainSharedKey(item: sessionStoreItem)
                ),
                authFailureMessage: Shared<ErrorMessage?>(value: nil),
                selectedSessionID: Shared(value: baseSession.accountID as Atmosphere.Account.ID?)
            )
            try await relaunchedStorage.enforceFreshness()

            let relaunchedSession = try #require(relaunchedStorage.session.wrappedValue)
            #expect(relaunchedSession.accessToken == upgradedSession.accessToken)
            #expect(
                OAuth.authorizationStatus(
                    for: OpenMusicEventOAuth.tangledPullMergeAuthRequirement,
                    session: relaunchedSession,
                    manifest: OpenMusicEventOAuth.appManifest
                ) == .satisfied(upgradedSession)
            )
        }
    }

    @Test
    func cancelClearsAuthorizationAndCancelsRequest() async {
        let recorder = AuthorizationRequestRecorder()
        var state = AuthenticationCoordinator.State.localTestState()
        state.authorization = AuthorizationFlow.State(
            requirement: OAuth.AuthRequirement(
                permissions: [OpenMusicEventOAuth.tangledPullCreatePermission]
            )
        )
        let store = withDependencies {
            $0.openMusicEventAuthorizationRequests = .recording(recorder)
        } operation: {
            Store(initialState: state) {
                AuthenticationCoordinator()
            }
        }

        let task = store.send(.authorization(.cancel))
        await task?.value

        #expect(store.authorization == nil)
        #expect(await recorder.events == [.cancel])
    }

    @Test
    func routedCancelClearsAuthorizationAndCancelsResponder() async {
        let recorder = AuthorizationRequestRecorder()
        let request = AuthorizationPresentationRequest(
            requirement: OAuth.AuthRequirement(
                permissions: [OpenMusicEventOAuth.tangledPullCreatePermission]
            )
        )
        var state = AuthenticationCoordinator.State.localTestState()
        state.routedAuthorizationRequest = request
        state.authorization = OpenMusicEventOAuth.authorizationFlowState(
            for: request,
            session: state.session,
            sessionStore: state.sessionStore
        )
        let store = withDependencies {
            $0.openMusicEventAuthorizationRequests = .recording(recorder)
        } operation: {
            Store(initialState: state) {
                AuthenticationCoordinator()
            }
        }
        let waiter = Task {
            try await request.responder.wait()
        }

        let task = store.send(.authorization(.cancel))
        await task?.value
        await #expect(throws: CancellationError.self) {
            try await waiter.value
        }

        #expect(store.authorization == nil)
        #expect(store.routedAuthorizationRequest == nil)
        #expect(await recorder.events == [])
    }

    @Test
    func failureClearsAuthorizationAndFailsRequest() async {
        let recorder = AuthorizationRequestRecorder()
        let requirement = OAuth.AuthRequirement(
            permissions: [OpenMusicEventOAuth.tangledPullCreatePermission]
        )
        let failure = OAuth.AuthorizationRequired.signIn(requirement)
        var state = AuthenticationCoordinator.State.localTestState()
        state.authorization = AuthorizationFlow.State(
            requirement: requirement,
            loginHint: "woody.fm"
        )
        let store = withDependencies {
            $0[OAuth.Client.self] = failingOAuthClient(failure)
            $0.oauthAppManifest = OpenMusicEventOAuth.appManifest
            $0.openMusicEventAuthorizationRequests = .recording(recorder)
        } operation: {
            Store(initialState: state) {
                AuthenticationCoordinator()
            }
        }

        let task = store.send(.authorization(.submit))
        await task?.value

        #expect(store.authorization == nil)
        #expect(await recorder.events == [.fail(String(describing: failure))])
    }

    @Test
    func routedFailureClearsAuthorizationAndFailsResponder() async {
        let recorder = AuthorizationRequestRecorder()
        let requirement = OAuth.AuthRequirement(
            permissions: [OpenMusicEventOAuth.tangledPullCreatePermission]
        )
        let failure = OAuth.AuthorizationRequired.signIn(requirement)
        let request = AuthorizationPresentationRequest(
            loginHint: "woody.fm",
            requirement: requirement
        )
        var state = AuthenticationCoordinator.State.localTestState()
        state.routedAuthorizationRequest = request
        state.authorization = OpenMusicEventOAuth.authorizationFlowState(
            for: request,
            session: state.session,
            sessionStore: state.sessionStore
        )
        let store = withDependencies {
            $0[OAuth.Client.self] = failingOAuthClient(failure)
            $0.oauthAppManifest = OpenMusicEventOAuth.appManifest
            $0.openMusicEventAuthorizationRequests = .recording(recorder)
        } operation: {
            Store(initialState: state) {
                AuthenticationCoordinator()
            }
        }
        let waiter = Task {
            try await request.responder.wait()
        }

        let task = store.send(.authorization(.submit))
        await task?.value
        let error = await #expect(throws: OAuth.AuthorizationRequired.self) {
            try await waiter.value
        }

        #expect(error == failure)
        #expect(store.authorization == nil)
        #expect(store.routedAuthorizationRequest == nil)
        #expect(await recorder.events == [])
    }

    @Test
    func authenticatedDependencyModifierExposesStoredSession() {
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(.placeholder)
        let sessionStore = Shared<OAuth.SessionStore>(value: sessionStoreValue)
        let selectedSessionID = Shared<Atmosphere.Account.ID?>(
            value: OAuth.Session.placeholder.accountID
        )
        let authFailureMessage = Shared<ErrorMessage?>(value: nil)
        let store = Store(initialState: SessionProbe.State()) {
            SessionProbe()
                .openMusicEventAuthenticatedSession(
                    sessionStore: sessionStore,
                    selectedSessionID: selectedSessionID,
                    authFailureMessage: authFailureMessage
                )
        }

        store.send(.readSession)

        #expect(store.observedSession == .placeholder)
    }

    @Test
    func authenticatedDependencyModifierExposesSelectedSessionStoreFallback() {
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(.placeholder)
        let sessionStore = Shared<OAuth.SessionStore>(value: sessionStoreValue)
        let selectedSessionID = Shared<Atmosphere.Account.ID?>(
            value: OAuth.Session.placeholder.accountID
        )
        let authFailureMessage = Shared<ErrorMessage?>(value: nil)
        let store = Store(initialState: SessionProbe.State()) {
            SessionProbe()
                .openMusicEventAuthenticatedSession(
                    sessionStore: sessionStore,
                    selectedSessionID: selectedSessionID,
                    authFailureMessage: authFailureMessage
                )
        }

        store.send(.readSession)

        #expect(store.observedSession == .placeholder)
    }
}

@Feature
private struct SessionProbe {
    struct State {
        var observedSession: OAuth.Session?
    }

    enum Action {
        case readSession
    }

    @Dependency(\.getOptionalDefaultSession) var getOptionalDefaultSession

    var body: some Feature {
        Update { state, action in
            switch action {
            case .readSession:
                state.observedSession = getOptionalDefaultSession()
            }
        }
    }
}

private let testCallbackURL = OAuth.App.CallbackURI(
    URL(string: "app.openmusicevent:/oauth/callback?code=test-code&state=test-nonce&iss=https://bsky.social")!
)

private func successfulOAuthClient(session: OAuth.Session) -> OAuth.Client {
    var client = OAuth.Client()
    client.beginAuthorizationWithPermissions = { _, _ in
        (
            URL(string: "https://bsky.social/oauth/authorize")!,
            try testPendingSession()
        )
    }
    client.exchangeCode = { _, _, _, _ in
        session
    }
    return client
}

private func failingOAuthClient(_ failure: OAuth.AuthorizationRequired) -> OAuth.Client {
    var client = OAuth.Client()
    client.beginAuthorizationWithPermissions = { _, _ in
        throw failure
    }
    return client
}

private func openMusicEventTestSession(
    permissions: Set<OAuth.Permission>
) -> OAuth.Session {
    var session = OAuth.Session.placeholder
    var granted = Set([OAuth.Permission.atproto])
    granted.formUnion(permissions)
    session.scope = OAuth.Scope(
        rawValue: granted
            .map(\.rawValue)
            .sorted()
            .joined(separator: " ")
    )
    return session
}

private func testPendingSession() throws -> OAuth.Session.Pending {
    let metadata = try withDependencies {
        $0.defaultPort = 443
    } operation: {
        try JSONDecoder().decode(
            OAuth.AuthorizationServer.Metadata.self,
            from: Data("""
            {
                "issuer": "https://bsky.social",
                "authorization_endpoint": "https://bsky.social/oauth/authorize",
                "token_endpoint": "https://bsky.social/oauth/token",
                "response_types_supported": ["code"],
                "grant_types_supported": ["authorization_code", "refresh_token"],
                "code_challenge_methods_supported": ["S256"],
                "token_endpoint_auth_methods_supported": ["none"],
                "token_endpoint_auth_signing_alg_values_supported": ["ES256"],
                "scopes_supported": ["atproto"],
                "authorization_response_iss_parameter_supported": true,
                "require_pushed_authorization_requests": true,
                "pushed_authorization_request_endpoint": "https://bsky.social/oauth/par",
                "dpop_signing_alg_values_supported": ["ES256"],
                "require_request_uri_registration": true,
                "client_id_metadata_document_supported": true
            }
            """.utf8)
        )
    }
    return OAuth.Session.Pending(
        pkceChallenge: OAuth.PKCE.Challenge(verifier: OAuth.PKCE.CodeVerifier("test-verifier")),
        state: OAuth.Nonce(rawValue: "test-nonce"),
        redirectURI: OAuth.App.RedirectURI(OpenMusicEventOAuth.redirectURL),
        authServer: metadata,
        accountID: OAuth.Session.placeholder.accountID,
        pdsHost: .init("placeholder.example"),
        dpopKey: OAuth.DPOP.Key()
    )
}

private func waitForCondition(
    _ condition: @escaping @Sendable () -> Bool
) async throws {
    for _ in 0..<100 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(condition())
}

private func waitForAsyncCondition(
    _ condition: @escaping @Sendable () async -> Bool
) async throws {
    for _ in 0..<100 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    let finalResult = await condition()
    try #require(finalResult)
}

private extension OAuthAuthenticationCoordinator.State {
    static func localTestState() -> Self {
        Self(
            storage: OAuthSessionStorage(
                sessionStore: Shared<OAuth.SessionStore>(value: OAuth.SessionStore()),
                authFailureMessage: Shared<ErrorMessage?>(value: nil),
                selectedSessionID: Shared<Atmosphere.Account.ID?>(value: nil)
            )
        )
    }
}

private actor AuthorizationRequestRecorder {
    enum Event: Equatable {
        case cancel
        case fail(String)
        case succeed
    }

    private(set) var events: [Event] = []

    func record(_ event: Event) {
        events.append(event)
    }
}

private extension OpenMusicEventAuthorizationRequests {
    static func recording(_ recorder: AuthorizationRequestRecorder) -> Self {
        Self(
            broker: { .init { _ in } },
            requests: {
                AsyncStream { continuation in
                    continuation.finish()
                }
            },
            signUp: { _, _ in },
            succeed: {
                await recorder.record(.succeed)
            },
            fail: { error in
                await recorder.record(.fail(String(describing: error)))
            },
            cancel: {
                await recorder.record(.cancel)
            }
        )
    }
}
