import ComposableArchitecture2
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
        OpenMusicEventOAuth.resetStoredSession()
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
        OpenMusicEventOAuth.resetStoredSession()
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
        OpenMusicEventOAuth.resetStoredSession()
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
        OpenMusicEventOAuth.resetStoredSession()
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
        OpenMusicEventOAuth.resetStoredSession()
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
    func cancelClearsAuthorizationAndCancelsRequest() async {
        OpenMusicEventOAuth.resetStoredSession()
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
        OpenMusicEventOAuth.resetStoredSession()
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
        OpenMusicEventOAuth.resetStoredSession()
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
        #expect(await recorder.events == [.fail(failure)])
    }

    @Test
    func routedFailureClearsAuthorizationAndFailsResponder() async {
        OpenMusicEventOAuth.resetStoredSession()
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
        let session = Shared<OAuth.Session?>(value: .placeholder)
        let authFailureMessage = Shared<ErrorMessage?>(value: nil)
        let store = Store(initialState: SessionProbe.State()) {
            SessionProbe()
                .openMusicEventAuthenticatedSession(
                    session: session,
                    authFailureMessage: authFailureMessage
                )
        }

        store.send(.readSession)

        #expect(store.observedSession == .placeholder)
    }

    @Test
    func authenticatedDependencyModifierExposesSelectedSessionStoreFallback() {
        let session = Shared<OAuth.Session?>(value: nil)
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(.placeholder)
        let sessionStore = Shared<OAuth.SessionStore>(value: sessionStoreValue)
        let authFailureMessage = Shared<ErrorMessage?>(value: nil)
        let store = Store(initialState: SessionProbe.State()) {
            SessionProbe()
                .openMusicEventAuthenticatedSession(
                    session: session,
                    sessionStore: sessionStore,
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

private extension OAuthAuthenticationCoordinator.State {
    static func localTestState() -> Self {
        Self(
            storage: OAuthSessionStorage(
                session: Shared<OAuth.Session?>(value: nil),
                sessionStore: Shared<OAuth.SessionStore>(value: OAuth.SessionStore()),
                authFailureMessage: Shared<ErrorMessage?>(value: nil)
            )
        )
    }
}

private actor AuthorizationRequestRecorder {
    enum Event: Equatable {
        case cancel
        case fail(OAuth.AuthorizationRequired)
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
                await recorder.record(.fail(error))
            },
            cancel: {
                await recorder.record(.cancel)
            }
        )
    }
}
