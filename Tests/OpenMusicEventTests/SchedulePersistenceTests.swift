import ATProto
import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import OpenMusicEvent
@testable import OpenMusicEventLexicon

struct SchedulePersistenceTests {
    @Test
    func roundTripsScheduleDateAndOptionalBounds() async throws {
        let database = try makePreparedDatabase()
        let organizerID = OMERecord.Organizer.ID("did:web:example.com")!
        let eventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: eventLocalID("event-1")
        )
        let scheduleID = OMERecord.Schedule.ID(
            organizerID: organizerID,
            eventID: eventLocalID("event-1"),
            scheduleID: scheduleLocalID("schedule-1")
        )
        let eventStartDate = try #require(LocalDate("2025-08-29"))
        let eventEndDate = try #require(LocalDate("2025-08-31"))
        let scheduleDate = try #require(LocalDate("2025-08-29"))
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let startsAt = scheduleDate.atStartOfDay(in: timeZone)
        let endsAt = try #require(scheduleDate.at(hour: 23, minute: 59, in: timeZone))

        try await database.write { db in
            try OMERecord.Organizer.insert {
                OMERecord.Organizer.Draft(id: organizerID)
            }
            .execute(db)

            try OMERecord.Event.insert {
                OMERecord.Event.Draft(
                    id: eventID,
                    name: "Test Event",
                    description: nil,
                    startDate: eventStartDate,
                    endDate: eventEndDate,
                    status: .known(.planned),
                    mode: .known(.inPerson),
                    locations: nil,
                    uris: nil,
                    timeZone: timeZone,
                    imageURL: nil,
                    iconImageURL: nil,
                    siteMapImageURL: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)

            try OMERecord.Schedule.insert {
                OMERecord.Schedule.Draft(
                    id: scheduleID,
                    date: scheduleDate,
                    startsAt: startsAt,
                    endsAt: endsAt,
                    customTitle: "Friday"
                )
            }
            .execute(db)
        }

        let schedules = try await database.read { db in
            try OMERecord.Schedule.fetchAll(db)
        }
        let events = try await database.read { db in
            try OMERecord.Event.fetchAll(db)
        }

        let schedule = try #require(schedules.first)
        let event = try #require(events.first)
        #expect(event.id == eventID)
        #expect(event.startDate == eventStartDate)
        #expect(event.endDate == eventEndDate)
        #expect(event.timeZone.identifier == timeZone.identifier)
        #expect(schedule.id == scheduleID)
        #expect(schedule.date == scheduleDate)
        #expect(schedule.startsAt == startsAt)
        #expect(schedule.endsAt == endsAt)
        #expect(schedule.customTitle == "Friday")
    }

    private func makePreparedDatabase() throws -> any DatabaseWriter {
        try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            @Dependency(\.defaultDatabase) var database
            return database
        }
    }
}

private func eventLocalID(_ string: String) -> OMERecord.ID<OMERecord.Event> {
    OMERecord.ID<OMERecord.Event>(rawValue: ATProto.Record.Key(rawValue: string))
}

private func scheduleLocalID(_ string: String) -> OMERecord.ID<OMERecord.Schedule> {
    OMERecord.ID<OMERecord.Schedule>(rawValue: ATProto.Record.Key(rawValue: string))
}
