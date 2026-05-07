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
    func savesMinimalEvent() async throws {
        let database = try makePreparedDatabase()
        let store = makeStore(
            initialState: makeState {
                $0.eventName = "Testival 2026"
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
        #expect(events.count == 1)

        let event = try #require(events.first)
        #expect(event.id.rawValue.rawValue == UUID(1).uuidString.lowercased())
        #expect(event.name == "Testival 2026")
        #expect(event.startDate == nil)
        #expect(event.endDate == nil)
        #expect(event.status == .planned)
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
            $0.defaultDatabase = database
            $0.uuid = .constant(uuid)
        } operation: {
            TestStore(initialState: initialState) {
                CreateEvent()
            }
        }
    }

    private func makeState(
        _ update: (inout CreateEvent.State) -> Void
    ) -> CreateEvent.State {
        withDependencies {
            $0.context = .test
        } operation: {
            var state = CreateEvent.State()
            update(&state)
            return state
        }
    }
}
