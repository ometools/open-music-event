import ComposableWorkspace
import CustomDump
import Foundation
import GRDB
import OpenMusicEventDatabase
import OpenMusicEventLexicon
@testable import OpenMusicEventSourceEditing
import SQLiteData
import SourceEditing
import Testing

@Suite("Workspace publication persistence", .serialized)
struct WorkspacePublicationTests {
    @Test
    func recordReceiptAndRepairCommitTogetherAndRepairCompletesIndependently() async throws {
        let database = try makeDatabase()
        let workspace = try makeWorkspace()
        let proposal = makeProposal()
        let patch = makePatch()
        let persistence = WorkspacePublicationPersistence(database: database)

        try await database.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_workspace_proposal_repair
                BEFORE INSERT ON sourceWorkspaceProposalRepairs
                BEGIN
                  SELECT RAISE(ABORT, 'repair rejected');
                END
                """)
        }

        await #expect(throws: (any Error).self) {
            try await persistence.saveReceiptAndRepair(
                proposal: proposal,
                patch: patch,
                workspaceID: workspace.id
            )
        }

        let rolledBack = try await publicationState(
            workspaceID: workspace.id,
            database: database
        )
        expectNoDifference(rolledBack.receipts, [])
        expectNoDifference(rolledBack.repair, nil)

        try await database.write { db in
            try db.execute(sql: "DROP TRIGGER reject_workspace_proposal_repair")
        }
        try await persistence.saveReceiptAndRepair(
            proposal: proposal,
            patch: patch,
            workspaceID: workspace.id
        )

        let recorded = try await publicationState(
            workspaceID: workspace.id,
            database: database
        )
        expectNoDifference(recorded.receipts, [proposal])
        expectNoDifference(
            recorded.repair,
            SourceWorkspaceProposalRepair(proposal: proposal, patch: patch)
        )

        try await persistence.completeRepair(workspaceID: workspace.id)

        let completed = try await publicationState(
            workspaceID: workspace.id,
            database: database
        )
        expectNoDifference(completed.receipts, [proposal])
        expectNoDifference(completed.repair, nil)
    }

    @Test
    func proposalContextMovesEveryMainDatabasePointerAtomically() async throws {
        let database = try makeDatabase()
        let workspace = try makeWorkspace()
        let proposal = makeProposal()
        let persistence = WorkspacePublicationPersistence(database: database)

        try await database.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_workspace_proposal_context
                BEFORE INSERT ON sourceWorkspaceContexts
                BEGIN
                  SELECT RAISE(ABORT, 'context rejected');
                END
                """)
        }

        await #expect(throws: (any Error).self) {
            try await persistence.saveProposalContext(
                proposal,
                workspaceID: workspace.id
            )
        }

        let rolledBack = try await mountedState(
            workspaceID: workspace.id,
            database: database
        )
        expectNoDifference(rolledBack.installation, nil)
        expectNoDifference(rolledBack.selection, nil)
        expectNoDifference(rolledBack.context, nil)

        try await database.write { db in
            try db.execute(sql: "DROP TRIGGER reject_workspace_proposal_context")
        }
        try await persistence.saveProposalContext(
            proposal,
            workspaceID: workspace.id
        )

        let mounted = try await mountedState(
            workspaceID: workspace.id,
            database: database
        )
        expectNoDifference(
            mounted.installation,
            SourceWorkspaceInstallationRecord(
                id: workspace.id,
                revision: proposal.revision.rawValue
            )
        )
        expectNoDifference(
            mounted.selection,
            SourceWorkspaceSelectionRecord(
                id: workspace.id,
                branch: proposal.target.branch.rawValue,
                revision: proposal.revision.rawValue
            )
        )
        expectNoDifference(mounted.context, .proposal(proposal))
    }

    @Test
    func legacyOpenProposalMigratesToExactContextReceiptAndRepair() async throws {
        let database = try SQLiteData.defaultDatabase()
        let workspace = try makeWorkspace()
        let proposal = makeProposal()
        let patch = makePatch()
        let proposalData = try encode(proposal)
        let patchData = try encode(patch)
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(
            database,
            upTo: "Keep source workspace proposals across authoring sessions"
        )

        try await database.write { db in
            try SourceWorkspaceInstallationRecord.insert {
                SourceWorkspaceInstallationRecord(
                    id: workspace.id,
                    revision: proposal.target.revision.rawValue
                )
            }
            .execute(db)
            try SourceWorkspaceSelectionRecord.insert {
                SourceWorkspaceSelectionRecord(
                    id: workspace.id,
                    branch: proposal.target.branch.rawValue,
                    revision: proposal.target.revision.rawValue
                )
            }
            .execute(db)
            try LegacyWorkspaceOpenProposalRecord.insert {
                LegacyWorkspaceOpenProposalRecord(
                    id: workspace.id,
                    proposalData: proposalData
                )
            }
            .execute(db)
            try db.execute(
                sql: """
                    INSERT INTO "sourceWorkspacePublications" (
                      "id", "captureRequestID", "capturedChangesData", "submissionData",
                      "pushedSubmissionID", "commitData", "recordedSubmissionID",
                      "mutationData", "proposalTimestamp"
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    workspace.id.rawValue,
                    "capture-1",
                    patchData,
                    Data("submission".utf8),
                    "push-1",
                    Data("commit".utf8),
                    proposal.id.rawValue,
                    proposalData,
                    "2026-08-29T00:00:00Z",
                ]
            )
        }

        try migrator.migrate(database)

        let mounted = try await mountedState(
            workspaceID: workspace.id,
            database: database
        )
        expectNoDifference(
            mounted.installation?.revision,
            proposal.target.revision.rawValue
        )
        expectNoDifference(
            mounted.selection,
            SourceWorkspaceSelectionRecord(
                id: workspace.id,
                branch: proposal.target.branch.rawValue,
                revision: proposal.target.revision.rawValue
            )
        )
        expectNoDifference(mounted.context, .published(proposal.target))

        let publication = try await publicationState(
            workspaceID: workspace.id,
            database: database
        )
        expectNoDifference(publication.receipts, [proposal])
        expectNoDifference(
            publication.repair,
            SourceWorkspaceProposalRepair(proposal: proposal, patch: patch)
        )

        let retained = try #require(
            try await database.read { db in
                try LegacyWorkspacePublicationRecord.find(workspace.id).fetchOne(db)
            }
        )
        expectNoDifference(retained.captureRequestID, "capture-1")
        expectNoDifference(retained.capturedChangesData, patchData)
        expectNoDifference(retained.submissionData, Data("submission".utf8))
        expectNoDifference(retained.pushedSubmissionID, "push-1")
        expectNoDifference(retained.commitData, Data("commit".utf8))
        expectNoDifference(retained.recordedSubmissionID, proposal.id.rawValue)
        expectNoDifference(retained.mutationData, proposalData)
        expectNoDifference(retained.proposalTimestamp, "2026-08-29T00:00:00Z")

        try await WorkspacePublicationPersistence(database: database)
            .completeRepair(workspaceID: workspace.id)

        let cleared = try #require(
            try await database.read { db in
                try LegacyWorkspacePublicationRecord.find(workspace.id).fetchOne(db)
            }
        )
        expectNoDifference(cleared.captureRequestID, nil)
        expectNoDifference(cleared.capturedChangesData, nil)
        expectNoDifference(cleared.submissionData, nil)
        expectNoDifference(cleared.pushedSubmissionID, nil)
        expectNoDifference(cleared.commitData, nil)
        expectNoDifference(cleared.recordedSubmissionID, nil)
        expectNoDifference(cleared.mutationData, nil)
        expectNoDifference(cleared.proposalTimestamp, nil)
        let completed = try await publicationState(
            workspaceID: workspace.id,
            database: database
        )
        expectNoDifference(completed.receipts, [proposal])
        expectNoDifference(completed.repair, nil)
    }

    @Test
    func preRecordCheckpointSurvivesAuthoringDeactivation() async throws {
        let database = try makeDatabase()
        let workspace = try makeWorkspace()
        let checkpoint = WorkspacePublicationCheckpoint(
            attempt: WorkspaceProposalAttempt(
                changes: makePatch(),
                target: .createProposal(
                    target: makeProposal().target,
                    details: WorkspaceProposalDetails(
                        title: try #require(WorkspaceProposalTitle("Retry me"))
                    )
                )
            )
        )
        let checkpointData = try encode(checkpoint)

        try await database.write { db in
            try LegacyWorkspacePublicationRecord.insert {
                LegacyWorkspacePublicationRecord(
                    id: workspace.id,
                    submissionData: checkpointData
                )
            }
            .execute(db)
            try SourceWorkspaceEditingState.deactivate(workspace.id, in: db)
        }

        let persisted = try await database.read { db in
            try LegacyWorkspacePublicationRecord.find(workspace.id).fetchOne(db)
        }
        expectNoDifference(
            try persisted.map { try decode(WorkspacePublicationCheckpoint.self, from: $0.submissionData!) },
            checkpoint
        )
    }

    private func makeDatabase() throws -> any DatabaseWriter {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }

    private func makeWorkspace() throws -> SourceWorkspace {
        SourceWorkspace(
            organizerID: try #require(OME.Organizer.ID("did:plc:workspace")),
            repository: "tangled.org/example/events",
            branch: "main"
        )
    }

    private func makeProposal() -> WorkspaceProposal {
        WorkspaceProposal(
            id: WorkspaceProposalID(
                rawValue: "at://did:plc:workspace/sh.tangled.repo.pull/proposal-1"
            ),
            revision: WorkspaceRevision(rawValue: "proposal-revision"),
            target: WorkspaceBranchReference(
                branch: WorkspaceBranch(rawValue: "main"),
                revision: WorkspaceRevision(rawValue: "published-revision")
            )
        )
    }

    private func makePatch() -> SourcePatch {
        SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/example/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Before\n".utf8),
                    newContents: Data("name: After\n".utf8)
                )
            ]
        )
    }

    private func publicationState(
        workspaceID: SourceWorkspace.ID,
        database: any DatabaseWriter
    ) async throws -> (
        receipts: [WorkspaceProposal],
        repair: SourceWorkspaceProposalRepair?
    ) {
        try await database.read { db in
            (
                receipts: try SourceWorkspaceProposalReceiptsRequest(
                    workspaceID: workspaceID
                )
                .fetch(db),
                repair: try SourceWorkspaceProposalRepairRequest(
                    workspaceID: workspaceID
                )
                .fetch(db)
            )
        }
    }

    private func mountedState(
        workspaceID: SourceWorkspace.ID,
        database: any DatabaseWriter
    ) async throws -> (
        installation: SourceWorkspaceInstallationRecord?,
        selection: SourceWorkspaceSelectionRecord?,
        context: WorkspaceEditingContext?
    ) {
        try await database.read { db in
            (
                installation: try SourceWorkspaceInstallationRecord
                    .find(workspaceID)
                    .fetchOne(db),
                selection: try SourceWorkspaceSelectionRecord
                    .find(workspaceID)
                    .fetchOne(db),
                context: try WorkspaceContextRecord.find(workspaceID)
                    .fetchOne(db)
                    .map { try decode(WorkspaceEditingContext.self, from: $0.contextData) }
            )
        }
    }
}
