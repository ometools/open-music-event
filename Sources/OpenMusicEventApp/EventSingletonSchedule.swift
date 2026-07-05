import OpenMusicEventLexicon
import SQLiteData

enum EventSingletonSchedule {
    static func draft(
        eventID: OMERecord.Event.ID,
        date: LocalDate
    ) -> OMERecord.Schedule.Draft {
        OMERecord.Schedule.Draft(
            id: OMERecord.Schedule.ID(
                organizerID: eventID.organizerID,
                eventID: eventID.eventID,
                scheduleID: OMERecord.Schedule.singletonID
            ),
            date: date,
            startsAt: nil,
            endsAt: nil,
            customTitle: nil
        )
    }

    static func insert(
        eventID: OMERecord.Event.ID,
        date: LocalDate,
        in db: Database
    ) throws {
        try OMERecord.Schedule.insert {
            draft(eventID: eventID, date: date)
        }
        .execute(db)
    }
}
