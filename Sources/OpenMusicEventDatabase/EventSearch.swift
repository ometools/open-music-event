import Foundation
import OpenMusicEventLexicon
import SQLiteData
import class GRDB.DatabaseFunction
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
    public init(document: EventSearchDocument, rank: EventSearchRank, artwork: OME.Image? = nil, performance: PerformanceDashboardRow? = nil) {
        self.document = document
        self.rank = rank
        self.artwork = artwork
        self.performance = performance
    }

    public var id: String { document.id }
    public var document: EventSearchDocument
    public var rank: EventSearchRank
    public var artwork: OME.Image?
    public var performance: PerformanceDashboardRow?
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

        db.add(function: GRDB.DatabaseFunction("ome_search_field", argumentCount: 4, pure: true) { values in
            let fields = values.map { String.fromDatabaseValue($0) ?? "" }
            let words = fields.joined(separator: " ").lowercased()
                .split { !$0.isLetter && !$0.isNumber }
            guard term.tokens.allSatisfy({ token in words.contains { $0.hasPrefix(token) } })
            else { return -1 }
            for (index, rank) in [400, 300, 200, 100].enumerated() {
                if term.tokens.contains(where: { fields[index].lowercased().contains($0) }) {
                    return rank
                }
            }
            return 0
        })
        let features = try String(decoding: JSONSerialization.data(withJSONObject:
            EventSearchFeature.indexedFeatures.map {
                ["id": $0.id.rawValue, "title": $0.title, "subtitle": $0.subtitle,
                 "body": $0.body ?? "", "keywords": $0.keywords, "baseRank": $0.baseRank] as [String: Any]
            }), as: UTF8.self)
        let artwork = ContributorArtworkQuery.image(media: Contributor.media.queryFragment)
        let matches = try #sql(
            """
            WITH documents(kind, recordID, title, subtitle, body, keywords, baseRank) AS (
                SELECT 'feature', json_extract(value, '$.id'), json_extract(value, '$.title'),
                       json_extract(value, '$.subtitle'), json_extract(value, '$.body'),
                       json_extract(value, '$.keywords'), json_extract(value, '$.baseRank')
                FROM json_each(\(features))
                UNION ALL
                SELECT 'channel', id, name, 'Comms', description,
                       'channel announcements updates communications', 700
                FROM \(Social.Category.self) WHERE event = \(eventID)
                UNION ALL
                SELECT 'contributor', id, name, 'Artist', description,
                       'artist contributor performer lineup', 850
                FROM \(Contributor.self) WHERE event = \(eventID)
                UNION ALL
                SELECT 'stage', id, name, 'Stage', description,
                       'stage venue area location ' || name, 900
                FROM \(EventPlace.self) WHERE event = \(eventID)
                  AND json_extract(kind, '$.$type') = 'events.openmusic.defs#eventPlaceStage'
                UNION ALL
                SELECT 'performance', id, title, 'Performance', description,
                       'performance set show music lineup', 950
                FROM \(ProgramItem.self) WHERE event = \(eventID)
            ), ranked AS MATERIALIZED (
                SELECT *, ome_search_field(title, keywords, subtitle, body) AS field FROM documents
            ), matches AS MATERIALIZED (
                SELECT * FROM ranked WHERE field >= 0
                ORDER BY baseRank + field DESC, baseRank DESC, field DESC, title, kind || ':' || recordID
                LIMIT \(limit)
            )
            SELECT matches.kind, recordID, matches.title, subtitle, body, keywords, baseRank, field,
                   (SELECT \(artwork) FROM \(Contributor.self)
                    WHERE \(Contributor.id) = matches.recordID AND \(Contributor.event) = \(eventID)
                      AND matches.kind = 'contributor'),
                   \(ProgramItem.columns), \(EventPlace.columns)
            FROM matches
            LEFT JOIN \(ProgramItem.self) ON \(ProgramItem.id) = matches.recordID
                AND matches.kind = 'performance' AND \(ProgramItem.event) = \(eventID)
            LEFT JOIN \(EventPlace.self) ON \(EventPlace.id) = \(ProgramItem.eventPlace)
                AND \(EventPlace.event) = \(eventID)
            ORDER BY baseRank + field DESC, baseRank DESC, field DESC, matches.title, matches.kind || ':' || recordID
            """, as: SearchMatch.self
        ).fetchAll(db)
        return matches.compactMap { row in
            let target: EventSearchDocument.Target
            switch row.kind {
            case "feature": target = .feature(.init(row.recordID))
            case "contributor":
                guard let id = Contributor.ID(row.recordID) else { return nil }
                target = .contributor(id)
            case "performance":
                guard let id = ProgramItem.ID(row.recordID) else { return nil }
                target = .performance(id)
            case "stage":
                guard let id = EventPlace.ID(row.recordID) else { return nil }
                target = .stage(id)
            case "channel":
                guard let id = Social.Category.ID(row.recordID) else { return nil }
                target = .channel(id)
            default: return nil
            }
            guard let kind = EventSearchDocument.Kind(rawValue: row.kind),
                  let field = EventSearchRank.Field(rawValue: row.field) else { return nil }
            return EventSearchResult(
                document: EventSearchDocument(
                    id: "\(row.kind):\(row.recordID)", eventID: eventID, kind: kind,
                    title: row.title, subtitle: row.subtitle, body: row.body, keywords: row.keywords,
                    target: target, baseRank: row.baseRank
                ),
                rank: EventSearchRank(baseRank: row.baseRank, field: field), artwork: row.artwork,
                performance: row.programItem.map { PerformanceDashboardRow(performance: $0, stage: row.eventPlace) }
            )
        }
    }
}

@Selection
private struct SearchMatch {
    let kind: String
    let recordID: String
    let title: String
    let subtitle: String?
    let body: String?
    let keywords: String
    let baseRank: Int
    let field: Int
    @Column(as: OME.Image.JSONRepresentation?.self)
    let artwork: OME.Image?
    let programItem: ProgramItem?
    let eventPlace: EventPlace?
}
