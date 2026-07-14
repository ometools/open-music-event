import ATProtoOAuth
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import IssueReporting
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
        let store = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: OpenMusicEventAppRoot.State()) {
                OpenMusicEventAppRoot()
            }
        }

        #expect(store.authentication.authorization == nil)
    }

    @Test
    func oauthCallbackURLIsConsumedByAuthentication() async throws {
        let database = try makePreparedDatabase()
        let store = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: OpenMusicEventAppRoot.State()) {
                OpenMusicEventAppRoot()
            }
        }

        let task = store.send(
            .openURL(URL(string: "app.openmusicevent:/oauth/callback?code=abc&state=def")!)
        )
        await task?.value

        #expect(store.eventViewer == nil)
    }

    @Test
    func authorizationFlowErrorIsReportedThroughRootErrorHandling() async throws {
        let database = try makePreparedDatabase()
        let failure = AuthenticationRootTestError.invalidScope
        let store = withDependencies {
            $0.defaultDatabase = database
            $0[OAuth.Client.self] = failingOAuthClient(failure)
            $0.oauthAppManifest = OpenMusicEventOAuth.appManifest
        } operation: {
            var state = OpenMusicEventAppRoot.State()
            state.authentication.directAuthorization = OpenMusicEventOAuth.authorizationFlowState(
                for: AuthorizationPresentationRequest(
                    loginHint: "woody.fm",
                    startsImmediately: true,
                    requirement: OpenMusicEventOAuth.baseAuthRequirement
                )
            )
            return Store(initialState: state) {
                OpenMusicEventAppRoot()
            }
        }

        await withIssueReporters([]) {
            let task = store.send(.authentication(.directAuthorization(.submit)))
            await task?.value
        }

        expectNoDifference(
            store.errorNotifications.state.latestError?.message.fallback,
            "Unable to authorize account."
        )
        expectNoDifference(
            store.errorNotifications.state.latestError?.operation.rawValue,
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
