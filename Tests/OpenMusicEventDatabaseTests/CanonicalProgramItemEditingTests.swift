import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite
struct CanonicalProgramItemEditingTests {
    @Test
    func announcementCanBeScheduledEditedAndRemovedWithoutChangingItsRecordIdentity() throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let programID = try #require(Program.ID(
            "at://did:plc:organizer/events.openmusic.program/3mrdbziccpcal"
        ))
        let otherProgramID = try #require(Program.ID(
            "at://did:plc:organizer/events.openmusic.program/3mrdbziccpcan"
        ))
        let scheduleID = try #require(Schedule.ID(
            "at://did:plc:organizer/events.openmusic.schedule/3mrdbziccpcae"
        ))
        let placeID = try #require(EventPlace.ID(
            "at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcae"
        ))
        let timestamp = ATProto.DateTime(rawValue: "2026-09-01T12:00:00Z")
        let event = try Event(
            id: eventID,
            name: "Wicked Woods",
            createdAt: timestamp,
            timeZone: #require(TimeZone(identifier: "America/Denver")),
            programs: [programID],
            schedules: [scheduleID]
        )
        let program = try Program(
            id: programID,
            event: eventID,
            title: "Music",
            createdAt: timestamp,
            eventPlaces: [placeID]
        )
        let otherProgram = try Program(
            id: otherProgramID,
            event: eventID,
            title: "Undeclared",
            createdAt: timestamp,
            eventPlaces: []
        )
        let schedule = try Schedule(
            id: scheduleID,
            event: eventID,
            date: #require(LocalDate("2026-09-05")),
            createdAt: timestamp
        )
        let place = try EventPlace(
            id: placeID,
            event: eventID,
            name: "Main Stage",
            createdAt: timestamp
        )
        try database.write { db in
            try Event.insert { event }.execute(db)
            try Program.insert { program }.execute(db)
            try Program.insert { otherProgram }.execute(db)
            try Schedule.insert { schedule }.execute(db)
            try EventPlace.insert { place }.execute(db)
        }

        let createdAt = try Date("2026-09-02T18:00:00Z", strategy: .iso8601)
        let itemID = try database.write { db in
            try ProgramItemRecordEditing.create(
                eventID: eventID,
                fields: .init(program: programID, title: "Main stage set"),
                createdAt: createdAt,
                in: db
            )
        }
        let announcement = try database.read {
            try #require(try ProgramItem.find(itemID).fetchOne($0))
        }
        #expect(announcement.event == eventID)
        #expect(announcement.schedule == nil)
        #expect(announcement.startsAt == nil)

        let start = ATProto.DateTime(rawValue: "2026-09-05T20:00:00Z")
        let end = ATProto.DateTime(rawValue: "2026-09-05T21:00:00Z")
        try database.write { db in
            try ProgramItemRecordEditing.update(
                itemID,
                eventID: eventID,
                fields: .init(
                    program: programID,
                    title: "Opening set",
                    description: "At the main stage",
                    schedule: scheduleID,
                    eventPlace: placeID,
                    startsAt: start,
                    endsAt: end
                ),
                in: db
            )
        }
        let scheduled = try database.read {
            try #require(try ProgramItem.find(itemID).fetchOne($0))
        }
        #expect(scheduled.id == announcement.id)
        #expect(scheduled.createdAt == announcement.createdAt)
        #expect(scheduled.title == "Opening set")
        #expect(scheduled.schedule == scheduleID)
        #expect(scheduled.eventPlace == placeID)
        #expect(scheduled.startsAt == start)
        #expect(scheduled.endsAt == end)

        #expect(throws: ValidationError.self) {
            try database.write { db in
                try ProgramItemRecordEditing.update(
                    itemID,
                    eventID: eventID,
                    fields: .init(program: otherProgramID, title: "Wrong program"),
                    in: db
                )
            }
        }
        #expect(try database.read { try ProgramItem.find(itemID).fetchOne($0) } == scheduled)

        try database.write {
            try ProgramItemRecordEditing.delete(itemID, eventID: eventID, in: $0)
        }
        #expect(try database.read { try ProgramItem.find(itemID).fetchOne($0) } == nil)
        #expect(try database.read { try Schedule.find(scheduleID).fetchOne($0) } == schedule)
        #expect(try database.read { try Program.find(programID).fetchOne($0) } == program)
    }
}
