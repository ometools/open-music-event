import ATProto
import BlueskyActorCache
import ComposableArchitecture2
import ComposableCalendarEvents
import ComposableNotifications
import CustomDump
import Dependencies
import DependenciesTestSupport
import ErrorHandling
import FileTree
import Foundation
import HTTPClient
import HTTPTypes
import HummingbirdTesting
import IssueReporting
@testable import OpenMusicEventApp
import OpenMusicEventAppViewServer
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import OpenMusicEventViewers
import OpenMusicEventWhiteLabel
import SourceControlClient
import SQLiteData
import Synchronization
import Testing
import XRPCClient

@Suite(.serialized)
struct EventBrowseStoryTests {
    @Test @MainActor
    func `an empty app browses and refreshes from a delivered notification`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        let appViewRequests = Mutex<[String]>([])

        let app = try OpenMusicEventAppViewServer.application(
            configuration: AppViewConfiguration(port: 0)
        )
        let getEventsRequestCount: @Sendable () -> Int = {
            appViewRequests.withLock {
                $0.filter {
                    $0.hasPrefix("/xrpc/app.openmusicevent.calendar.getEvents")
                }.count
            }
        }
        try await app.test(.router) { server in
            try await withDependencies {
                $0.context = .test
                $0.date = .constant(Date(timeIntervalSince1970: 0))
                OME.prepareDependencies(&$0, database: database)
                $0.notificationTokenClient = NotificationTokenClient(
                    tokens: { AsyncStream { $0.finish() } }
                )
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
                    store.scope(\.browser, action: \.browser).spawn(\.browse)
                }

                let browseTask = await MainActor.run {
                    browse.send(.task)
                }
                await browseTask?.value
                expectNoDifference(getEventsRequestCount(), 1)

                // APNs delivers the background update as JSON. The app root lets the
                // notifications feature decode it before deciding that Browse should refresh.
                let notificationJSON = #"""
                {
                  "aps": {
                    "content-available": 1
                  },
                  "kind": "source_available",
                  "source": "openmusicevent.app",
                  "version": "1"
                }
                """#
                let refreshTask = try await MainActor.run {
                    try store.state.notificationEvent(
                        NotificationEvent(
                            json: notificationJSON,
                            delivery: .contentAvailable
                        )
                    )
                }
                await refreshTask?.value

                await MainActor.run {
                    expectNoDifference(browse.catalog, .openMusicEvent)
                    expectNoDifference(browse.events.count, 20)
                    expectNoDifference(browse.events.first?.name, "Wicked Woods 2026")
                    expectNoDifference(
                        browse.events.first?.uri.description,
                        "at://did:plc:5df2u7ief6m6tn77jznicxob/app.openmusicevent.event/ome-workspace-2026"
                    )
                    expectNoDifference(browse.events.last?.name, "Goth Night")
                    expectNoDifference(
                        browse.events.last?.uri.description,
                        "at://did:web:gallatinlabortemple.org/app.openmusicevent.event/gallatin-labor-temple-ome-2026-10-24-goth-night"
                    )
                    expectNoDifference(browse.errorMessage, nil)
                    expectNoDifference(browse.isLoading, false)
                    expectNoDifference(
                        browse.events.first?.source.appViewHost,
                        "openmusicevent.app"
                    )
                    expectNoDifference(
                        getEventsRequestCount(),
                        2
                    )
                    withExtendedLifetime(store) {}
                }

                let firstEventURI = await MainActor.run { browse.events.first?.uri }
                let eventURI = try #require(firstEventURI)
                let event = try await CalendarEventsClient
                    .openMusicEventAndAtmo(database: database)
                    .event(eventURI)
                expectNoDifference(event.name, "Wicked Woods 2026")
                expectNoDifference(event.uri, eventURI)
                #expect(
                    appViewRequests.withLock { $0.last }?.hasPrefix(
                        "/xrpc/app.openmusicevent.calendar.getEvent?uri="
                    ) == true
                )
            }
        }

    }

    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @Test(.tcaExhaustivity(.off)) @MainActor
    func `entering an event publishes its canonical notification subscription`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        BlueskyActorCacheMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let organizerID = try #require(DID("did:plc:wickedwoods"))
        let eventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: OME.ID<OME.Event>(rawValue: "2026")
        )
        try await database.write { database in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: organizerID)
            }
            .execute(database)
            try OME.Event.insert {
                testEventDraft(id: eventID, name: "Wicked Woods 2026")
            }
            .execute(database)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .tangled,
                    sourceReference: "tangled.org/woody.fm/wicked-woods",
                    ref: "main",
                    eventIDOrigin: .explicit,
                    sourceEventDirectory: "wicked-woods-2026"
                )
            }
            .execute(database)
        }

        let expectedSubscription = NotificationSubscription(
            sourceID: .init(
                rawValue: "at://did:plc:wickedwoods/app.openmusicevent.event/2026"
            )
        )
        let (replacements, replacementContinuation) =
            AsyncStream<Set<NotificationSubscription>>.makeStream()
        defer { replacementContinuation.finish() }

        await withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.uuid = .incrementing
            OME.prepareDependencies(&$0, database: database)
            $0.defaultEventID = eventID
            $0.notificationTokenClient = NotificationTokenClient(
                tokens: { AsyncStream { $0.finish() } }
            )
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
            await store.dismount(timeout: .seconds(1))
        }
    }

    @Test @MainActor
    func `a silent source update refreshes the entered event without remounting it`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        BlueskyActorCacheMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let organizerID = try #require(DID("did:plc:5df2u7ief6m6tn77jznicxob"))
        let eventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: OME.ID<OME.Event>(rawValue: "ome-workspace-2026")
        )
        try await database.write { database in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: organizerID)
            }
            .execute(database)
            try OME.Event.insert {
                testEventDraft(id: eventID, name: "Wicked Woods 2026")
            }
            .execute(database)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .tangled,
                    sourceReference: "tangled.org/wickedwoods.ca/ome-workspace",
                    ref: "main",
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "2026"
                )
            }
            .execute(database)
        }

        let notificationVersion = "manual-wicked-woods-1"
        let checkoutRequests = Mutex<[TangledSourceCheckoutRequest]>([])

        try await withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.uuid = .incrementing
            OME.prepareDependencies(&$0, database: database)
            $0.defaultEventID = eventID
            $0.calendarEvents = CalendarEventsClient(
                browse: { _ in CalendarEvent.Page(events: []) },
                event: { _ in throw CalendarEventsClientError.unimplemented },
                organizer: { _ in throw CalendarEventsClientError.unimplemented }
            )
            $0.notificationTokenClient = NotificationTokenClient(
                tokens: { AsyncStream { $0.finish() } }
            )
            $0.notificationsClient = NotificationsClient(
                registerDestination: { _ in },
                replaceSubscriptions: { _ in },
                synchronize: {},
                signals: { AsyncStream { $0.finish() } }
            )
            $0.omeEventSourceRefresh = .liveValue
            $0.tangledSourceCheckout = TangledSourceCheckoutClient { request in
                checkoutRequests.withLock { $0.append(request) }
                try FileManager.default.createDirectory(
                    at: request.outputURL,
                    withIntermediateDirectories: true
                )
                try writeWickedWoodsSourceWithTwoEvents(
                    to: request.outputURL,
                    event2026Name: "Wicked Woods 2026 — Updated"
                )
                return TangledSourceCheckout(repositoryURL: request.outputURL)
            }
        } operation: {
            var initialState = OpenMusicEventAppRoot.State(
                variant: .whiteLabel(
                    WickedWoodsWhiteLabel.configuration(organizerID: organizerID)
                ),
                selectedEventIDAtLaunch: eventID
            )
            if case var .eventViewer(eventViewer) = initialState.destination {
                eventViewer.authoring.content.content.selectedFeature = .communications
                initialState.destination = .eventViewer(eventViewer)
            }
            let mountedWorkspaceID = initialState.destination?.eventViewer?.authoring.context.id
            let store = Store(initialState: initialState) {
                OpenMusicEventAppRoot()
            }

            // A source update for some other subscription must not touch the mounted event.
            // Keeping this as provider JSON proves that filtering happens after the same
            // notification decoding boundary used by the app delegate.
            let unrelatedNotificationJSON = """
            {
              "aps": {
                "content-available": 1
              },
              "kind": "source_available",
              "source": "at://did:plc:somebody-else/app.openmusicevent.event/other-event",
              "version": "manual-other-event-1"
            }
            """
            let unrelatedNotificationTask = try store.state.notificationEvent(
                NotificationEvent(
                    json: unrelatedNotificationJSON,
                    delivery: .contentAvailable
                )
            )
            await unrelatedNotificationTask?.value

            expectNoDifference(
                store.destination?.eventViewer?.authoring.content.content.event?.name,
                "Wicked Woods 2026"
            )
            expectNoDifference(
                store.destination?.eventViewer?.authoring.context.id,
                mountedWorkspaceID
            )
            expectNoDifference(checkoutRequests.withLock { $0 }, [])

            // This is the exact provider JSON delivered through the app delegate. Its version is
            // opaque notification metadata, while the source ID matches the subscription
            // published by the already-mounted event viewer.
            let notificationJSON = """
            {
              "aps": {
                "content-available": 1
              },
              "kind": "source_available",
              "source": "\(OME.Event.reference(id: eventID).uri.description)",
              "version": "\(notificationVersion)"
            }
            """
            let notificationTask = try store.state.notificationEvent(
                NotificationEvent(
                    json: notificationJSON,
                    delivery: .contentAvailable
                )
            )
            await notificationTask?.value

            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(1))
            while store.destination?.eventViewer?
                .authoring.content.content.event?.name != "Wicked Woods 2026 — Updated",
                  clock.now < deadline
            {
                try await clock.sleep(for: .milliseconds(1))
            }

            expectNoDifference(
                store.destination?.eventViewer?.authoring.content.content.event?.name,
                "Wicked Woods 2026 — Updated"
            )
            expectNoDifference(
                store.destination?.eventViewer?.authoring.content.content.selectedFeature,
                .communications
            )
            expectNoDifference(
                store.destination?.eventViewer?.authoring.context.id,
                mountedWorkspaceID
            )
            expectNoDifference(
                checkoutRequests.withLock { $0.map(\.ref) },
                ["main"]
            )
            expectNoDifference(
                checkoutRequests.withLock {
                    $0.map(\.repository.normalizedReference)
                },
                ["tangled.org/wickedwoods.ca/ome-workspace"]
            )

            // Refresh remains event-scoped even though the canonical repository also contains
            // Wicked Woods 2025.
            let installedEventIDs = try await database.read { database in
                try OME.Event.fetchAll(database).map(\.id)
            }
            expectNoDifference(installedEventIDs, [eventID])
            withExtendedLifetime(store) {}
        }
    }

    @Test
    func `the OME AppView client preserves pagination through XRPC`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        let requests = Mutex<[HTTPRequest]>([])

        let page = try await withDependencies {
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { request, _ in
                requests.withLock { $0.append(request) }
                return Data(Self.omeAppViewPageResponse.utf8)
            }
        } operation: {
            try await CalendarEventsClient
                .openMusicEventAndAtmo(database: database)
                .browse(
                    CalendarEvent.PageRequest(
                        collection: OME.Event.nsid,
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
            "/xrpc/app.openmusicevent.calendar.getEvents"
        )
        expectNoDifference(
            Set(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
                .queryItems ?? []),
            [
                URLQueryItem(name: "catalog", value: OME.Event.nsid.rawValue),
                URLQueryItem(name: "cursor", value: "page-2"),
                URLQueryItem(name: "limit", value: "12"),
            ]
        )
        expectNoDifference(page.events.map(\.name), ["Network Festival"])
        expectNoDifference(page.cursor, "page-3")
        expectNoDifference(page.events.first?.source.appViewHost, "openmusicevent.app")
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
    func `an installed OME poster is the first browse image`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let organizerID = try #require(DID("did:plc:artfestival"))
        let eventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: OME.ID<OME.Event>(rawValue: "summer-art-festival")
        )
        let posterURL = try #require(URL(string: "https://example.com/poster.jpg"))
        let heroURL = try #require(URL(string: "https://example.com/hero.jpg"))
        let iconURL = try #require(URL(string: "https://example.com/icon.png"))

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Summer Art Festival",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: nil,
                    mode: nil,
                    locations: nil,
                    uris: nil,
                    timeZone: TimeZone.current,
                    images: [
                        OME.ImageAsset(
                            source: .url(iconURL),
                            role: .icon,
                            renderKind: .transparent,
                            materializationPolicy: .lazy
                        ),
                        OME.ImageAsset(
                            source: .url(heroURL),
                            role: .hero,
                            renderKind: .fullImage,
                            materializationPolicy: .lazy
                        ),
                    ],
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
            try OME.Poster.insert {
                OME.Poster.Draft(
                    id: OME.Poster.ID(
                        organizerID: organizerID,
                        eventID: eventID.eventID,
                        posterID: OME.ID<OME.Poster>(rawValue: "main-poster")
                    ),
                    title: "Summer Art Festival poster",
                    image: OME.ImageAsset(
                        source: .url(posterURL),
                        role: .poster,
                        renderKind: .fullImage,
                        materializationPolicy: .lazy
                    )
                )
            }
            .execute(db)
        }

        let page = try await withDependencies {
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { _, _ in
                Data(Self.installedEventAppViewPageResponse.utf8)
            }
        } operation: {
            try await CalendarEventsClient
                .openMusicEventAndAtmo(database: database)
                .browse(CalendarEvent.PageRequest(collection: OME.Event.nsid))
        }
        let event = try #require(page.events.first { $0.name == "Summer Art Festival" })

        // Poster is the primary visual; hero and icon remain useful failure fallbacks.
        expectNoDifference(event.media.map(\.role), ["poster", "hero", "icon"])
        expectNoDifference(event.media.map(\.url), [posterURL, heroURL, iconURL])
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
                ATProto.URI("at://did:plc:organizer/app.openmusicevent.event/festival")
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
            source: CalendarEvent.Source(collection: OME.Event.nsid)
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
    func `browse opens organization detail by organizer identity`() throws {
        let organizerID = try #require(DID("did:plc:organizer"))
        let currentEvent = try event(
            uri: "at://did:plc:organizer/app.openmusicevent.event/current",
            name: "Current Festival",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 200),
            collection: OME.Event.nsid
        )
        let store = Store(
            initialState: EventBrowseDetail.State(event: currentEvent)
        ) {
            EventBrowseDetail()
        }

        store.send(.organizerButtonTapped)

        let organizationDetail = try #require(store.organizationDetail)
        expectNoDifference(organizationDetail.organizerID, organizerID)
        expectNoDifference(organizationDetail.collection, OME.Event.nsid)
        expectNoDifference(organizationDetail.events, [])
    }

    @Test @MainActor
    func `organization detail opens selected event detail without entering it`() async throws {
        let organizerID = try #require(DID("did:plc:organizer"))
        let previousEvent = try event(
            uri: "at://did:plc:organizer/app.openmusicevent.event/2025",
            name: "Wicked Woods 2025",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 100),
            collection: OME.Event.nsid
        )
        let selectedEvent = try event(
            uri: "at://did:plc:organizer/app.openmusicevent.event/2026",
            name: "Wicked Woods 2026",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 200),
            collection: OME.Event.nsid
        )
        let organizerEvents = [previousEvent, selectedEvent]
        let selectedEventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: OME.ID<OME.Event>(rawValue: "2026")
        )
        let installations = Mutex<[ATProto.URI]>([])
        let store = withDependencies {
            $0.calendarEvents = CalendarEventsClient(
                browse: { _ in CalendarEvent.Page(events: organizerEvents) },
                event: { _ in selectedEvent },
                organizer: { _ in selectedEvent.organizer }
            )
            $0.omeEventInstallation = OMEEventInstallationClient { uri in
                installations.withLock { $0.append(uri) }
                return selectedEventID
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
        await store.dismount(timeout: .seconds(1))
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
    func `entering Wicked Woods downloads and installs only that event before opening it`() async throws {
        struct UnexpectedGitOperation: Error {}

        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let organizerID = try #require(DID("did:plc:5df2u7ief6m6tn77jznicxob"))
        let eventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: OME.ID<OME.Event>(rawValue: "ome-workspace-2026")
        )
        let wickedWoods = CalendarEvent(
            uri: OME.Event.reference(id: eventID).uri,
            name: "Wicked Woods 2026",
            startsAt: nil,
            organizer: CalendarEvent.Organizer(
                id: organizerID,
                displayName: "Wicked Woods"
            ),
            source: CalendarEvent.Source(
                collection: OME.Event.nsid,
                appViewHost: "openmusicevent.app"
            )
        )
        let downloadUUID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000026")
        )
        let gitOperations = Mutex<[String]>([])

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { _, _ in
                Data(Self.wickedWoodsAppViewPageResponse.utf8)
            }
            $0.omeEventInstallation = .liveValue
            $0.uuid = .constant(downloadUUID)
            $0.sourceControl.clone = { _ in
                gitOperations.withLock { $0.append("clone") }
                throw UnexpectedGitOperation()
            }
            $0.sourceControl.open = { _ in
                gitOperations.withLock { $0.append("open") }
                throw UnexpectedGitOperation()
            }
            $0.sourceControl.fetch = { _ in
                gitOperations.withLock { $0.append("fetch") }
                throw UnexpectedGitOperation()
            }
            $0.sourceControl.checkout = { _ in
                gitOperations.withLock { $0.append("checkout") }
                throw UnexpectedGitOperation()
            }
            $0.tangledSourceCheckout = TangledSourceCheckoutClient { request in
                expectNoDifference(
                    request.repository.normalizedReference,
                    "tangled.org/wickedwoods.ca/ome-workspace"
                )
                try FileManager.default.createDirectory(
                    at: request.outputURL,
                    withIntermediateDirectories: true
                )
                try writeWickedWoodsSourceWithTwoEvents(to: request.outputURL)
                return TangledSourceCheckout(repositoryURL: request.outputURL)
            }
        } operation: {
            Store(
                initialState: EnterEventStory.State(event: wickedWoods)
            ) {
                EnterEventStory()
            }
        }

        // Entering starts from the AppView browse identity and uses the existing viewer route.
        let enterEventTask = store.send(.detail(.enterEventButtonTapped))
        #expect(store.detail.isEnteringEvent)
        await enterEventTask?.value
        expectNoDifference(store.lastRequest, .event(eventID, nil))
        #expect(!store.detail.isEnteringEvent)

        // The downloaded source contained 2025 and 2026, but this installation is event-scoped.
        let installedEvents = try await database.read { db in
            try OME.Event.fetchAll(db)
        }
        expectNoDifference(installedEvents.map(\.id), [eventID])
        expectNoDifference(installedEvents.map(\.name), ["Wicked Woods 2026"])
        expectNoDifference(gitOperations.withLock { $0 }, [])

        // Browse persists only the neutral source locator carried by the OME record. It does not
        // prepare a repository, install an organization source, or manufacture publication state.
        let browseState = try await database.read { db in
            (
                provenance: try EventSourceProvenanceRecord.find(eventID).fetchOne(db),
                installations: try SourceWorkspaceInstallationRecord.fetchCount(db)
            )
        }
        let workspace = try #require(browseState.provenance?.workspace)
        expectNoDifference(workspace.organizerID, organizerID)
        expectNoDifference(workspace.repository, "tangled.org/wickedwoods.ca/ome-workspace")
        expectNoDifference(workspace.branch, "main")
        expectNoDifference(browseState.installations, 0)
        #expect(try SourceWorkspaceOpenProposalStore(database: database).load(workspace.id) == nil)
    }

    @Test @MainActor
    func `a failed event installation is reported without becoming detail state`() async throws {
        struct InstallationFailure: Error {}

        let organizerID = try #require(DID("did:plc:organizer"))
        let omeEvent = try event(
            uri: "at://did:plc:organizer/app.openmusicevent.event/festival",
            name: "Summer Festival",
            organizerID: organizerID,
            startsAt: Date(timeIntervalSince1970: 100),
            collection: OME.Event.nsid
        )
        let store = withDependencies {
            $0.context = .test
            $0.omeEventInstallation = OMEEventInstallationClient { _ in
                throw InstallationFailure()
            }
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

extension EventBrowseStoryTests {
    static let omeAppViewPageResponse = #"""
        {
          "events": [
            {
              "uri": "at://did:plc:organizer/app.openmusicevent.event/network-festival",
              "name": "Network Festival",
              "startsAt": "2026-09-04T06:00:00Z",
              "locations": [],
              "links": [],
              "media": [],
              "organizer": {
                "id": "did:plc:organizer",
                "displayName": "Network Organizer"
              },
              "attendance": {
                "going": 0,
                "interested": 0,
                "notGoing": 0
              },
              "source": {
                "collection": "app.openmusicevent.event",
                "appViewHost": "openmusicevent.app",
                "sourceRecord": {
                  "$type": "app.openmusicevent.source",
                  "kind": "tangled",
                  "reference": "https://tangled.org/example.com/network-festival",
                  "ref": "main"
                }
              },
              "timeZoneIdentifier": "America/Denver"
            }
          ],
          "cursor": "page-3"
        }
        """#

    static let installedEventAppViewPageResponse = #"""
        {
          "events": [
            {
              "uri": "at://did:plc:artfestival/app.openmusicevent.event/summer-art-festival",
              "name": "Summer Art Festival",
              "locations": [],
              "links": [],
              "media": [],
              "organizer": {
                "id": "did:plc:artfestival"
              },
              "attendance": {
                "going": 0,
                "interested": 0,
                "notGoing": 0
              },
              "source": {
                "collection": "app.openmusicevent.event",
                "appViewHost": "openmusicevent.app"
              }
            }
          ]
        }
        """#

    static let wickedWoodsAppViewPageResponse = #"""
        {
          "events": [
            {
              "uri": "at://did:plc:5df2u7ief6m6tn77jznicxob/app.openmusicevent.event/ome-workspace-2026",
              "name": "Wicked Woods 2026",
              "locations": [],
              "links": [],
              "media": [],
              "organizer": {
                "id": "did:plc:5df2u7ief6m6tn77jznicxob",
                "displayName": "Wicked Woods"
              },
              "attendance": {
                "going": 0,
                "interested": 0,
                "notGoing": 0
              },
              "source": {
                "collection": "app.openmusicevent.event",
                "appViewHost": "openmusicevent.app",
                "sourceRecord": {
                  "$type": "app.openmusicevent.source",
                  "kind": "tangled",
                  "reference": "https://tangled.org/wickedwoods.ca/ome-workspace",
                  "ref": "main"
                }
              }
            }
          ]
        }
        """#
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
        Scope(\.detail, action: \.detail) {
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
        Scope(\.detail, action: \.detail) {
            OrganizationDetail()
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}

private func writeWickedWoodsSourceWithTwoEvents(
    to repositoryURL: URL,
    event2026Name: String = "Wicked Woods 2026"
) throws {
    let timeZone = try #require(TimeZone(identifier: "America/Denver"))
    let source = OpenMusicEventSourceRepository(
        events: [
            wickedWoodsSourceEvent(
                directoryName: "2025",
                name: "Wicked Woods 2025",
                timeZone: timeZone
            ),
            wickedWoodsSourceEvent(
                directoryName: "2026",
                name: event2026Name,
                timeZone: timeZone
            ),
        ]
    )
    _ = try OpenMusicEventSourceRepositoryFileTree().write(source, to: repositoryURL)
}

private func wickedWoodsSourceEvent(
    directoryName: String,
    name: String,
    timeZone: TimeZone
) -> DirectoryContent<OpenMusicEventSourceEvent> {
    DirectoryContent(
        directoryName: directoryName,
        components: OpenMusicEventSourceEvent(
            event: EventDTO(
                id: nil,
                name: name,
                description: nil,
                startDate: nil,
                endDate: nil,
                status: nil,
                mode: nil,
                locations: nil,
                uris: nil,
                timeZone: timeZone,
                images: nil,
                contactNumbers: nil,
                categoryConfigs: nil
            )
        )
    )
}
