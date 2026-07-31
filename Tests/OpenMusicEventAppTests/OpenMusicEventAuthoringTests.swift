import ATProto
import ATProtoOAuth
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
import Synchronization
import TCATProtoAuthentication
import Testing

@testable import OpenMusicEventApp

@MainActor
@Suite("Open Music Event authoring context")
struct OpenMusicEventAuthoringTests {
    @Test
    func signedOutTeamEntryRequestsOnlyBaseSignIn() async throws {
        let database = try makePreparedDatabase()
        let ownerID = try #require(DID("did:plc:workspace-owner"))
        let workspace = teamWorkspace("signed-out", ownerID: ownerID)
        try await insert(workspace, into: database)
        let recorder = AuthorizationRequirementRecorder()

        let policy = AuthoringPolicyClient.openMusicEvent
        let admission = try await withDependencies {
            $0.defaultDatabase = database
            $0.getOptionalDefaultSession = { nil }
            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { requirement in
                await recorder.record(requirement)
            }
        } operation: {
            let admission = try await policy.admission(workspace.id)
            try await policy.requestSignIn()
            return admission
        }

        expectNoDifference(admission, .signInRequired)
        let recordedRequirements = await recorder.requirements
        expectNoDifference(
            recordedRequirements,
            [OpenMusicEventOAuth.baseAuthRequirement]
        )
    }

    @Test
    func workspaceOwnerIsAdmittedWithoutActionPermissionUpgrade() async throws {
        let session = testSession(
            permissions: OpenMusicEventOAuth.appManifest.basePermissions.permissions
        )
        let ownerID = try #require(DID(session.accountID.rawValue.description))
        let database = try makePreparedDatabase()
        let workspace = teamWorkspace("owner", ownerID: ownerID)
        try await insert(workspace, into: database)

        let admission = try await withDependencies {
            $0.defaultDatabase = database
            $0.getOptionalDefaultSession = { session }
            $0.tangledRepositoryMembership = .init { _, expectedOwnerID, actorID in
                expectedOwnerID == ownerID && actorID == ownerID
            }
        } operation: {
            try await AuthoringPolicyClient.openMusicEvent.admission(workspace.id)
        }

        expectNoDifference(
            admission,
            .granted(principal: .actor(ownerID), role: .owner)
        )
    }

    @Test
    func workspaceOwnerIsDeniedWhenTheRepositoryOwnerDoesNotMatch() async throws {
        let session = testSession(
            permissions: OpenMusicEventOAuth.appManifest.basePermissions.permissions
        )
        let workspaceOwnerID = try #require(DID(session.accountID.rawValue.description))
        let repositoryOwnerID = try #require(DID("did:plc:different-repository-owner"))
        let database = try makePreparedDatabase()
        let workspace = teamWorkspace("owner-mismatch", ownerID: workspaceOwnerID)
        try await insert(workspace, into: database)

        let admission = try await withDependencies {
            $0.defaultDatabase = database
            $0.getOptionalDefaultSession = { session }
            $0.tangledRepositoryMembership = .init { _, expectedOwnerID, actorID in
                expectedOwnerID == repositoryOwnerID && actorID == repositoryOwnerID
            }
        } operation: {
            try await AuthoringPolicyClient.openMusicEvent.admission(workspace.id)
        }

        expectNoDifference(admission, .denied)
    }

    @Test
    func tangledCollaboratorIsAdmittedWithProposalAndMergeCapabilities() async throws {
        let session = testSession(
            permissions: OpenMusicEventOAuth.appManifest.basePermissions.permissions
        )
        let collaboratorID = try #require(DID(session.accountID.rawValue.description))
        let ownerID = try #require(DID("did:plc:workspace-owner"))
        let database = try makePreparedDatabase()
        let workspace = teamWorkspace("collaborator", ownerID: ownerID)
        try await insert(workspace, into: database)

        let admission = try await withDependencies {
            $0.defaultDatabase = database
            $0.getOptionalDefaultSession = { session }
            $0.tangledRepositoryMembership = .init { _, expectedOwnerID, actorID in
                expectedOwnerID == ownerID && actorID == collaboratorID
            }
        } operation: {
            try await AuthoringPolicyClient.openMusicEvent.admission(workspace.id)
        }

        expectNoDifference(
            admission,
            .granted(
                principal: .actor(collaboratorID),
                role: .collaborator([.propose, .merge])
            )
        )
    }

    @Test
    func tangledCollaboratorDoesNotRequireASourceRosterRelationship() async throws {
        let session = testSession(
            permissions: OpenMusicEventOAuth.appManifest.basePermissions.permissions
        )
        let collaboratorID = try #require(DID(session.accountID.rawValue.description))
        let database = try makePreparedDatabase()
        let workspace = teamWorkspace(
            "tangled-only",
            ownerID: try #require(DID("did:plc:other-owner"))
        )
        try await insert(workspace, into: database)

        let admission = try await withDependencies {
            $0.defaultDatabase = database
            $0.getOptionalDefaultSession = { session }
            $0.tangledRepositoryMembership = .init { _, _, _ in true }
        } operation: {
            try await AuthoringPolicyClient.openMusicEvent.admission(workspace.id)
        }

        expectNoDifference(
            admission,
            .granted(
                principal: .actor(collaboratorID),
                role: .collaborator([.propose, .merge])
            )
        )
    }

    @Test
    func workspaceOwnerWithoutTangledMembershipIsDenied() async throws {
        let session = testSession(
            permissions: OpenMusicEventOAuth.appManifest.basePermissions.permissions
        )
        let ownerID = try #require(DID(session.accountID.rawValue.description))
        let database = try makePreparedDatabase()
        let workspace = teamWorkspace("ome-only", ownerID: ownerID)
        try await insert(workspace, into: database)

        let admission = try await withDependencies {
            $0.defaultDatabase = database
            $0.getOptionalDefaultSession = { session }
            $0.tangledRepositoryMembership = .init { _, _, _ in false }
        } operation: {
            try await AuthoringPolicyClient.openMusicEvent.admission(workspace.id)
        }

        expectNoDifference(admission, .denied)
    }

    @Test
    func repositoryMembershipLookupFailureIsPropagated() async throws {
        let session = testSession(
            permissions: OpenMusicEventOAuth.appManifest.basePermissions.permissions
        )
        let ownerID = try #require(DID(session.accountID.rawValue.description))
        let database = try makePreparedDatabase()
        let workspace = teamWorkspace("lookup-failure", ownerID: ownerID)
        try await insert(workspace, into: database)

        await #expect(throws: RepositoryMembershipLookupFailure.self) {
            try await withDependencies {
                $0.defaultDatabase = database
                $0.getOptionalDefaultSession = { session }
                $0.tangledRepositoryMembership = .init { _, _, _ in
                    throw RepositoryMembershipLookupFailure()
                }
            } operation: {
                try await AuthoringPolicyClient.openMusicEvent.admission(workspace.id)
            }
        }
    }

    @Test
    func malformedTangledSourceIsDeniedWithoutMembershipLookup() async throws {
        let session = testSession(
            permissions: OpenMusicEventOAuth.appManifest.basePermissions.permissions
        )
        let ownerID = try #require(DID(session.accountID.rawValue.description))
        let database = try makePreparedDatabase()
        let workspace = teamWorkspace("malformed-source", ownerID: ownerID)
        var baseline = try sourceBaseline(for: workspace)
        baseline.sourceReference = "not-a-repository-reference"
        let malformedBaseline = baseline
        try await database.write { db in
            try SourceBaselineRecord.insert { malformedBaseline }.execute(db)
            try EditingWorkspaceRecord.insert { workspace }.execute(db)
        }

        let admission = try await withDependencies {
            $0.defaultDatabase = database
            $0.getOptionalDefaultSession = { session }
            $0.tangledRepositoryMembership = .init { _, _, _ in
                Issue.record("Malformed source must fail before membership lookup")
                return true
            }
        } operation: {
            try await AuthoringPolicyClient.openMusicEvent.admission(workspace.id)
        }

        expectNoDifference(admission, .denied)
    }

    @Test
    func localEntryProducesNoOAuthRequest() async throws {
        let database = try makePreparedDatabase()
        let workspace = localWorkspace("local")
        try await insert(workspace, into: database)
        let recorder = AuthorizationRequirementRecorder()

        let admission = try await withDependencies {
            $0.defaultDatabase = database
            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { requirement in
                await recorder.record(requirement)
            }
        } operation: {
            try await AuthoringPolicyClient.openMusicEvent.admission(workspace.id)
        }

        expectNoDifference(admission, .granted(principal: .local, role: .owner))
        let recordedRequirements = await recorder.requirements
        expectNoDifference(recordedRequirements, [])
    }

    @Test
    func authorizationLossKeepsTheWorkspaceAuthoringGrant() async throws {
        let database = try makePreparedDatabase()
        let session = testSession(
            permissions: OpenMusicEventOAuth
                .tangledPullRequestWorkflowAuthRequirement
                .permissions
        )
        let actorID = try #require(DID(session.accountID.rawValue.description))
        let workspace = teamWorkspace("invalidation", ownerID: actorID)
        try await insert(workspace, into: database)
        let storage = testStorage(session: session)
        let editingWorkspace = EditingWorkspace(
            id: workspace.id,
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: database)
        )
        let admissionRequests = Mutex<[EditingWorkspaceRecord.ID]>([])
        let grant = Shared<AuthoringGrant?>(
            value: AuthoringGrant(
                principal: .actor(actorID),
                role: .owner,
                workspace: editingWorkspace
            )
        )
        let store = withDependencies {
            $0.defaultDatabase = database
            $0[AuthoringPolicyClient.self] = AuthoringPolicyClient { workspaceID in
                admissionRequests.withLock { $0.append(workspaceID) }
                return .signInRequired
            }
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
                .refreshingAuthoringAdmissionWhenAuthorizationChanges()
            }
        }

        #expect(store.content.access.canEditContent)
        await store.send(.authentication(.resetAuthentication))?.value
        try await waitForCondition {
            store.authentication.session == nil
        }
        #expect(store.content.access.canEditContent)
        #expect(grant.wrappedValue != nil)
        expectNoDifference(admissionRequests.withLock { $0 }, [])
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
        let baseline: SourceBaselineRecord?
        if workspace.kind == .team {
            baseline = try sourceBaseline(for: workspace)
        } else {
            baseline = nil
        }
        try await database.write { db in
            if let baseline {
                try SourceBaselineRecord.insert { baseline }.execute(db)
            }
            try EditingWorkspaceRecord.insert { workspace }.execute(db)
        }
    }

    private func sourceBaseline(
        for workspace: EditingWorkspaceRecord
    ) throws -> SourceBaselineRecord {
        SourceBaselineRecord(
            id: try #require(workspace.sourceBaselineID),
            sourceKind: .tangled,
            sourceReference: "tangled.org/did:plc:repository/source",
            ref: "main",
            databaseFileName: workspace.databaseFileName,
            importedAt: workspace.createdAt
        )
    }

    private func teamWorkspace(
        _ name: String,
        ownerID: DID
    ) -> EditingWorkspaceRecord {
        EditingWorkspaceRecord(
            id: .init(rawValue: "team.\(name)"),
            kind: .team,
            databaseFileName: "\(name).sqlite",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            sourceBaselineID: SourceBaselineRecord.ID(rawValue: "baseline.\(name)"),
            publicRecord: OME.Relationship.RecordReference(
                author: ownerID,
                collection: OME.SourceRecord.nsid,
                rkey: ATProto.Record.Key(rawValue: OME.SourceRecord.canonicalRecordKey)
            )
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

private struct RepositoryMembershipLookupFailure: Error {}

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

@MainActor
private func waitForCondition(
    _ condition: @escaping @MainActor () -> Bool
) async throws {
    for _ in 0..<100 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(condition())
}
