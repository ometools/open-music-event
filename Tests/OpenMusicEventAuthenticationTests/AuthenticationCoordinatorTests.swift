import ATProtoOAuth
import ComposableArchitecture2
import Dependencies
import Foundation
import Sharing
import TCATProtoAuthentication
import Testing

@testable import OpenMusicEventAuthentication

@MainActor
@Suite("AuthenticationCoordinator", .serialized)
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
    func successStoresSelectedSessionAndCompletesRequest() async {
        OpenMusicEventOAuth.resetStoredSession()
        let recorder = AuthorizationRequestRecorder()
        var state = AuthenticationCoordinator.State.localTestState()
        state.authorization = AuthorizationFlow.State(
            requirement: OAuth.AuthRequirement(
                permissions: [OpenMusicEventOAuth.tangledPullCreatePermission]
            )
        )
        state.$sessionStore.withLock {
            $0.upsert(.placeholder)
        }
        let store = withDependencies {
            $0.openMusicEventAuthorizationRequests = .recording(recorder)
        } operation: {
            Store(initialState: state) {
                AuthenticationCoordinator()
            }
        }

        let task = store.send(
            .authorization(.delegate(.succeeded(OAuth.Session.placeholder.accountID)))
        )
        await task?.value

        #expect(store.authorization == nil)
        #expect(store.session == .placeholder)
        #expect(await recorder.events == [.succeed])
    }

    @Test
    func routedSuccessStoresSelectedSessionAndCompletesResponder() async throws {
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
        state.$sessionStore.withLock {
            $0.upsert(.placeholder)
        }
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

        let task = store.send(
            .authorization(.delegate(.succeeded(OAuth.Session.placeholder.accountID)))
        )
        await task?.value
        try await waiter.value

        #expect(store.authorization == nil)
        #expect(store.routedAuthorizationRequest == nil)
        #expect(store.session == .placeholder)
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

        let task = store.send(.authorization(.delegate(.cancelled)))
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

        let task = store.send(.authorization(.delegate(.cancelled)))
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
        state.authorization = AuthorizationFlow.State(requirement: requirement)
        let store = withDependencies {
            $0.openMusicEventAuthorizationRequests = .recording(recorder)
        } operation: {
            Store(initialState: state) {
                AuthenticationCoordinator()
            }
        }

        let task = store.send(.authorization(.delegate(.failed(failure))))
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
        let request = AuthorizationPresentationRequest(requirement: requirement)
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

        let task = store.send(.authorization(.delegate(.failed(failure))))
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
