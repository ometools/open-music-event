import ComposableArchitecture2
import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import OpenMusicEventApp

@MainActor
@Suite(.tcaExhaustivity(.off))
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
    func rejectsMissingStartDate() {
        let store = TestStore(
            initialState: makeState {
                $0.eventName = "Testival"
                $0.hasStartDate = false
            }
        ) {
            CreateEvent()
        }

        store.send(.saveButtonTapped) {
            $0.errorMessage = "Choose a start date."
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
        let schedules = try await database.read { db in
            try OMERecord.Schedule.fetchAll(db)
        }
        let eventOrganizerCount = try await database.read { db in
            try OMERecord.EventOrganizer.fetchCount(db)
        }
        #expect(events.count == 1)
        #expect(organizers.count == 1)
        #expect(schedules.count == 1)
        #expect(eventOrganizerCount == 0)

        let event = try #require(events.first)
        let organizer = try #require(organizers.first)
        let schedule = try #require(schedules.first)
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
        #expect(schedule.id.organizerID == event.id.organizerID)
        #expect(schedule.id.eventID == event.id.eventID)
        #expect(schedule.id.scheduleID == OMERecord.Schedule.singletonID)
        #expect(schedule.date == event.startDate)
        #expect(schedule.startsAt == nil)
        #expect(schedule.endsAt == nil)
        #expect(schedule.customTitle == nil)
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

        await store.send(.saveButtonTapped)?.value

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
        uuid: UUID = UUID(0),
        updateDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStore<CreateEvent> {
        withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
            $0.uuid = .constant(uuid)
            updateDependencies(&$0)
        } operation: {
            TestStore(initialState: initialState) {
                CreateEvent()
            }
        }
    }

    private func makeState(
        organizerID: OMERecord.Organizer.ID? = nil,
        eventOrganizerID: OMERecord.Organizer.ID? = nil,
        _ update: (inout CreateEvent.State) -> Void
    ) -> CreateEvent.State {
        withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        } operation: {
            var state = CreateEvent.State(
                organizerID: organizerID,
                eventOrganizerID: eventOrganizerID
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

}
