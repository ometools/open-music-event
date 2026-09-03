import ATProto
import ComposableWorkspace
import CustomDump
import Dependencies
import Foundation
import HTTPClient
import OpenMusicEventSourceClone
import Synchronization
import TangledLexicon
import Testing
import XRPCClient

@testable import OpenMusicEventSourceEditing

@Suite("Patch-only Tangled proposal publication")
struct TangledPatchOnlyProposalPublisherTests {
    @Test
    func `live merge check identifies the repository to the knot`() async throws {
        let request = try publicationRequest()
        let requests = Mutex([(url: URL?, body: Data?)]())

        let output = try await withDependencies {
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { urlRequest, body in
                requests.withLock {
                    $0.append((url: urlRequest.url, body: body))
                }
                return Data(#"{"is_conflicted":false}"#.utf8)
            }
        } operation: {
            try await TangledPatchOnlyProposalTransport.live.mergeCheck(
                TangledPatchOnlyProposalMergeCheckRequest(
                    target: request.target,
                    patch: request.patch.patchText,
                    branch: "main"
                )
            )
        }

        #expect(output.isConflicted == false)
        let sentRequest = try #require(requests.withLock { $0.first })
        #expect(
            sentRequest.url?.path.hasSuffix("/sh.tangled.repo.mergeCheck") == true
        )
        let body = try #require(sentRequest.body)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["did"] as? String == "did:plc:owner")
        #expect(json["name"] as? String == "festival-source")
        #expect(json["branch"] as? String == "main")
        #expect(json["repo"] as? String == "did:plc:repository")
    }

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

        let error = await #expect(throws: WorkspaceHeadMismatch.self) {
            try await TangledPatchOnlyProposalPublisher(transport: transport).publish(request)
        }

        expectNoDifference(
            error,
            WorkspaceHeadMismatch(
                observedRevision: WorkspaceRevision(rawValue: "advanced-revision")
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

        let error = await #expect(throws: WorkspaceHeadMismatch.self) {
            try await TangledPatchOnlyProposalPublisher(transport: transport).publish(request)
        }

        expectNoDifference(
            error,
            WorkspaceHeadMismatch(
                observedRevision: WorkspaceRevision(rawValue: "advanced-revision")
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

        let error = await #expect(throws: WorkspacePublicationConflict.self) {
            try await TangledPatchOnlyProposalPublisher(transport: transport).publish(request)
        }

        expectNoDifference(
            error,
            WorkspacePublicationConflict(
                conflictingPaths: [WorkspaceConflictPath(rawValue: "event.yml")]
            )
        )
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

}

private enum PublicationEvent: Equatable, Sendable {
    case listRefs(head: String)
    case mergeCheck(patch: String, branch: String)
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
        title: "Improve the festival source",
        body: "Complete replacement proposal",
        createdAt: "2026-08-28T15:00:00Z",
        patch: TangledReplacementPatch(
            baseRevision: WorkspaceRevision(rawValue: "base-revision"),
            currentRevision: WorkspaceRevision(rawValue: "current-revision"),
            patchText: "From current-revision Mon Sep 17 00:00:00 2001\n",
            compressedBlob: Data([0x1f, 0x8b, 0x08, 0x00])
        )
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
