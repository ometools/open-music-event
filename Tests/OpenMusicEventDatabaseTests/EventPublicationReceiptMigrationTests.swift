import ATProto
import CustomDump
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SQLiteData
import Testing

@Suite struct EventPublicationReceiptMigrationTests {
    @Test(arguments: [false, true])
    func `receipt upgrade preserves installed content even when migration fails`(forceFailure: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "installed.sqlite")
        let database = try DatabaseQueue(path: url.path)
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        // Start from the actual preceding schema, with user content and a pre-upgrade receipt.
        try migrator.migrate(database, upTo: "Preserve canonical source Event identities")
        let id = Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")!
        let event = try Event(id: id, name: "Keep my local edits", createdAt: "2026-07-01T00:00:00Z", timeZone: .gmt)
        try database.write { db in
            try Event.insert { event }.execute(db)
            try #sql("""
                INSERT INTO \(quote: EventRecordPublicationReceipt.tableName)
                ("id", "cid", "payloadSHA256", "images")
                VALUES (\(bind: id.description), 'bafyreiexisting', 'existing-hash', '[]')
                """).execute(db)
            if forceFailure {
                // An unexpected existing column makes the forward migration fail transactionally.
                try #sql("""
                    ALTER TABLE \(quote: EventRecordPublicationReceipt.tableName) ADD COLUMN "event" TEXT
                    """).execute(db)
            }
        }
        if forceFailure {
            #expect(throws: (any Error).self) { try migrator.migrate(database) }
        } else {
            try migrator.migrate(database)
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
        expectNoDifference(try database.read { try Event.find(id).fetchOne($0)?.name }, "Keep my local edits")
        let receipt = try database.read { try EventRecordPublicationReceipt.find(id).fetchOne($0) }
        expectNoDifference(receipt?.payloadSHA256, "existing-hash")
        expectNoDifference(receipt?.event, nil)
    }
}
