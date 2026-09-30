import ATProto
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData

@Table("events.openmusic.stage")
@Lexicon("events.openmusic.stage", type: .record(key: .tid), description: "A persistent stage identity that can be followed and linked across event editions. Its repository owns this profile; event places own their separate event-specific presentation.")
public struct Stage: RecordCodable, Equatable {
    @LexiconIgnored
    @Column(primaryKey: true)
    public let id: ATProto.URI

    @LexiconIgnored
    public var cid: ATProto.CID? = nil

    @LexiconField(description: "The public name of the persistent stage.", minLength: 1, maxLength: 5_000, maxGraphemes: 500)
    public var name: String

    @LexiconField(description: "Client-declared timestamp when this record was created. Preserved through profile edits.")
    public var createdAt: ATProto.DateTime

    @LexiconField(description: "A public description of the persistent stage.", maxLength: 30_000, maxGraphemes: 3_000)
    public var description: String? = nil

    @LexiconField(description: "Public links for the stage, in preferred display order.")
    @Column(as: [OME.Link].JSONRepresentation?.self)
    public var links: [OME.Link]? = nil

    @LexiconField(description: "Media for this stage profile, in preferred display order. Event places do not inherit these values automatically.")
    @Column(as: [Open<OME.Media>].JSONRepresentation?.self)
    public var media: [Open<OME.Media>]? = nil
}
