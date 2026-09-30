import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventLexicon
import SQLiteData

public struct EventRecordGraph: Equatable, Sendable {
    public var event: Event
    public var programs: [Program]
    public var schedules: [Schedule]
    public var places: [EventPlace]
    public var contributors: [Contributor]
    public var items: [ProgramItem]
    public var categories: [Social.Category]

    public init(
        event: Event,
        programs: [Program] = [],
        schedules: [Schedule] = [],
        places: [EventPlace] = [],
        contributors: [Contributor] = [],
        items: [ProgramItem] = [],
        categories: [Social.Category] = []
    ) {
        self.event = event
        self.programs = programs
        self.schedules = schedules
        self.places = places
        self.contributors = contributors
        self.items = items
        self.categories = categories
    }

    public func validate() throws {
        try event.validateReferences()
        guard Set(programs.map(\.id)) == Set(event.programs ?? []),
              Set(schedules.map(\.id)) == Set(event.schedules ?? []),
              Set(categories.map(\.id)) == Set(event.categories ?? [])
        else {
            throw ValidationError("The installed records must include the event's declared programs, schedules and categories")
        }
        for program in programs {
            try program.validateReferences()
            guard program.event == event.id else {
                throw ValidationError("A program belongs to another event")
            }
            guard Set(program.eventPlaces).isSubset(of: Set(places.map(\.id))) else {
                throw ValidationError("A program refers to an unavailable event place")
            }
        }
        for schedule in schedules {
            try schedule.validateReferences()
            guard schedule.event == event.id else {
                throw ValidationError("A schedule belongs to another event")
            }
        }
        for place in places {
            try place.validateReferences()
            guard place.event == event.id else {
                throw ValidationError("A place belongs to another event")
            }
        }
        for contributor in contributors {
            try contributor.validateReferences()
            guard contributor.event == event.id else {
                throw ValidationError("A contributor belongs to another event")
            }
        }
        for category in categories {
            try category.validateGraph(event: event)
        }
        for item in items {
            guard let program = programs.first(where: { $0.id == item.program }) else {
                throw ValidationError("A program item refers to an unavailable program")
            }
            try item.validateGraph(
                event: event,
                program: program,
                schedule: schedules.first { $0.id == item.schedule },
                eventPlace: places.first { $0.id == item.eventPlace }
            )
        }
    }

    public static func fetch(eventID: Event.ID, from db: Database) throws -> Self? {
        guard let event = try Event.find(eventID).fetchOne(db) else { return nil }
        return Self(
            event: event,
            programs: try Program.where { $0.event.eq(eventID) }.fetchAll(db),
            schedules: try Schedule.where { $0.event.eq(eventID) }.fetchAll(db),
            places: try EventPlace.where { $0.event.eq(eventID) }.fetchAll(db),
            contributors: try Contributor.where { $0.event.eq(eventID) }.fetchAll(db),
            items: try ProgramItem.where { $0.event.eq(eventID) }.fetchAll(db),
            categories: try Social.Category.where { $0.event.eq(eventID) }.fetchAll(db)
        )
    }

    public func upsert(in db: Database) throws {
        try validate()
        try Event.upsert { event }.execute(db)
        for record in programs { try Program.upsert { record }.execute(db) }
        for record in schedules { try Schedule.upsert { record }.execute(db) }
        for record in places { try EventPlace.upsert { record }.execute(db) }
        for record in contributors { try Contributor.upsert { record }.execute(db) }
        for record in items { try ProgramItem.upsert { record }.execute(db) }
        for record in categories { try Social.Category.upsert { record }.execute(db) }
    }
}
