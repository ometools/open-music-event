import ComposableArchitecture2
import Dependencies
import Foundation
import SQLiteData
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
