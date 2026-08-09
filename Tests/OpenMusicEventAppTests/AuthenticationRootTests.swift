import ATProtoOAuth
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import IssueReporting
import Observation
import Sharing
import SQLiteData
import TCATProtoAuthentication
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAuthentication
@testable import OpenMusicEventWhiteLabel

@MainActor
struct AuthenticationRootTests {
    @Test
    func initialRootStateDoesNotPresentAuthorization() throws {
        let database = try makePreparedDatabase()
        let storage = makeStorage()
        let store = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            Store(
                initialState: OpenMusicEventApplication.State(storage: storage) {
                    OpenMusicEventAppRoot.State()
                }
            ) {
                OpenMusicEventApplication(storage: storage) {
                    OpenMusicEventAppRoot()
                }
                .presentAuthorizationFailures()
            }
        }

        #expect(store.authentication.authorization == nil)
        #expect(store.authentication.directAuthorization == nil)
    }

    @Test
    func genericAndWhiteLabelRootsUseTheSameSharedAuthorizationComposition() throws {
        let database = try makePreparedDatabase()
        let storage = makeStorage()
        let whiteLabel = WhiteLabelAppConfiguration(
            brand: WhiteLabelBrand(displayName: "Test Festival")
        )
        let (genericState, whiteLabelState) = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            (
                OpenMusicEventApplication.State(storage: storage) {
                    OpenMusicEventAppRoot.State(variant: .generic)
                },
                OpenMusicEventApplication.State(storage: storage) {
                    OpenMusicEventAppRoot.State(variant: .whiteLabel(whiteLabel))
                }
            )
        }

        #expect(genericState.content.variant == .generic)
        #expect(whiteLabelState.content.variant == .whiteLabel(whiteLabel))
        #expect(genericState.authentication.authorization == nil)
        #expect(whiteLabelState.authentication.authorization == nil)
    }

    @Test
    func oauthCallbackURLIsConsumedByTheSharedAuthorizationWrapper() async throws {
        let database = try makePreparedDatabase()
        let storage = makeStorage()
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.oauthBrowserStrategy = .webAuthenticationSession
        } operation: {
            Store(
                initialState: OpenMusicEventApplication.State(storage: storage) {
                    OpenMusicEventAppRoot.State()
                }
            ) {
                OpenMusicEventApplication(storage: storage) {
                    OpenMusicEventAppRoot()
                }
                .presentAuthorizationFailures()
            }
        }

        let task = store.send(
            .authentication(
                .handleOpenURL(
                    OAuth.App.CallbackURI(
                        URL(string: "app.openmusicevent:/oauth/callback?code=abc&state=def")!
                    )
                )
            )
        )
        await task?.value

        #expect(store.content.destination == nil)
    }

    @Test
    func authorizationRequestPresentsAuthorizationFlow() throws {
        let database = try makePreparedDatabase()
        let storage = makeStorage()
        let store = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            Store(
                initialState: OpenMusicEventApplication.State(storage: storage) {
                    OpenMusicEventAppRoot.State()
                }
            ) {
                OpenMusicEventApplication(storage: storage) {
                    OpenMusicEventAppRoot()
                }
                .presentAuthorizationFailures()
            }
        }

        store.send(
            .authentication(
                .authorizationRequestChanged(
                    AuthorizationRequestCenter.Request(
                        id: UUID(0),
                        requirement: OpenMusicEventOAuth.baseAuthRequirement
                    )
                )
            )
        )

        #expect(
            store.authentication.authorization?.requirement
                == OpenMusicEventOAuth.baseAuthRequirement
        )
    }

    @Test
    func authorizationFlowErrorIsReportedThroughRootErrorHandling() async throws {
        let database = try makePreparedDatabase()
        let storage = makeStorage()
        let failure = AuthenticationRootTestError.invalidScope
        let store = withDependencies {
            $0.defaultDatabase = database
            $0[OAuth.Client.self] = failingOAuthClient(failure)
            $0.oauthAppManifest = OpenMusicEventOAuth.appManifest
        } operation: {
            var state = OpenMusicEventApplication.State(storage: storage) {
                OpenMusicEventAppRoot.State()
            }
            state.authentication.directAuthorization = OpenMusicEventOAuth.authorizationFlowState(
                for: AuthorizationPresentationRequest(
                    loginHint: "woody.fm",
                    startsImmediately: true,
                    requirement: OpenMusicEventOAuth.baseAuthRequirement
                )
            )
            return Store(initialState: state) {
                OpenMusicEventApplication(storage: storage) {
                    OpenMusicEventAppRoot()
                }
                .presentAuthorizationFailures()
            }
        }

        await withIssueReporters([]) {
            let task = store.send(.authentication(.directAuthorization(.submit)))
            await task?.value
        }

        await waitForCondition {
            store.authentication.authorizationFailure != nil
        }
        await waitForCondition {
            store.content.errorNotifications.state.latestError != nil
        }
        expectNoDifference(
            store.content.errorNotifications.state.latestError?.message.fallback,
            "Unable to authorize account."
        )
        expectNoDifference(
            store.content.errorNotifications.state.latestError?.operation.rawValue,
            "auth.authorization"
        )
    }

    @Test
    func nonOAuthURLIsNotTreatedAsAuthenticationCallback() {
        #expect(
            !OpenMusicEventOAuth.isCallbackURL(
                URL(string: "app.openmusicevent:/organizers/demo/events/event")!
            )
        )
    }

    private func makePreparedDatabase() throws -> any DatabaseWriter {
        try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            @Dependency(\.defaultDatabase) var database
            return database
        }
    }

    private func makeStorage() -> OAuthSessionStorage {
        OAuthSessionStorage(
            sessionStore: Shared(value: OAuth.SessionStore()),
            authFailureMessage: Shared(value: nil),
            selectedSessionID: Shared(value: nil)
        )
    }
}

private enum AuthenticationRootTestError: Equatable, Error {
    case invalidScope
}

private func failingOAuthClient(_ failure: any Error) -> OAuth.Client {
    var client = OAuth.Client()
    client.beginAuthorizationWithPermissions = { _, _ in
        throw failure
    }
    return client
}

@MainActor
private func waitForCondition(
    _ condition: @escaping @MainActor () -> Bool
) async {
    while !condition() {
        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = condition()
            } onChange: {
                continuation.resume()
            }
        }
    }
}
