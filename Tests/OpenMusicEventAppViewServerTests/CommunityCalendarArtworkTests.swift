import ATProto
import ATProtoAppView
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventLexicon
import SQLiteData
import Testing

@testable import OpenMusicEventAppViewServer

@Suite(AppViewTestTime()) struct CommunityCalendarArtworkTests {
    @Test func `published artwork reaches rows and details and disappears when removed`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let indexer = store.appViewRecordIndexer(tangledWebhookConfiguration: nil)
        let catalog = ATProto.NSID("community.lexicon.calendar.event")
        let uri = ATProto.URI("at://did:plc:venue/community.lexicon.calendar.event/concert")!
        let blobCID = "bafkreigdcl6knsg6xgvcsrmdehb37xwlstbvcv3kbbmrc37ormgg2ll3g4"
        var value: [String: Any] = [
            "$type": catalog.rawValue, "name": "Concert with artwork", "createdAt": "2026-10-01T12:00:00Z",
            "poster": ["url": "https://laugh.town/cdn/p/posters/concert.webp"],
            "media": [["role": "thumbnail", "alt": "Concert poster", "content": [
                "$type": "blob", "ref": ["$link": blobCID], "mimeType": "image/webp", "size": 125612
            ]]]
        ]
        try withDependencies { $0.defaultDatabase = database } operation: {
            let record = try AppView.RecordVersion<Data>(collection: catalog, uri: uri,
                cid: ATProto.CID(rawValue: "bafy-artwork"), value: JSONSerialization.data(withJSONObject: value), sequence: 1)
            _ = try indexer.apply(.put(record), checkpointID: "artwork")
        }
        let detail = try #require(try store.communityCalendarEvent(uri: uri))
        expectNoDifference(detail.media.count, 2)
        expectNoDifference(detail.media.first?.url.absoluteString, "https://laugh.town/cdn/p/posters/concert.webp")
        expectNoDifference(detail.media.map(\.renderKind), [.fullImage, .fullImage])
        expectNoDifference(detail.media.last?.alt, "Concert poster")
        let row = try #require(try store.browseEventSummaries(.init(catalogs: [catalog], dates: "all")).events.first)
        expectNoDifference(row.markerMedia, detail.media.first)
        #expect(try store.containsWebBlob(record: uri, cid: blobCID))
        #expect(try !store.containsWebBlob(record: uri, cid: "unrelated"))

        // Simulate the previous projection while keeping the original indexed record intact.
        var legacy = detail
        legacy.media = []
        let legacyData = try JSONEncoder().encode(legacy)
        try database.write { db in
            try CommunityCalendarEventProjection.find(uri.description).update { $0.event = #bind(legacyData) }.execute(db)
            try CalendarEventBrowseProjection.upsert(legacy, in: db)
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = ?", arguments: ["Preserve community calendar event artwork"])
        }
        let migrated = try OpenMusicEventAppViewStore(database: database)
        expectNoDifference(try migrated.communityCalendarEvent(uri: uri)?.media, detail.media)
        expectNoDifference(try migrated.browseEventSummaries(.init(catalogs: [catalog], dates: "all")).events.first?.markerMedia, detail.media.first)

        // A publisher removes the artwork: neither the row nor the blob route keeps stale media.
        value.removeValue(forKey: "poster")
        value.removeValue(forKey: "media")
        try withDependencies { $0.defaultDatabase = database } operation: {
            let record = try AppView.RecordVersion<Data>(collection: catalog, uri: uri,
                cid: ATProto.CID(rawValue: "bafy-without-artwork"), value: JSONSerialization.data(withJSONObject: value), sequence: 2)
            _ = try indexer.apply(.put(record), checkpointID: "artwork")
        }
        expectNoDifference(try store.communityCalendarEvent(uri: uri)?.media, [])
        expectNoDifference(try store.browseEventSummaries(.init(catalogs: [catalog], dates: "all")).events.first?.markerMedia, nil)
        #expect(try !store.containsWebBlob(record: uri, cid: blobCID))
    }

    @Test func `invalid optional artwork does not hide an event or become a script URL`() throws {
        let uri = ATProto.URI("at://did:plc:venue/community.lexicon.calendar.event/concert")!
        let data = Data(#"{"poster":{"url":"javascript:alert(1)"},"media":[{"content":{"$type":"blob","mimeType":"video/mp4","ref":{"$link":"video"}}},{"content":null}]}"#.utf8)
        expectNoDifference(try CommunityCalendarEventProjection.artwork(data, uri: uri), [])
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OME_ARTWORK_SNAPSHOT"] != nil))
    func `backfills existing indexed artwork on an isolated database`() throws {
        let sourcePath = try #require(ProcessInfo.processInfo.environment["OME_ARTWORK_SNAPSHOT"])
        var configuration = Configuration()
        configuration.readonly = true
        let source = try DatabaseQueue(path: sourcePath, configuration: configuration)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ome-artwork-validation-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try DatabaseQueue(path: directory.appendingPathComponent("appview.sqlite").path)
        try source.backup(to: database)
        let before = try database.read { try CommunityCalendarEventProjection.all.fetchCount($0) }
        let start = ContinuousClock.now
        _ = try OpenMusicEventAppViewStore(database: database)
        expectNoDifference(try database.read { try CommunityCalendarEventProjection.all.fetchCount($0) }, before)
        expectNoDifference(try database.read { try String.fetchOne($0, sql: "PRAGMA quick_check") }, "ok")
        let count = try database.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM \"\(CommunityCalendarEventProjection.tableName)\" WHERE json_array_length(event, '$.media') > 0") }
        #expect((count ?? 0) > 0)
        print("Artwork backfill: \(count ?? 0) events with images, \(before) preserved events, \(start.duration(to: .now)); database: \(directory.path)")
    }
}
