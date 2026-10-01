import ATProto
import ATProtoTypes
import CustomDump
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite
struct SchedulePersistenceTests {
    @Test
    func organizerScheduleDayRoundTripsWithItsEvent() throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let scheduleID = try #require(Schedule.ID(
            "at://did:plc:organizer/events.openmusic.schedule/3mrdbziccpcae"
        ))
        let createdAt = ATProto.DateTime(rawValue: "2026-09-01T12:00:00Z")
        let event = try Event(
            id: eventID,
            name: "Wicked Woods",
            createdAt: createdAt,
            timeZone: #require(TimeZone(identifier: "America/Denver")),
            schedules: [scheduleID]
        )
        let schedule = try Schedule(
            id: scheduleID,
            event: eventID,
            date: #require(LocalDate("2026-09-05")),
            createdAt: createdAt,
            title: "Saturday"
        )

        try database.write { db in
            try Event.insert { event }.execute(db)
            try Schedule.insert { schedule }.execute(db)
        }

        let savedEvent = try database.read {
            try #require(try Event.find(eventID).fetchOne($0))
        }
        let savedSchedule = try database.read {
            try #require(try Schedule.find(scheduleID).fetchOne($0))
        }
        expectNoDifference(savedEvent.schedules, [scheduleID])
        expectNoDifference(savedSchedule, schedule)
    }
}
