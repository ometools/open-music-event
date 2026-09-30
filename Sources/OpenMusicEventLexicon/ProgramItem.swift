import ATProto
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData

@Table("events.openmusic.programItem")
@Lexicon("events.openmusic.programItem", type: .record(key: .tid), description: "One organizer-owned attendee-facing occurrence, span, or milestone in an event program. It may be announced before its time or place is assigned.")
public struct ProgramItem: RecordCodable, Equatable {
    @LexiconIgnored
    @Column(primaryKey: true)
    public let id: ATProto.URI

    @LexiconIgnored
    public var cid: ATProto.CID? = nil

    @LexiconField(description: "The DID-based record URI of the events.openmusic.event containing this program item.")
    public var event: Event.ID

    @LexiconField(description: "The DID-based events.openmusic.program this item belongs to.")
    public var program: ATProto.URI

    @LexiconField(description: "The organizer's public title for this occurrence, span, or milestone.", minLength: 1, maxLength: 5_000, maxGraphemes: 500)
    public var title: String

    @LexiconField(description: "Client-declared timestamp when this program item record was created. Preserved when scheduling details change.")
    public var createdAt: ATProto.DateTime

    @LexiconField(description: "A public description of this program item.", maxLength: 30_000, maxGraphemes: 3_000)
    public var description: String? = nil

    @LexiconField(description: "The organizer-defined events.openmusic.schedule festival day assigned to this item. Omitted until a day is assigned.")
    public var schedule: ATProto.URI? = nil

    @LexiconField(description: "The DID-based events.openmusic.eventPlace assigned to this item. Omitted until a place is assigned.")
    public var eventPlace: ATProto.URI? = nil

    @LexiconField(description: "The exact instant when this item starts. Omitted until the start is assigned.")
    public var startsAt: ATProto.DateTime? = nil

    @LexiconField(description: "The exact instant when this item ends. Requires startsAt and must be later than it.")
    public var endsAt: ATProto.DateTime? = nil

    @LexiconField(description: "Ordered organizer-authored credits. Omitted for items such as doors opening that have no credited contributors.", minLength: 1)
    @Column(as: [Credit].JSONRepresentation?.self)
    public var credits: [Credit]? = nil

    @LexiconField(description: "Media attached to this particular occurrence. Array order is the organizer's preferred display order.")
    @Column(as: [Open<OME.Media>].JSONRepresentation?.self)
    public var media: [Open<OME.Media>]? = nil

    /// Call at the authoring or verified ingestion boundary, separately from payload decoding.
    public func validateReferences() throws {
        try LexiconCoding.validateRecordURI(id, type: Self.self)
        try LexiconCoding.validateRecordURI(event, type: Event.self)
        guard id.authority == event.authority else {
            throw ValidationError("A program item must be published in its event's repository", path: ["event"])
        }
        try LexiconCoding.validateRecordURI(program, type: Program.self)
        guard program.authority == event.authority else {
            throw ValidationError("A program item's program must be published in its event's repository", path: ["program"])
        }
        if let schedule {
            try LexiconCoding.validateRecordURI(schedule, type: Schedule.self)
            guard schedule.authority == event.authority else {
                throw ValidationError("A program item's schedule must be published in its event's repository", path: ["schedule"])
            }
        }
        if let eventPlace {
            try LexiconCoding.validateRecordURI(eventPlace, type: EventPlace.self)
            guard eventPlace.authority == event.authority else {
                throw ValidationError("A program item's place must be published in its event's repository", path: ["eventPlace"])
            }
        }
        if let endsAt {
            guard let startsAt else {
                throw ValidationError("A program item end requires a start", path: ["endsAt"])
            }
            guard let start = Self.date(startsAt), let end = Self.date(endsAt), end > start else {
                throw ValidationError("A program item end must be later than its start", path: ["endsAt"])
            }
        }
        if startsAt != nil, schedule == nil {
            throw ValidationError("A timed program item requires an organizer-assigned schedule", path: ["schedule"])
        }
        for (index, media) in (media ?? []).enumerated() {
            guard case .known(let media) = media else { continue }
            do {
                try media.validateForPublication()
            } catch let error as ValidationError {
                throw ValidationError(error.reason, path: ["media", String(index)] + error.path)
            }
        }
        for (index, credit) in (credits ?? []).enumerated() {
            guard let contributor = credit.contributor else { continue }
            do {
                try LexiconCoding.validateRecordURI(contributor, type: Contributor.self)
            } catch let error as ValidationError {
                throw ValidationError(error.reason, path: ["credits", String(index), "contributor"] + error.path)
            }
            guard contributor.authority == event.authority else {
                throw ValidationError("A program credit's contributor must be published in its event's repository", path: ["credits", String(index), "contributor"])
            }
        }
        _ = try encodeLexicon()
    }

    /// Validates the resolved event graph at an authoring or verified ingestion boundary.
    public func validateGraph(
        event resolvedEvent: Event,
        program resolvedProgram: Program,
        schedule resolvedSchedule: Schedule? = nil,
        eventPlace resolvedEventPlace: EventPlace? = nil
    ) throws {
        try validateReferences()
        try resolvedEvent.validateReferences()
        try resolvedProgram.validateReferences()
        try resolvedSchedule?.validateReferences()
        try resolvedEventPlace?.validateReferences()

        guard resolvedEvent.id == event else {
            throw ValidationError("The resolved event does not match the program item", path: ["event"])
        }
        guard resolvedProgram.id == program, resolvedProgram.event == event else {
            throw ValidationError("The resolved program does not belong to the program item's event", path: ["program"])
        }
        guard resolvedEvent.programs?.contains(program) == true else {
            throw ValidationError("The program item references a program not declared by its event", path: ["program"])
        }

        if let schedule {
            guard let resolvedSchedule, resolvedSchedule.id == schedule, resolvedSchedule.event == event else {
                throw ValidationError("The resolved schedule does not belong to the program item's event", path: ["schedule"])
            }
            guard resolvedEvent.schedules?.contains(schedule) == true else {
                throw ValidationError("The program item references a schedule not declared by its event", path: ["schedule"])
            }
        } else if resolvedSchedule != nil {
            throw ValidationError("The resolved schedule is not assigned to the program item", path: ["schedule"])
        }

        if let eventPlace {
            guard let resolvedEventPlace, resolvedEventPlace.id == eventPlace, resolvedEventPlace.event == event else {
                throw ValidationError("The resolved place does not belong to the program item's event", path: ["eventPlace"])
            }
            guard resolvedProgram.eventPlaces.contains(eventPlace) else {
                throw ValidationError("The program item's place is not declared by its program", path: ["eventPlace"])
            }
        } else if resolvedEventPlace != nil {
            throw ValidationError("The resolved place is not assigned to the program item", path: ["eventPlace"])
        }
    }

    static func date(_ value: ATProto.DateTime) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value.rawValue) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value.rawValue)
    }
}

extension ProgramItem {
    @Lexicon("events.openmusic.defs#programCredit", description: "One organizer-authored credit for a program item. The display name keeps the item renderable without dereferencing another repository.")
    public struct Credit: Equatable, Sendable {
        @LexiconField(description: "The organizer-owned display name for this credit.", minLength: 1, maxLength: 5_000, maxGraphemes: 500)
        public var name: String

        @LexiconField(description: "The optional DID-based URI of this event's organizer-authored events.openmusic.contributor record.")
        public var contributor: ATProto.URI? = nil

        @LexiconField(required: false, default: "primary", description: "How prominently this contributor is billed. Defaults to primary when omitted.")
        public var billing: Open<Billing> = .known(.primary)

        @LexiconField(description: "The contributor's role in this program item.", minLength: 1, maxLength: 1_000, maxGraphemes: 100)
        public var role: String? = nil
    }

    @Lexicon("events.openmusic.defs#programBilling", type: .string, description: "A known billing level for a program credit. Other string values may be used by extensions.")
    public enum Billing: String, Equatable, Sendable {
        case primary
        case supporting
    }
}
