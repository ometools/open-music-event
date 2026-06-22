import BlueskyActorCache
import ATProto
import Clocks
import ComposableArchitecture2
import CustomDump
import Dependencies
import DebugSnapshots
import Foundation
import Observation
import OpenMusicEventDatabase
import OpenMusicEventAuthentication
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
import SwiftUI
import Testing
import XRPCClient

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

private let testOrganizerID = OMERecord.Organizer.ID("did:web:example.com")!

private func eventID(_ string: String) -> OMERecord.Event.ID {
    OMERecord.Event.ID(
        organizerID: testOrganizerID,
        eventID: eventLocalID(string)
    )
}

private func eventLocalID(_ string: String) -> OMERecord.ID<OMERecord.Event> {
    OMERecord.ID<OMERecord.Event>(rawValue: ATProto.Record.Key(rawValue: string))
}

private func calendarLocalID(_ string: String) -> OMERecord.ID<OMERecord.Calendar> {
    OMERecord.ID<OMERecord.Calendar>(rawValue: ATProto.Record.Key(rawValue: string))
}

private func calendarEntryLocalID(_ string: String) -> OMERecord.ID<OMERecord.CalendarEntry> {
    OMERecord.ID<OMERecord.CalendarEntry>(rawValue: ATProto.Record.Key(rawValue: string))
}

private func sourceProvenance(
    _ source: String,
    ref: String? = "HEAD"
) -> OMERecord.SourceDatabaseInsertion.SourceProvenance {
    OMERecord.SourceDatabaseInsertion.SourceProvenance(
        kind: .tangled,
        reference: "tangled.org/woody.fm/\(source)",
        ref: ref
    )
}

private func contributorLocalID(_ string: String) -> OMERecord.ID<OMERecord.Contributor> {
    OMERecord.ID<OMERecord.Contributor>(rawValue: ATProto.Record.Key(rawValue: string))
}

private func performanceLocalID(_ string: String) -> OMERecord.ID<OMERecord.Performance> {
    OMERecord.ID<OMERecord.Performance>(rawValue: ATProto.Record.Key(rawValue: string))
}

private func scheduleLocalID(_ string: String) -> OMERecord.ID<OMERecord.Schedule> {
    OMERecord.ID<OMERecord.Schedule>(rawValue: ATProto.Record.Key(rawValue: string))
}

private func stageLocalID(_ string: String) -> OMERecord.ID<OMERecord.Stage> {
    OMERecord.ID<OMERecord.Stage>(rawValue: ATProto.Record.Key(rawValue: string))
}

private actor ObservationRecorder<Value: Sendable> {
    private var recordedValues: [Value] = []

    var values: [Value] {
        recordedValues
    }

    func record(_ value: Value) {
        recordedValues.append(value)
    }
}

private actor BlueskyProfileRequestRecorder {
    private var recordedActors: [String] = []

    var actors: [String] {
        recordedActors
    }

    func record(_ actor: String) {
        recordedActors.append(actor)
    }
}

private actor SourceRefreshRecorder {
    private var recordedSourceBaselineIDs: [SourceBaselineRecord.ID] = []

    var sourceBaselineIDs: [SourceBaselineRecord.ID] {
        recordedSourceBaselineIDs
    }

    func record(_ sourceBaselineID: SourceBaselineRecord.ID) {
        recordedSourceBaselineIDs.append(sourceBaselineID)
    }
}

private actor SourceEditModePreparationRecorder {
    private var recordedSourceBaselineIDs: [SourceBaselineRecord.ID] = []

    var sourceBaselineIDs: [SourceBaselineRecord.ID] {
        recordedSourceBaselineIDs
    }

    func record(_ sourceBaselineID: SourceBaselineRecord.ID) {
        recordedSourceBaselineIDs.append(sourceBaselineID)
    }
}

@MainActor
@Suite(.tcaExhaustivity(.off))
struct NavigationTests {
    @Test(
        arguments: [
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1",
                AppRoute.event(eventID("event-1"), nil)
            ),
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/schedule",
                AppRoute.event(eventID("event-1"), .schedule)
            ),
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/contributors",
                AppRoute.event(eventID("event-1"), .contributors)
            ),
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/contributors/artist-1",
                AppRoute.event(eventID("event-1"), .contributor(contributorLocalID("artist-1")))
            ),
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/stages",
                AppRoute.event(eventID("event-1"), .stages)
            ),
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/stages/stage-1",
                AppRoute.event(eventID("event-1"), .stage(stageLocalID("stage-1")))
            ),
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/edit",
                AppRoute.event(eventID("event-1"), .edit)
            ),
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/settings",
                AppRoute.event(eventID("event-1"), .settings)
            ),
        ]
    )
    func appRouteRoundTrips(urlString: String, expected: AppRoute) throws {
        let url = try #require(URL(string: urlString))
        let route = try #require(AppRoute(url: url))

        #expect(route == expected)
        #expect(route.path == url.path(percentEncoded: true))
    }

    @Test(
        arguments: [
            "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/people",
            "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/participants/artist-1",
        ]
    )
    func appRouteRejectsOldContributorURLs(urlString: String) throws {
        let url = try #require(URL(string: urlString))
        #expect(AppRoute(url: url) == nil)
    }

    @Test
    func navigationRequestSelectsEventAndMountsViewer() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
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
        #expect(store.state.root.eventViewer?.state.eventID == eventID)
    }

    @Test
    func navigationRequestSelectsContributorContributorsDestination() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("contributor-1")
        let store = makeRootHarnessStore(database: database, eventID: eventID)

        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            store.send(.root(.handleNavigationRequest(.event(eventID, .contributor(contributorID)))))
        }

        #expect(store.state.root.eventViewer?.state.selectedFeature == .contributors)
        #expect(
            store.state.root.eventViewer?.state.contributorsViewer?.destination?.contributorDetail?.contributorID == contributorID
        )
    }

    @Test
    func navigationRequestSelectsStageDestination() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let stageID = stageLocalID("stage-1")
        let store = makeRootHarnessStore(database: database, eventID: eventID)

        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            store.send(.root(.handleNavigationRequest(.event(eventID, .stage(stageID)))))
        }

        #expect(store.state.root.eventViewer?.state.selectedFeature == .stages)
        #expect(
            store.state.root.eventViewer?.state.stagesViewer?.destination?.stageDetail?.stageID == stageID
        )
    }

    @Test
    func navigationRequestSelectsEditEventFeature() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let store = makeRootHarnessStore(database: database, eventID: eventID)

        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            store.send(.root(.handleNavigationRequest(.event(eventID, .edit))))
        }

        #expect(store.state.root.eventViewer?.state.selectedFeature == .edit)
        #expect(store.state.root.eventViewer?.state.editEvent?.eventID == eventID)
    }

    @Test
    func eventViewerConsumesContributorNavigationFromSearchDescendant() async throws {
        let contributorID = contributorLocalID("contributor-1")
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let store = try makeEventViewerHarnessStore(database: database)

        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            await store.send(
                to: \.eventViewer.eventSearch,
                EventSearch.Action.openTarget(.contributor(contributorID))
            )?.value
        }
        await Task.yield()

        #expect(
            store.state.eventViewer.eventSearch.state.destination?.contributorDetail?.state
                .contributorID == contributorID
        )
        #expect(store.state.lastRequest == nil)
    }

    @Test
    func eventViewerSearchUsesMountedEventIDForContributorNavigation() async throws {
        let selectedEventID = eventID("event-1")
        let ambientEventID = eventID("other-event")
        let contributorID = contributorLocalID("contributor-1")
        let database = try makePreparedDatabase()
        let store = try makeEventViewerHarnessStore(
            eventID: selectedEventID,
            defaultEventID: ambientEventID,
            database: database
        )

        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = ambientEventID
        } operation: {
            await store.send(
                to: \.eventViewer.eventSearch,
                EventSearch.Action.openTarget(.contributor(contributorID))
            )?.value
        }
        await Task.yield()

        #expect(
            store.state.eventViewer.eventSearch.state.destination?.contributorDetail?.state
                .eventID == selectedEventID
        )
    }

    @Test
    func eventViewerConsumesStageNavigationFromSearchDescendant() async throws {
        let stageID = stageLocalID("stage-1")
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let store = try makeEventViewerHarnessStore(database: database)

        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            await store.send(
                to: \.eventViewer.eventSearch,
                EventSearch.Action.openTarget(.stage(stageID))
            )?.value
        }
        await Task.yield()

        #expect(
            store.state.eventViewer.eventSearch.state.destination?.stageDetail?.state.stageID
                == stageID
        )
        #expect(store.state.lastRequest == nil)
    }

    @Test
    func myEventsPostsNavigationRequest() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        try await database.write { db in
            try OMERecord.Organizer.insert {
                OMERecord.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
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
    func myEventsDownloadedSourceTapPresentsSourceDetail() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("downloaded-event")
        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/woody.fm/wicked-woods-ome",
            ref: "HEAD"
        )
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        try database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Downloaded Event")
            try Self.insertEventOrganizer(db, eventID: eventID, organizerID: testOrganizerID)
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
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "downloaded-event"
                )
            }
            .execute(db)
        }
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: MyEventsEventHarness.State()) {
                MyEventsEventHarness()
            }
        }

        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            store.send(.myEvents(.didTapDownloadedSource(sourceBaselineID)))
        }
        #expect(store.state.myEvents.sourceDetail?.sourceBaselineID == sourceBaselineID)
    }

    @Test
    func sourceDetailLoadsLiveCalendarFromSourceProvenance() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("live-calendar-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let importedAt = Date(timeIntervalSince1970: 1_000)
        let calendarID = OrganizerDetail.defaultCalendarID(organizerID: testOrganizerID)
        let eventID = eventID("live-event")
        let entryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("live-event")
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Live Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: importedAt
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
            try Self.insertCalendar(
                db,
                id: calendarID,
                name: "Live Calendar",
                description: "Live calendar description"
            )
            try Self.insertCalendarEntry(
                db,
                id: entryID,
                event: OMERecord.Event.reference(id: eventID),
                createdAt: importedAt,
                note: "Live note",
                pinned: true
            )
        }

        let store = try makeSourceDetailStore(
            sourceBaselineID: sourceBaselineID,
            database: database
        )

        let displayEntries = SourceDetail.displayEntries(
            calendarEntries: store.state.calendarEntries,
            events: store.state.events,
            sourceBaseline: store.state.sourceBaseline
        )

        #expect(store.state.calendar?.name == "Live Calendar")
        #expect(store.state.calendar?.description == "Live calendar description")
        #expect(displayEntries.map(\.id) == [entryID])
        #expect(displayEntries.first?.note == "Live note")
        #expect(displayEntries.first?.pinned == true)
        #expect(store.state.events.map(\.name) == ["Live Event"])
    }

    @Test
    func sourceDetailEditCalendarPresentsLiveCalendarEditor() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("editable-live-calendar-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let calendarID = OrganizerDetail.defaultCalendarID(organizerID: testOrganizerID)
        let eventID = eventID("editable-live-event")

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Editable Live Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 1_500)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
            try Self.insertCalendar(db, id: calendarID, name: "Editable Live Calendar")
        }

        let store = try makeSourceDetailStore(
            sourceBaselineID: sourceBaselineID,
            database: database
        )

        store.send(.editButtonTapped)

        #expect(store.state.editCalendar?.calendarID == calendarID)
    }

    @Test
    func sourceDetailPreparesSourceForEditingBeforePresentingManagement() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("editable-source-management")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let calendarID = OrganizerDetail.defaultCalendarID(organizerID: testOrganizerID)
        let eventID = eventID("editable-source-management-event")
        let recorder = SourceEditModePreparationRecorder()

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Editable Source Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 1_600)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
            try Self.insertCalendar(db, id: calendarID, name: "Editable Source Calendar")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourceEditModePreparation = SourceEditModePreparationClient { sourceBaselineID in
                await recorder.record(sourceBaselineID)
            }
        } operation: {
            TestStore(initialState: SourceDetail.State(sourceBaselineID: sourceBaselineID)) {
                SourceDetail()
            }
        }

        let task = store.send(.manageSourceButtonTapped) {
            $0.isPreparingSourceManagement = true
        }
        await task?.value

        #expect(await recorder.sourceBaselineIDs == [sourceBaselineID])
        #expect(store.state.isPreparingSourceManagement == false)
        #expect(store.state.sourceManagement?.sourceBaselineID == sourceBaselineID)
        #expect(store.state.sourceManagement?.calendarID == calendarID)
    }

    @Test
    func sourceDetailRoutesPreparationAuthorizationThroughAppSheet() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("auth-source-management")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let calendarID = OrganizerDetail.defaultCalendarID(organizerID: testOrganizerID)
        let eventID = eventID("auth-source-management-event")
        let requirement = OpenMusicEventOAuth.tangledPublicKeyAuthRequirement
        let authorizationCenter = AuthorizationRequestCenter()

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Authorized Source Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 1_600)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
            try Self.insertCalendar(db, id: calendarID, name: "Authorized Source Calendar")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.openMusicEventAuthorizationRequests = OpenMusicEventAuthorizationRequests(
                center: authorizationCenter
            )
            $0.oauthAuthorizationBroker = authorizationCenter.broker
            $0.sourceEditModePreparation = SourceEditModePreparationClient { _ in
                @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
                try await authorizationBroker.authorize(requirement)
            }
        } operation: {
            TestStore(initialState: SourceDetail.State(sourceBaselineID: sourceBaselineID)) {
                SourceDetail()
            }
        }

        let task = store.send(.manageSourceButtonTapped) {
            $0.isPreparingSourceManagement = true
        }
        let requests = await authorizationCenter.requests()
        for await request in requests {
            guard let request else { continue }
            #expect(request.requirement == requirement)
            await authorizationCenter.succeed()
            break
        }
        await task?.value

        #expect(store.state.isPreparingSourceManagement == false)
        #expect(store.state.sourceManagement?.sourceBaselineID == sourceBaselineID)
        #expect(store.state.sourceManagement?.calendarID == calendarID)
    }

    @Test
    func sourceDetailScopesLiveCalendarEntriesToSourceProvenance() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("first-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let importedAt = Date(timeIntervalSince1970: 2_000)
        let firstEventID = eventID("first-source-event")
        let otherEventID = eventID("other-source-event")
        let calendarID = OrganizerDetail.defaultCalendarID(organizerID: testOrganizerID)

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: firstEventID, name: "First Source Event")
            try Self.insertEvent(db, id: otherEventID, name: "Other Source Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: importedAt
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: firstEventID,
                sourceProvenance: sourceProvenance
            )
            try Self.insertCalendar(db, id: calendarID, name: "Live Calendar")
            try Self.insertCalendarEntry(
                db,
                id: .init(
                    calendarOwnerID: testOrganizerID,
                    calendarID: OMERecord.Calendar.defaultID,
                    entryID: calendarEntryLocalID("first-source-event")
                ),
                event: OMERecord.Event.reference(id: firstEventID),
                createdAt: importedAt
            )
            try Self.insertCalendarEntry(
                db,
                id: .init(
                    calendarOwnerID: testOrganizerID,
                    calendarID: OMERecord.Calendar.defaultID,
                    entryID: calendarEntryLocalID("other-source-event")
                ),
                event: OMERecord.Event.reference(id: otherEventID),
                createdAt: Date(timeIntervalSince1970: 3_000)
            )
        }

        let store = try makeSourceDetailStore(
            sourceBaselineID: sourceBaselineID,
            database: database
        )
        let displayEntries = SourceDetail.displayEntries(
            calendarEntries: store.state.calendarEntries,
            events: store.state.events,
            sourceBaseline: store.state.sourceBaseline
        )

        #expect(store.state.calendar?.name == "Live Calendar")
        #expect(displayEntries.map(\.id.entryID) == [
            calendarEntryLocalID("first-source-event")
        ])
        #expect(store.state.events.map(\.id) == [firstEventID])
    }

    @Test
    func sourceDetailSynthesizesRowsFromProvenanceWhenLiveCalendarEntryIsMissing() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("missing-reference-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let importedAt = Date(timeIntervalSince1970: 4_000)
        let eventID = eventID("fallback-event")

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Fallback Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                databaseFileName: "missing-reference.sqlite",
                importedAt: importedAt
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
        }

        let store = try makeSourceDetailStore(
            sourceBaselineID: sourceBaselineID,
            database: database
        )
        let displayEntries = SourceDetail.displayEntries(
            calendarEntries: store.state.calendarEntries,
            events: store.state.events,
            sourceBaseline: store.state.sourceBaseline
        )

        #expect(store.state.calendar == nil)
        #expect(store.state.canEditCalendar == true)
        #expect(displayEntries.map(\.id.entryID) == [
            calendarEntryLocalID("fallback-event")
        ])
        #expect(displayEntries.first?.createdAt == importedAt)
        #expect(displayEntries.first?.pinned == false)
        #expect(store.state.events.map(\.id) == [eventID])

        store.send(.editButtonTapped)
        #expect(
            store.state.editCalendar?.calendarID
            == OrganizerDetail.defaultCalendarID(organizerID: testOrganizerID)
        )
    }

    @Test
    func sourceDetailEventTapPostsNavigationRequest() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("source-event")
        let sourceProvenance = sourceProvenance("navigation-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        try database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Source Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 0)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: SourceDetailHarness.State(sourceBaselineID: sourceBaselineID)
            ) {
                SourceDetailHarness()
            }
        }

        store.send(.sourceDetail(.eventButtonTapped(eventID))) {
            $0.lastRequest = .event(eventID, nil)
        }
        #expect(store.state.lastRequest == .event(eventID, nil))
    }

    @Test
    func eventInfoPullToRefreshPostsSourceDataRefreshRequest() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("refresh-source-event")
        let sourceProvenance = sourceProvenance("refresh-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Refresh Source Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 0)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EventInfoRefreshHarness.State(eventID: eventID)) {
                EventInfoRefreshHarness()
            }
        }

        await store.send(.eventInfo(.didPullToRefresh))?.value
        #expect(
            store.state.lastRefreshRequest == SourceDataRefreshRequest(
                eventID: eventID,
                sourceBaselineID: sourceBaselineID
            )
        )
    }

    @Test
    func eventInfoPullToRefreshNoOpsForNonSourceEvent() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("plain-event")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Plain Event")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EventInfoRefreshHarness.State(eventID: eventID)) {
                EventInfoRefreshHarness()
            }
        }

        await store.send(.eventInfo(.didPullToRefresh))?.value
        #expect(store.state.lastRefreshRequest == nil)
    }

    @Test
    func eventViewerRefreshesSourceDataFromAboutPull() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("viewer-refresh-event")
        let sourceProvenance = sourceProvenance("viewer-refresh-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let recorder = SourceRefreshRecorder()
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Viewer Refresh Event")
            try Self.insertEventOrganizer(db, eventID: eventID, organizerID: testOrganizerID)
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 0)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.sourceDataRefresh = SourceDataRefreshClient { sourceBaselineID in
                await recorder.record(sourceBaselineID)
            }
        } operation: {
            var initialState = EventViewerHarness.State(eventID: eventID)
            initialState.eventViewer.selectedFeature = .about
            return TestStore(initialState: initialState) {
                EventViewerHarness()
            }
        }

        await store.send(
            to: \EventViewerHarness.State.eventInfoViewer,
            EventInfoViewer.Action.didPullToRefresh
        )?.value
        #expect(await recorder.sourceBaselineIDs == [sourceBaselineID])
        #expect(store.state.eventViewer.selectedFeature == .about)
    }

    @Test
    func eventViewerRefreshesSourceDataFromSourceTabRefresh() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("viewer-source-refresh-event")
        let sourceProvenance = sourceProvenance("viewer-source-refresh-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let recorder = SourceRefreshRecorder()
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Viewer Source Refresh Event")
            try Self.insertEventOrganizer(db, eventID: eventID, organizerID: testOrganizerID)
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 0)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.sourceDataRefresh = SourceDataRefreshClient { sourceBaselineID in
                await recorder.record(sourceBaselineID)
            }
        } operation: {
            var initialState = EventViewerHarness.State(eventID: eventID)
            initialState.eventViewer.selectedFeature = .edit
            return TestStore(initialState: initialState) {
                EventViewerHarness()
            }
        }

        await store.send(
            to: \EventViewerHarness.State.editEvent,
            EditEvent.Action.refreshSourceButtonTapped
        )?.value
        let sourceBaselineIDs = await recorder.sourceBaselineIDs
        expectNoDifference(sourceBaselineIDs, [sourceBaselineID])
        expectNoDifference(store.state.eventViewer.selectedFeature, .edit)
    }

    @Test
    func eventViewerIgnoresSourceRefreshForDifferentEvent() async throws {
        let database = try makePreparedDatabase()
        let viewerEventID = eventID("viewer-refresh-event")
        let otherEventID = eventID("other-refresh-event")
        let sourceProvenance = sourceProvenance("other-refresh-source")
        let recorder = SourceRefreshRecorder()
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: viewerEventID, name: "Viewer Refresh Event")
            try Self.insertEvent(db, id: otherEventID, name: "Other Refresh Event")
            try Self.insertEventOrganizer(db, eventID: viewerEventID, organizerID: testOrganizerID)
            try Self.insertEventOrganizer(db, eventID: otherEventID, organizerID: testOrganizerID)
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 0)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: otherEventID,
                sourceProvenance: sourceProvenance
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = viewerEventID
            $0.sourceDataRefresh = SourceDataRefreshClient { sourceBaselineID in
                await recorder.record(sourceBaselineID)
            }
        } operation: {
            var initialState = EventViewerHarness.State(eventID: viewerEventID)
            initialState.eventViewer.eventInfoViewer?.state = EventInfoViewer.State(eventID: otherEventID)
            return TestStore(initialState: initialState) {
                EventViewerHarness()
            }
        }

        await store.send(
            to: \EventViewerHarness.State.eventInfoViewer,
            EventInfoViewer.Action.didPullToRefresh
        )?.value
        #expect(await recorder.sourceBaselineIDs == [])
    }

    @Test
    func organizerDetailFetchesLinkedEvents() async throws {
        let database = try makePreparedDatabase()
        let linkedEventID = eventID("linked-event")
        let unlinkedEventID = eventID("unlinked-event")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: linkedEventID, name: "Linked Event")
            try Self.insertEvent(db, id: unlinkedEventID, name: "Unlinked Event")
            try Self.insertEventOrganizer(db, eventID: linkedEventID, organizerID: testOrganizerID)
        }

        let events = try await database.read { db in
            try OrganizerDetail.eventsQuery(organizerID: testOrganizerID).fetchAll(db)
        }

        #expect(events.map(\.id) == [linkedEventID])
    }

    @Test
    func organizerDetailFetchesCalendarsForOrganizer() async throws {
        let database = try makePreparedDatabase()
        let otherOrganizerID = try #require(OMERecord.Organizer.ID("did:web:other.example"))
        let defaultCalendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let sideCalendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: calendarLocalID("side-room")
        )
        let otherCalendarID = OMERecord.Calendar.ID(
            ownerID: otherOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertOrganizer(db, id: otherOrganizerID)
            try Self.insertCalendar(db, id: sideCalendarID, name: "Side Room")
            try Self.insertCalendar(db, id: defaultCalendarID, name: "Main Calendar")
            try Self.insertCalendar(db, id: otherCalendarID, name: "Other Calendar")
        }

        let calendars = try await database.read { db in
            try OrganizerDetail.calendarsQuery(organizerID: testOrganizerID).fetchAll(db)
        }

        #expect(calendars.map(\.id) == [defaultCalendarID, sideCalendarID])
    }

    @Test
    func calendarDetailResolvesEntriesWithLocalEvents() async throws {
        let database = try makePreparedDatabase()
        let calendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let firstEventID = eventID("first-event")
        let pinnedEventID = eventID("pinned-event")
        let firstEventDate = try #require(LocalDate("2026-06-01"))
        let pinnedEventDate = try #require(LocalDate("2026-05-01"))
        let firstEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("first-entry")
        )
        let pinnedEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("pinned-entry")
        )
        let unavailableEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("unavailable-entry")
        )
        let unavailableEventRef = OMERecord.Event.Reference(
            uri: ATProto.URI(
                authority: .did(try #require(OMERecord.Organizer.ID("did:web:remote.example"))),
                collection: OMERecord.Event.nsid,
                rkey: "remote-event"
            )
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(
                db,
                id: firstEventID,
                name: "First Event",
                startDate: firstEventDate
            )
            try Self.insertEvent(
                db,
                id: pinnedEventID,
                name: "Pinned Event",
                startDate: pinnedEventDate
            )
            try Self.insertCalendar(db, id: calendarID, name: "Main Calendar")
            try Self.insertCalendarEntry(
                db,
                id: firstEntryID,
                event: OMERecord.Event.reference(id: firstEventID),
                createdAt: Date(timeIntervalSince1970: 100)
            )
            try Self.insertCalendarEntry(
                db,
                id: unavailableEntryID,
                event: unavailableEventRef,
                createdAt: Date(timeIntervalSince1970: 200)
            )
            try Self.insertCalendarEntry(
                db,
                id: pinnedEntryID,
                event: OMERecord.Event.reference(id: pinnedEventID),
                createdAt: Date(timeIntervalSince1970: 50),
                note: "Pinned pick",
                pinned: true
            )
        }

        let rows = try await database.read { db in
            CalendarDetail.EntryRows(
                entries: try CalendarDetail.entriesQuery(calendarID: calendarID).fetchAll(db),
                events: try CalendarDetail.localEventsQuery.fetchAll(db)
            )
        }

        #expect(rows.rows.map(\.entry.id) == [pinnedEntryID, firstEntryID, unavailableEntryID])
        #expect(rows.rows.map(\.event?.id) == [pinnedEventID, firstEventID, nil])
        #expect(rows.rows.first?.entry.note == "Pinned pick")
    }

    @Test
    func calendarDetailEditButtonPresentsEditor() throws {
        let database = try makePreparedDatabase()
        let calendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: CalendarDetail.State(calendarID: calendarID)) {
                CalendarDetail()
            }
        }

        store.send(.editButtonTapped)

        #expect(store.state.editCalendar?.calendarID == calendarID)
    }

    @Test
    func editCalendarSavesHeroAndLogoImages() async throws {
        let database = try makePreparedDatabase()
        let calendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let logoURL = try #require(URL(string: "https://example.com/logo.png"))
        let logoImage = OMERecord.ImageAsset(
            source: .url(logoURL),
            role: .logo,
            renderKind: .transparent,
            materializationPolicy: .lazy
        )
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertCalendar(
                db,
                id: calendarID,
                name: "Main Calendar",
                description: "Calendar description",
                images: [logoImage]
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            var state = EditCalendar.State(calendarID: calendarID)
            state.hasLoadedDraft = true
            state.draft = OMERecord.Calendar.Draft(
                id: calendarID,
                name: "Main Calendar",
                description: "Calendar description",
                images: [logoImage]
            )
            state.resetImagePickers()
            state.form.value.name = " Updated Calendar "
            state.form.value.description = " Updated description "
            state.heroImagePicker.replaceURLString(" https://example.com/hero.png ")

            return TestStore(initialState: state) {
                EditCalendar()
            }
        }

        let submitTask = store.send(.saveButtonTapped)
        let saveTask = await store.receive(
            \.formSubmitted,
            .equals(
                EditCalendar.FormValue(
                    name: " Updated Calendar ",
                    description: " Updated description "
                )
            ),
            timeout: .seconds(1)
        )
        await saveTask?.value
        await submitTask?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let calendar = try await database.read { db in
            try #require(
                try OMERecord.Calendar
                    .where { $0.id.eq(calendarID) }
                    .fetchOne(db)
            )
        }

        #expect(calendar.name == "Updated Calendar")
        #expect(calendar.description == "Updated description")
        #expect(calendar.images?.imageAsset(role: .hero)?.url?.absoluteString == "https://example.com/hero.png")
        #expect(calendar.images?.imageAsset(role: .logo)?.url?.absoluteString == "https://example.com/logo.png")
    }

    @Test
    func editCalendarLoadsMissingCalendarAsDefaultDraft() throws {
        let database = try makePreparedDatabase()
        let calendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EditCalendar.State(calendarID: calendarID)) {
                EditCalendar()
            }
        }

        #expect(store.state.hasLoadedDraft == true)
        #expect(store.state.draft?.id == calendarID)
        #expect(store.state.draft?.name == "Events")
        #expect(store.state.form.value.name == "Events")
        #expect(store.state.errorMessage == nil)
    }

    @Test
    func editCalendarSavesMissingDefaultCalendar() async throws {
        let database = try makePreparedDatabase()
        let calendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            var state = EditCalendar.State(calendarID: calendarID)
            state.hasLoadedDraft = true
            state.draft = OMERecord.Calendar.Draft(
                id: calendarID,
                name: "Events",
                description: nil,
                images: nil
            )
            state.form.value.name = " Source Calendar "
            state.form.value.description = " Source description "
            state.heroImagePicker.replaceURLString("https://example.com/source-hero.png")

            return TestStore(initialState: state) {
                EditCalendar()
            }
        }

        let submitTask = store.send(.saveButtonTapped)
        let saveTask = await store.receive(
            \.formSubmitted,
            .equals(
                EditCalendar.FormValue(
                    name: " Source Calendar ",
                    description: " Source description "
                )
            ),
            timeout: .seconds(1)
        )
        await saveTask?.value
        await submitTask?.value

        let calendar = try await database.read { db in
            try #require(
                try OMERecord.Calendar
                    .where { $0.id.eq(calendarID) }
                    .fetchOne(db)
            )
        }

        #expect(calendar.name == "Source Calendar")
        #expect(calendar.description == "Source description")
        #expect(calendar.images?.imageAsset(role: .hero)?.url?.absoluteString == "https://example.com/source-hero.png")
    }

    @Test
    func organizerDetailGroupsDefaultCalendarEntries() async throws {
        let database = try makePreparedDatabase()
        let calendarID = OrganizerDetail.defaultCalendarID(organizerID: testOrganizerID)
        let currentEventID = eventID("current-event")
        let previousEventID = eventID("previous-event")
        let upcomingEventID = eventID("upcoming-event")
        let legacyOnlyEventID = eventID("legacy-only-event")
        let currentEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("current-event")
        )
        let previousEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("previous-event")
        )
        let upcomingEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("upcoming-event")
        )
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let today = try #require(LocalDate("2026-05-11"))
        let currentStartDate = try #require(LocalDate("2026-05-10"))
        let currentEndDate = try #require(LocalDate("2026-05-12"))
        let previousStartDate = try #require(LocalDate("2026-05-01"))
        let previousEndDate = try #require(LocalDate("2026-05-03"))
        let upcomingStartDate = try #require(LocalDate("2026-06-01"))
        let upcomingEndDate = try #require(LocalDate("2026-06-03"))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(
                db,
                id: currentEventID,
                name: "Current Event",
                startDate: currentStartDate,
                endDate: currentEndDate,
                timeZone: timeZone
            )
            try Self.insertEvent(
                db,
                id: previousEventID,
                name: "Previous Event",
                startDate: previousStartDate,
                endDate: previousEndDate,
                timeZone: timeZone
            )
            try Self.insertEvent(
                db,
                id: upcomingEventID,
                name: "Upcoming Event",
                startDate: upcomingStartDate,
                endDate: upcomingEndDate,
                timeZone: timeZone
            )
            try Self.insertEvent(db, id: legacyOnlyEventID, name: "Legacy Only Event")
            try Self.insertEventOrganizer(db, eventID: legacyOnlyEventID, organizerID: testOrganizerID)
            try Self.insertCalendar(db, id: calendarID, name: "Main Calendar")
            try Self.insertCalendarEntry(
                db,
                id: currentEntryID,
                event: OMERecord.Event.reference(id: currentEventID),
                createdAt: Date(timeIntervalSince1970: 100)
            )
            try Self.insertCalendarEntry(
                db,
                id: previousEntryID,
                event: OMERecord.Event.reference(id: previousEventID),
                createdAt: Date(timeIntervalSince1970: 200)
            )
            try Self.insertCalendarEntry(
                db,
                id: upcomingEntryID,
                event: OMERecord.Event.reference(id: upcomingEventID),
                createdAt: Date(timeIntervalSince1970: 300)
            )
        }
        let entryRows = try await database.read { db in
            CalendarDetail.EntryRows(
                entries: try OrganizerDetail.defaultCalendarEntriesQuery(
                    organizerID: testOrganizerID
                )
                .fetchAll(db),
                events: try CalendarDetail.localEventsQuery.fetchAll(db)
            )
        }
        let sections = OrganizerDetail.CalendarEntrySections(
            entryRows: entryRows,
            now: today.atStartOfDay(in: timeZone)
        )

        #expect(sections.currentRows.map(\.event?.id) == [currentEventID])
        #expect(sections.upcomingRows.map(\.event?.id) == [upcomingEventID])
        #expect(sections.previousRows.map(\.event?.id) == [previousEventID])
    }

    @Test
    func contributorsViewerFetchesContributorsForEvent() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let otherEventID = eventID("event-2")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertEvent(db, id: otherEventID, name: "Event Two")
            try Self.insertContributor(db, eventID: selectedEventID, contributorID: "zara", name: "Zara")
            try Self.insertContributor(db, eventID: selectedEventID, contributorID: "amy", name: "Amy")
            try Self.insertContributor(db, eventID: otherEventID, contributorID: "other", name: "Other")
        }

        let contributors = try await database.read { db in
            try ContributorsViewer.contributorProfilesQuery(eventID: selectedEventID).fetchAll(db)
        }

        #expect(contributors.map(\.name) == ["Amy", "Zara"])
    }

    @Test
    func contributorProfileUnhydratedDoesNotRequireActorCacheTables() async throws {
        let database = try makeCoreDatabase()
        let selectedEventID = eventID("event-1")
        let actor = try #require(OMERecord.Contributor.Actor("alice.bsky.social"))
        let date = try #require(LocalDate("2026-08-07"))

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: selectedEventID,
                contributorID: "speaker-1",
                name: "Alice"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                contributorID: "speaker-1",
                contributorActor: actor
            )
        }

        let profiles = try await database.read { db in
            try ContributorProfile
                .all(eventID: selectedEventID, hydration: .none)
                .fetchAll(db)
        }

        let profile = try #require(profiles.first)
        #expect(profile.name == "Alice")
        #expect(profile.contributorActor == actor)
        #expect(profile.handle == nil)

        await #expect(throws: (any Error).self) {
            try await database.read { db in
                try ContributorProfile
                    .all(eventID: selectedEventID, hydration: .bskyActorProfile)
                    .fetchAll(db)
            }
        }
    }

    @Test
    func contributorStageContextAggregatesScheduledAndLineupStages() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let otherEventID = eventID("event-2")
        let contributorID = contributorLocalID("artist")
        let date = try #require(LocalDate("2026-08-07"))

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertEvent(db, id: otherEventID, name: "Event Two")
            try Self.insertContributor(db, eventID: selectedEventID, contributorID: "artist", name: "Artist")
            try Self.insertContributor(db, eventID: otherEventID, contributorID: "artist", name: "Other Artist")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertSchedule(db, eventID: otherEventID, scheduleID: "friday", date: date)
            try Self.insertStage(
                db,
                eventID: selectedEventID,
                stageID: "main",
                name: "Main",
                sortIndex: 1,
                lineup: [contributorID]
            )
            try Self.insertStage(
                db,
                eventID: selectedEventID,
                stageID: "meadow",
                name: "Meadow",
                sortIndex: 2
            )
            try Self.insertStage(
                db,
                eventID: selectedEventID,
                stageID: "tent",
                name: "Tent",
                sortIndex: 3,
                lineup: [contributorID]
            )
            try Self.insertStage(
                db,
                eventID: otherEventID,
                stageID: "other",
                name: "Other",
                sortIndex: 0,
                lineup: [contributorID]
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "meadow-set",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 100),
                endTime: Date(timeIntervalSince1970: 200),
                title: "Meadow Set"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "tent-set",
                stageID: "tent",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 300),
                endTime: Date(timeIntervalSince1970: 400),
                title: "Tent Set"
            )
            try Self.insertPerformance(
                db,
                eventID: otherEventID,
                performanceID: "other-set",
                stageID: "other",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 50),
                endTime: Date(timeIntervalSince1970: 60),
                title: "Other Set"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: selectedEventID,
                performanceID: "meadow-set",
                contributorID: "artist"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: selectedEventID,
                performanceID: "tent-set",
                contributorID: "artist"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: otherEventID,
                performanceID: "other-set",
                contributorID: "artist"
            )
        }

        let context = try await database.read { db in
            ContributorStageContext(
                contributorID: contributorID,
                performanceContributors: try ContributorsViewer.performanceContributorsQuery(
                    eventID: selectedEventID
                )
                .fetchAll(db),
                performances: try ScheduleViewer.eventPerformancesQuery(eventID: selectedEventID)
                    .fetchAll(db),
                stages: try ScheduleViewer.stagesQuery(eventID: selectedEventID)
                    .fetchAll(db)
            )
        }

        #expect(context.scheduledPerformances.map(\.title) == ["Meadow Set", "Tent Set"])
        #expect(context.lineupOnlyStages.map(\.name) == ["Main"])
        #expect(context.stages.map(\.name) == ["Main", "Meadow", "Tent"])
        #expect(context.primaryStage?.name == "Main")
        let firstPerformance = try #require(context.scheduledPerformances.first)
        #expect(context.stage(for: firstPerformance)?.name == "Meadow")

        let rowContext = try await database.read { db in
            try #require(
                ContributorsViewer.contributorRowsQuery(eventID: selectedEventID)
                    .fetchAll(db)
                    .first { $0.contributorID == contributorID }
            )
            .stageContext
        }

        #expect(rowContext.lineupOnlyStages.map(\.name) == ["Main"])
        #expect(rowContext.stages.map(\.name) == ["Main", "Meadow", "Tent"])
    }

    @Test
    func performanceRowScheduleQueryReturnsPerformanceAndStage() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "saturday", date: date)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "meadow", name: "Meadow")
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "opening",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 18, in: timeZone)),
                endTime: try #require(date.at(hour: 19, in: timeZone)),
                title: "Opening"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "next-day",
                stageID: "meadow",
                scheduleID: "saturday",
                startTime: try #require(date.at(hour: 20, in: timeZone)),
                endTime: try #require(date.at(hour: 21, in: timeZone)),
                title: "Next Day"
            )
        }

        let rows = try await database.read { db in
            try PerformanceRow
                .all(eventID: selectedEventID, scheduleID: scheduleLocalID("friday"))
                .fetchAll(db)
        }

        #expect(rows.map(\.performanceID) == [performanceLocalID("opening")])
        #expect(rows.map(\.title) == ["Opening"])
        #expect(rows.first?.stage?.name == "Meadow")
    }

    @Test
    func performanceRowContributorQueryReturnsContributorPerformancesAndStages() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let contributorID = contributorLocalID("artist")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertContributor(db, eventID: selectedEventID, contributorID: "artist", name: "Artist")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "meadow", name: "Meadow")
            try Self.insertStage(db, eventID: selectedEventID, stageID: "tent", name: "Tent")
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "meadow-set",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 18, in: timeZone)),
                endTime: try #require(date.at(hour: 19, in: timeZone)),
                title: "Meadow Set"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "tent-set",
                stageID: "tent",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 20, in: timeZone)),
                endTime: try #require(date.at(hour: 21, in: timeZone)),
                title: "Tent Set"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: selectedEventID,
                performanceID: "meadow-set",
                contributorID: "artist"
            )
        }

        let rows = try await database.read { db in
            try PerformanceRow
                .forContributor(contributorID: contributorID, eventID: selectedEventID)
                .fetchAll(db)
        }

        #expect(rows.map(\.performanceID) == [performanceLocalID("meadow-set")])
        #expect(rows.map(\.title) == ["Meadow Set"])
        #expect(rows.first?.stage?.name == "Meadow")
    }

    @Test
    func performanceRowSubtitleUsesEventTimeZoneAndLegacyDaySegment() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let friday = try #require(LocalDate("2026-08-07"))
        let saturday = try #require(LocalDate("2026-08-08"))

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "friday", date: friday)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "evening",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(friday.at(hour: 18, in: timeZone)),
                endTime: try #require(friday.at(hour: 19, in: timeZone)),
                title: "Evening Set"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "late-night",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(saturday.at(hour: 1, minute: 30, in: timeZone)),
                endTime: try #require(saturday.at(hour: 2, minute: 30, in: timeZone)),
                title: "Late Night"
            )
        }

        let rows = try await database.read { db in
            try PerformanceRow
                .all(eventID: eventID, scheduleID: scheduleLocalID("friday"))
                .fetchAll(db)
        }
        let eveningPerformance = try #require(rows.first?.performance)
        let afterMidnightPerformance = try #require(rows.dropFirst().first?.performance)

        #expect(
            ScheduleViewer.performanceRowSubtitle(
                for: eveningPerformance,
                timeZone: timeZone
            ) == "6:00 PM - 7:00 PM Friday Evening"
        )
        #expect(
            ScheduleViewer.performanceRowSubtitle(
                for: afterMidnightPerformance,
                timeZone: timeZone
            ) == "1:30 AM - 2:30 AM Friday Night"
        )
    }

    @Test(arguments: ["alice.bsky.social", "did:plc:alice123"])
    func contributorProfileUsesCachedBlueskyProfileDataForGeneratedActor(actorString: String) async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let actor = try #require(OMERecord.Contributor.Actor(actorString))
        let contributorID = contributorLocalID("schedule-actor-alice.bsky.social")
        let date = try #require(LocalDate("2026-08-07"))
        let profile = BlueskyActorProfile(
            did: "did:plc:alice123",
            handle: "alice.bsky.social",
            displayName: "Alice Example",
            description: "ATProto builder",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg"),
            banner: URL(string: "https://cdn.example/alice-banner.jpg")
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: selectedEventID,
                contributorID: "schedule-actor-alice.bsky.social",
                name: "alice.bsky.social"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                contributorID: "schedule-actor-alice.bsky.social",
                contributorActor: actor
            )
            try BlueskyActorProfile.insert { profile }
                .execute(db)
            try BlueskyActorProfileCacheEntry.insert {
                BlueskyActorProfileCacheEntry(
                    actor: actor.description,
                    did: profile.did,
                    lastFetchedAt: Date(timeIntervalSince1970: 1_000),
                    lastFetchAttemptAt: Date(timeIntervalSince1970: 1_000)
                )
            }
            .execute(db)
        }

        let row = try await database.read { db in
            try #require(
                ContributorsViewer.contributorRowsQuery(
                    eventID: selectedEventID,
                    hydration: .bskyActorProfile
                )
                    .fetchAll(db)
                    .first { $0.contributorID == contributorID }
            )
        }
        let contributorProfile = row.profile

        #expect(contributorProfile.contributorActor == actor)
        #expect(contributorProfile.usesActorProfileAsPrimary)
        #expect(contributorProfile.name == "Alice Example")
        #expect(contributorProfile.handle == "alice.bsky.social")
        #expect(contributorProfile.subtitle == "@alice.bsky.social")
        #expect(contributorProfile.bio == "ATProto builder")
        #expect(contributorProfile.artworkAsset?.url?.absoluteString == "https://cdn.example/alice-avatar.jpg")
        #expect(contributorProfile.artworkCacheContext == nil)
        #expect(row.matchesSearch("Alice Example"))
        #expect(row.matchesSearch("alice.bsky.social"))
    }

    @Test
    func contributorProfileKeepsExplicitContributorFieldsAheadOfCachedBlueskyProfileData() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let actor = try #require(OMERecord.Contributor.Actor("alice.bsky.social"))
        let contributorID = contributorLocalID("speaker-1")
        let date = try #require(LocalDate("2026-08-07"))
        let explicitImageURL = try #require(URL(string: "https://example.com/explicit.jpg"))
        let profile = BlueskyActorProfile(
            did: "did:plc:alice123",
            handle: "alice.bsky.social",
            displayName: "Bluesky Alice",
            description: "Bluesky bio",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg")
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: selectedEventID,
                contributorID: "speaker-1",
                name: "Explicit Alice",
                bio: "OME bio",
                imageURL: explicitImageURL,
                kind: OMERecord.Contributor.Kind("speaker")
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                contributorID: "speaker-1",
                contributorActor: actor
            )
            try BlueskyActorProfile.insert { profile }
                .execute(db)
            try BlueskyActorProfileCacheEntry.insert {
                BlueskyActorProfileCacheEntry(
                    actor: actor.description,
                    did: profile.did,
                    lastFetchedAt: Date(timeIntervalSince1970: 1_000),
                    lastFetchAttemptAt: Date(timeIntervalSince1970: 1_000)
                )
            }
            .execute(db)
        }

        let row = try await database.read { db in
            try #require(
                ContributorsViewer.contributorRowsQuery(
                    eventID: selectedEventID,
                    hydration: .bskyActorProfile
                )
                    .fetchAll(db)
                    .first { $0.contributorID == contributorID }
            )
        }
        let contributorProfile = row.profile

        #expect(contributorProfile.contributorActor == actor)
        #expect(!contributorProfile.usesActorProfileAsPrimary)
        #expect(contributorProfile.name == "Explicit Alice")
        #expect(contributorProfile.handle == "alice.bsky.social")
        #expect(contributorProfile.subtitle == "@alice.bsky.social")
        #expect(contributorProfile.kindDisplayName == "speaker")
        #expect(contributorProfile.bio == "OME bio")
        #expect(contributorProfile.artworkAsset?.url == explicitImageURL)
        #expect(contributorProfile.artworkCacheContext == LocalImageCacheContext(contributorID: row.contributor.id))
        #expect(row.matchesSearch("Explicit Alice"))
        #expect(row.matchesSearch("alice.bsky.social"))
        #expect(!row.matchesSearch("Bluesky Alice"))
    }

    @Test(arguments: ["alice.bsky.social", "did:plc:alice123"])
    func contributorsViewerRefreshesGeneratedActorProfilesForListRows(actorString: String) async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let actor = try #require(OMERecord.Contributor.Actor(actorString))
        let contributorID = contributorLocalID("schedule-actor-alice.bsky.social")
        let date = try #require(LocalDate("2026-08-07"))
        let profile = BlueskyActorProfile(
            did: "did:plc:alice123",
            handle: "alice.bsky.social",
            displayName: "Alice Example",
            description: "ATProto builder",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg")
        )
        let requestRecorder = BlueskyProfileRequestRecorder()

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: selectedEventID,
                contributorID: "schedule-actor-alice.bsky.social",
                name: "alice.bsky.social"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                contributorID: "schedule-actor-alice.bsky.social",
                contributorActor: actor
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.blueskyActorProfileCache = BlueskyActorProfileCacheClient(
                cachedProfile: { _ in nil },
                refreshProfile: { requestedActor in
                    await requestRecorder.record(requestedActor)
                    return profile
                },
                refreshProfileIfNeeded: { requestedActor, _, _ in
                    await requestRecorder.record(requestedActor)
                    try await database.write { db in
                        try BlueskyActorProfile.insert { profile }
                            .execute(db)
                        try BlueskyActorProfileCacheEntry.insert {
                            BlueskyActorProfileCacheEntry(
                                actor: requestedActor,
                                did: profile.did,
                                lastFetchedAt: Date(timeIntervalSince1970: 1_000),
                                lastFetchAttemptAt: Date(timeIntervalSince1970: 1_000)
                            )
                        }
                        .execute(db)
                    }
                    return profile
                }
            )
        } operation: {
            Store(initialState: ContributorsViewer.State(eventID: selectedEventID)) {
                ContributorsViewer()
            }
        }

        try await waitForContributorListBlueskyProfile(in: store, contributorID: contributorID)

        #expect(await requestRecorder.actors == [actor.description])
        let row = try #require(store.contributorRows.first { $0.contributorID == contributorID })
        #expect(row.profile.name == "Alice Example")
        #expect(row.profile.subtitle == "@alice.bsky.social")
        #expect(row.profile.artworkAsset?.url?.absoluteString == "https://cdn.example/alice-avatar.jpg")
    }

    @Test
    func stagesViewerFetchesStagesForEventInOrder() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let otherEventID = eventID("event-2")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertEvent(db, id: otherEventID, name: "Event Two")
            try Self.insertStage(db, eventID: selectedEventID, stageID: "late", name: "Late", sortIndex: 2)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "main", name: "Main", sortIndex: 1)
            try Self.insertStage(db, eventID: otherEventID, stageID: "other", name: "Other")
        }

        let stages = try await database.read { db in
            try StagesViewer.stagesQuery(eventID: selectedEventID).fetchAll(db)
        }

        #expect(stages.map(\.name) == ["Main", "Late"])
    }

    @Test
    func stageDetailFetchesStageForEvent() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let otherEventID = eventID("event-2")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertEvent(db, id: otherEventID, name: "Event Two")
            try Self.insertStage(db, eventID: selectedEventID, stageID: "main", name: "Main")
            try Self.insertStage(db, eventID: otherEventID, stageID: "main", name: "Other Main")
        }

        let stage = try await database.read { db in
            try StageDetail.stageQuery(
                stageID: stageLocalID("main"),
                eventID: selectedEventID
            )
            .fetchOne(db)
        }

        #expect(stage?.name == "Main")
    }

    @Test
    func scheduleViewerFetchesSchedulesForEventInOrder() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let otherEventID = eventID("event-2")
        let friday = try #require(LocalDate("2026-08-07"))
        let saturday = try #require(LocalDate("2026-08-08"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One", timeZone: timeZone)
            try Self.insertEvent(db, id: otherEventID, name: "Event Two", timeZone: timeZone)
            try Self.insertSchedule(
                db,
                eventID: selectedEventID,
                scheduleID: "friday-late",
                date: friday,
                startsAt: friday.at(hour: 20, in: timeZone),
                customTitle: "Friday Late"
            )
            try Self.insertSchedule(
                db,
                eventID: selectedEventID,
                scheduleID: "saturday",
                date: saturday,
                startsAt: saturday.at(hour: 12, in: timeZone),
                customTitle: "Saturday"
            )
            try Self.insertSchedule(
                db,
                eventID: selectedEventID,
                scheduleID: "friday-early",
                date: friday,
                startsAt: friday.at(hour: 18, in: timeZone),
                customTitle: "Friday Early"
            )
            try Self.insertSchedule(
                db,
                eventID: otherEventID,
                scheduleID: "other",
                date: friday,
                startsAt: friday.at(hour: 17, in: timeZone),
                customTitle: "Other"
            )
        }

        let schedules = try await database.read { db in
            try ScheduleViewer.schedulesQuery(eventID: selectedEventID).fetchAll(db)
        }

        #expect(schedules.map(\.id.scheduleID) == [
            scheduleLocalID("friday-early"),
            scheduleLocalID("friday-late"),
            scheduleLocalID("saturday"),
        ])
    }

    @Test
    func scheduleViewerFetchesPerformancesForSelectedScheduleInOrder() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let otherEventID = eventID("event-2")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One", timeZone: timeZone)
            try Self.insertEvent(db, id: otherEventID, name: "Event Two", timeZone: timeZone)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "meadow", name: "Meadow")
            try Self.insertStage(db, eventID: otherEventID, stageID: "other-stage", name: "Other")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "saturday", date: date)
            try Self.insertSchedule(db, eventID: otherEventID, scheduleID: "other", date: date)
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "closing",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 22, in: timeZone)),
                endTime: try #require(date.at(hour: 23, in: timeZone)),
                title: "Closing"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "opening",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 18, in: timeZone)),
                endTime: try #require(date.at(hour: 19, in: timeZone)),
                title: "Opening"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "other-day",
                stageID: "meadow",
                scheduleID: "saturday",
                startTime: try #require(date.at(hour: 17, in: timeZone)),
                endTime: try #require(date.at(hour: 18, in: timeZone)),
                title: "Other Day"
            )
            try Self.insertPerformance(
                db,
                eventID: otherEventID,
                performanceID: "other-event",
                stageID: "other-stage",
                scheduleID: "other",
                startTime: try #require(date.at(hour: 16, in: timeZone)),
                endTime: try #require(date.at(hour: 17, in: timeZone)),
                title: "Other Event"
            )
        }

        let performances = try await database.read { db in
            try ScheduleViewer.performancesQuery(
                eventID: selectedEventID,
                scheduleID: scheduleLocalID("friday")
            )
            .fetchAll(db)
        }

        #expect(performances.map(\.title) == ["Opening", "Closing"])
    }

    @Test
    func scheduleTimelineCardsWrapPerformancesAndBuildBufferedRange() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let openingStart = try #require(date.at(hour: 18, in: timeZone))
        let openingEnd = try #require(date.at(hour: 19, in: timeZone))
        let closingStart = try #require(date.at(hour: 20, in: timeZone))
        let closingEnd = try #require(date.at(hour: 21, in: timeZone))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One", timeZone: timeZone)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "friday", date: date)
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "closing",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: closingStart,
                endTime: closingEnd,
                title: "Closing"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "opening",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: openingStart,
                endTime: openingEnd,
                title: "Opening"
            )
        }

        let performanceRows = try await database.read { db in
            try PerformanceRow.all(
                eventID: eventID,
                scheduleID: scheduleLocalID("friday")
            )
            .fetchAll(db)
        }
        let performances = performanceRows.map(\.performance)
        let cards = performances.map(SchedulePerformanceTimelineCard.init)
        let timeRange = try #require(
            ScheduleStageTimelinePage.timeRange(
                for: performances,
                buffer: 30 * 60
            )
        )

        #expect(cards.map(\.id) == [
            performanceLocalID("opening"),
            performanceLocalID("closing"),
        ])
        #expect(cards.first?.dateInterval.start == openingStart)
        #expect(cards.first?.dateInterval.end == openingEnd)
        #expect(timeRange.start == openingStart.addingTimeInterval(-30 * 60))
        #expect(timeRange.end == closingEnd.addingTimeInterval(30 * 60))
    }

    @Test
    func scheduleViewerDefaultsToSingleStageMode() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            ScheduleViewer.State(eventID: eventID)
        }

        #expect(state.scheduleMode == .singleStageAtOnce)
    }

    @Test
    func scheduleViewerModeButtonChangesMode() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            TestStore(initialState: ScheduleViewer.State(eventID: eventID)) {
                ScheduleViewer()
            }
        }

        store.send(.scheduleModeButtonTapped(.list))

        #expect(store.state.scheduleMode == .list)
    }

    @Test
    func addScheduleDefaultsToEventStartDate() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let eventStartDate = try #require(LocalDate("2026-08-07"))
        let today = try #require(LocalDate("2026-06-01"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(today.at(hour: 12, in: timeZone))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(
                db,
                id: eventID,
                name: "Event One",
                startDate: eventStartDate,
                timeZone: timeZone
            )
        }
        let store = withDependencies {
            $0.context = .test
            $0.date = .constant(now)
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.defaultEventTimeZone = timeZone
        } operation: {
            TestStore(initialState: ScheduleViewer.State(eventID: eventID)) {
                ScheduleViewer()
            }
        }

        store.send(.addScheduleButtonTapped)

        let editSchedule = try #require(store.state.destination?.editSchedule)
        expectNoDifference(editSchedule.scheduleDate, eventStartDate)
        expectNoDifference(editSchedule.customTitle, "Friday")
        expectNoDifference(editSchedule.sourceFileName, "friday")
    }

    @Test
    func scheduleViewerStatePersistsModeAndStagePerDivision() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let workshopDivision = ScheduleViewer.ScheduleDivision(
            category: OMERecord.Stage.Category("workshop")
        )

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            ScheduleViewer.State(eventID: eventID)
        }

        state.$scheduleViewerState.withLock {
            $0.scheduleMode = .list
            $0.selectedStageID = stageLocalID("main")
            $0.showStageNameLabels = true
        }
        try await state.$scheduleViewerState.save()

        let storedState = try await database.read { db in
            try ScheduleViewerStateRequest(
                eventID: eventID,
                scheduleDivision: .schedule
            )
            .fetch(db)
        }

        let restoredState = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            ScheduleViewer.State(eventID: eventID)
        }

        let workshopState = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            ScheduleViewer.State(
                eventID: eventID,
                scheduleDivision: workshopDivision
            )
        }

        #expect(storedState.scheduleMode == .list)
        #expect(storedState.selectedStageID == stageLocalID("main"))
        #expect(storedState.showStageNameLabels)
        #expect(restoredState.scheduleMode == .list)
        #expect(restoredState.selectedStageID == stageLocalID("main"))
        #expect(restoredState.showStageNameLabels)
        #expect(workshopState.scheduleMode == .singleStageAtOnce)
        #expect(workshopState.selectedStageID == nil)
        #expect(!workshopState.showStageNameLabels)
    }

    @Test
    func scheduleViewerResolvedStageFallsBackToFirstOrderedStage() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(db, eventID: eventID, stageID: "late", name: "Late", sortIndex: 2)
            try Self.insertStage(db, eventID: eventID, stageID: "main", name: "Main", sortIndex: 1)
        }

        let stages = try await database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }

        #expect(
            ScheduleViewer.resolvedSelectedStageID(
                selectedStageID: nil,
                stages: stages
            ) == stageLocalID("main")
        )
        #expect(
            ScheduleViewer.resolvedSelectedStageID(
                selectedStageID: stageLocalID("missing"),
                stages: stages
            ) == stageLocalID("main")
        )
        #expect(
            ScheduleViewer.resolvedSelectedStageID(
                selectedStageID: stageLocalID("late"),
                stages: stages
            ) == stageLocalID("late")
        )
    }

    @Test
    func scheduleViewerBuildsDivisionsFromStageCategories() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(db, eventID: eventID, stageID: "main", name: "Main", sortIndex: 1)
            try Self.insertStage(
                db,
                eventID: eventID,
                stageID: "workshop",
                name: "Workshop",
                category: OMERecord.Stage.Category("workshop"),
                sortIndex: 2
            )
            try Self.insertStage(
                db,
                eventID: eventID,
                stageID: "second-workshop",
                name: "Second Workshop",
                category: OMERecord.Stage.Category("workshop"),
                sortIndex: 3
            )
        }

        let stages = try await database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }
        let divisions = ScheduleViewer.scheduleDivisions(stages: stages)

        #expect(divisions.map(\.id) == ["schedule", "workshop"])
        #expect(divisions.map(\.title) == ["Schedule", "Workshops"])
    }

    @Test
    func scheduleViewerFiltersStagesAndPerformancesToDivision() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let workshopDivision = ScheduleViewer.ScheduleDivision(
            category: OMERecord.Stage.Category("workshop")
        )
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One", timeZone: timeZone)
            try Self.insertStage(db, eventID: eventID, stageID: "main", name: "Main", sortIndex: 1)
            try Self.insertStage(
                db,
                eventID: eventID,
                stageID: "workshop",
                name: "Workshop",
                category: OMERecord.Stage.Category("workshop"),
                sortIndex: 2
            )
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "friday", date: date)
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "concert",
                stageID: "main",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 18, in: timeZone)),
                endTime: try #require(date.at(hour: 19, in: timeZone)),
                title: "Concert"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "workshop",
                stageID: "workshop",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 20, in: timeZone)),
                endTime: try #require(date.at(hour: 21, in: timeZone)),
                title: "Workshop"
            )
        }

        let stages = try await database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }
        let performanceRows = try await database.read { db in
            try PerformanceRow.all(
                eventID: eventID,
                scheduleID: scheduleLocalID("friday")
            )
            .fetchAll(db)
        }
        let visibleStages = ScheduleViewer.visibleStages(
            stages: stages,
            division: workshopDivision
        )
        let visiblePerformances = ScheduleViewer.visiblePerformances(
            performanceRows: performanceRows,
            scheduleID: scheduleLocalID("friday"),
            stages: visibleStages
        )

        #expect(visibleStages.map(\.id.stageID) == [stageLocalID("workshop")])
        #expect(visiblePerformances.map(\.title) == ["Workshop"])
    }

    @Test
    func eventViewerBuildsScheduleDivisionTabsFromStageCategories() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let workshopDivision = ScheduleViewer.ScheduleDivision(
            category: OMERecord.Stage.Category("workshop")
        )
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(db, eventID: eventID, stageID: "main", name: "Main", sortIndex: 1)
            try Self.insertStage(
                db,
                eventID: eventID,
                stageID: "workshop",
                name: "Workshop",
                category: workshopDivision.category,
                sortIndex: 2
            )
        }

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            EventViewer.State(eventID: eventID)
        }

        #expect(Array(state.installedFeatures.prefix(2).map(\.description)) == [
            "schedule",
            "schedule:workshop",
        ])
        #expect(state.scheduleViewers.map { $0.state.scheduleDivision.id } == ["schedule", "workshop"])
        #expect(state.installedFeatures.contains(.edit))
        #expect(state.installedFeatures.contains(.settings))
        #expect(state.editEvent?.eventID == eventID)
        #expect(state.eventSettings?.eventID == eventID)
    }

    @Test
    func eventViewerStatePersistsSelectedSchedulePerEvent() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let workshopDivision = ScheduleViewer.ScheduleDivision(
            category: OMERecord.Stage.Category("workshop")
        )

        let state = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            EventViewer.State(
                eventID: eventID,
                features: [
                    .schedule(.schedule),
                    .schedule(workshopDivision),
                ]
            )
        }

        state.$eventViewerState.selectedScheduleID.withLock {
            $0 = scheduleLocalID("thursday")
        }
        try await state.$eventViewerState.save()

        let storedState = try await database.read { db in
            try EventViewerStateRequest(eventID: eventID).fetch(db)
        }

        let restoredState = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            EventViewer.State(
                eventID: eventID,
                features: [
                    .schedule(.schedule),
                    .schedule(workshopDivision),
                ]
            )
        }

        #expect(state.scheduleViewers.map { $0.state.scheduleDivision.id } == ["schedule", "workshop"])
        #expect(storedState.selectedScheduleID == scheduleLocalID("thursday"))
        #expect(restoredState.eventViewerState.selectedScheduleID == scheduleLocalID("thursday"))
    }

    @Test
    func scheduleViewerStageFallbackIsScopedToDivision() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let workshopDivision = ScheduleViewer.ScheduleDivision(
            category: OMERecord.Stage.Category("workshop")
        )
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(db, eventID: eventID, stageID: "main", name: "Main", sortIndex: 1)
            try Self.insertStage(
                db,
                eventID: eventID,
                stageID: "workshop",
                name: "Workshop",
                category: workshopDivision.category,
                sortIndex: 2
            )
        }

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            var state = ScheduleViewer.State(
                eventID: eventID,
                scheduleDivision: workshopDivision
            )
            state.selectedStageID = stageLocalID("main")
            return state
        }

        #expect(state.visibleStages.map(\.id.stageID) == [stageLocalID("workshop")])
        #expect(state.resolvedSelectedStageID == stageLocalID("workshop"))
    }

    @Test
    func scheduleViewerPerformanceTapPresentsDetail() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let performanceID = performanceLocalID("opening")
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            TestStore(initialState: ScheduleViewer.State(eventID: eventID)) {
                ScheduleViewer()
            }
        }

        store.send(.performanceButtonTapped(performanceID))

        #expect(store.state.destination?.performanceDetail?.performanceID == performanceID)
    }

    @Test
    func performanceDetailQueriesCoreFields() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let recordingURL = try #require(URL(string: "https://example.com/recording"))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One", timeZone: timeZone)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "friday", date: date)
            try Self.insertContributor(db, eventID: eventID, contributorID: "amy", name: "Amy")
            try Self.insertContributor(db, eventID: eventID, contributorID: "zara", name: "Zara")
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "opening",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 18, in: timeZone)),
                endTime: try #require(date.at(hour: 19, in: timeZone)),
                title: "Opening",
                description: "First set",
                recordings: [ExternalPlatform.Asset(url: recordingURL)]
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "opening",
                contributorID: "zara"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "opening",
                contributorID: "amy"
            )
        }

        let performance = try await database.read { db in
            try #require(
                try PerformanceDetail.performanceQuery(
                    performanceID: performanceLocalID("opening"),
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }
        let contributors = try await database.read { db in
            try PerformanceDetail.contributorsQuery(
                performanceID: performanceLocalID("opening"),
                eventID: eventID
            )
            .fetchAll(db)
        }
        let stages = try await database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }

        #expect(performance.title == "Opening")
        #expect(performance.description == "First set")
        #expect(performance.recordings.map(\.url) == [recordingURL])
        #expect(stages.first { $0.id.stageID == performance.stageID }?.name == "Meadow")
        #expect(contributors.map(\.name) == ["Amy", "Zara"])
    }

    @Test
    func editContributorSavesChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("artist-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertContributor(db, eventID: eventID, contributorID: "artist-1", name: "Old Name")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = EditContributor.State(contributorID: contributorID, eventID: eventID)
            state.hasLoadedDraft = true
            state.form.value.name = " New Name "
            state.form.value.kind = "dj"
            state.form.value.bio = " Updated bio "
            state.imageURL = "https://example.com/image.jpg"
            state.logoURL = " "
            var link = EditableContributorLink()
            link.url = "https://example.com"
            link.platformRawValue = ExternalPlatform.website.rawValue
            state.form.value.links = [link]

            return TestStore(initialState: state) {
                EditContributor()
            }
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let contributor = try await database.read { db in
            try #require(
                try ContributorDetail.contributorQuery(
                    contributorID: contributorID,
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }

        #expect(contributor.name == "New Name")
        #expect(contributor.kind?.rawValue == "dj")
        #expect(contributor.bio == "Updated bio")
        #expect(contributor.imageURL?.absoluteString == "https://example.com/image.jpg")
        #expect(contributor.logoURL == nil)
        #expect(contributor.links?.map(\.url.absoluteString) == ["https://example.com"])
        #expect(contributor.links?.map(\.platform) == [.website])
    }

    @Test
    func editContributorSaveSurfacesUnderlyingError() async throws {
        let database = try defaultDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("artist-1")

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = EditContributor.State(contributorID: contributorID, eventID: eventID)
            state.hasLoadedDraft = true
            state.form.value.name = "New Name"

            return TestStore(initialState: state) {
                EditContributor()
            }
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.isPresented)
        #expect(store.state.errorMessage?.hasPrefix("Unable to save contributor: ") == true)
        #expect(store.state.errorMessage != "Unable to save contributor.")
    }

    @Test
    func editContributorStoreBindingsSaveChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("artist-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertContributor(db, eventID: eventID, contributorID: "artist-1", name: "Old Name")
        }

        @Bindable var store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EditContributor.State(contributorID: contributorID, eventID: eventID)) {
                EditContributor()
            }
        }

        #expect(store.hasLoadedDraft)
        #expect(store.form.value.name == "Old Name")

        $store.form.value.name.wrappedValue = "New Name"
        await store.send(.saveButtonTapped)?.value

        let contributor = try await database.read { db in
            try #require(
                try ContributorDetail.contributorQuery(
                    contributorID: contributorID,
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }

        #expect(contributor.name == "New Name")
    }

    @Test
    func contributorDetailEditSheetBindingsSaveChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("artist-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertContributor(db, eventID: eventID, contributorID: "artist-1", name: "Old Name")
        }

        @Bindable var detailStore = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: ContributorDetail.State(contributorID: contributorID, eventID: eventID)) {
                ContributorDetail()
            }
        }

        detailStore.send(.editButtonTapped)

        @Bindable var editStore = try #require(
            $detailStore
                .scope(\.destination, action: \.destination)
                .editContributor
                .wrappedValue
        )

        #expect(editStore.hasLoadedDraft)
        #expect(editStore.form.value.name == "Old Name")

        $editStore.form.value.name.wrappedValue = "New Name"
        await editStore.send(.saveButtonTapped)?.value

        let contributor = try await database.read { db in
            try #require(
                try ContributorDetail.contributorQuery(
                    contributorID: contributorID,
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }

        #expect(contributor.name == "New Name")
        #expect(detailStore.contributor?.name == "New Name")
        #expect(detailStore.destination == nil)
    }

    @Test
    func spawnedContributorDetailObservesSavedChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("artist-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertContributor(db, eventID: eventID, contributorID: "artist-1", name: "Old Name")
        }

        @Bindable var contributorsStore = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            Store(initialState: ContributorsViewer.State(eventID: eventID)) {
                ContributorsViewer()
            }
        }

        contributorsStore.send(.contributorButtonTapped(contributorID))
        @Bindable var detailStore = try #require(
            $contributorsStore
                .scope(\.destination, action: \.destination)
                .contributorDetail
                .wrappedValue
        )

        let viewObservationRecorder = ObservationRecorder<String>()
        withObservationTracking {
            _ = ContributorDetailView(store: detailStore).body
        } onChange: {
            Task {
                await viewObservationRecorder.record("invalidated")
            }
        }

        detailStore.send(.editButtonTapped)
        @Bindable var editStore = try #require(
            $detailStore
                .scope(\.destination, action: \.destination)
                .editContributor
                .wrappedValue
        )
        $editStore.form.value.name.wrappedValue = "New Name"
        await editStore.send(.saveButtonTapped)?.value
        try await Task.sleep(for: .milliseconds(300))

        #expect(await viewObservationRecorder.values == ["invalidated"])
        #expect(detailStore.contributor?.name == "New Name")
        #expect(detailStore.destination == nil)
    }

    @Test
    func contributorDetailDerivesActorFromMatchingPerformanceContributors() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let actor = try #require(OMERecord.Contributor.Actor("alice.bsky.social"))
        let contributorID = contributorLocalID("speaker-1")
        let date = try #require(LocalDate("2026-08-07"))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "day-1", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: eventID,
                contributorID: "speaker-1",
                name: "Alice"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "day-1",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                contributorID: "speaker-1",
                contributorActor: actor
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: ContributorDetail.State(contributorID: contributorID, eventID: eventID)) {
                ContributorDetail()
            }
        }

        #expect(store.contributorActor == actor)
        #expect(store.actorProfileLoadRequest?.actor == actor)
        #expect(!store.usesActorProfileAsPrimary)
    }

    @Test
    func editContributorActorPickerSearchesTypeaheadThenExactLookup() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("speaker-1")
        let exactIdentity = ActorIdentity(
            did: try #require(DID("did:plc:alice123")),
            handle: Atmosphere.Account.Handle(rawValue: "alice.example.com"),
            displayName: "Alice Exact",
            source: .canonicalResolution
        )
        let typeaheadIdentity = ActorIdentity(
            did: try #require(DID("did:plc:alice456")),
            handle: Atmosphere.Account.Handle(rawValue: "alice.bsky.social"),
            displayName: "Alice Typeahead",
            avatar: try #require(URL(string: "https://example.com/alice.jpg")),
            source: .typeahead
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertContributor(
                db,
                eventID: eventID,
                contributorID: "speaker-1",
                name: "Alice"
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.actorTypeaheadSearch.search = { query in
                #expect(query.normalizedText == "alice")
                return [typeaheadIdentity]
            }
            $0.actorIdentityLookup.resolve = { input in
                #expect(input == "alice")
                return exactIdentity
            }
        } operation: {
            Store(initialState: EditContributor.State(contributorID: contributorID, eventID: eventID)) {
                EditContributor()
            }
        }

        await store.send(.actorSearchQueryChanged(" alice "))?.value

        expectNoDifference(
            store.actorSearchSections.map(\.title),
            ["Profiles", "Exact match"]
        )
        expectNoDifference(
            store.actorSearchSections.flatMap(\.results),
            [typeaheadIdentity, exactIdentity]
        )
        #expect(store.actorSearchIsLoading == false)
        #expect(store.actorSearchFailures.isEmpty)
    }

    @Test
    func editContributorActorPickerAppliesSelectedDidToContributorAppearances() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("speaker-1")
        let previousActor = try #require(OMERecord.Contributor.Actor("alice.bsky.social"))
        let selectedIdentity = ActorIdentity(
            did: try #require(DID("did:plc:alice123")),
            handle: Atmosphere.Account.Handle(rawValue: "alice.bsky.social"),
            displayName: "Alice",
            source: .canonicalResolution
        )
        let selectedActor = try #require(OMERecord.Contributor.Actor(selectedIdentity.did.description))
        let date = try #require(LocalDate("2026-08-07"))
        let requestRecorder = BlueskyProfileRequestRecorder()

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "day-1", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: eventID,
                contributorID: "speaker-1",
                name: "Alice"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "day-1",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk One"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "talk-2",
                stageID: "meadow",
                scheduleID: "day-1",
                startTime: Date(timeIntervalSince1970: 7_200),
                endTime: Date(timeIntervalSince1970: 10_800),
                title: "Talk Two"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                contributorID: "speaker-1",
                contributorActor: previousActor
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "talk-2",
                contributorID: "speaker-1",
                contributorActor: previousActor
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.blueskyActorProfileCache = BlueskyActorProfileCacheClient(
                cachedProfile: { _ in nil },
                refreshProfile: { requestedActor in
                    await requestRecorder.record(requestedActor)
                    return BlueskyActorProfile(
                        did: selectedActor.description,
                        handle: "alice.bsky.social"
                    )
                },
                refreshProfileIfNeeded: { requestedActor, _, _ in
                    await requestRecorder.record(requestedActor)
                    return BlueskyActorProfile(
                        did: selectedActor.description,
                        handle: "alice.bsky.social"
                    )
                }
            )
        } operation: {
            Store(initialState: EditContributor.State(contributorID: contributorID, eventID: eventID)) {
                EditContributor()
            }
        }

        await store.send(.actorIdentityTapped(selectedIdentity))?.value

        let actors = try await database.read { db in
            try OMERecord.Performance.Contributors
                .fetchAll(db)
                .compactMap(\.contributorActor?.description)
                .sorted()
        }

        expectNoDifference(
            actors,
            [selectedActor.description, selectedActor.description]
        )
        #expect(await requestRecorder.actors == [selectedActor.description])
        #expect(store.contributorActor == selectedActor)
        #expect(store.actorPickerIsPresented == false)
        #expect(store.isSavingActor == false)
        #expect(store.actorPickerErrorMessage == nil)
    }

    @Test(arguments: ["alice.bsky.social", "did:plc:alice123"])
    func generatedActorContributorDisplayUsesBlueskyProfileData(actorString: String) async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let actor = try #require(OMERecord.Contributor.Actor(actorString))
        let contributorID = contributorLocalID("schedule-actor-alice.bsky.social")
        let date = try #require(LocalDate("2026-08-07"))
        let profile = BlueskyActorProfile(
            did: "did:plc:alice123",
            handle: "alice.bsky.social",
            displayName: "Alice Example",
            description: "ATProto builder",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg"),
            banner: URL(string: "https://cdn.example/alice-banner.jpg")
        )
        let requestRecorder = BlueskyProfileRequestRecorder()
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "day-1", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: eventID,
                contributorID: "schedule-actor-alice.bsky.social",
                name: "alice.bsky.social"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "day-1",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                contributorID: "schedule-actor-alice.bsky.social",
                contributorActor: actor
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.blueskyActorProfileCache = BlueskyActorProfileCacheClient(
                cachedProfile: { _ in nil },
                refreshProfile: { requestedActor in
                    await requestRecorder.record(requestedActor)
                    return profile
                },
                refreshProfileIfNeeded: { requestedActor, _, _ in
                    await requestRecorder.record(requestedActor)
                    try await database.write { db in
                        try BlueskyActorProfile.insert { profile }
                            .execute(db)
                        try BlueskyActorProfileCacheEntry.insert {
                            BlueskyActorProfileCacheEntry(
                                actor: requestedActor,
                                did: profile.did,
                                lastFetchedAt: Date(timeIntervalSince1970: 1_000),
                                lastFetchAttemptAt: Date(timeIntervalSince1970: 1_000)
                            )
                        }
                        .execute(db)
                    }
                    return profile
                }
            )
        } operation: {
            Store(initialState: ContributorDetail.State(contributorID: contributorID, eventID: eventID)) {
                ContributorDetail()
            }
        }

        try await waitForBlueskyProfile(in: store)

        #expect(await requestRecorder.actors == [actor.description])
        #expect(store.contributorActor == actor)
        #expect(store.usesActorProfileAsPrimary)
        let contributorProfile = try #require(store.profile)
        #expect(contributorProfile.name == "Alice Example")
        #expect(contributorProfile.bio == "ATProto builder")
        #expect(contributorProfile.handle == "alice.bsky.social")
        #expect(contributorProfile.artworkAsset?.url?.absoluteString == "https://cdn.example/alice-avatar.jpg")
        #expect(contributorProfile.artworkCacheContext == nil)
    }

    @Test
    func explicitContributorDisplayDoesNotGetOverwrittenByBlueskyProfileData() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let actor = try #require(OMERecord.Contributor.Actor("alice.bsky.social"))
        let contributorID = contributorLocalID("speaker-1")
        let date = try #require(LocalDate("2026-08-07"))
        let explicitImageURL = try #require(URL(string: "https://example.com/explicit.jpg"))
        let profile = BlueskyActorProfile(
            did: "did:plc:alice123",
            handle: "alice.bsky.social",
            displayName: "Alice Example",
            description: "Bluesky bio",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg"),
            banner: URL(string: "https://cdn.example/alice-banner.jpg")
        )
        let requestRecorder = BlueskyProfileRequestRecorder()
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "day-1", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: eventID,
                contributorID: "speaker-1",
                name: "Explicit Alice",
                bio: "OME bio",
                imageURL: explicitImageURL
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "day-1",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                contributorID: "speaker-1",
                contributorActor: actor
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.blueskyActorProfileCache = BlueskyActorProfileCacheClient(
                cachedProfile: { _ in nil },
                refreshProfile: { requestedActor in
                    await requestRecorder.record(requestedActor)
                    return profile
                },
                refreshProfileIfNeeded: { requestedActor, _, _ in
                    await requestRecorder.record(requestedActor)
                    try await database.write { db in
                        try BlueskyActorProfile.insert { profile }
                            .execute(db)
                        try BlueskyActorProfileCacheEntry.insert {
                            BlueskyActorProfileCacheEntry(
                                actor: requestedActor,
                                did: profile.did,
                                lastFetchedAt: Date(timeIntervalSince1970: 1_000),
                                lastFetchAttemptAt: Date(timeIntervalSince1970: 1_000)
                            )
                        }
                        .execute(db)
                    }
                    return profile
                }
            )
        } operation: {
            Store(initialState: ContributorDetail.State(contributorID: contributorID, eventID: eventID)) {
                ContributorDetail()
            }
        }
        try await waitForBlueskyProfile(in: store)

        #expect(await requestRecorder.actors == [actor.description])
        #expect(store.contributorActor == actor)
        #expect(!store.usesActorProfileAsPrimary)
        let contributorProfile = try #require(store.profile)
        #expect(contributorProfile.name == "Explicit Alice")
        #expect(contributorProfile.handle == "alice.bsky.social")
        #expect(contributorProfile.bio == "OME bio")
        #expect(contributorProfile.artworkAsset?.url == explicitImageURL)
        #expect(contributorProfile.artworkCacheContext == LocalImageCacheContext(contributorID: contributorProfile.contributor.id))
    }

    @Test
    func createContributorSavesNewContributor() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = EditContributor.State(eventID: eventID)
            state.form.value.name = " New Contributor "
            state.form.value.kind = "speaker"
            state.form.value.bio = " Bio "

            return TestStore(initialState: state) {
                EditContributor()
            }
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let contributorID = contributorLocalID("new-contributor")
        let contributor = try await database.read { db in
            try #require(
                try ContributorDetail.contributorQuery(
                    contributorID: contributorID,
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }

        #expect(contributor.name == "New Contributor")
        #expect(contributor.kind?.rawValue == "speaker")
        #expect(contributor.bio == "Bio")
    }

    @Test
    func stageDetailEditButtonOpensEventStageEditor() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let stageID = stageLocalID("meadow")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: StageDetail.State(stageID: stageID, eventID: eventID)) {
                StageDetail()
            }
        }

        store.send(.editButtonTapped)

        #expect(store.state.destination?.editStage?.stageID == Optional(stageID))
        #expect(store.state.destination?.editStage?.eventID == eventID)
    }

    @Test
    func editStageSavesEventSnapshotChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let stageID = stageLocalID("meadow")
        let lineupID = contributorLocalID("artist-1")
        let posterURL = try #require(URL(string: "https://example.com/poster.png"))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(
                db,
                eventID: eventID,
                stageID: "meadow",
                name: "Old Meadow",
                posterImageURL: posterURL,
                lineup: [lineupID]
            )
        }
        let existingStage = try await database.read { db in
            try #require(
                try StageDetail.stageQuery(
                    stageID: stageID,
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            var state = EditStage.State(stageID: stageID, eventID: eventID)
            state.hasLoadedDraft = true
            state.draft = OMERecord.Stage.Draft(
                id: existingStage.id,
                name: " New Meadow ",
                color: existingStage.color,
                category: existingStage.category,
                sortIndex: existingStage.sortIndex,
                images: existingStage.images,
                systemIconName: existingStage.systemIconName,
                iconShortCode: existingStage.iconShortCode,
                lineup: existingStage.lineup
            )
            state.category = " workshop "
            state.sortIndex = " 7 "
            state.colorHex = " #AABBCC "
            state.systemIconName = "sparkles"
            state.iconShortCode = " MD "
            state.logoURL = "https://example.com/logo.png"
            state.heroImageURL = "https://example.com/hero.png"

            return TestStore(initialState: state) {
                EditStage()
            }
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let stage = try await database.read { db in
            try #require(
                try StageDetail.stageQuery(
                    stageID: stageID,
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }

        #expect(stage.name == "New Meadow")
        #expect(stage.category == OMERecord.Stage.Category("workshop"))
        #expect(stage.sortIndex == 7)
        #expect(stage.color.rawValue == 0xAABBCC)
        #expect(stage.systemIconName == "sparkles")
        #expect(stage.iconShortCode == "MD")
        #expect(stage.iconImageURL?.absoluteString == "https://example.com/logo.png")
        #expect(stage.imageURL?.absoluteString == "https://example.com/hero.png")
        #expect(stage.posterImageURL?.absoluteString == "https://example.com/poster.png")
        #expect(stage.lineup == [lineupID])
    }

    @Test
    func stagesViewerAddButtonOpensCreateStageEditor() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: StagesViewer.State(eventID: eventID)) {
                StagesViewer()
            }
        }

        store.send(.addButtonTapped)

        #expect(store.state.destination?.createStage?.stageID == nil)
        #expect(store.state.destination?.createStage?.eventID == eventID)
    }

    @Test
    func createStageSavesNewEventStage() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(db, eventID: eventID, stageID: "new-meadow", name: "Old Meadow")
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            var state = EditStage.State(eventID: eventID)
            state.draft.name = " New Meadow "
            state.category = " workshop "
            state.sortIndex = " 4 "
            state.colorHex = "#123456"
            state.systemIconName = "music.mic"
            state.iconShortCode = "NM"
            state.logoURL = "https://example.com/new-logo.png"
            state.heroImageURL = "https://example.com/new-hero.png"

            return TestStore(initialState: state) {
                EditStage()
            }
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let stageID = stageLocalID("new-meadow-2")
        let stage = try await database.read { db in
            try #require(
                try StageDetail.stageQuery(
                    stageID: stageID,
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }

        #expect(stage.name == "New Meadow")
        #expect(stage.category == OMERecord.Stage.Category("workshop"))
        #expect(stage.sortIndex == 4)
        #expect(stage.color.rawValue == 0x123456)
        #expect(stage.systemIconName == "music.mic")
        #expect(stage.iconShortCode == "NM")
        #expect(stage.iconImageURL?.absoluteString == "https://example.com/new-logo.png")
        #expect(stage.imageURL?.absoluteString == "https://example.com/new-hero.png")
        #expect(stage.posterImageURL == nil)
    }

    @Test
    func stagesViewerDeleteRemovesEventStage() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let stageID = stageLocalID("meadow")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: StagesViewer.State(eventID: eventID)) {
                StagesViewer()
            }
        }

        await store.send(.deleteStages([stageID]))?.value

        #expect(store.state.errorMessage == nil)

        let stage = try await database.read { db in
            try StageDetail.stageQuery(
                stageID: stageID,
                eventID: eventID
            )
            .fetchOne(db)
        }
        #expect(stage == nil)
    }

    @Test
    func launchRestoreMountsLaunchEventViewer() async throws {
        let eventID = eventID("event-1")
        let database = try makePreparedDatabase()
        try await database.write { db in
            try AppState.update {
                $0.organizerID = #bind(eventID.organizerID)
                $0.eventID = #bind(eventID.eventID)
            }
            .execute(db)
        }

        let store = makeRootHarnessStore(database: database, eventID: eventID)
        #expect(store.state.root.launchEventViewer?.state.eventID == eventID)
        #expect(store.state.root.eventViewer == nil)
    }

    @Test
    func launchEventViewerDismissClearsSelectedEvent() async throws {
        let eventID = eventID("event-1")
        let database = try makePreparedDatabase()
        try await database.write { db in
            try AppState.update {
                $0.organizerID = #bind(eventID.organizerID)
                $0.eventID = #bind(eventID.eventID)
            }
            .execute(db)
        }

        let store = makeRootHarnessStore(database: database, eventID: eventID)
        #expect(store.state.root.launchEventViewer?.state.eventID == eventID)

        await store.modify {
            $0.root.launchEventViewer = nil
        }?.value

        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }
        #expect(appState?.selectedEventID == nil)
    }

    @Test
    func modalEventViewerDismissClearsSelectedEvent() async throws {
        let eventID = eventID("event-1")
        let database = try makePreparedDatabase()
        let store = makeRootHarnessStore(database: database, eventID: eventID)

        store.send(.root(.handleNavigationRequest(.event(eventID, nil))))
        #expect(store.state.root.eventViewer?.state.eventID == eventID)
        #expect(store.state.root.launchEventViewer == nil)

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

    private func makeCoreDatabase() throws -> any DatabaseWriter {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OMERecord.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }

    private func makeSourceDetailStore(
        sourceBaselineID: SourceBaselineRecord.ID,
        database: any DatabaseWriter
    ) throws -> TestStore<SourceDetail> {
        return withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: SourceDetail.State(sourceBaselineID: sourceBaselineID)) {
                SourceDetail()
            }
        }
    }

    private nonisolated static func insertOrganizer(
        _ db: Database,
        id organizerID: OMERecord.Organizer.ID
    ) throws {
        try OMERecord.Organizer.insert {
            OMERecord.Organizer.Draft(id: organizerID)
        }
        .execute(db)
    }

    private nonisolated static func insertEvent(
        _ db: Database,
        id eventID: OMERecord.Event.ID,
        name: String,
        startDate: LocalDate? = nil,
        endDate: LocalDate? = nil,
        timeZone: TimeZone = .current
    ) throws {
        try OMERecord.Event.insert {
            CreateEvent.makeEventDraft(
                id: eventID,
                name: name,
                startDate: startDate,
                endDate: endDate,
                timeZone: timeZone
            )
        }
        .execute(db)
    }

    private nonisolated static func insertEventOrganizer(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        organizerID: OMERecord.Organizer.ID
    ) throws {
        try OMERecord.EventOrganizer.insert {
            OMERecord.EventOrganizer.Draft(
                id: .init(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    eventOrganizerID: organizerID
                )
            )
        }
        .execute(db)
    }

    private nonisolated static func insertCalendar(
        _ db: Database,
        id calendarID: OMERecord.Calendar.ID,
        name: String,
        description: String? = nil,
        images: [OMERecord.ImageAsset]? = nil
    ) throws {
        try OMERecord.Calendar.insert {
            OMERecord.Calendar.Draft(
                id: calendarID,
                name: name,
                description: description,
                images: images
            )
        }
        .execute(db)
    }

    private nonisolated static func insertCalendarEntry(
        _ db: Database,
        id entryID: OMERecord.CalendarEntry.ID,
        event: OMERecord.Event.Reference,
        createdAt: Date,
        note: String? = nil,
        pinned: Bool = false
    ) throws {
        try OMERecord.CalendarEntry.insert {
            OMERecord.CalendarEntry.Draft(
                id: entryID,
                event: event,
                createdAt: createdAt,
                note: note,
                pinned: pinned
            )
        }
        .execute(db)
    }

    private nonisolated static func insertSourceBaseline(
        _ db: Database,
        sourceProvenance: OMERecord.SourceDatabaseInsertion.SourceProvenance,
        databaseFileName: String = "baseline.sqlite",
        importedAt: Date
    ) throws {
        try SourceBaselineRecord.insert {
            SourceBaselineRecord(
                source: sourceProvenance,
                databaseFileName: databaseFileName,
                importedAt: importedAt
            )
        } onConflict: {
            $0.id
        }
        .execute(db)
    }

    private nonisolated static func insertEventSourceProvenance(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        sourceProvenance: OMERecord.SourceDatabaseInsertion.SourceProvenance
    ) throws {
        try EventSourceProvenanceRecord.insert {
            EventSourceProvenanceRecord(
                id: eventID,
                sourceBaselineID: SourceBaselineRecord.ID(source: sourceProvenance),
                sourceKind: sourceProvenance.kind,
                sourceReference: sourceProvenance.reference,
                ref: sourceProvenance.ref,
                eventIDOrigin: .inferred,
                sourceEventDirectory: eventID.eventID.rawValue.rawValue
            )
        }
        .execute(db)
    }

    private nonisolated static func insertContributor(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        contributorID: String,
        name: String,
        bio: String? = nil,
        imageURL: URL? = nil,
        logoURL: URL? = nil,
        kind: OMERecord.Contributor.Kind? = nil,
        links: [ExternalPlatform.Link]? = nil
    ) throws {
        try OMERecord.Contributor.insert {
            OMERecord.Contributor.Draft(
                id: OMERecord.Contributor.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    contributorID: contributorLocalID(contributorID)
                ),
                name: name,
                bio: bio,
                imageURL: imageURL,
                logoURL: logoURL,
                kind: kind,
                links: links
            )
        }
        .execute(db)
    }

    private nonisolated static func insertPerformance(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        performanceID: String,
        stageID: String,
        scheduleID: String,
        startTime: Date,
        endTime: Date,
        title: String,
        description: String? = nil,
        recordings: [ExternalPlatform.Asset] = []
    ) throws {
        try OMERecord.Performance.insert {
            OMERecord.Performance.Draft(
                id: OMERecord.Performance.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    performanceID: performanceLocalID(performanceID)
                ),
                stageID: stageLocalID(stageID),
                scheduleID: scheduleLocalID(scheduleID),
                startTime: startTime,
                endTime: endTime,
                title: title,
                description: description,
                recordings: recordings
            )
        }
        .execute(db)
    }

    private nonisolated static func insertPerformanceContributor(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        performanceID: String,
        contributorID: String,
        contributorActor: OMERecord.Contributor.Actor? = nil
    ) throws {
        try OMERecord.Performance.Contributors.insert {
            OMERecord.Performance.Contributors.Draft(
                organizerID: eventID.organizerID,
                eventID: eventID.eventID,
                performanceID: performanceLocalID(performanceID),
                contributorID: contributorLocalID(contributorID),
                anonymousName: nil,
                contributorActor: contributorActor
            )
        }
        .execute(db)
    }

    private nonisolated static func insertSchedule(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        scheduleID: String,
        date: LocalDate,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        customTitle: String? = nil
    ) throws {
        try OMERecord.Schedule.insert {
            OMERecord.Schedule.Draft(
                id: OMERecord.Schedule.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    scheduleID: scheduleLocalID(scheduleID)
                ),
                date: date,
                startsAt: startsAt,
                endsAt: endsAt,
                customTitle: customTitle
            )
        }
        .execute(db)
    }

    private nonisolated static func insertStage(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        stageID: String,
        name: String,
        color: OMEColor = 0x336699,
        category: OMERecord.Stage.Category? = nil,
        sortIndex: Int? = nil,
        iconImageURL: URL? = nil,
        systemIconName: String? = nil,
        iconShortCode: String? = nil,
        imageURL: URL? = nil,
        posterImageURL: URL? = nil,
        lineup: [OMERecord.ID<OMERecord.Contributor>]? = nil
    ) throws {
        try OMERecord.Stage.insert {
            OMERecord.Stage.Draft(
                id: OMERecord.Stage.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    stageID: stageLocalID(stageID)
                ),
                name: name,
                color: color,
                category: category,
                sortIndex: sortIndex,
                iconImageURL: iconImageURL,
                systemIconName: systemIconName,
                iconShortCode: iconShortCode,
                imageURL: imageURL,
                posterImageURL: posterImageURL,
                lineup: lineup
            )
        }
        .execute(db)
    }

    private func waitForBlueskyProfile(
        in store: StoreOf<ContributorDetail>
    ) async throws {
        for _ in 0..<100 {
            if store.profile?.handle != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(store.profile?.handle != nil)
    }

    private func waitForContributorListBlueskyProfile(
        in store: StoreOf<ContributorsViewer>,
        contributorID: OMERecord.ID<OMERecord.Contributor>
    ) async throws {
        for _ in 0..<100 {
            if store.contributorRows.first(where: { $0.contributorID == contributorID })?
                .profile.handle != nil {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(
            store.contributorRows.first(where: { $0.contributorID == contributorID })?
                .profile.handle != nil
        )
    }

    private func makeRootHarnessStore(
        database: any DatabaseWriter,
        eventID: OMERecord.Event.ID = eventID("event-1")
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
        eventID: OMERecord.Event.ID = eventID("event-1"),
        defaultEventID: OMERecord.Event.ID? = nil,
        database: (any DatabaseWriter)? = nil
    ) throws -> TestStore<EventViewerHarness> {
        let database = try database ?? makePreparedDatabase()
        return withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = defaultEventID ?? eventID
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
        Scope(\.root, action: \.root) {
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
        Scope(\.myEvents, action: \.myEvents) {
            MyEvents()
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}

@Feature
private struct SourceDetailHarness {
    struct State {
        init(sourceBaselineID: SourceBaselineRecord.ID) {
            self.sourceDetail = SourceDetail.State(sourceBaselineID: sourceBaselineID)
        }

        var lastRequest: NavigationRequest?
        @DebugSnapshotIgnored
        var sourceDetail: SourceDetail.State
    }

    enum Action {
        case sourceDetail(SourceDetail.Action)
    }

    var body: some Feature {
        Scope(\.sourceDetail, action: \.sourceDetail) {
            SourceDetail()
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}

@Feature
private struct EventInfoRefreshHarness {
    struct State {
        init(eventID: OMERecord.Event.ID) {
            self.eventInfo = EventInfoViewer.State(eventID: eventID)
        }

        @DebugSnapshotIgnored
        var eventInfo: EventInfoViewer.State
        var lastRefreshRequest: SourceDataRefreshRequest?
    }

    enum Action {
        case eventInfo(EventInfoViewer.Action)
    }

    var body: some Feature {
        Scope(\.eventInfo, action: \.eventInfo) {
            EventInfoViewer()
        }
        .onEvent(SourceDataRefreshRequested.self) { request, state in
            state.lastRefreshRequest = request
        }
    }
}

@Feature
private struct EventViewerHarness {
    struct State {
        init(eventID: OMERecord.Event.ID = eventID("event-1")) {
            self.eventViewer = EventViewer.State.route(
                eventID: eventID,
                target: nil
            )
        }

        var lastRequest: NavigationRequest?
        @DebugSnapshotIgnored
        var eventViewer: EventViewer.State

        var eventInfoViewer: Spawn<EventInfoViewer> {
            get { eventViewer.eventInfoViewer! }
            set { eventViewer.eventInfoViewer = newValue }
        }

        var editEvent: Spawn<EditEvent> {
            get { eventViewer.editEvent! }
            set { eventViewer.editEvent = newValue }
        }
    }

    enum Action {
        case eventViewer(EventViewer.Action)
    }

    var body: some Feature {
        Scope(\.eventViewer, action: \.eventViewer) {
            EventViewer()
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}
