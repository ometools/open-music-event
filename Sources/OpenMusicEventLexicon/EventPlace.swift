import ATProto
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData

@Table("events.openmusic.eventPlace")
@Lexicon("events.openmusic.eventPlace", type: .record(key: .tid), description: "An organizer-owned named destination within one event edition. The record must be in the event's repository and contains its own display data, independently of any linked persistent stage.")
public struct EventPlace: RecordCodable, Equatable {
    @LexiconIgnored
    @Column(primaryKey: true)
    public let id: ATProto.URI

    @LexiconIgnored
    public var cid: ATProto.CID? = nil

    @LexiconField(description: "The DID-based record URI of the events.openmusic.event edition containing this place. A different edition requires a new place identity.")
    public var event: ATProto.URI

    @LexiconField(description: "The organizer's name for this place, independent of any persistent stage profile.", minLength: 1, maxLength: 5_000, maxGraphemes: 500)
    public var name: String

    @LexiconField(description: "Client-declared timestamp when this record was created. Preserved through place edits.")
    public var createdAt: ATProto.DateTime

    @LexiconField(description: "The organizer's description of the place, such as access or arrival instructions within the event.", maxLength: 30_000, maxGraphemes: 3_000)
    public var description: String? = nil

    @LexiconField(description: "Locators for this place. A map pin requires an understood coordinate locator; a place without one remains displayable by name.")
    @Column(as: [Open<Event.Locator>].JSONRepresentation?.self)
    public var locators: [Open<Event.Locator>]? = nil

    @LexiconField(description: "Public links for this place, in preferred display order. Missing values are not inherited from a linked stage.")
    @Column(as: [OME.Link].JSONRepresentation?.self)
    public var links: [OME.Link]? = nil

    @LexiconField(description: "Organizer-selected media for this place, in preferred display order. Blob sources belong to this record's repository. Missing values are not inherited from a linked stage.")
    @Column(as: [Open<OME.Media>].JSONRepresentation?.self)
    public var media: [Open<OME.Media>]? = nil

    @LexiconField(description: "The place's primary use. Missing or unrecognized kinds still render using the common place fields.")
    @Column(as: Open<Kind>.JSONRepresentation?.self)
    public var kind: Open<Kind>? = nil

    /// Call at the authoring or verified ingestion boundary, separately from payload decoding.
    /// Checks addresses and repository ownership, without resolving records or implying Stage-owner consent.
    public func validateReferences() throws {
        try LexiconCoding.validateRecordURI(id, type: Self.self)
        try LexiconCoding.validateRecordURI(event, type: Event.self)
        guard id.authority == event.authority else {
            throw ValidationError("An event place must be published in its event's repository", path: ["event"])
        }
        if case let .known(.stage(use)) = kind, let stage = use.stage {
            try LexiconCoding.validateRecordURI(stage, type: OpenMusicEventLexicon.Stage.self)
        }
    }
}

extension EventPlace {
    @LexiconUnion
    public enum Kind: Equatable, Sendable {
        case stage(Stage)
        case entrance(Entrance)
        case camping(Camping)
        case info(Info)
    }
}

extension EventPlace.Kind {
    @Lexicon("events.openmusic.defs#eventPlaceStage", description: "Stage use of an event place. All event-specific display data belongs to the containing place, and persistent identity is optional.")
    public struct Stage: Equatable, Sendable {
        @LexiconField(description: "An optional DID-based events.openmusic.stage record URI for continuity across editions. This is a live identity reference, not required rendering data or proof of the stage owner's agreement. Linking or unlinking it preserves the event place's identity.")
        public var stage: ATProto.URI? = nil

        @LexiconField(description: "The organizer's presentation color for this stage use. Missing means unspecified, without inheritance from a persistent stage.")
        public var color: OME.Color? = nil
    }

    @Lexicon("events.openmusic.defs#eventPlaceEntrance", description: "An entrance or gate within an event.")
    public struct Entrance: Equatable, Sendable {}

    @Lexicon("events.openmusic.defs#eventPlaceCamping", description: "A camping destination within an event.")
    public struct Camping: Equatable, Sendable {}

    @Lexicon("events.openmusic.defs#eventPlaceInfo", description: "An information point within an event.")
    public struct Info: Equatable, Sendable {}
}
