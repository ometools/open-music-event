import ATProto
import ComposableArchitecture2
import CustomDump
import Dependencies
import ErrorHandling
import Foundation
import IssueReporting
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import OpenMusicEventTimeZones
import SourceEditing
import SQLiteData
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
                initialState: TeamWorkspaceEditor.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            ) {
                TeamWorkspaceEditor()
            }
        }

        expectNoDifference(
            store.state.sourceChangesScope,
            .source(sourceBaselineID: sourceBaselineID, calendarID: calendarID)
        )
    }

    @Test
    func eventWorkspaceUsesEventSourceScope() throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(OMERecord.Organizer.ID("did:plc:sourcemanagement"))
        let eventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: OMERecord.ID("source-event")
        )
        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            EventWorkspace.State(eventID: eventID)
        }

        expectNoDifference(
            state.sourceChangesScope,
            .event(eventID)
        )
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
                initialState: TeamWorkspaceEditor.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            ) {
                TeamWorkspaceEditor()
            }
        }

        let task = store.send(.generateSourcePatchButtonTapped) {
            $0.sourcePatchStatus = .generating
        }
        await store.receive(
            \.sourcePatchGenerationResponse,
            .equals(.success(patch)),
            timeout: .seconds(1)
        ) {
            $0.sourcePatchStatus = .generated(patch)
        }
        await task?.value
    }

    @Test
    func proposesCalendarSourcePatch() throws {
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

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = TeamWorkspaceEditor.State(
                sourceBaselineID: sourceBaselineID,
                calendarID: calendarID
            )
            state.sourcePatchStatus = .generated(patch)
            return TestStore(initialState: state) {
                TeamWorkspaceEditor()
            }
        }

        store.send(.proposeChangeButtonTapped) {
            $0.sourceProposalStatus = .composing
        }
        #expect(store.state.sourceProposal?.target == .calendar(calendarID, sourceBaselineID))
        #expect(store.state.sourceProposal?.sourceChangeGroups == [])
        #expect(store.state.sourceProposal?.patch == patch)
    }

    @Test
    func failedCalendarSourcePatchReportsEphemeralError() async throws {
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
                    throw TeamWorkspaceEditorPatchFailure()
                }
        } operation: {
            TestStore(
                initialState: TeamWorkspaceEditorErrorHost.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            ) {
                TeamWorkspaceEditorErrorHost()
            }
        }

        await withIssueReporters([]) {
            await store.send(to: \.teamWorkspaceEditor, .generateSourcePatchButtonTapped)?.value
        }

        guard case .failed = store.state.teamWorkspaceEditor.state.sourcePatchStatus else {
            Issue.record("Expected source patch status to be failed.")
            return
        }
        let latestError = store.state.errorNotifications.state.latestError
        #expect(latestError?.kind == .unhandled)
        #expect(latestError?.message.fallback == "Unable to check source changes.")
        #expect(latestError?.operation == .sourcePatchGeneration)
    }

    @Test
    func malformedSourceRecordKeepsRawSourceChangeReviewable() async throws {
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let workingDatabasePath = directoryURL.appending(path: "working.sqlite").path
        let baselineDatabasePath = directoryURL.appending(path: "baseline.sqlite").path
        let workingDatabase = try makePreparedDatabase(path: workingDatabasePath)
        let baselineDatabase = try makePreparedDatabase(path: baselineDatabasePath)
        let sourceEditingSession = try SourceEditingSession(
            workingDatabasePath: workingDatabasePath,
            baselineDatabasePath: baselineDatabasePath
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

        try await seedTeamWorkspaceEditorSummaryRows(
            database: workingDatabase,
            organizerID: organizerID,
            calendarID: calendarID,
            eventID: eventID,
            contributorID: contributorID,
            sourceBaseline: sourceBaseline
        )
        try await seedTeamWorkspaceEditorSummaryRows(
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
                UPDATE "contributors"
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

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = sourceEditingSession.database
            $0.sourceEditingSession = sourceEditingSession
        } operation: {
            TestStore(
                initialState: TeamWorkspaceEditor.State(
                    sourceBaselineID: sourceBaseline.id,
                    calendarID: calendarID
                )
            ) {
                TeamWorkspaceEditor()
            }
        }

        expectNoDifference(store.state.fetchLoadFailures.map(\.label), [])
        #expect(store.state.editSummary.availability == .available)
        #expect(store.state.editSummary.totalCount == 1)

        let contributorsGroup = try #require(
            store.state.editSummary.groups.first { $0.id == "contributors" }
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
    func createEventButtonPresentsWorkspaceCreateEvent() throws {
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
                initialState: TeamWorkspaceEditor.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            ) {
                TeamWorkspaceEditor()
            }
        }

        store.send(.createEventButtonTapped)

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
        #expect(eventYML.contains("performances:"))
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

private func seedTeamWorkspaceEditorSummaryRows(
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

private actor SourceEditPreparationRecorder {
    private var values: [SourceBaselineRecord.ID] = []

    var sourceBaselineIDs: [SourceBaselineRecord.ID] {
        values
    }

    func record(_ sourceBaselineID: SourceBaselineRecord.ID) {
        values.append(sourceBaselineID)
    }
}

private struct TeamWorkspaceEditorPatchFailure: Error {}

@Feature
private struct TeamWorkspaceEditorErrorHost {
    struct State {
        init(
            sourceBaselineID: SourceBaselineRecord.ID,
            calendarID: OMERecord.Calendar.ID
        ) {
            teamWorkspaceEditor = Spawn(
                TeamWorkspaceEditor.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            )
        }

        var errorNotifications = Spawn(ErrorNotifications.State())
        var teamWorkspaceEditor: Spawn<TeamWorkspaceEditor>
    }

    enum Action {}

    var body: some Feature {
        Update { _, _ in }
            .spawn(\.teamWorkspaceEditor) {
                TeamWorkspaceEditor()
            }
            .spawn(\.errorNotifications) {
                ErrorNotifications()
            }
            .onEvent(ErrorReported.self) { error, state in
                state.errorNotifications.state.report(error)
            }
    }
}
