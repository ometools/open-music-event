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
    func `recording a proposal preserves the workspace baseline`() async throws {
        let database = try makeDatabase()
        let workspace = try makeWorkspace()
        let proposal = makeProposal()
        let patch = makePatch()
        let persistence = WorkspacePublicationPersistence(database: database)
        let attempt = WorkspaceProposalAttempt(
            changes: patch,
            details: WorkspaceProposalDetails(
                title: try #require(WorkspaceProposalTitle("Improve the source"))
            ),
            target: proposal.target
        )
        let checkpoint = try await persistence.checkpoint(
            workspaceID: workspace.id,
            attempt: attempt
        )
        try await persistence.installBaseline(
            proposal.target,
            workspaceID: workspace.id
        )

        try await persistence.savePublishedProposal(
            proposal,
            checkpoint: checkpoint,
            workspaceID: workspace.id
        )

        let receiptsAfterRecording = try await receipts(
            workspaceID: workspace.id,
            database: database
        )
        expectNoDifference(try persistence.baseline(workspace.id), proposal.target)
        expectNoDifference(receiptsAfterRecording, [proposal])
        expectNoDifference(try persistence.checkpoint(workspace.id), checkpoint)

        try await persistence.completePublication(workspaceID: workspace.id)

        let receiptsAfterCompletion = try await receipts(
            workspaceID: workspace.id,
            database: database
        )
        expectNoDifference(try persistence.baseline(workspace.id), proposal.target)
        expectNoDifference(receiptsAfterCompletion, [proposal])
        expectNoDifference(try persistence.checkpoint(workspace.id), nil)
    }

    @Test
    func `a publication retry reuses only the same frozen creation`() async throws {
        let database = try makeDatabase()
        let workspace = try makeWorkspace()
        let persistence = WorkspacePublicationPersistence(database: database)
        let attempt = WorkspaceProposalAttempt(
            changes: makePatch(),
            details: WorkspaceProposalDetails(
                title: try #require(WorkspaceProposalTitle("Retry this publication"))
            ),
            target: makeProposal().target
        )

        let first = try await persistence.checkpoint(
            workspaceID: workspace.id,
            attempt: attempt
        )
        let retry = try await persistence.checkpoint(
            workspaceID: workspace.id,
            attempt: attempt
        )
        expectNoDifference(retry, first)

        let distinctAttempt = WorkspaceProposalAttempt(
            changes: attempt.changes,
            details: WorkspaceProposalDetails(
                title: try #require(WorkspaceProposalTitle("A distinct proposal"))
            ),
            target: attempt.target
        )
        let distinct = try await persistence.checkpoint(
            workspaceID: workspace.id,
            attempt: distinctAttempt
        )
        #expect(distinct.id != first.id)
    }

    @Test
    func `pre-record checkpoint survives authoring deactivation`() async throws {
        let database = try makeDatabase()
        let workspace = try makeWorkspace()
        let checkpoint = WorkspacePublicationCheckpoint(
            attempt: WorkspaceProposalAttempt(
                changes: makePatch(),
                details: WorkspaceProposalDetails(
                    title: try #require(WorkspaceProposalTitle("Retry me"))
                ),
                target: makeProposal().target
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
            try persisted.map {
                try decode(WorkspacePublicationCheckpoint.self, from: $0.submissionData!)
            },
            checkpoint
        )
    }

    @Test
    func `reconciliation repoints the checkpoint and invalidates prepared publication`() async throws {
        let database = try makeDatabase()
        let workspace = try makeWorkspace()
        let persistence = WorkspacePublicationPersistence(database: database)
        let oldTarget = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "c6dbc")
        )
        let newTarget = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "9f569")
        )
        let attempt = WorkspaceProposalAttempt(
            changes: makePatch(),
            details: WorkspaceProposalDetails(
                title: try #require(WorkspaceProposalTitle("Reconcile this publication"))
            ),
            target: oldTarget
        )

        let checkpoint = try await persistence.checkpoint(
            workspaceID: workspace.id,
            attempt: attempt
        )
        try await persistence.reconcileCheckpoint(
            workspaceID: workspace.id,
            attempt: attempt,
            target: newTarget
        )

        let reconciled = try #require(try persistence.checkpoint(workspace.id))
        #expect(reconciled.id == checkpoint.id)
        #expect(reconciled.changes == attempt.changes)
        #expect(reconciled.target == newTarget)
        #expect(try persistence.preparedPublication(
            workspaceID: workspace.id,
            checkpointID: checkpoint.id
        ) == nil)
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

    private func receipts(
        workspaceID: SourceWorkspace.ID,
        database: any DatabaseWriter
    ) async throws -> [WorkspaceProposal] {
        try await database.read { db in
            try SourceWorkspaceProposalReceiptsRequest(workspaceID: workspaceID).fetch(db)
        }
    }
}
