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
            body: "Event description, details, policies, and general information.",
            keywords: "about info details description policies"
        ),
    ]
}

@Table("eventSearchDocuments")
public struct EventSearchDocument: Equatable, Identifiable, Sendable {
    public enum IDTag {}
    public typealias ID = Tagged<IDTag, Int64>

    public enum StableIDTag {}
    public typealias StableID = Tagged<StableIDTag, String>

    public enum Kind: String, Codable, Equatable, Hashable, Sendable, SQLiteType {
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

    public enum Target: Codable, Equatable, Hashable, Sendable {
        case channel(OME.ID<OME.Channel>)
        case contributor(OME.ID<OME.Contributor>)
        case feature(EventSearchFeature.ID)
        case performance(OME.ID<OME.Performance>)
        case poster(OME.ID<OME.Poster>)
        case stage(OME.ID<OME.Stage>)
    }

    public init(
        id: ID,
        stableID: StableID,
        organizerID: OME.Organizer.ID,
        eventID: OME.ID<OME.Event>,
        kind: Kind,
        title: String,
        subtitle: String? = nil,
        body: String? = nil,
        keywords: String = "",
        target: Target,
        baseRank: Int = 0
    ) {
        self.id = id
        self.stableID = stableID
        self.organizerID = organizerID
        self.eventID = eventID
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.keywords = keywords
        self.target = target
        self.baseRank = baseRank
    }

    @Column(primaryKey: true)
    public var id: ID
    public var stableID: StableID
    public var organizerID: OME.Organizer.ID
    public var eventID: OME.ID<OME.Event>
    public var kind: Kind
    public var title: String
    public var subtitle: String?
    public var body: String?
    public var keywords: String
    @Column(as: Target.JSONRepresentation.self)
    public var target: Target
    public var baseRank: Int

    public var eventRecordID: OME.Event.ID {
        OME.Event.ID(organizerID: organizerID, eventID: eventID)
    }
}

@Table("eventSearchText")
public struct EventSearchText: Equatable, FTS5, Identifiable, Sendable {
    public init(
        rowid: EventSearchDocument.ID,
        title: String,
        keywords: String,
        subtitle: String,
        body: String
    ) {
        self.rowid = rowid
        self.title = title
        self.keywords = keywords
        self.subtitle = subtitle
        self.body = body
    }

    @Column(primaryKey: true)
    public let rowid: EventSearchDocument.ID
    public var id: EventSearchDocument.ID { rowid }

    public var title: String
    public var keywords: String
    public var subtitle: String
    public var body: String
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
        self.ftsQuery = tokens.map { "\($0)*" }.joined(separator: " ")
    }

    public let rawValue: String
    let tokens: [String]
    let ftsQuery: String
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

    public var id: EventSearchDocument.ID { document.id }
    public var document: EventSearchDocument
    public var rank: EventSearchRank
}

public enum EventSearchIndex {
    public static func results(
        matching term: EventSearchTerm,
        in eventID: OME.Event.ID,
        limit: Int = 25,
        db: Database
    ) throws -> [EventSearchResult] {
        guard limit > 0
        else { return [] }

        let textMatches = try EventSearchText
            .where { $0.match(term.ftsQuery) }
            .fetchAll(db)
        let documentIDs = textMatches.map(\.id)
        guard !documentIDs.isEmpty
        else { return [] }

        let documents = try EventSearchDocument
            .where { $0.id.in(documentIDs) }
            .where { $0.organizerID.eq(eventID.organizerID) }
            .where { $0.eventID.eq(eventID.eventID) }
            .fetchAll(db)

        return documents
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

                return lhs.document.stableID < rhs.document.stableID
            }
            .prefix(limit)
            .map { $0 }
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
