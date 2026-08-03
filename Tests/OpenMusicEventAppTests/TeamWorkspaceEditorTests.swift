import ATProto
import ComposableArchitecture2
import ComposableAuthoring
import ComposableWorkspace
import CustomDump
import Dependencies
import ErrorHandling
import FileTree
import Foundation
import IssueReporting
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import OpenMusicEventTimeZones
import Sharing
import SourceEditing
import SQLiteData
import Synchronization
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

private typealias OMERecord = OpenMusicEventLexicon.OpenMusicEvent

@MainActor
@Suite(.tcaExhaustivity(.off))
struct TeamWorkspaceEditorTests {
    @Test
    func teamWorkspaceEditorUsesOrganizerSourceScope() throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(OMERecord.Organizer.ID("did:plc:sourcemanagement"))
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let sourceBaselineID = SourceBaselineRecord.ID(rawValue: "source")
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: SourceWorkspace.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            ) {
                SourceWorkspace()
            }
        }

        expectNoDifference(
            store.state.target,
            .calendar(calendarID, sourceBaselineID)
        )
    }

    @Test
    func eventWorkspaceUsesSourceWorkspaceScopeWhenSourceBacked() async throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(OMERecord.Organizer.ID("did:plc:sourcemanagement"))
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let eventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: OMERecord.ID("source-event")
        )
        let contributorID = OMERecord.Contributor.ID(
            organizerID: organizerID,
            eventID: eventID.eventID,
            contributorID: OMERecord.ID("woody-melling")
        )
        let sourceProvenance = makeSourceProvenance(
            reference: "tangled.org/woody.fm/source-management"
        )
        let sourceBaseline = SourceBaselineRecord(
            source: sourceProvenance,
            databaseFileName: "reference.sqlite",
            importedAt: Date(timeIntervalSince1970: 1)
        )
        try await seedSourceWorkspaceSummaryRows(
            database: database,
            organizerID: organizerID,
            calendarID: calendarID,
            eventID: eventID,
            contributorID: contributorID,
            sourceBaseline: sourceBaseline
        )
        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            EventWorkspace.State(eventID: eventID)
        }

        expectNoDifference(
            state.target,
            .event(eventID)
        )
    }

    @Test
    func eventWorkspaceSummaryKeepsChangesOutsideTheFocusedEvent() throws {
        let organizerID = try #require(OMERecord.Organizer.ID("did:plc:sourcemanagement"))
        let eventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: OMERecord.ID("source-event")
        )
        let otherEventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: OMERecord.ID("other-source-event")
        )
        let focusedRecord = sourceRecordChange(eventID: eventID)
        let otherRecord = sourceRecordChange(eventID: otherEventID)

        let summary = SourceWorkspaceSummary(
            target: .event(eventID),
            availability: .available,
            groups: [
                SourceChangeGroup(
                    id: OMERecord.Contributor.tableName,
                    displayName: "Contributor",
                    added: 0,
                    modified: 2,
                    deleted: 0,
                    records: [otherRecord, focusedRecord]
                ),
            ]
        )

        #expect(summary.totalCount == 2)
        #expect(summary.focusedCount == 1)
        #expect(summary.outOfTargetCount == 1)
        #expect(
            summary.outOfTargetInclusionDescription
                == "1 change from another event is included in this workspace."
        )
        expectNoDifference(summary.groups.first?.records, [focusedRecord, otherRecord])
    }

    @Test
    func draftSummarySectionCarriesSemanticRecordComparisons() throws {
        let organizerID = try #require(OMERecord.Organizer.ID("did:plc:sourcemanagement"))
        let eventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: OMERecord.ID("source-event")
        )
        let record = sourceRecordChange(eventID: eventID)
        let comparisons = SourceRecordComparisons([
            AnySourceRecordComparison(
                SourceRecordComparison(
                    change: record,
                    left: "Old contributor",
                    right: "Updated contributor"
                )
            ),
        ])
        let summary = SourceWorkspaceSummary(
            target: .event(eventID),
            availability: .available,
            groups: [
                SourceChangeGroup(
                    id: OMERecord.Contributor.tableName,
                    displayName: "Contributor",
                    added: 0,
                    modified: 1,
                    deleted: 0,
                    records: [record]
                ),
            ],
            recordComparisons: comparisons
        )

        let section = SourceChangeSummarySection(
            groups: summary.groups,
            recordComparisons: summary.recordComparisons
        )

        expectNoDifference(section.groups, summary.groups)
        expectNoDifference(section.recordComparisons, comparisons)
    }

    @Test
    func generatesCalendarSourcePatch() async throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(OMERecord.Organizer.ID("did:plc:sourcemanagement"))
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let sourceBaselineID = SourceBaselineRecord.ID(rawValue: "source")
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "calendar.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let expectedWorkspaceSummary = try SourceWorkspaceSummary.query(
            target: .calendar(calendarID, sourceBaselineID),
            using: database
        )
        let expectedSourceFileAttributions = try await database.read { db in
            try openMusicEventSourceFileAttributions(
                patch: patch,
                groups: expectedWorkspaceSummary.groups,
                recordComparisons: expectedWorkspaceSummary.recordComparisons,
                in: db
            )
        }
        let expectedPreparation = WorkspaceChanges.SourceProposalPreparation(
            patch: patch,
            sourceFileAttributions: expectedSourceFileAttributions,
            sourceWorkspaceSummary: expectedWorkspaceSummary
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] =
                SourcePatchGenerator { request in
                    #expect(
                        request == OpenMusicEventCalendarSourcePatchRequest(
                            calendarID: calendarID,
                            sourceBaselineID: sourceBaselineID
                        )
                    )
                    return patch
                }
        } operation: {
            TestStore(
                initialState: SourceWorkspace.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            ) {
                SourceWorkspace()
            }
        }

        let task = store.send(.changes(.checkChangesButtonTapped)) {
            $0.changes.sourcePatchStatus = .generating(.checkChanges)
        }
        await task?.value
        expectNoDifference(
            store.state.changes.sourcePatchStatus,
            .generated(expectedPreparation)
        )
    }

    @Test
    func proposesCalendarSourcePatch() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let workingDatabasePath = directoryURL.appending(path: "working.sqlite").path
        let baselineDatabasePath = directoryURL.appending(path: "baseline.sqlite").path
        let workingDatabase = try makePreparedDatabase(path: workingDatabasePath)
        let baselineDatabase = try makePreparedDatabase(path: baselineDatabasePath)
        let baselineReference = SourceBaselineDatabase(
            path: baselineDatabasePath,
            database: baselineDatabase
        )
        let organizerID = try #require(OMERecord.Organizer.ID("did:plc:sourcemanagement"))
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/woody.fm/source-management",
            ref: "main"
        )
        let sourceBaseline = SourceBaselineRecord(
            source: sourceProvenance,
            databaseFileName: "reference.sqlite",
            importedAt: Date(timeIntervalSince1970: 1)
        )
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "calendar.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        try await seedOrganizerSourceWorkspaceDefaults(
            database: workingDatabase,
            organizerID: organizerID,
            calendarID: calendarID,
            sourceBaseline: sourceBaseline
        )
        try await seedOrganizerSourceWorkspaceDefaults(
            database: baselineDatabase,
            organizerID: organizerID,
            calendarID: calendarID,
            sourceBaseline: sourceBaseline
        )
        try await workingDatabase.write { db in
            try db.execute(
                sql: """
                UPDATE "app.openmusicevent.calendar"
                SET "name" = ?
                WHERE "ownerID" = ?
                  AND "calendarID" = ?
                """,
                arguments: [
                    "Wicked Woods 2026",
                    String(describing: organizerID),
                    calendarID.calendarID.rawValue.rawValue,
                ]
            )
        }
        let workspaceID = EditingWorkspaceRecord.ID(sourceBaselineID: sourceBaseline.id)
        let workspaceDatabase = try SourceWorkspaceDatabase(
            workspaceID: workspaceID,
            mainDatabase: workingDatabase,
            referenceDatabase: baselineReference
        )
        let expectedWorkspaceSummary = try await withDependencies {
            $0.defaultDatabase = workspaceDatabase.database
        } operation: {
            try SourceWorkspaceSummary.query(
                target: .calendar(calendarID, sourceBaseline.id),
                using: workspaceDatabase.database
            )
        }
        #expect(expectedWorkspaceSummary.totalCount == 1)
        let expectedSourceFileAttributions = try await workspaceDatabase.database.read { db in
            try openMusicEventSourceFileAttributions(
                patch: patch,
                groups: expectedWorkspaceSummary.groups,
                recordComparisons: expectedWorkspaceSummary.recordComparisons,
                in: db
            )
        }
        let expectedPreparation = WorkspaceChanges.SourceProposalPreparation(
            patch: patch,
            sourceFileAttributions: expectedSourceFileAttributions,
            sourceWorkspaceSummary: expectedWorkspaceSummary
        )
        let grant = SharedReader<AuthoringGrant?>(
            value: AuthoringGrant(
                principal: .local,
                role: .owner,
                workspaceID: workspaceID
            )
        )
        let workspacePhase = Shared<WorkspacePhase<SourcePatch>>(
            value: .ready(
                .canonical(
                    WorkspaceBranchReference(
                        branch: WorkspaceBranch(rawValue: "main"),
                        revision: WorkspaceRevision(rawValue: "main-1")
                    )
                )
            )
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = workspaceDatabase.database
            $0.useAuthoringContext(workspaceID, grant: grant)
            $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] =
                SourcePatchGenerator { request in
                    #expect(
                        request == OpenMusicEventCalendarSourcePatchRequest(
                            calendarID: calendarID,
                            sourceBaselineID: sourceBaseline.id
                        )
                    )
                    return patch
                }
        } operation: {
            var state = SourceWorkspace.State(
                sourceBaselineID: sourceBaseline.id,
                calendarID: calendarID
            )
            state.changes.$sourceWorkspaceSummary = Fetch(
                wrappedValue: expectedWorkspaceSummary
            )
            state.changes.sourcePatchStatus = .generated(
                WorkspaceChanges.SourceProposalPreparation(
                    patch: patch,
                    sourceFileAttributions: expectedSourceFileAttributions,
                    sourceWorkspaceSummary: state.changes.sourceWorkspaceSummary
                )
            )
            return TestStore(initialState: state) {
                SourceWorkspace()
                    .environment(
                        ComposableAuthoring.AuthoringContext(grant: grant)
                    )
                    .environment(
                        WorkspaceContext(
                            phase: SharedReader(workspacePhase),
                            source: SharedReader(value: workspaceDatabase)
                        )
                    )
            }
        }

        let task = store.send(.changes(.proposeChangesButtonTapped))
        await task?.value

        #expect(store.state.changes.canGenerateSourcePatch)
        #expect(store.state.changes.canPublishSourceProposal)
        expectNoDifference(
            store.state.availablePages(authoringAccess: .authoring(.owner)),
            [.changes, .reviews]
        )
        expectNoDifference(store.state.changes.sourcePatchStatus, .generated(expectedPreparation))
        #expect(store.state.changes.proposalDraft?.groups == expectedWorkspaceSummary.groups)
        #expect(
            store.state.changes.proposalDraft?.recordComparisons
                == expectedWorkspaceSummary.recordComparisons
        )
        await store.dismount()
    }

    @Test
    func localCalendarWorkspaceDoesNotPresentProposalOrReviewControls() throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(OMERecord.Organizer.ID("did:plc:sourcemanagement"))
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let sourceBaselineID = SourceBaselineRecord.ID(rawValue: "local-source")
        try database.write { db in
            try SourceBaselineRecord.insert {
                SourceBaselineRecord(
                    id: sourceBaselineID,
                    sourceKind: .local,
                    sourceReference: "/tmp/source-management",
                    ref: nil,
                    databaseFileName: "reference.sqlite",
                    importedAt: Date(timeIntervalSince1970: 1)
                )
            }
            .execute(db)
        }
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "calendar.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = SourceWorkspace.State(
                sourceBaselineID: sourceBaselineID,
                calendarID: calendarID
            )
            state.changes.sourcePatchStatus = .generated(
                WorkspaceChanges.SourceProposalPreparation(
                    patch: patch,
                    sourceWorkspaceSummary: state.changes.sourceWorkspaceSummary
                )
            )
            return TestStore(initialState: state) {
                SourceWorkspace()
            }
        }

        #expect(store.state.changes.canGenerateSourcePatch)
        #expect(!store.state.changes.canPublishSourceProposal)
        expectNoDifference(
            store.state.availablePages(authoringAccess: .attendee),
            [.changes]
        )

        store.send(.changes(.proposeChangesButtonTapped))

        #expect(store.state.changes.proposalDraft == nil)
    }

    @Test
    func resetsCalendarSourceChangesAndClearsProposalState() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let workingDatabasePath = directoryURL.appending(path: "working.sqlite").path
        let baselineDatabasePath = directoryURL.appending(path: "baseline.sqlite").path
        let workingDatabase = try makePreparedDatabase(path: workingDatabasePath)
        let baselineDatabase = try makePreparedDatabase(path: baselineDatabasePath)
        let baselineReference = SourceBaselineDatabase(
            path: baselineDatabasePath,
            database: baselineDatabase
        )
        let organizerID = try #require(OMERecord.Organizer.ID("did:plc:sourcemanagement"))
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let sourceBaseline = SourceBaselineRecord(
            source: makeSourceProvenance(
                reference: "tangled.org/woody.fm/source-management"
            ),
            databaseFileName: "reference.sqlite",
            importedAt: Date(timeIntervalSince1970: 1)
        )
        let sourceBaselineID = sourceBaseline.id
        let resetRequests = Mutex([OpenMusicEventSourceTarget]())
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "calendar.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        try await seedOrganizerSourceWorkspaceDefaults(
            database: workingDatabase,
            organizerID: organizerID,
            calendarID: calendarID,
            sourceBaseline: sourceBaseline
        )
        try await seedOrganizerSourceWorkspaceDefaults(
            database: baselineDatabase,
            organizerID: organizerID,
            calendarID: calendarID,
            sourceBaseline: sourceBaseline
        )
        try await workingDatabase.write { db in
            try db.execute(
                sql: """
                UPDATE "app.openmusicevent.calendar"
                SET "name" = ?
                WHERE "ownerID" = ?
                  AND "calendarID" = ?
                """,
                arguments: [
                    "Wicked Woods 2026",
                    String(describing: organizerID),
                    calendarID.calendarID.rawValue.rawValue,
                ]
            )
        }
        let workspaceDatabase = try SourceWorkspaceDatabase(
            workspaceID: EditingWorkspaceRecord.ID(sourceBaselineID: sourceBaselineID),
            mainDatabase: workingDatabase,
            referenceDatabase: baselineReference
        )
        let workspaceSummary = try SourceWorkspaceSummary.query(
            target: .calendar(calendarID, sourceBaselineID),
            using: workspaceDatabase.database
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = workspaceDatabase.database
            $0.eventWorkspaceResetter = EventWorkspaceResetter(
                reset: { eventID in
                    Issue.record("Expected source reset request, not event reset for \(eventID).")
                },
                resetSourceChanges: { target in
                    resetRequests.withLock { $0.append(target) }
                }
            )
        } operation: {
            var state = SourceWorkspace.State(
                sourceBaselineID: sourceBaselineID,
                calendarID: calendarID
            )
            state.changes.$sourceWorkspaceSummary = Fetch(wrappedValue: workspaceSummary)
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
                SourceWorkspace()
            }
        }

        let task = store.send(.changes(.resetChangesButtonTapped))
        await task?.value

        #expect(store.state.changes.resetStatus == .idle)
        #expect(store.state.changes.proposalDraft == nil)
        guard case let .generated(preparation) = store.state.changes.sourcePatchStatus else {
            Issue.record("Expected an empty generated patch after reset.")
            return
        }
        #expect(preparation.patch.isEmpty)
        expectNoDifference(
            resetRequests.withLock { $0 },
            [.calendar(calendarID, sourceBaselineID)]
        )
        await store.dismount()
    }

    @Test
    func failedCalendarSourcePatchStoresFailure() async throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(OMERecord.Organizer.ID("did:plc:sourcemanagement"))
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let sourceBaselineID = SourceBaselineRecord.ID(rawValue: "source")

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] =
                SourcePatchGenerator { _ in
                    throw SourceWorkspacePatchFailure()
                }
        } operation: {
            TestStore(
                initialState: SourceWorkspaceErrorHost.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            ) {
                SourceWorkspaceErrorHost()
            }
        }

        await withIssueReporters([]) {
            await store.send(
                to: \.teamWorkspaceEditor,
                .changes(.checkChangesButtonTapped)
            )?.value
        }

        guard case .failed = store.state.teamWorkspaceEditor.state.changes.sourcePatchStatus else {
            Issue.record("Expected source patch status to be failed.")
            return
        }
        #expect(store.state.errorNotifications.state.latestError == nil)
    }

    @Test
    func malformedSourceRecordKeepsRawSourceChangeReviewable() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let workingDatabasePath = directoryURL.appending(path: "working.sqlite").path
        let baselineDatabasePath = directoryURL.appending(path: "baseline.sqlite").path
        let workingDatabase = try makePreparedDatabase(path: workingDatabasePath)
        let baselineDatabase = try makePreparedDatabase(path: baselineDatabasePath)
        let baselineReference = SourceBaselineDatabase(
            path: baselineDatabasePath,
            database: baselineDatabase
        )
        let organizerID = try #require(OMERecord.Organizer.ID("did:web:wickedwoods.example"))
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let eventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: OMERecord.ID("wicked-woods-ome-2025")
        )
        let contributorID = OMERecord.Contributor.ID(
            organizerID: organizerID,
            eventID: eventID.eventID,
            contributorID: OMERecord.ID("woody-melling")
        )
        let sourceProvenance = makeSourceProvenance(
            reference: "tangled.org/woody.fm/wicked-woods-ome"
        )
        let sourceBaseline = SourceBaselineRecord(
            source: sourceProvenance,
            databaseFileName: "reference.sqlite",
            importedAt: Date(timeIntervalSince1970: 1)
        )

        try await seedSourceWorkspaceSummaryRows(
            database: workingDatabase,
            organizerID: organizerID,
            calendarID: calendarID,
            eventID: eventID,
            contributorID: contributorID,
            sourceBaseline: sourceBaseline
        )
        try await seedSourceWorkspaceSummaryRows(
            database: baselineDatabase,
            organizerID: organizerID,
            calendarID: calendarID,
            eventID: eventID,
            contributorID: contributorID,
            sourceBaseline: sourceBaseline
        )
        try await workingDatabase.write { db in
            try db.execute(
                sql: """
                UPDATE "app.openmusicevent.contributor"
                SET "did" = ?
                WHERE "organizerID" = ?
                  AND "eventID" = ?
                  AND "contributorID" = ?
                """,
                arguments: [
                    "not-a-did",
                    String(describing: organizerID),
                    eventID.eventID.rawValue.rawValue,
                    contributorID.contributorID.rawValue.rawValue,
                ]
            )
        }
        let workspaceDatabase = try SourceWorkspaceDatabase(
            workspaceID: EditingWorkspaceRecord.ID(sourceBaselineID: sourceBaseline.id),
            mainDatabase: workingDatabase,
            referenceDatabase: baselineReference
        )
        let workspaceSummary = try SourceWorkspaceSummary.query(
            target: .calendar(calendarID, sourceBaseline.id),
            using: workspaceDatabase.database
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = workspaceDatabase.database
        } operation: {
            let state = SourceWorkspace.State(
                sourceBaselineID: sourceBaseline.id,
                calendarID: calendarID
            )
            state.changes.$sourceWorkspaceSummary = Fetch(wrappedValue: workspaceSummary)
            return TestStore(initialState: state) {
                SourceWorkspace()
            }
        }

        expectNoDifference(
            [
                store.state.changes.$sourceBaseline.loadError.map { _ in
                    "SourceWorkspace.sourceBaseline"
                },
                store.state.changes.$sourceProvenance.loadError.map { _ in
                    "SourceWorkspace.sourceProvenance"
                },
            ]
            .compactMap { $0 },
            []
        )
        #expect(store.state.changes.sourceWorkspaceSummary.availability == .available)
        #expect(store.state.changes.sourceWorkspaceSummary.totalCount == 1)

        let contributorsGroup = try #require(
            store.state.changes.sourceWorkspaceSummary.groups.first { $0.id == "contributors" }
        )
        #expect(contributorsGroup.modified == 1)

        let contributorRecord = try #require(contributorsGroup.records.first)
        #expect(contributorRecord.kind == .modified)
        #expect(contributorRecord.recordDiff == nil)

        let primaryKeyValues = Dictionary(
            uniqueKeysWithValues: contributorRecord.primaryKeyValues.map {
                ($0.columnName, $0.value)
            }
        )
        #expect(primaryKeyValues["organizerID"] == String(describing: organizerID).databaseValue)
        #expect(primaryKeyValues["eventID"] == eventID.eventID.rawValue.rawValue.databaseValue)
        #expect(primaryKeyValues["contributorID"] == contributorID.contributorID.rawValue.rawValue.databaseValue)

        let didChange = try #require(
            contributorRecord.fieldChanges.first { $0.columnName == "did" }
        )
        #expect(didChange.workingValue == "not-a-did".databaseValue)
    }

    @Test
    func createEventButtonRequestsWorkspaceCreateEvent() async throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(OMERecord.Organizer.ID("did:web:wickedwoods.example"))
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let sourceBaselineID = SourceBaselineRecord.ID(rawValue: "wicked-woods")

        let store = withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: SourceWorkspace.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            ) {
                SourceWorkspace()
            }
        }

        let task = store.send(.createEventButtonTapped)
        await store.receive(
            \.delegate,
            .equals(
                .createEventRequested(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            ),
            timeout: .seconds(1)
        )
        await task?.value
    }

    @Test
    func teamWorkspaceDetailPresentsCreateEventFromWorkspaceRequest() throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(OMERecord.Organizer.ID("did:web:wickedwoods.example"))
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let sourceBaselineID = SourceBaselineRecord.ID(rawValue: "wicked-woods")

        let store = withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
        } operation: {
            var state = TeamWorkspaceDetail.State(sourceBaselineID: sourceBaselineID)
            state.teamWorkspaceEditor = SourceWorkspace.State(
                sourceBaselineID: sourceBaselineID,
                calendarID: calendarID
            )
            return TestStore(initialState: state) {
                TeamWorkspaceDetail()
            }
        }

        store.send(
            .teamWorkspaceEditor(
                .delegate(
                    .createEventRequested(
                        sourceBaselineID: sourceBaselineID,
                        calendarID: calendarID
                    )
                )
            )
        )

        guard case let .createEvent(createEvent)? = store.state.destination else {
            Issue.record("Expected source management to present create event.")
            return
        }
        #expect(createEvent.state.sourceBaselineID == sourceBaselineID)
        #expect(createEvent.state.calendarID == calendarID)
        #expect(createEvent.state.eventDirectoryName == "2026")
    }

    @Test
    func createEventInOrganizerWorkspaceWritesAndImports2026() async throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(OMERecord.Organizer.ID("did:web:wickedwoods.example"))
        let repositoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let sourceProvenance = makeSourceProvenance(
            reference: repositoryURL.path(percentEncoded: false)
        )
        let sourceBaseline = SourceBaselineRecord(
            source: sourceProvenance,
            databaseFileName: "baseline.sqlite",
            importedAt: Date(timeIntervalSince1970: 1)
        )
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let expectedLocalEventID = OMERecord.SourceDatabaseInsertion.inferredEventID(
            eventDirectoryName: "2026",
            sourceProvenance: sourceProvenance
        )
        let expectedEventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: expectedLocalEventID
        )
        let recorder = SourceEditPreparationRecorder()
        try await seedOrganizerSourceWorkspaceDefaults(
            database: database,
            organizerID: organizerID,
            calendarID: calendarID,
            sourceBaseline: sourceBaseline
        )

        var initialState = makeCreateEventState(
            sourceBaselineID: sourceBaseline.id,
            calendarID: calendarID
        )
        initialState.eventName = "Wicked Woods 2026"
        initialState.timeZone = TimeZone(identifier: "America/Denver")!
        initialState.hasStartDate = true
        initialState.startDateSelection = try #require(
            LocalDate("2026-08-01")?.at(hour: 12, in: initialState.timeZone)
        )
        let store = makeCreateEventStore(
            initialState: initialState,
            database: database
        ) {
            $0.organizerSourceWorkspace = .live
            $0.sourceEditModePreparation = SourceEditModePreparationClient { sourceBaselineID in
                await recorder.record(sourceBaselineID)
            }
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)
        let preparedSourceBaselineIDs = await recorder.sourceBaselineIDs
        expectNoDifference(preparedSourceBaselineIDs, [sourceBaseline.id])

        let rows = try await database.read { db in
            (
                events: try OMERecord.Event.fetchAll(db),
                organizers: try OMERecord.Organizer.fetchAll(db),
                eventOrganizers: try OMERecord.EventOrganizer.fetchAll(db),
                stages: try OMERecord.Stage.fetchAll(db),
                schedules: try OMERecord.Schedule.fetchAll(db),
                calendarEntries: try OMERecord.CalendarEntry.fetchAll(db),
                sourceProvenances: try EventSourceProvenanceRecord.fetchAll(db),
                workspaces: try EditingWorkspaceRecord.fetchAll(db),
                eventWorkspaces: try EventEditingWorkspaceRecord.fetchAll(db)
            )
        }
        let event = try #require(rows.events.first)
        let eventOrganizer = try #require(rows.eventOrganizers.first)
        let stage = try #require(rows.stages.first)
        let schedule = try #require(rows.schedules.first)
        let calendarEntry = try #require(rows.calendarEntries.first)
        let sourceProvenanceRecord = try #require(rows.sourceProvenances.first)
        let workspace = try #require(rows.workspaces.first)
        let eventWorkspace = try #require(rows.eventWorkspaces.first)

        #expect(rows.events.count == 1)
        expectNoDifference(rows.organizers.map(\.id), [organizerID])
        #expect(rows.eventOrganizers.count == 1)
        #expect(rows.stages.count == 1)
        #expect(rows.schedules.count == 1)
        #expect(rows.calendarEntries.count == 1)
        #expect(rows.sourceProvenances.count == 1)
        #expect(rows.workspaces.count == 1)
        #expect(rows.eventWorkspaces.count == 1)
        #expect(event.id == expectedEventID)
        #expect(event.name == "Wicked Woods 2026")
        #expect(event.startDate == LocalDate("2026-08-01"))
        #expect(event.timeZone.identifier == "America/Denver")
        #expect(eventOrganizer.id.organizerID == expectedEventID.organizerID)
        #expect(eventOrganizer.id.eventID == expectedEventID.eventID)
        #expect(eventOrganizer.id.eventOrganizerID == organizerID)
        #expect(stage.id.organizerID == expectedEventID.organizerID)
        #expect(stage.id.eventID == expectedEventID.eventID)
        #expect(stage.id.stageID == OMERecord.Stage.singletonID)
        #expect(stage.name == OMERecord.Stage.singletonName)
        #expect(stage.color == OMERecord.Stage.singletonColor)
        #expect(stage.category == nil)
        #expect(stage.sortIndex == nil)
        #expect(schedule.id.organizerID == expectedEventID.organizerID)
        #expect(schedule.id.eventID == expectedEventID.eventID)
        #expect(schedule.id.scheduleID == OMERecord.Schedule.singletonID)
        #expect(schedule.date == event.startDate)
        #expect(schedule.startsAt == nil)
        #expect(schedule.endsAt == nil)
        #expect(schedule.customTitle == nil)
        #expect(calendarEntry.id.calendarOwnerID == calendarID.ownerID)
        #expect(calendarEntry.id.calendarID == calendarID.calendarID)
        #expect(calendarEntry.id.entryID.rawValue.rawValue == expectedLocalEventID.rawValue.rawValue)
        #expect(calendarEntry.event.localEventID == expectedEventID)
        #expect(sourceProvenanceRecord.id == expectedEventID)
        #expect(sourceProvenanceRecord.sourceBaselineID == sourceBaseline.id)
        #expect(sourceProvenanceRecord.sourceKind == sourceProvenance.kind)
        #expect(sourceProvenanceRecord.sourceReference == sourceProvenance.reference)
        #expect(sourceProvenanceRecord.ref == sourceProvenance.ref)
        #expect(sourceProvenanceRecord.eventIDOrigin == .inferred)
        #expect(sourceProvenanceRecord.sourceEventDirectory == "2026")
        #expect(workspace.id == EditingWorkspaceRecord.ID(sourceBaselineID: sourceBaseline.id))
        #expect(workspace.kind == .team)
        #expect(workspace.sourceBaselineID == sourceBaseline.id)
        #expect(eventWorkspace.id == expectedEventID)
        #expect(eventWorkspace.workspaceID == workspace.id)

        let eventYMLURL = repositoryURL
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "2026", directoryHint: .isDirectory)
            .appending(path: "event.yml")
        let eventYML = try String(contentsOf: eventYMLURL, encoding: .utf8)
        #expect(eventYML.contains("name: Wicked Woods 2026"))
        #expect(eventYML.contains("startDate:"))
        #expect(eventYML.contains("2026-08-01"))
        #expect(eventYML.contains("timeZone: America/Denver"))
        #expect(eventYML.contains("schedule:"))
        #expect(eventYML.contains("scheduleItems: {}"))
        #expect(!eventYML.contains("performances:"))
        #expect(!eventYML.contains("  date:"))
        #expect(!eventYML.contains("id:"))
        let stageYMLURL = repositoryURL
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "2026", directoryHint: .isDirectory)
            .appending(path: "stages", directoryHint: .isDirectory)
            .appending(path: "stage.yml")
        let stageYML = try String(contentsOf: stageYMLURL, encoding: .utf8)
        #expect(stageYML.contains("name: Stage"))
        #expect(stageYML.contains("color: \(OMERecord.Stage.singletonColor.rawValue)"))
    }

    @Test
    func rolloverEventCarriesDurableGroupsAndStartsFresh() async throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(OMERecord.Organizer.ID("did:web:wickedwoods.example"))
        let repositoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let sourceProvenance = makeSourceProvenance(
            reference: repositoryURL.path(percentEncoded: false)
        )
        let sourceBaseline = SourceBaselineRecord(
            source: sourceProvenance,
            databaseFileName: "baseline.sqlite",
            importedAt: Date(timeIntervalSince1970: 1)
        )
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let previousEventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: OMERecord.ID("2025")
        )
        let mainStageID = OMERecord.Stage.ID(
            organizerID: organizerID,
            eventID: previousEventID.eventID,
            stageID: OMERecord.ID("main")
        )
        let sideStageID = OMERecord.Stage.ID(
            organizerID: organizerID,
            eventID: previousEventID.eventID,
            stageID: OMERecord.ID("side")
        )
        let previousStartDate = try #require(LocalDate("2025-08-01"))
        let previousEndDate = try #require(LocalDate("2025-08-03"))
        let olderEventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: OMERecord.ID("2024")
        )
        let olderStageID = OMERecord.Stage.ID(
            organizerID: organizerID,
            eventID: olderEventID.eventID,
            stageID: OMERecord.ID("main")
        )
        let olderStartDate = try #require(LocalDate("2024-08-01"))
        try await seedOrganizerSourceWorkspaceDefaults(
            database: database,
            organizerID: organizerID,
            calendarID: calendarID,
            sourceBaseline: sourceBaseline
        )
        try await database.write { db in
            try OMERecord.Event.insert {
                CreateEvent.makeEventDraft(
                    id: previousEventID,
                    name: "Wicked Woods 2025",
                    startDate: previousStartDate,
                    endDate: previousEndDate,
                    timeZone: TimeZone(identifier: "America/Denver")!
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: previousEventID,
                    sourceBaselineID: sourceBaseline.id,
                    sourceKind: sourceBaseline.sourceKind,
                    sourceReference: sourceBaseline.sourceReference,
                    ref: sourceBaseline.ref,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "2025"
                )
            }
            .execute(db)
            try OMERecord.Stage.insert {
                OMERecord.Stage.Draft(
                    id: mainStageID,
                    name: "Main Stage",
                    color: 0x00AAEE,
                    category: nil,
                    sortIndex: 0,
                    images: nil,
                    systemIconName: nil,
                    iconShortCode: nil,
                    lineup: nil
                )
            }
            .execute(db)
            try OMERecord.Stage.insert {
                OMERecord.Stage.Draft(
                    id: sideStageID,
                    name: "Side Stage",
                    color: 0xEEAA00,
                    category: nil,
                    sortIndex: 1,
                    images: nil,
                    systemIconName: nil,
                    iconShortCode: nil,
                    lineup: nil
                )
            }
            .execute(db)
            try OMERecord.Event.insert {
                CreateEvent.makeEventDraft(
                    id: olderEventID,
                    name: "Wicked Woods 2024",
                    startDate: olderStartDate,
                    endDate: LocalDate("2024-08-03"),
                    timeZone: TimeZone(identifier: "America/Denver")!
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: olderEventID,
                    sourceBaselineID: sourceBaseline.id,
                    sourceKind: sourceBaseline.sourceKind,
                    sourceReference: sourceBaseline.sourceReference,
                    ref: sourceBaseline.ref,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "2024"
                )
            }
            .execute(db)
            try OMERecord.Stage.insert {
                OMERecord.Stage.Draft(
                    id: olderStageID,
                    name: "Main Stage",
                    color: 0x00AAEE,
                    category: nil,
                    sortIndex: 0,
                    images: nil,
                    systemIconName: nil,
                    iconShortCode: nil,
                    lineup: nil
                )
            }
            .execute(db)
        }
        try writeRolloverSourceEvent(
            in: repositoryURL,
            eventID: previousEventID,
            startDate: previousStartDate
        )

        var initialState = withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        } operation: {
            TeamWorkspaceCreateEvent.State(
                sourceBaselineID: sourceBaseline.id,
                calendarID: calendarID,
                strategy: .rollover
            )
        }
        initialState.eventName = "Wicked Woods 2026"
        initialState.timeZone = TimeZone(identifier: "America/Denver")!
        initialState.hasStartDate = true
        initialState.startDateSelection = try #require(
            LocalDate("2026-08-01")?.at(hour: 12, in: initialState.timeZone)
        )
        let recorder = SourceEditPreparationRecorder()
        let store = makeCreateEventStore(
            initialState: initialState,
            database: database
        ) {
            $0.organizerSourceWorkspace = .live
            $0.sourceEditModePreparation = SourceEditModePreparationClient { sourceBaselineID in
                await recorder.record(sourceBaselineID)
            }
        }

        await store.send(.task)?.value
        let sourceEvent = try #require(store.state.rolloverOptions.first)
        #expect(sourceEvent.id == previousEventID)
        #expect(store.state.rolloverOptions.map(\.id) == [previousEventID, olderEventID])
        #expect(store.state.selectedRolloverEventID == previousEventID)
        #expect(sourceEvent.stages.map(\.id) == [mainStageID, sideStageID])
        store.send(.rolloverStageButtonTapped(sideStageID))
        #expect(store.state.selectedRolloverStageIDs == [mainStageID])

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == true)
        let checklist = try #require(store.state.rolloverChecklist)
        #expect(checklist.carriedForward == [
            "1 stage from Wicked Woods 2025",
            "Venue and location details",
            "Site map and theme/branding",
            "Channel definitions without message history",
        ])
        #expect(checklist.startFresh.contains("Artist and contributor roster"))
        #expect(checklist.startFresh.contains("Schedule performances"))
        let preparedSourceBaselineIDs = await recorder.sourceBaselineIDs
        expectNoDifference(preparedSourceBaselineIDs, [sourceBaseline.id])

        let expectedLocalEventID = OMERecord.SourceDatabaseInsertion.inferredEventID(
            eventDirectoryName: "2026",
            sourceProvenance: sourceProvenance
        )
        let expectedEventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: expectedLocalEventID
        )
        let rows = try await database.read { db in
            (
                events: try OMERecord.Event.fetchAll(db),
                stages: try OMERecord.Stage.fetchAll(db),
                channels: try OMERecord.Channel.fetchAll(db),
                contributors: try OMERecord.Contributor.fetchAll(db),
                schedules: try OMERecord.Schedule.fetchAll(db),
                performances: try OMERecord.Performance.fetchAll(db)
            )
        }
        let newEvent = try #require(rows.events.first(where: { $0.id == expectedEventID }))
        let newStage = try #require(
            rows.stages.first(where: { $0.id.eventID == expectedLocalEventID })
        )
        let newChannel = try #require(
            rows.channels.first(where: { $0.id.eventID == expectedLocalEventID })
        )
        #expect(rows.events.count == 3)
        #expect(rows.stages.filter { $0.id.eventID == expectedLocalEventID }.count == 1)
        #expect(newStage.id.stageID == OMERecord.ID("main"))
        #expect(newStage.lineup == nil)
        #expect(rows.channels.filter { $0.id.eventID == expectedLocalEventID }.count == 1)
        #expect(newChannel.defaultNotificationState == .unsubscribed)
        #expect(newChannel.notificationsRequired == false)
        #expect(rows.contributors.filter { $0.id.eventID == expectedLocalEventID }.isEmpty)
        #expect(rows.schedules.filter { $0.id.eventID == expectedLocalEventID }.count == 1)
        #expect(rows.performances.filter { $0.id.eventID == expectedLocalEventID }.isEmpty)
        #expect(newEvent.description == "The woods return for another season.")
        #expect(newEvent.locations?.first?.address == "1 Forest Road")
        expectNoDifference(
            newEvent.reportingLinks,
            [
                OMERecord.Event.ReportingLink(
                    name: "Safety Concern",
                    url: try #require(URL(string: "https://example.org/safety")),
                    description: "Contact the event safety team."
                ),
                OMERecord.Event.ReportingLink(
                    name: "Accessibility Help",
                    url: try #require(URL(string: "https://example.org/accessibility")),
                    description: nil
                ),
            ]
        )

        let newEventURL = repositoryURL
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "2026", directoryHint: .isDirectory)
        let eventYML = try String(
            contentsOf: newEventURL.appending(path: "event.yml"),
            encoding: .utf8
        )
        #expect(eventYML.contains("name: Wicked Woods 2026"))
        #expect(eventYML.contains("description: The woods return for another season."))
        #expect(eventYML.contains("address: 1 Forest Road"))
        #expect(eventYML.contains("reportingLinks:"))
        #expect(eventYML.contains("name: Safety Concern"))
        #expect(eventYML.contains("name: Accessibility Help"))
        #expect(!FileManager.default.fileExists(atPath: newEventURL.appending(path: "contributors").path()))
        #expect(!FileManager.default.fileExists(atPath: newEventURL.appending(path: "schedules").path()))
        #expect(!FileManager.default.fileExists(atPath: newEventURL.appending(path: "communications").path()))
        #expect(FileManager.default.fileExists(atPath: newEventURL.appending(path: "stages/main.yml").path()))
        #expect(!FileManager.default.fileExists(atPath: newEventURL.appending(path: "stages/side.yml").path()))
        #expect(FileManager.default.fileExists(atPath: newEventURL.appending(path: "channels/general.yml").path()))

        await store.send(.saveButtonTapped)?.value
        #expect(store.state.errorMessage == "An event already exists at that directory.")

        await store.send(.rolloverChecklistDoneButtonTapped)?.value
        #expect(store.isPresented == false)
    }

    @Test
    func createEventRejectsInvalidWorkspaceDirectoryNames() throws {
        let invalidCases = [
            (" ", "Enter an event directory."),
            (".", "Use a single directory name like 2026-pre-party-kelowna."),
            ("..", "Use a single directory name like 2026-pre-party-kelowna."),
            ("events/2026", "Use a single directory name like 2026-pre-party-kelowna."),
            (#"events\2026"#, "Use a single directory name like 2026-pre-party-kelowna."),
        ]
        let organizerID = try #require(OMERecord.Organizer.ID("did:web:wickedwoods.example"))
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )

        for (directoryName, expectedMessage) in invalidCases {
            var initialState = makeCreateEventState(
                sourceBaselineID: SourceBaselineRecord.ID(rawValue: "wicked-woods"),
                calendarID: calendarID
            )
            initialState.eventName = "Wicked Woods 2026"
            initialState.eventDirectoryName = directoryName
            let store = withDependencies {
                $0.context = .test
                $0.date = .constant(Date(timeIntervalSince1970: 0))
            } operation: {
                TestStore(initialState: initialState) {
                    TeamWorkspaceCreateEvent()
                }
            }

            store.send(.saveButtonTapped) {
                $0.errorMessage = expectedMessage
            }
        }
    }

    @Test
    func createEventRejectsMissingStartDate() throws {
        let organizerID = try #require(OMERecord.Organizer.ID("did:web:wickedwoods.example"))
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        var initialState = makeCreateEventState(
            sourceBaselineID: SourceBaselineRecord.ID(rawValue: "wicked-woods"),
            calendarID: calendarID
        )
        initialState.eventName = "Wicked Woods 2026"
        initialState.hasStartDate = false
        let store = withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        } operation: {
            TestStore(initialState: initialState) {
                TeamWorkspaceCreateEvent()
            }
        }

        store.send(.saveButtonTapped) {
            $0.errorMessage = "Choose a start date."
        }
    }

    @Test
    func existingWorkspaceEventDirectoryBlocksCreation() async throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(OMERecord.Organizer.ID("did:web:wickedwoods.example"))
        let repositoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try writeExistingEventDirectory(named: "2026", in: repositoryURL)
        let sourceProvenance = makeSourceProvenance(
            reference: repositoryURL.path(percentEncoded: false)
        )
        let sourceBaseline = SourceBaselineRecord(
            source: sourceProvenance,
            databaseFileName: "baseline.sqlite",
            importedAt: Date(timeIntervalSince1970: 1)
        )
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        try await seedOrganizerSourceWorkspaceDefaults(
            database: database,
            organizerID: organizerID,
            calendarID: calendarID,
            sourceBaseline: sourceBaseline
        )

        var initialState = makeCreateEventState(
            sourceBaselineID: sourceBaseline.id,
            calendarID: calendarID
        )
        initialState.eventName = "Replacement Wicked Woods 2026"
        let store = makeCreateEventStore(
            initialState: initialState,
            database: database
        ) {
            $0.organizerSourceWorkspace = .live
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == "An event already exists at that directory.")
        #expect(store.isPresented == true)

        let eventCount = try await database.read { db in
            try OMERecord.Event.fetchCount(db)
        }
        let eventYML = try String(
            contentsOf: repositoryURL
                .appending(path: "events", directoryHint: .isDirectory)
                .appending(path: "2026", directoryHint: .isDirectory)
                .appending(path: "event.yml"),
            encoding: .utf8
        )
        #expect(eventCount == 0)
        #expect(eventYML.contains("name: Existing Wicked Woods 2026"))
    }
}

private func makePreparedDatabase(path: String? = nil) throws -> any DatabaseWriter {
    try withDependencies {
        $0.context = .test
    } operation: {
        let database: any DatabaseWriter
        if let path {
            database = try DatabasePool(path: path)
        } else {
            database = try SQLiteData.defaultDatabase()
        }
        var migrator = DatabaseMigrator()
        OMERecord.DatabaseMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }
}

@MainActor
private func makeCreateEventStore(
    initialState: TeamWorkspaceCreateEvent.State,
    database: any DatabaseWriter,
    updateDependencies: (inout DependencyValues) -> Void = { _ in }
) -> TestStore<TeamWorkspaceCreateEvent> {
    withDependencies {
        $0.context = .test
        $0.date = .constant(Date(timeIntervalSince1970: 0))
        $0.defaultDatabase = database
        updateDependencies(&$0)
    } operation: {
        TestStore(initialState: initialState) {
            TeamWorkspaceCreateEvent()
        }
    }
}

private func makeCreateEventState(
    sourceBaselineID: SourceBaselineRecord.ID,
    calendarID: OMERecord.Calendar.ID
) -> TeamWorkspaceCreateEvent.State {
    withDependencies {
        $0.context = .test
        $0.date = .constant(Date(timeIntervalSince1970: 0))
    } operation: {
        TeamWorkspaceCreateEvent.State(
            sourceBaselineID: sourceBaselineID,
            calendarID: calendarID
        )
    }
}

private func makeSourceProvenance(
    reference: String
) -> OMERecord.SourceDatabaseInsertion.SourceProvenance {
    OMERecord.SourceDatabaseInsertion.SourceProvenance(
        kind: .local,
        reference: reference,
        ref: nil
    )
}

private func temporaryDirectoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "ome-source-management-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeExistingEventDirectory(
    named directoryName: String,
    in repositoryURL: URL
) throws {
    let eventURL = repositoryURL
        .appending(path: "events", directoryHint: .isDirectory)
        .appending(path: directoryName, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: eventURL, withIntermediateDirectories: true)
    try """
    name: Existing Wicked Woods 2026
    status: planned
    mode: inPerson
    timeZone: America/Denver
    """.write(
        to: eventURL.appending(path: "event.yml"),
        atomically: true,
        encoding: .utf8
    )
}

private func writeRolloverSourceEvent(
    in repositoryURL: URL,
    eventID: OMERecord.Event.ID,
    startDate: LocalDate
) throws {
    let sourceEvent = OpenMusicEventSourceEvent(
        event: EventDTO(
            id: eventID,
            name: "Wicked Woods 2025",
            description: "The woods return for another season.",
            startDate: startDate,
            endDate: LocalDate("2025-08-03"),
            status: .known(.scheduled),
            mode: .known(.inPerson),
            locations: [OMERecord.Event.Location(address: "1 Forest Road")],
            uris: nil,
            timeZone: TimeZone(identifier: "America/Denver")!,
            images: nil,
            contactNumbers: nil,
            categoryConfigs: nil,
            reportingLinks: [
                OMERecord.Event.ReportingLink(
                    name: "Safety Concern",
                    url: URL(string: "https://example.org/safety")!,
                    description: "Contact the event safety team."
                ),
                OMERecord.Event.ReportingLink(
                    name: "Accessibility Help",
                    url: URL(string: "https://example.org/accessibility")!,
                    description: nil
                ),
            ]
        ),
        stages: [
            try FileContent(
                fileName: "main",
                fileType: "yml",
                data: StageDTO(
                    name: "Main Stage",
                    color: 0x00AAEE,
                    lineup: [OMERecord.ID("artist-one")]
                )
            ),
            try FileContent(
                fileName: "side",
                fileType: "yml",
                data: StageDTO(name: "Side Stage", color: 0xEEAA00)
            ),
        ],
        contributors: [
            try FileContent(
                fileName: "artist-one",
                fileType: "md",
                data: ContributorDTO(name: "Artist One", bio: "A returning artist.")
            ),
        ],
        schedules: [
            try FileContent(
                fileName: "saturday",
                fileType: "yml",
                data: ScheduleDTO(
                    date: startDate,
                    scheduleItems: [
                        "main": [
                            ScheduleDTO.ScheduleItem(
                                title: "Old Set",
                                startTime: "18:00",
                                endTime: "19:00"
                            ),
                        ],
                    ]
                )
            ),
        ],
        channels: [
            try FileContent(
                fileName: "general",
                fileType: "yml",
                data: OMERecord.Channel.Draft(
                    id: nil,
                    name: "General",
                    description: "Official event updates.",
                    iconImageURL: nil,
                    headerImageURL: nil,
                    sortIndex: 0,
                    defaultNotificationState: .subscribed,
                    notificationsRequired: false
                )
            ),
        ]
    )
    let eventURL = repositoryURL
        .appending(path: "events", directoryHint: .isDirectory)
        .appending(path: "2025", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: eventURL, withIntermediateDirectories: true)
    _ = try OpenMusicEventSourceEventFileTree().write(sourceEvent, to: eventURL)

    let communicationURL = eventURL
        .appending(path: "communications", directoryHint: .isDirectory)
        .appending(path: "general", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: communicationURL, withIntermediateDirectories: true)
    try """
    name: General
    description: Official event updates.
    """.write(
        to: communicationURL.appending(path: "channel-info.yaml"),
        atomically: true,
        encoding: .utf8
    )
    try """
    ---
    title: Last year's update
    ---

    This message belongs to the old event.
    """.write(
        to: communicationURL.appending(path: "last-year.md"),
        atomically: true,
        encoding: .utf8
    )
}

private func seedOrganizerSourceWorkspaceDefaults(
    database: any DatabaseWriter,
    organizerID: OMERecord.Organizer.ID,
    calendarID: OMERecord.Calendar.ID,
    sourceBaseline: SourceBaselineRecord
) async throws {
    try await database.write { db in
        try OMERecord.Organizer.insert {
            OMERecord.Organizer.Draft(id: organizerID)
        }
        .execute(db)
        try OMERecord.Calendar.insert {
            OMERecord.Calendar.Draft(
                id: calendarID,
                name: "Wicked Woods",
                description: nil,
                images: nil
            )
        }
        .execute(db)
        try SourceBaselineRecord.insert {
            sourceBaseline
        }
        .execute(db)
    }
}

private func seedSourceWorkspaceSummaryRows(
    database: any DatabaseWriter,
    organizerID: OMERecord.Organizer.ID,
    calendarID: OMERecord.Calendar.ID,
    eventID: OMERecord.Event.ID,
    contributorID: OMERecord.Contributor.ID,
    sourceBaseline: SourceBaselineRecord
) async throws {
    try await database.write { db in
        try OMERecord.Organizer.insert {
            OMERecord.Organizer.Draft(id: organizerID)
        }
        .execute(db)
        try OMERecord.Calendar.insert {
            OMERecord.Calendar.Draft(
                id: calendarID,
                name: "Wicked Woods",
                description: nil,
                images: nil
            )
        }
        .execute(db)
        try SourceBaselineRecord.insert {
            sourceBaseline
        }
        .execute(db)
        try OMERecord.Event.insert {
            CreateEvent.makeEventDraft(
                id: eventID,
                name: "Wicked Woods 2025",
                startDate: nil,
                endDate: nil,
                timeZone: TimeZone(identifier: "America/Denver")!
            )
        }
        .execute(db)
        try EventSourceProvenanceRecord.insert {
            EventSourceProvenanceRecord(
                id: eventID,
                sourceBaselineID: sourceBaseline.id,
                sourceKind: sourceBaseline.sourceKind,
                sourceReference: sourceBaseline.sourceReference,
                ref: sourceBaseline.ref,
                eventIDOrigin: .inferred,
                sourceEventDirectory: "2025"
            )
        }
        .execute(db)
        try OMERecord.Contributor.insert {
            OMERecord.Contributor.Draft(
                id: contributorID,
                name: "Woody Melling",
                did: nil,
                bio: nil,
                images: nil,
                links: nil
            )
        }
        .execute(db)
    }
}

private func sourceRecordChange(
    eventID: OMERecord.Event.ID
) -> SourceRecordChange {
    SourceRecordChange(
        tableID: OMERecord.Contributor.tableName,
        kind: .modified,
        primaryKeyValues: [
            SourceColumnValue(
                columnName: "organizerID",
                value: String(describing: eventID.organizerID).databaseValue
            ),
            SourceColumnValue(
                columnName: "eventID",
                value: eventID.eventID.rawValue.rawValue.databaseValue
            ),
            SourceColumnValue(
                columnName: "contributorID",
                value: "woody-melling".databaseValue
            ),
        ],
        fieldChanges: [
            SourceFieldChange(
                columnName: "name",
                baselineValue: "Old Name".databaseValue,
                workingValue: "New Name".databaseValue
            ),
        ]
    )
}

private actor SourceEditPreparationRecorder {
    private var values: [SourceBaselineRecord.ID] = []

    var sourceBaselineIDs: [SourceBaselineRecord.ID] {
        values
    }

    func record(_ sourceBaselineID: SourceBaselineRecord.ID) {
        values.append(sourceBaselineID)
    }
}

private struct SourceWorkspacePatchFailure: Error {}

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

@Feature
private struct SourceWorkspaceErrorHost {
    struct State {
        init(
            sourceBaselineID: SourceBaselineRecord.ID,
            calendarID: OMERecord.Calendar.ID
        ) {
            teamWorkspaceEditor = Spawn(
                SourceWorkspace.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            )
        }

        var errorNotifications = Spawn(ErrorNotifications.State())
        var teamWorkspaceEditor: Spawn<SourceWorkspace>
    }

    enum Action {}

    var body: some Feature {
        Update { _, _ in }
            .spawn(\.teamWorkspaceEditor) {
                SourceWorkspace()
            }
            .spawn(\.errorNotifications) {
                ErrorNotifications()
            }
            .onEvent(ErrorReported.self) { error, state in
                state.errorNotifications.state.report(error)
            }
    }
}
