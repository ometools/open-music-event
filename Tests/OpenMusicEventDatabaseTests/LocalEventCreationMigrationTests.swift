import CustomDump
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite struct LocalEventCreationMigrationTests {
    @Test(arguments: [false, true])
    func `creation migration preserves existing events on success and failure`(forceFailure: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: "installed.sqlite").path
        let database = try DatabaseQueue(path: path)
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database, upTo: "Retain verified Event content for workspace review")
        let id = Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")!
        let event = try Event(id: id, name: "Keep my event", createdAt: "2026-07-01T00:00:00Z", timeZone: .gmt)
        try database.write { db in
            try Event.insert { event }.execute(db)
            if forceFailure {
                try #sql("CREATE TABLE \(quote: LocallyCreatedEvent.tableName) (id TEXT PRIMARY KEY)").execute(db)
            }
        }
        if forceFailure {
            #expect(throws: (any Error).self) { try migrator.migrate(database) }
        } else {
            try migrator.migrate(database)
        }
        #expect(FileManager.default.fileExists(atPath: path))
        expectNoDifference(try database.read { try Event.find(id).fetchOne($0) }, event)
        expectNoDifference(try database.read { try LocallyCreatedEvent.all.fetchAll($0) }, [])
    }
}
