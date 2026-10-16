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
    public var posts: [Social.Post]

    public init(
        event: Event,
        programs: [Program] = [],
        schedules: [Schedule] = [],
        places: [EventPlace] = [],
        contributors: [Contributor] = [],
        items: [ProgramItem] = [],
        categories: [Social.Category] = [],
        posts: [Social.Post] = []
    ) {
        self.event = event
        self.programs = programs
        self.schedules = schedules
        self.places = places
        self.contributors = contributors
        self.items = items
        self.categories = categories
        self.posts = posts
    }

    public func validate() throws {
        // Validate each payload once. A performance must not revalidate its entire parent graph.
        try event.validateReferences()
        for record in programs { try record.validateReferences() }
        for record in schedules { try record.validateReferences() }
        for record in places { try record.validateReferences() }
        for record in contributors { try record.validateReferences() }
        for record in categories { try record.validateReferences() }
        for record in items { try record.validateReferences() }
        for record in posts { try record.validateReferences() }
        try validateRelationships()
    }

    /// Checks a graph whose individual records were validated at ingestion or decoding.
    public func validateRelationships() throws {
        guard Set(programs.map(\.id)) == Set(event.programs ?? []),
              Set(schedules.map(\.id)) == Set(event.schedules ?? []),
              Set(categories.map(\.id)) == Set(event.categories ?? []),
              Set(programs.map(\.id)).count == programs.count,
              Set(schedules.map(\.id)).count == schedules.count,
              Set(places.map(\.id)).count == places.count,
              Set(contributors.map(\.id)).count == contributors.count,
              Set(items.map(\.id)).count == items.count,
              Set(categories.map(\.id)).count == categories.count,
              Set(posts.map(\.id)).count == posts.count
        else { throw ValidationError("The event graph has missing or duplicate records") }
        let programsByID = Dictionary(uniqueKeysWithValues: programs.map { ($0.id, $0) })
        let scheduleIDs = Set(schedules.map(\.id))
        let placeIDs = Set(places.map(\.id))
        let categoryIDs = Set(categories.map(\.id))
        guard programs.allSatisfy({ $0.event == event.id && Set($0.eventPlaces).isSubset(of: placeIDs) }),
              schedules.allSatisfy({ $0.event == event.id }),
              places.allSatisfy({ $0.event == event.id }),
              contributors.allSatisfy({ $0.event == event.id }),
              categories.allSatisfy({ $0.event == event.id }),
              posts.allSatisfy({ $0.event == event.id && $0.id.authority == event.id.authority
                && ($0.category.map { categoryIDs.contains($0) } ?? true) })
        else { throw ValidationError("A record belongs to another event or refers to unavailable content") }
        for item in items {
            guard item.event == event.id, let program = programsByID[item.program],
                  item.schedule.map({ scheduleIDs.contains($0) }) ?? true,
                  item.eventPlace.map({ placeIDs.contains($0) && program.eventPlaces.contains($0) }) ?? true
            else { throw ValidationError("A program item refers to unavailable event content") }
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
            categories: try Social.Category.where { $0.event.eq(eventID) }.fetchAll(db),
            posts: try Social.Post.where { $0.event.eq(eventID) }.fetchAll(db)
                .filter { $0.id.authority == eventID.authority }
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
        for record in posts { try Social.Post.upsert { record }.execute(db) }
    }
}
