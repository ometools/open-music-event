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
import XRPCClient

@testable import OpenMusicEventApp

@MainActor
@Suite("Open Music Event authoring context")
struct OpenMusicEventAuthoringTests {
    @Test
    func signedOutTeamEntryRequestsCompleteWorkflowAuthorization() async throws {
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
            [OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement]
        )
    }

    @Test
    func signedInTeamEntryRequestsCompleteWorkflowAuthorization() async throws {
        let recorder = AuthorizationRequirementRecorder()
        let actorID = try #require(DID("did:plc:workspace-owner"))

        try await withDependencies {
            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { requirement in
                await recorder.record(requirement)
            }
        } operation: {
            try await AuthoringPolicyClient.openMusicEvent.authorizeEntry(
                EditingWorkspaceRecord.ID(rawValue: "team-workspace"),
                .actor(actorID)
            )
        }

        let recordedRequirements = await recorder.requirements
        expectNoDifference(
            recordedRequirements,
            [OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement]
        )
    }

    @Test
    func requiredXRPCPermissionStillUpgradesAndResumes() async throws {
        let initialSession = testSession(
            permissions: OpenMusicEventOAuth.appManifest.basePermissions.permissions
        )
        let upgradedSession = testSession(
            permissions: OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement
                .permissions
        )
        let selectedSession = Mutex(initialSession)
        let recordedRequirements = Mutex([OAuth.AuthRequirement]())
        let operationCount = Mutex(0)
        let operation: @Sendable () async throws -> Data? = {
            operationCount.withLock { $0 += 1 }
            return Data("resumed".utf8)
        }

        let result = try await withDependencies {
            OpenMusicEventOAuth.prepareDependencies(&$0)
            $0.getDefaultSession = { selectedSession.withLock { $0 } }
            $0.getOptionalDefaultSession = { selectedSession.withLock { $0 } }
            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { requirement in
                recordedRequirements.withLock { $0.append(requirement) }
                selectedSession.withLock { $0 = upgradedSession }
            }
        } operation: {
            @Dependency(\.xrpcAuthorizationGate) var authorizationGate
            return try await authorizationGate.run(
                policy: .required(OpenMusicEventOAuth.tangledPublicKeyAuthRequirement),
                routing: XRPC.Routing(),
                operation: operation
            )
        }

        expectNoDifference(try #require(result), Data("resumed".utf8))
        expectNoDifference(
            recordedRequirements.withLock { $0 },
            [OpenMusicEventOAuth.tangledPublicKeyAuthRequirement]
        )
        expectNoDifference(operationCount.withLock { $0 }, 1)
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
        try await insertRelationship(
            workspace: workspace,
            actorID: collaboratorID,
            capabilities: [.propose, .merge],
            into: database
        )

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
    func tangledMembershipDoesNotReplaceTheWorkspaceRelationship() async throws {
        let session = testSession(
            permissions: OpenMusicEventOAuth.appManifest.basePermissions.permissions
        )
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
            .denied
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
            let policy = AuthoringPolicyClient.openMusicEvent
            let admission = try await policy.admission(workspace.id)
            try await policy.authorizeEntry(workspace.id, .local)
            return admission
        }

        expectNoDifference(admission, .granted(principal: .local, role: .owner))
        let recordedRequirements = await recorder.requirements
        expectNoDifference(recordedRequirements, [])
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

    private func insertRelationship(
        workspace: EditingWorkspaceRecord,
        actorID: DID,
        capabilities: Set<OME.WorkspaceRole.Capability>,
        into database: any DatabaseWriter
    ) async throws {
        let relationship = WorkspaceRelationshipRecord(
            id: .init(workspaceID: workspace.id, actorID: actorID),
            recordKey: WorkspaceRelationshipRecord.recordKey(for: actorID),
            relationship: OME.Relationship(
                subject: .identity(did: actorID, handle: nil),
                role: .collaborator(capabilities),
                object: .record(try #require(workspace.publicRecord)),
                createdAt: "2026-08-02T00:00:00Z"
            )
        )
        try await database.write { db in
            try WorkspaceRelationshipRecord.insert { relationship }.execute(db)
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
            databaseFileName: workspace.referenceDatabaseFileName,
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
            referenceDatabaseFileName: "\(name).sqlite",
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
            referenceDatabaseFileName: "\(name).sqlite",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
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
