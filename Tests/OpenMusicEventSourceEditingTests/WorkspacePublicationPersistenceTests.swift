import ATProto
import ComposableWorkspace
import CustomDump
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceClone
import SQLiteData
import SourceEditing
import Testing

@testable import OpenMusicEventSourceEditing

@Suite("Patch-only workspace publication persistence")
struct WorkspacePublicationPersistenceTests {
    @Test
    func `restoring absent recovery state does not create an empty publication row`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let persistence = WorkspacePublicationPersistence(database: database)
        let workspaceID = SourceWorkspace.ID(rawValue: "workspace-without-recovery")
        let snapshot = try persistence.recoverySnapshot(workspaceID)
        _ = try await persistence.checkpoint(
            workspaceID: workspaceID,
            attempt: WorkspaceProposalAttempt(
                changes: SourcePatch(),
                details: WorkspaceProposalDetails(
                    title: try #require(WorkspaceProposalTitle("Temporary checkpoint"))
                ),
                target: WorkspaceBranchReference(
                    branch: WorkspaceBranch(rawValue: "main"),
                    revision: WorkspaceRevision(rawValue: "base-revision")
                )
            )
        )

        try await database.write { db in
            try persistence.restoreRecoverySnapshot(
                snapshot,
                workspaceID: workspaceID,
                in: db
            )
        }

        let restored = try await database.read { db in
            try LegacyWorkspacePublicationRecord.find(workspaceID).fetchOne(db)
        }
        #expect(restored == nil)
    }

    @Test
    func `reconciling keeps proposal details and identity while replacing transport recovery`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let persistence = WorkspacePublicationPersistence(database: database)
        let workspaceID = SourceWorkspace.ID(rawValue: "workspace-reconcile")
        let oldTarget = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "old-revision")
        )
        let newTarget = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "new-revision")
        )
        let details = WorkspaceProposalDetails(
            title: try #require(WorkspaceProposalTitle("Keep the gates open")),
            description: "Preserve this description"
        )
        let oldChanges = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/2026/event.yml",
                    kind: .modified,
                    oldContents: Data("old".utf8),
                    newContents: Data("local".utf8)
                )
            ]
        )
        let newChanges = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/2026/comms/general/gates-open.md",
                    kind: .added,
                    newContents: Data("Gates are open".utf8)
                )
            ]
        )
        let checkpoint = try await persistence.checkpoint(
            workspaceID: workspaceID,
            attempt: WorkspaceProposalAttempt(
                changes: oldChanges,
                details: details,
                target: oldTarget
            )
        )
        let prepared = TangledPatchOnlyProposalPublicationRequest(
            authorRepository: try #require(DID("did:plc:author")),
            recordKey: ATProto.Record.Key(rawValue: "ome-reconcile"),
            target: TangledPatchOnlyProposalTarget(
                repositoryDID: try #require(DID("did:plc:repository")),
                repositoryOwnerDID: try #require(DID("did:plc:owner")),
                repositoryName: "festival-source",
                knotHost: "knot.example"
            ),
            title: details.title.rawValue,
            body: details.description ?? "",
            createdAt: "2026-09-03T20:00:00Z",
            patch: TangledReplacementPatch(
                baseRevision: oldTarget.revision,
                currentRevision: WorkspaceRevision(rawValue: "prepared-revision"),
                patchText: "prepared patch",
                compressedBlob: Data([1, 2, 3])
            )
        )
        try await persistence.savePreparedPublication(
            prepared,
            workspaceID: workspaceID,
            checkpointID: checkpoint.id
        )

        try await persistence.reconcileCheckpoint(
            workspaceID: workspaceID,
            from: oldTarget,
            to: newTarget,
            changes: newChanges
        )

        let reconciled = try #require(try persistence.checkpoint(workspaceID))
        expectNoDifference(reconciled.id, checkpoint.id)
        expectNoDifference(reconciled.details, details)
        expectNoDifference(reconciled.target, newTarget)
        expectNoDifference(reconciled.changes, newChanges)
        #expect(
            try persistence.preparedPublication(
                workspaceID: workspaceID,
                checkpointID: checkpoint.id
            ) == nil
        )
    }

    @Test
    func `discard clears unpublished transport recovery and preserves proposal receipts`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let persistence = WorkspacePublicationPersistence(database: database)
        let workspaceID = SourceWorkspace.ID(rawValue: "workspace-discard")
        let target = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: "main"),
            revision: WorkspaceRevision(rawValue: "published-revision")
        )
        let details = WorkspaceProposalDetails(
            title: try #require(WorkspaceProposalTitle("Keep this proposal")),
            description: "The remote proposal remains independent of local edits."
        )
        let publishedCheckpoint = try await persistence.checkpoint(
            workspaceID: workspaceID,
            attempt: WorkspaceProposalAttempt(
                changes: SourcePatch(),
                details: details,
                target: target
            )
        )
        let proposal = WorkspaceProposal(
            id: WorkspaceProposalID(
                rawValue: "at://did:plc:author/sh.tangled.repo.pull/keep-this-proposal"
            ),
            revision: WorkspaceRevision(rawValue: "proposal-revision"),
            target: target
        )
        try await persistence.savePublishedProposal(
            proposal,
            checkpoint: publishedCheckpoint,
            workspaceID: workspaceID
        )
        try await persistence.completePublication(workspaceID: workspaceID)

        let pendingCheckpoint = try await persistence.checkpoint(
            workspaceID: workspaceID,
            attempt: WorkspaceProposalAttempt(
                changes: SourcePatch(
                    fileChanges: [
                        SourcePatchFileChange(
                            path: "events/2026/event.yml",
                            kind: .modified,
                            oldContents: Data("name: Published\n".utf8),
                            newContents: Data("name: My Changes\n".utf8)
                        )
                    ]
                ),
                details: WorkspaceProposalDetails(
                    title: try #require(WorkspaceProposalTitle("Discard this draft"))
                ),
                target: target
            )
        )
        let prepared = TangledPatchOnlyProposalPublicationRequest(
            authorRepository: try #require(DID("did:plc:author")),
            recordKey: ATProto.Record.Key(rawValue: "discard-this-draft"),
            target: TangledPatchOnlyProposalTarget(
                repositoryDID: try #require(DID("did:plc:repository")),
                repositoryOwnerDID: try #require(DID("did:plc:owner")),
                repositoryName: "festival-source",
                knotHost: "knot.example"
            ),
            title: "Discard this draft",
            body: "",
            createdAt: "2026-09-03T20:00:00Z",
            patch: TangledReplacementPatch(
                baseRevision: target.revision,
                currentRevision: WorkspaceRevision(rawValue: "discarded-revision"),
                patchText: "discarded patch",
                compressedBlob: Data([1, 2, 3])
            )
        )
        try await persistence.savePreparedPublication(
            prepared,
            workspaceID: workspaceID,
            checkpointID: pendingCheckpoint.id
        )

        try await database.write { db in
            try persistence.discardUnpublishedCheckpoint(
                workspaceID: workspaceID,
                in: db
            )
        }

        #expect(try persistence.checkpoint(workspaceID) == nil)
        #expect(
            try persistence.preparedPublication(
                workspaceID: workspaceID,
                checkpointID: pendingCheckpoint.id
            ) == nil
        )
        let receipts = try await database.read { db in
            try SourceWorkspaceProposalReceiptsRequest(workspaceID: workspaceID).fetch(db)
        }
        expectNoDifference(receipts, [proposal])
    }

    @Test
    func `freezes transport input before publication and caches its proposal result`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let persistence = WorkspacePublicationPersistence(database: database)
        let workspaceID = SourceWorkspace.ID(rawValue: "workspace-1")
        let attempt = WorkspaceProposalAttempt(
            changes: SourcePatch(),
            details: WorkspaceProposalDetails(
                title: try #require(WorkspaceProposalTitle("Improve the source")),
                description: "Complete replacement proposal"
            ),
            target: WorkspaceBranchReference(
                branch: WorkspaceBranch(rawValue: "main"),
                revision: WorkspaceRevision(rawValue: "base-revision")
            )
        )
        let checkpoint = try await persistence.checkpoint(
            workspaceID: workspaceID,
            attempt: attempt
        )
        let request = TangledPatchOnlyProposalPublicationRequest(
            authorRepository: try #require(DID("did:plc:author")),
            recordKey: ATProto.Record.Key(rawValue: "ome-proposal"),
            target: TangledPatchOnlyProposalTarget(
                repositoryDID: try #require(DID("did:plc:repository")),
                repositoryOwnerDID: try #require(DID("did:plc:owner")),
                repositoryName: "festival-source",
                knotHost: "knot.example"
            ),
            title: "Improve the source",
            body: "Complete replacement proposal",
            createdAt: "2026-08-28T15:00:00Z",
            patch: TangledReplacementPatch(
                baseRevision: WorkspaceRevision(rawValue: "base-revision"),
                currentRevision: WorkspaceRevision(rawValue: "proposal-revision"),
                patchText: "From proposal-revision Mon Sep 17 00:00:00 2001\n",
                compressedBlob: Data([0x1f, 0x8b, 0x08, 0x00])
            )
        )
        let proposal = WorkspaceProposal(
            id: WorkspaceProposalID(
                rawValue: "at://did:plc:author/sh.tangled.repo.pull/ome-proposal"
            ),
            revision: request.patch.currentRevision,
            target: WorkspaceBranchReference(
                branch: WorkspaceBranch(rawValue: "main"),
                revision: request.patch.baseRevision
            )
        )

        try await persistence.savePreparedPublication(
            request,
            workspaceID: workspaceID,
            checkpointID: checkpoint.id
        )
        expectNoDifference(
            try persistence.preparedPublication(
                workspaceID: workspaceID,
                checkpointID: checkpoint.id
            ),
            request
        )

        try await persistence.savePublishedProposal(
            proposal,
            checkpoint: checkpoint,
            workspaceID: workspaceID
        )
        expectNoDifference(
            try persistence.publishedProposal(
                workspaceID: workspaceID,
                checkpointID: checkpoint.id
            ),
            proposal
        )

        try await persistence.completePublication(workspaceID: workspaceID)
        #expect(
            try persistence.preparedPublication(
                workspaceID: workspaceID,
                checkpointID: checkpoint.id
            ) == nil
        )
        #expect(
            try persistence.publishedProposal(
                workspaceID: workspaceID,
                checkpointID: checkpoint.id
            ) == nil
        )
    }
}
