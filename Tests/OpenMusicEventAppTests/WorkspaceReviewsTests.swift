import ATProto
import BlueskyActorCache
import ComposableArchitecture2
import CustomDump
import Dependencies
import FileTree
import Foundation
import IssueReporting
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
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

        await waitUntil { store.reviews.contains(where: { $0.id == review.id }) }
        try await expectReportedIssue(containing: "ReviewSourceSnapshotUnavailable") {
            #expect(store.canReview)
            await store.send(.reviewButtonTapped(review))?.value
            #expect(store.destination != nil)
            await waitUntil {
                guard case let .reviewDetail(detail)? = store.destination else { return false }
                guard case .failed = detail.semanticDiffStatus else { return false }
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
                    repository: .target(review.targetRepositoryDID),
                    ref: review.targetBranch,
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
    func semanticChangesCompareTheReviewSourceRepositoryToItsTargetRepository() async throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let review = review()
        let grant = AuthoringGrant(
            principal: AuthoringPrincipal(
                actorID: try #require(DID(workspace.organizerID.description))
            ),
            role: .owner,
            workspaceID: workspace.id
        )
        let requests = LockIsolated<[TangledPullReviewSourceSnapshotRequest]>([])
        let targetInsertion = try reviewInsertion(
            workspace: workspace,
            eventName: "Published event"
        )
        let sourceInsertion = try reviewInsertion(
            workspace: workspace,
            eventName: "Proposed event"
        )
        let store = makeStore(
            database: database,
            workspace: workspace,
            review: review,
            grant: grant,
            sourceSnapshotRequests: requests,
            sourceSnapshot: { request in
                switch request.repository {
                case .target:
                    targetInsertion
                case .source:
                    sourceInsertion
                }
            }
        )

        await waitUntil { store.reviews.contains(where: { $0.id == review.id }) }
        #expect(store.canReview)
        await store.send(.reviewButtonTapped(review))?.value
        #expect(store.destination != nil)
        await waitUntil {
            guard case let .reviewDetail(detail)? = store.destination,
                  case .loaded = detail.semanticDiffStatus
            else { return false }
            return true
        }

        expectNoDifference(
            requests.value,
            [
                TangledPullReviewSourceSnapshotRequest(
                    organizerID: workspace.organizerID,
                    repository: .target(review.targetRepositoryDID),
                    ref: review.targetBranch,
                    sourceProvenance: workspace.sourceProvenance
                ),
                TangledPullReviewSourceSnapshotRequest(
                    organizerID: workspace.organizerID,
                    repository: .source(try #require(review.sourceRepositoryDID)),
                    ref: try #require(review.sourceBranch),
                    sourceProvenance: workspace.sourceProvenance
                ),
            ]
        )
        guard case let .reviewDetail(detail)? = store.destination,
              case let .loaded(diff) = detail.semanticDiffStatus
        else {
            Issue.record("The proposal must render its source-to-target semantic changes.")
            return
        }
        expectNoDifference(diff.totalCount, 1)
        #expect(diff.groups.contains { $0.modified == 1 })
    }

    @Test
    func collaboratorCanCloseButCannotMergeAProposal() async throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let review = review()
        let mutations = LockIsolated<[String]>([])
        let grant = AuthoringGrant(
            principal: AuthoringPrincipal(
                actorID: try #require(DID("did:plc:proposer"))
            ),
            role: .collaborator([.propose]),
            workspaceID: workspace.id
        )
        let store = makeStore(
            database: database,
            workspace: workspace,
            review: review,
            grant: grant,
            merge: { _ in mutations.withValue { $0.append("merge") } },
            close: { _ in mutations.withValue { $0.append("close") } }
        )

        await waitUntil { store.reviews.contains(where: { $0.id == review.id }) }
        try await expectReportedIssue(containing: "ReviewSourceSnapshotUnavailable") {
            #expect(store.canReview)
            await store.send(.reviewButtonTapped(review))?.value
            #expect(store.destination != nil)
            await waitUntil {
                guard case let .reviewDetail(detail)? = store.destination else { return false }
                guard case .failed = detail.semanticDiffStatus else { return false }
                return detail.canClose && !detail.canMergeProposals && !detail.canMerge
            }
        }

        await store.send(.destination(.reviewDetail(.mergeButtonTapped)))?.value
        #expect(mutations.value.isEmpty)

        await store.send(.destination(.reviewDetail(.closeButtonTapped)))?.value
        await waitUntil { store.destination == nil }

        expectNoDifference(mutations.value, ["close"])
        #expect(store.reviews.isEmpty)
    }

    @Test
    func pendingCreatedProposalNavigatesWhenTheReviewAppears() throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let review = review()
        let eventID = OME.Event.ID(
            organizerID: workspace.organizerID,
            eventID: OME.ID<OME.Event>(rawValue: "workspace-reviews")
        )
        withDependencies {
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            var state = WorkspaceReviews.State(workspace: workspace)
            state.requestedReviewID = review.id
            state.status = .loaded([review])

            state.openRequestedReviewIfAvailable()

            expectNoDifference(state.requestedReviewID, nil)
            guard case let .reviewDetail(detail)? = state.destination else {
                Issue.record("The hydrated pending proposal must open its detail.")
                return
            }
            expectNoDifference(detail.review, review)
            expectNoDifference(detail.workspace, workspace)
        }
    }

    @Test
    func grantForAnotherWorkspaceCannotChangeAProposal() async throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let review = review()
        let mutations = LockIsolated<[String]>([])
        let otherWorkspace = SourceWorkspace(
            organizerID: workspace.organizerID,
            repository: "tangled.org/owner/other-events",
            branch: "main"
        )
        let grant = AuthoringGrant(
            principal: AuthoringPrincipal(actorID: try #require(DID("did:plc:owner"))),
            role: .owner,
            workspaceID: otherWorkspace.id
        )
        let store = makeStore(
            database: database,
            workspace: workspace,
            review: review,
            grant: grant,
            merge: { _ in mutations.withValue { $0.append("merge") } },
            close: { _ in mutations.withValue { $0.append("close") } },
            preloadedReviews: true
        )

        await store.send(.reviewButtonTapped(review))?.value
        #expect(store.destination == nil)
        #expect(mutations.value.isEmpty)
    }

    func makeStore(
        database: any DatabaseWriter,
        workspace: SourceWorkspace,
        review: TangledPullReview,
        grant: AuthoringGrant? = nil,
        merge: @escaping @Sendable (
            OpenMusicEventTangledPullReviewMergeRequest
        ) async throws -> Void = { _ in },
        close: @escaping @Sendable (TangledPullReview) async throws -> Void = { _ in },
        sourceSnapshotRequests: LockIsolated<[TangledPullReviewSourceSnapshotRequest]>? = nil,
        sourceSnapshot: @escaping @Sendable (
            TangledPullReviewSourceSnapshotRequest
        ) async throws -> OME.SourceDatabaseInsertion = { _ in
            throw ReviewSourceSnapshotUnavailable()
        },
        preloadedReviews: Bool = false
    ) -> StoreOf<WorkspaceReviews> {
        let eventID = OME.Event.ID(
            organizerID: workspace.organizerID,
            eventID: OME.ID<OME.Event>(rawValue: "workspace-reviews")
        )
        return withDependencies {
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
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
                rawDiff: { _ in "Rendered remote patch" }
            )
            $0.tangledPullReviewSourceSnapshot = TangledPullReviewSourceSnapshotClient(
                insertion: { request in
                    sourceSnapshotRequests?.withValue { $0.append(request) }
                    return try await sourceSnapshot(request)
                }
            )
        } operation: {
            var state = WorkspaceReviews.State(
                workspace: workspace,
                authoringGrant: grant
            )
            if preloadedReviews {
                state.status = .loaded([review])
            }
            return Store(initialState: state) {
                WorkspaceReviews()
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

    func reviewInsertion(
        workspace: SourceWorkspace,
        eventName: String
    ) throws -> OME.SourceDatabaseInsertion {
        let eventID = OME.Event.ID(
            organizerID: workspace.organizerID,
            eventID: OME.ID<OME.Event>(rawValue: "workspace-reviews")
        )
        let event = OpenMusicEventSourceEvent(
            event: EventDTO(
                id: eventID,
                name: eventName,
                description: nil,
                startDate: nil,
                endDate: nil,
                status: nil,
                mode: nil,
                locations: nil,
                uris: nil,
                timeZone: try #require(TimeZone(identifier: "America/Denver")),
                images: nil,
                contactNumbers: nil,
                categoryConfigs: nil
            )
        )
        return try OME.SourceDatabaseInsertion(
            .init(
                source: OpenMusicEventSourceRepository(
                    events: [
                        DirectoryContent(
                            directoryName: "workspace-reviews",
                            components: event
                        )
                    ]
                ),
                organizerID: workspace.organizerID,
                sourceProvenance: workspace.sourceProvenance
            )
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
