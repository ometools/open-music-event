import ComposableWorkspace
import CustomDump
import Dependencies
import Foundation
import Gzip
import SourceControlClient
import Synchronization
import Testing

@testable import OpenMusicEventSourceEditing

@Suite("Tangled replacement patches")
struct TangledReplacementPatchTests {
    @Test
    func `keeps the exact Git patch and compressed blob stable for one revision pair`() async throws {
        let requests = Mutex([EmailPatchRequest]())
        let patchText = """
        From current-revision Mon Sep 17 00:00:00 2001
        From: Open Music Event <noreply@openmusicevent.app>
        Subject: [PATCH] Complete proposal

        diff --git a/event.yml b/event.yml
        """
        var sourceControl = SourceControlClient.unimplemented
        sourceControl.emailPatch = { request in
            requests.withLock { $0.append(request) }
            return Data(patchText.utf8)
        }
        let repository = Repository(
            url: URL(filePath: "/tmp/open-music-event-replacement-patch")
        )

        // The proposal round is formatted against its immutable original base.
        let first = try await withDependencies {
            $0.sourceControl = sourceControl
        } operation: {
            try await TangledReplacementPatchGenerator().generate(
                repository: repository,
                baseRevision: WorkspaceRevision(rawValue: "base-revision"),
                baseCommit: CommitID(rawValue: "local-base-revision"),
                currentRevision: WorkspaceRevision(rawValue: "current-revision")
            )
        }

        // Retrying the same frozen revision pair produces the exact same transport bytes.
        let retry = try await withDependencies {
            $0.sourceControl = sourceControl
        } operation: {
            try await TangledReplacementPatchGenerator().generate(
                repository: repository,
                baseRevision: WorkspaceRevision(rawValue: "base-revision"),
                baseCommit: CommitID(rawValue: "local-base-revision"),
                currentRevision: WorkspaceRevision(rawValue: "current-revision")
            )
        }

        expectNoDifference(
            requests.withLock { $0 },
            [
                EmailPatchRequest(
                    repository: repository,
                    commit: "current-revision",
                    baseCommit: "local-base-revision"
                ),
                EmailPatchRequest(
                    repository: repository,
                    commit: "current-revision",
                    baseCommit: "local-base-revision"
                ),
            ]
        )
        expectNoDifference(first, retry)
        expectNoDifference(first.baseRevision, WorkspaceRevision(rawValue: "base-revision"))
        expectNoDifference(
            first.currentRevision,
            WorkspaceRevision(rawValue: "current-revision")
        )
        expectNoDifference(first.patchText, patchText)
        expectNoDifference(first.patchByteCount, Data(patchText.utf8).count)
        expectNoDifference(first.compressedBlobByteCount, first.compressedBlob.count)
        expectNoDifference(
            try first.compressedBlob.gunzipped(),
            Data(patchText.utf8)
        )
    }

    @Test
    func `rejects patch and blob sizes beyond the configured transport limits`() async throws {
        var sourceControl = SourceControlClient.unimplemented
        sourceControl.emailPatch = { _ in Data("complete replacement patch".utf8) }
        let repository = Repository(
            url: URL(filePath: "/tmp/open-music-event-replacement-patch-limits")
        )

        let patchError = await #expect(
            throws: TangledReplacementPatchError.self
        ) {
            try await withDependencies {
                $0.sourceControl = sourceControl
            } operation: {
                try await TangledReplacementPatchGenerator(
                    limits: TangledReplacementPatchLimits(
                        maxPatchBytes: 1,
                        maxCompressedBlobBytes: 1_024
                    )
                )
                .generate(
                    repository: repository,
                    baseRevision: WorkspaceRevision(rawValue: "base-revision"),
                    baseCommit: CommitID(rawValue: "local-base-revision"),
                    currentRevision: WorkspaceRevision(rawValue: "current-revision")
                )
            }
        }
        expectNoDifference(
            patchError,
            .patchTooLarge(byteCount: 26, limit: 1)
        )

        let blobError = await #expect(
            throws: TangledReplacementPatchError.self
        ) {
            try await withDependencies {
                $0.sourceControl = sourceControl
            } operation: {
                try await TangledReplacementPatchGenerator(
                    limits: TangledReplacementPatchLimits(
                        maxPatchBytes: 1_024,
                        maxCompressedBlobBytes: 1
                    )
                )
                .generate(
                    repository: repository,
                    baseRevision: WorkspaceRevision(rawValue: "base-revision"),
                    baseCommit: CommitID(rawValue: "local-base-revision"),
                    currentRevision: WorkspaceRevision(rawValue: "current-revision")
                )
            }
        }
        guard case let .compressedBlobTooLarge(byteCount, limit) = blobError else {
            Issue.record("Expected the compressed blob size limit to fail.")
            return
        }
        #expect(byteCount > 1)
        #expect(limit == 1)
    }
}
