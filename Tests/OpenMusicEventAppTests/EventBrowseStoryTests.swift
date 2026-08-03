import ATProto
import ComposableArchitecture2
import ComposableCalendarEvents
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import OpenMusicEventApp
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventViewers
import SQLiteData
import Testing

struct EventBrowseStoryTests {
    @Test
    func `an empty app still browses the temporary OME catalog`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let client = CalendarEventsClient.openMusicEventAndAtmo(database: database)

        // Browse is useful before the attendee has installed an event.
        let page = try await client.browse(
            CalendarEvent.PageRequest(collection: OME.Event.nsid)
        )
        expectNoDifference(
            Set(page.events.map(\.name)),
            [
                "Daniel Donato’s Cosmic Country",
                "Montana Folk Festival 2026",
                "Shambhala 2026",
                "Wicked Woods 2026",
            ]
        )

        // The same URI hydrates detail without inventing a second identity.
        let wickedWoods = try #require(
            page.events.first { $0.name == "Wicked Woods 2026" }
        )
        let detail = try await client.event(wickedWoods.uri)
        expectNoDifference(detail.uri, wickedWoods.uri)
        expectNoDifference(detail.name, wickedWoods.name)
    }

    @Test
    func `browse starts with happening now and keeps later events upcoming`() throws {
        let organizerID = try #require(DID("did:plc:organizer"))
        let happeningNow = try event(
            uri: "at://did:plc:organizer/app.openmusicevent.event/happening",
            name: "Happening Now",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 100),
            endsAt: Date(timeIntervalSince1970: 300),
            collection: OME.Event.nsid
        )
        let upcoming = try event(
            uri: "at://did:plc:organizer/app.openmusicevent.event/upcoming",
            name: "Upcoming",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 400),
            collection: OME.Event.nsid
        )
        let past = try event(
            uri: "at://did:plc:organizer/app.openmusicevent.event/past",
            name: "Past",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 10),
            endsAt: Date(timeIntervalSince1970: 90),
            collection: OME.Event.nsid
        )

        let browse = Browse.State(
            events: [upcoming, past, happeningNow],
            referenceDate: Date(timeIntervalSince1970: 200)
        )

        expectNoDifference(browse.happeningNowEvents.map(\.name), ["Happening Now"])
        expectNoDifference(browse.upcomingEvents.map(\.name), ["Upcoming"])
        expectNoDifference(browse.pastEvents.map(\.name), ["Past"])
    }

    @Test @MainActor
    func `the browser opens on OME and can switch to community calendar events`() async throws {
        let organizerID = try #require(DID("did:plc:organizer"))
        let omeEvent = try event(
            uri: "at://did:plc:organizer/app.openmusicevent.event/festival",
            name: "Summer Festival",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 100),
            collection: OME.Event.nsid
        )
        let calendarEvent = try event(
            uri: "at://did:plc:organizer/community.lexicon.calendar.event/dance",
            name: "Community Dance",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 200),
            collection: "community.lexicon.calendar.event"
        )

        await withDependencies {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.calendarEvents = CalendarEventsClient(
                browse: { request in
                    switch request.collection {
                    case OME.Event.nsid:
                        CalendarEvent.Page(events: [omeEvent])
                    case "community.lexicon.calendar.event":
                        CalendarEvent.Page(events: [calendarEvent])
                    default:
                        throw CalendarEventsClientError.collectionNotServed(request.collection)
                    }
                },
                event: { _ in throw CalendarEventsClientError.unimplemented },
                organizer: { _ in throw CalendarEventsClientError.unimplemented }
            )
        } operation: {
            let store = Store(initialState: Browse.State()) {
                Browse()
            }

            // Launching the generic app asks for the OME catalog first.
            await store.send(.task)?.value
            expectNoDifference(store.catalog, .openMusicEvent)
            expectNoDifference(store.visibleEvents.map(\.name), ["Summer Festival"])

            // The catalog control swaps the provider without changing the browse feature.
            await store.send(.catalogSelected(.communityCalendar))?.value
            expectNoDifference(store.catalog, .communityCalendar)
            expectNoDifference(store.visibleEvents.map(\.name), ["Community Dance"])

            // Search and date selection are ordinary in-memory browse state.
            store.send(.searchTextChanged("missing"))
            #expect(store.visibleEvents.isEmpty)
            store.send(.searchTextChanged("dance"))
            expectNoDifference(store.visibleEvents.map(\.name), ["Community Dance"])
            store.send(.daySelected(calendarEvent.localStartDay))
            expectNoDifference(store.selectedDay, calendarEvent.localStartDay)
        }
    }

    @Test @MainActor
    func `choosing Going is stored and restored for the signed in attendee`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let attendeeDID = try #require(DID("did:plc:attendee"))
        let organizerID = try #require(DID("did:plc:organizer"))
        let calendarEvent = try event(
            uri: "at://did:plc:organizer/community.lexicon.calendar.event/dance",
            name: "Community Dance",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 200),
            collection: "community.lexicon.calendar.event"
        )
        let savedAt = Date(timeIntervalSince1970: 300)

        try await withDependencies {
            $0.calendarEvents = CalendarEventsClient(
                browse: { _ in throw CalendarEventsClientError.unimplemented },
                event: { _ in calendarEvent },
                organizer: { _ in throw CalendarEventsClientError.unimplemented }
            )
            $0.date = .constant(savedAt)
            $0.defaultDatabase = database
            $0.getSelectedOAuthSessionID = { Atmosphere.Account.ID(attendeeDID) }
        } operation: {
            let detail = Store(
                initialState: EventBrowseDetail.State(event: calendarEvent)
            ) {
                EventBrowseDetail()
            }

            // The attendee RSVPs from the event detail page.
            await detail.send(.rsvpButtonTapped(.going))?.value
            expectNoDifference(detail.rsvpStatus, .going)

            let consumer = EventRSVP.Consumer(accountDID: attendeeDID)
            let persisted = try await database.read { db in
                try EventRSVP.forEvent(calendarEvent.uri, consumer: consumer).fetchOne(db)
            }
            expectNoDifference(persisted?.status, .going)
            expectNoDifference(persisted?.createdAt, savedAt)

            // Reopening the detail page restores the same account's local choice.
            let reopenedDetail = Store(
                initialState: EventBrowseDetail.State(event: calendarEvent)
            ) {
                EventBrowseDetail()
            }
            await reopenedDetail.send(.task)?.value
            expectNoDifference(reopenedDetail.rsvpStatus, .going)
        }
    }

    @Test @MainActor
    func `opening a community event hydrates its detail using the same record URI`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let organizerID = try #require(DID("did:plc:organizer"))
        let summary = try event(
            uri: "at://did:plc:organizer/community.lexicon.calendar.event/dance",
            name: "Community Dance",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 200),
            collection: "community.lexicon.calendar.event"
        )
        var hydrated = summary
        hydrated.description = "An evening of music and movement."
        let hydratedEvent = hydrated

        await withDependencies {
            $0.calendarEvents = CalendarEventsClient(
                browse: { _ in throw CalendarEventsClientError.unimplemented },
                event: { eventURI in
                    #expect(eventURI == summary.uri)
                    return hydratedEvent
                },
                organizer: { _ in throw CalendarEventsClientError.unimplemented }
            )
            $0.defaultDatabase = database
            $0.getSelectedOAuthSessionID = { nil }
        } operation: {
            let detail = Store(initialState: EventBrowseDetail.State(event: summary)) {
                EventBrowseDetail()
            }

            // The detail page asks for one record and keeps the browse identity intact.
            await detail.send(.task)?.value
            expectNoDifference(detail.event.uri, summary.uri)
            expectNoDifference(
                detail.event.description,
                "An evening of music and movement."
            )
        }
    }

    @Test @MainActor
    func `entering an OME event installs it before opening the event viewer`() async throws {
        let organizerID = try #require(DID("did:plc:organizer"))
        let eventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: OME.ID<OME.Event>(rawValue: "festival")
        )
        let omeEvent = try event(
            uri: "at://did:plc:organizer/app.openmusicevent.event/festival",
            name: "Summer Festival",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 100),
            collection: OME.Event.nsid
        )

        await withDependencies {
            $0.omeEventInstallation = OMEEventInstallationClient { eventURI in
                #expect(eventURI == omeEvent.uri)
                return eventID
            }
        } operation: {
            let store = Store(
                initialState: EnterEventStory.State(event: omeEvent)
            ) {
                EnterEventStory()
            }

            // Entering installs exactly the selected URI, then uses the existing viewer route.
            await store.send(.detail(.enterEventButtonTapped))?.value
            expectNoDifference(store.lastRequest, .event(eventID, nil))
            #expect(!store.detail.isEnteringEvent)
        }
    }

    func event(
        uri: String,
        name: String,
        organizerID: DID,
        startsAt: Date,
        endsAt: Date? = nil,
        collection: ATProto.NSID
    ) throws -> CalendarEvent {
        CalendarEvent(
            uri: try #require(ATProto.URI(uri)),
            name: name,
            startsAt: startsAt,
            endsAt: endsAt,
            organizer: CalendarEvent.Organizer(id: organizerID),
            source: CalendarEvent.Source(collection: collection),
            timeZoneIdentifier: "America/Denver"
        )
    }
}

@Feature
struct EnterEventStory {
    struct State {
        init(event: CalendarEvent) {
            self.detail = EventBrowseDetail.State(event: event)
        }

        var detail: EventBrowseDetail.State
        var lastRequest: NavigationRequest?
    }

    enum Action {
        case detail(EventBrowseDetail.Action)
    }

    var body: some Feature {
        Scope(\.detail, action: \.detail) {
            EventBrowseDetail()
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}
