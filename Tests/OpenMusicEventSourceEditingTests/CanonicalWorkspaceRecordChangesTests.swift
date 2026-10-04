import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
@testable import OpenMusicEventSourceEditing
import SQLiteData
import Testing

@Suite("Canonical workspace record changes")
struct CanonicalWorkspaceRecordChangesTests {
    @Test
    func eventRelationshipChangesResetWithoutTouchingSiblingEvent() throws {
        let working = try DatabaseQueue()
        let baseline = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(working)
        try migrator.migrate(baseline)
        let reference = SourceBaselineDatabase(path: "baseline", database: baseline)
        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let siblingID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcai"
        ))
        let events = try [eventID, siblingID].map {
            try Event(id: $0, name: "Wicked Woods", createdAt: "2026-09-01T12:00:00Z", timeZone: .gmt)
        }
        try working.write { db in try Event.insert { events }.execute(db) }
        try baseline.write { db in try Event.insert { events }.execute(db) }
        let collaborator = try #require(DID("did:plc:collaborator"))
        let fields = RelationshipRecordEditing.Fields(
            subject: .known(.identity(did: collaborator)),
            role: .collaborator,
            capabilities: [.propose]
        )
        let createdAt = try Date("2026-09-02T18:00:00Z", strategy: .iso8601)

        // The sibling event receives a collaborator, but this workspace has no changes.
        let siblingRelationshipID = try working.write {
            try RelationshipRecordEditing.create(eventID: siblingID, fields: fields, createdAt: createdAt, in: $0)
        }
        try working.read { db in
            let changes = try CanonicalWorkspaceRecordChanges.changes(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(changes.isEmpty)
        }

        // Adding a collaborator to this event produces one URI-addressed change.
        let relationshipID = try working.write {
            try RelationshipRecordEditing.create(eventID: eventID, fields: fields, createdAt: createdAt, in: $0)
        }
        try working.read { db in
            let changes = try CanonicalWorkspaceRecordChanges.changes(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(changes.count == 1)
            #expect(changes.first?.id == relationshipID)
            #expect(changes.first?.collection == OME.Relationship.tableName)
            #expect(changes.first?.kind == .added)
        }

        try CanonicalWorkspaceRecordChanges.reset(
            eventID: eventID,
            in: working,
            referenceDatabase: reference
        )
        try working.read { db in
            let relationships = try OME.Relationship.all.fetchAll(db)
            let changes = try CanonicalWorkspaceRecordChanges.changes(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(relationships.map(\.id) == [siblingRelationshipID])
            #expect(changes.isEmpty)
        }
    }

    @Test
    func detectsOrganizerChangesWithoutCountingOtherRepositories() throws {
        let working = try DatabaseQueue()
        let baseline = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(working)
        try migrator.migrate(baseline)
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
                eventID: eventID, in: db, referenceDatabase: reference
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
            let changes = try CanonicalWorkspaceRecordChanges.changes(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(changes.count == 1)
            #expect(changes.first?.collection == Event.tableName)
            #expect(changes.first?.id == eventID)
            #expect(changes.first?.kind == .edited)
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
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(!hasChanges)
        }

        let siblingID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcaj"
        ))
        let sibling = try Event(
            id: siblingID,
            name: "Another organizer event",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        try working.write { db in try Event.insert { sibling }.execute(db) }
        try working.read { db in
            let changes = try CanonicalWorkspaceRecordChanges.changes(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(changes.count == 1)
            #expect(changes.first?.id == siblingID)
            #expect(changes.first?.kind == .added)
        }
        try baseline.write { db in try Event.insert { sibling }.execute(db) }

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
                eventID: eventID, in: db, referenceDatabase: reference
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
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(hasChanges)
        }

        // Deleting one record and adding another produces two local changes without
        // including the unrelated repository's event.
        try working.write { db in try EventPlace.find(placeID).delete().execute(db) }
        try working.read { db in
            let changes = try CanonicalWorkspaceRecordChanges.changes(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(changes.count == 2)
            #expect(changes.contains { $0.id == placeID && $0.kind == .deleted })
            #expect(changes.contains { $0.id == stageID && $0.kind == .added })
        }

        try CanonicalWorkspaceRecordChanges.reset(
            eventID: eventID,
            in: working,
            referenceDatabase: reference
        )
        try working.read { db in
            let restoredEvent = try Event.find(eventID).fetchOne(db)
            let siblingEvent = try Event.find(siblingID).fetchOne(db)
            let restoredPlace = try EventPlace.find(placeID).fetchOne(db)
            let removedStage = try Stage.find(stageID).fetchOne(db)
            let otherEvent = try Event.find(otherID).fetchOne(db)
            let remainingChanges = try CanonicalWorkspaceRecordChanges.changes(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(restoredEvent?.name == "Wicked Woods")
            #expect(siblingEvent?.name == "Another organizer event")
            #expect(restoredPlace?.name == "Main Stage")
            #expect(removedStage == nil)
            #expect(otherEvent?.name == "Another Event")
            #expect(remainingChanges.isEmpty)
        }
    }
}
