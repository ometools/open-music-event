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
    func observedSourceSummaryTracksOnlyRelevantMainDatabaseWrites() async throws {
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
        try await workspaceDatabase.database.write { db in
            try db.execute(
                sql: "CREATE TABLE observation_noise (id INTEGER PRIMARY KEY)"
            )
        }

        let fetchCount = Mutex(0)
        let summaries = Mutex<[SourceWorkspaceSummary]>([])
        let failures = Mutex<[String]>([])
        let observation = ValueObservation
            .tracking { db in
                try SourceWorkspaceSummary.Query(target: .event(eventID)).fetch(db)
            }
            .handleEvents(
                willFetch: {
                    fetchCount.withLock { $0 += 1 }
                }
            )
        let cancellable = observation.start(
            in: workspaceDatabase.database,
            scheduling: .immediate,
            onError: { error in
                failures.withLock { $0.append(String(reflecting: error)) }
            },
            onChange: { summary in
                summaries.withLock { $0.append(summary) }
            }
        )
        defer { cancellable.cancel() }

        let initialFetchCount = fetchCount.withLock { $0 }
        #expect(initialFetchCount > 0)
        #expect(summaries.withLock { $0.last?.totalCount } == 0)
        #expect(failures.withLock { $0 }.isEmpty)

        try await workspaceDatabase.database.write { db in
            try db.execute(sql: "INSERT INTO observation_noise DEFAULT VALUES")
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(fetchCount.withLock { $0 } == initialFetchCount)

        try await workspaceDatabase.database.write { db in
            try OME.Event
                .find(eventID)
                .update { $0.name = "Observed Source Event" }
                .execute(db)
        }
        try await waitForCondition {
            summaries.withLock { $0.last?.totalCount == 1 }
        }
        #expect(fetchCount.withLock { $0 } == initialFetchCount + 1)
        #expect(failures.withLock { $0 }.isEmpty)
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
        #expect(store.state.changes.sourceProposal == nil)
        await store.dismount()
    }

    @Test
    func proposeChangeReviewsChangesWhenPatchIsNotReady() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let database = try makePreparedDatabase(
            at: directoryURL.appending(path: "app.sqlite")
        )
        let eventID = testEventID("event-1")
        let expectedSourceBaselineID = sourceBaselineID(for: eventID)
        try await seedSourceBackedEvent(eventID, sourceKind: .tangled, in: database)
        try await seedEditingWorkspace(for: eventID, in: database)
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
        let expectedWorkspaceSummary = try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.workspaceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try SourceWorkspaceSummary.query(target: .event(eventID), using: database)
        }
        #expect(expectedWorkspaceSummary.availability == .available)
        #expect(expectedWorkspaceSummary.totalCount == 1)
        let eventRecord = try #require(
            expectedWorkspaceSummary.groups
                .first { $0.id == OME.Event.tableName }?
                .records
                .first
        )
        let expectedSourceFileAttributions = [
            SourceFileAttribution(
                filePath: "events/event-1/event.yml",
                recordChangeIDs: [eventRecord.id]
            )
        ]
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
        let workspaceID = EditingWorkspaceRecord.ID(sourceBaselineID: expectedSourceBaselineID)
        let authoringDatabase = try makeAuthoringDatabase(
            for: eventID,
            mainDatabase: database,
            baselineDatabase: baselineDatabase
        )
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.context = .test
            $0.defaultDatabase = authoringDatabase
            $0.useAuthoringContext(
                workspaceID,
                grant: SharedReader(
                    value: AuthoringGrant(
                        principal: .local,
                        role: .collaborator([.propose]),
                        workspaceID: workspaceID
                    )
                )
            )
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.workspaceReferenceDatabase = .test(database: baselineDatabase)
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

        let task = store.send(.changes(.proposeChangesButtonTapped))
        await task?.value

        #expect(store.state.changes.sourceProposal?.eventID == eventID)
        #expect(store.state.changes.sourceProposal?.patch == patch)
        expectNoDifference(
            store.state.changes.sourceProposal?.sourceFileAttributions,
            expectedSourceFileAttributions
        )
        expectNoDifference(
            store.state.changes.sourceProposal?.sourceChangeGroups,
            expectedWorkspaceSummary.groups
        )
        await store.dismount()
    }

    @Test
    func proposeChangeButtonRegeneratesPatchAndPreparesInlineProposalFromCurrentDiff() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let expectedSourceBaselineID = sourceBaselineID(for: eventID)
        try await seedSourceBackedEvent(eventID, sourceKind: .tangled, in: database)
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
        let expectedWorkspaceSummary = try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.workspaceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try SourceWorkspaceSummary.query(target: .event(eventID), using: database)
        }
        #expect(expectedWorkspaceSummary.availability == .available)
        #expect(expectedWorkspaceSummary.totalCount == 1)
        let eventRecord = try #require(
            expectedWorkspaceSummary.groups
                .first { $0.id == OME.Event.tableName }?
                .records
                .first
        )
        let expectedSourceFileAttributions = [
            SourceFileAttribution(
                filePath: "events/event-1/event.yml",
                recordChangeIDs: [eventRecord.id]
            )
        ]
        let stalePatch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let currentPatch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Source Event\n".utf8),
                    newContents: Data("name: Updated Source Event\n".utf8)
                )
            ]
        )
        let workspaceID = EditingWorkspaceRecord.ID(sourceBaselineID: expectedSourceBaselineID)
        let authoringDatabase = try makeAuthoringDatabase(
            for: eventID,
            mainDatabase: database,
            baselineDatabase: baselineDatabase
        )
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.context = .test
            $0.defaultDatabase = authoringDatabase
            $0.useAuthoringContext(
                workspaceID,
                grant: SharedReader(
                    value: AuthoringGrant(
                        principal: .local,
                        role: .collaborator([.propose]),
                        workspaceID: workspaceID
                    )
                )
            )
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.workspaceReferenceDatabase = .test(database: baselineDatabase)
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
                return currentPatch
            }
        } operation: {
            var state = EventWorkspace.State(eventID: eventID)
            state.changes.sourcePatchStatus = .generated(
                WorkspaceChanges.SourceProposalPreparation(
                    patch: stalePatch,
                    sourceWorkspaceSummary: expectedWorkspaceSummary
                )
            )
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        let task = store.send(.changes(.proposeChangesButtonTapped))
        await task?.value
        #expect(store.state.changes.sourceProposal?.eventID == eventID)
        #expect(store.state.changes.sourceProposal?.patch == currentPatch)
        expectNoDifference(
            store.state.changes.sourceProposal?.sourceFileAttributions,
            expectedSourceFileAttributions
        )
        expectNoDifference(
            store.state.changes.sourceProposal?.sourceChangeGroups,
            expectedWorkspaceSummary.groups
        )

        await store.dismount()
    }

    @Test
    func proposeChangeButtonAttributesStagePatchFileToCurrentStageDiff() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let expectedSourceBaselineID = sourceBaselineID(for: eventID)
        let stageID = OME.Stage.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            stageID: OME.ID<OME.Stage>(.init("meadow"))
        )
        try await seedSourceBackedEvent(eventID, sourceKind: .tangled, in: database)
        try await seedEditingWorkspace(for: eventID, in: database)
        try await database.write { db in
            try OME.Stage.insert {
                OME.Stage.Draft(
                    id: stageID,
                    name: "Meadow",
                    color: 0x00bbcc,
                    sortIndex: 1
                )
            }
            .execute(db)
        }
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let baselineDatabase = try defaultBaselineDatabase(
            path: directoryURL.appending(path: "baseline.sqlite").path()
        )
        try database.backup(to: baselineDatabase.database)
        try await database.write { db in
            try OME.Stage
                .find(stageID)
                .update { $0.name = "Main Meadow" }
                .execute(db)
        }
        let expectedWorkspaceSummary = try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.workspaceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try SourceWorkspaceSummary.query(target: .event(eventID), using: database)
        }
        let stageRecord = try #require(
            expectedWorkspaceSummary.groups
                .first { $0.id == OME.Stage.tableName }?
                .records
                .first
        )
        let expectedSourceFileAttributions = [
            SourceFileAttribution(
                filePath: "events/event-1/stages/meadow.yml",
                recordChangeIDs: [stageRecord.id]
            )
        ]
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/stages/meadow.yml",
                    kind: .modified,
                    oldContents: Data("name: Meadow\n".utf8),
                    newContents: Data("name: Main Meadow\n".utf8)
                )
            ]
        )
        let workspaceID = EditingWorkspaceRecord.ID(sourceBaselineID: expectedSourceBaselineID)
        let authoringDatabase = try makeAuthoringDatabase(
            for: eventID,
            mainDatabase: database,
            baselineDatabase: baselineDatabase
        )
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.context = .test
            $0.defaultDatabase = authoringDatabase
            $0.useAuthoringContext(
                workspaceID,
                grant: SharedReader(
                    value: AuthoringGrant(
                        principal: .local,
                        role: .collaborator([.propose]),
                        workspaceID: workspaceID
                    )
                )
            )
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.workspaceReferenceDatabase = .test(database: baselineDatabase)
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

        let task = store.send(.changes(.proposeChangesButtonTapped))
        await task?.value

        expectNoDifference(
            store.state.changes.sourceProposal?.sourceFileAttributions,
            expectedSourceFileAttributions
        )

        await store.dismount()
    }

    @Test
    func sourceFileAttributionsCollectMultipleCurrentDiffRecordsForSameFile() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let scheduleID = OME.Schedule.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            scheduleID: OME.Schedule.singletonID
        )
        let scheduleDate = try #require(LocalDate("2026-08-01"))
        try await seedSourceBackedEvent(eventID, in: database)
        try await seedEditingWorkspace(for: eventID, in: database)
        try await database.write { db in
            try OME.Schedule.insert {
                OME.Schedule.Draft(
                    id: scheduleID,
                    date: scheduleDate,
                    startsAt: nil,
                    endsAt: nil,
                    customTitle: "Original Schedule"
                )
            }
            .execute(db)
        }
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
            try OME.Schedule
                .find(scheduleID)
                .update { $0.customTitle = #bind("Updated Schedule") }
                .execute(db)
        }
        let workspaceSummary = try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.workspaceReferenceDatabase = .test(database: baselineDatabase)
        } operation: {
            try SourceWorkspaceSummary.query(target: .event(eventID), using: database)
        }
        let eventRecord = try #require(
            workspaceSummary.groups
                .first { $0.id == OME.Event.tableName }?
                .records
                .first
        )
        let scheduleRecord = try #require(
            workspaceSummary.groups
                .first { $0.id == OME.Schedule.tableName }?
                .records
                .first
        )
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Source Event\n".utf8),
                    newContents: Data("name: Updated Source Event\n".utf8)
                )
            ]
        )

        let attributions = try await database.read { db in
            try openMusicEventSourceFileAttributions(
                patch: patch,
                groups: workspaceSummary.groups,
                recordComparisons: workspaceSummary.recordComparisons,
                in: db
            )
        }

        expectNoDifference(
            attributions,
            [
                SourceFileAttribution(
                    filePath: "events/event-1/event.yml",
                    recordChangeIDs: [
                        eventRecord.id,
                        scheduleRecord.id,
                    ].sorted()
                )
            ]
        )
    }

    @Test
    func localProposalAndReviewSemanticDiffUseSameTypedSourceDiff() async throws {
        let database = try makePreparedDatabase()
        let baselineDatabase = try defaultBaselineDatabase()
        let eventID = testEventID("event-1")
        let sourceProvenance = OME.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/woody.fm/wicked-woods-ome",
            ref: "main"
        )
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
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
        try await database.write { db in
            try OME.Event
                .find(eventID)
                .update { $0.name = "Wicked Woods 2026" }
                .execute(db)
        }
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Wicked Woods 2025\n".utf8),
                    newContents: Data("name: Wicked Woods 2026\n".utf8)
                )
            ]
        )
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
        let workspaceID = EditingWorkspaceRecord.ID(sourceBaselineID: sourceBaselineID)
        let authoringDatabase = try makeAuthoringDatabase(
            for: eventID,
            mainDatabase: database,
            baselineDatabase: baselineDatabase
        )
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.context = .test
            $0.defaultDatabase = authoringDatabase
            $0.useAuthoringContext(
                workspaceID,
                grant: SharedReader(
                    value: AuthoringGrant(
                        principal: .local,
                        role: .collaborator([.propose]),
                        workspaceID: workspaceID
                    )
                )
            )
            $0.workspaceReferenceDatabase = .test(database: baselineDatabase)
            $0.sourceReferenceDatabase = .test(database: baselineDatabase)
            $0.sourceReferenceDatabaseMigrator = .openMusicEvent
            $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] = SourcePatchGenerator { request in
                #expect(
                    request == OpenMusicEventCalendarSourcePatchRequest(
                        calendarID: OME.Calendar.ID(
                            ownerID: eventID.organizerID,
                            calendarID: OME.Calendar.defaultID
                        ),
                        sourceBaselineID: sourceBaselineID
                    )
                )
                return patch
            }
            $0.tangledPullReviewSourceSnapshot = TangledPullReviewSourceSnapshotClient { request in
                #expect(
                    request == TangledPullReviewSourceSnapshotRequest(
                        organizerID: eventID.organizerID,
                        review: review,
                        sourceProvenance: sourceProvenance
                    )
                )
                return try OME.SourceDatabaseInsertion(
                    OME.SourceDatabaseInsertion.Configuration(
                        source: reviewSource,
                        organizerID: request.organizerID,
                        sourceProvenance: request.sourceProvenance
                    )
                )
            }
            $0.uuid = .incrementing
        } operation: {
            TestStore(initialState: EventWorkspace.State(eventID: eventID)) {
                EventWorkspace()
            }
        }

        let prepareProposalTask = store.send(.changes(.proposeChangesButtonTapped))
        await prepareProposalTask?.value
        guard case let .generated(localPreparation) = store.state.changes.sourcePatchStatus else {
            Issue.record("Expected local source proposal preparation.")
            return
        }
        let reviewDiffTask = store.send(.reviews(.showChangesButtonTapped(review)))
        await reviewDiffTask?.value
        guard case let .loaded(reviewDiff) = store.state.reviews.semanticDiffs[review.id] else {
            Issue.record("Expected review semantic diff.")
            return
        }
        expectNoDifference(
            reviewDiff.groups,
            localPreparation.sourceWorkspaceSummary.groups
        )
        expectNoDifference(
            reviewDiff.recordComparisons,
            localPreparation.sourceWorkspaceSummary.recordComparisons
        )
        expectNoDifference(
            reviewDiff.sourceFileAttributions,
            localPreparation.sourceFileAttributions
        )

        await store.dismount()
    }

    @Test
    func sourceProposalFormTitleAndDescriptionCanBeEdited() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
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
            $0.continuousClock = ImmediateClock()
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: SourceProposalFlow.State(
                    eventID: eventID,
                    patch: patch
                )
            ) {
                SourceProposalFlow()
            }
        }

        store.modify {
            $0.form.value.title = "Update the event name"
            $0.form.value.description = "Updated the event name."
        } changes: {
            $0.form.value.title = "Update the event name"
            $0.form.value.description = "Updated the event name."
        }

        await store.dismount()
    }

    @Test
    func createProposalRequiresTitleFormValidation() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
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
        let publishRequests = Mutex([SourcePatchPublishRequest]())
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourcePatchPublisher = SourcePatchPublisher { request in
                publishRequests.withLock { $0.append(request) }
                return SourcePatchPublication()
            }
        } operation: {
            TestStore(
                initialState: SourceProposalFlow.State(
                    eventID: eventID,
                    patch: patch
                )
            ) {
                SourceProposalFlow()
            }
        }

        await store.send(.createProposalButtonTapped)?.value

        expectNoDifference(store.state.status, .composing)
        expectNoDifference(publishRequests.withLock { $0 }, [])
        expectNoDifference(
            store.state.form.validation[AnyHashable(\SourceProposalFlow.FormValue.title)]?
                .errors.map(\.message),
            ["Enter a title."]
        )

        await store.dismount()
    }

    @Test
    func createProposalPublishesGeneratedPatchWithResolvedSourceLocation() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let repositoryURL = URL(fileURLWithPath: "/tmp/source-repository")
        let location = SourcePatchLocation(
            repositoryURL: repositoryURL,
            relativePath: "events/event-1"
        )
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
        let sourceChangeURL = try #require(URL(string: "https://source.woody.fm/events/event-1/proposals/1"))
        let publication = SourcePatchPublication(sourceChangeURL: sourceChangeURL)
        let workspaceID = EditingWorkspaceRecord.ID(rawValue: "proposal-workspace")
        let operations = Mutex<[String]>([])

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.useAuthoringContext(workspaceID, grant: SharedReader(value: nil))
            $0[WorkspacePreparationClient.self] = WorkspacePreparationClient(
                prepareSource: { requestedWorkspaceID in
                    #expect(requestedWorkspaceID == workspaceID)
                    operations.withLock { $0.append("prepare") }
                }
            )
            $0.openMusicEventSourcePatchLocationResolver = OpenMusicEventSourcePatchLocationResolver { request in
                #expect(request == OpenMusicEventSourcePatchRequest(eventID: eventID))
                operations.withLock { $0.append("resolve") }
                return location
            }
            $0.sourcePatchPublisher = SourcePatchPublisher { request in
                operations.withLock { $0.append("publish") }
                #expect(
                    request == SourcePatchPublishRequest(
                        description: "Updated the event name.",
                        location: location,
                        patch: patch,
                        title: "Update the event name"
                    )
                )
                return publication
            }
        } operation: {
            var state = SourceProposalFlow.State(eventID: eventID, patch: patch)
            state.description = "Updated the event name."
            state.title = "Update the event name"
            return TestStore(initialState: state) {
                SourceProposalFlow()
            }
        }

        let task = store.send(.formSubmitted(store.state.form.value))
        await task?.value
        #expect(store.state.status == .created(publication))
        expectNoDifference(operations.withLock { $0 }, ["prepare", "resolve", "publish"])

        await store.dismount()
    }

    @Test
    func createdSourceProposalDismissesToReviewWhenTangledReviewLoads() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedTangledSourceBackedEvent(eventID, in: database)
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
        let review = testTangledPullReview()
        let publication = SourcePatchPublication(
            sourceChangeID: review.uri,
            sourceChangeURL: URL(string: "https://tangled.org/woody.fm/wicked-woods/pulls")
        )
        let requests = Mutex([OpenMusicEventTangledPullReviewRequest]())
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
            $0.openMusicEventSourcePatchLocationResolver =
                OpenMusicEventSourcePatchLocationResolver { _ in
                    SourcePatchLocation(
                        repositoryURL: URL(fileURLWithPath: "/tmp/source-repository"),
                        relativePath: "events/event-1"
                    )
                }
            $0.sourcePatchPublisher = SourcePatchPublisher { _ in publication }
            $0.tangledPullReviewClient = TangledPullReviewClient { request in
                requests.withLock { $0.append(request) }
                return [review]
            }
        } operation: {
            var state = EventWorkspace.State(eventID: eventID)
            state.changes.sourcePatchStatus = .generated(
                WorkspaceChanges.SourceProposalPreparation(
                    patch: patch,
                    sourceWorkspaceSummary: state.changes.sourceWorkspaceSummary
                )
            )
            state.changes.sourceProposal = SourceProposalFlow.State(eventID: eventID, patch: patch)
            state.changes.sourceProposal?.title = "Update the event"
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        let task = store.send(
            .changes(
                .sourceProposal(
                    .formSubmitted(try #require(store.state.changes.sourceProposal?.form.value))
                )
            )
        )
        await task?.value

        #expect(store.state.reviews.pendingCreatedReviewID == nil)
        #expect(store.state.reviews.selectedReview == .loaded(review))
        #expect(store.state.reviews.reviewsStatus == .loaded([review]))
        #expect(store.state.changes.sourceProposal == nil)

        expectNoDifference(
            requests.withLock { $0 },
            [
                OpenMusicEventTangledPullReviewRequest(eventID: eventID),
                OpenMusicEventTangledPullReviewRequest(eventID: eventID),
            ]
        )
        await store.dismount()
    }

    @Test
    func dismissedCreatedSourceProposalStopsPendingReviewNavigation() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        try await seedTangledSourceBackedEvent(eventID, in: database)
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
        let review = testTangledPullReview()
        let publication = SourcePatchPublication(
            sourceChangeID: review.uri,
            sourceChangeURL: URL(string: "https://tangled.org/woody.fm/wicked-woods/pulls")
        )
        let store: TestStore<EventWorkspace> = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            var state = EventWorkspace.State(eventID: eventID)
            state.changes.sourcePatchStatus = .generated(
                WorkspaceChanges.SourceProposalPreparation(
                    patch: patch,
                    sourceWorkspaceSummary: state.changes.sourceWorkspaceSummary
                )
            )
            state.changes.sourceProposal = SourceProposalFlow.State(eventID: eventID, patch: patch)
            state.changes.sourceProposal?.status = .created(publication)
            state.reviews.pendingCreatedReviewID = review.uri
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        let task = store.send(.changes(.sourceProposal(.doneButtonTapped)))
        await task?.value

        #expect(store.state.reviews.pendingCreatedReviewID == nil)
        #expect(store.state.changes.sourceProposal == nil)
        #expect(store.state.reviews.selectedReview == nil)
        await store.dismount()
    }

    @Test
    func failedProposalCanBeRetried() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let location = SourcePatchLocation(
            repositoryURL: URL(fileURLWithPath: "/tmp/source-repository"),
            relativePath: "events/event-1"
        )
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
        let workspaceID = EditingWorkspaceRecord.ID(rawValue: "team.retry")
        let grant = Shared<AuthoringGrant?>(
            value: AuthoringGrant(
                principal: .local,
                role: .owner,
                workspaceID: workspaceID
            )
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.useAuthoringContext(workspaceID, grant: SharedReader(grant))
            $0[AuthoringPolicyClient.self] = .authoring
            $0.openMusicEventSourcePatchLocationResolver = OpenMusicEventSourcePatchLocationResolver { _ in
                location
            }
            $0.sourcePatchPublisher = SourcePatchPublisher { _ in
                throw SourceProposalTestError.failed
            }
        } operation: {
            var state = SourceProposalFlow.State(eventID: eventID, patch: patch)
            state.title = "Update the event name"
            return TestStore(
                initialState: SourceProposalErrorReportingHost.State(proposal: state)
            ) {
                SourceProposalErrorReportingHost()
            }
        }

        await withIssueReporters([]) {
            let task = store.send(.proposal(.formSubmitted(store.state.proposal.form.value)))
            await task?.value
        }
        guard case let .failed(failure) = store.state.proposal.status else {
            #expect(Bool(false))
            return
        }
        expectNoDifference(failure.message, "Unable to create proposal.")
        expectNoDifference(
            store.state.errorNotifications.state.latestError?.message.fallback,
            "Unable to create proposal."
        )
        expectNoDifference(
            store.state.errorNotifications.state.latestError?.operation.rawValue,
            "source.proposal.publish"
        )
        #expect(grant.wrappedValue != nil)

        await withIssueReporters([]) {
            let retryTask = store.send(.proposal(.formSubmitted(store.state.proposal.form.value)))
            await retryTask?.value
        }
        guard case let .failed(retryFailure) = store.state.proposal.status else {
            #expect(Bool(false))
            return
        }
        expectNoDifference(retryFailure.message, "Unable to create proposal.")
        #expect(grant.wrappedValue != nil)

        await store.dismount()
    }

    @Test
    func revokedProposalAccessReturnsToAttendeeWithoutPublishing() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let workspaceID = EditingWorkspaceRecord.ID(rawValue: "team.revoked")
        let grant = Shared<AuthoringGrant?>(
            value: AuthoringGrant(
                principal: .actor(try #require(DID("did:plc:revoked"))),
                role: .collaborator([.propose]),
                workspaceID: workspaceID
            )
        )
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: Draft remains\n".utf8)
                )
            ]
        )
        let publishRequests = Mutex([SourcePatchPublishRequest]())
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.useAuthoringContext(workspaceID, grant: SharedReader(grant))
            $0[AuthoringPolicyClient.self] = .attendee
            $0.sourcePatchPublisher = SourcePatchPublisher { request in
                publishRequests.withLock { $0.append(request) }
                return SourcePatchPublication()
            }
        } operation: {
            var proposal = SourceProposalFlow.State(eventID: eventID, patch: patch)
            proposal.title = "Publish the saved draft"
            return TestStore(
                initialState: SourceProposalRevocationHost.State(
                    grant: grant,
                    proposal: proposal
                )
            ) {
                SourceProposalRevocationHost()
            }
        }

        try await withIssueReporters([]) {
            let task = store.send(.proposal(.formSubmitted(
                try #require(store.state.proposal?.form.value)
            )))
            await task?.value
        }

        #expect(store.state.grant == nil)
        #expect(store.state.proposal == nil)
        #expect(store.state.didRevokeAuthoring)
        #expect(store.state.savedPatch == patch)
        expectNoDifference(publishRequests.withLock { $0 }, [])
        expectNoDifference(
            store.state.errorNotifications.state.latestError?.message.fallback,
            "Your authoring access changed. Your edits remain saved."
        )

        await store.dismount()
    }

    @Test
    func proposalFailureRechecksRevokedAccessBeforeReportingFailure() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let actor = try #require(DID("did:plc:revoked-after-publish"))
        let workspaceID = EditingWorkspaceRecord.ID(rawValue: "team.revoked-after-publish")
        let role = OME.WorkspaceRole.collaborator([.propose])
        let grant = Shared<AuthoringGrant?>(
            value: AuthoringGrant(
                principal: .actor(actor),
                role: role,
                workspaceID: workspaceID
            )
        )
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: Draft remains\n".utf8)
                )
            ]
        )
        let admissionRequestCount = Mutex(0)
        let publishRequestCount = Mutex(0)
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.useAuthoringContext(workspaceID, grant: SharedReader(grant))
            $0[AuthoringPolicyClient.self] = AuthoringPolicyClient { requestedWorkspaceID in
                #expect(requestedWorkspaceID == workspaceID)
                let requestNumber = admissionRequestCount.withLock { count in
                    count += 1
                    return count
                }
                return requestNumber == 1
                    ? .granted(principal: .actor(actor), role: role)
                    : .denied
            }
            $0.openMusicEventSourcePatchLocationResolver = OpenMusicEventSourcePatchLocationResolver { _ in
                SourcePatchLocation(
                    repositoryURL: URL(fileURLWithPath: "/tmp/source-repository"),
                    relativePath: "events/event-1"
                )
            }
            $0.sourcePatchPublisher = SourcePatchPublisher { _ in
                publishRequestCount.withLock { $0 += 1 }
                throw SourceProposalTestError.failed
            }
        } operation: {
            var proposal = SourceProposalFlow.State(eventID: eventID, patch: patch)
            proposal.title = "Publish the saved draft"
            return TestStore(
                initialState: SourceProposalRevocationHost.State(
                    grant: grant,
                    proposal: proposal
                )
            ) {
                SourceProposalRevocationHost()
            }
        }

        try await withIssueReporters([]) {
            let task = store.send(.proposal(.formSubmitted(
                try #require(store.state.proposal?.form.value)
            )))
            await task?.value
        }

        #expect(store.state.grant == nil)
        #expect(store.state.proposal == nil)
        #expect(store.state.didRevokeAuthoring)
        #expect(store.state.savedPatch == patch)
        #expect(admissionRequestCount.withLock { $0 } == 2)
        #expect(publishRequestCount.withLock { $0 } == 1)
        expectNoDifference(
            store.state.errorNotifications.state.latestError?.message.fallback,
            "Your authoring access changed. Your edits remain saved."
        )

        await store.dismount()
    }

    @Test
    func embeddedSourceProposalActionUsesParentAuthorizationBroker() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let location = SourcePatchLocation(
            repositoryURL: URL(fileURLWithPath: "/tmp/source-repository"),
            relativePath: "events/event-1"
        )
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
        let publication = SourcePatchPublication(
            sourceChangeURL: URL(string: "https://source.woody.fm/events/event-1/proposals/1")
        )
        let requirement = OpenMusicEventOAuth.proposalAuthRequirement
        let authorizationCenter = AuthorizationRequestCenter()
        var proposal = SourceProposalFlow.State(eventID: eventID, patch: patch)
        proposal.title = "Update the event name"

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.openMusicEventAuthorizationRequests = OpenMusicEventAuthorizationRequests(
                center: authorizationCenter
            )
            $0.openMusicEventSourcePatchLocationResolver = OpenMusicEventSourcePatchLocationResolver { _ in
                location
            }
            $0.sourcePatchPublisher = SourcePatchPublisher { _ in
                @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
                try await authorizationBroker.authorize(requirement)
                return publication
            }
        } operation: {
            TestStore(
                initialState: SourceProposalEmbeddedHost.State(proposal: proposal)
            ) {
                SourceProposalEmbeddedHost()
                    .transformDependency(\.oauthAuthorizationBroker) {
                        $0 = authorizationCenter.broker
                    }
            }
        }

        let proposalForm = try #require(
            store.state.proposal?.form.value
        )
        let task = store.send(
            .proposal(.formSubmitted(proposalForm))
        )
        await fulfillAuthorizationRequest(
            from: authorizationCenter,
            requirement: requirement
        )
        await task?.value
        #expect(
            store.state.proposal?.status
                == .created(publication)
        )
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
        let resetRequests = Mutex([SourceProposalTarget]())
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
            state.changes.sourceProposal = SourceProposalFlow.State(eventID: eventID, patch: patch)
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
        #expect(store.state.changes.sourceProposal == nil)
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
            state.changes.sourceProposal = SourceProposalFlow.State(
                eventID: eventID,
                patch: originalPatch
            )
            state.changes.sourceProposal?.title = "Update the event"
            state.changes.sourceProposal?.description = "Describe the changes."
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        let task = store.send(.changes(.checkChangesButtonTapped))
        await task?.value

        #expect(store.state.changes.sourcePatchStatus.preparation?.patch == regeneratedPatch)
        #expect(store.state.changes.sourceProposal == nil)
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
            state.changes.sourceProposal = SourceProposalFlow.State(eventID: eventID, patch: patch)
            return TestStore(initialState: state) {
                EventWorkspace()
            }
        }

        let task = store.send(.changes(.checkChangesButtonTapped))
        await task?.value

        #expect(store.state.changes.sourcePatchStatus.preparation?.patch == SourcePatch())
        #expect(store.state.changes.sourceProposal == nil)
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

        #expect(store.state.changes.sourceProposal == nil)
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
                        source: reviewSource,
                        organizerID: request.organizerID,
                        sourceProvenance: request.sourceProvenance
                    )
                )
            }
            $0.uuid = .incrementing
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
                    review: review,
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

private enum SourceProposalTestError: Equatable, Error {
    case failed
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

@Feature
private struct SourceProposalErrorReportingHost {
    struct State {
        var errorNotifications = Spawn(ErrorNotifications.State())
        var proposal: SourceProposalFlow.State
    }

    enum Action {
        case proposal(SourceProposalFlow.Action)
    }

    var body: some Feature {
        Scope(\.proposal, action: \.proposal) {
            SourceProposalFlow()
        }
        .spawn(\.errorNotifications) {
            ErrorNotifications()
        }
        .onEvent(ErrorReported.self) { error, state in
            state.errorNotifications.state.report(error)
        }
    }
}

@Feature
private struct SourceProposalEmbeddedHost {
    struct State {
        var proposal: SourceProposalFlow.State?
    }

    enum Action {
        case proposal(SourceProposalFlow.Action)
    }

    var body: some Feature {
        Update { _, _ in }
            .ifLet(\.proposal, action: \.proposal) {
                SourceProposalFlow()
            }
    }
}

@Feature
private struct SourceProposalRevocationHost {
    struct State {
        init(
            grant: Shared<AuthoringGrant?>,
            proposal: SourceProposalFlow.State
        ) {
            self._grant = grant
            self.proposal = proposal
            self.savedPatch = proposal.patch
        }

        @Shared var grant: AuthoringGrant?
        var proposal: SourceProposalFlow.State?
        var savedPatch: SourcePatch
        var didRevokeAuthoring = false
        var errorNotifications = Spawn(ErrorNotifications.State())
    }

    enum Action {
        case proposal(SourceProposalFlow.Action)
    }

    var body: some Feature {
        Update { _, _ in }
            .ifLet(\.proposal, action: \.proposal) {
                SourceProposalFlow()
            }
            .spawn(\.errorNotifications) {
                ErrorNotifications()
            }
            .onEvent(AuthoringAccessRevoked.self) { _, state in
                state.$grant.withLock { $0 = nil }
                state.proposal = nil
                state.didRevokeAuthoring = true
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
