import ATProto
import ComposableWorkspace
import Foundation
import OpenMusicEventSourceClone
import Synchronization
import TangledLexicon
import TangledXRPC
import Testing

@testable import OpenMusicEventSourceEditing

@Suite("Direct Tangled publication")
struct TangledDirectPublisherTests {
    @Test
    func `merge checks and merges the patch against the exact captured head`() async throws {
        let heads = Mutex(["base-revision", "base-revision", "published-revision"])
        let mergeCalls = Mutex(0)
        let publisher = TangledDirectPublisher(
            transport: TangledDirectTransport(
                listRefs: { _ in
                    let head = heads.withLock { $0.removeFirst() }
                    return directListRefs(head: head)
                },
                mergeCheck: { _ in TangledMergeCheckOutput(isConflicted: false) },
                merge: { _, _ in mergeCalls.withLock { $0 += 1 } }
            )
        )

        let published = try await publisher.publish(try directRequest())

        #expect(published.branch == WorkspaceBranch(rawValue: "main"))
        #expect(published.revision == WorkspaceRevision(rawValue: "published-revision"))
        #expect(mergeCalls.withLock { $0 } == 1)
    }

    @Test
    func `an advanced head is rejected before merge and is never retried`() async throws {
        let mergeCalls = Mutex(0)
        let publisher = TangledDirectPublisher(
            transport: TangledDirectTransport(
                listRefs: { _ in directListRefs(head: "advanced-revision") },
                mergeCheck: { _ in TangledMergeCheckOutput(isConflicted: false) },
                merge: { _, _ in mergeCalls.withLock { $0 += 1 } }
            )
        )

        let error = await #expect(throws: WorkspaceHeadMismatch.self) {
            try await publisher.publish(try directRequest())
        }

        #expect(
            error == WorkspaceHeadMismatch(
                observedRevision: WorkspaceRevision(rawValue: "advanced-revision")
            )
        )
        #expect(mergeCalls.withLock { $0 } == 0)
    }

    @Test
    func `a merge check conflict is modeled before merge`() async throws {
        let mergeCalls = Mutex(0)
        let publisher = TangledDirectPublisher(
            transport: TangledDirectTransport(
                listRefs: { _ in directListRefs(head: "base-revision") },
                mergeCheck: { _ in
                    TangledMergeCheckOutput(
                        isConflicted: true,
                        conflicts: [
                            .init(filename: "event.yml", reason: "content conflict")
                        ],
                        message: "Patch has conflicts"
                    )
                },
                merge: { _, _ in mergeCalls.withLock { $0 += 1 } }
            )
        )

        let error = await #expect(throws: WorkspacePublicationConflict.self) {
            try await publisher.publish(try directRequest())
        }

        #expect(
            error == WorkspacePublicationConflict(
                conflictingPaths: [WorkspaceConflictPath(rawValue: "event.yml")]
            )
        )
        #expect(mergeCalls.withLock { $0 } == 0)
    }

    @Test
    func `a lost merge response is reported without another merge attempt`() async throws {
        let mergeCalls = Mutex(0)
        let publisher = TangledDirectPublisher(
            transport: TangledDirectTransport(
                listRefs: { _ in directListRefs(head: "base-revision") },
                mergeCheck: { _ in TangledMergeCheckOutput(isConflicted: false) },
                merge: { _, _ in
                    mergeCalls.withLock { $0 += 1 }
                    throw DirectPublicationTestError.responseLost
                }
            )
        )

        await #expect(throws: DirectPublicationTestError.responseLost) {
            try await publisher.publish(try directRequest())
        }
        #expect(mergeCalls.withLock { $0 } == 1)
    }
}

private enum DirectPublicationTestError: Error {
    case responseLost
}

private func directRequest() throws -> TangledDirectPublicationRequest {
    TangledDirectPublicationRequest(
        target: TangledPatchOnlyProposalTarget(
            repositoryDID: try #require(DID("did:plc:repository")),
            repositoryOwnerDID: try #require(DID("did:plc:owner")),
            repositoryName: "festival-source",
            knotHost: "knot.example"
        ),
        branch: WorkspaceBranch(rawValue: "main"),
        title: "Publish the festival source",
        body: "Direct publication",
        patch: TangledReplacementPatch(
            baseRevision: WorkspaceRevision(rawValue: "base-revision"),
            currentRevision: WorkspaceRevision(rawValue: "current-revision"),
            patchText: "From current-revision Mon Sep 17 00:00:00 2001\n",
            compressedBlob: Data()
        )
    )
}

private func directListRefs(head: String) -> TangledListRefsOutput {
    TangledListRefsOutput(
        refs: [TangledGitReference(ref: "refs/heads/main", sha: head)],
        defaultBranch: TangledDefaultBranchReference(
            ref: "refs/heads/main",
            head: head
        )
    )
}
