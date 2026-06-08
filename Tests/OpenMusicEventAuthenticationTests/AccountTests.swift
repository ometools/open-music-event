import ATProtoOAuth
import ComposableArchitecture2
import Sharing
import TCATProtoAuthentication
import Testing

@testable import OpenMusicEventAuthentication

@MainActor
@Suite("Account", .serialized)
struct AccountTests {
    @Test
    func loginButtonRequestsBaseAuthorization() async {
        let recorder = AccountAuthorizationRecorder()
        let store = withDependencies {
            $0.openMusicEventAuthorizationRequests = .recording(recorder)
        } operation: {
            Store(initialState: Account.State.localTestState()) {
                Account()
            }
        }

        let task = store.send(.loginButtonTapped)
        await task?.value

        #expect(await recorder.requirements == [OpenMusicEventOAuth.baseAuthRequirement])
        #expect(store.isLoginInProgress == false)
        #expect(store.errorMessage == nil)
    }

    @Test
    func signUpButtonRequestsBaseAuthorizationWithServerConfiguration() async {
        let recorder = AccountAuthorizationRecorder()
        let store = withDependencies {
            $0.openMusicEventAuthorizationRequests = .recording(recorder)
        } operation: {
            Store(initialState: Account.State.localTestState()) {
                Account()
            }
        }

        let task = store.send(.signUpButtonTapped)
        await task?.value

        #expect(
            await recorder.signUpRequests == [
                AccountAuthorizationRecorder.SignUpRequest(
                    requirement: OpenMusicEventOAuth.baseAuthRequirement,
                    signUpServerConfiguration: OpenMusicEventOAuth.signUpServerConfiguration
                )
            ]
        )
        #expect(store.isSignUpInProgress == false)
        #expect(store.errorMessage == nil)
    }

    @Test
    func signUpSuccessStoresSelectedSession() async {
        let recorder = AccountAuthorizationRecorder()
        let state = Account.State.localTestState()
        state.$sessionStore.withLock {
            $0.upsert(.placeholder)
        }
        let store = withDependencies {
            $0.openMusicEventAuthorizationRequests = .recording(recorder)
        } operation: {
            Store(initialState: state) {
                Account()
            }
        }

        let task = store.send(.signUpButtonTapped)
        await task?.value

        #expect(store.session == .placeholder)
        #expect(store.isSignUpInProgress == false)
        #expect(store.errorMessage == nil)
    }

    @Test
    func signUpCancellationClearsProgressWithoutError() async {
        let recorder = AccountAuthorizationRecorder(signUpError: CancellationError())
        let store = withDependencies {
            $0.openMusicEventAuthorizationRequests = .recording(recorder)
        } operation: {
            Store(initialState: Account.State.localTestState()) {
                Account()
            }
        }

        let task = store.send(.signUpButtonTapped)
        await task?.value

        #expect(store.isSignUpInProgress == false)
        #expect(store.errorMessage == nil)
    }

    @Test
    func logoutClearsStoredSessionAndCancelsRequests() async {
        let recorder = AccountAuthorizationRecorder()
        let state = Account.State.localTestState()
        state.$session.withLock { $0 = .placeholder }
        state.$sessionStore.withLock { $0.upsert(.placeholder) }
        let store = withDependencies {
            $0.openMusicEventAuthorizationRequests = .recording(recorder)
        } operation: {
            Store(initialState: state) {
                Account()
            }
        }

        let task = store.send(.logoutButtonTapped)
        await task?.value

        #expect(store.session == nil)
        #expect(store.sessionStore.selectedSession == nil)
        #expect(await recorder.didCancel)
    }
}

private extension Account.State {
    static func localTestState() -> Self {
        Self(
            authFailureMessage: Shared<ErrorMessage?>(value: nil),
            session: Shared<OAuth.Session?>(value: nil),
            sessionStore: Shared<OAuth.SessionStore>(value: OAuth.SessionStore())
        )
    }
}

private actor AccountAuthorizationRecorder {
    struct SignUpRequest: Equatable {
        var requirement: OAuth.AuthRequirement
        var signUpServerConfiguration: OAuthSignUpServerConfiguration
    }

    private(set) var didCancel = false
    private(set) var requirements: [OAuth.AuthRequirement] = []
    private(set) var signUpRequests: [SignUpRequest] = []
    private let signUpError: (any Error)?

    init(signUpError: (any Error)? = nil) {
        self.signUpError = signUpError
    }

    func recordCancel() {
        didCancel = true
    }

    func recordRequirement(_ requirement: OAuth.AuthRequirement) {
        requirements.append(requirement)
    }

    func recordSignUp(
        _ requirement: OAuth.AuthRequirement,
        signUpServerConfiguration: OAuthSignUpServerConfiguration
    ) throws {
        signUpRequests.append(
            SignUpRequest(
                requirement: requirement,
                signUpServerConfiguration: signUpServerConfiguration
            )
        )
        if let signUpError {
            throw signUpError
        }
    }
}

private extension OpenMusicEventAuthorizationRequests {
    static func recording(_ recorder: AccountAuthorizationRecorder) -> Self {
        Self(
            broker: {
                OAuth.AuthorizationBroker { requirement in
                    await recorder.recordRequirement(requirement)
                }
            },
            requests: {
                AsyncStream { continuation in
                    continuation.finish()
                }
            },
            signUp: { requirement, serverHost in
                try await recorder.recordSignUp(
                    requirement,
                    signUpServerConfiguration: OAuthSignUpServerConfiguration(
                        defaultServerHost: serverHost
                    )
                )
            },
            signUpWithConfiguration: { requirement, configuration in
                try await recorder.recordSignUp(
                    requirement,
                    signUpServerConfiguration: configuration
                )
            },
            succeed: {},
            fail: { _ in },
            cancel: {
                await recorder.recordCancel()
            }
        )
    }
}
