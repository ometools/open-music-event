import ATProto
import ComposableWorkspace
import CustomDump
import Foundation
import OpenMusicEventSourceClone
import Synchronization
import TangledLexicon
import Testing

@testable import OpenMusicEventSourceEditing

@Suite("Patch-only Tangled proposal publication")
struct TangledPatchOnlyProposalPublisherTests {
    @Test
    func `publishes the frozen patch to the live default branch without a source branch`() async throws {
        let events = PublicationEventRecorder()
        let request = try publicationRequest()
        let publisher = TangledPatchOnlyProposalPublisher(
            transport: recordingTransport(events: events)
        )

        // A retry reuses the same record key, patch, timestamp, and compressed bytes.
        let first = try await publisher.publish(request)
        let retry = try await publisher.publish(request)

        expectNoDifference(
            first,
            WorkspaceProposalID(
                rawValue: "at://did:plc:author/sh.tangled.repo.pull/ome-proposal"
            )
        )
        expectNoDifference(first, retry)
        expectNoDifference(
            events.values,
            expectedSuccessfulEvents(request: request) + expectedSuccessfulEvents(request: request)
        )
    }

    @Test
    func `does not authorize upload or write a pull when the default branch advances`() async throws {
        let events = PublicationEventRecorder()
        let listRefsCount = CallCounter()
        let request = try publicationRequest()
        var transport = recordingTransport(events: events)
        transport.listRefs = { _ in
            let count = listRefsCount.next()
            let head = count == 0 ? "base-revision" : "advanced-revision"
            events.record(.listRefs(head: head))
            return listRefsOutput(head: head)
        }

        let error = await #expect(throws: TangledPatchOnlyProposalPublisherError.self) {
            try await TangledPatchOnlyProposalPublisher(transport: transport).publish(request)
        }

        expectNoDifference(
            error,
            .defaultBranchAdvanced(
                expected: WorkspaceRevision(rawValue: "base-revision"),
                observed: WorkspaceRevision(rawValue: "advanced-revision")
            )
        )
        expectNoDifference(
            events.values,
            [
                .listRefs(head: "base-revision"),
                .mergeCheck(patch: request.patch.patchText, branch: "main"),
                .listRefs(head: "advanced-revision"),
            ]
        )
    }

    @Test
    func `does not write a pull when the default branch advances during upload`() async throws {
        let events = PublicationEventRecorder()
        let listRefsCount = CallCounter()
        let request = try publicationRequest()
        var transport = recordingTransport(events: events)
        transport.listRefs = { _ in
            let count = listRefsCount.next()
            let head = count < 2 ? "base-revision" : "advanced-revision"
            events.record(.listRefs(head: head))
            return listRefsOutput(head: head)
        }

        let error = await #expect(throws: TangledPatchOnlyProposalPublisherError.self) {
            try await TangledPatchOnlyProposalPublisher(transport: transport).publish(request)
        }

        expectNoDifference(
            error,
            .defaultBranchAdvanced(
                expected: WorkspaceRevision(rawValue: "base-revision"),
                observed: WorkspaceRevision(rawValue: "advanced-revision")
            )
        )
        expectNoDifference(
            events.values,
            [
                .listRefs(head: "base-revision"),
                .mergeCheck(patch: request.patch.patchText, branch: "main"),
                .listRefs(head: "base-revision"),
                .authorize,
                .upload(request.patch.compressedBlob),
                .listRefs(head: "advanced-revision"),
            ]
        )
    }

    @Test
    func `does not upload or write a pull when merge check reports a conflict`() async throws {
        let events = PublicationEventRecorder()
        let request = try publicationRequest()
        var transport = recordingTransport(events: events)
        transport.mergeCheck = { request in
            events.record(.mergeCheck(patch: request.patch, branch: request.branch))
            return TangledMergeCheckOutput(
                isConflicted: true,
                conflicts: [
                    .init(filename: "event.yml", reason: "content conflict")
                ],
                message: "Patch has conflicts"
            )
        }

        let error = await #expect(throws: TangledPatchOnlyProposalPublisherError.self) {
            try await TangledPatchOnlyProposalPublisher(transport: transport).publish(request)
        }

        expectNoDifference(error, .mergeCheckRejected("Patch has conflicts"))
        expectNoDifference(
            events.values,
            [
                .listRefs(head: "base-revision"),
                .mergeCheck(patch: request.patch.patchText, branch: "main"),
            ]
        )
    }

    @Test
    func `fails closed when list refs cannot identify a usable default branch head`() async throws {
        let request = try publicationRequest()
        let cases: [(TangledListRefsOutput, TangledPatchOnlyProposalPublisherError)] = [
            (
                TangledListRefsOutput(refs: []),
                .missingDefaultBranch
            ),
            (
                TangledListRefsOutput(
                    refs: [],
                    defaultBranch: TangledDefaultBranchReference(
                        ref: "",
                        head: "base-revision"
                    )
                ),
                .invalidDefaultBranchRef("")
            ),
            (
                TangledListRefsOutput(
                    refs: [],
                    defaultBranch: TangledDefaultBranchReference(
                        ref: "refs/heads/main"
                    )
                ),
                .missingDefaultBranchHead("refs/heads/main")
            ),
        ]

        for (output, expectedError) in cases {
            let events = PublicationEventRecorder()
            var transport = recordingTransport(events: events)
            transport.listRefs = { _ in output }

            let error = await #expect(throws: TangledPatchOnlyProposalPublisherError.self) {
                try await TangledPatchOnlyProposalPublisher(transport: transport).publish(request)
            }

            expectNoDifference(error, expectedError)
            expectNoDifference(events.values, [])
        }
    }

    @Test
    func `proposal update appends a replacement round without restoring a source branch`() async throws {
        let events = PublicationEventRecorder()
        var request = try publicationRequest()
        let previous = WorkspaceProposal(
            id: WorkspaceProposalID(
                rawValue: "at://did:plc:author/sh.tangled.repo.pull/ome-proposal"
            ),
            revision: WorkspaceRevision(rawValue: "previous-revision"),
            target: WorkspaceBranchReference(
                branch: WorkspaceBranch(rawValue: "main"),
                revision: WorkspaceRevision(rawValue: "base-revision")
            )
        )
        request.previousProposal = previous
        let previousRound = TangledPullRecord.Round(
            patchBlob: ATProto.Blob(
                ref: "bafypreviouspatch",
                mimeType: "application/gzip",
                size: 12
            ),
            createdAt: "2026-08-27T15:00:00Z"
        )
        let previousRecord = TangledPullRecord(
            target: TangledPullRecord.Target(
                repo: request.target.repositoryDID,
                branch: "main"
            ),
            title: "Original title",
            body: "Original body",
            rounds: [previousRound],
            source: TangledPullRecord.Source(branch: "retired/proposal-branch"),
            createdAt: "2026-08-27T15:00:00Z"
        )
        var transport = recordingTransport(events: events)
        transport.loadProposal = { id in
            events.record(.loadProposal(id.rawValue))
            return TangledPatchOnlyProposalSnapshot(
                cid: "bafypreviousrecord",
                record: previousRecord,
                revision: previous.revision
            )
        }

        let result = try await TangledPatchOnlyProposalPublisher(transport: transport)
            .publish(request)

        expectNoDifference(result, previous.id)
        var updatedRecord = previousRecord
        updatedRecord.rounds.append(
            TangledPullRecord.Round(
                patchBlob: ATProto.Blob(
                    ref: "bafyreplacementpatch",
                    mimeType: "application/gzip",
                    size: request.patch.compressedBlob.count
                ),
                createdAt: request.createdAt
            )
        )
        updatedRecord.source = nil
        expectNoDifference(
            events.values,
            [
                .listRefs(head: "base-revision"),
                .mergeCheck(patch: request.patch.patchText, branch: "main"),
                .listRefs(head: "base-revision"),
                .loadProposal(previous.id.rawValue),
                .authorize,
                .upload(request.patch.compressedBlob),
                .listRefs(head: "base-revision"),
                .putRecord(
                    repo: request.authorRepository.description,
                    rkey: request.recordKey.rawValue,
                    record: updatedRecord,
                    swapRecord: "bafypreviousrecord"
                ),
            ]
        )
    }

    @Test
    func `proposal update retry recognizes the already published replacement revision`() async throws {
        let events = PublicationEventRecorder()
        var request = try publicationRequest()
        let previous = WorkspaceProposal(
            id: WorkspaceProposalID(
                rawValue: "at://did:plc:author/sh.tangled.repo.pull/ome-proposal"
            ),
            revision: WorkspaceRevision(rawValue: "previous-revision"),
            target: WorkspaceBranchReference(
                branch: WorkspaceBranch(rawValue: "main"),
                revision: WorkspaceRevision(rawValue: "base-revision")
            )
        )
        request.previousProposal = previous
        let frozenRequest = request
        var transport = recordingTransport(events: events)
        transport.loadProposal = { id in
            events.record(.loadProposal(id.rawValue))
            return TangledPatchOnlyProposalSnapshot(
                cid: "bafycurrentrecord",
                record: TangledPullRecord(
                    target: TangledPullRecord.Target(
                        repo: frozenRequest.target.repositoryDID,
                        branch: "main"
                    ),
                    title: frozenRequest.title,
                    rounds: [],
                    source: nil,
                    createdAt: frozenRequest.createdAt
                ),
                revision: frozenRequest.patch.currentRevision
            )
        }

        let result = try await TangledPatchOnlyProposalPublisher(transport: transport)
            .publish(frozenRequest)

        expectNoDifference(result, previous.id)
        expectNoDifference(
            events.values,
            [
                .listRefs(head: "base-revision"),
                .mergeCheck(patch: frozenRequest.patch.patchText, branch: "main"),
                .listRefs(head: "base-revision"),
                .loadProposal(previous.id.rawValue),
            ]
        )
    }

    @Test
    func `proposal update fails closed when the existing pull target changed`() async throws {
        var request = try publicationRequest()
        let previous = WorkspaceProposal(
            id: WorkspaceProposalID(
                rawValue: "at://did:plc:author/sh.tangled.repo.pull/ome-proposal"
            ),
            revision: WorkspaceRevision(rawValue: "previous-revision"),
            target: WorkspaceBranchReference(
                branch: WorkspaceBranch(rawValue: "main"),
                revision: WorkspaceRevision(rawValue: "base-revision")
            )
        )
        request.previousProposal = previous
        let otherRepository = try #require(DID("did:plc:other-repository"))
        let cases: [(
            target: TangledPullRecord.Target,
            error: TangledPatchOnlyProposalPublisherError
        )] = [
            (
                TangledPullRecord.Target(repo: otherRepository, branch: "main"),
                .proposalTargetRepositoryChanged(
                    expected: request.target.repositoryDID,
                    observed: otherRepository
                )
            ),
            (
                TangledPullRecord.Target(
                    repo: request.target.repositoryDID,
                    branch: "other-branch"
                ),
                .proposalTargetBranchChanged(expected: "main", observed: "other-branch")
            ),
        ]

        for testCase in cases {
            let events = PublicationEventRecorder()
            var transport = recordingTransport(events: events)
            transport.loadProposal = { id in
                events.record(.loadProposal(id.rawValue))
                return TangledPatchOnlyProposalSnapshot(
                    cid: "bafyexistingrecord",
                    record: TangledPullRecord(
                        target: testCase.target,
                        title: "Original title",
                        rounds: [],
                        source: nil,
                        createdAt: "2026-08-27T15:00:00Z"
                    ),
                    revision: previous.revision
                )
            }

            let error = await #expect(throws: TangledPatchOnlyProposalPublisherError.self) {
                try await TangledPatchOnlyProposalPublisher(transport: transport)
                    .publish(request)
            }

            expectNoDifference(error, testCase.error)
            expectNoDifference(
                events.values,
                [
                    .listRefs(head: "base-revision"),
                    .mergeCheck(patch: request.patch.patchText, branch: "main"),
                    .listRefs(head: "base-revision"),
                    .loadProposal(previous.id.rawValue),
                ]
            )
        }
    }
}

private enum PublicationEvent: Equatable, Sendable {
    case listRefs(head: String)
    case mergeCheck(patch: String, branch: String)
    case loadProposal(String)
    case authorize
    case upload(Data)
    case putRecord(
        repo: String,
        rkey: String,
        record: TangledPullRecord,
        swapRecord: String?
    )
}

private func publicationRequest() throws -> TangledPatchOnlyProposalPublicationRequest {
    TangledPatchOnlyProposalPublicationRequest(
        authorRepository: try #require(DID("did:plc:author")),
        recordKey: ATProto.Record.Key(rawValue: "ome-proposal"),
        target: TangledPatchOnlyProposalTarget(
            repositoryDID: try #require(DID("did:plc:repository")),
            repositoryOwnerDID: try #require(DID("did:plc:owner")),
            repositoryName: "festival-source",
            knotHost: "knot.example"
        ),
        title: "Update the festival source",
        body: "Complete replacement proposal",
        createdAt: "2026-08-28T15:00:00Z",
        patch: TangledReplacementPatch(
            baseRevision: WorkspaceRevision(rawValue: "base-revision"),
            currentRevision: WorkspaceRevision(rawValue: "current-revision"),
            patchText: "From current-revision Mon Sep 17 00:00:00 2001\n",
            compressedBlob: Data([0x1f, 0x8b, 0x08, 0x00])
        ),
        previousProposal: nil
    )
}

private func recordingTransport(
    events: PublicationEventRecorder
) -> TangledPatchOnlyProposalTransport {
    TangledPatchOnlyProposalTransport(
        listRefs: { _ in
            events.record(.listRefs(head: "base-revision"))
            return listRefsOutput(head: "base-revision")
        },
        mergeCheck: { request in
            events.record(.mergeCheck(patch: request.patch, branch: request.branch))
            return TangledMergeCheckOutput(isConflicted: false)
        },
        loadProposal: { _ in
            throw PublicationTestError.unexpectedProposalLoad
        },
        authorize: {
            events.record(.authorize)
        },
        uploadPatchBlob: { data in
            events.record(.upload(data))
            return ATProto.Blob(
                ref: "bafyreplacementpatch",
                mimeType: "application/gzip",
                size: data.count
            )
        },
        putRecord: { request in
            events.record(
                .putRecord(
                    repo: request.authorRepository.description,
                    rkey: request.recordKey.rawValue,
                    record: request.record,
                    swapRecord: request.swapRecord?.rawValue
                )
            )
            return try #require(
                ATProto.URI("at://did:plc:author/sh.tangled.repo.pull/ome-proposal")
            )
        }
    )
}

private enum PublicationTestError: Error {
    case unexpectedProposalLoad
}

private final class PublicationEventRecorder: Sendable {
    private let storage = Mutex([PublicationEvent]())

    var values: [PublicationEvent] {
        storage.withLock { $0 }
    }

    func record(_ event: PublicationEvent) {
        storage.withLock { $0.append(event) }
    }
}

private final class CallCounter: Sendable {
    private let storage = Mutex(0)

    func next() -> Int {
        storage.withLock { count in
            defer { count += 1 }
            return count
        }
    }
}

private func listRefsOutput(head: String) -> TangledListRefsOutput {
    TangledListRefsOutput(
        refs: [
            TangledGitReference(ref: "refs/heads/main", sha: head)
        ],
        defaultBranch: TangledDefaultBranchReference(
            ref: "refs/heads/main",
            head: head
        )
    )
}

private func expectedSuccessfulEvents(
    request: TangledPatchOnlyProposalPublicationRequest
) -> [PublicationEvent] {
    [
        .listRefs(head: "base-revision"),
        .mergeCheck(patch: request.patch.patchText, branch: "main"),
        .listRefs(head: "base-revision"),
        .authorize,
        .upload(request.patch.compressedBlob),
        .listRefs(head: "base-revision"),
        .putRecord(
            repo: request.authorRepository.description,
            rkey: request.recordKey.rawValue,
            record: TangledPullRecord(
                target: TangledPullRecord.Target(
                    repo: request.target.repositoryDID,
                    branch: "main"
                ),
                title: request.title,
                body: request.body,
                rounds: [
                    TangledPullRecord.Round(
                        patchBlob: ATProto.Blob(
                            ref: "bafyreplacementpatch",
                            mimeType: "application/gzip",
                            size: request.patch.compressedBlob.count
                        ),
                        createdAt: request.createdAt
                    )
                ],
                source: nil,
                createdAt: request.createdAt
            ),
            swapRecord: nil
        ),
    ]
}
