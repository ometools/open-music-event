import ATProto
import CustomDump
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HummingbirdTesting
import OpenMusicEventLexicon
import SQLiteData
import Testing

@testable import OpenMusicEventAppViewServer

@Suite(AppViewTestTime()) struct CalendarEventBrowseTests {
    private let canonicalCatalog = ATProto.NSID(Event.lexiconID.rawValue)!
    private let communityCatalog = ATProto.NSID("community.lexicon.calendar.event")

    @Test
    func `catalog search bounds pagination updates and deletion are database backed`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let first = try event(
            uri: "at://did:plc:venue/events.openmusic.event/3mrdbziccpcaa",
            catalog: canonicalCatalog,
            name: "Midnight Brass",
            city: "Bozeman",
            latitude: 45.68,
            longitude: -111.04,
            startsAt: "2026-10-11T01:00:00Z"
        )
        let second = try event(
            uri: "at://did:plc:community/community.lexicon.calendar.event/3mrdbziccpcab",
            catalog: communityCatalog,
            name: "Café Session",
            city: "Butte",
            latitude: 46.01,
            longitude: -112.54,
            startsAt: "2026-10-12T01:00:00Z"
        )
        try database.write { db in
            try CalendarEventBrowseProjection.upsert(first, searchText: "Beyoncé Labor Temple", in: db)
            try CalendarEventBrowseProjection.upsert(second, searchText: "Copper King", in: db)
        }

        let both = try store.browseCalendarEvents(
            parameters: .init(catalogs: [canonicalCatalog, communityCatalog], limit: 1),
            appViewHost: "localhost",
            now: date("2026-10-10T00:00:00Z")
        )
        expectNoDifference(both.events.map { $0.name }, ["Midnight Brass"])
        let cursor = try #require(both.cursor)
        let next = try store.browseCalendarEvents(
            parameters: .init(
                catalogs: [canonicalCatalog, communityCatalog],
                cursor: cursor,
                limit: 1
            ),
            appViewHost: "localhost",
            now: date("2026-10-20T00:00:00Z")
        )
        expectNoDifference(next.events.map { $0.name }, ["Café Session"])

        let searched = try store.browseCalendarEvents(
            parameters: .init(catalogs: [canonicalCatalog], query: "Beyonce!", limit: 100),
            appViewHost: "localhost"
        )
        expectNoDifference(searched.events.map { $0.name }, ["Midnight Brass"])
        let scoped = try store.browseCalendarEvents(
            parameters: .init(catalogs: [communityCatalog], query: "Beyonce", limit: 100),
            appViewHost: "localhost"
        )
        #expect(scoped.events.isEmpty)
        let bounded = try store.browseCalendarEvents(
            parameters: .init(
                catalogs: [canonicalCatalog, communityCatalog],
                north: 46,
                south: 45,
                east: -110,
                west: -112,
                limit: 100
            ),
            appViewHost: "localhost"
        )
        expectNoDifference(bounded.events.map { $0.name }, ["Midnight Brass"])

        var updated = first
        updated.name = "Updated Brass"
        try database.write { db in
            try CalendarEventBrowseProjection.upsert(updated, searchText: "Beyoncé", in: db)
            try CalendarEventBrowseProjection.delete(uri: second.uri.description, in: db)
        }
        let refreshed = try store.browseCalendarEvents(
            parameters: .init(catalogs: [canonicalCatalog, communityCatalog], limit: 100),
            appViewHost: "localhost"
        )
        expectNoDifference(refreshed.events.map { $0.name }, ["Updated Brass"])
        #expect(throws: OpenMusicEventAppViewStoreError.self) {
            _ = try store.browseCalendarEvents(
                parameters: .init(
                    catalogs: [canonicalCatalog, communityCatalog],
                    query: "changed query",
                    cursor: cursor,
                    limit: 1
                ),
                appViewHost: "localhost"
            )
        }
    }

    @Test
    func `temporal browse prioritizes ongoing viewers then future and fills from remaining events`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let now = date("2026-10-11T12:00:00Z")
        let events = [
            try event(
                uri: "at://did:plc:venue/events.openmusic.event/ongoing",
                catalog: canonicalCatalog,
                name: "Ongoing Viewer",
                city: "Bozeman",
                latitude: 45.68,
                longitude: -111.04,
                startsAt: "2026-10-11T11:00:00Z",
                endsAt: "2026-10-11T13:00:00Z"
            ),
            try event(
                uri: "at://did:plc:venue/events.openmusic.event/ongoing-basic",
                catalog: canonicalCatalog,
                name: "Ongoing Browse Only",
                city: "Bozeman",
                latitude: 45.68,
                longitude: -111.04,
                startsAt: "2026-10-11T11:30:00Z",
                endsAt: "2026-10-11T13:30:00Z"
            ),
            try event(
                uri: "at://did:plc:venue/events.openmusic.event/future-near",
                catalog: canonicalCatalog,
                name: "Future Near",
                city: "Bozeman",
                latitude: 45.68,
                longitude: -111.04,
                startsAt: "2026-10-11T13:00:00Z"
            ),
            try event(
                uri: "at://did:plc:venue/events.openmusic.event/future-far",
                catalog: canonicalCatalog,
                name: "Future Far",
                city: "Bozeman",
                latitude: 45.68,
                longitude: -111.04,
                startsAt: "2026-10-12T13:00:00Z"
            ),
            try event(
                uri: "at://did:plc:venue/events.openmusic.event/past-recent",
                catalog: canonicalCatalog,
                name: "Past Recent",
                city: "Bozeman",
                latitude: 45.68,
                longitude: -111.04,
                startsAt: "2026-10-11T10:00:00Z",
                endsAt: "2026-10-11T11:00:00Z"
            ),
            try event(
                uri: "at://did:plc:venue/events.openmusic.event/past-old",
                catalog: canonicalCatalog,
                name: "Past Old",
                city: "Bozeman",
                latitude: 45.68,
                longitude: -111.04,
                startsAt: "2026-10-01T10:00:00Z"
            ),
            try event(
                uri: "at://did:plc:venue/events.openmusic.event/undated",
                catalog: canonicalCatalog,
                name: "Undated",
                city: "Bozeman",
                latitude: 45.68,
                longitude: -111.04,
                startsAt: nil
            ),
        ]
        try database.write { db in
            for event in events {
                try CalendarEventBrowseProjection.upsert(
                    event,
                    hasEventViewer: event.name == "Ongoing Viewer",
                    in: db
                )
            }
        }

        let prioritized = try store.browseCalendarEvents(
            parameters: .init(catalogs: [canonicalCatalog], limit: 3),
            appViewHost: "localhost",
            now: now
        )
        expectNoDifference(
            prioritized.events.map(\.name),
            ["Ongoing Viewer", "Future Near", "Future Far"]
        )

        var names: [String] = []
        var cursor: String?
        repeat {
            let page = try store.browseCalendarEvents(
                parameters: .init(
                    catalogs: [canonicalCatalog],
                    cursor: cursor,
                    limit: 2
                ),
                appViewHost: "localhost",
                now: cursor == nil ? now : date("2027-01-01T00:00:00Z")
            )
            names.append(contentsOf: page.events.map(\.name))
            cursor = page.cursor
        } while cursor != nil

        expectNoDifference(
            names,
            [
                "Ongoing Viewer",
                "Future Near",
                "Future Far",
                "Ongoing Browse Only",
                "Past Recent",
                "Past Old",
                "Undated",
            ]
        )
    }

    @Test
    func `RTree tracks coordinate inserts moves deletes missing coordinates and antimeridian bounds`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        var east = try event(
            uri: "at://did:plc:venue/events.openmusic.event/east",
            catalog: canonicalCatalog,
            name: "East",
            city: "Suva",
            latitude: -17.7,
            longitude: 179.5,
            startsAt: "2026-10-20T00:00:00Z"
        )
        east.media = [
            .init(
                url: URL(string: "https://example.com/east-logo.png")!,
                role: "logo",
                renderKind: .transparent
            )
        ]
        let west = try event(
            uri: "at://did:plc:venue/events.openmusic.event/west",
            catalog: canonicalCatalog,
            name: "West",
            city: "Pago Pago",
            latitude: -14.3,
            longitude: -179.5,
            startsAt: "2026-10-21T00:00:00Z"
        )
        var moving = try event(
            uri: "at://did:plc:venue/events.openmusic.event/moving",
            catalog: canonicalCatalog,
            name: "Moving",
            city: "London",
            latitude: 51.5,
            longitude: 0,
            startsAt: "2026-10-22T00:00:00Z"
        )
        let missing = try event(
            uri: "at://did:plc:venue/events.openmusic.event/missing",
            catalog: canonicalCatalog,
            name: "Missing",
            city: "Somewhere",
            latitude: nil,
            longitude: nil,
            startsAt: "2026-10-23T00:00:00Z"
        )
        try database.write { db in
            for event in [east, west, moving, missing] {
                try CalendarEventBrowseProjection.upsert(event, in: db)
            }
        }

        let global = try store.browseCalendarEvents(
            parameters: .init(
                catalogs: [canonicalCatalog],
                north: 90, south: -90, east: 180, west: -180
            ),
            appViewHost: "localhost",
            now: date("2026-10-11T00:00:00Z")
        )
        expectNoDifference(Set(global.events.map(\.name)), Set(["East", "West", "Moving"]))
        expectNoDifference(
            global.events.first(where: { $0.name == "East" })?.media.first,
            .init(
                url: URL(string: "https://example.com/east-logo.png")!,
                role: "logo",
                renderKind: .transparent
            )
        )

        let antimeridian = try OME.CalendarEvent.BrowseEvents.Bounds(
            north: 10,
            south: -30,
            east: -170,
            west: 170
        )
        var bounded = try store.browseCalendarEvents(
            parameters: .init(
                catalogs: [canonicalCatalog],
                north: antimeridian.north, south: antimeridian.south,
                east: antimeridian.east, west: antimeridian.west
            ),
            appViewHost: "localhost",
            now: date("2026-10-11T00:00:00Z")
        )
        expectNoDifference(Set(bounded.events.map(\.name)), Set(["East", "West"]))

        moving.locations[0].latitude = "-20"
        moving.locations[0].longitude = "175"
        try database.write { db in
            try CalendarEventBrowseProjection.upsert(moving, in: db)
            try CalendarEventBrowseProjection.delete(uri: east.uri.description, in: db)
        }
        bounded = try store.browseCalendarEvents(
            parameters: .init(
                catalogs: [canonicalCatalog],
                north: antimeridian.north, south: antimeridian.south,
                east: antimeridian.east, west: antimeridian.west
            ),
            appViewHost: "localhost",
            now: date("2026-10-11T00:00:00Z")
        )
        expectNoDifference(Set(bounded.events.map(\.name)), Set(["West", "Moving"]))
        #expect(try database.read {
            try Int.fetchOne(
                $0,
                sql: "SELECT COUNT(*) FROM \"\(CalendarEventBrowseSpatialIndex.tableName)\""
            )
        } == 2)

        let searchableMissing = try store.browseCalendarEvents(
            parameters: .init(catalogs: [canonicalCatalog], query: "Missing"),
            appViewHost: "localhost",
            now: date("2026-10-11T00:00:00Z")
        )
        expectNoDifference(searchableMissing.events.map(\.name), ["Missing"])
    }

    @Test
    func `opening the store rebuilds browse rows from preserved source projections`() async throws {
        let database = try DatabaseQueue()
        _ = try OpenMusicEventAppViewStore(database: database)
        let canonicalID = ATProto.URI(
            "at://did:plc:venue/events.openmusic.event/3mrdbziccpcaz"
        )!
        let programID = ATProto.URI(
            "at://did:plc:venue/events.openmusic.program/3mrdbziccpcaz"
        )!
        let canonical = try Event(
            id: canonicalID,
            name: "Preserved Canonical Event",
            createdAt: "2026-10-10T12:00:00Z",
            timeZone: .gmt,
            programs: [programID]
        )
        let community = try event(
            uri: "at://did:plc:community/community.lexicon.calendar.event/3mrdbziccpcyy",
            catalog: communityCatalog,
            name: "Preserved Community Event",
            city: "Butte",
            latitude: 46.01,
            longitude: -112.54,
            startsAt: "2026-10-12T01:00:00Z"
        )
        let encodedCommunity = try JSONEncoder().encode(community)
        try await database.write { db in
            try Event.insert { canonical }.execute(db)
            try CommunityCalendarEventProjection.insert {
                CommunityCalendarEventProjection(
                    uri: community.uri.description,
                    cid: "bafy-preserved-community",
                    startsAt: community.startsAt,
                    createdAt: community.createdAt!,
                    sequence: 1,
                    event: encodedCommunity
                )
            }
            .execute(db)
            try CalendarEventBrowseProjection.deleteAll(in: db)
        }

        let rebuiltStore = try OpenMusicEventAppViewStore(database: database)
        let page = try rebuiltStore.browseCalendarEvents(
            parameters: .init(
                catalogs: [canonicalCatalog, communityCatalog],
                limit: 20
            ),
            appViewHost: "localhost"
        )
        expectNoDifference(
            Set(page.events.map(\.name)),
            Set(["Preserved Canonical Event", "Preserved Community Event"])
        )
        let canonicalHasEventViewer = try await database.read { db in
            try CalendarEventBrowseProjection.find(canonicalID.description)
                .select(\.hasEventViewer)
                .fetchOne(db)
        }
        #expect(canonicalHasEventViewer == true)
        let communityHasEventViewer = try await database.read { db in
            try CalendarEventBrowseProjection.find(community.uri.description)
                .select(\.hasEventViewer)
                .fetchOne(db)
        }
        #expect(communityHasEventViewer == false)
        #expect(
            page.events.first { $0.uri == canonicalID }?.links.contains {
                $0.source == "app.openmusicevent.eventViewer"
            } == false
        )

        let detail = try #require(
            try rebuiltStore.calendarEvent(uri: canonicalID, appViewHost: "localhost")
        )
        expectNoDifference(
            detail.links.filter {
                $0.source == "app.openmusicevent.eventViewer"
            }.map { "\($0.name ?? "")|\($0.uri.absoluteString)" },
            ["Enter Event|https://localhost/events/did%3Aplc%3Avenue/3mrdbziccpcaz"]
        )
        let communityDetail = try #require(
            try rebuiltStore.calendarEvent(uri: community.uri, appViewHost: "localhost")
        )
        #expect(!communityDetail.links.contains {
            $0.source == "app.openmusicevent.eventViewer"
        })

        let app = try OpenMusicEventAppViewServer.application(
            configuration: .init(
                host: "127.0.0.1",
                port: 0,
                publicAppViewHost: "localhost"
            ),
            store: rebuiltStore
        )
        var eventURL = URLComponents()
        eventURL.path = "/xrpc/app.openmusicevent.calendar.getEvent"
        eventURL.queryItems = [URLQueryItem(name: "uri", value: canonicalID.description)]
        let eventPath = try #require(eventURL.string)
        try await app.test(.router) { client in
            try await client.execute(
                uri: eventPath,
                method: .get
            ) { response in
                #expect(response.status == .ok)
                let event = try xrpcDecoder().decode(
                    OME.CalendarEvent.self,
                    from: Data(response.body.readableBytesView)
                )
                expectNoDifference(
                    event.links.filter {
                        $0.source == "app.openmusicevent.eventViewer"
                    }.map(\.name),
                    ["Enter Event"]
                )
            }
        }
    }

    @Test
    func `event viewer entry requires detail beyond the browse surface`() throws {
        let id = ATProto.URI(
            "at://did:plc:venue/events.openmusic.event/3mrdbziccpcaz"
        )!
        var event = try Event(
            id: id,
            name: "Browse-only Event",
            createdAt: "2026-10-10T12:00:00Z",
            timeZone: .gmt
        )

        #expect(!event.hasDetailsBeyondBrowse)
        event.programs = [
            ATProto.URI("at://did:plc:venue/events.openmusic.program/3mrdbziccpcaz")!
        ]
        #expect(event.hasDetailsBeyondBrowse)
    }

    @Test
    func `store caches deployment geocoding overrides before rebuilding browse rows`() throws {
        let database = try DatabaseQueue()
        _ = try OpenMusicEventAppViewStore(database: database)
        var community = try event(
            uri: "at://did:plc:community/community.lexicon.calendar.event/3mrdbziccpcoo",
            catalog: communityCatalog,
            name: "Labor Temple Event",
            city: "Bozeman",
            latitude: nil,
            longitude: nil,
            startsAt: "2026-10-12T01:00:00Z"
        )
        community.locations[0].street = "422 East Mendenhall Street"
        community.locations[0].region = "MT"
        community.locations[0].postalCode = "59715"
        community.locations[0].country = "US"
        let encodedCommunity = try JSONEncoder().encode(community)
        try database.write { db in
            try CommunityCalendarEventProjection.insert {
                CommunityCalendarEventProjection(
                    uri: community.uri.description,
                    cid: "bafy-geocoding-override",
                    startsAt: community.startsAt,
                    createdAt: community.createdAt!,
                    sequence: 1,
                    event: encodedCommunity
                )
            }
            .execute(db)
        }

        let rebuiltStore = try OpenMusicEventAppViewStore(
            database: database,
            geocodingOverrides: [
                "422 East Mendenhall Street, Bozeman, MT, 59715, US": .init(
                    latitude: 45.6802,
                    longitude: -111.03126
                )
            ]
        )
        let page = try rebuiltStore.browseCalendarEvents(
            parameters: .init(
                catalogs: [communityCatalog],
                north: 46,
                south: 45,
                east: -110,
                west: -112,
                limit: 20
            ),
            appViewHost: "localhost"
        )

        expectNoDifference(page.events.map(\.name), ["Labor Temple Event"])
        expectNoDifference(page.events.first?.locations.first?.latitude, "45.6802")
        expectNoDifference(page.events.first?.locations.first?.longitude, "-111.03126")
    }

    @Test
    func `browse XRPC accepts both repeated catalogs and preserves single catalog getEvents`() async throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let canonical = try event(
            uri: "at://did:plc:venue/events.openmusic.event/3mrdbziccpcac",
            catalog: canonicalCatalog,
            name: "Canonical",
            city: "Livingston",
            latitude: 45.66,
            longitude: -110.56,
            startsAt: "2026-10-13T01:00:00Z"
        )
        let community = try event(
            uri: "at://did:plc:community/community.lexicon.calendar.event/3mrdbziccpcad",
            catalog: communityCatalog,
            name: "Community",
            city: "Bozeman",
            latitude: 45.68,
            longitude: -111.04,
            startsAt: "2026-10-14T01:00:00Z"
        )
        try await database.write { db in
            try CalendarEventBrowseProjection.upsert(canonical, in: db)
            try CalendarEventBrowseProjection.upsert(community, in: db)
        }
        let app = try OpenMusicEventAppViewServer.application(
            configuration: .init(host: "127.0.0.1", port: 0),
            store: store
        )

        try await app.test(.router) { client in
            let uri = "/xrpc/app.openmusicevent.calendar.browseEvents"
                + "?catalogs=events.openmusic.event"
                + "&catalogs=community.lexicon.calendar.event"
                + "&query=Bozeman&limit=20"
            try await client.execute(uri: uri, method: .get) { response in
                #expect(response.status == .ok)
                let page = try xrpcDecoder().decode(
                    OME.CalendarEvent.Page.self,
                    from: Data(response.body.readableBytesView)
                )
                expectNoDifference(page.events.map(\.name), ["Community"])
            }
            try await client.execute(uri: "/xrpc/app.openmusicevent.calendar.getMapItems", method: .get) { response in
                #expect(response.status == .notFound)
            }
            try await client.execute(
                uri: "/xrpc/app.openmusicevent.calendar.getEvents"
                    + "?catalog=events.openmusic.event&limit=20",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                let page = try xrpcDecoder().decode(
                    OME.CalendarEvent.Page.self,
                    from: Data(response.body.readableBytesView)
                )
                expectNoDifference(page.events.map(\.name), ["Canonical"])
            }
        }
    }

    @Test
    func `address geocoding is enqueued once and cached coordinates rebuild matching events`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        var unresolved = try event(
            uri: "at://did:plc:venue/events.openmusic.event/3mrdbziccpcae",
            catalog: canonicalCatalog,
            name: "Labor Temple Show",
            city: "Bozeman",
            latitude: nil,
            longitude: nil,
            startsAt: "2026-10-15T01:00:00Z"
        )
        unresolved.locations[0].street = "422 E Mendenhall St"
        unresolved.locations[0].region = "MT"
        unresolved.locations[0].postalCode = "59715"
        unresolved.locations[0].country = "US"
        try database.write { db in
            try CalendarEventBrowseProjection.upsert(unresolved, in: db)
            try CalendarEventBrowseProjection.upsert(unresolved, in: db)
        }
        let pendingJob = try store.nextGeocodeJob(now: .now)
        let job = try #require(pendingJob)
        #expect(job.normalizedAddress == "422 e mendenhall st bozeman mt 59715 us")
        #expect(try database.read {
            try CalendarGeocodeJob.all.fetchAll($0).count
        } == 1)

        try store.completeGeocode(
            job: job,
            latitude: 45.6819,
            longitude: -111.0321,
            now: .now
        )
        let page = try store.browseCalendarEvents(
            parameters: .init(
                catalogs: [canonicalCatalog],
                north: 46,
                south: 45,
                east: -110,
                west: -112,
                limit: 20
            ),
            appViewHost: "localhost"
        )
        expectNoDifference(page.events.first?.locations.first?.latitude, "45.6819")
        expectNoDifference(page.events.first?.locations.first?.longitude, "-111.0321")
        #expect(try store.nextGeocodeJob(now: .now) == nil)
    }

    @Test
    func `readiness waits for every configured Hydrant`() async {
        let readiness = OpenMusicEventAppViewReadiness(state: .ready(cursor: nil))
        await readiness.configure(subscriptionIDs: ["private", "public"])
        await readiness.markReady(subscriptionID: "private", cursor: 10)
        let catchingUp = await readiness.snapshot()
        expectNoDifference(catchingUp, .catchingUp)
        await readiness.markReady(subscriptionID: "public", cursor: 20)
        let ready = await readiness.snapshot()
        expectNoDifference(ready, .ready(cursor: nil))
    }

    @Test
    func `Geoapify client sends one encoded address lookup and decodes coordinates`() async throws {
        let client = CalendarEventGeocodingClient.geoapify(
            apiKey: "fixture-key",
            dataForRequest: { request in
                let components = try #require(
                    request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
                )
                #expect(components.scheme == "https")
                #expect(components.host == "api.geoapify.com")
                #expect(components.path == "/v1/geocode/search")
                let query = Dictionary(
                    uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
                )
                #expect(query["text"] == "422 E Mendenhall St, Bozeman, MT 59715, US")
                #expect(query["limit"] == "1")
                #expect(query["format"] == "geojson")
                #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
                #expect(request.value(forHTTPHeaderField: "x-api-key") == "fixture-key")
                let response = HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["content-type": "application/json"]
                )!
                return (
                    Data(#"{"features":[{"properties":{"lat":45.6819,"lon":-111.0321}}]}"#.utf8),
                    response
                )
            }
        )
        let result = try await client.coordinatesForAddress(
            "422 E Mendenhall St, Bozeman, MT 59715, US"
        )
        expectNoDifference(
            result,
            .coordinates(latitude: 45.6819, longitude: -111.0321)
        )
    }

    @Test
    func `geocoding overrides normalize addresses and preserve the fallback`() async throws {
        let client = CalendarEventGeocodingClient.overrides(
            [
                "422 East Mendenhall Street, Bozeman, MT 59715": .init(
                    latitude: 45.68020,
                    longitude: -111.03126
                )
            ],
            fallback: .init { address in
                #expect(address == "Somewhere else")
                return .noResult
            }
        )

        let overridden = try await client.coordinatesForAddress(
            "422 EAST MENDENHALL STREET — Bozeman, MT 59715"
        )
        let fallback = try await client.coordinatesForAddress("Somewhere else")
        expectNoDifference(
            overridden,
            .coordinates(latitude: 45.68020, longitude: -111.03126)
        )
        expectNoDifference(fallback, .noResult)
    }

    private func xrpcDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func event(
        uri: String,
        catalog: ATProto.NSID,
        name: String,
        city: String,
        latitude: Double?,
        longitude: Double?,
        startsAt: String?,
        endsAt: String? = nil
    ) throws -> OME.CalendarEvent {
        return OME.CalendarEvent(
            uri: ATProto.URI(uri)!,
            name: name,
            startsAt: startsAt.map(date),
            endsAt: endsAt.map(date),
            createdAt: ISO8601DateFormatter().date(from: "2026-10-10T12:00:00Z")!,
            locations: [
                .init(
                    name: "Venue",
                    locality: city,
                    latitude: latitude.map { String($0) },
                    longitude: longitude.map { String($0) }
                )
            ],
            organizer: .init(id: DID("did:plc:venue")!),
            source: .init(collection: catalog)
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
