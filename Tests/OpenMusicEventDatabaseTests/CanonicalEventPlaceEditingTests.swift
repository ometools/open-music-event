import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite
struct CanonicalEventPlaceEditingTests {
    typealias Event = OpenMusicEventLexicon.Event

    @Test
    func stagePlaceEditsKeepIdentityAndDeletionRespectsProgramItems() throws {
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

        let color = try #require(OME.Color(rawValue: 0x336699))
        let placeID = try database.write { db in
            try EventPlaceRecordEditing.create(
                eventID: eventID,
                fields: .init(
                    name: "The Hollow",
                    kind: .known(.stage(.init(
                        color: color,
                        category: "main",
                        sortIndex: 1,
                        icon: .init(rawValue: "sparkles"),
                        shortLabel: "H"
                    )))
                ),
                createdAt: try Date("2026-09-02T18:00:00Z", strategy: .iso8601),
                in: db
            )
        }
        let original = try database.read {
            try #require(try EventPlace.find(placeID).fetchOne($0))
        }
        #expect(placeID.authority == eventID.authority)

        try database.write { db in
            try EventPlaceRecordEditing.update(
                placeID,
                eventID: eventID,
                fields: .init(
                    name: "The Hollow Stage",
                    description: "Follow the forest path",
                    kind: .known(.stage(.init(
                        color: color,
                        category: "workshop",
                        sortIndex: 7,
                        icon: .init(rawValue: "sparkles"),
                        shortLabel: "HS"
                    )))
                ),
                in: db
            )
        }
        let updated = try database.read {
            try #require(try EventPlace.find(placeID).fetchOne($0))
        }
        #expect(updated.id == original.id)
        #expect(updated.createdAt == original.createdAt)
        #expect(updated.name == "The Hollow Stage")
        #expect(updated.description == "Follow the forest path")
        #expect(updated.kind == .known(.stage(.init(
            color: color,
            category: "workshop",
            sortIndex: 7,
            icon: .init(rawValue: "sparkles"),
            shortLabel: "HS"
        ))))

        let programID = try database.write { db in
            try ProgramRecordEditing.create(
                eventID: eventID,
                title: "Music",
                eventPlaces: [placeID],
                createdAt: try Date("2026-09-02T19:00:00Z", strategy: .iso8601),
                in: db
            )
        }
        let itemID = try #require(ProgramItem.ID(
            "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcam"
        ))
        let item = try ProgramItem(
            id: itemID,
            event: eventID,
            program: programID,
            title: "Opening Set",
            createdAt: "2026-09-02T19:00:00Z",
            eventPlace: placeID
        )
        try database.write { try ProgramItem.insert { item }.execute($0) }

        do {
            try database.write {
                try EventPlaceRecordEditing.delete(placeID, eventID: eventID, in: $0)
            }
            Issue.record("A scheduled item must keep its place available")
        } catch let error as EventPlaceRecordEditing.Error {
            #expect(error == .placeInUse)
        }

        try database.write { db in
            try ProgramItem.find(itemID).delete().execute(db)
            try EventPlaceRecordEditing.delete(placeID, eventID: eventID, in: db)
        }
        #expect(try database.read { try EventPlace.find(placeID).fetchOne($0) } == nil)
        let program = try database.read {
            try #require(try Program.find(programID).fetchOne($0))
        }
        #expect(program.eventPlaces == [])
    }
}
