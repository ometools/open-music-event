import ATProto
import CustomDump
import TangledLexicon
import Testing

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
}
