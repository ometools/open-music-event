import ATProto
import Bluesky
import Clocks
import ComposableArchitecture2
import ComposableWorkspace
import CustomDump
import Dependencies
import Foundation
import IssueReporting
import ATProtoTypes
import OpenMusicEventLexicon
@testable import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
import SourceEditing
import Testing

@testable import OpenMusicEventAppEventViewer

@MainActor
@Suite("Workspace proposal reviews", .serialized)
struct WorkspaceReviewsTests {
    @Test
    func `the Workspace badge combines local changes and open proposals`() throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let eventID = OME.Event.ID(
            organizerID: workspace.organizerID,
            eventID: OME.ID<OME.Event>(rawValue: "workspace-badges")
        )
        var state = withDependencies {
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            EventWorkspace.State(
                workspace: workspace,
                eventID: eventID,
                workspaceState: SharedReader(
                    value: WorkspaceState(
                        id: WorkspaceID(rawValue: workspace.id.rawValue)
                    )
                )
            )
        }
        state.changes.$summary = Fetch(
            wrappedValue: SourceWorkspaceEditSummary(
                workspaceID: workspace.id,
                availability: .available,
                groups: [
                    SourceChangeGroup(
                        id: "event-records",
                        displayName: "Events",
                        added: 1,
                        modified: 2,
                        deleted: 0
                    )
                ]
            )
        )

        // Three local edits explain the badge while the remote proposal count is still unknown.
        expectNoDifference(state.changeCount, 3)
        expectNoDifference(state.openProposalCount, nil)
        expectNoDifference(state.badgeCount, 3)

        // Once proposals load, their count joins the Workspace badge.
        state.reviews.status = .loaded([proposalListItem()])
        expectNoDifference(state.openProposalCount, 1)
        expectNoDifference(state.badgeCount, 4)

        // A local receipt represents the same proposal while its server projection catches up.
        state.reviews.$publicationReceipts = Fetch(
            wrappedValue: [workspaceProposal(revision: "source-revision")]
        )
        expectNoDifference(state.openProposalCount, 1)
        expectNoDifference(state.badgeCount, 4)

        // Opening Proposals presents the already-loaded list without losing either count.
        state.openProposalList()
        expectNoDifference(state.navigationDestination, .proposals)
        expectNoDifference(state.openProposalCount, 1)
        expectNoDifference(state.badgeCount, 4)
    }

    @Test
    func `recording a proposal refreshes an already-loaded list without clearing it`() async throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let existing = proposalListItem()
        let createdURI = try #require(
            ATProto.URI("at://did:plc:owner/sh.tangled.repo.pull/created")
        )
        let created = {
            var proposal = proposalListItem()
            proposal.uri = createdURI
            proposal.title = "Created proposal"
            proposal.updatedAt = proposalDate.addingTimeInterval(1)
            return proposal
        }()
        let detail = proposalDetail()
        let store = makeStore(
            database: database,
            workspace: workspace,
            proposals: [existing],
            list: { _ in [existing, created] },
            detail: { _ in detail },
            preloadedProposals: true
        )

        await store.send(.proposalRecorded)?.value

        await waitUntil { store.proposals == [created, existing] }
        expectNoDifference(store.status, .loaded([created, existing]))
    }

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
    func `a hydrated patch proposal remains available before its changes are rendered`(
        renderStatus: OME.WorkspaceProposal.RenderStatus
    ) async throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let receipt = workspaceProposal(revision: "0cfcf74f19973c463bcb34fb0f2e676920592c9a")
        var item = proposalListItem()
        item.renderStatus = renderStatus
        var detail = proposalDetail()
        detail.source = nil
        detail.renderStatus = renderStatus
        detail.presentation = nil
        let hydratedDetail = detail

        expectNoDifference(
            try WorkspaceProposalObservation.observe(
                detail,
                proposalURI: proposalURI,
                request: OpenMusicEventWorkspaceProposalListRequest(workspace: workspace),
                expectedProposal: receipt
            ),
            .available(detail)
        )

        // The app has durably recorded its successful publication receipt.
        let persistence = WorkspacePublicationPersistence(database: database)
        let checkpoint = try await persistence.checkpoint(
            workspaceID: workspace.id,
            attempt: WorkspaceProposalAttempt(
                changes: SourcePatch(),
                details: WorkspaceProposalDetails(
                    title: try #require(WorkspaceProposalTitle("Improve the source"))
                ),
                target: receipt.target
            )
        )
        try await persistence.savePublishedProposal(
            receipt,
            checkpoint: checkpoint,
            workspaceID: workspace.id
        )

        let store = makeStore(
            database: database,
            workspace: workspace,
            proposals: [item],
            detail: { _ in hydratedDetail },
            grant: try ownerGrant(workspace: workspace)
        )

        // The patch-only record hydrates without inventing a source branch or rendered preview.
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
    func `published receipt opens immediately and waits for its exact rendered revision`() async throws {
        let database = try makePreparedDatabase()
        let workspace = try workspace()
        let receipt = workspaceProposal(revision: "new-revision")
        let stale = proposalDetail(revision: "old-revision")
        let rendering = {
            var detail = proposalDetail(revision: "new-revision")
            detail.renderStatus = .pending
            detail.presentation = nil
            return detail
        }()
        let ready = proposalDetail(revision: "new-revision")
        let responses = LockIsolated([stale, rendering, ready])
        let eventID = OME.Event.ID(
            organizerID: workspace.organizerID,
            eventID: OME.ID<OME.Event>(rawValue: "workspace-reviews")
        )
        let grant = try ownerGrant(workspace: workspace)

        let store = withDependencies {
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.continuousClock = ImmediateClock()
            $0.workspaceProposalProjectionRetryDelays = [.zero, .zero]
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

    @Test
    func addedProposalRecordUsesItsAfterSnapshotWithoutDatabaseHydration() {
        let proposed = proposalCalendar(name: "Wicked Woods 2027")
        let snapshot = proposalSnapshot(
            title: nil,
            kind: .added,
            after: .known(.calendar(proposed))
        )

        expectNoDifference(snapshot.record, .calendar(proposed))
        #expect(snapshot.previousSnapshot == nil)
        #expect(snapshot.title == "Wicked Woods 2027")
        #expect(snapshot.collectionName == "Calendars")
        #expect(snapshot.contextTitle == "Added in this proposal")
    }

    @Test
    func modifiedProposalRecordUsesAfterAndKeepsBeforeForPreviousVersion() {
        let previous = proposalCalendar(name: "Wicked Woods 2026")
        let proposed = proposalCalendar(name: "Wicked Woods 2027")
        let snapshot = proposalSnapshot(
            kind: .modified,
            before: .known(.calendar(previous)),
            after: .known(.calendar(proposed))
        )

        expectNoDifference(snapshot.record, .calendar(proposed))
        expectNoDifference(snapshot.previousSnapshot?.record, .calendar(previous))
        #expect(snapshot.contextTitle == "Proposed version")
        #expect(snapshot.previousSnapshot?.contextTitle == "Previous version")
    }

    @Test
    func removedProposalRecordUsesItsBeforeSnapshot() {
        let removed = proposalCalendar(name: "Wicked Woods 2026")
        let snapshot = proposalSnapshot(
            kind: .deleted,
            before: .known(.calendar(removed))
        )

        expectNoDifference(snapshot.record, .calendar(removed))
        #expect(snapshot.previousSnapshot == nil)
        #expect(snapshot.contextTitle == "Removed by this proposal")
    }

    @Test
    func malformedModifiedRecordStillOffersItsAvailablePreviousSnapshot() {
        let previous = proposalCalendar(name: "Wicked Woods 2026")
        let snapshot = proposalSnapshot(
            title: "Wicked Woods",
            kind: .modified,
            before: .known(.calendar(previous)),
            after: nil
        )

        #expect(snapshot.record == nil)
        #expect(snapshot.title == "Wicked Woods")
        expectNoDifference(snapshot.previousSnapshot?.record, .calendar(previous))
    }

    @Test
    func unknownProposalRecordUsesFriendlyUnavailablePresentation() {
        let unknown: Open<OME.WorkspaceProposal.SourceRecord> = .unknown(
            .object(["$type": .string("example.music.customRecord")])
        )
        let snapshot = proposalSnapshot(
            title: "Custom record",
            groupName: "CommsPost",
            kind: .added,
            after: unknown
        )

        #expect(snapshot.record == nil)
        #expect(snapshot.title == "Custom record")
        #expect(snapshot.collectionName == "Posts")
        #expect(snapshot.recordType == .unavailable)
    }

    func proposalSnapshot(
        title: String? = nil,
        groupName: String = "Calendars",
        kind: OME.WorkspaceProposal.Presentation.Transition.Kind,
        before: Open<OME.WorkspaceProposal.SourceRecord>? = nil,
        after: Open<OME.WorkspaceProposal.SourceRecord>? = nil
    ) -> ProposalRecordSnapshot {
        ProposalRecordSnapshot(
            record: OME.WorkspaceProposal.Presentation.Record(
                id: "calendar",
                title: title,
                transition: OME.WorkspaceProposal.Presentation.Transition(
                    kind: kind,
                    before: before,
                    after: after
                ),
                changedFields: ["name"],
                sourceFiles: ["calendar.yml"]
            ),
            groupName: groupName
        )
    }

    func proposalCalendar(name: String) -> OME.Calendar {
        OME.Calendar(
            id: OME.Calendar.ID(
                ownerID: targetRepositoryDID,
                calendarID: OME.ID<OME.Calendar>(rawValue: "calendar")
            ),
            name: name,
            description: "The festival calendar"
        )
    }

    func makeStore(
        database: any DatabaseWriter,
        workspace: SourceWorkspace,
        proposals: [OME.WorkspaceProposal.ListItem],
        list: (@Sendable (
            OpenMusicEventWorkspaceProposalListRequest
        ) async throws -> [OME.WorkspaceProposal.ListItem])? = nil,
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
                list: list ?? { _ in proposals },
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
