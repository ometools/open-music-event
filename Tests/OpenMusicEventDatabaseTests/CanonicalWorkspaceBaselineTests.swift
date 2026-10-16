import ATProto
import Foundation
import GRDB
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite("Canonical workspace baseline")
struct CanonicalWorkspaceBaselineTests {
    @Test
    func reopeningTheWorkspaceKeepsTheOriginalEventReference() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let application = try DatabaseQueue(path: directory.appending(path: "application.sqlite").path)
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(application)

        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let event = try Event(
            id: eventID,
            name: "Wicked Woods",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        try application.write { db in try Event.insert { event }.execute(db) }

        // Entering the local workspace captures the canonical database once.
        let path = directory.appending(path: "workspace/reference.sqlite").path
        let initial = try CanonicalWorkspaceBaseline.openOrCapture(
            at: path, from: application
        )
        #expect(try initial.read { try Event.find(eventID).fetchOne($0)?.name } == "Wicked Woods")

        // An edit stays in the writable database, while the reference remains unchanged.
        try application.write { db in
            var changed = try #require(try Event.find(eventID).fetchOne(db))
            changed.name = "Wicked Woods Updated"
            let saved = changed
            try Event.upsert { saved }.execute(db)
        }
        let reopened = try CanonicalWorkspaceBaseline.openOrCapture(
            at: path, from: application
        )
        #expect(try reopened.read { try Event.find(eventID).fetchOne($0)?.name } == "Wicked Woods")
        #expect(try application.read { try Event.find(eventID).fetchOne($0)?.name } == "Wicked Woods Updated")
    }
}
