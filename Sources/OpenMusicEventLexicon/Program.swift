import ATProto
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData

@Table("events.openmusic.program")
@Lexicon("events.openmusic.program", type: .record(key: .tid), description: "One organizer-defined attendee-facing program within an event, such as the main schedule or workshops.")
public struct Program: RecordCodable, Equatable {
    @LexiconIgnored
    @Column(primaryKey: true)
    public let id: ATProto.URI

    @LexiconIgnored
    public var cid: ATProto.CID? = nil

    @LexiconField(description: "The DID-based record URI of the events.openmusic.event containing this program.")
    public var event: Event.ID

    @LexiconField(description: "The attendee-facing title used for this program's tab or section.", minLength: 1, maxLength: 5_000, maxGraphemes: 500)
    public var title: String

    @LexiconField(description: "Client-declared timestamp when this program record was created.")
    public var createdAt: ATProto.DateTime

    @LexiconField(description: "A public description of this attendee-facing program.", maxLength: 30_000, maxGraphemes: 3_000)
    public var description: String? = nil

    @LexiconField(description: "A platform-neutral icon for this program's tab or section.")
    public var icon: OME.SemanticIcon? = nil

    @LexiconField(description: "The exhaustive list of places used by this program, in organizer-defined lane order. An empty list means the program contains only unplaced items.")
    @Column(as: [ATProto.URI].JSONRepresentation.self)
    public var eventPlaces: [ATProto.URI]

    /// Call at the authoring or verified ingestion boundary, separately from payload decoding.
    public func validateReferences() throws {
        try LexiconCoding.validateRecordURI(id, type: Self.self)
        try LexiconCoding.validateRecordURI(event, type: Event.self)
        guard id.authority == event.authority else {
            throw ValidationError("A program must be published in its event's repository", path: ["event"])
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("A program title cannot be blank", path: ["title"])
        }
        var seenPlaces: Set<ATProto.URI> = []
        for (index, eventPlace) in eventPlaces.enumerated() {
            do {
                try LexiconCoding.validateRecordURI(eventPlace, type: EventPlace.self)
            } catch let error as ValidationError {
                throw ValidationError(error.reason, path: ["eventPlaces", String(index)] + error.path)
            }
            guard eventPlace.authority == event.authority else {
                throw ValidationError("A program's place must be published in its event's repository", path: ["eventPlaces", String(index)])
            }
            guard seenPlaces.insert(eventPlace).inserted else {
                throw ValidationError("A program's place cannot be repeated", path: ["eventPlaces", String(index)])
            }
        }
        _ = try encodeLexicon()
    }
}
