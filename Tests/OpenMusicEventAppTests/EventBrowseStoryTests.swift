#if os(macOS)
import ATProto
import ATProtoOAuth
import Bluesky
import ComposableArchitecture2
import ComposableCalendarEvents
import ComposableNotifications
import CustomDump
import Dependencies
import DependenciesTestSupport
import ErrorHandling
import Foundation
import HTTPClient
import HTTPTypes
import HummingbirdTesting
import IssueReporting
@testable import OpenMusicEventApp
import OpenMusicEventAppEventViewer
import OpenMusicEventAppViewServer
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventLexicon
import OpenMusicEventViewers
import OpenMusicEventWhiteLabel
import Sharing
import SQLiteData
import Synchronization
import ComposableAtmosphere
import Testing

private struct UnexpectedEventBrowseGraphLoad: Error {}

@Suite(.serialized)
struct EventBrowseStoryTests {
    @Test @MainActor
    func `an empty app browses canonical AppView records and refreshes after another record is indexed`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let appViewDatabase = try SQLiteData.defaultDatabase()
        let appViewStore = try OpenMusicEventAppViewStore(database: appViewDatabase)
        let firstID = try #require(Event.ID(
            "at://did:plc:5df2u7ief6m6tn77jznicxob/events.openmusic.event/3mrdbziccpcah"
        ))
        let secondID = try #require(Event.ID(
            "at://did:plc:gothnight/events.openmusic.event/3mrdbziccpcaq"
        ))
        let firstEvent = try Event(
            id: firstID,
            name: "Wicked Woods 2026",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        let secondEvent = try Event(
            id: secondID,
            name: "Goth Night",
            createdAt: "2026-09-02T12:00:00Z",
            timeZone: .gmt
        )
        try await appViewDatabase.write { db in
            try Event.insert { firstEvent }.execute(db)
        }

        let appViewRequests = TestMutex<[String]>([])
        let app = try OpenMusicEventAppViewServer.application(
            configuration: AppViewConfiguration(port: 0),
            store: appViewStore
        )
        let getEventsRequestCount: @Sendable () -> Int = {
            appViewRequests.withLock {
                $0.count { $0.hasPrefix("/xrpc/events.openmusic.getEvents") }
            }
        }
        try await app.test(.router) { server in
            try await withDependencies {
                $0.context = .test
                $0.date = .constant(Date(timeIntervalSince1970: 0))
                OME.prepareDependencies(&$0, database: database)
                $0.notificationsClient = NotificationsClient(
                    registerDestination: { _ in },
                    replaceSubscriptions: { _ in },
                    synchronize: {},
                    signals: { AsyncStream { $0.finish() } }
                )
                $0[XRPC.Client.self] = .liveValue
                $0.httpClient = .liveValue
                $0.requestInterceptors = []
                $0.dataForURL = { request, body in
                    #expect(body == nil)
                    let url = try #require(request.url)
                    let components = try #require(
                        URLComponents(url: url, resolvingAgainstBaseURL: false)
                    )
                    let uri = components.percentEncodedQuery.map {
                        "\(components.percentEncodedPath)?\($0)"
                    } ?? components.percentEncodedPath
                    appViewRequests.withLock { $0.append(uri) }
                    let response = try await server.execute(
                        uri: uri,
                        method: request.method,
                        headers: request.headerFields
                    )
                    return (Data(response.body.readableBytesView), response.head)
                }
            } operation: {
                let store = await MainActor.run {
                    Store(initialState: OpenMusicEventAppRoot.State()) {
                        OpenMusicEventAppRoot()
                    }
                }
                let browse = await MainActor.run {
                    store.scope(\.browser).spawn(\.browse)
                }

                let firstLoad = await MainActor.run { browse.send(.task) }
                await firstLoad?.value
                await MainActor.run {
                    expectNoDifference(browse.catalog, .openMusicEvent)
                    expectNoDifference(browse.events.map(\.uri), [firstID])
                    expectNoDifference(browse.events.map(\.name), ["Wicked Woods 2026"])
                    expectNoDifference(browse.errorMessage, nil)
                    expectNoDifference(getEventsRequestCount(), 1)
                }

                try await appViewDatabase.write { db in
                    try Event.insert { secondEvent }.execute(db)
                }
                let refresh = await MainActor.run { browse.send(.didPullToRefresh) }
                await refresh?.value
                await MainActor.run {
                    expectNoDifference(
                        Set(browse.events.map(\.uri)),
                        Set([firstID, secondID])
                    )
                    expectNoDifference(getEventsRequestCount(), 2)
                    expectNoDifference(browse.errorMessage, nil)
                }

                let detail = try await CalendarEventsClient
                    .openMusicEventAndAtmo()
                    .event(firstID)
                expectNoDifference(detail.name, "Wicked Woods 2026")
                expectNoDifference(detail.uri, firstID)
                #expect(
                    appViewRequests.withLock { $0.last }?.hasPrefix(
                        "/xrpc/events.openmusic.getEvent?uri="
                    ) == true
                )
            }
        }
    }

    @Test @MainActor
    func `resuming the app retains an installed canonical event and its local edit`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        BlueskyActorCacheMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let eventID = try #require(Event.ID(
            "at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcah"
        ))
        let event = try Event(
            id: eventID,
            name: "Wicked Woods 2026 — Local edit",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        try await database.write { db in
            try Event.insert { event }.execute(db)
            try InstalledEvent.insert { InstalledEvent(id: eventID) }.execute(db)
        }

        let storage = OAuthSessionStorage(
            sessionStore: Shared(value: OAuth.SessionStore()),
            authFailureMessage: Shared(value: nil),
            selectedSessionID: Shared(value: nil)
        )
        let store = withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database)
            $0.notificationsClient = NotificationsClient(
                registerDestination: { _ in },
                replaceSubscriptions: { _ in },
                synchronize: {},
                signals: { AsyncStream { $0.finish() } }
            )
        } operation: {
            TestStore(
                initialState: OpenMusicEventApp.State(
                    content: OpenMusicEventApplication.State(storage: storage) {
                        OpenMusicEventAppRoot.State()
                    }
                )
            ) {
                OpenMusicEventApp(
                    eventTrigger:
                        \OpenMusicEventApplication.State.content.appDelegateEvent,
                    notificationDestinationTrigger:
                        \OpenMusicEventApplication.State.content.notificationDestination,
                    notificationEventTrigger:
                        \OpenMusicEventApplication.State.content.notificationEvent
                ) {
                    OpenMusicEventApplication(storage: storage) {
                        OpenMusicEventAppRoot()
                    }
                }
            }
        }

        await store.send(.lifecycle(.launched))?.value
        await store.send(.lifecycle(.resumed))?.value
        let saved = try await database.read { db in
            (
                try Event.find(eventID).fetchOne(db)?.name,
                try InstalledEvent.find(eventID).fetchOne(db)?.id
            )
        }
        expectNoDifference(saved.0, "Wicked Woods 2026 — Local edit")
        expectNoDifference(saved.1, eventID)

        await store.dismount()
    }

    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @Test(.tcaExhaustivity(.off)) @MainActor
    func `an installed event publishes its notification subscription before it is opened`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        BlueskyActorCacheMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let eventID = try #require(Event.ID(
            "at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcah"
        ))
        let event = try Event(
            id: eventID,
            name: "Wicked Woods 2026",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        try await database.write { database in
            try Event.insert { event }.execute(database)
            try InstalledEvent.insert { InstalledEvent(id: eventID) }.execute(database)
        }

        let expectedSubscription = NotificationSubscription(
            sourceID: .init(rawValue: eventID.description)
        )
        let (replacements, replacementContinuation) =
            AsyncStream<Set<NotificationSubscription>>.makeStream()
        defer { replacementContinuation.finish() }

        await withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.uuid = .incrementing
            $0.defaultDatabase = database
            $0.notificationsClient = NotificationsClient(
                registerDestination: { _ in },
                replaceSubscriptions: { replacementContinuation.yield($0) },
                synchronize: {},
                signals: { AsyncStream { $0.finish() } }
            )
        } operation: {
            var replacementIterator = replacements.makeAsyncIterator()
            let store = await TestStoreActor(
                initialState: OpenMusicEventAppRoot.State(
                    selectedEventIDAtLaunch: eventID
                )
            ) {
                OpenMusicEventAppRoot()
            }

            let subscriptions = await replacementIterator.next()
            expectNoDifference(subscriptions, Optional(Set([expectedSubscription])))
            await store.dismount()
        }
    }

    @Test @MainActor
    func `a canonical record update refreshes the mounted event without remounting it`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        BlueskyActorCacheMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let eventID = try #require(Event.ID(
            "at://did:plc:5df2u7ief6m6tn77jznicxob/events.openmusic.event/3mrdbziccpcah"
        ))
        var event = try Event(
            id: eventID,
            name: "Wicked Woods 2026",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        let initialEvent = event
        try await database.write { db in
            try Event.insert { initialEvent }.execute(db)
            try InstalledEvent.insert { InstalledEvent(id: eventID) }.execute(db)
        }

        try await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_786_000_000))
        } operation: {
            let store = Store(initialState: EventViewer.State(eventID: eventID)) {
                EventViewer()
            }
            let mountedID = store.id
            let selectedFeature = store.selectedFeature
            expectNoDifference(store.event?.name, "Wicked Woods 2026")

            event.name = "Wicked Woods 2026 — Updated"
            let updatedEvent = event
            try await database.write { db in
                try Event.upsert { updatedEvent }.execute(db)
            }
            await waitForEventBrowseObservation {
                store.event?.name == "Wicked Woods 2026 — Updated"
            }

            expectNoDifference(store.id, mountedID)
            expectNoDifference(store.selectedFeature, selectedFeature)
            expectNoDifference(store.event, updatedEvent)
            let installed = try await database.read { db in
                try InstalledEvent.find(eventID).fetchOne(db)
            }
            expectNoDifference(installed, InstalledEvent(id: eventID))
            withExtendedLifetime(store) {}
        }
    }

    @Test
    func `the canonical AppView client preserves pagination through XRPC`() async throws {
        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let event = try Event(
            id: eventID,
            name: "Network Festival",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        let response = try JSONEncoder().encode(Event.Page(
            events: [.init(uri: eventID, cid: nil, value: event.encodeLexicon())],
            cursor: "page-3"
        ))
        let requests = TestMutex<[HTTPRequest]>([])

        let page = try await withDependencies {
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { request, _ in
                requests.withLock { $0.append(request) }
                return response
            }
        } operation: {
            try await CalendarEventsClient
                .openMusicEventAndAtmo()
                .browse(
                    CalendarEvent.PageRequest(
                        collection: ATProto.NSID(Event.lexiconID.rawValue),
                        cursor: "page-2",
                        limit: 12
                    )
                )
        }

        let request = try #require(requests.withLock { $0.first })
        expectNoDifference(request.method, .get)
        expectNoDifference(request.url?.host(), "openmusicevent.app")
        expectNoDifference(
            request.url?.path(),
            "/xrpc/events.openmusic.getEvents"
        )
        expectNoDifference(
            Set(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
                .queryItems ?? []),
            [
                URLQueryItem(name: "cursor", value: "page-2"),
                URLQueryItem(name: "limit", value: "12"),
            ]
        )
        expectNoDifference(page.events.map(\.name), ["Network Festival"])
        expectNoDifference(page.cursor, "page-3")
        expectNoDifference(page.events.first?.uri, eventID)
    }

    @Test
    func `organizer rows use the cached actor identity instead of a DID`() throws {
        let organizerID = try #require(DID("did:plc:organizer"))
        let avatarURL = try #require(URL(string: "https://cdn.example/wicked-woods.jpg"))
        let identity = ActorIdentity(
            did: organizerID,
            handle: Atmosphere.Account.Handle(rawValue: "wickedwoods.example"),
            displayName: "Wicked Woods",
            avatar: avatarURL,
            source: .canonicalResolution
        )

        let presentation = OrganizerActorPresentation(
            organizer: CalendarEvent.Organizer(id: organizerID),
            cachedIdentity: identity
        )

        expectNoDifference(presentation.title, "Wicked Woods")
        expectNoDifference(presentation.avatarURL, avatarURL)
    }

    @Test
    func `organizer rows do not expose an uncached DID`() throws {
        let organizerID = try #require(DID("did:plc:organizer"))

        let presentation = OrganizerActorPresentation(
            organizer: CalendarEvent.Organizer(
                id: organizerID,
                handle: organizerID.description
            ),
            cachedIdentity: nil
        )

        expectNoDifference(presentation.title, "Organizer")
    }

    @Test @MainActor
    func `the calendar picker preserves the local day and can clear the filter`() throws {
        let denver = try #require(TimeZone(identifier: "America/Denver"))
        let selectedDay = CalendarEvent.Day(year: 2026, month: 8, day: 3)

        // Material stores a selected date as UTC-midnight milliseconds. Converting
        // through that representation must preserve the browser day outside UTC.
        let selectedDate = selectedDay.date(in: denver)
        let milliseconds = BrowseDatePickerConversion.datePickerMilliseconds(
            from: selectedDate,
            timeZone: denver
        )
        let materialDate = BrowseDatePickerConversion.date(
            fromDatePickerMilliseconds: milliseconds,
            timeZone: denver
        )
        expectNoDifference(
            CalendarEvent.Day(materialDate, timeZone: denver),
            selectedDay
        )

        let store = Store(initialState: Browse.State()) {
            Browse()
        }

        // Choosing a date filters Browse, and All Dates removes that filter.
        store.send(.daySelected(selectedDay))
        expectNoDifference(store.selectedDay, selectedDay)
        store.send(.daySelected(nil))
        #expect(store.selectedDay == nil)
    }

    @Test
    func `canonical Event media puts the poster first in browse artwork`() async throws {
        let eventID = try #require(Event.ID(
            "at://did:plc:artfestival/events.openmusic.event/3mrdbziccpcah"
        ))
        let posterURL = try #require(URL(string: "https://example.com/poster.jpg"))
        let heroURL = try #require(URL(string: "https://example.com/hero.jpg"))
        let iconURL = try #require(URL(string: "https://example.com/icon.png"))
        var event = try Event(
            id: eventID,
            name: "Summer Art Festival",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        let icon = OME.Image(source: .known(.url(iconURL)), role: .known(.icon(.init())))
        let hero = OME.Image(source: .known(.url(heroURL)), role: .known(.hero))
        let poster = OME.Image(source: .known(.url(posterURL)), role: .known(.poster))
        event.media = [
            .known(.image(icon)),
            .known(.image(hero)),
            .known(.image(poster)),
        ]
        let response = try JSONEncoder().encode(Event.Page(events: [
            .init(uri: eventID, cid: nil, value: event.encodeLexicon())
        ]))

        let page = try await withDependencies {
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { _, _ in response }
        } operation: {
            try await CalendarEventsClient
                .openMusicEventAndAtmo()
                .browse(CalendarEvent.PageRequest(
                    collection: ATProto.NSID(Event.lexiconID.rawValue)
                ))
        }
        let browsedEvent = try #require(page.events.first)
        expectNoDifference(browsedEvent.uri, eventID)
        expectNoDifference(
            browsedEvent.artworkSources.map(\.image.asset.url),
            [posterURL, heroURL, iconURL]
        )
    }

    @Test
    func `event artwork falls back through every semantic image`() throws {
        let organizerID = try #require(DID("did:plc:organizer"))
        let posterURL = try #require(URL(string: "https://example.com/poster.jpg"))
        let heroURL = try #require(URL(string: "https://example.com/hero.jpg"))
        let photoURL = try #require(URL(string: "https://example.com/photo.jpg"))
        let iconURL = try #require(URL(string: "https://example.com/icon.png"))
        let organizerURL = try #require(URL(string: "https://example.com/organizer.png"))
        let calendarEvent = CalendarEvent(
            uri: try #require(
                ATProto.URI("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")
            ),
            name: "Summer Festival",
            startsAt: nil,
            media: [
                CalendarEvent.Media(url: iconURL, role: "icon"),
                CalendarEvent.Media(url: photoURL, role: "photo"),
                CalendarEvent.Media(url: posterURL, role: "poster"),
                CalendarEvent.Media(url: heroURL, role: "hero"),
            ],
            organizer: CalendarEvent.Organizer(
                id: organizerID,
                avatarURL: organizerURL
            ),
            source: CalendarEvent.Source(collection: ATProto.NSID(Event.lexiconID.rawValue))
        )

        // The renderer tries event-specific art first and organizer identity last.
        expectNoDifference(
            calendarEvent.artworkSources.map(\.image.asset.url),
            [posterURL, heroURL, photoURL, iconURL, organizerURL]
        )
        expectNoDifference(
            calendarEvent.artworkSources.map(\.kind),
            [.primaryImage, .primaryImage, .primaryImage, .logo, .logo]
        )

        // An organization history identifies the event before trying promotional artwork.
        expectNoDifference(
            calendarEvent.organizationArtworkSources.map(\.image.asset.url),
            [iconURL, posterURL, heroURL, photoURL, organizerURL]
        )
        expectNoDifference(
            calendarEvent.organizationArtworkSources.map(\.kind),
            [.logo, .primaryImage, .primaryImage, .primaryImage, .logo]
        )
    }

    @Test
    func `browse starts with happening now and keeps later events upcoming`() throws {
        let organizerID = try #require(DID("did:plc:organizer"))
        let happeningNow = try event(
            uri: "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah",
            name: "Happening Now",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 100),
            endsAt: Date(timeIntervalSince1970: 300),
            collection: ATProto.NSID(Event.lexiconID.rawValue)
        )
        let upcoming = try event(
            uri: "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcai",
            name: "Upcoming",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 400),
            collection: ATProto.NSID(Event.lexiconID.rawValue)
        )
        let past = try event(
            uri: "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcaj",
            name: "Past",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 10),
            endsAt: Date(timeIntervalSince1970: 90),
            collection: ATProto.NSID(Event.lexiconID.rawValue)
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
    func `the browser opens on canonical Events and can switch to community calendar events`() async throws {
        let organizerID = try #require(DID("did:plc:organizer"))
        let omeEvent = try event(
            uri: "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah",
            name: "Summer Festival",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 100),
            collection: ATProto.NSID(Event.lexiconID.rawValue)
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
                    case ATProto.NSID(Event.lexiconID.rawValue):
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
    func `browse opens organization detail by organizer identity`() throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        let organizerID = try #require(DID("did:plc:organizer"))
        let currentEvent = try event(
            uri: "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah",
            name: "Current Festival",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 200),
            collection: ATProto.NSID(Event.lexiconID.rawValue)
        )
        try withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            let store = Store(
                initialState: EventBrowseDetail.State(event: currentEvent)
            ) {
                EventBrowseDetail()
            }

            store.send(.organizerButtonTapped)

            let organizationDetail = try #require(store.organizationDetail)
            expectNoDifference(organizationDetail.organizerID, organizerID)
            expectNoDifference(
                organizationDetail.collection,
                ATProto.NSID(Event.lexiconID.rawValue)
            )
            expectNoDifference(organizationDetail.events, [])
        }
    }

    @Test @MainActor
    func `organization detail opens selected event detail without entering it`() async throws {
        let organizerID = try #require(DID("did:plc:organizer"))
        let previousEvent = try event(
            uri: "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcak",
            name: "Wicked Woods 2025",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 100),
            collection: ATProto.NSID(Event.lexiconID.rawValue)
        )
        let selectedEvent = try event(
            uri: "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcam",
            name: "Wicked Woods 2026",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 200),
            collection: ATProto.NSID(Event.lexiconID.rawValue)
        )
        let organizerEvents = [previousEvent, selectedEvent]
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        let installations = TestMutex<[ATProto.URI]>([])
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.calendarEvents = CalendarEventsClient(
                browse: { _ in CalendarEvent.Page(events: organizerEvents) },
                event: { _ in selectedEvent },
                organizer: { _ in selectedEvent.organizer }
            )
            $0.eventRecords = EventRecordClient { uri in
                installations.withLock { $0.append(uri) }
                throw UnexpectedEventBrowseGraphLoad()
            }
        } operation: {
            TestStore(
                initialState: OrganizationDetailStory.State(organizerID: organizerID)
            ) {
                OrganizationDetailStory()
            }
        }

        let loadTask = store.send(.detail(.task)) {
            $0.detail.isLoading = true
        }
        await loadTask?.value
        store.expect {
            $0.detail.events = organizerEvents
            $0.detail.isLoading = false
            $0.detail.organizer = selectedEvent.organizer
        }

        expectNoDifference(
            store.detail.events.map(\.name),
            ["Wicked Woods 2025", "Wicked Woods 2026"]
        )
        #expect(store.lastRequest == nil)

        let selectionTask = store.send(.detail(.eventButtonTapped(selectedEvent.uri)))
        await selectionTask?.value

        let eventDetail = try #require(store.detail.eventDetail)
        expectNoDifference(eventDetail.event, selectedEvent)
        #expect(installations.withLock { $0 }.isEmpty)
        #expect(store.lastRequest == nil)
        await store.dismount()
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
    func enteringWickedWoodsInstallsTheCanonicalRecordGraph() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        BlueskyActorCacheMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let organizerID = try #require(DID("did:plc:5df2u7ief6m6tn77jznicxob"))
        let eventID = try #require(Event.ID(
            "at://did:plc:5df2u7ief6m6tn77jznicxob/events.openmusic.event/3mrdbziccpcah"
        ))
        let wickedWoods = CalendarEvent(
            uri: eventID,
            name: "Wicked Woods 2026",
            startsAt: nil,
            organizer: CalendarEvent.Organizer(
                id: organizerID,
                displayName: "Wicked Woods"
            ),
            source: CalendarEvent.Source(
                collection: ATProto.NSID(Event.lexiconID.rawValue),
                appViewHost: "openmusicevent.app"
            )
        )
        let event = try Event(
            id: eventID,
            name: "Wicked Woods 2026",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: #require(TimeZone(identifier: "America/Denver"))
        )
        let graph = EventRecordGraph(event: event)
        let requestedIDs = TestMutex<[Event.ID]>([])

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.eventRecords = EventRecordClient { requestedID in
                requestedIDs.withLock { $0.append(requestedID) }
                return graph
            }
        } operation: {
            Store(initialState: EnterEventStory.State(event: wickedWoods)) {
                EnterEventStory()
            }
        }

        let enterEventTask = store.send(.detail(.enterEventButtonTapped))
        #expect(store.detail.isEnteringEvent)
        await enterEventTask?.value
        expectNoDifference(requestedIDs.withLock { $0 }, [eventID])
        expectNoDifference(store.lastRequest, .event(eventID, nil))
        #expect(!store.detail.isEnteringEvent)

        let saved = try await database.read { db in
            (
                event: try Event.find(eventID).fetchOne(db),
                installation: try InstalledEvent.find(eventID).fetchOne(db)
            )
        }
        #expect(saved.event?.name == "Wicked Woods 2026")
        #expect(saved.installation == InstalledEvent(id: eventID))
    }

    @Test
    func `replacing a canonical event record preserves attendee schedules and selection`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        BlueskyActorCacheMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let eventID = try #require(Event.ID(
            "at://did:plc:5df2u7ief6m6tn77jznicxob/events.openmusic.event/3mrdbziccpcah"
        ))
        var event = try Event(
            id: eventID,
            name: "Wicked Woods before refresh",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        let userSchedule = UserSchedule(
            id: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000026")),
            eventID: eventID,
            title: "My Schedule"
        )
        let viewerState = EventViewerState(
            id: eventID,
            selectedUserScheduleID: userSchedule.id,
            didInitializeUserSchedules: true
        )
        let initialEvent = event
        try await database.write { db in
            try EventRecordGraph(event: initialEvent).upsert(in: db)
            try InstalledEvent.insert { InstalledEvent(id: eventID) }.execute(db)
            try UserSchedule.insert { userSchedule }.execute(db)
            try EventViewerState.insert { viewerState }.execute(db)
        }

        event.name = "Wicked Woods after refresh"
        let refreshed = event
        try await database.write { db in
            try EventRecordGraph(event: refreshed).upsert(in: db)
        }

        try await database.read { db in
            expectNoDifference(try Event.find(eventID).fetchOne(db), refreshed)
            expectNoDifference(
                try InstalledEvent.find(eventID).fetchOne(db),
                InstalledEvent(id: eventID)
            )
            expectNoDifference(
                try UserSchedule.find(userSchedule.id).fetchOne(db),
                userSchedule
            )
            expectNoDifference(
                try EventViewerState.find(eventID).fetchOne(db),
                viewerState
            )
        }
    }

    @Test @MainActor
    func `a failed event installation is reported without becoming detail state`() async throws {
        struct InstallationFailure: Error {}

        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        let organizerID = try #require(DID("did:plc:organizer"))
        let omeEvent = try event(
            uri: "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah",
            name: "Summer Festival",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 100),
            collection: ATProto.NSID(Event.lexiconID.rawValue)
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.eventRecords = EventRecordClient { _ in throw InstallationFailure() }
        } operation: {
            Store(initialState: EnterEventStory.State(event: omeEvent)) {
                EnterEventStory()
            }
        }

        await withIssueReporters([]) {
            await store.send(.detail(.enterEventButtonTapped))?.value
        }

        #expect(!store.detail.isEnteringEvent)
        #expect(store.detail.errorMessage == nil)
        #expect(store.lastError?.message.fallback == "Unable to enter this event.")
        #expect(store.lastError?.operation.rawValue == "event.install")
        #expect(store.lastRequest == nil)
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
        var lastError: HandledError?
        var lastRequest: NavigationRequest?
    }

    enum Action {
        case detail(EventBrowseDetail.Action)
    }

    var body: some Feature {
        Scope(\.detail) {
            EventBrowseDetail()
        }
        .onEvent(ErrorReported.self) { error, state in
            state.lastError = error
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}

@Feature
struct OrganizationDetailStory {
    struct State {
        init(organizerID: OME.Organizer.ID) {
            self.detail = OrganizationDetail.State(organizerID: organizerID)
        }

        var detail: OrganizationDetail.State
        var lastRequest: NavigationRequest?
    }

    enum Action {
        case detail(OrganizationDetail.Action)
    }

    var body: some Feature {
        Scope(\.detail) {
            OrganizationDetail()
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}

@MainActor
func waitForEventBrowseObservation(
    _ condition: @escaping @MainActor () -> Bool
) async {
    while !condition() {
        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = condition()
            } onChange: {
                continuation.resume()
            }
        }
    }
}

#endif
