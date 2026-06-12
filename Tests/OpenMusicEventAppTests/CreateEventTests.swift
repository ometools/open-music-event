import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventSourceEditing
import SQLiteData
import Testing

@testable import OpenMusicEventApp

@MainActor
struct CreateEventTests {
    @Test
    func rejectsWhitespaceOnlyNames() {
        let store = TestStore(
            initialState: makeState {
                $0.eventName = "   "
            }
        ) {
            CreateEvent()
        }

        store.send(.saveButtonTapped) {
            $0.errorMessage = "Enter an event name."
        }
    }

    @Test
    func rejectsInvalidDateRange() {
        let store = TestStore(
            initialState: makeState {
                $0.eventName = "Testival"
                $0.hasStartDate = true
                $0.startDateSelection = makeLocalDate(year: 1970, month: 1, day: 2)
                $0.hasEndDate = true
                $0.endDateSelection = makeLocalDate(year: 1970, month: 1, day: 1)
            }
        ) {
            CreateEvent()
        }

        store.send(.saveButtonTapped) {
            $0.errorMessage = "End date must be on or after the start date."
        }
    }

    @Test
    func savesMinimalEvent() async throws {
        let database = try makePreparedDatabase()
        let store = makeStore(
            initialState: makeState {
                $0.eventName = "Testival 2026"
                $0.hasStartDate = true
                $0.startDateSelection = makeLocalDate(year: 1970, month: 1, day: 2)
                $0.hasEndDate = true
                $0.endDateSelection = makeLocalDate(year: 1970, month: 1, day: 3)
            },
            database: database,
            uuid: UUID(1)
        )

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let events = try await database.read { db in
            try OMERecord.Event.fetchAll(db)
        }
        let organizers = try await database.read { db in
            try OMERecord.Organizer.fetchAll(db)
        }
        let eventOrganizerCount = try await database.read { db in
            try OMERecord.EventOrganizer.fetchCount(db)
        }
        #expect(events.count == 1)
        #expect(organizers.count == 1)
        #expect(eventOrganizerCount == 0)

        let event = try #require(events.first)
        let organizer = try #require(organizers.first)
        let organizerID = OMERecord.Organizer.ID("did:web:local.openmusicevent")!
        #expect(organizer.id == organizerID)
        #expect(event.id.organizerID == organizerID)
        #expect(event.id.eventID.rawValue.rawValue == UUID(1).uuidString.lowercased())
        #expect(event.name == "Testival 2026")
        #expect(event.startDate == LocalDate(year: 1970, month: 1, day: 2))
        #expect(event.endDate == LocalDate(year: 1970, month: 1, day: 3))
        #expect(event.status == .known(.planned))
        #expect(event.mode == .known(.inPerson))
        #expect(event.timeZone.identifier == TimeZone.current.identifier)
        #expect(event.description == nil)
        #expect(event.locations == nil)
        #expect(event.uris == nil)
        #expect(event.imageURL == nil)
        #expect(event.iconImageURL == nil)
        #expect(event.siteMapImageURL == nil)
        #expect(event.contactNumbers == nil)
        #expect(event.categoryConfigs == nil)
    }

    @Test
    func savesOrganizerScopedEvent() async throws {
        let database = try makePreparedDatabase()
        let organizerID = OMERecord.Organizer.ID("did:web:wickedwoods.example")!
        let store = makeStore(
            initialState: makeState(
                organizerID: organizerID,
                eventOrganizerID: organizerID
            ) {
                $0.eventName = "Wicked Woods 2026"
            },
            database: database,
            uuid: UUID(2)
        )

        await store.send(.saveButtonTapped)?.value

        let events = try await database.read { db in
            try OMERecord.Event.fetchAll(db)
        }
        let eventOrganizers = try await database.read { db in
            try OMERecord.EventOrganizer.fetchAll(db)
        }
        let organizers = try await database.read { db in
            try OMERecord.Organizer.fetchAll(db)
        }
        let event = try #require(events.first)
        let eventOrganizer = try #require(eventOrganizers.first)

        #expect(store.isPresented == false)
        #expect(events.count == 1)
        #expect(eventOrganizers.count == 1)
        #expect(organizers.map(\.id) == [organizerID])
        #expect(event.id.organizerID == organizerID)
        #expect(event.id.eventID.rawValue.rawValue == UUID(2).uuidString.lowercased())
        #expect(event.name == "Wicked Woods 2026")
        #expect(eventOrganizer.id.organizerID == event.id.organizerID)
        #expect(eventOrganizer.id.eventID == event.id.eventID)
        #expect(eventOrganizer.id.eventOrganizerID == organizerID)
    }

    @Test
    func savesSourceBackedWickedWoods2026Event() async throws {
        let database = try makePreparedDatabase()
        let organizerID = OMERecord.Organizer.ID("did:web:wickedwoods.example")!
        let sourceProvenance = makeSourceProvenance()
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
        try await seedSourceBackedCreateDefaults(
            database: database,
            organizerID: organizerID,
            calendarID: calendarID,
            sourceBaseline: sourceBaseline
        )
        let store = makeStore(
            initialState: makeState(
                organizerID: organizerID,
                eventOrganizerID: organizerID,
                sourceContext: CreateEvent.State.SourceContext(
                    sourceBaseline: sourceBaseline,
                    calendarID: calendarID,
                    sourceEventDirectory: " 2026 "
                )
            ) {
                $0.eventName = "Wicked Woods 2026"
                $0.timeZone = TimeZone(identifier: "America/Denver")!
            },
            database: database,
            uuid: UUID(99)
        )

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

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
        #expect(rows.organizers.map(\.id) == [organizerID])
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
    }

    @Test
    func rejectsInvalidSourceSlugsBeforeWritingEventRows() async throws {
        let invalidCases = [
            (" ", "Enter a source slug."),
            (".", "Use a single source slug like 2026-pre-party-kelowna."),
            ("..", "Use a single source slug like 2026-pre-party-kelowna."),
            ("events/2026", "Use a single source slug like 2026-pre-party-kelowna."),
            (#"events\2026"#, "Use a single source slug like 2026-pre-party-kelowna."),
        ]

        for (sourceEventDirectory, expectedMessage) in invalidCases {
            let database = try makePreparedDatabase()
            let organizerID = OMERecord.Organizer.ID("did:web:wickedwoods.example")!
            let sourceBaseline = SourceBaselineRecord(
                source: makeSourceProvenance(reference: "/tmp/wicked-woods-\(UUID().uuidString)"),
                databaseFileName: "baseline.sqlite",
                importedAt: Date(timeIntervalSince1970: 1)
            )
            let calendarID = OMERecord.Calendar.ID(
                ownerID: organizerID,
                calendarID: OMERecord.Calendar.defaultID
            )
            let store = makeStore(
                initialState: makeState(
                    organizerID: organizerID,
                    eventOrganizerID: organizerID,
                    sourceContext: CreateEvent.State.SourceContext(
                        sourceBaseline: sourceBaseline,
                        calendarID: calendarID,
                        sourceEventDirectory: sourceEventDirectory
                    )
                ) {
                    $0.eventName = "Wicked Woods 2026"
                },
                database: database
            )

            store.send(.saveButtonTapped) {
                $0.errorMessage = expectedMessage
            }

            let eventCount = try await database.read { db in
                try OMERecord.Event.fetchCount(db)
            }
            #expect(eventCount == 0)
        }
    }

    @Test
    func rejectsDuplicateSourceDirectoryBeforeWritingNewEventRows() async throws {
        let database = try makePreparedDatabase()
        let organizerID = OMERecord.Organizer.ID("did:web:wickedwoods.example")!
        let sourceProvenance = makeSourceProvenance()
        let sourceBaseline = SourceBaselineRecord(
            source: sourceProvenance,
            databaseFileName: "baseline.sqlite",
            importedAt: Date(timeIntervalSince1970: 1)
        )
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let existingEventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: OMERecord.SourceDatabaseInsertion.inferredEventID(
                eventDirectoryName: "2026",
                sourceProvenance: sourceProvenance
            )
        )
        try await seedSourceBackedCreateDefaults(
            database: database,
            organizerID: organizerID,
            calendarID: calendarID,
            sourceBaseline: sourceBaseline
        )
        try await database.write { db in
            try OMERecord.Event.insert {
                OMERecord.Event.Draft(
                    id: existingEventID,
                    name: "Existing Wicked Woods 2026",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: .known(.planned),
                    mode: .known(.inPerson),
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone(identifier: "America/Denver")!,
                    imageURL: nil,
                    iconImageURL: nil,
                    siteMapImageURL: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: existingEventID,
                    sourceBaselineID: sourceBaseline.id,
                    sourceKind: sourceProvenance.kind,
                    sourceReference: sourceProvenance.reference,
                    ref: sourceProvenance.ref,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "2026"
                )
            }
            .execute(db)
        }
        let store = makeStore(
            initialState: makeState(
                organizerID: organizerID,
                eventOrganizerID: organizerID,
                sourceContext: CreateEvent.State.SourceContext(
                    sourceBaseline: sourceBaseline,
                    calendarID: calendarID,
                    sourceEventDirectory: "2026"
                )
            ) {
                $0.eventName = "Replacement Wicked Woods 2026"
            },
            database: database
        )

        await store.send(.saveButtonTapped) {
            $0.errorMessage = "An event already uses that source slug."
        }?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == "An event already uses that source slug.")
        #expect(store.isPresented == true)

        let events = try await database.read { db in
            try OMERecord.Event.fetchAll(db)
        }
        let sourceProvenanceCount = try await database.read { db in
            try EventSourceProvenanceRecord.fetchCount(db)
        }
        let event = try #require(events.first)
        #expect(events.count == 1)
        #expect(event.id == existingEventID)
        #expect(event.name == "Existing Wicked Woods 2026")
        #expect(sourceProvenanceCount == 1)
    }

    @Test
    func surfacesSaveFailure() async throws {
        let database = try withDependencies {
            $0.context = .test
        } operation: {
            try SQLiteData.defaultDatabase()
        }
        let store = makeStore(
            initialState: makeState {
                $0.eventName = "Broken Event"
            },
            database: database
        )

        await store.send(.saveButtonTapped) {
            $0.isSaving = false
            $0.errorMessage = "Unable to create event."
        }?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == "Unable to create event.")
        #expect(store.isPresented == true)
    }

    private func makePreparedDatabase() throws -> any DatabaseWriter {
        try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            @Dependency(\.defaultDatabase) var database
            return database
        }
    }

    private func makeStore(
        initialState: CreateEvent.State = CreateEvent.State(),
        database: any DatabaseWriter,
        uuid: UUID = UUID(0)
    ) -> TestStore<CreateEvent> {
        withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
            $0.uuid = .constant(uuid)
        } operation: {
            TestStore(initialState: initialState) {
                CreateEvent()
            }
        }
    }

    private func makeState(
        organizerID: OMERecord.Organizer.ID? = nil,
        eventOrganizerID: OMERecord.Organizer.ID? = nil,
        sourceContext: CreateEvent.State.SourceContext? = nil,
        _ update: (inout CreateEvent.State) -> Void
    ) -> CreateEvent.State {
        withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        } operation: {
            var state = CreateEvent.State(
                organizerID: organizerID,
                eventOrganizerID: eventOrganizerID,
                sourceContext: sourceContext
            )
            update(&state)
            return state
        }
    }

    private func makeLocalDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func makeSourceProvenance(
        reference: String = "/tmp/wicked-woods-ome"
    ) -> OMERecord.SourceDatabaseInsertion.SourceProvenance {
        OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .local,
            reference: reference,
            ref: nil
        )
    }

    private func seedSourceBackedCreateDefaults(
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
}
