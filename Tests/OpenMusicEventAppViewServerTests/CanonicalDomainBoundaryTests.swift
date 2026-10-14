import ATProto
import ATProtoAppView
import CustomDump
import Dependencies
import Foundation
import HummingbirdTesting
import OpenMusicEventLexicon
import SQLiteData
import Testing
@testable import OpenMusicEventAppViewServer

@Suite(AppViewTestTime())
struct CanonicalDomainBoundaryTests {
    @Test func `database storage preserves lexicon semantics and still rejects invalid publication`() throws {
        let database = try DatabaseQueue()
        _ = try OpenMusicEventAppViewStore(database: database)
        let payload = Data(#"{"$type":"events.openmusic.event","name":"Wicked Woods 2026","createdAt":"2026-08-01T12:00:00Z","start":{"$type":"events.openmusic.defs#day","value":"2026-09-04"},"end":{"$type":"events.openmusic.defs#day","value":"2026-09-07"},"locations":[{"locators":[{"$type":"community.lexicon.location.geo","latitude":"50.1","longitude":"-115.5"},{"$type":"test.future.locator","value":"preserve"}]}],"links":[{"url":"https://example.com/tickets","role":{"$type":"events.openmusic.defs#ticketsLink"}},{"url":"https://example.com","title":"Website"}],"media":[{"$type":"test.future.media","values":[2,1]}]}"#.utf8)
        let tree = try JSONDecoder().decode(Lexicon.JSONValue.self, from: payload)
        let id = Event.ID("at://did:plc:venue/events.openmusic.event/3mrdbziccpcaa")!
        let event = try Event.decodeLexicon(tree, metadata: .init(uri: id, cid: "bafy-original"))
        try database.write { try Event.insert { event }.execute($0) }
        var restored = try database.read { try #require(try Event.find(id).fetchOne($0)) }
        expectNoDifference(restored, event)
        expectNoDifference(try restored.encodeLexicon(), tree)

        // Local storage is lossless even before validation, but not publication authority.
        restored.locations?[0].name = ""
        try database.write { db in
            try Event.find(id).update { $0.locations = #bind(restored.locations) }.execute(db)
        }
        let invalid = try database.read { try #require(try Event.find(id).fetchOne($0)) }
        expectNoDifference(invalid.locations, restored.locations)
        #expect(throws: (any Error).self) { try invalid.encodeLexicon() }
        #expect(throws: (any Error).self) { try invalid.validateReferences() }

        // Storage must still reject malformed field types, not invent a value.
        let malformed: Lexicon.JSONValue = ["locators": [["$type": "community.lexicon.location.geo", "latitude": 123, "longitude": "-115"]]]
        #expect(throws: (any Error).self) {
            try malformed.decoded(as: Lexicon.Storage<Event.Location>.self)
        }
    }

    @Test func `native reads preserve published payload and exclude imported domain rows`() async throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let id = Event.ID("at://did:plc:venue/events.openmusic.event/3mrdbziccpcaa")!
        let importedID = Event.ID("at://did:plc:calendar/community.lexicon.calendar.event/3mrdbziccpcab")!
        let payload = Data(#"{"$type":"events.openmusic.event","name":"Published festival","createdAt":"2026-08-01T12:00:00Z","timeZone":"America/Denver","start":{"$type":"events.openmusic.defs#day","value":"2026-09-04"},"futureExtension":{"meaning":"retain me"}}"#.utf8)
        let cid = ATProto.CID(rawValue: "bafy-published-original")

        // Native publication enters through the same indexer as the live AppView.
        try withDependencies { $0.defaultDatabase = database } operation: {
            _ = try store.appViewRecordIndexer(tangledWebhookConfiguration: nil).apply(
                .put(AppView.RecordVersion<Data>(collection: "events.openmusic.event", uri: id,
                    cid: cid, value: payload, sequence: 1)), checkpointID: "canonical-boundary")
        }

        // Domain storage is not evidence of publication. Its local representation
        // can differ, and an external row must not acquire an OME publication identity.
        let imported = try Event(projecting: importedID, cid: "bafy-imported-original",
                                 projectionVersion: 1, name: "Imported calendar event",
                                 createdAt: "2026-08-01T12:00:00Z")
        try await database.write { db in
            try Event.find(id).update { $0.name = "Local domain representation" }.execute(db)
            try Event.insert { imported }.execute(db)
        }

        let expected = try JSONDecoder().decode(Lexicon.JSONValue.self, from: payload)
        let record = try #require(try store.indexedEvent(id: id))
        expectNoDifference(record.value, expected)
        expectNoDifference(record.cid, cid)
        let page = try store.eventPage(cursor: nil, limit: 1)
        expectNoDifference(page.events, [record])
        #expect(page.cursor == nil)
        #expect(try store.indexedEvent(id: importedID) == nil)
        #expect(try store.event(id: importedID) == nil)
        #expect(try store.eventViewerContent(id: importedID) == nil)
        #expect(try await store.eventBundles.bundle(id: importedID, store: store) == nil)

        let roots = try TestAppViewRoots()
        defer { roots.remove() }
        let app = try OpenMusicEventAppViewServer.application(configuration: roots.configuration, store: store)
        try await app.test(.router) { client in
            for endpoint in ["events.openmusic.getEvent", "events.openmusic.getEventBundle"] {
                var url = URLComponents()
                url.path = "/xrpc/\(endpoint)"
                url.queryItems = [.init(name: "uri", value: importedID.description)]
                try await client.execute(uri: try #require(url.string), method: .get) { response in
                    if endpoint == "events.openmusic.getEventBundle" {
                        #expect(response.status == .badRequest)
                    } else {
                        #expect(response.status == .notFound)
                    }
                }
            }
            try await client.execute(uri: "/xrpc/events.openmusic.getEvents?limit=100", method: .get) { response in
                #expect(response.status == .ok)
                let page = try JSONDecoder().decode(Event.Page.self, from: Data(response.body.readableBytesView))
                expectNoDifference(page.events, [record])
            }
        }
    }
}
