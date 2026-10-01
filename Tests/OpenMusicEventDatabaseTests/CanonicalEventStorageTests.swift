import ATProto
import CustomDump
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite
struct CanonicalEventStorageTests {
    typealias Event = OpenMusicEventLexicon.Event

    @Test
    func eventEditsSurviveReopeningWithoutReplacingTheirRecordIdentity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("events.sqlite").path
        let id = try #require(ATProto.URI("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"))
        var event = try Event(
            id: id,
            name: "Wicked Woods",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: try #require(TimeZone(identifier: "America/Denver")),
            description: "A weekend in the woods",
            start: .known(.day(.init(value: try #require(LocalDate("2026-09-04"))))),
            end: .known(.day(.init(value: try #require(LocalDate("2026-09-07"))))),
            media: [.unknown(.object([
                "$type": "events.example.defs#video",
                "url": "https://example.com/recap.mp4",
            ]))],
            rsvpExpected: true
        )

        // The application migration creates storage for the public model itself.
        do {
            let database = try DatabaseQueue(path: path)
            var migrator = DatabaseMigrator()
            OME.DatabaseMigrations.register(into: &migrator)
            try migrator.migrate(database)
            try database.write { db in
                try Event.insert { event }.execute(db)
                try #sql("""
                    CREATE TABLE attendeeNotes (
                        event TEXT PRIMARY KEY REFERENCES "events.openmusic.event"(id)
                          ON DELETE CASCADE,
                        note TEXT NOT NULL
                    ) STRICT
                    """).execute(db)
                try #sql("""
                    INSERT INTO attendeeNotes VALUES (\(id), 'Meet friends at the gate')
                    """).execute(db)
            }

            // Saving an edit must update in place, never replace the row and cascade-delete notes.
            event.name = "Wicked Woods 2026"
            event.description = nil
            event.end = nil
            try database.write { try Event.upsert { event }.execute($0) }
        }

        let reopened = try DatabaseQueue(path: path)
        expectNoDifference(try reopened.read { try Event.find(id).fetchOne($0) }, event)
        let note = try reopened.read {
            try #sql("SELECT note FROM attendeeNotes WHERE event = \(id)", as: String.self).fetchOne($0)
        }
        expectNoDifference(note, "Meet friends at the gate")
        #expect(try event.encodeLexicon().object?["description"] == nil)
        #expect(try event.encodeLexicon().object?["end"] == nil)

        // Deleting this event deliberately removes its dependent content.
        try reopened.write { try Event.find(id).delete().execute($0) }
        #expect(try reopened.read { try Event.all.fetchCount($0) } == 0)
        #expect(try reopened.read { try #sql("SELECT count(*) FROM attendeeNotes", as: Int.self).fetchOne($0) } == 0)
    }

    @Test
    func installingCanonicalStoragePreservesExistingEventAndAttendeeRows() throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database, upTo: "Create OpenMusicEvent event site maps")
        try database.write { db in
            try #sql("""
                INSERT INTO "app.openmusicevent.organizer" (id) VALUES ('did:plc:organizer')
                """).execute(db)
            try #sql("""
                INSERT INTO "app.openmusicevent.event" (organizerID, eventID, name, timeZone)
                VALUES ('did:plc:organizer', '2026', 'Wicked Woods', 'America/Denver')
                """).execute(db)
            try #sql("""
                INSERT INTO installedEvents (organizerID, eventID)
                VALUES ('did:plc:organizer', '2026')
                """).execute(db)
        }
        try migrator.migrate(database)
        #expect(try database.read { try Event.all.fetchCount($0) } == 0)
        expectNoDifference(
            try database.read {
                try #sql("""
                    SELECT name FROM "app.openmusicevent.event"
                    WHERE organizerID = 'did:plc:organizer' AND eventID = '2026'
                    """, as: String.self).fetchOne($0)
            },
            "Wicked Woods"
        )
        #expect(try database.read { try InstalledEventRecord.all.fetchCount($0) } == 1)
        #expect(try database.read { try InstalledEvent.all.fetchCount($0) } == 0)
        #expect(try database.read {
            try #sql("""
                SELECT count(*) FROM pragma_table_info('app.openmusicevent.event')
                WHERE name IN ('policies', 'categoryConfigs')
                """, as: Int.self).fetchOne($0)
        } == 0)
    }

    @Test
    func aConflictingSchemaFailsWithoutErasingExistingData() throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database, upTo: "Create OpenMusicEvent event site maps")
        try database.write { db in
            try #sql("""
                CREATE TABLE "events.openmusic.event" (sentinel TEXT NOT NULL)
                """).execute(db)
            try #sql("""
                INSERT INTO "events.openmusic.event" VALUES ('Keep this database recoverable')
                """).execute(db)
        }
        #expect(throws: (any Error).self) { try migrator.migrate(database) }
        expectNoDifference(
            try database.read {
                try #sql("SELECT sentinel FROM \"events.openmusic.event\"", as: String.self).fetchOne($0)
            },
            "Keep this database recoverable"
        )
    }
}
