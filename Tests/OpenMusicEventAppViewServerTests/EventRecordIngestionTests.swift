import ATProto
import ATProtoAppView
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventLexicon
import SQLiteData
import Testing

@testable import OpenMusicEventAppViewServer

@Suite
struct EventRecordIngestionTests {
    typealias Event = OpenMusicEventLexicon.Event

    @Test
    func protocolCreatesUpdatesAndDeletesUseTheSameEventID() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let id: Event.ID = try #require(.init("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"))
        let indexer = store.appViewRecordIndexer(tangledWebhookConfiguration: nil)
        try withDependencies {
            $0.defaultDatabase = database
        } operation: {
            let first = try version(id: id, name: "Wicked Woods", sequence: 1)
            _ = try indexer.apply(.put(first), checkpointID: "events")
            let event = try #require(try store.event(id: id))
            expectNoDifference(event.id, id)
            expectNoDifference(event.cid, first.cid)
            expectNoDifference(event.name, "Wicked Woods")

            try database.write { db in
                try #sql("""
                    CREATE TABLE attendeeNotes (
                        event TEXT PRIMARY KEY REFERENCES "events.openmusic.event"(id) ON DELETE CASCADE,
                        note TEXT NOT NULL
                    ) STRICT
                    """).execute(db)
                try #sql("INSERT INTO attendeeNotes VALUES (\(id), 'Meet at the gate')").execute(db)
            }

            let updated = try version(id: id, name: "Wicked Woods 2026", sequence: 2)
            _ = try indexer.apply(.put(updated), checkpointID: "events")
            _ = try indexer.apply(.put(first), checkpointID: "events")
            let refreshed = try #require(try store.event(id: id))
            expectNoDifference(refreshed.id, id)
            expectNoDifference(refreshed.cid, updated.cid)
            expectNoDifference(refreshed.name, "Wicked Woods 2026")
            #expect(try database.read {
                try #sql("SELECT count(*) FROM attendeeNotes", as: Int.self).fetchOne($0)
            } == 1)

            _ = try indexer.apply(.delete(.init(
                collection: ATProto.NSID(Event.lexiconID.rawValue), uri: id, sequence: 3
            )), checkpointID: "events")
            #expect(try store.event(id: id) == nil)
            _ = try indexer.apply(.put(updated), checkpointID: "events")
            #expect(try store.event(id: id) == nil)
        }
    }

    @Test
    func invalidEventDoesNotAdvanceItsCheckpointOrReplaceStoredContent() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let id: Event.ID = try #require(.init("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"))
        let indexer = store.appViewRecordIndexer(tangledWebhookConfiguration: nil)
        try withDependencies {
            $0.defaultDatabase = database
        } operation: {
            _ = try indexer.apply(.put(version(id: id, name: "Keep me", sequence: 1)), checkpointID: "events")
            let invalid = try version(
                id: id, name: "Invalid", sequence: 2,
                categories: ["at://did:plc:another/social.ome.category/3mrdbziccpcai"]
            )
            #expect(throws: (any Error).self) {
                try indexer.apply(.put(invalid), checkpointID: "events")
            }
            expectNoDifference(try store.event(id: id)?.name, "Keep me")
            expectNoDifference(try AppViewIndexDatabase.checkpoint(id: "events")?.sequence, 1)
        }
    }

    private func version(
        id: Event.ID,
        name: String,
        sequence: Int64,
        categories: [String]? = nil
    ) throws -> AppView.RecordVersion<Data> {
        var object: [String: Any] = [
            "$type": "events.openmusic.event",
            "name": name,
            "createdAt": "2026-09-01T12:00:00Z",
            "timeZone": "America/Denver",
        ]
        if let categories { object["categories"] = categories }
        return try .init(
            collection: ATProto.NSID(Event.lexiconID.rawValue),
            uri: id,
            cid: ATProto.CID(rawValue: "bafy-event-\(sequence)"),
            value: JSONSerialization.data(withJSONObject: object),
            sequence: sequence
        )
    }
}
