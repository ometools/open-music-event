import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite
struct CanonicalProgramEditingTests {
    typealias Event = OpenMusicEventLexicon.Event

    @Test
    func programPlaceAndItemReferencesStayValidThroughEditing() throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let placeID = try #require(EventPlace.ID(
            "at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcak"
        ))
        let otherEventID = try #require(Event.ID(
            "at://did:plc:other/events.openmusic.event/3mrdbziccpcah"
        ))
        let otherPlaceID = try #require(EventPlace.ID(
            "at://did:plc:other/events.openmusic.eventPlace/3mrdbziccpcak"
        ))
        let event = try Event(
            id: eventID,
            name: "Wicked Woods",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: #require(TimeZone(identifier: "America/Denver"))
        )
        let place = try EventPlace(
            id: placeID,
            event: eventID,
            name: "Main Stage",
            createdAt: "2026-09-01T12:00:00Z"
        )
        let otherEvent = try Event(
            id: otherEventID,
            name: "Other Event",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: #require(TimeZone(identifier: "America/Denver"))
        )
        let otherPlace = try EventPlace(
            id: otherPlaceID,
            event: otherEventID,
            name: "Other Stage",
            createdAt: "2026-09-01T12:00:00Z"
        )
        try database.write { db in
            try Event.insert { [event, otherEvent] }.execute(db)
            try EventPlace.insert { [place, otherPlace] }.execute(db)
        }

        let createdAt = try Date("2026-09-02T18:00:00Z", strategy: .iso8601)
        let programID = try database.write { db in
            try ProgramRecordEditing.create(
                eventID: eventID,
                title: "Music",
                eventPlaces: [placeID],
                createdAt: createdAt,
                in: db
            )
        }
        #expect(try database.read { try Event.find(eventID).fetchOne($0)?.programs } == [programID])
        let original = try database.read { try #require(try Program.find(programID).fetchOne($0)) }

        try database.write { db in
            try ProgramRecordEditing.update(
                programID,
                eventID: eventID,
                title: "Main Music",
                eventPlaces: [placeID],
                in: db
            )
        }
        let updated = try database.read { try #require(try Program.find(programID).fetchOne($0)) }
        #expect(updated.id == original.id)
        #expect(updated.createdAt == original.createdAt)
        #expect(updated.title == "Main Music")

        do {
            try database.write { db in
                try ProgramRecordEditing.update(
                    programID,
                    eventID: eventID,
                    title: "Wrong Place",
                    eventPlaces: [otherPlaceID],
                    in: db
                )
            }
            Issue.record("A program must not use another event's place")
        } catch let error as ProgramRecordEditing.Error {
            #expect(error == .placeUnavailable)
        }

        let item = try ProgramItem(
            id: #require(ProgramItem.ID(
                "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcam"
            )),
            event: eventID,
            program: programID,
            title: "Main stage set",
            createdAt: "2026-09-02T18:00:00Z",
            eventPlace: placeID
        )
        try database.write { try ProgramItem.insert { item }.execute($0) }
        do {
            try database.write { db in
                try ProgramRecordEditing.update(
                    programID,
                    eventID: eventID,
                    title: "No Stage",
                    eventPlaces: [],
                    in: db
                )
            }
            Issue.record("Removing a place used by a program item should fail")
        } catch let error as ProgramRecordEditing.Error {
            #expect(error == .placeInUse)
        }
        do {
            try database.write { try ProgramRecordEditing.delete(programID, eventID: eventID, in: $0) }
            Issue.record("Deleting a program with an item should fail")
        } catch let error as ProgramRecordEditing.Error {
            #expect(error == .programInUse)
        }
        #expect(try database.read { try Program.find(programID).fetchOne($0) } == updated)

        try database.write { db in
            try ProgramItem.find(item.id).delete().execute(db)
            try ProgramRecordEditing.delete(programID, eventID: eventID, in: db)
        }
        #expect(try database.read { try Program.find(programID).fetchOne($0) } == nil)
        #expect(try database.read { try Event.find(eventID).fetchOne($0)?.programs } == nil)
    }
}
