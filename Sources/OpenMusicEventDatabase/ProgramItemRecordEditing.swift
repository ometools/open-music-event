import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventLexicon
import SQLiteData

public enum ProgramItemRecordEditing {
    public enum Error: Swift.Error, Equatable {
        case eventUnavailable
        case programUnavailable
        case itemUnavailable
    }

    public struct Fields: Equatable {
        public var program: Program.ID
        public var title: String
        public var description: String?
        public var schedule: Schedule.ID?
        public var eventPlace: EventPlace.ID?
        public var startsAt: ATProto.DateTime?
        public var endsAt: ATProto.DateTime?
        public var credits: [ProgramItem.Credit]?
        public var media: [Open<OME.Media>]?

        public init(
            program: Program.ID,
            title: String,
            description: String? = nil,
            schedule: Schedule.ID? = nil,
            eventPlace: EventPlace.ID? = nil,
            startsAt: ATProto.DateTime? = nil,
            endsAt: ATProto.DateTime? = nil,
            credits: [ProgramItem.Credit]? = nil,
            media: [Open<OME.Media>]? = nil
        ) {
            self.program = program
            self.title = title
            self.description = description
            self.schedule = schedule
            self.eventPlace = eventPlace
            self.startsAt = startsAt
            self.endsAt = endsAt
            self.credits = credits
            self.media = media
        }

        public init(_ item: ProgramItem) {
            self.init(
                program: item.program,
                title: item.title,
                description: item.description,
                schedule: item.schedule,
                eventPlace: item.eventPlace,
                startsAt: item.startsAt,
                endsAt: item.endsAt,
                credits: item.credits,
                media: item.media
            )
        }

        fileprivate func apply(to item: inout ProgramItem) {
            item.program = program
            item.title = title
            item.description = description
            item.schedule = schedule
            item.eventPlace = eventPlace
            item.startsAt = startsAt
            item.endsAt = endsAt
            item.credits = credits
            item.media = media
        }
    }

    public static func create(
        eventID: Event.ID,
        fields: Fields,
        createdAt: Date,
        in db: Database
    ) throws -> ProgramItem.ID {
        guard try Event.find(eventID).fetchOne(db) != nil else {
            throw Error.eventUnavailable
        }
        let existing = try ProgramItem.all.fetchAll(db)
            .filter { $0.id.authority == eventID.authority }
        let previousKey = existing.map(\.id).compactMap(\.rkey)
            .max { $0.rawValue < $1.rawValue }
        let id = try CanonicalRecordID.next(
            collection: ProgramItem.lexiconID,
            in: eventID.authority,
            at: createdAt,
            after: previousKey
        )
        var item = try ProgramItem(
            id: id,
            event: eventID,
            program: fields.program,
            title: fields.title,
            createdAt: ATProto.DateTime(rawValue: ISO8601DateFormatter().string(from: createdAt))
        )
        fields.apply(to: &item)
        try validateGraph(item, in: db)
        try ProgramItem.insert { item }.execute(db)
        return id
    }

    public static func update(
        _ itemID: ProgramItem.ID,
        eventID: Event.ID,
        fields: Fields,
        in db: Database
    ) throws {
        guard var item = try ProgramItem.find(itemID).fetchOne(db),
              item.event == eventID else {
            throw Error.itemUnavailable
        }
        fields.apply(to: &item)
        try validateGraph(item, in: db)
        try ProgramItem.upsert { item }.execute(db)
    }

    public static func delete(
        _ itemID: ProgramItem.ID,
        eventID: Event.ID,
        in db: Database
    ) throws {
        guard let item = try ProgramItem.find(itemID).fetchOne(db),
              item.event == eventID else {
            throw Error.itemUnavailable
        }
        try ProgramItem.find(item.id).delete().execute(db)
    }

    private static func validateGraph(_ item: ProgramItem, in db: Database) throws {
        guard let event = try Event.find(item.event).fetchOne(db) else {
            throw Error.eventUnavailable
        }
        guard let program = try Program.find(item.program).fetchOne(db) else {
            throw Error.programUnavailable
        }
        let schedule = try item.schedule.flatMap { try Schedule.find($0).fetchOne(db) }
        let place = try item.eventPlace.flatMap { try EventPlace.find($0).fetchOne(db) }
        try item.validateGraph(
            event: event,
            program: program,
            schedule: schedule,
            eventPlace: place
        )
    }
}
