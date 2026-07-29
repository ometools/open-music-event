import ATProto
import ATProtoOAuth
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
import TCATProtoAuthentication
import Testing

@testable import OpenMusicEventApp

@MainActor
@Suite("Open Music Event authoring context")
struct OpenMusicEventAuthoringTests {
    @Test
    func signedOutTeamEntryProducesOneCombinedAuthorization() async throws {
        let database = try makePreparedDatabase()
        let workspace = teamWorkspace("signed-out")
        try await insert(workspace, into: database)
        let recorder = AuthorizationRequirementRecorder()

        let capabilities = try await withDependencies {
            $0.defaultDatabase = database
            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { requirement in
                await recorder.record(requirement)
            }
        } operation: {
            try await AuthoringPolicyClient.openMusicEvent.authorize(workspace.id)
        }

        expectNoDifference(capabilities, [.editContent])
        let recordedRequirements = await recorder.requirements
        expectNoDifference(
            recordedRequirements,
            [OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement]
        )
    }

    @Test
    func baseTokenTeamEntryProducesOneCombinedUpgrade() async throws {
        let session = testSession(
            permissions: OpenMusicEventOAuth.appManifest.basePermissions.permissions
        )
        let storage = testStorage(session: session)
        let center = AuthorizationRequestCenter()
        let requests = OAuthAuthorizationRequests(center: center)
            .automaticallyUpgradingCurrentAccount(storage: storage)
        let stream = await center.requests()
        var iterator = stream.makeAsyncIterator()
        let authorization = Task {
            try await withDependencies {
                $0.oauthAppManifest = OpenMusicEventOAuth.appManifest
            } operation: {
                try await requests.broker().authorize(
                    OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement
                )
            }
        }

        var request = await iterator.next() ?? nil
        if request == nil {
            request = await iterator.next() ?? nil
        }
        let activeRequest = try #require(request)
        #expect(activeRequest.startsImmediately)
        #expect(activeRequest.loginHint == session.accountID.rawValue.description)
        #expect(
            activeRequest.requirement
                == OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement
        )

        await center.cancel()
        await #expect(throws: CancellationError.self) {
            try await authorization.value
        }
    }

    @Test
    func alreadyAuthorizedTeamEntryProducesNoPresentation() async throws {
        let session = testSession(
            permissions: OpenMusicEventOAuth
                .tangledPullRequestWorkflowAuthRequirement
                .permissions
        )
        let storage = testStorage(session: session)
        let center = AuthorizationRequestCenter()
        let requests = OAuthAuthorizationRequests(center: center)
            .automaticallyUpgradingCurrentAccount(storage: storage)

        try await withDependencies {
            $0.oauthAppManifest = OpenMusicEventOAuth.appManifest
        } operation: {
            try await requests.broker().authorize(
                OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement
            )
        }

        let stream = await center.requests()
        var iterator = stream.makeAsyncIterator()
        let activeRequest = await iterator.next() ?? nil
        #expect(activeRequest == nil)
    }

    @Test
    func localEntryProducesNoOAuthRequest() async throws {
        let database = try makePreparedDatabase()
        let workspace = localWorkspace("local")
        try await insert(workspace, into: database)
        let recorder = AuthorizationRequirementRecorder()

        let capabilities = try await withDependencies {
            $0.defaultDatabase = database
            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { requirement in
                await recorder.record(requirement)
            }
        } operation: {
            try await AuthoringPolicyClient.openMusicEvent.authorize(workspace.id)
        }

        expectNoDifference(capabilities, [.editContent])
        let recordedRequirements = await recorder.requirements
        expectNoDifference(recordedRequirements, [])
    }

    @Test
    func authorizationLossClearsTheWorkspaceAuthoringGrant() async throws {
        let database = try makePreparedDatabase()
        let workspace = teamWorkspace("invalidation")
        try await insert(workspace, into: database)
        let session = testSession(
            permissions: OpenMusicEventOAuth
                .tangledPullRequestWorkflowAuthRequirement
                .permissions
        )
        let storage = testStorage(session: session)
        let workspaceContext = WorkspaceContext(
            id: workspace.id,
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: database)
        )
        let grant = Shared<AuthoringGrant?>(
            value: AuthoringGrant(
                capabilities: [.editContent],
                workspace: workspaceContext
            )
        )
        let store = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            Store(
                initialState: OpenMusicEventAuthoring<AuthoringProbe>.State(
                    storage: storage
                ) {
                    Authoring<AuthoringProbe>.State(
                        workspaceID: workspace.id,
                        grant: grant
                    ) {
                        AuthoringProbe.State()
                    }
                }
            ) {
                OpenMusicEventAuthoring(storage: storage) {
                    Authoring {
                        AuthoringProbe()
                    }
                }
                .invalidatingAuthoringWhenAuthorizationIsLost()
            }
        }

        #expect(store.content.access.canEditContent)
        await store.send(.authentication(.resetAuthentication))?.value
        try await waitForCondition {
            grant.wrappedValue == nil
        }
        #expect(!store.content.access.canEditContent)
        #expect(grant.wrappedValue == nil)
    }

    @Test
    func authoringWrapperForwardsContentIdentity() throws {
        let database = try makePreparedDatabase()
        let workspace = localWorkspace("identity")
        let state = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            Authoring<AuthoringIdentityProbe>.State(workspaceID: workspace.id) {
                AuthoringIdentityProbe.State(id: 42)
            }
        }

        #expect(state.id == 42)
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

    private func insert(
        _ workspace: EditingWorkspaceRecord,
        into database: any DatabaseWriter
    ) async throws {
        try await database.write { db in
            try EditingWorkspaceRecord.insert { workspace }.execute(db)
        }
    }

    private func teamWorkspace(_ name: String) -> EditingWorkspaceRecord {
        EditingWorkspaceRecord(
            id: .init(rawValue: "team.\(name)"),
            kind: .team,
            databaseFileName: "\(name).sqlite",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func localWorkspace(_ name: String) -> EditingWorkspaceRecord {
        EditingWorkspaceRecord(
            id: .init(rawValue: "local.\(name)"),
            kind: .local,
            databaseFileName: "\(name).sqlite",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}

@Feature
private struct AuthoringProbe {
    struct State {}
    enum Action {}
}

@Feature
private struct AuthoringIdentityProbe {
    struct State: Identifiable {
        let id: Int
    }

    enum Action {}
}

private actor AuthorizationRequirementRecorder {
    private(set) var requirements: [OAuth.AuthRequirement] = []

    func record(_ requirement: OAuth.AuthRequirement) {
        requirements.append(requirement)
    }
}

private func testSession(permissions: Set<OAuth.Permission>) -> OAuth.Session {
    var session = OAuth.Session.placeholder
    var granted: Set<OAuth.Permission> = [.atproto]
    granted.formUnion(permissions)
    session.scope = OAuth.Scope(
        rawValue: granted
            .map(\.rawValue)
            .sorted()
            .joined(separator: " ")
    )
    return session
}

private func testStorage(session: OAuth.Session) -> OAuthSessionStorage {
    var sessionStore = OAuth.SessionStore()
    sessionStore.upsert(session)
    return OAuthSessionStorage(
        sessionStore: Shared(value: sessionStore),
        authFailureMessage: Shared(value: nil),
        selectedSessionID: Shared(value: session.accountID)
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
