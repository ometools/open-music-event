import ATProto
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite
struct CanonicalPersistentStageEditingTests {
    @Test
    func profileEditsKeepIdentityAndLinkedPlacesPreventDeletion() throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let event = try Event(
            id: eventID,
            name: "Wicked Woods",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: #require(TimeZone(identifier: "America/Denver"))
        )
        try database.write { try Event.insert { event }.execute($0) }

        let stageID = try database.write { db in
            try PersistentStageRecordEditing.create(
                eventID: eventID,
                fields: .init(name: "The Hollow"),
                createdAt: try Date("2026-09-02T18:00:00Z", strategy: .iso8601),
                in: db
            )
        }
        let original = try database.read { db in
            try #require(try Stage.find(stageID).fetchOne(db))
        }
        #expect(stageID.authority == eventID.authority)

        try database.write { db in
            try PersistentStageRecordEditing.update(
                stageID,
                eventID: eventID,
                fields: .init(name: "The Hollow Stage", description: "Among the trees"),
                in: db
            )
        }
        let updated = try database.read { db in
            try #require(try Stage.find(stageID).fetchOne(db))
        }
        #expect(updated.id == original.id)
        #expect(updated.createdAt == original.createdAt)
        #expect(updated.name == "The Hollow Stage")
        #expect(updated.description == "Among the trees")

        let placeID = try database.write { db in
            try EventPlaceRecordEditing.create(
                eventID: eventID,
                fields: .init(
                    name: "The Hollow in 2026",
                    kind: .known(.stage(.init(stage: stageID)))
                ),
                createdAt: try Date("2026-09-02T19:00:00Z", strategy: .iso8601),
                in: db
            )
        }
        #expect(throws: PersistentStageRecordEditing.Error.stageInUse) {
            try database.write { db in
                try PersistentStageRecordEditing.delete(stageID, eventID: eventID, in: db)
            }
        }

        try database.write { db in
            try EventPlaceRecordEditing.delete(placeID, eventID: eventID, in: db)
            try PersistentStageRecordEditing.delete(stageID, eventID: eventID, in: db)
        }
        #expect(try database.read { try Stage.find(stageID).fetchOne($0) } == nil)
    }
}
