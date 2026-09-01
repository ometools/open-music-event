import ATProto
import BlueskyActorCache
import Clocks
import ComposableArchitecture2
import ComposableWorkspace
import CustomDump
import Dependencies
import Foundation
import IssueReporting
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SQLiteData
import Testing

@testable import OpenMusicEventAppEventViewer

@MainActor
@Suite("Workspace proposal reviews", .serialized)
struct WorkspaceReviewsTests {
    @Test
    func detailResponseMustMatchTheRequestedProposalURI() throws {
        let workspace = try workspace()
        let request = try OpenMusicEventWorkspaceProposalListRequest(workspace: workspace)
        let requestedURI = proposalURI
        var detail = proposalDetail()
        detail.uri = try #require(
            ATProto.URI("at://did:plc:other/sh.tangled.repo.pull/review-2")
        )

        #expect(throws: WorkspaceProposalObservation.Error.proposalURIMismatch(
            expected: requestedURI,
            actual: detail.uri
        )) {
            try WorkspaceProposalObservation.observe(
                detail,
                proposalURI: requestedURI,
                request: request,
                expectedProposal: nil
            )
        }
    }

    @Test
    func ownerLoadsAppViewProposalsOpensServerPresentationAndMerges() async throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let item = proposalListItem()
        let detail = proposalDetail()
        let mergeRequests = LockIsolated<[OpenMusicEventWorkspaceProposalMergeRequest]>([])
        let store = makeStore(
            database: database,
            workspace: workspace,
            proposals: [item],
            detail: { _ in detail },
            grant: try ownerGrant(workspace: workspace),
            merge: { request in
                mergeRequests.withValue { $0.append(request) }
            }
        )

        await waitUntil { store.proposals == [item] }
        await store.send(.proposalButtonTapped(item))?.value
        await waitUntil {
            guard case let .reviewDetail(state)? = store.destination,
                  case let .loaded(loaded) = state.status
            else { return false }
            return loaded == detail && state.canMerge
        }

        await store.send(.destination(.reviewDetail(.mergeButtonTapped)))?.value
        await waitUntil { store.destination == nil }

        expectNoDifference(
            mergeRequests.value,
            [
                OpenMusicEventWorkspaceProposalMergeRequest(
                    target: OpenMusicEventSourceTarget(workspace: workspace),
                    proposal: detail
                )
            ]
        )
        #expect(store.proposals.isEmpty)
        expectNoDifference(
            store.locallyRemovedProposalURIs,
            Set([item.uri.description])
        )
    }

    @Test(arguments: [
        OME.WorkspaceProposal.RenderStatus.awaitingInput,
        .pending,
    ])
    func `a hydrated proposal remains available before its changes are rendered`(
        renderStatus: OME.WorkspaceProposal.RenderStatus
    ) async throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let receipt = workspaceProposal(revision: "source-revision")
        var item = proposalListItem()
        item.renderStatus = renderStatus
        var detail = proposalDetail()
        detail.renderStatus = renderStatus
        detail.presentation = nil
        let hydratedDetail = detail

        // The app has durably recorded its successful publication receipt.
        try await SourceWorkspaceContextStore(database: database).saveProposalContext(
            receipt,
            workspaceID: workspace.id
        )

        let store = makeStore(
            database: database,
            workspace: workspace,
            proposals: [item],
            detail: { _ in hydratedDetail },
            grant: try ownerGrant(workspace: workspace)
        )

        // Hydration replaces the local publication placeholder even without a rendered preview.
        await waitUntil {
            store.proposals == [item]
                && store.pendingProjectionReceipts.isEmpty
        }
        expectNoDifference(store.proposals, [item])
        expectNoDifference(store.pendingProjectionReceipts, [])

        // The organizer can inspect and close the proposal, but cannot merge unseen changes.
        await store.send(.proposalButtonTapped(item))?.value
        await waitUntil {
            guard case let .reviewDetail(state)? = store.destination,
                  case let .loaded(loaded) = state.status
            else { return false }
            return loaded == detail && state.canClose && !state.canMerge
        }
        guard case let .reviewDetail(state)? = store.destination else {
            Issue.record("The hydrated proposal should open from the server projection.")
            return
        }
        expectNoDifference(state.proposal, detail)
        #expect(state.canClose)
        #expect(!state.canMerge)
    }

    @Test
    func publishedReceiptOpensImmediatelyAndWaitsForItsExactRevision() async throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let receipt = workspaceProposal(revision: "new-revision")
        let stale = proposalDetail(revision: "old-revision")
        let ready = proposalDetail(revision: "new-revision")
        let responses = LockIsolated([stale, ready])
        let eventID = OME.Event.ID(
            organizerID: workspace.organizerID,
            eventID: OME.ID<OME.Event>(rawValue: "workspace-reviews")
        )
        let grant = try ownerGrant(workspace: workspace)

        let store = withDependencies {
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.continuousClock = ImmediateClock()
            $0.workspaceProposalProjectionRetryDelays = [.zero]
            $0.blueskyActorProfileCache = actorCache
            $0.workspaceProposalClient = WorkspaceProposalClient(
                list: { _ in [] },
                detail: { _ in
                    responses.withValue { values in
                        values.isEmpty ? ready : values.removeFirst()
                    }
                }
            )
        } operation: {
            var state = WorkspaceReviews.State(
                workspace: workspace,
                authoringGrant: grant
            )
            state.open(receipt)
            guard case let .reviewDetail(detail)? = state.destination else {
                Issue.record("A successful publication receipt must open immediately.")
                return Store(initialState: state) { WorkspaceReviews() }
            }
            expectNoDifference(detail.expectedProposal, receipt)
            expectNoDifference(detail.proposalURI.description, receipt.id.rawValue)
            return Store(initialState: state) { WorkspaceReviews() }
        }

        await waitUntil {
            guard case let .reviewDetail(detail)? = store.destination,
                  case let .loaded(proposal) = detail.status
            else { return false }
            return proposal == ready && detail.canMerge
        }
        #expect(responses.value.isEmpty)
    }

    @Test
    func collaboratorCanCloseButCannotMergeAProposal() async throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let item = proposalListItem()
        let detail = proposalDetail()
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
            proposals: [item],
            detail: { _ in detail },
            grant: grant,
            merge: { _ in mutations.withValue { $0.append("merge") } },
            close: { _ in mutations.withValue { $0.append("close") } }
        )

        await waitUntil { store.proposals == [item] }
        await store.send(.proposalButtonTapped(item))?.value
        await waitUntil {
            guard case let .reviewDetail(state)? = store.destination,
                  case .loaded = state.status
            else { return false }
            return state.canClose && !state.canMergeProposals && !state.canMerge
        }

        await store.send(.destination(.reviewDetail(.mergeButtonTapped)))?.value
        #expect(mutations.value.isEmpty)

        await store.send(.destination(.reviewDetail(.closeButtonTapped)))?.value
        await waitUntil { store.destination == nil }

        expectNoDifference(mutations.value, ["close"])
        #expect(store.proposals.isEmpty)
    }

    @Test
    func mismatchedServerProjectionFailsEphemerallyThenRetryRecovers() async throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let item = proposalListItem()
        let wrongSource = try #require(
            ATProto.URI("at://did:plc:other/sh.tangled.repo/other-events")
        )
        let mismatched = proposalDetail(canonicalSource: wrongSource)
        let ready = proposalDetail()
        let responses = LockIsolated([mismatched, ready])
        let mutations = LockIsolated<[String]>([])
        let store = makeStore(
            database: database,
            workspace: workspace,
            proposals: [item],
            detail: { _ in
                responses.withValue { values in
                    values.isEmpty ? ready : values.removeFirst()
                }
            },
            grant: try ownerGrant(workspace: workspace),
            merge: { _ in mutations.withValue { $0.append("merge") } },
            close: { _ in mutations.withValue { $0.append("close") } }
        )

        await waitUntil { store.proposals == [item] }
        try await expectReportedIssue(containing: "Proposal source mismatch") {
            await store.send(.proposalButtonTapped(item))?.value
            await waitUntil {
                guard case let .reviewDetail(detail)? = store.destination,
                      case .failed = detail.status
                else { return false }
                return !detail.canClose && !detail.canMerge
            }
        }
        await store.send(.destination(.reviewDetail(.mergeButtonTapped)))?.value
        await store.send(.destination(.reviewDetail(.closeButtonTapped)))?.value
        #expect(mutations.value.isEmpty)

        await store.send(.destination(.reviewDetail(.retryButtonTapped)))?.value
        await waitUntil {
            guard case let .reviewDetail(detail)? = store.destination,
                  case .loaded = detail.status
            else { return false }
            return detail.canClose && detail.canMerge
        }
        #expect(responses.value.isEmpty)
    }

    @Test
    func `a grant for another workspace can read but cannot change a proposal`() async throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let item = proposalListItem()
        let detail = proposalDetail()
        let mutations = LockIsolated<[String]>([])
        let otherWorkspace = SourceWorkspace(
            organizerID: workspace.organizerID,
            repository: "at://did:plc:owner/sh.tangled.repo/other-events",
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
            proposals: [item],
            detail: { _ in detail },
            grant: grant,
            merge: { _ in mutations.withValue { $0.append("merge") } },
            close: { _ in mutations.withValue { $0.append("close") } },
            preloadedProposals: true
        )

        await store.send(.proposalButtonTapped(item))?.value
        guard case let .reviewDetail(state)? = store.destination,
              case .loaded = state.status
        else {
            Issue.record("The proposal should remain readable without a matching authoring grant.")
            return
        }
        #expect(!state.canClose)
        #expect(!state.canMerge)

        await store.send(.destination(.reviewDetail(.mergeButtonTapped)))?.value
        await store.send(.destination(.reviewDetail(.closeButtonTapped)))?.value
        #expect(mutations.value.isEmpty)
    }

    func makeStore(
        database: any DatabaseWriter,
        workspace: SourceWorkspace,
        proposals: [OME.WorkspaceProposal.ListItem],
        detail: @escaping @Sendable (
            ATProto.URI
        ) async throws -> OME.WorkspaceProposal.Detail,
        grant: AuthoringGrant? = nil,
        merge: @escaping @Sendable (
            OpenMusicEventWorkspaceProposalMergeRequest
        ) async throws -> Void = { _ in },
        close: @escaping @Sendable (ATProto.URI) async throws -> Void = { _ in },
        preloadedProposals: Bool = false
    ) -> StoreOf<WorkspaceReviews> {
        let eventID = OME.Event.ID(
            organizerID: workspace.organizerID,
            eventID: OME.ID<OME.Event>(rawValue: "workspace-reviews")
        )
        return withDependencies {
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.continuousClock = ImmediateClock()
            $0.workspaceProposalProjectionRetryDelays = [.zero]
            $0.blueskyActorProfileCache = actorCache
            $0.workspaceProposalClient = WorkspaceProposalClient(
                list: { _ in proposals },
                detail: detail,
                close: close,
                merge: merge
            )
        } operation: {
            var state = WorkspaceReviews.State(
                workspace: workspace,
                authoringGrant: grant
            )
            if preloadedProposals {
                state.status = .loaded(proposals)
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
            repository: canonicalSource.description,
            branch: "main"
        )
    }

    func ownerGrant(workspace: SourceWorkspace) throws -> AuthoringGrant {
        AuthoringGrant(
            principal: AuthoringPrincipal(
                actorID: try #require(DID(workspace.organizerID.description))
            ),
            role: .owner,
            workspaceID: workspace.id
        )
    }

    func proposalListItem() -> OME.WorkspaceProposal.ListItem {
        OME.WorkspaceProposal.ListItem(
            uri: proposalURI,
            canonicalSource: canonicalSource,
            title: "Update event details",
            authorDID: authorDID,
            status: .open,
            targetBranch: "main",
            createdAt: proposalDate,
            updatedAt: proposalDate,
            pullNumber: 42,
            pageURL: URL(string: "https://tangled.org/owner/events/pulls/42"),
            renderStatus: .ready
        )
    }

    func proposalDetail(
        canonicalSource: ATProto.URI? = nil,
        revision: String = "source-revision"
    ) -> OME.WorkspaceProposal.Detail {
        OME.WorkspaceProposal.Detail(
            uri: proposalURI,
            canonicalSource: canonicalSource ?? self.canonicalSource,
            title: "Update event details",
            body: "Updates the published event details.",
            authorDID: authorDID,
            status: .open,
            targetRepositoryDID: targetRepositoryDID,
            targetBranch: "main",
            source: OME.WorkspaceProposal.Source(
                repositoryDID: sourceRepositoryDID,
                branch: "ome/proposal-event-details",
                revision: revision
            ),
            createdAt: proposalDate,
            updatedAt: proposalDate,
            pullNumber: 42,
            roundNumber: 1,
            pageURL: URL(string: "https://tangled.org/owner/events/pulls/42"),
            patchURL: URL(string: "https://tangled.org/owner/events/pulls/42.patch"),
            recordCID: ATProto.CID("bafyreiproposal"),
            recordAvailability: .present,
            renderStatus: .ready,
            presentation: OME.WorkspaceProposal.Presentation(
                groups: [
                    OME.WorkspaceProposal.Presentation.Group(
                        id: "events",
                        displayName: "Event details",
                        records: [
                            OME.WorkspaceProposal.Presentation.Record(
                                id: "event",
                                title: "Wicked Woods",
                                transition: OME.WorkspaceProposal.Presentation.Transition(
                                    kind: .modified
                                ),
                                changedFields: ["name"],
                                sourceFiles: ["events/wicked-woods.yml"]
                            )
                        ]
                    )
                ]
            )
        )
    }

    func workspaceProposal(revision: String) -> WorkspaceProposal {
        WorkspaceProposal(
            id: WorkspaceProposalID(rawValue: proposalURI.description),
            revision: WorkspaceRevision(rawValue: revision),
            target: WorkspaceBranchReference(
                branch: WorkspaceBranch(rawValue: "main"),
                revision: WorkspaceRevision(rawValue: "target-revision")
            )
        )
    }

    var actorCache: BlueskyActorProfileCacheClient {
        BlueskyActorProfileCacheClient(
            cachedProfile: { _ in nil },
            refreshProfile: { _ in throw ReviewProfileUnavailable() },
            refreshProfileIfNeeded: { _, _, _ in nil }
        )
    }

    var proposalURI: ATProto.URI {
        ATProto.URI("at://did:plc:author/sh.tangled.repo.pull/review-1")!
    }

    var canonicalSource: ATProto.URI {
        ATProto.URI("at://did:plc:owner/sh.tangled.repo/events")!
    }

    var authorDID: DID { DID("did:plc:author")! }
    var sourceRepositoryDID: DID { DID("did:plc:author-repository")! }
    var targetRepositoryDID: DID { DID("did:plc:owner-repository")! }
    var proposalDate: Date { Date(timeIntervalSince1970: 1_775_000_000) }

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

struct ReviewProfileUnavailable: Error {}
