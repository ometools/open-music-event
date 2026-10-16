import ATProto
import CustomDump
import Foundation
import Gzip
import HummingbirdTesting
import OpenMusicEventLexicon
import SQLiteData
import SwiftProtobuf
import Testing

@testable import OpenMusicEventAppViewServer

@Suite(AppViewTestTime()) struct CalendarMapTileTests {
    let catalog = ATProto.NSID("community.lexicon.calendar.event")
    let otherCatalog = ATProto.NSID("events.openmusic.event")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func `unchanged projections preserve tile revisions in active and building generations`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let event = fixture("unchanged")
        try database.write { db in
            try CalendarEventBrowseProjection.upsert(event, now: now, in: db)
        }
        try store.beginMapRebuild()
        #expect(try !store.rebuildMapBatch(limit: 1, now: now))
        let cells = try database.read { try CalendarMapCell.order(by: \.id).fetchAll($0) }
        let revisions = try database.read { try CalendarMapRevision.order(by: \.id).select(\.revision).fetchAll($0) }

        // A replay must not invalidate either the visible tiles or their replacement generation.
        try database.write { db in
            try CalendarEventBrowseProjection.upsert(event, now: now, in: db)
        }
        try database.read { db throws -> Void in
            expectNoDifference(try CalendarMapCell.order(by: \.id).fetchAll(db), cells)
            expectNoDifference(try CalendarMapRevision.order(by: \.id).select(\.revision).fetchAll(db), revisions)
            #expect(try CalendarMapEvent.all.fetchCount(db) == 2)
        }

        // An actual move still updates both generations and reclaims the old cells.
        try database.write { db in
            try CalendarEventBrowseProjection.upsert(
                fixture("unchanged", latitude: -35, longitude: 150), now: now, in: db)
        }
        try database.read { db throws -> Void in
            #expect(try CalendarMapCell.all.fetchCount(db) == 38)
            #expect(try CalendarMapEvent.all.fetchAll(db).allSatisfy { $0.x > 0.9 })
            #expect(try CalendarMapCell.order(by: \.id).fetchAll(db) != cells)
        }
    }

    @Test func `cells track moves missing coordinates deletion rollback and expiration`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let event = fixture("one", latitude: 45, longitude: -110)
        try database.write { db in
            try CalendarEventBrowseProjection.upsert(event, now: now, in: db)
        }
        try database.read { db throws -> Void in
            #expect(try CalendarMapEvent.all.fetchCount(db) == 1)
            #expect(try CalendarMapCell.all.fetchCount(db) == 19)
            #expect(try CalendarMapCell.all.fetchAll(db).allSatisfy { $0.count == 1 && $0.activeCount == 1 })
        }
        let before = try rootTile(store)
        enum Rollback: Error { case requested }
        #expect(throws: Rollback.self) {
            try database.write { db in
                try CalendarEventBrowseProjection.delete(uri: event.uri.description, in: db)
                throw Rollback.requested
            }
        }
        expectNoDifference(try rootTile(store).etag, before.etag)

        let moved = fixture("one", latitude: -35, longitude: 150)
        try database.write { db in
            try CalendarEventBrowseProjection.upsert(moved, now: now, in: db)
        }
        #expect(try rootTile(store).etag != before.etag)
        try database.read { db throws -> Void in
            #expect(try CalendarMapCell.all.fetchCount(db) == 19)
            let record = try #require(try CalendarMapEvent.all.fetchOne(db))
            #expect(record.x > 0.9)
            #expect(record.y > 0.5)
        }
        #expect(try store.expireMapEvents(now: now.addingTimeInterval(200)) == 1)
        #expect(try rootTile(store).featureCount == 0)
        #expect(try rootTile(store, dates: "all").featureCount == 1)

        let unlocated = fixture("one", latitude: nil, longitude: nil)
        try database.write { db in
            try CalendarEventBrowseProjection.upsert(unlocated, now: now, in: db)
        }
        try database.read { db throws -> Void in
            #expect(try CalendarMapCell.all.fetchCount(db) == 0)
            #expect(try CalendarMapEvent.all.fetchCount(db) == 0)
            #expect(try CalendarEventBrowseProjection.all.fetchCount(db) == 1)
        }
        try database.write { db in
            try CalendarEventBrowseProjection.upsert(event, now: now, in: db)
            try CalendarEventBrowseProjection.delete(uri: event.uri.description, in: db)
        }
        #expect(try rootTile(store, dates: "all").featureCount == 0)
    }

    @Test func `generation rebuild catches concurrent changes and preserves source projection`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        try database.write { db in
            for id in ["a", "b", "c"] {
                try CalendarEventBrowseProjection.upsert(fixture(id), now: now, in: db)
            }
        }
        try store.beginMapRebuild()
        #expect(try !store.rebuildMapBatch(limit: 1, now: now))
        try database.write { db in
            try CalendarEventBrowseProjection.delete(uri: fixture("a").uri.description, in: db)
            try CalendarEventBrowseProjection.upsert(fixture("b", latitude: -10, longitude: 100), now: now, in: db)
            try CalendarEventBrowseProjection.upsert(fixture("aa"), now: now, in: db)
        }
        let original = try database.read { try CalendarEventBrowseProjection.order(by: \.uri).fetchAll($0) }
        while try !store.rebuildMapBatch(limit: 1, now: now) {}
        try database.read { db throws -> Void in
            #expect(try CalendarMapBuild.find(0).select(\.active).fetchOne(db) == 2)
            expectNoDifference(try CalendarEventBrowseProjection.order(by: \.uri).fetchAll(db), original)
            let counts = try CalendarMapCell.where { $0.generation.eq(2) && $0.depth.eq(3) }.fetchAll(db)
            #expect(counts.reduce(0) { $0 + $1.count } == 3)
        }
        let tile = try store.mapTile(.init(z: 0, x: 0, y: 0, catalogs: [catalog], dates: "current"), generation: 2)
        #expect(try representedEvents(tile) == 3)
        // Reclamation is bounded and must remove revision metadata as well as points/cells.
        for _ in 0..<100 { try store.expireMapEvents(now: now, limit: 2) }
        try database.read { db throws -> Void in
            #expect(try CalendarMapBuild.find(0).select(\.retiring).fetchOne(db) == 2)
            #expect(try CalendarMapEvent.where { $0.generation.eq(1) }.fetchCount(db) == 0)
            #expect(try CalendarMapCell.where { $0.generation.eq(1) }.fetchCount(db) == 0)
            #expect(try CalendarMapRevision.where { $0.id >= "1|" && $0.id < "1|~" }.fetchCount(db) == 0)
            #expect(try CalendarMapRevision.where { $0.id >= "2|" && $0.id < "2|~" }.fetchCount(db) > 0)
            expectNoDifference(try CalendarEventBrowseProjection.order(by: \.uri).fetchAll(db), original)
        }
    }

    @Test func `tiles are bounded protobuf with complete counts catalogs and date modes`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        try database.write { db in
            for number in 0..<70 {
                try CalendarEventBrowseProjection.upsert(fixture("same-\(number)"), now: now, in: db)
            }
            try CalendarEventBrowseProjection.upsert(fixture("past", start: -200), now: now, in: db)
            try CalendarEventBrowseProjection.upsert(fixture("missing", latitude: nil, longitude: nil), now: now, in: db)
            try CalendarEventBrowseProjection.upsert(fixture("pole", latitude: 89), now: now, in: db)
            try CalendarEventBrowseProjection.upsert(fixture("edge-east", latitude: 0, longitude: 179.9), now: now, in: db)
            try CalendarEventBrowseProjection.upsert(fixture("edge-west", latitude: 0, longitude: -179.9), now: now, in: db)
            try CalendarEventBrowseProjection.upsert(fixture("other", catalog: otherCatalog), now: now, in: db)
        }
        let current = try rootTile(store)
        #expect(try representedEvents(current) == 72)
        #expect(current.featureCount == 3)
        #expect(current.data.count < 4096)
        expectNoDifference(try current.gzip.gunzipped(), current.data)
        #expect(try representedEvents(rootTile(store, dates: "all")) == 73)
        let both = try store.mapTile(.init(z: 0, x: 0, y: 0, catalogs: [catalog, otherCatalog], dates: "current"), generation: 1)
        #expect(try representedEvents(both) == 73)
        let layer = try #require(OmeVectorTile_Tile(serializedBytes: current.data).layers.first)
        #expect(layer.version == 2 && layer.extent == 4096 && layer.name == "events")
        let cluster = try #require(layer.features.first { properties($0, layer: layer)["kind"] == "cluster" })
        let attributes = properties(cluster, layer: layer)
        #expect(attributes["expansionZoom"] == "18")
        let cell = try #require(attributes["clusterID"])
        let first = try store.browseEventSummaries(.init(catalogs: [catalog], limit: 50, cell: cell), now: now)
        #expect(first.events.count == 50 && first.hasMore)
        let second = try store.browseEventSummaries(.init(catalogs: [catalog], cursor: first.cursor, limit: 50, cell: cell), now: now.addingTimeInterval(1000))
        #expect(second.events.count == 20 && !second.hasMore)
        #expect(Set((first.events + second.events).map(\.uri)).count == 70)
    }

    @Test func `publisher marker colors are stable across events catalogs and tiles`() throws {
        // These golden colors are also checked by the browser story.
        for (publisher, color) in [("did:plc:music", "#a05cff"), ("did:plc:venue", "#f354ca"),
                                   ("did:web:venue.example%3A8443", "#df61ff")] {
            expectNoDifference(CalendarMapTile.publisherColor(eventURI: "at://\(publisher)/\(catalog)/first"), color)
            expectNoDifference(CalendarMapTile.publisherColor(eventURI: "at://\(publisher)/\(otherCatalog)/second"), color)
        }

        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        // Separate locations expose individual markers rather than a mixed cluster.
        try database.write { db in
            try CalendarEventBrowseProjection.upsert(fixture("first", latitude: 45, longitude: -110), now: now, in: db)
            try CalendarEventBrowseProjection.upsert(fixture("second", catalog: otherCatalog, latitude: -45, longitude: 110), now: now, in: db)
            try CalendarEventBrowseProjection.upsert(fixture("third", latitude: 45, longitude: 110, publisher: "did:plc:music"), now: now, in: db)
        }
        let tile = try store.mapTile(.init(z: 0, x: 0, y: 0, catalogs: [catalog, otherCatalog], dates: "current"), generation: 1)
        let layer = try #require(OmeVectorTile_Tile(serializedBytes: tile.data).layers.first)
        let colors = try Dictionary(uniqueKeysWithValues: layer.features.map { feature in
            let attributes = properties(feature, layer: layer)
            return (try #require(attributes["name"]), try #require(attributes["color"]))
        })
        expectNoDifference(colors, ["first": "#f354ca", "second": "#f354ca", "third": "#a05cff"])
    }

    @Test func `compact search is global stable scoped and includes unlocated events`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        try database.write { db in
            for id in ["a", "b", "c"] {
                var event = fixture(id, latitude: id == "c" ? nil : 45)
                event.description = String(repeating: "Long description ", count: 10000)
                try CalendarEventBrowseProjection.upsert(event, searchText: "Beyoncé Labor Temple Bozeman", now: now, in: db)
            }
            try CalendarEventBrowseProjection.upsert(fixture("historical", start: -200), now: now, in: db)
        }
        let page = try store.browseEventSummaries(.init(catalogs: [catalog], query: "Beyonce!", limit: 2), now: now)
        expectNoDifference(page.events.map(\.name), ["a", "b"])
        #expect(try JSONEncoder().encode(page).count < 4096)
        let next = try store.browseEventSummaries(.init(catalogs: [catalog], query: "Beyonce!", cursor: page.cursor, limit: 2), now: now.addingTimeInterval(1000))
        expectNoDifference(next.events.map(\.name), ["c"])
        #expect(next.evaluatedAt == now)
        #expect(next.events[0].latitude == nil)
        #expect(try store.browseEventSummaries(.init(catalogs: [otherCatalog], query: "Beyonce!"), now: now).events.isEmpty)
        let scoped = try store.browseEventSummaries(.init(catalogs: [catalog], query: "Labor Temple", north: 46, south: 44, east: -109, west: -111), now: now)
        expectNoDifference(scoped.events.map(\.name), ["a", "b"])
        #expect(throws: OpenMusicEventAppViewStoreError.self) {
            try store.browseEventSummaries(.init(catalogs: [catalog], query: "different", cursor: page.cursor), now: now)
        }
        let map = try store.searchMapItems(.init(uris: (page.events + next.events).map(\.uri), zoom: 2))
        #expect(map.metrics.candidateCount == 2)
        #expect(map.clusters.first?.count == 2)
        #expect(throws: CalendarBrowseError.self) {
            try store.searchMapItems(.init(uris: Array(repeating: fixture("a").uri.description, count: 51), zoom: 2))
        }
    }

    @Test func `tile routes validate inputs negotiate gzip and conditionally revalidate`() async throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let future = fixture("future", start: 100_000_000)
        try await database.write { db in
            try CalendarEventBrowseProjection.upsert(future, now: now, in: db)
        }
        let app = try OpenMusicEventAppViewServer.application(configuration: .init(host: "127.0.0.1", port: 0), store: store)
        try await app.test(.router) { client in
            let uri = "/map/events/0/0/0.mvt?catalogs=community.lexicon.calendar.event"
            let response = try await client.execute(uri: uri, method: .get, headers: [.acceptEncoding: "gzip"])
            #expect(response.status == .ok)
            #expect(response.headers[.contentEncoding] == "gzip")
            let data = try Data(response.body.readableBytesView).gunzipped()
            #expect(try OmeVectorTile_Tile(serializedBytes: data).layers[0].features.count == 1)
            let etag = try #require(response.headers[.eTag])
            let unchanged = try await client.execute(uri: uri, method: .get, headers: [.acceptEncoding: "gzip", .ifNoneMatch: etag])
            #expect(unchanged.status == .notModified)
            #expect(unchanged.body.readableBytes == 0)
            for invalid in ["/map/events/0/1/0.mvt?catalogs=community.lexicon.calendar.event", "/map/events/0/0/0.mvt?catalogs=invalid", "/map/events/0/0/0.mvt?dates=no&catalogs=community.lexicon.calendar.event"] {
                #expect(try await client.execute(uri: invalid, method: .get).status == .badRequest)
            }
            let summaries = try await client.execute(uri: "/xrpc/app.openmusicevent.calendar.browseEventSummaries?catalogs=community.lexicon.calendar.event", method: .get)
            #expect(summaries.status == .ok)
            #expect(!String(decoding: summaries.body.readableBytesView, as: UTF8.self).contains("description"))
            for invalid in [
                "browseEventSummaries?catalogs=app.invalid.catalog",
                "browseEventSummaries?catalogs=community.lexicon.calendar.event&limit=51",
                "browseEventSummaries?catalogs=community.lexicon.calendar.event&cursor=invalid",
                "browseEventSummaries?catalogs=community.lexicon.calendar.event&north=45",
                "getSearchMapItems?uris=invalid&zoom=99",
            ] {
                let rejected = try await client.execute(uri: "/xrpc/app.openmusicevent.calendar.\(invalid)", method: .get)
                #expect(rejected.status == .badRequest)
            }
            let old = try await client.execute(uri: "/xrpc/app.openmusicevent.calendar.getEvents?catalog=community.lexicon.calendar.event&limit=1", method: .get)
            #expect(old.status == .ok)
        }
    }

    @Test func `cache invalidates only touched areas including metadata edits and empty tiles`() async throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let request = try CalendarMapTileRequest(z: 5, x: 6, y: 11, catalogs: [catalog], dates: "all")
        let first = try await store.mapTiles.tile(request, store: store)
        #expect(first.featureCount == 0 && !first.cacheHit)
        #expect(try await store.mapTiles.tile(request, store: store).cacheHit)
        let nearby = fixture("nearby", latitude: 45, longitude: -110)
        try await database.write { db in
            try CalendarEventBrowseProjection.upsert(nearby, now: now, in: db)
        }
        let populated = try await store.mapTiles.tile(request, store: store)
        #expect(populated.featureCount == 1 && !populated.cacheHit)
        #expect(populated.etag != first.etag)
        try await database.write { db in
            try CalendarEventBrowseProjection.upsert(fixture("far", latitude: -35, longitude: 150), now: now, in: db)
        }
        #expect(try await store.mapTiles.tile(request, store: store).cacheHit)
        let cellsBeforeEdit = try await database.read { try CalendarMapCell.order(by: \.id).fetchAll($0) }
        var changed = nearby
        changed.name = "New marker title"
        let edited = changed
        try await database.write { db in
            try CalendarEventBrowseProjection.upsert(edited, now: now, in: db)
        }
        let refreshed = try await store.mapTiles.tile(request, store: store)
        #expect(!refreshed.cacheHit && refreshed.etag != populated.etag)
        let cellsAfterTitle = try await database.read { try CalendarMapCell.order(by: \.id).fetchAll($0) }
        expectNoDifference(cellsAfterTitle, cellsBeforeEdit)

        // Adding and removing artwork refreshes marker content without touching spatial aggregates.
        var illustrated = edited
        illustrated.media = [.init(url: URL(string: "https://example.com/marker.png")!, role: "logo", renderKind: .transparent)]
        let withArtwork = illustrated
        try await database.write { db in
            try CalendarEventBrowseProjection.upsert(withArtwork, now: now, in: db)
        }
        let artwork = try await store.mapTiles.tile(request, store: store)
        #expect(!artwork.cacheHit && artwork.etag != refreshed.etag)
        let cellsWithArtwork = try await database.read { try CalendarMapCell.order(by: \.id).fetchAll($0) }
        expectNoDifference(cellsWithArtwork, cellsBeforeEdit)
        // JSON layout, escaping, and non-rendered metadata are not marker changes.
        try await database.write { db in
            let equivalent = Data(#"{ "renderKind":"transparent", "role":"poster", "url":"https://example.com/marker.png", "alt":"Updated description" }"#.utf8)
            try CalendarEventBrowseProjection.find(edited.uri.description).update {
                $0.markerMedia = #bind(equivalent)
            }.execute(db)
        }
        #expect(try await store.mapTiles.tile(request, store: store).cacheHit)
        // The same image with a different rendering mode does change the tile.
        try await database.write { db in
            let changedRendering = Data(#"{"url":"https://example.com/marker.png","renderKind":"fullImage"}"#.utf8)
            try CalendarEventBrowseProjection.find(edited.uri.description).update {
                $0.markerMedia = #bind(changedRendering)
            }.execute(db)
        }
        let rerendered = try await store.mapTiles.tile(request, store: store)
        #expect(!rerendered.cacheHit && rerendered.etag != artwork.etag)
        try await database.write { db in
            try CalendarEventBrowseProjection.upsert(edited, now: now, in: db)
        }
        let removed = try await store.mapTiles.tile(request, store: store)
        #expect(!removed.cacheHit && removed.etag != artwork.etag)
        let cellsWithoutArtwork = try await database.read { try CalendarMapCell.order(by: \.id).fetchAll($0) }
        expectNoDifference(cellsWithoutArtwork, cellsBeforeEdit)

        // Replaying identical content leaves the refreshed tile cached.
        try await database.write { db in
            try CalendarEventBrowseProjection.upsert(edited, now: now, in: db)
        }
        #expect(try await store.mapTiles.tile(request, store: store).cacheHit)
    }

    @Test func `publishers sort by total count across pages search and record changes`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        try database.write { db in
            for index in 0..<52 {
                try CalendarEventBrowseProjection.upsert(fixture("first", latitude: nil, longitude: nil,
                    publisher: "did:plc:publisher\(index)"), now: now, in: db)
            }
            for (publisher, id) in [(50, "second"), (51, "second"), (51, "third")] {
                try CalendarEventBrowseProjection.upsert(fixture(id, start: -100,
                    publisher: "did:plc:publisher\(publisher)"), now: now, in: db)
            }
            try CalendarEventBrowseProjection.upsert(fixture("native", catalog: otherCatalog,
                publisher: "did:plc:publisher50"), now: now, in: db)
        }
        let first = try store.calendarPublishers(.init())
        expectNoDifference(first.publishers.prefix(2).map(\.did), ["did:plc:publisher51", "did:plc:publisher50"])
        expectNoDifference(first.publishers.prefix(2).map(\.eventCount), [3, 2])
        let second = try store.calendarPublishers(.init(cursor: #require(first.cursor)))
        let all = first.publishers + second.publishers
        expectNoDifference(all.count, 53)
        expectNoDifference(Set(all.map(\.id)).count, 53)
        expectNoDifference(all.map(\.eventCount), all.map(\.eventCount).sorted(by: >))
        #expect(second.cursor == nil)
        expectNoDifference(all.last?.eventCount, 0)
        let search = try store.calendarPublishers(.init(query: "publisher5"))
        expectNoDifference(search.publishers.map(\.eventCount), [3, 2, 1])
        try database.write { db in
            try CalendarEventBrowseProjection.find("at://did:plc:publisher51/\(catalog.rawValue)/third").delete().execute(db)
        }
        let changed = try store.calendarPublishers(.init())
        expectNoDifference(changed.publishers.prefix(2).map(\.did), ["did:plc:publisher50", "did:plc:publisher51"])
        expectNoDifference(changed.publishers.prefix(2).map(\.eventCount), [2, 2])
    }

    @Test func `publisher choices agree across list tile cluster and empty selections`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let comedy = fixture("comedy", publisher: CalendarPublisher.laughTown)
        let concert = fixture("concert")
        let native = fixture("native", catalog: otherCatalog)
        try database.write { db in
            for event in [comedy, concert, native] {
                try CalendarEventBrowseProjection.upsert(event, now: now, in: db)
            }
        }
        // OME defaults hide the publisher, not events guessed to be comedy.
        let directory = try store.calendarPublishers(.init())
        let defaults = directory.defaults
        var query = CalendarBrowseQuery.Parameters(catalogs: [catalog, otherCatalog],
            publisherMode: defaults.mode.rawValue, publishers: defaults.publishers)
        expectNoDifference(try store.browseEventSummaries(query, now: now).events.map(\.name).sorted(), ["concert", "native"])
        let filtered = try CalendarMapTileRequest(z: 0,x: 0,y: 0,catalogs: [catalog,otherCatalog], dates: "current",
            publisherMode: defaults.mode.rawValue,publishers: defaults.publishers)
        let tile = try store.mapTile(filtered,generation: 1)
        expectNoDifference(try representedEvents(tile), 2)
        let layer = try #require(try OmeVectorTile_Tile(serializedBytes: tile.data).layers.first)
        query.cell = try #require(properties(layer.features[0], layer: layer)["clusterID"])
        expectNoDifference(try store.browseEventSummaries(query, now: now).events.map(\.name).sorted(), ["concert", "native"])

        // Only selected affects Community Calendar, leaving the OME toggle independent.
        query.publisherMode = "only"
        expectNoDifference(try store.browseEventSummaries(query, now: now).events.map(\.name).sorted(), ["comedy", "native"])
        query.publishers = []
        expectNoDifference(try store.browseEventSummaries(query, now: now).events.map(\.name), ["native"])
        let empty = try CalendarMapTileRequest(z: 0,x: 0,y: 0,catalogs: [catalog],dates: "current",publisherMode: "only")
        expectNoDifference(try store.mapTile(empty,generation: 1).featureCount, 0)
        query.catalogs = [catalog]
        expectNoDifference(try store.browseEventSummaries(query, now: now).events.count, 0)
    }

    @Test func `publisher summaries survive moves expiration deletion rollback and rebuild`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        var event = fixture("concert")
        try database.write { try CalendarEventBrowseProjection.upsert(event, now: now, in: $0) }
        let publisher = try #require(try store.calendarPublishers(.init(query: "did:plc:venue")).publishers.first)
        let request = try CalendarMapTileRequest(z: 0,x: 0,y: 0,catalogs: [catalog],dates: "current",publisherMode: "only",publishers: [publisher.id])
        let original = try store.mapTile(request,generation: 1)
        event = fixture("concert",latitude: -35,longitude: 150)
        try database.write { try CalendarEventBrowseProjection.upsert(event, now: now, in: $0) }
        #expect(try store.mapTile(request,generation: 1).etag != original.etag)
        enum Rollback: Error { case requested }
        #expect(throws: Rollback.self) {
            try database.write { db in
                try CalendarEventBrowseProjection.delete(uri: event.uri.description, in: db)
                throw Rollback.requested
            }
        }
        expectNoDifference(try representedEvents(store.mapTile(request,generation: 1)),1)
        _ = try store.expireMapEvents(now: now.addingTimeInterval(200))
        expectNoDifference(try store.mapTile(request,generation: 1).featureCount,0)
        try store.beginMapRebuild()
        while try !store.rebuildMapBatch(limit: 1, now: now) {}
        expectNoDifference(try representedEvents(store.mapTile(request,generation: 2)),1)
        expectNoDifference(try store.calendarPublishers(.init(query: publisher.did)).publishers.first?.id,publisher.id)
        try database.write { try CalendarEventBrowseProjection.delete(uri: event.uri.description,in: $0) }
        expectNoDifference(try store.mapTile(request,generation: 2).featureCount,0)
        expectNoDifference(try database.read { try CalendarPublisherMapCell.all.fetchCount($0) },0)
    }

    @Test func `publisher cursor fingerprint and cache isolate equivalent and different lenses`() async throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        try await database.write { db in
            for id in ["one", "two"] { try CalendarEventBrowseProjection.upsert(fixture(id),now: now,in: db) }
            try CalendarEventBrowseProjection.upsert(fixture("comedy",publisher: CalendarPublisher.laughTown),now: now,in: db)
        }
        let defaults = try store.calendarPublishers(.init()).defaults
        var query = CalendarBrowseQuery.Parameters(catalogs: [catalog],limit: 1,publisherMode: "allExcept",publishers: defaults.publishers)
        query.cursor = try #require(store.browseEventSummaries(query,now: now).cursor)
        query.publishers = defaults.publishers + defaults.publishers
        expectNoDifference(try store.browseEventSummaries(query,now: now).events.count,1)
        query.publisherMode = "only"
        #expect(throws: (any Error).self) { try store.browseEventSummaries(query,now: now) }
        let excluded = try CalendarMapTileRequest(z: 0,x: 0,y: 0,catalogs: [catalog],dates: "current",publishers: defaults.publishers)
        let only = try CalendarMapTileRequest(z: 0,x: 0,y: 0,catalogs: [catalog],dates: "current",publisherMode: "only",publishers: defaults.publishers)
        let excludedTile = try await store.mapTiles.tile(excluded,store: store)
        let onlyTile = try await store.mapTiles.tile(only,store: store)
        expectNoDifference(try representedEvents(excludedTile),2)
        expectNoDifference(try representedEvents(onlyTile),1)
        #expect(try await store.mapTiles.tile(excluded,store: store).cacheHit)
        #expect(throws: CalendarBrowseError.self) { try CalendarPublisherLens(mode: "unexpected") }
        #expect(throws: CalendarBrowseError.self) { try CalendarPublisherLens(publishers: [-1]) }
    }

    private func rootTile(_ store: OpenMusicEventAppViewStore, dates: String = "current") throws -> CalendarMapTile {
        try store.mapTile(.init(z: 0, x: 0, y: 0, catalogs: [catalog], dates: dates), generation: 1)
    }

    private func representedEvents(_ tile: CalendarMapTile) throws -> Int {
        let layer = try #require(OmeVectorTile_Tile(serializedBytes: tile.data).layers.first)
        return layer.features.reduce(0) { total, feature in
            total + (Int(properties(feature, layer: layer)["count"] ?? "1") ?? 0)
        }
    }

    private func properties(_ feature: OmeVectorTile_Tile.Feature, layer: OmeVectorTile_Tile.Layer) -> [String: String] {
        var result: [String: String] = [:]
        for index in stride(from: 0, to: feature.tags.count, by: 2) {
            let value = layer.values[Int(feature.tags[index + 1])]
            result[layer.keys[Int(feature.tags[index])]] = value.hasStringValue ? value.stringValue : String(value.intValue)
        }
        return result
    }

    private func fixture(_ id: String, catalog: ATProto.NSID? = nil, latitude: Double? = 45, longitude: Double? = -110, start: TimeInterval = 100, publisher: String = "did:plc:venue") -> OME.CalendarEvent {
        let catalog = catalog ?? self.catalog
        return .init(uri: ATProto.URI("at://\(publisher)/\(catalog.rawValue)/\(id)")!, name: id,
            startsAt: now.addingTimeInterval(start), createdAt: now,
            locations: [.init(name: "Venue", locality: "Bozeman", latitude: latitude.map(String.init(describing:)), longitude: longitude.map(String.init(describing:)))],
            organizer: .init(id: DID("did:plc:venue")!), source: .init(collection: catalog))
    }
}
