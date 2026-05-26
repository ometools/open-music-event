import ATProtoOAuth
import ComposableArchitecture2
import Testing

@testable import OpenMusicEventAuthentication

@MainActor
@Suite("Account", .serialized)
struct AccountTests {
    @Test
    func loginButtonRequestsBaseAuthorization() async {
        OpenMusicEventOAuth.resetStoredSession()
        let recorder = AccountAuthorizationRecorder()
        let store = withDependencies {
            $0.openMusicEventAuthorizationRequests = .recording(recorder)
        } operation: {
            Store(initialState: Account.State()) {
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
    func logoutClearsStoredSessionAndCancelsRequests() async {
        OpenMusicEventOAuth.resetStoredSession()
        let recorder = AccountAuthorizationRecorder()
        let state = Account.State()
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

private actor AccountAuthorizationRecorder {
    private(set) var didCancel = false
    private(set) var requirements: [OAuth.AuthRequirement] = []

    func recordCancel() {
        didCancel = true
    }

    func recordRequirement(_ requirement: OAuth.AuthRequirement) {
        requirements.append(requirement)
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
            succeed: {},
            fail: { _ in },
            cancel: {
                await recorder.recordCancel()
            }
        )
    }
}
