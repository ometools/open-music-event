import Foundation
import ATProtoTypes
import OpenMusicEventLexicon
import SQLiteData

public enum ScheduleRecordEditing {
    public enum Error: Swift.Error, Equatable {
        case eventUnavailable
        case scheduleUnavailable
        case scheduleInUse
    }

    public static func create(
        eventID: Event.ID,
        date: LocalDate,
        title: String?,
        createdAt: Date,
        in db: Database
    ) throws -> Schedule.ID {
        guard var event = try Event.find(eventID).fetchOne(db) else {
            throw Error.eventUnavailable
        }
        let existing = try Schedule.all.fetchAll(db)
            .filter { $0.id.authority == eventID.authority }
        let previousKey = (existing.map(\.id) + (event.schedules ?? []))
            .compactMap(\.rkey)
            .max { $0.rawValue < $1.rawValue }
        let id = try CanonicalRecordID.next(
            collection: Schedule.lexiconID,
            in: eventID.authority,
            at: createdAt,
            after: previousKey
        )
        let timestamp = ISO8601DateFormatter().string(from: createdAt)
        let schedule = try Schedule(
            id: id,
            event: eventID,
            date: date,
            createdAt: ATProto.DateTime(rawValue: timestamp),
            title: title
        )
        try schedule.validateReferences()
        try Schedule.insert { schedule }.execute(db)
        event.schedules = (event.schedules ?? []) + [id]
        try event.validateReferences()
        try Event.upsert { event }.execute(db)
        return id
    }

    public static func update(
        _ scheduleID: Schedule.ID,
        eventID: Event.ID,
        date: LocalDate,
        title: String?,
        in db: Database
    ) throws {
        guard try Event.find(eventID).fetchOne(db) != nil else {
            throw Error.eventUnavailable
        }
        guard var schedule = try Schedule.find(scheduleID).fetchOne(db),
              schedule.event == eventID else {
            throw Error.scheduleUnavailable
        }
        schedule.date = date
        schedule.title = title
        try schedule.validateReferences()
        try Schedule.upsert { schedule }.execute(db)
    }

    public static func delete(
        _ scheduleID: Schedule.ID,
        eventID: Event.ID,
        in db: Database
    ) throws {
        guard var event = try Event.find(eventID).fetchOne(db),
              let schedule = try Schedule.find(scheduleID).fetchOne(db),
              schedule.event == eventID else {
            throw Error.scheduleUnavailable
        }
        let assignedItems = try ProgramItem.where { $0.event.eq(eventID) }.fetchAll(db)
        guard !assignedItems.contains(where: { $0.schedule == scheduleID }) else {
            throw Error.scheduleInUse
        }
        try Schedule.find(scheduleID).delete().execute(db)
        let remainingSchedules = event.schedules?.filter { $0 != scheduleID }
        event.schedules = remainingSchedules?.isEmpty == true ? nil : remainingSchedules
        try event.validateReferences()
        try Event.upsert { event }.execute(db)
    }
}
