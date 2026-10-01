import ATProto
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
@testable import OpenMusicEventSourceEditing
import SQLiteData
import Testing

@Suite("Canonical workspace record changes")
struct CanonicalWorkspaceRecordChangesTests {
    @Test
    func detectsOrganizerOwnedRecordsWithoutCountingOtherRepositories() throws {
        let working = try DatabaseQueue()
        let baseline = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(working)
        try migrator.migrate(baseline)
        let owner = try #require(DID("did:plc:organizer"))
        let workspace = SourceWorkspace(
            organizerID: owner,
            repository: "tangled.org/organizer/events",
            branch: "main"
        )
        let reference = SourceBaselineDatabase(path: "baseline", database: baseline)
        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let event = try Event(
            id: eventID,
            name: "Wicked Woods",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        try working.write { db in try Event.insert { event }.execute(db) }
        try baseline.write { db in try Event.insert { event }.execute(db) }

        try working.read { db in
            let hasChanges = try CanonicalWorkspaceRecordChanges.hasChanges(
                workspace: workspace, in: db, referenceDatabase: reference
            )
            #expect(!hasChanges)
        }

        try working.write { db in
            var changed = try #require(try Event.find(eventID).fetchOne(db))
            changed.name = "Wicked Woods Updated"
            let saved = changed
            try Event.upsert { saved }.execute(db)
        }
        try working.read { db in
            let hasChanges = try CanonicalWorkspaceRecordChanges.hasChanges(
                workspace: workspace, in: db, referenceDatabase: reference
            )
            #expect(hasChanges)
        }

        let otherID = try #require(Event.ID(
            "at://did:plc:other/events.openmusic.event/3mrdbziccpcai"
        ))
        let other = try Event(
            id: otherID,
            name: "Another Event",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        try working.write { db in
            try Event.upsert { event }.execute(db)
            try Event.insert { other }.execute(db)
        }
        try working.read { db in
            let hasChanges = try CanonicalWorkspaceRecordChanges.hasChanges(
                workspace: workspace, in: db, referenceDatabase: reference
            )
            #expect(!hasChanges)
        }

        let placeID = try #require(EventPlace.ID(
            "at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcak"
        ))
        let place = try EventPlace(
            id: placeID,
            event: eventID,
            name: "Main Stage",
            createdAt: "2026-09-01T12:00:00Z"
        )
        try working.write { db in try EventPlace.insert { place }.execute(db) }
        try working.read { db in
            let hasChanges = try CanonicalWorkspaceRecordChanges.hasChanges(
                workspace: workspace, in: db, referenceDatabase: reference
            )
            #expect(hasChanges)
        }

        let stageID = try #require(Stage.ID(
            "at://did:plc:organizer/events.openmusic.stage/3mrdbziccpcam"
        ))
        let stage = try Stage(
            id: stageID,
            name: "Persistent Main Stage",
            createdAt: "2026-09-01T12:00:00Z"
        )
        try baseline.write { db in try EventPlace.insert { place }.execute(db) }
        try working.write { db in try Stage.insert { stage }.execute(db) }
        try working.read { db in
            let hasChanges = try CanonicalWorkspaceRecordChanges.hasChanges(
                workspace: workspace, in: db, referenceDatabase: reference
            )
            #expect(hasChanges)
        }
    }
}
