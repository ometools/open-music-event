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
struct SourceManagementTests {
    @Test
    func sourceManagementUsesOrganizerSourceScope() throws {
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
                initialState: SourceManagement.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            ) {
                SourceManagement()
            }
        }

        expectNoDifference(
            store.state.sourceChangesScope,
            .source(sourceBaselineID: sourceBaselineID, calendarID: calendarID)
        )
    }

    @Test
    func editEventUsesEventSourceScope() throws {
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
            EditEvent.State(eventID: eventID)
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
                initialState: SourceManagement.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            ) {
                SourceManagement()
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
            var state = SourceManagement.State(
                sourceBaselineID: sourceBaselineID,
                calendarID: calendarID
            )
            state.sourcePatchStatus = .generated(patch)
            return TestStore(initialState: state) {
                SourceManagement()
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
                    throw SourceManagementPatchFailure()
                }
        } operation: {
            TestStore(
                initialState: SourceManagementErrorHost.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            ) {
                SourceManagementErrorHost()
            }
        }

        await withIssueReporters([]) {
            await store.send(to: \.sourceManagement, .generateSourcePatchButtonTapped)?.value
        }

        guard case .failed = store.state.sourceManagement.state.sourcePatchStatus else {
            Issue.record("Expected source patch status to be failed.")
            return
        }
        let latestError = store.state.errorNotifications.state.latestError
        #expect(latestError?.kind == .unhandled)
        #expect(latestError?.message.fallback == "Unable to check source changes.")
        #expect(latestError?.operation == .sourcePatchGeneration)
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
                initialState: SourceManagement.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            ) {
                SourceManagement()
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
                calendarEntries: try OMERecord.CalendarEntry.fetchAll(db),
                sourceProvenances: try EventSourceProvenanceRecord.fetchAll(db)
            )
        }
        let event = try #require(rows.events.first)
        let eventOrganizer = try #require(rows.eventOrganizers.first)
        let calendarEntry = try #require(rows.calendarEntries.first)
        let sourceProvenanceRecord = try #require(rows.sourceProvenances.first)

        #expect(rows.events.count == 1)
        expectNoDifference(rows.organizers.map(\.id), [organizerID])
        #expect(rows.eventOrganizers.count == 1)
        #expect(rows.calendarEntries.count == 1)
        #expect(rows.sourceProvenances.count == 1)
        #expect(event.id == expectedEventID)
        #expect(event.name == "Wicked Woods 2026")
        #expect(event.timeZone.identifier == "America/Denver")
        #expect(eventOrganizer.id.organizerID == expectedEventID.organizerID)
        #expect(eventOrganizer.id.eventID == expectedEventID.eventID)
        #expect(eventOrganizer.id.eventOrganizerID == organizerID)
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

        let eventYMLURL = repositoryURL
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "2026", directoryHint: .isDirectory)
            .appending(path: "event.yml")
        let eventYML = try String(contentsOf: eventYMLURL, encoding: .utf8)
        #expect(eventYML.contains("name: Wicked Woods 2026"))
        #expect(eventYML.contains("timeZone: America/Denver"))
        #expect(!eventYML.contains("id:"))
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
                    SourceManagementCreateEvent()
                }
            }

            store.send(.saveButtonTapped) {
                $0.errorMessage = expectedMessage
            }
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

private func makePreparedDatabase() throws -> any DatabaseWriter {
    try withDependencies {
        $0.context = .test
    } operation: {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OMERecord.DatabaseMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }
}

@MainActor
private func makeCreateEventStore(
    initialState: SourceManagementCreateEvent.State,
    database: any DatabaseWriter,
    updateDependencies: (inout DependencyValues) -> Void = { _ in }
) -> TestStore<SourceManagementCreateEvent> {
    withDependencies {
        $0.context = .test
        $0.date = .constant(Date(timeIntervalSince1970: 0))
        $0.defaultDatabase = database
        updateDependencies(&$0)
    } operation: {
        TestStore(initialState: initialState) {
            SourceManagementCreateEvent()
        }
    }
}

private func makeCreateEventState(
    sourceBaselineID: SourceBaselineRecord.ID,
    calendarID: OMERecord.Calendar.ID
) -> SourceManagementCreateEvent.State {
    withDependencies {
        $0.context = .test
        $0.date = .constant(Date(timeIntervalSince1970: 0))
    } operation: {
        SourceManagementCreateEvent.State(
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

private actor SourceEditPreparationRecorder {
    private var values: [SourceBaselineRecord.ID] = []

    var sourceBaselineIDs: [SourceBaselineRecord.ID] {
        values
    }

    func record(_ sourceBaselineID: SourceBaselineRecord.ID) {
        values.append(sourceBaselineID)
    }
}

private struct SourceManagementPatchFailure: Error {}

@Feature
private struct SourceManagementErrorHost {
    struct State {
        init(
            sourceBaselineID: SourceBaselineRecord.ID,
            calendarID: OMERecord.Calendar.ID
        ) {
            sourceManagement = Spawn(
                SourceManagement.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            )
        }

        var errorNotifications = Spawn(ErrorNotifications.State())
        var sourceManagement: Spawn<SourceManagement>
    }

    enum Action {}

    var body: some Feature {
        Update { _, _ in }
            .spawn(\.sourceManagement) {
                SourceManagement()
            }
            .spawn(\.errorNotifications) {
                ErrorNotifications()
            }
            .onEvent(ErrorReported.self) { error, state in
                state.errorNotifications.state.report(error)
            }
    }
}
