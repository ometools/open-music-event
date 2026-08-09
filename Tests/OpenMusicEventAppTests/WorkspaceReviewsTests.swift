import ATProto
import BlueskyActorCache
import ComposableArchitecture2
import ComposableAuthoring
import CustomDump
import Dependencies
import Foundation
import IssueReporting
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
import Testing

@testable import OpenMusicEventAppEventViewer

@MainActor
@Suite("Workspace proposal reviews", .serialized)
struct WorkspaceReviewsTests {
    @Test
    func ownerOpensReviewDetailLoadsRemoteChangesAndMerges() async throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let review = review()
        let mergeRequests = LockIsolated<[OpenMusicEventTangledPullReviewMergeRequest]>([])
        let sourceSnapshotRequests = LockIsolated<[TangledPullReviewSourceSnapshotRequest]>([])
        let grant = AuthoringGrant(
            principal: AuthoringPrincipal(
                actorID: try #require(DID(workspace.organizerID.description))
            ),
            role: .owner,
            workspaceID: workspace.id
        )
        let store = makeStore(
            database: database,
            workspace: workspace,
            review: review,
            grant: grant,
            merge: { request in
                mergeRequests.withValue { $0.append(request) }
            },
            sourceSnapshotRequests: sourceSnapshotRequests
        )

        try await expectReportedIssue(containing: "ReviewSourceSnapshotUnavailable") {
            await store.send(.reviewButtonTapped(review))?.value
            await waitUntil {
                guard case let .reviewDetail(detail)? = store.destination else { return false }
                return detail.canMerge
                    && detail.rawDiffStatus == .loaded("Rendered remote patch")
                    && !sourceSnapshotRequests.value.isEmpty
            }
        }

        guard case let .reviewDetail(detail)? = store.destination else {
            Issue.record("Selecting a review must mount WorkspaceReviewDetail.")
            return
        }
        expectNoDifference(detail.workspace, workspace)
        expectNoDifference(detail.review, review)
        expectNoDifference(
            sourceSnapshotRequests.value,
            [
                TangledPullReviewSourceSnapshotRequest(
                    organizerID: workspace.organizerID,
                    ref: try #require(review.sourceBranch),
                    sourceProvenance: workspace.sourceProvenance
                )
            ]
        )

        await store.send(
            .destination(.reviewDetail(.mergeButtonTapped))
        )?.value
        await waitUntil { store.destination == nil }

        expectNoDifference(
            mergeRequests.value,
            [
                OpenMusicEventTangledPullReviewMergeRequest(
                    target: OpenMusicEventSourceTarget(workspace: workspace),
                    review: review
                )
            ]
        )
        #expect(store.reviews.isEmpty)
        expectNoDifference(store.locallyRemovedReviewIDs, Set([review.id]))
    }

    @Test
    func deletingReviewRemovesItOnlyAfterRemoteDeletionSucceeds() async throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let review = review()
        let deletedReviewIDs = LockIsolated<[String]>([])
        let grant = AuthoringGrant(
            principal: AuthoringPrincipal(
                actorID: try #require(DID(workspace.organizerID.description))
            ),
            role: .owner,
            workspaceID: workspace.id
        )
        let store = makeStore(
            database: database,
            workspace: workspace,
            review: review,
            grant: grant,
            delete: { review in
                deletedReviewIDs.withValue { $0.append(review.id) }
            }
        )

        try await expectReportedIssue(containing: "ReviewSourceSnapshotUnavailable") {
            await store.send(.reviewButtonTapped(review))?.value
            await waitUntil {
                guard case let .reviewDetail(detail)? = store.destination else { return false }
                guard case .failed = detail.semanticDiffStatus else { return false }
                return true
            }
        }

        await store.send(
            .destination(.reviewDetail(.deleteButtonTapped))
        )?.value
        await waitUntil { store.destination == nil }

        expectNoDifference(deletedReviewIDs.value, [review.id])
        #expect(store.reviews.isEmpty)
    }

    @Test
    func pendingCreatedProposalNavigatesWhenTheReviewAppears() throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let review = review()
        withDependencies {
            $0.defaultDatabase = database
        } operation: {
            var state = WorkspaceReviews.State(workspace: workspace)
            state.pendingCreatedReviewID = review.id
            state.status = .loaded([review])

            state.openPendingReviewIfAvailable()

            expectNoDifference(state.pendingCreatedReviewID, nil)
            guard case let .reviewDetail(detail)? = state.destination else {
                Issue.record("The hydrated pending proposal must open its detail.")
                return
            }
            expectNoDifference(detail.review, review)
            expectNoDifference(detail.workspace, workspace)
        }
    }

    @Test
    func proposerCannotMutateAReviewThroughDirectReducerActions() async throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let review = review()
        let mutations = LockIsolated<[String]>([])
        let grant = AuthoringGrant(
            principal: AuthoringPrincipal(actorID: try #require(DID("did:plc:proposer"))),
            role: .collaborator([.propose]),
            workspaceID: workspace.id
        )
        let store = makeStore(
            database: database,
            workspace: workspace,
            review: review,
            grant: grant,
            merge: { _ in mutations.withValue { $0.append("merge") } },
            delete: { _ in mutations.withValue { $0.append("delete") } },
            close: { _ in mutations.withValue { $0.append("close") } }
        )

        try await expectReportedIssue(containing: "ReviewSourceSnapshotUnavailable") {
            await store.send(.reviewButtonTapped(review))?.value
            await waitUntil {
                guard case let .reviewDetail(detail)? = store.destination else { return false }
                guard case .failed = detail.semanticDiffStatus else { return false }
                return detail.canMerge == false
            }
        }

        await store.send(.destination(.reviewDetail(.mergeButtonTapped)))?.value
        await store.send(.destination(.reviewDetail(.closeButtonTapped)))?.value
        await store.send(.destination(.reviewDetail(.deleteButtonTapped)))?.value
        #expect(mutations.value.isEmpty)
        #expect(store.destination != nil)
    }

    func makeStore(
        database: any DatabaseWriter,
        workspace: SourceWorkspace,
        review: TangledPullReview,
        grant: AuthoringGrant? = nil,
        merge: @escaping @Sendable (
            OpenMusicEventTangledPullReviewMergeRequest
        ) async throws -> Void = { _ in },
        delete: @escaping @Sendable (TangledPullReview) async throws -> Void = { _ in },
        close: @escaping @Sendable (TangledPullReview) async throws -> Void = { _ in },
        sourceSnapshotRequests: LockIsolated<[TangledPullReviewSourceSnapshotRequest]>? = nil
    ) -> StoreOf<WorkspaceReviews> {
        return withDependencies {
            $0.defaultDatabase = database
            $0.uuid = .incrementing
            $0.blueskyActorProfileCache = BlueskyActorProfileCacheClient(
                cachedProfile: { _ in nil },
                refreshProfile: { _ in throw ReviewProfileUnavailable() },
                refreshProfileIfNeeded: { _, _, _ in nil }
            )
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in [review] },
                close: close,
                merge: merge,
                delete: delete,
                rawDiff: { _ in "Rendered remote patch" }
            )
            $0.tangledPullReviewSourceSnapshot = TangledPullReviewSourceSnapshotClient(
                insertion: { request in
                    sourceSnapshotRequests?.withValue { $0.append(request) }
                    throw ReviewSourceSnapshotUnavailable()
                }
            )
        } operation: {
            var state = WorkspaceReviews.State(workspace: workspace)
            state.status = .loaded([review])
            return Store(initialState: state) {
                WorkspaceReviews()
                    .environment(
                        ComposableAuthoring.AuthoringContext(
                            grant: SharedReader(value: grant)
                        )
                    )
            }
        }
    }

    func workspace() throws -> SourceWorkspace {
        let ownerID = try #require(DID("did:plc:owner"))
        return SourceWorkspace(
            organizerID: try #require(OME.Organizer.ID(ownerID.description)),
            repository: "tangled.org/owner/events",
            branch: "main"
        )
    }

    func review() -> TangledPullReview {
        TangledPullReview(
            author: "did:plc:author",
            body: "Updates the published event details.",
            commentCount: 2,
            createdAt: "2026-08-04T18:00:00Z",
            patchBlobs: [],
            sourceBranch: "ome/proposal-event-details",
            sourceRepositoryDID: "did:plc:author-repository",
            state: "open",
            stateUpdatedAt: "2026-08-04T18:10:00Z",
            targetBranch: "main",
            targetRepositoryDID: "did:plc:owner-repository",
            title: "Update event details",
            uri: "at://did:plc:author/sh.tangled.repo.pull/review-1"
        )
    }

    func makePreparedDatabase() throws -> any DatabaseWriter {
        try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            @Dependency(\.defaultDatabase) var database
            return database
        }
    }

    func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while clock.now < deadline {
            if condition() { return }
            try? await clock.sleep(for: .milliseconds(1))
        }
        Issue.record(
            "Condition was not satisfied within one second.",
            sourceLocation: sourceLocation
        )
    }
}

struct ReviewSourceSnapshotUnavailable: Error {}
struct ReviewProfileUnavailable: Error {}
