import ATProto
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData

@Table("events.openmusic.contributor")
@Lexicon("events.openmusic.contributor", type: .record(key: .tid), description: "An organizer-authored profile for a person, project, or other contributor to one event.")
public struct Contributor: RecordCodable, Equatable {
    @LexiconIgnored
    @Column(primaryKey: true)
    public let id: ATProto.URI

    @LexiconIgnored
    public var cid: ATProto.CID? = nil

    @LexiconField(description: "The DID-based record URI of the events.openmusic.event this contributor participated in.")
    public var event: Event.ID

    @LexiconField(description: "The organizer-owned display name for this event contributor.", minLength: 1, maxLength: 5_000, maxGraphemes: 500)
    public var name: String

    @LexiconField(description: "Client-declared timestamp when this contributor record was created.")
    public var createdAt: ATProto.DateTime

    @LexiconField(description: "The stable DID the organizer asserts is represented by this event profile. This assertion is not confirmation by that account.")
    public var subject: DID? = nil

    @LexiconField(description: "A pinned DID-authored profile record used as provenance when hydrating this organizer-owned snapshot.")
    @Column(as: Source.JSONRepresentation?.self)
    public var source: Source? = nil

    @LexiconField(description: "The organizer-authored public description of this contributor for this event.", maxLength: 30_000, maxGraphemes: 3_000)
    public var description: String? = nil

    @LexiconField(description: "Ordered event-wide roles. Array order is the organizer's preferred display order.", minLength: 1)
    @Column(as: [Open<Role>].JSONRepresentation?.self)
    public var roles: [Open<Role>]? = nil

    @LexiconField(description: "Public links for this event contributor. Array order is the organizer's preferred display order.")
    @Column(as: [OME.Link].JSONRepresentation?.self)
    public var links: [OME.Link]? = nil

    @LexiconField(description: "Media attached to this event contributor. Array order is the organizer's preferred display order.")
    @Column(as: [Open<OME.Media>].JSONRepresentation?.self)
    public var media: [Open<OME.Media>]? = nil

    /// Call at the authoring or verified ingestion boundary, separately from payload decoding.
    public func validateReferences() throws {
        try LexiconCoding.validateRecordURI(id, type: Self.self)
        try LexiconCoding.validateRecordURI(event, type: Event.self)
        guard id.authority == event.authority else {
            throw ValidationError("A contributor must be published in its event's repository", path: ["event"])
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("A contributor name cannot be blank", path: ["name"])
        }
        if let source {
            guard let subject else {
                throw ValidationError("A contributor source requires a subject DID", path: ["source"])
            }
            guard case .did(let author) = source.uri.authority,
                  source.uri.collection != nil,
                  source.uri.rkey != nil
            else {
                throw ValidationError("A contributor source requires a complete DID-authored record URI", path: ["source", "uri"])
            }
            guard author == subject else {
                throw ValidationError("A contributor source must be authored by the asserted subject", path: ["source", "uri"])
            }
        }
        var seenRoles: Set<String> = []
        for (index, role) in (roles ?? []).enumerated() {
            let value: String? = switch role {
            case .known(let role): role.rawValue
            case .unknown(let value): value.string
            }
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError("A contributor role must be a nonblank string", path: ["roles", String(index)])
            }
            guard seenRoles.insert(value).inserted else {
                throw ValidationError("A contributor role cannot be repeated", path: ["roles", String(index)])
            }
        }
        for (index, media) in (media ?? []).enumerated() {
            guard case .known(let media) = media else { continue }
            do {
                try media.validateForPublication()
            } catch let error as ValidationError {
                throw ValidationError(error.reason, path: ["media", String(index)] + error.path)
            }
        }
        _ = try encodeLexicon()
    }
}

extension Contributor {
    @Lexicon("com.atproto.repo.strongRef", description: "A URI with a content-hash fingerprint.")
    public struct Source: Equatable, Sendable {
        @LexiconField(description: "The AT Protocol record URI.")
        public var uri: ATProto.URI

        @LexiconField(description: "The content identifier of the exact record revision.")
        public var cid: ATProto.CID
    }

    @Lexicon("events.openmusic.defs#contributorRole", type: .string, description: "A known event-wide contribution category. Other string values may be used by extensions.")
    public enum Role: String, Equatable, Sendable {
        case performer
        case facilitator
        case organizer
        case sponsor
        case vendor
        case volunteer
        case staff
    }
}
