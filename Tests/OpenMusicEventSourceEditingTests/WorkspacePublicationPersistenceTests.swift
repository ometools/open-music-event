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
    func `freezes transport input before publication and caches its proposal result`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let persistence = WorkspacePublicationPersistence(database: database)
        let workspaceID = SourceWorkspace.ID(rawValue: "workspace-1")
        let attempt = WorkspaceProposalAttempt(
            changes: SourcePatch(),
            target: .createProposal(
                target: WorkspaceBranchReference(
                    branch: WorkspaceBranch(rawValue: "main"),
                    revision: WorkspaceRevision(rawValue: "base-revision")
                ),
                details: WorkspaceProposalDetails(
                    title: try #require(WorkspaceProposalTitle("Update the source")),
                    description: "Complete replacement proposal"
                )
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
            title: "Update the source",
            body: "Complete replacement proposal",
            createdAt: "2026-08-28T15:00:00Z",
            patch: TangledReplacementPatch(
                baseRevision: WorkspaceRevision(rawValue: "base-revision"),
                currentRevision: WorkspaceRevision(rawValue: "proposal-revision"),
                patchText: "From proposal-revision Mon Sep 17 00:00:00 2001\n",
                compressedBlob: Data([0x1f, 0x8b, 0x08, 0x00])
            ),
            previousProposal: nil
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

        try await persistence.completeRepair(workspaceID: workspaceID)
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
