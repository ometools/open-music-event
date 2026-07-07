import ATProto
import ATProtoOAuth
import CustomDump
import Dependencies
import Foundation
import HTTPClient
import Synchronization
import TangledLexicon
import Testing
import XRPCClient

@testable import OpenMusicEventSourceEditing

struct TangledPullReviewClientTests {
    @Test
    func mapsTangledListPullItemToReviewRowWithRawBackup() throws {
        let item = TangledPullListItem(
            uri: try #require(ATProto.URI("at://did:plc:author123/sh.tangled.repo.pull/3pull")),
            cid: "bafyreipull",
            value: TangledPullRecord(
                target: TangledPullRecord.Target(
                    repo: try #require(DID("did:plc:targetrepo")),
                    branch: "main"
                ),
                title: "Update Saturday schedule",
                body: "Move one performance later.",
                rounds: [
                    TangledPullRecord.Round(
                        patchBlob: ATProto.Blob(
                            ref: "bafkreipatch",
                            mimeType: "application/gzip",
                            size: 123
                        ),
                        createdAt: "2026-07-03T12:00:00Z"
                    )
                ],
                source: TangledPullRecord.Source(
                    branch: "ome/proposal-schedule",
                    repo: try #require(DID("did:plc:authorrepo"))
                ),
                createdAt: "2026-07-03T12:01:00Z"
            ),
            state: .open,
            stateUpdatedAt: "2026-07-03T12:02:00Z",
            commentCount: 2
        )

        let review = TangledPullReview(item: item)

        expectNoDifference(
            review,
            TangledPullReview(
                author: "did:plc:author123",
                body: "Move one performance later.",
                commentCount: 2,
                createdAt: "2026-07-03T12:01:00Z",
                patchBlobs: [
                    TangledPullReview.PatchBlob(
                        cid: "bafkreipatch",
                        createdAt: "2026-07-03T12:00:00Z",
                        index: 1,
                        mimeType: "application/gzip",
                        size: 123
                    )
                ],
                sourceBranch: "ome/proposal-schedule",
                sourceRepositoryDID: "did:plc:authorrepo",
                state: "open",
                stateUpdatedAt: "2026-07-03T12:02:00Z",
                targetBranch: "main",
                targetRepositoryDID: "did:plc:targetrepo",
                title: "Update Saturday schedule",
                uri: "at://did:plc:author123/sh.tangled.repo.pull/3pull"
            )
        )
        #expect(review.rawReviewText.contains("patchBlobs:"))
        #expect(review.rawReviewText.contains("cid: bafkreipatch"))
    }

    @Test
    func closeCreatesClosedPullStatusRecord() async throws {
        let review = TangledPullReview(
            author: "did:plc:author123",
            body: "Move one performance later.",
            commentCount: 2,
            createdAt: "2026-07-03T12:01:00Z",
            patchBlobs: [],
            sourceBranch: "ome/proposal-schedule",
            state: "open",
            targetBranch: "main",
            targetRepositoryDID: "did:plc:targetrepo",
            title: "Update Saturday schedule",
            uri: "at://did:plc:author123/sh.tangled.repo.pull/3pull"
        )
        let requests = Mutex([(url: URL?, body: Data?)]())

        try await withDependencies {
            $0.date.now = Date(timeIntervalSince1970: 1_783_453_261)
            $0[XRPC.Client.self] = .liveValue
            $0.pdsHost = "publisher.pds.example"
            $0.getDefaultSession = { .placeholder }
            $0.httpClient = HTTPClient { request, body in
                requests.withLock {
                    $0.append((url: request.url, body: body))
                }
                return Data(
                    """
                    {
                      "uri": "at://did:plc:placeholder/sh.tangled.repo.pull.status/3status",
                      "cid": "bafyreistatus"
                    }
                    """
                    .utf8
                )
            }
        } operation: {
            try await TangledPullReviewClient.openMusicEvent.close(review)
        }

        let request = try #require(requests.withLock { $0.first })
        #expect(request.url?.host == "publisher.pds.example")
        #expect(request.url?.path.hasSuffix("/com.atproto.repo.createRecord") == true)
        let body = try #require(request.body)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["repo"] as? String == "did:plc:placeholder")
        #expect(json["collection"] as? String == TangledPullStatusRecord.collection.rawValue)
        let record = try #require(json["record"] as? [String: Any])
        #expect(record["$type"] as? String == TangledPullStatusRecord.collection.rawValue)
        #expect(record["pull"] as? String == review.uri)
        #expect(record["status"] as? String == TangledPullStatus.closed.rawValue)
        #expect(record["createdAt"] != nil)
    }

    @Test
    func deleteRemovesPullRecord() async throws {
        let review = TangledPullReview(
            author: "did:plc:author123",
            body: "Move one performance later.",
            commentCount: 2,
            createdAt: "2026-07-03T12:01:00Z",
            patchBlobs: [],
            sourceBranch: "ome/proposal-schedule",
            state: "open",
            targetBranch: "main",
            targetRepositoryDID: "did:plc:targetrepo",
            title: "Update Saturday schedule",
            uri: "at://did:plc:author123/sh.tangled.repo.pull/3pull"
        )
        let requests = Mutex([(url: URL?, body: Data?)]())

        try await withDependencies {
            $0[XRPC.Client.self] = .liveValue
            $0.pdsHost = "publisher.pds.example"
            $0.getDefaultSession = { .placeholder }
            $0.httpClient = HTTPClient { request, body in
                requests.withLock {
                    $0.append((url: request.url, body: body))
                }
                return Data("{}".utf8)
            }
        } operation: {
            try await TangledPullReviewClient.openMusicEvent.delete(review)
        }

        let request = try #require(requests.withLock { $0.first })
        #expect(request.url?.host == "publisher.pds.example")
        #expect(request.url?.path.hasSuffix("/com.atproto.repo.deleteRecord") == true)
        let body = try #require(request.body)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["repo"] as? String == "did:plc:author123")
        #expect(json["collection"] as? String == TangledCollection.pull.rawValue)
        #expect(json["rkey"] as? String == "3pull")
    }
}
