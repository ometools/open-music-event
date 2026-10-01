import ATProto
import Foundation
import ATProtoTypes
import ATProtoSQLite
import OpenMusicEventTimeZones
import SQLiteData

@Table("events.openmusic.event")
@Lexicon("events.openmusic.event", type: .record(key: .tid), description: "An organizer-owned music event, including its public boundaries, locations, programs, festival-day schedules, links, and media.")
public struct Event: RecordCodable, Equatable {
    public typealias ID = ATProto.URI

    @LexiconIgnored
    @Column(primaryKey: true)
    public let id: ATProto.URI

    @LexiconIgnored
    public var cid: ATProto.CID? = nil

    @LexiconField(description: "The public name of the event.", minLength: 1, maxLength: 5_000, maxGraphemes: 500)
    public var name: String

    @LexiconField(description: "Client-declared timestamp when this event record was created.")
    public var createdAt: ATProto.DateTime

    @LexiconField(encoding: TimeZoneIdentifier.self, description: "The IANA time-zone identifier used for calendar days and event-local schedule display.", minLength: 1, maxLength: 64)
    public var timeZone: TimeZone

    @LexiconField(description: "A public description of the event.", maxLength: 30_000, maxGraphemes: 3_000)
    public var description: String? = nil

    @LexiconField(description: "The event's starting calendar day or exact instant. Omitted when it has not been announced.")
    @Column(as: Open<Time>.JSONRepresentation?.self)
    public var start: Open<Time>? = nil

    @LexiconField(description: "The event's ending calendar day or exact instant. Omitted when it has not been announced.")
    @Column(as: Open<Time>.JSONRepresentation?.self)
    public var end: Open<Time>? = nil

    @LexiconField(description: "The event's current planning or cancellation status.")
    public var status: Open<Status>? = nil

    @LexiconField(description: "How attendees can participate in the event.")
    public var mode: Open<Mode>? = nil

    @LexiconField(description: "Named event locations. Array order is the organizer's preferred display order.")
    @Column(as: [Location].JSONRepresentation?.self)
    public var locations: [Location]? = nil

    @LexiconField(description: "Public links for the event. Array order is the organizer's preferred display order.")
    @Column(as: [OME.Link].JSONRepresentation?.self)
    public var links: [OME.Link]? = nil

    @LexiconField(description: "Media attached to the event. Array order is the organizer's preferred display order.")
    @Column(as: [Open<OME.Media>].JSONRepresentation?.self)
    public var media: [Open<OME.Media>]? = nil

    @LexiconField(description: "The event's attendee-facing programs in organizer-defined tab order.", minLength: 1)
    @Column(as: [ATProto.URI].JSONRepresentation?.self)
    public var programs: [ATProto.URI]? = nil

    @LexiconField(description: "The event's organizer-defined festival days in attendee-facing order.", minLength: 1)
    @Column(as: [ATProto.URI].JSONRepresentation?.self)
    public var schedules: [ATProto.URI]? = nil

    @LexiconField(description: "Whether the organizer requests a response from attendees. Omitted when unspecified.")
    public var rsvpExpected: Bool? = nil

    @LexiconField(description: "The event's post categories in organizer-defined display order. When present this is the complete category list.", minLength: 1)
    @Column(as: [ATProto.URI].JSONRepresentation?.self)
    public var categories: [ATProto.URI]? = nil

    @LexiconField(description: "The event's selectable site-map images and default style.")
    @Column(as: SiteMap.JSONRepresentation?.self)
    public var siteMap: SiteMap? = nil

    /// Call at the authoring or verified ingestion boundary, separately from payload decoding.
    public func validateReferences() throws {
        try LexiconCoding.validateRecordURI(id, type: Self.self)

        var seenCategories: Set<ATProto.URI> = []
        for (index, category) in (categories ?? []).enumerated() {
            do { try LexiconCoding.validateRecordURI(category, type: Social.Category.self) }
            catch let error as ValidationError {
                throw ValidationError(error.reason, path: ["categories", String(index)] + error.path)
            }
            guard category.authority == id.authority else {
                throw ValidationError("An event's category must be published in the event repository", path: ["categories", String(index)])
            }
            guard seenCategories.insert(category).inserted else {
                throw ValidationError("An event's category cannot be repeated", path: ["categories", String(index)])
            }
        }
        if let siteMap {
            do { try siteMap.validate() }
            catch let error as ValidationError {
                throw ValidationError(error.reason, path: ["siteMap"] + error.path)
            }
        }

        var seenPrograms: Set<ATProto.URI> = []
        for (index, program) in (programs ?? []).enumerated() {
            do {
                try LexiconCoding.validateRecordURI(program, type: Program.self)
            } catch let error as ValidationError {
                throw ValidationError(error.reason, path: ["programs", String(index)] + error.path)
            }
            guard program.authority == id.authority else {
                throw ValidationError("An event's program must be published in the event repository", path: ["programs", String(index)])
            }
            guard seenPrograms.insert(program).inserted else {
                throw ValidationError("An event's program cannot be repeated", path: ["programs", String(index)])
            }
        }

        var seenSchedules: Set<ATProto.URI> = []
        for (index, schedule) in (schedules ?? []).enumerated() {
            do {
                try LexiconCoding.validateRecordURI(schedule, type: Schedule.self)
            } catch let error as ValidationError {
                throw ValidationError(error.reason, path: ["schedules", String(index)] + error.path)
            }
            guard schedule.authority == id.authority else {
                throw ValidationError("An event's schedule must be published in the event repository", path: ["schedules", String(index)])
            }
            guard seenSchedules.insert(schedule).inserted else {
                throw ValidationError("An event's schedule cannot be repeated", path: ["schedules", String(index)])
            }
        }
        _ = try encodeLexicon()
    }
}

public extension Event {
    struct IndexedRecord: Codable, Equatable, Sendable {
        public init(uri: Event.ID, cid: ATProto.CID?, value: Lexicon.JSONValue) {
            self.uri = uri
            self.cid = cid
            self.value = value
        }

        public var uri: Event.ID
        public var cid: ATProto.CID?
        public var value: Lexicon.JSONValue

        public func event() throws -> Event {
            let event = try Event.decodeLexicon(
                value,
                metadata: RecordMetadata(uri: uri, cid: cid)
            )
            try event.validateReferences()
            return event
        }
    }

    struct Page: Codable, Equatable, Sendable {
        public init(events: [IndexedRecord], cursor: String? = nil) {
            self.events = events
            self.cursor = cursor
        }

        public var events: [IndexedRecord]
        public var cursor: String?
    }

    struct GetEvent: XRPC.Query, Sendable {
        public static let nsid = ATProto.NSID("events.openmusic.getEvent")
        public typealias Input = Never
        public typealias Output = IndexedRecord

        public init(uri: Event.ID) {
            self.parameters = Parameters(uri: uri)
        }

        public var parameters: Parameters

        public struct Parameters: Codable, Equatable, Sendable {
            public var uri: Event.ID
        }
    }

    struct GetEvents: XRPC.Query, Sendable {
        public static let nsid = ATProto.NSID("events.openmusic.getEvents")
        public typealias Input = Never
        public typealias Output = Page

        public init(cursor: String? = nil, limit: Int = 100) {
            self.parameters = Parameters(cursor: cursor, limit: limit)
        }

        public var parameters: Parameters

        public struct Parameters: Codable, Equatable, Sendable {
            public var cursor: String?
            public var limit: Int
        }
    }
}

public extension Open where Known == Event.Time {
    func date(in timeZone: TimeZone) -> Date? {
        switch self {
        case let .known(.day(day)):
            day.value.atStartOfDay(in: timeZone)
        case let .known(.time(instant)):
            (try? Date(instant.value.rawValue, strategy: .iso8601.time(includingFractionalSeconds: true)))
                ?? (try? Date(instant.value.rawValue, strategy: .iso8601))
        case .unknown:
            nil
        }
    }
}

extension Event {
    public enum TimeZoneIdentifier: LexiconFieldEncoding {
        public static func encode(_ value: TimeZone) -> String { value.identifier }
        public static func decode(_ value: String) throws -> TimeZone {
            guard let zone = TimeZone(identifier: value) else { throw ValidationError("Invalid time zone identifier") }
            return zone
        }
    }

    public enum LocalDayString: LexiconFieldEncoding {
        public static func encode(_ value: LocalDate) -> String { value.rawValue }
        public static func decode(_ value: String) throws -> LocalDate {
            guard let day = LocalDate(value) else { throw ValidationError("Invalid calendar day") }
            return day
        }
    }

    public enum URLString: LexiconFieldEncoding {
        public static func encode(_ value: URL) -> String { value.absoluteString }
        public static func decode(_ value: String) throws -> URL {
            guard let url = URL(string: value) else { throw ValidationError("Invalid URL") }
            return url
        }
    }

    @LexiconUnion
    public enum Time: Equatable, Sendable {
        case day(Day)
        case time(Instant)
    }

    @Lexicon("events.openmusic.defs#day", description: "A calendar day in the event's declared time zone, used when an exact instant is not appropriate or not yet known.")
    public struct Day: Equatable, Sendable {
        @LexiconField(encoding: LocalDayString.self, description: "A calendar date written as YYYY-MM-DD.", minLength: 10, maxLength: 10)
        public var value: LocalDate
    }

    @Lexicon("events.openmusic.defs#time", description: "An exact instant used for an event schedule boundary.")
    public struct Instant: Equatable, Sendable {
        @LexiconField(description: "The exact event boundary as an AT Protocol datetime.")
        public var value: ATProto.DateTime
    }

    @Lexicon("events.openmusic.defs#eventStatus", type: .string, description: "A known lifecycle status for an event. Other string values may be used by extensions.")
    public enum Status: String, Equatable, Sendable {
        case planned = "community.lexicon.calendar.event#planned"
        case scheduled = "community.lexicon.calendar.event#scheduled"
        case rescheduled = "community.lexicon.calendar.event#rescheduled"
        case cancelled = "community.lexicon.calendar.event#cancelled"
        case postponed = "community.lexicon.calendar.event#postponed"
    }

    @Lexicon("events.openmusic.defs#eventMode", type: .string, description: "A known attendance mode for an event. Other string values may be used by extensions.")
    public enum Mode: String, Equatable, Sendable {
        case inPerson = "community.lexicon.calendar.event#inperson"
        case virtual = "community.lexicon.calendar.event#virtual"
        case hybrid = "community.lexicon.calendar.event#hybrid"
    }

}
