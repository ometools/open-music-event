import Foundation
import OpenMusicEventLexicon
import SQLiteData
import Tagged

public struct EventSearchFeature: Equatable, Identifiable, Sendable {
    public enum IDTag {}
    public typealias ID = Tagged<IDTag, String>

    public enum KnownID {
        public static let schedule = ID("schedule")
        public static let contributors = ID("contributors")
        public static let stages = ID("stages")
        public static let communications = ID("communications")
        public static let location = ID("location")
        public static let contact = ID("contact")
        public static let posters = ID("posters")
        public static let alerts = ID("alerts")
        public static let about = ID("about")
    }

    public init(
        id: ID,
        title: String,
        subtitle: String = "Feature",
        body: String? = nil,
        keywords: String,
        baseRank: Int = 800
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.keywords = keywords
        self.baseRank = baseRank
    }

    public var id: ID
    public var title: String
    public var subtitle: String
    public var body: String?
    public var keywords: String
    public var baseRank: Int

    public static let indexedFeatures: [Self] = [
        Self(
            id: KnownID.schedule,
            title: "Schedule",
            body: "Lineup, set times, performances, and stage schedule.",
            keywords: "schedule lineup set times performances timetable"
        ),
        Self(
            id: KnownID.contributors,
            title: "Contributors",
            body: "Artists, performers, facilitators, and event contributors.",
            keywords: "contributors artists performers facilitators lineup"
        ),
        Self(
            id: KnownID.stages,
            title: "Stages",
            body: "Stage list, stage details, and stage lineups.",
            keywords: "stages venues areas locations"
        ),
        Self(
            id: KnownID.communications,
            title: "Comms",
            body: "Event announcements, channels, and communications.",
            keywords: "communications comms channels announcements updates"
        ),
        Self(
            id: KnownID.location,
            title: "Location",
            body: "Venue location, directions, maps, and arrival information.",
            keywords: "location venue map directions address"
        ),
        Self(
            id: KnownID.contact,
            title: "Contact",
            body: "Event contact numbers, reporting links, and support information.",
            keywords: "contact phone help support report reporting incident safety"
        ),
        Self(
            id: KnownID.posters,
            title: "Posters",
            body: "Event posters and shared images.",
            keywords: "posters images flyers photos"
        ),
        Self(
            id: KnownID.about,
            title: "About",
            body: "Event description, details and general information.",
            keywords: "about info details description"
        ),
    ]
}

public struct EventSearchDocument: Equatable, Identifiable, Sendable {
    public enum Kind: String, Equatable, Hashable, Sendable {
        case channel
        case contact
        case contributor
        case eventInfo
        case feature
        case location
        case performance
        case poster
        case stage
    }

    public enum Target: Equatable, Hashable, Sendable {
        case channel(Social.Category.ID)
        case contributor(Contributor.ID)
        case feature(EventSearchFeature.ID)
        case performance(ProgramItem.ID)
        case stage(EventPlace.ID)
    }

    public init(
        id: String,
        eventID: Event.ID,
        kind: Kind,
        title: String,
        subtitle: String? = nil,
        body: String? = nil,
        keywords: String = "",
        target: Target,
        baseRank: Int = 0
    ) {
        self.id = id
        self.eventID = eventID
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.keywords = keywords
        self.target = target
        self.baseRank = baseRank
    }

    public var id: String
    public var eventID: Event.ID
    public var kind: Kind
    public var title: String
    public var subtitle: String?
    public var body: String?
    public var keywords: String
    public var target: Target
    public var baseRank: Int
}

public struct EventSearchTerm: Equatable, Hashable, RawRepresentable, Sendable {
    public init?(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0).lowercased() }
        guard !tokens.isEmpty
        else { return nil }

        self.rawValue = trimmed
        self.tokens = tokens
    }

    public let rawValue: String
    let tokens: [String]
}

public struct EventSearchRank: Equatable, Comparable, Sendable {
    public enum Field: Int, Equatable, Sendable {
        case matchedText = 0
        case body = 100
        case subtitle = 200
        case keywords = 300
        case title = 400
    }

    public init(baseRank: Int, field: Field) {
        self.baseRank = baseRank
        self.field = field
    }

    public var baseRank: Int
    public var field: Field

    public static func < (lhs: Self, rhs: Self) -> Bool {
        guard lhs.sortValue == rhs.sortValue
        else { return lhs.sortValue < rhs.sortValue }

        guard lhs.baseRank == rhs.baseRank
        else { return lhs.baseRank < rhs.baseRank }

        return lhs.field.rawValue < rhs.field.rawValue
    }

    private var sortValue: Int { baseRank + field.rawValue }
}

public struct EventSearchResult: Equatable, Identifiable, Sendable {
    public init(document: EventSearchDocument, rank: EventSearchRank) {
        self.document = document
        self.rank = rank
    }

    public var id: String { document.id }
    public var document: EventSearchDocument
    public var rank: EventSearchRank
}

public enum EventSearchIndex {
    public static func results(
        matching term: EventSearchTerm,
        in eventID: Event.ID,
        limit: Int = 25,
        db: Database
    ) throws -> [EventSearchResult] {
        guard limit > 0, try Event.find(eventID).fetchOne(db) != nil
        else { return [] }

        let categories = try Social.Category
            .where { $0.event.eq(eventID) }
            .fetchAll(db)
        let contributors = try Contributor
            .where { $0.event.eq(eventID) }
            .fetchAll(db)
        let places = try EventPlace
            .where { $0.event.eq(eventID) }
            .fetchAll(db)
        let items = try ProgramItem
            .where { $0.event.eq(eventID) }
            .fetchAll(db)

        var documents = EventSearchFeature.indexedFeatures.map { feature in
            EventSearchDocument(
                id: "feature:\(feature.id.rawValue)",
                eventID: eventID,
                kind: .feature,
                title: feature.title,
                subtitle: feature.subtitle,
                body: feature.body,
                keywords: feature.keywords,
                target: .feature(feature.id),
                baseRank: feature.baseRank
            )
        }
        documents += categories.map { category in
            EventSearchDocument(
                id: "channel:\(category.id)",
                eventID: eventID,
                kind: .channel,
                title: category.name,
                subtitle: "Comms",
                body: category.description,
                keywords: "channel announcements updates communications",
                target: .channel(category.id),
                baseRank: 700
            )
        }
        documents += contributors.map { contributor in
            EventSearchDocument(
                id: "contributor:\(contributor.id)",
                eventID: eventID,
                kind: .contributor,
                title: contributor.name,
                subtitle: "Artist",
                body: contributor.description,
                keywords: "artist contributor performer lineup",
                target: .contributor(contributor.id),
                baseRank: 850
            )
        }
        documents += places.compactMap { place -> EventSearchDocument? in
            guard case .known(.stage) = place.kind else { return nil }
            return EventSearchDocument(
                id: "stage:\(place.id)",
                eventID: eventID,
                kind: .stage,
                title: place.name,
                subtitle: "Stage",
                body: place.description,
                keywords: "stage venue area location \(place.name)",
                target: .stage(place.id),
                baseRank: 900
            )
        }
        documents += items.map { item in
            EventSearchDocument(
                id: "performance:\(item.id)",
                eventID: eventID,
                kind: .performance,
                title: item.title,
                subtitle: "Performance",
                body: item.description,
                keywords: "performance set show music lineup",
                target: .performance(item.id),
                baseRank: 950
            )
        }

        return documents
            .filter { matches($0, term: term) }
            .map {
                EventSearchResult(
                    document: $0,
                    rank: EventSearchRank(
                        baseRank: $0.baseRank,
                        field: matchedField(in: $0, term: term)
                    )
                )
            }
            .sorted { lhs, rhs in
                guard lhs.rank == rhs.rank
                else { return lhs.rank > rhs.rank }

                guard lhs.document.title == rhs.document.title
                else { return lhs.document.title < rhs.document.title }

                return lhs.document.id < rhs.document.id
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func matches(
        _ document: EventSearchDocument,
        term: EventSearchTerm
    ) -> Bool {
        let words = [document.title, document.keywords, document.subtitle, document.body]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
        return term.tokens.allSatisfy { token in
            words.contains { $0.hasPrefix(token) }
        }
    }

    private static func matchedField(
        in document: EventSearchDocument,
        term: EventSearchTerm
    ) -> EventSearchRank.Field {
        if contains(document.title, term: term) {
            return .title
        } else if contains(document.keywords, term: term) {
            return .keywords
        } else if contains(document.subtitle, term: term) {
            return .subtitle
        } else if contains(document.body, term: term) {
            return .body
        } else {
            return .matchedText
        }
    }

    private static func contains(
        _ text: String?,
        term: EventSearchTerm
    ) -> Bool {
        guard let text
        else { return false }

        let searchableText = text.lowercased()
        return term.tokens.contains { searchableText.contains($0) }
    }
}
