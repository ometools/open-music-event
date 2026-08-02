import BlueskyActorCache
import Clocks
import ComposableArchitecture2
import CustomDump
import Dependencies
import DependenciesTestSupport
import ErrorHandling
import FileTree
import Foundation
import GRDB
import HTTPClient
import HTTPTypes
import IssueReporting
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import Sharing
import SourceEditing
import SQLiteData
import Synchronization
import Testing

@testable import ATProtoOAuth
@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

@MainActor
@Suite(
    .tcaExhaustivity(.off),
    .serialized,
    .dependencies { $0.defaultPort = 443 }
)
struct EventWorkspaceSourcePatchInvalidationTests {
    @Test
    func observedSourceSummaryTracksWritesToTheOriginalApplicationDatabase() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let mainDatabase = try makePreparedDatabase(
            at: directoryURL.appending(path: "app.sqlite")
        )
        let eventID = testEventID("event-1")
        try await seedSourceBackedEvent(eventID, in: mainDatabase)
        try await seedEditingWorkspace(for: eventID, in: mainDatabase)
        let baselineDatabase = try defaultBaselineDatabase(
            path: directoryURL.appending(path: "baseline.sqlite").path()
        )
        try mainDatabase.backup(to: baselineDatabase.database)
        try await mainDatabase.write { db in
            try db.execute(
                sql: "CREATE TABLE observation_noise (id INTEGER PRIMARY KEY)"
            )
        }

        let state = withDependencies {
            $0.defaultDatabase = mainDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.workspaceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            WorkspaceChanges.State(target: .event(eventID))
        }
        try await waitForCondition {
            state.sourceWorkspaceSummary.availability == .available
        }
        #expect(state.sourceWorkspaceSummary.totalCount == 0)

        try await mainDatabase.write { db in
            try db.execute(sql: "INSERT INTO observation_noise DEFAULT VALUES")
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(state.sourceWorkspaceSummary.totalCount == 0)

        try await mainDatabase.write { db in
            try OME.Event
                .find(eventID)
                .update { $0.name = "Observed Source Event" }
                .execute(db)
        }
        try await waitForCondition {
            state.sourceWorkspaceSummary.totalCount == 1
        }
        #expect(state.sourceWorkspaceSummary.totalCount == 1)
    }

    @Test
    func workspaceOwnerAndReviewAuthorObserveOneActorIdentityCache() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let review = testTangledPullReview()
        try await seedTangledSourceBackedEvent(eventID, in: database)
        var state = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            EventWorkspace.State(eventID: eventID)
        }
        state.reviews.reviewsStatus = .loaded([review])

        try await waitForCondition {
            state.reviews.sourceProvenance != nil
        }
        #expect(state.reviews.workspaceOwnerIdentity == .unavailable)
        #expect(state.reviews.reviewAuthorIdentities[review.author] == .unavailable)

        try await database.write { db in
            try BlueskyActorProfile.insert {
                BlueskyActorProfile(
                    did: "did:plc:owner123",
                    handle: "woody.fm",
                    displayName: "Woody"
                )
            }
            .execute(db)
            try BlueskyActorProfileCacheEntry.insert {
                BlueskyActorProfileCacheEntry(
                    actor: "woody.fm",
                    did: "did:plc:owner123"
                )
            }
            .execute(db)
            try BlueskyActorProfile.insert {
                BlueskyActorProfile(
                    did: review.author,
                    handle: "reviewer.example.com",
                    displayName: "Review Author"
                )
            }
            .execute(db)
            try BlueskyActorProfileCacheEntry.insert {
                BlueskyActorProfileCacheEntry(
                    actor: review.author,
                    did: review.author
                )
            }
            .execute(db)
        }

        try await waitForCondition {
            guard case let .loaded(owner) = state.reviews.workspaceOwnerIdentity,
                  case let .loaded(author) =
                    state.reviews.reviewAuthorIdentities[review.author]
            else { return false }
            return owner.displayName == "Woody"
                && author.displayName == "Review Author"
        }
    }

    @Test
    func generateSourcePatchButtonLoadsPatch() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let expectedSourceBaselineID = sourceBaselineID(for: eventID)
        try await seedSourceBackedEvent(eventID, in: database)
        let expectedWorkspaceSummary = try SourceWorkspaceSummary.query(
            target: .event(eventID),
            using: database
        )
        let expectedSourceFileAttributions: [SourceFileAttribution] = []
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] = SourcePatchGenerator { request in
                #expect(
                    request == OpenMusicEventCalendarSourcePatchRequest(
                        calendarID: OME.Calendar.ID(
                            ownerID: eventID.organizerID,
                            calendarID: OME.Calendar.defaultID
                        ),
                        sourceBaselineID: expectedSourceBaselineID
                    )
                )
                return patch
            }
        } operation: {
            TestStore(initialState: EventWorkspace.State(eventID: eventID)) {
                EventWorkspace()
            }
        }

        let task = store.send(.changes(.checkChangesButtonTapped))
        await task?.value

        expectNoDifference(
            store.state.changes.sourcePatchStatus,
            .generated(
                WorkspaceChanges.SourceProposalPreparation(
                    patch: patch,
                    sourceFileAttributions: expectedSourceFileAttributions,
                    sourceWorkspaceSummary: expectedWorkspaceSummary
                )
            )
        )
        #expect(store.state.changes.proposalDraft == nil)
        await store.dismount()
    }

    @Test
    func resetEditsButtonResetsDraftAndClearsProposalState() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let database = try makePreparedDatabase(
            at: directoryURL.appending(path: "app.sqlite")
        )
        let eventID = testEventID("event-1")
        try await seedSourceBackedEvent(eventID, in: database)
        try await seedEditingWorkspace(for: eventID, in: database)
        let baselineDatabase = try defaultBaselineDatabase(
            path: directoryURL.appending(path: "baseline.sqlite").path()
        )
        try database.backup(to: baselineDatabase.database)
        try await database.write { db in
            try OME.Event.find(eventID).update { $0.name = "Edited" }.execute(db)
        }
        let authoringDatabase = try makeAuthoringDatabase(
            for: eventID,
            mainDatabase: database,
            baselineDatabase: baselineDatabase
        )
        let resetRequests = Mutex([OpenMusicEventSourceTarget]())
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = authoringDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.workspaceReferenceDatabase = .test(database: baselineDatabase)
            $0.eventWorkspaceResetter = EventWorkspaceResetter(
                reset: { _ in },
                resetSourceChanges: { target in
                    resetRequests.withLock { $0.append(target) }
                }
            )
        } operation: {
            var state = EventWorkspace.State(eventID: eventID)
            state.changes.sourcePatchStatus = .generated(
                WorkspaceChanges.SourceProposalPreparation(
                    patch: patch,
                    sourceWorkspaceSummary: state.changes.sourceWorkspaceSummary
                )
            )
            state.changes.proposalDraft = WorkspaceProposalDraft.State(
                groups: state.changes.sourceWorkspaceSummary.groups,
                recordComparisons: state.changes.sourceWorkspaceSummary.recordComparisons
            )
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        try await waitForCondition {
            store.state.changes.sourceWorkspaceSummary.totalCount == 1
        }
        let task = store.send(.changes(.resetChangesButtonTapped))
        await task?.value

        #expect(store.state.changes.resetStatus == .idle)
        #expect(store.state.changes.sourcePatchStatus.preparation?.patch == SourcePatch())
        #expect(store.state.changes.proposalDraft == nil)
        #expect(resetRequests.withLock { $0 } == [.event(eventID)])
        await store.dismount()
    }

    @Test
    func resetEditsButtonShowsFailure() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let database = try makePreparedDatabase(
            at: directoryURL.appending(path: "app.sqlite")
        )
        let eventID = testEventID("event-1")
        try await seedSourceBackedEvent(eventID, in: database)
        try await seedEditingWorkspace(for: eventID, in: database)
        let baselineDatabase = try defaultBaselineDatabase(
            path: directoryURL.appending(path: "baseline.sqlite").path()
        )
        try database.backup(to: baselineDatabase.database)
        try await database.write { db in
            try OME.Event.find(eventID).update { $0.name = "Edited" }.execute(db)
        }
        let authoringDatabase = try makeAuthoringDatabase(
            for: eventID,
            mainDatabase: database,
            baselineDatabase: baselineDatabase
        )
        let failure = WorkspaceChanges.ResetEditsFailure(ResetEditsTestError.failed)
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = authoringDatabase
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.workspaceReferenceDatabase = .test(database: baselineDatabase)
            $0.eventWorkspaceResetter = EventWorkspaceResetter(
                reset: { _ in },
                resetSourceChanges: { _ in
                    throw ResetEditsTestError.failed
                }
            )
        } operation: {
            var state = EventWorkspace.State(eventID: eventID)
            state.changes.resetStatus = .failed(WorkspaceChanges.ResetEditsFailure(
                ResetEditsTestError.previousFailure
            ))
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        try await waitForCondition {
            store.state.changes.sourceWorkspaceSummary.totalCount == 1
        }
        let task = store.send(.changes(.resetChangesButtonTapped))
        await task?.value

        #expect(store.state.changes.resetStatus == .failed(failure))
        await store.dismount()
    }

    @Test
    func resetterAttachesSourceEditingBaselineToDefaultDatabase() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedSourceBackedEvent(eventID, in: database)
        try await seedEditingWorkspace(for: eventID, in: database)
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let baselineDatabase = try defaultBaselineDatabase(
            path: directoryURL.appending(path: "baseline.sqlite").path()
        )
        try database.backup(to: baselineDatabase.database)

        try await database.write { db in
            try OME.Event
                .find(eventID)
                .update { $0.name = "Updated Source Event" }
                .execute(db)
        }

        let changedSummary = try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.workspaceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try EventWorkspaceSummary.query(eventID: eventID, using: database)
        }
        expectNoDifference(changedSummary.availability, .available)
        expectNoDifference(changedSummary.totalCount, 1)

        try withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.workspaceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try EventWorkspaceResetter.openMusicEvent.reset(eventID)
        }

        let resetSummary = try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.workspaceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try EventWorkspaceSummary.query(eventID: eventID, using: database)
        }
        let restoredEvent = try await database.read { db in
            try OME.Event.find(eventID).fetchOne(db)
        }
        expectNoDifference(restoredEvent?.name, "Source Event")
        expectNoDifference(resetSummary.availability, .available)
        expectNoDifference(resetSummary.totalCount, 0)
    }

    @Test
    func sourcePatchGenerationDoesNotCacheInlineProposal() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedSourceBackedEvent(eventID, in: database)
        let originalPatch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let regeneratedPatch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/contributors/artist.md",
                    kind: .modified,
                    oldContents: Data("Old bio.\n".utf8),
                    newContents: Data("New bio.\n".utf8)
                )
            ]
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] =
                SourcePatchGenerator { _ in regeneratedPatch }
        } operation: {
            var state = EventWorkspace.State(eventID: eventID)
            state.changes.sourcePatchStatus = .generated(
                WorkspaceChanges.SourceProposalPreparation(
                    patch: originalPatch,
                    sourceWorkspaceSummary: state.changes.sourceWorkspaceSummary
                )
            )
            state.changes.proposalDraft = WorkspaceProposalDraft.State(
                groups: state.changes.sourceWorkspaceSummary.groups,
                recordComparisons: state.changes.sourceWorkspaceSummary.recordComparisons
            )
            state.changes.proposalDraft?.title = "Update the event"
            state.changes.proposalDraft?.description = "Describe the changes."
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        let task = store.send(.changes(.checkChangesButtonTapped))
        await task?.value

        #expect(store.state.changes.sourcePatchStatus.preparation?.patch == regeneratedPatch)
        #expect(store.state.changes.proposalDraft == nil)
        await store.dismount()
    }

    @Test
    func emptySourcePatchClearsInlineProposal() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedSourceBackedEvent(eventID, in: database)
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] =
                SourcePatchGenerator { _ in SourcePatch() }
        } operation: {
            var state = EventWorkspace.State(eventID: eventID)
            state.changes.sourcePatchStatus = .generated(
                WorkspaceChanges.SourceProposalPreparation(
                    patch: patch,
                    sourceWorkspaceSummary: state.changes.sourceWorkspaceSummary
                )
            )
            state.changes.proposalDraft = WorkspaceProposalDraft.State(
                groups: state.changes.sourceWorkspaceSummary.groups,
                recordComparisons: state.changes.sourceWorkspaceSummary.recordComparisons
            )
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        let task = store.send(.changes(.checkChangesButtonTapped))
        await task?.value

        #expect(store.state.changes.sourcePatchStatus.preparation?.patch == SourcePatch())
        #expect(store.state.changes.proposalDraft == nil)
        await store.dismount()
    }

    @Test
    func sourceChangesDuringPatchGenerationRequireRegeneration() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let mainDatabase = try makePreparedDatabase(
            at: directoryURL.appending(path: "app.sqlite")
        )
        let eventID = testEventID("event-1")
        try await seedSourceBackedEvent(eventID, in: mainDatabase)
        try await seedEditingWorkspace(for: eventID, in: mainDatabase)
        let baselineDatabase = try defaultBaselineDatabase(
            path: directoryURL.appending(path: "baseline.sqlite").path()
        )
        try mainDatabase.backup(to: baselineDatabase.database)
        let workspaceDatabase = try SourceWorkspaceDatabase(
            workspaceID: EditingWorkspaceRecord.ID(
                sourceBaselineID: sourceBaselineID(for: eventID)
            ),
            mainDatabase: mainDatabase,
            referenceDatabase: baselineDatabase
        )
        let generation = SourcePatchGenerationGate()
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = workspaceDatabase.database
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.workspaceReferenceDatabase = .test(database: baselineDatabase)
            $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] =
                SourcePatchGenerator { _ in
                    await generation.pauseUntilOpened()
                    return SourcePatch()
                }
        } operation: {
            TestStore(initialState: EventWorkspace.State(eventID: eventID)) {
                EventWorkspace()
            }
        }

        let task = store.send(.changes(.checkChangesButtonTapped))
        await generation.waitForStart()
        try await workspaceDatabase.database.write { db in
            try OME.Event.find(eventID).update { $0.name = "Changed while generating" }.execute(db)
        }
        try await waitForCondition {
            store.state.changes.sourceWorkspaceSummary.totalCount == 1
                && store.state.changes.sourcePatchStatus == .needsGeneration
        }
        await generation.open()
        await task?.value

        #expect(store.state.changes.proposalDraft == nil)
        #expect(store.state.changes.sourcePatchStatus == .needsGeneration)
        await store.dismount()
    }

    @Test
    func workspaceAppearanceLoadsTangledPullReviewsForTangledSource() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let sourceProvenance = OME.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/woody.fm/shambhala-ome",
            ref: "main"
        )
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Test Event",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: timeZone,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try SourceBaselineRecord.insert {
                SourceBaselineRecord(
                    source: sourceProvenance,
                    databaseFileName: "baseline.sqlite",
                    importedAt: Date(timeIntervalSince1970: 0)
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceBaselineID: sourceBaselineID,
                    sourceKind: sourceProvenance.kind,
                    sourceReference: sourceProvenance.reference,
                    ref: sourceProvenance.ref,
                    eventIDOrigin: .explicit,
                    sourceEventDirectory: "event-1"
                )
            }
            .execute(db)
        }
        let review = TangledPullReview(
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
            state: "open",
            targetBranch: "main",
            targetRepositoryDID: "did:plc:targetrepo",
            title: "Update Saturday schedule",
            uri: "at://did:plc:author123/sh.tangled.repo.pull/3pull"
        )
        let requests = Mutex([OpenMusicEventTangledPullReviewRequest]())
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.tangledPullReviewClient = TangledPullReviewClient { request in
                requests.withLock { $0.append(request) }
                return [review]
            }
        } operation: {
            TestStore(initialState: EventWorkspace.State(eventID: eventID)) {
                EventWorkspace()
            }
        }

        try await waitForCondition {
            store.state.reviews.reviewsStatus == .loaded([review])
        }

        #expect(
            requests.withLock { $0 } == [
                OpenMusicEventTangledPullReviewRequest(eventID: eventID)
            ]
        )
        await store.dismount()
    }

    @Test
    func closeTangledPullReviewButtonRemovesReviewAfterStatusWrite() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedTangledSourceBackedEvent(eventID, in: database)
        let review = testTangledPullReview()
        let closedReviews = Mutex([TangledPullReview]())
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in [review] },
                close: { review in
                    closedReviews.withLock { $0.append(review) }
                }
            )
        } operation: {
            var initialState = EventWorkspace.State(eventID: eventID)
            initialState.reviews.reviewsStatus = .loaded([review])
            initialState.reviews.semanticDiffs[review.id] = .failed(
                WorkspaceReviews.SemanticDiffFailure(TestCloseFailure.closeFailed)
            )
            return TestStore(initialState: initialState) {
                EventWorkspace()
            }
        }

        let task = store.send(.reviews(.closeButtonTapped(review)))
        await task?.value

        expectNoDifference(closedReviews.withLock { $0 }, [review])
        #expect(store.state.reviews.reviewsStatus == .loaded([]))
        #expect(store.state.reviews.locallyRemovedReviewIDs == [review.id])
        #expect(store.state.reviews.reviewOperations[review.id] == nil)
        await store.dismount()
    }

    @Test
    func mergeTangledPullReviewButtonRemovesReviewAfterMerge() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedTangledSourceBackedEvent(eventID, in: database)
        let review = testTangledPullReview()
        let workspaceID = EditingWorkspaceRecord.ID(rawValue: "team.merge-success")
        let mergedRequests = Mutex([OpenMusicEventTangledPullReviewMergeRequest]())
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.useAuthoringContext(
                workspaceID,
                grant: SharedReader(
                    value: AuthoringGrant(
                        principal: .local,
                        role: .owner,
                        workspaceID: workspaceID
                    )
                )
            )
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in [review] },
                merge: { request in
                    mergedRequests.withLock { $0.append(request) }
                }
            )
        } operation: {
            var initialState = EventWorkspace.State(eventID: eventID)
            initialState.reviews.reviewsStatus = .loaded([review])
            initialState.reviews.reviewOperations[review.id] = .failed(
                .approve,
                WorkspaceReviews.ReviewFailure(TestCloseFailure.mergeFailed)
            )
            initialState.reviews.semanticDiffs[review.id] = .failed(
                WorkspaceReviews.SemanticDiffFailure(TestCloseFailure.closeFailed)
            )
            return TestStore(initialState: initialState) {
                EventWorkspace()
            }
        }

        let task = store.send(.reviews(.approveButtonTapped(review)))
        await task?.value

        expectNoDifference(
            mergedRequests.withLock { $0 },
            [
                OpenMusicEventTangledPullReviewMergeRequest(
                    eventID: eventID,
                    review: review
                )
            ]
        )
        #expect(store.state.reviews.reviewsStatus == .loaded([]))
        #expect(store.state.reviews.reviewOperations[review.id] == nil)
        await store.dismount()
    }

    @Test
    func mountKeepsLocallyRemovedTangledPullReviewHidden() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let sourceProvenance = OME.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/woody.fm/wicked-woods",
            ref: "main"
        )
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Test Event",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: timeZone,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try SourceBaselineRecord.insert {
                SourceBaselineRecord(
                    source: sourceProvenance,
                    databaseFileName: "baseline.sqlite",
                    importedAt: Date(timeIntervalSince1970: 0)
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceBaselineID: sourceBaselineID,
                    sourceKind: sourceProvenance.kind,
                    sourceReference: sourceProvenance.reference,
                    ref: sourceProvenance.ref,
                    eventIDOrigin: .explicit,
                    sourceEventDirectory: "event-1"
                )
            }
            .execute(db)
        }
        let review = testTangledPullReview()
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.tangledPullReviewClient = TangledPullReviewClient { _ in
                [review]
            }
        } operation: {
            var initialState = EventWorkspace.State(eventID: eventID)
            initialState.reviews.locallyRemovedReviewIDs = [review.id]
            return TestStore(initialState: initialState) {
                EventWorkspace()
            }
        }

        try await waitForCondition {
            store.state.reviews.reviewsStatus == .loaded([])
        }

        await store.dismount()
    }

    @Test
    func deleteTangledPullReviewForeverButtonRemovesReviewBeforeRecordDelete() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedTangledSourceBackedEvent(eventID, in: database)
        let review = testTangledPullReview()
        let deletedReviews = Mutex([TangledPullReview]())
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in [review] },
                delete: { review in
                    deletedReviews.withLock { $0.append(review) }
                }
            )
        } operation: {
            var initialState = EventWorkspace.State(eventID: eventID)
            initialState.reviews.reviewsStatus = .loaded([review])
            initialState.reviews.reviewOperations[review.id] = .failed(
                .close,
                WorkspaceReviews.ReviewFailure(TestCloseFailure.closeFailed)
            )
            initialState.reviews.semanticDiffs[review.id] = .failed(
                WorkspaceReviews.SemanticDiffFailure(TestCloseFailure.closeFailed)
            )
            return TestStore(initialState: initialState) {
                EventWorkspace()
            }
        }

        let task = store.send(.reviews(.deleteButtonTapped(review)))
        await task?.value
        try await waitForCondition {
            store.state.reviews.reviewsStatus == .loaded([])
        }

        expectNoDifference(deletedReviews.withLock { $0 }, [review])
        #expect(store.state.reviews.reviewOperations[review.id] == nil)
        #expect(store.state.reviews.pendingDeletedReviews[review.id] == nil)
        await store.dismount()
    }

    @Test
    func deleteTangledPullReviewForeverButtonRestoresReviewAndShowsFailure() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedTangledSourceBackedEvent(eventID, in: database)
        let review = testTangledPullReview()
        var earlierReview = testTangledPullReview()
        earlierReview.title = "Earlier update"
        earlierReview.uri = "at://did:plc:author123/sh.tangled.repo.pull/2pull"
        let reviews = [earlierReview, review]
        let failure = WorkspaceReviews.ReviewFailure(
            TestCloseFailure.deleteFailed
        )
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in reviews },
                delete: { _ in
                    throw TestCloseFailure.deleteFailed
                }
            )
        } operation: {
            var initialState = EventWorkspace.State(eventID: eventID)
            initialState.reviews.reviewsStatus = .loaded(reviews)
            return TestStore(initialState: initialState) {
                EventWorkspace()
            }
        }

        await withIssueReporters([]) {
            let task = store.send(.reviews(.deleteButtonTapped(review)))
            await task?.value
        }

        #expect(store.state.reviews.reviewsStatus == .loaded([earlierReview, review]))
        #expect(store.state.reviews.reviewOperations[review.id] == .failed(.delete, failure))

        await store.dismount()
    }

    @Test
    func closeTangledPullReviewButtonKeepsReviewAndShowsFailure() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let review = testTangledPullReview()
        let failure = WorkspaceReviews.ReviewFailure(
            TestCloseFailure.closeFailed
        )
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in [] },
                close: { _ in
                    throw TestCloseFailure.closeFailed
                }
            )
        } operation: {
            var initialState = EventWorkspace.State(eventID: eventID)
            initialState.reviews.reviewsStatus = .loaded([review])
            return TestStore(initialState: initialState) {
                EventWorkspace()
            }
        }

        await withIssueReporters([]) {
            let task = store.send(.reviews(.closeButtonTapped(review)))
            await task?.value
        }
        #expect(store.state.reviews.reviewOperations[review.id] == .failed(.close, failure))

        await store.dismount()
    }

    @Test
    func mergeTangledPullReviewButtonKeepsReviewAndShowsFailure() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let review = testTangledPullReview()
        let workspaceID = EditingWorkspaceRecord.ID(rawValue: "team.merge-failure")
        let failure = WorkspaceReviews.ReviewFailure(
            TestCloseFailure.mergeFailed
        )
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.useAuthoringContext(
                workspaceID,
                grant: SharedReader(
                    value: AuthoringGrant(
                        principal: .local,
                        role: .owner,
                        workspaceID: workspaceID
                    )
                )
            )
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in [] },
                merge: { _ in
                    throw TestCloseFailure.mergeFailed
                }
            )
        } operation: {
            var initialState = EventWorkspace.State(eventID: eventID)
            initialState.reviews.reviewsStatus = .loaded([review])
            return TestStore(initialState: initialState) {
                EventWorkspace()
            }
        }

        await withIssueReporters([]) {
            let task = store.send(.reviews(.approveButtonTapped(review)))
            await task?.value
        }
        #expect(store.state.reviews.reviewOperations[review.id] == .failed(.approve, failure))

        await store.dismount()
    }

    @Test
    func tangledPullReviewMergeFailureIncludesHTTPResponseBody() throws {
        let body = Data(
            """
            {
              "error": "Auth",
              "message": "signature verification failed"
            }
            """.utf8
        )
        let failure = WorkspaceReviews.ReviewFailure(
            HTTPError.httpError(403, body, HTTPFields())
        )

        #expect(failure.message == "HTTP 403: Auth: signature verification failed")
    }

    @Test
    func mergeTangledPullReviewButtonReportsFailureThroughRootErrorHandling() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let review = testTangledPullReview()
        let workspaceID = EditingWorkspaceRecord.ID(rawValue: "team.root-merge-failure")
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.useAuthoringContext(
                workspaceID,
                grant: SharedReader(
                    value: AuthoringGrant(
                        principal: .local,
                        role: .owner,
                        workspaceID: workspaceID
                    )
                )
            )
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in [] },
                merge: { _ in
                    throw TestCloseFailure.mergeFailed
                }
            )
        } operation: {
            var workspace = EventWorkspace.State(eventID: eventID)
            workspace.reviews.reviewsStatus = .loaded([review])
            return Store(
                initialState: EventWorkspaceErrorReportingHost.State(workspace: workspace)
            ) {
                EventWorkspaceErrorReportingHost()
            }
        }

        await withIssueReporters([]) {
            let task = store.send(.workspace(.reviews(.approveButtonTapped(review))))
            await task?.value
        }

        expectNoDifference(
            store.errorNotifications.state.latestError?.message.fallback,
            "Unable to merge Tangled pull review."
        )
        expectNoDifference(
            store.errorNotifications.state.latestError?.operation.rawValue,
            "tangled.pull-review.merge"
        )
        expectNoDifference(
            store.workspace.reviews.reviewOperations[review.id]?.failure?.message,
            String(describing: TestCloseFailure.mergeFailed)
        )
    }

    @Test
    func mergeTangledPullReviewButtonReportsHTTPFailureBodyThroughRootErrorHandling() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let review = testTangledPullReview()
        let workspaceID = EditingWorkspaceRecord.ID(rawValue: "team.root-http-merge-failure")
        let body = Data(
            """
            {
              "error": "Auth",
              "message": "signature verification failed"
            }
            """.utf8
        )
        let error = HTTPError.httpError(403, body, HTTPFields())
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.useAuthoringContext(
                workspaceID,
                grant: SharedReader(
                    value: AuthoringGrant(
                        principal: .local,
                        role: .owner,
                        workspaceID: workspaceID
                    )
                )
            )
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in [] },
                merge: { _ in throw error }
            )
        } operation: {
            var workspace = EventWorkspace.State(eventID: eventID)
            workspace.reviews.reviewsStatus = .loaded([review])
            return Store(
                initialState: EventWorkspaceErrorReportingHost.State(workspace: workspace)
            ) {
                EventWorkspaceErrorReportingHost()
            }
        }

        await withIssueReporters([]) {
            let task = store.send(.workspace(.reviews(.approveButtonTapped(review))))
            await task?.value
        }

        expectNoDifference(
            store.errorNotifications.state.latestError?.debugDescription,
            "HTTP 403: Auth: signature verification failed"
        )
        expectNoDifference(
            store.workspace.reviews.reviewOperations[review.id]?.failure?.message,
            "HTTP 403: Auth: signature verification failed"
        )
    }

    @Test
    func reviewSemanticDiffLoadsFromReviewBranchSnapshot() async throws {
        let database = try makePreparedDatabase()
        let baselineDatabase = try defaultBaselineDatabase()
        let eventID = testEventID("event-1")
        let sourceProvenance = OME.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/woody.fm/wicked-woods-ome",
            ref: "main"
        )
        let baselineSource = try makeReviewSourceRepository(
            eventID: eventID,
            eventName: "Wicked Woods 2025"
        )
        let reviewSource = try makeReviewSourceRepository(
            eventID: eventID,
            eventName: "Wicked Woods 2026"
        )
        try await withDependencies {
            $0.context = .test
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.sourceReferenceDatabaseMigrator = .openMusicEvent
        } operation: {
            let insertion = try OME.SourceDatabaseInsertion(
                OME.SourceDatabaseInsertion.Configuration(
                    source: baselineSource,
                    organizerID: eventID.organizerID,
                    sourceProvenance: sourceProvenance
                )
            )
            try await insertion.migrateAndInsert(into: database)
        }
        let review = TangledPullReview(
            author: "did:plc:author123",
            body: "Hydrate the 2026 event.",
            commentCount: 0,
            createdAt: "2026-07-03T12:01:00Z",
            patchBlobs: [],
            sourceBranch: "ome/proposal-2026",
            state: "open",
            targetBranch: "main",
            targetRepositoryDID: "did:plc:targetrepo",
            title: "Hydrate 2026",
            uri: "at://did:plc:author123/sh.tangled.repo.pull/3pull"
        )
        let snapshotRequests = Mutex([TangledPullReviewSourceSnapshotRequest]())
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.sourceReferenceDatabaseMigrator = .openMusicEvent
            $0.tangledPullReviewSourceSnapshot = TangledPullReviewSourceSnapshotClient { request in
                snapshotRequests.withLock { $0.append(request) }
                return try OME.SourceDatabaseInsertion(
                    OME.SourceDatabaseInsertion.Configuration(
                        source: request.ref == review.targetBranch
                            ? baselineSource
                            : reviewSource,
                        organizerID: request.organizerID,
                        sourceProvenance: request.sourceProvenance
                    )
                )
            }
        } operation: {
            TestStore(initialState: EventWorkspace.State(eventID: eventID)) {
                EventWorkspace()
            }
        }

        let task = store.send(.reviews(.showChangesButtonTapped(review)))
        await task?.value

        #expect(
            snapshotRequests.withLock { $0 } == [
                TangledPullReviewSourceSnapshotRequest(
                    organizerID: eventID.organizerID,
                    ref: review.targetBranch,
                    sourceProvenance: sourceProvenance
                ),
                TangledPullReviewSourceSnapshotRequest(
                    organizerID: eventID.organizerID,
                    ref: try #require(review.sourceBranch),
                    sourceProvenance: sourceProvenance
                )
            ]
        )
        guard case let .loaded(loadedDiff) = store.state.reviews.semanticDiffs[review.id] else {
            Issue.record("Expected a loaded semantic diff.")
            return
        }
        let eventGroup = try #require(
            loadedDiff.groups.first { $0.id == "events" }
        )
        let eventChange = try #require(eventGroup.records.first)
        let nameChange = try #require(
            eventChange.fieldChanges.first { $0.columnName == "name" }
        )
        #expect(nameChange.baselineValue == "Wicked Woods 2025".databaseValue)
        #expect(nameChange.workingValue == "Wicked Woods 2026".databaseValue)
        #expect(loadedDiff.recordComparisons[eventChange]?.as(OME.Event.self) != nil)
        expectNoDifference(
            loadedDiff.sourceFileAttributions,
            [
                SourceFileAttribution(
                    filePath: "events/event-1/event.yml",
                    recordChangeIDs: [eventChange.id]
                )
            ]
        )

        await store.dismount()
    }

    @Test
    func simultaneousReviewDiffsOwnIndependentScratchDatabases() async throws {
        let eventID = testEventID("event-1")
        let target = OpenMusicEventSourceTarget.event(eventID)
        let sourceProvenance = OME.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/woody.fm/wicked-woods-ome",
            ref: "main"
        )
        let baselineSource = try makeReviewSourceRepository(
            eventID: eventID,
            eventName: "Wicked Woods 2025"
        )
        let reviewSource = try makeReviewSourceRepository(
            eventID: eventID,
            eventName: "Wicked Woods 2026"
        )
        let review = testTangledPullReview()
        let firstSnapshotGate = SimultaneousSnapshotGate()
        let sourceSnapshot = TangledPullReviewSourceSnapshotClient { request in
            await firstSnapshotGate.arrive()
            return try OME.SourceDatabaseInsertion(
                OME.SourceDatabaseInsertion.Configuration(
                    source: request.ref == review.targetBranch
                        ? baselineSource
                        : reviewSource,
                    organizerID: request.organizerID,
                    sourceProvenance: request.sourceProvenance
                )
            )
        }
        let repeatedUUID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )

        let (first, second) = try await withDependencies {
            // Deterministic domain UUIDs must not become shared temporary-resource identity.
            $0.uuid = .constant(repeatedUUID)
        } operation: {
            async let first = WorkspaceReviews.SemanticDiff.reviewBranchDiff(
                target: target,
                review: review,
                sourceProvenance: sourceProvenance,
                sourceSnapshot: sourceSnapshot
            )
            async let second = WorkspaceReviews.SemanticDiff.reviewBranchDiff(
                target: target,
                review: review,
                sourceProvenance: sourceProvenance,
                sourceSnapshot: sourceSnapshot
            )
            return try await (first, second)
        }

        expectNoDifference([first.totalCount, second.totalCount], [1, 1])
    }

    private func makePreparedDatabase(
        at databaseURL: URL? = nil
    ) throws -> any DatabaseWriter {
        if let databaseURL {
            let database = try DatabasePool(path: databaseURL.path)
            var migrator = DatabaseMigrator()
            OMERecord.DatabaseMigrations.register(into: &migrator)
            BlueskyActorCacheMigrations.register(into: &migrator)
            OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
            try migrator.migrate(database)
            return database
        }

        return try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            @Dependency(\.defaultDatabase) var database
            return database
        }
    }

    private func makeAuthoringDatabase(
        for eventID: OME.Event.ID,
        mainDatabase: any DatabaseWriter,
        baselineDatabase: SourceBaselineDatabase
    ) throws -> any DatabaseWriter {
        try SourceWorkspaceDatabase(
            workspaceID: EditingWorkspaceRecord.ID(
                sourceBaselineID: sourceBaselineID(for: eventID)
            ),
            mainDatabase: mainDatabase,
            referenceDatabase: baselineDatabase
        )
        .database
    }

    private func waitForCondition(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    private func seedTangledSourceBackedEvent(
        _ eventID: OME.Event.ID,
        in database: any DatabaseWriter
    ) async throws {
        let sourceProvenance = OME.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/woody.fm/wicked-woods",
            ref: "main"
        )
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Test Event",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: timeZone,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try SourceBaselineRecord.insert {
                SourceBaselineRecord(
                    source: sourceProvenance,
                    databaseFileName: "baseline.sqlite",
                    importedAt: Date(timeIntervalSince1970: 0)
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceBaselineID: sourceBaselineID,
                    sourceKind: sourceProvenance.kind,
                    sourceReference: sourceProvenance.reference,
                    ref: sourceProvenance.ref,
                    eventIDOrigin: .explicit,
                    sourceEventDirectory: "event-1"
                )
            }
            .execute(db)
        }
    }

    private func seedSourceBackedEvent(
        _ eventID: OME.Event.ID,
        sourceKind: OME.SourceDatabaseInsertion.SourceKind = .local,
        in database: any DatabaseWriter
    ) async throws {
        let sourceBaselineID = sourceBaselineID(for: eventID)
        let sourceReference = switch sourceKind {
        case .local:
            "/tmp/source-repository"
        case .tangled:
            "tangled.org/woody.fm/source-repository"
        }
        let ref = sourceKind == .tangled ? "main" : nil
        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Source Event",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone(identifier: "UTC")!,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try SourceBaselineRecord.insert {
                SourceBaselineRecord(
                    id: sourceBaselineID,
                    sourceKind: sourceKind,
                    sourceReference: sourceReference,
                    ref: ref,
                    databaseFileName: "reference.sqlite",
                    importedAt: Date(timeIntervalSince1970: 0)
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceBaselineID: sourceBaselineID,
                    sourceKind: sourceKind,
                    sourceReference: sourceReference,
                    ref: ref,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: eventID.eventID.rawValue.rawValue
                )
            }
            .execute(db)
        }
    }

    private func seedAdditionalSourceBackedEvent(
        _ eventID: OME.Event.ID,
        sourceBaselineID: SourceBaselineRecord.ID,
        in database: any DatabaseWriter
    ) async throws {
        try await database.write { db in
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Source Event",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone(identifier: "UTC")!,
                    images: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceBaselineID: sourceBaselineID,
                    sourceKind: .local,
                    sourceReference: "/tmp/source-repository",
                    ref: nil,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: eventID.eventID.rawValue.rawValue
                )
            }
            .execute(db)
        }
    }

    private func seedEditingWorkspace(
        for eventID: OME.Event.ID,
        in database: any DatabaseWriter
    ) async throws {
        let sourceBaselineID = sourceBaselineID(for: eventID)
        try await database.write { db in
            let sourceBaseline = try #require(
                try SourceBaselineRecord
                    .where { $0.id.eq(sourceBaselineID) }
                    .fetchOne(db)
            )
            let workspace = EditingWorkspaceRecord(teamSourceBaseline: sourceBaseline)
            try EditingWorkspaceRecord.insert {
                workspace
            }
            .execute(db)
            try EventEditingWorkspaceRecord.insert {
                EventEditingWorkspaceRecord(
                    id: eventID,
                    workspaceID: workspace.id
                )
            }
            .execute(db)
        }
    }

    private func sourceBaselineID(
        for eventID: OME.Event.ID
    ) -> SourceBaselineRecord.ID {
        SourceBaselineRecord.ID(
            rawValue: "source.\(eventID.eventID.rawValue.rawValue)"
        )
    }

    private func temporaryDirectoryURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeReviewSourceRepository(
        eventID: OME.Event.ID,
        eventName: String
    ) throws -> OpenMusicEventSourceRepository {
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        return OpenMusicEventSourceRepository(
            events: [
                DirectoryContent(
                    directoryName: eventID.eventID.rawValue.rawValue,
                    components: OpenMusicEventSourceEvent(
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
                            timeZone: timeZone,
                            images: nil,
                            contactNumbers: nil,
                            categoryConfigs: nil
                        )
                    )
                )
            ]
        )
    }
}

private func testEventID(_ string: String) -> OME.Event.ID {
    OME.Event.ID(
        organizerID: OME.Organizer.ID("did:web:example.com")!,
        eventID: OME.ID<OME.Event>(.init(string))
    )
}

private func testTangledPullReview() -> TangledPullReview {
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
        state: "open",
        targetBranch: "main",
        targetRepositoryDID: "did:plc:targetrepo",
        title: "Update Saturday schedule",
        uri: "at://did:plc:author123/sh.tangled.repo.pull/3pull"
    )
}

@Feature
private struct EventWorkspaceErrorReportingHost {
    struct State {
        var errorNotifications = Spawn(ErrorNotifications.State())
        var workspace: EventWorkspace.State
    }

    enum Action {
        case workspace(EventWorkspace.Action)
    }

    var body: some Feature {
        Scope(\.workspace, action: \.workspace) {
            EventWorkspace()
        }
        .spawn(\.errorNotifications) {
            ErrorNotifications()
        }
        .onEvent(ErrorReported.self) { error, state in
            state.errorNotifications.state.report(error)
        }
    }
}

private actor SourcePatchGenerationGate {
    private var isOpen = false
    private var hasStarted = false
    private var openWaiters: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func pauseUntilOpened() async {
        hasStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        guard !isOpen else { return }
        await withCheckedContinuation { openWaiters.append($0) }
    }

    func waitForStart() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func open() {
        isOpen = true
        openWaiters.forEach { $0.resume() }
        openWaiters.removeAll()
    }
}

private actor SimultaneousSnapshotGate {
    private var arrivalCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func arrive() async {
        arrivalCount += 1
        guard arrivalCount < 2 else {
            waiters.forEach { $0.resume() }
            waiters.removeAll()
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private enum ResetEditsTestError: Equatable, Error {
    case failed
    case previousFailure
}

private enum TestCloseFailure: Equatable, Error {
    case closeFailed
    case deleteFailed
    case mergeFailed
}

private extension SourceReferenceDatabaseClient {
    static func test(database: SourceBaselineDatabase) -> Self {
        Self(
            url: { _ in URL(fileURLWithPath: database.path) },
            prepareForImport: { _ in
                StagedSourceReferenceDatabase(
                    database: database,
                    databaseFileName: URL(fileURLWithPath: database.path).lastPathComponent,
                    commit: {},
                    discard: {}
                )
            },
            existing: { _ in database }
        )
    }
}

private extension WorkspaceReferenceDatabaseClient {
    static func test(database: SourceBaselineDatabase) -> Self {
        Self(
            url: { _, _ in URL(fileURLWithPath: database.path) },
            prepare: { _, _ in database },
            existing: { _, _ in database }
        )
    }

    static let missing = Self(
        url: { _, _ in URL(fileURLWithPath: "/missing/reference.sqlite") },
        prepare: { workspace, _ in
            throw WorkspaceReferenceDatabaseError.sourceBaselineMissing(workspace.id)
        },
        existing: { _, _ in nil }
    )
}

@MainActor
private func fulfillAuthorizationRequest(
    from authorizationCenter: AuthorizationRequestCenter,
    requirement: OAuth.AuthRequirement,
    beforeSucceed: () -> Void = {},
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let requests = await authorizationCenter.requests()
    for await request in requests {
        guard let request else { continue }
        #expect(request.requirement == requirement, sourceLocation: sourceLocation)
        beforeSucceed()
        await authorizationCenter.succeed()
        break
    }
}
