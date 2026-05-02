import ComposableArchitecture2
import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import OpenMusicEvent

@MainActor
struct CreateEventTests {
    @Test
    func rejectsWhitespaceOnlyNames() {
        let store = TestStore(
            initialState: CreateEvent.State(eventName: "   ")
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
            initialState: CreateEvent.State(
                eventName: "Testival",
                hasStartDate: true,
                startDate: Date(timeIntervalSince1970: 86_400),
                hasEndDate: true,
                endDate: .init(timeIntervalSince1970: 0)
            )
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
            initialState: CreateEvent.State(
                eventName: "Testival 2026",
                hasStartDate: true,
                startDate: Date(timeIntervalSince1970: 86_400),
                hasEndDate: true,
                endDate: Date(timeIntervalSince1970: 172_800)
            ),
            database: database,
            uuid: UUID(1)
        )

        store.send(.saveButtonTapped) {
            $0.isSaving = true
        }
        await store.receive(\.saveSucceeded) {
            $0.didCreateEvent = true
            $0.isSaving = false
        }

        let events = try database.read { db in
            try OMERecord.Event.fetchAll(db)
        }
        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.id.rawValue.rawValue == UUID(1).uuidString.lowercased())
        #expect(event.name == "Testival 2026")
        #expect(event.startsAt == Date(timeIntervalSince1970: 86_400))
        #expect(event.endsAt == Date(timeIntervalSince1970: 172_800))
        #expect(event.status == .planned)
        #expect(event.mode == .known(.inPerson))
        #expect(event.timeZone == TimeZone.current.identifier)
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
    func surfacesSaveFailure() async throws {
        let database = try withDependencies {
            $0.context = .test
        } operation: {
            try SQLiteData.defaultDatabase()
        }
        let store = makeStore(
            initialState: CreateEvent.State(eventName: "Broken Event"),
            database: database
        )

        store.send(.saveButtonTapped) {
            $0.isSaving = true
        }
        await store.receive(\.saveFailed)

        #expect(store.state.isSaving == false)
        #expect(store.state.didCreateEvent == false)
        #expect(store.state.errorMessage?.isEmpty == false)
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
            $0.defaultDatabase = database
            $0.uuid = .constant(uuid)
        } operation: {
            TestStore(initialState: initialState) {
                CreateEvent()
            }
        }
    }
}
