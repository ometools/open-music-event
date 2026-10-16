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

    @Test
    func communityCalendarEventWithATURILinkIsStillProjected() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let id = try #require(ATProto.URI(
            "at://did:plc:calendar/community.lexicon.calendar.event/3mrdbziccpcah"
        ))
        let value: [String: Any] = [
            "$type": "community.lexicon.calendar.event",
            "createdAt": "2026-09-29T10:05:09.087Z",
            "name": "Fred Rubino",
            "startsAt": "2026-10-10T20:00:00-04:00",
            "uris": [
                [
                    "name": "Venue",
                    "uri": "at://did:plc:calendar/town.laugh.db.venue/3mpeyybtl5csr",
                ],
                [
                    "name": "Tickets",
                    "uri": "https://example.com/tickets",
                ],
            ],
        ]
        let version = try AppView.RecordVersion<Data>(
            collection: ATProto.NSID("community.lexicon.calendar.event"),
            uri: id,
            cid: ATProto.CID(rawValue: "bafy-community-event"),
            value: JSONSerialization.data(withJSONObject: value),
            sequence: 1
        )

        try withDependencies {
            $0.defaultDatabase = database
        } operation: {
            _ = try store.appViewRecordIndexer(tangledWebhookConfiguration: nil)
                .apply(.put(version), checkpointID: "community-events")
        }

        let event = try #require(try store.communityCalendarEvent(uri: id))
        expectNoDifference(event.name, "Fred Rubino")
        expectNoDifference(event.links.map(\.name), ["Tickets"])
        expectNoDifference(event.links.map(\.uri.absoluteString), ["https://example.com/tickets"])
        expectNoDifference(
            try store.browseCalendarEvents(
                parameters: .init(
                    catalogs: [ATProto.NSID("community.lexicon.calendar.event")],
                    limit: 100
                ),
                appViewHost: "localhost"
            ).events.map(\.uri),
            [id]
        )
    }

    @Test
    func communityCalendarProjectionBackfillsPresentRawRecords() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let id = try #require(ATProto.URI(
            "at://did:plc:calendar/community.lexicon.calendar.event/3mrdbziccpcai"
        ))
        let value: [String: Any] = [
            "$type": "community.lexicon.calendar.event",
            "createdAt": "2026-09-29T10:05:09.087Z",
            "name": "Backfilled Event",
            "uris": [[
                "name": "Venue",
                "uri": "at://did:plc:calendar/town.laugh.db.venue/3mpeyybtl5csr",
            ]],
        ]
        let version = try AppView.RecordVersion<Data>(
            collection: ATProto.NSID("community.lexicon.calendar.event"),
            uri: id,
            cid: ATProto.CID(rawValue: "bafy-backfilled-community-event"),
            value: JSONSerialization.data(withJSONObject: value),
            sequence: 1
        )
        let rawIndex = AppViewRecordIndexer {
            AppViewRecordIndex<Data>(
                collection: ATProto.NSID("community.lexicon.calendar.event"),
                decode: { $0 }
            )
        }

        try withDependencies {
            $0.defaultDatabase = database
        } operation: {
            _ = try rawIndex.apply(.put(version), checkpointID: "raw-community-events")
        }
        #expect(try store.communityCalendarEvent(uri: id) == nil)

        try database.write { database in
            try CommunityCalendarEventProjection.backfillPresentRecords(in: database)
        }
        try store.rebuildCalendarEventBrowseProjection()

        expectNoDifference(try store.communityCalendarEvent(uri: id)?.name, "Backfilled Event")
        expectNoDifference(
            try store.browseCalendarEvents(
                parameters: .init(
                    catalogs: [ATProto.NSID("community.lexicon.calendar.event")],
                    limit: 100
                ),
                appViewHost: "localhost"
            ).events.map(\.uri),
            [id]
        )
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
