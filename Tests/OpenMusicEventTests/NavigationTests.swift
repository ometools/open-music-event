import ComposableArchitecture2
import Dependencies
import DebugSnapshots
import Foundation
import SQLiteData
import Testing

@testable import OpenMusicEvent
@testable import OpenMusicEventAppEventViewer

@MainActor
struct NavigationTests {
    @Test(
        arguments: [
            (
                "https://openmusicevent.app/events/event-1",
                AppRoute.event(.init(.init("event-1")), nil)
            ),
            (
                "https://openmusicevent.app/events/event-1/schedule",
                AppRoute.event(.init(.init("event-1")), .schedule)
            ),
            (
                "https://openmusicevent.app/events/event-1/participants/artist-1",
                AppRoute.event(.init(.init("event-1")), .participant(.init(.init("artist-1"))))
            ),
            (
                "https://openmusicevent.app/events/event-1/stages/stage-1",
                AppRoute.event(.init(.init("event-1")), .stage(.init(.init("stage-1"))))
            ),
        ]
    )
    func appRouteRoundTrips(urlString: String, expected: AppRoute) throws {
        let url = try #require(URL(string: urlString))
        let route = try #require(AppRoute(url: url))

        #expect(route == expected)
        #expect(route.path == url.path)
    }

    @Test
    func navigationRequestSelectsEventAndMountsViewer() async throws {
        let database = try makePreparedDatabase()
        let eventID = OMERecord.Event.ID(.init("event-1"))
        let store = makeRootHarnessStore(database: database, eventID: eventID)

        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            store.send(.root(.handleNavigationRequest(.event(eventID, nil))))
        }

        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }
        #expect(appState?.selectedEventID == eventID)
        #expect(store.state.root.eventViewer?.eventID == eventID)
    }

    @Test
    func navigationRequestSelectsParticipantSearchDestination() throws {
        let database = try makePreparedDatabase()
        let eventID = OMERecord.Event.ID(.init("event-1"))
        let participantID = OMERecord.Participant.ID(.init("participant-1"))
        let store = makeRootHarnessStore(database: database, eventID: eventID)

        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            store.send(.root(.handleNavigationRequest(.event(eventID, .participant(participantID)))))
        }

        #expect(store.state.root.eventViewer?.selectedFeature == .search)
        #expect(
            store.state.root.eventViewer?.eventSearch.destination?.participantDetail?.participantID == participantID
        )
    }

    @Test
    func navigationRequestSelectsStageSearchDestination() throws {
        let database = try makePreparedDatabase()
        let eventID = OMERecord.Event.ID(.init("event-1"))
        let stageID = OMERecord.Stage.ID(.init("stage-1"))
        let store = makeRootHarnessStore(database: database, eventID: eventID)

        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            store.send(.root(.handleNavigationRequest(.event(eventID, .stage(stageID)))))
        }

        #expect(store.state.root.eventViewer?.selectedFeature == .search)
        #expect(
            store.state.root.eventViewer?.eventSearch.destination?.stageDetail?.stageID == stageID
        )
    }

    @Test
    func eventViewerConsumesParticipantNavigationFromSearchDescendant() async throws {
        let participantID = OMERecord.Participant.ID(.init("participant-1"))
        let store = try makeEventViewerHarnessStore()

        await store.send(to: \.eventViewer.eventSearch, .openParticipant(participantID))?.value
        await Task.yield()

        #expect(store.state.eventViewer.selectedFeature == .search)
        #expect(
            store.state.eventViewer.eventSearch.destination?.participantDetail?.participantID == participantID
        )
        #expect(store.state.lastRequest == nil)
    }

    @Test
    func eventViewerConsumesStageNavigationFromSearchDescendant() async throws {
        let stageID = OMERecord.Stage.ID(.init("stage-1"))
        let store = try makeEventViewerHarnessStore()

        await store.send(to: \.eventViewer.eventSearch, .openStage(stageID))?.value
        await Task.yield()

        #expect(store.state.eventViewer.selectedFeature == .search)
        #expect(
            store.state.eventViewer.eventSearch.destination?.stageDetail?.stageID == stageID
        )
        #expect(store.state.lastRequest == nil)
    }

    @Test
    func myEventsPostsNavigationRequest() async throws {
        let database = try makePreparedDatabase()
        let eventID = OMERecord.Event.ID(.init("event-1"))
        try await database.write { db in
            let eventDraft = CreateEvent.makeEventDraft(
                id: eventID,
                name: "Test Event",
                startDate: nil,
                endDate: nil
            )
            try OMERecord.Event.insert {
                eventDraft
            }
            .execute(db)
        }
        let events = try await database.read { db in
            try OMERecord.Event.fetchAll(db)
        }
        let event = try #require(events.first)

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: MyEventsEventHarness.State()) {
                MyEventsEventHarness()
            }
        }

        store.send(.myEvents(.didTapEvent(event))) {
            $0.lastRequest = .event(eventID, nil)
        }
        #expect(store.state.lastRequest == .event(eventID, nil))
    }

    @Test
    func dismissClearsSelectedEvent() async throws {
        let eventID = OMERecord.Event.ID(.init("event-1"))
        let database = try makePreparedDatabase()
        try await database.write { db in
            try AppState.update {
                $0.selectedEventID = #bind(eventID)
            }
            .execute(db)
        }

        let store = makeRootHarnessStore(database: database, eventID: eventID)
        #expect(store.state.root.eventViewer?.eventID == eventID)

        store.send(.root(.eventViewerDismissed))

        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }
        #expect(appState?.selectedEventID == nil)
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

    private func makeRootHarnessStore(
        database: any DatabaseWriter,
        eventID: OMERecord.Event.ID = .init(.init("event-1"))
    ) -> TestStore<RootHarness> {
        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            TestStore(initialState: RootHarness.State()) {
                RootHarness()
            }
        }
    }

    private func makeEventViewerHarnessStore(
        eventID: OMERecord.Event.ID = .init(.init("event-1"))
    ) throws -> TestStore<EventViewerHarness> {
        let database = try makePreparedDatabase()
        return withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            TestStore(initialState: EventViewerHarness.State(eventID: eventID)) {
                EventViewerHarness()
            }
        }
    }
}

@Feature
private struct RootHarness {
    struct State {
        @DebugSnapshotIgnored
        var root = OpenMusicEventAppRoot.State()
    }

    enum Action {
        case root(OpenMusicEventAppRoot.Action)
    }

    var body: some Feature {
        Scope(state: \.root, action: \.root) {
            OpenMusicEventAppRoot()
        }
    }
}

@Feature
private struct MyEventsEventHarness {
    struct State {
        var lastRequest: NavigationRequest?
        var myEvents = MyEvents.State()
    }

    enum Action {
        case myEvents(MyEvents.Action)
    }

    var body: some Feature {
        Scope(state: \.myEvents, action: \.myEvents) {
            MyEvents()
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}

@Feature
private struct EventViewerHarness {
    struct State {
        init(eventID: OMERecord.Event.ID = .init(.init("event-1"))) {
            self.eventViewer = EventViewer.State.route(
                eventID: eventID,
                target: nil
            )
        }

        var lastRequest: NavigationRequest?
        @DebugSnapshotIgnored
        var eventViewer: EventViewer.State
    }

    enum Action {
        case eventViewer(EventViewer.Action)
    }

    var body: some Feature {
        Scope(state: \.eventViewer, action: \.eventViewer) {
            EventViewer()
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}
