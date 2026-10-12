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

@Suite struct CalendarMapTileTests {
    let catalog = ATProto.NSID("community.lexicon.calendar.event")
    let otherCatalog = ATProto.NSID("events.openmusic.event")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

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
        var changed = nearby
        changed.name = "New marker title"
        let edited = changed
        try await database.write { db in
            try CalendarEventBrowseProjection.upsert(edited, now: now, in: db)
        }
        let refreshed = try await store.mapTiles.tile(request, store: store)
        #expect(!refreshed.cacheHit && refreshed.etag != populated.etag)
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

    private func fixture(_ id: String, catalog: ATProto.NSID? = nil, latitude: Double? = 45, longitude: Double? = -110, start: TimeInterval = 100) -> OME.CalendarEvent {
        let catalog = catalog ?? self.catalog
        return .init(uri: ATProto.URI("at://did:plc:venue/\(catalog.rawValue)/\(id)")!, name: id,
            startsAt: now.addingTimeInterval(start), createdAt: now,
            locations: [.init(name: "Venue", locality: "Bozeman", latitude: latitude.map(String.init(describing:)), longitude: longitude.map(String.init(describing:)))],
            organizer: .init(id: DID("did:plc:venue")!), source: .init(collection: catalog))
    }
}
