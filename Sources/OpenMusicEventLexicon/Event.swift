import ATProto
import Foundation
import ATProtoTypes
import ATProtoSQLite
import OpenMusicEventTimeZones
import SQLiteData

@Table("events.openmusic.event")
@Lexicon("events.openmusic.event", type: .record(key: .tid), description: "An organizer-owned music event, including its public boundaries, locations, programs, festival-day schedules, links, and media.")
public struct Event: RecordCodable, Equatable {
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

    /// Call at the authoring or verified ingestion boundary, separately from payload decoding.
    public func validateReferences() throws {
        try LexiconCoding.validateRecordURI(id, type: Self.self)

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

