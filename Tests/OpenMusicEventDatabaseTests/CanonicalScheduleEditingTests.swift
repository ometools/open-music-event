import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite
struct CanonicalScheduleEditingTests {
    typealias Event = OpenMusicEventLexicon.Event

    @Test
    func scheduleEditingAndDeletionKeepTheCanonicalEventGraphConsistent() throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let programID = try #require(ATProto.URI(
            "at://did:plc:organizer/events.openmusic.program/3mrdbziccpcal"
        ))
        var event = try Event(
            id: eventID,
            name: "Wicked Woods",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: #require(TimeZone(identifier: "America/Denver"))
        )
        event.programs = [programID]
        let program = try Program(
            id: programID,
            event: eventID,
            title: "Music",
            createdAt: "2026-09-01T12:00:00Z",
            eventPlaces: []
        )
        try database.write { db in
            try Event.insert { event }.execute(db)
            try Program.insert { program }.execute(db)
        }

        let createdAt = try Date("2026-09-02T18:00:00Z", strategy: .iso8601)
        let saturday = try #require(LocalDate("2026-09-05"))
        let sunday = try #require(LocalDate("2026-09-06"))
        let scheduleID = try database.write { db in
            try ScheduleRecordEditing.create(
                eventID: eventID,
                date: saturday,
                title: "Saturday",
                createdAt: createdAt,
                in: db
            )
        }
        let original = try database.read { try #require(try Schedule.find(scheduleID).fetchOne($0)) }
        #expect(original.event == eventID)
        #expect(try database.read { try Event.find(eventID).fetchOne($0)?.schedules } == [scheduleID])

        try database.write { db in
            try ScheduleRecordEditing.update(
                scheduleID,
                eventID: eventID,
                date: sunday,
                title: "Sunday Music",
                in: db
            )
        }
        let edited = try database.read { try #require(try Schedule.find(scheduleID).fetchOne($0)) }
        #expect(edited.id == original.id)
        #expect(edited.createdAt == original.createdAt)
        #expect(edited.date == sunday)
        #expect(edited.title == "Sunday Music")

        let item = try ProgramItem(
            id: #require(ATProto.URI(
                "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcak"
            )),
            event: eventID,
            program: programID,
            title: "Main stage set",
            createdAt: "2026-09-01T12:00:00Z",
            schedule: scheduleID
        )
        try database.write { try ProgramItem.insert { item }.execute($0) }
        do {
            try database.write { db in
                try ScheduleRecordEditing.delete(scheduleID, eventID: eventID, in: db)
            }
            Issue.record("Deleting a schedule with an assigned item should fail")
        } catch let error as ScheduleRecordEditing.Error {
            #expect(error == .scheduleInUse)
        }
        #expect(try database.read { try Schedule.find(scheduleID).fetchOne($0) } == edited)

        try database.write { db in
            try ProgramItem.find(item.id).delete().execute(db)
            try ScheduleRecordEditing.delete(scheduleID, eventID: eventID, in: db)
        }
        #expect(try database.read { try Schedule.find(scheduleID).fetchOne($0) } == nil)
        let savedEvent = try database.read { try #require(try Event.find(eventID).fetchOne($0)) }
        #expect(savedEvent.schedules == nil)
        #expect(savedEvent.programs == [programID])
        #expect(try database.read { try Program.find(programID).fetchOne($0) } == program)
    }
}
