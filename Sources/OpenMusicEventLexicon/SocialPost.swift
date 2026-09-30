import ATProto
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData

public enum Social {}

extension Social {
    @Table("social.ome.post")
    @Lexicon("social.ome.post", type: .record(key: .tid), description: "An account-authored public post that may be associated with an Open Music Event and directed to an organizer-defined category.")
    public struct Post: RecordCodable, Equatable {
        @LexiconIgnored
        @Column(primaryKey: true)
        public let id: ATProto.URI

        @LexiconIgnored
        public var cid: ATProto.CID? = nil

        @LexiconField(description: "An optional display title for clients that support titled posts.", minLength: 1, maxLength: 5_000, maxGraphemes: 500)
        public var title: String? = nil

        @LexiconField(description: "The post's primary text. It may be empty when the post has an embed.", maxLength: 100_000, maxGraphemes: 10_000)
        public var text: String

        @LexiconField(description: "Annotations of the post text using app.bsky.richtext.facet byte ranges and features.")
        @Column(as: [Facet].JSONRepresentation?.self)
        public var facets: [Facet]? = nil

        @LexiconField(description: "Media, an external card, or a referenced AT Protocol record using the app.bsky post embed union.")
        @Column(as: Embed.JSONRepresentation?.self)
        public var embed: Embed? = nil

        @LexiconField(description: "The optional DID-based events.openmusic.event record this post concerns.")
        public var event: Event.ID? = nil

        @LexiconField(description: "An optional DID-based social.ome.category record that directs this post within its event.")
        public var category: ATProto.URI? = nil

        @LexiconField(description: "Pinned references to equivalent records syndicated from this post.", minLength: 1)
        @Column(as: [Contributor.Source].JSONRepresentation?.self)
        public var syndications: [Contributor.Source]? = nil

        @LexiconField(description: "Client-declared timestamp when this post was originally created.")
        public var createdAt: ATProto.DateTime

        @LexiconField(description: "Client-declared timestamp when this post was most recently updated.")
        public var updatedAt: ATProto.DateTime? = nil

        @LexiconField(description: "The author's requested notification delivery behavior. Omitted means unspecified. This is intent, not delivery authorization; clients verify the event and category authority before sending notifications.")
        public var delivery: Open<Delivery>? = nil

        public func validateReferences() throws {
            try LexiconCoding.validateRecordURI(id, type: Self.self)
            if let event {
                try LexiconCoding.validateRecordURI(event, type: Event.self)
            }
            if let category {
                guard let event else {
                    throw ValidationError("A post category requires an event", path: ["category"])
                }
                try LexiconCoding.validateRecordURI(category, type: Social.Category.self)
                guard category.authority == event.authority else {
                    throw ValidationError("A post category must be published in its event's repository", path: ["category"])
                }
            }
            if delivery == .known(.emergency) {
                guard let event, id.authority == event.authority else {
                    throw ValidationError("Emergency delivery requires an event-organizer-authored post", path: ["delivery"])
                }
            }
            guard !text.isEmpty || embed != nil else {
                throw ValidationError("A post requires text or an embed", path: ["text"])
            }
            var syndicatedRecords: Set<ATProto.URI> = []
            for (index, syndication) in (syndications ?? []).enumerated() {
                guard case .did = syndication.uri.authority,
                      syndication.uri.collection != nil,
                      syndication.uri.rkey != nil
                else {
                    throw ValidationError("A syndication requires a complete DID-authored record URI", path: ["syndications", String(index), "uri"])
                }
                guard syndicatedRecords.insert(syndication.uri).inserted else {
                    throw ValidationError("A syndicated record cannot be repeated", path: ["syndications", String(index), "uri"])
                }
            }
            _ = try encodeLexicon()
        }

        public func validateGraph(event: Event, category: Social.Category? = nil) throws {
            try validateReferences()
            try event.validateReferences()
            guard self.event == event.id else {
                throw ValidationError("The post must identify the supplied event", path: ["event"])
            }
            if let categoryURI = self.category {
                guard let category, category.id == categoryURI else {
                    throw ValidationError("The post category must be resolved", path: ["category"])
                }
                try category.validateGraph(event: event)
            } else if category != nil {
                throw ValidationError("The post does not reference the supplied category", path: ["category"])
            }
        }
    }
}

extension Social.Post {
    @Lexicon("social.ome.defs#delivery", type: .string, description: "A known post delivery preference. Silent does not request a notification; standard requests ordinary delivery; emergency requests time-sensitive organizer delivery. Unknown values do not imply emergency authority.")
    public enum Delivery: String, Equatable, Sendable {
        case silent
        case standard
        case emergency
    }
}

extension Social.Post {
    public struct Facet: NamedLexiconValue, ExternalLexiconDefinition, Equatable, Sendable {
        public static let lexiconID: Lexicon.ID = "app.bsky.richtext.facet"
        public static var lexiconDefinition: Definition { .object(.init(properties: [:])) }
        public static var lexiconDependencies: [any NamedLexiconDefinition.Type] { [] }

        public var object: [String: Lexicon.JSONValue]

        public init(_ object: [String: Lexicon.JSONValue]) {
            self.object = object
        }

        public init(from decoder: any Decoder) throws {
            let value = try Lexicon.JSONValue(from: decoder)
            try SchemaValidator(direction: .decoding).validate(value, against: Self.lexiconDefinition, id: Self.lexiconID)
            guard let object = value.object else { throw ValidationError("Expected object") }
            self.object = object
        }

        public func encode(to encoder: any Encoder) throws {
            let value = Lexicon.JSONValue.object(object)
            try SchemaValidator().validate(value, against: Self.lexiconDefinition, id: Self.lexiconID)
            try value.encode(to: encoder)
        }
    }

    public struct Embed: LexiconValue, Equatable, Sendable {
        public static var lexiconDefinition: Definition {
            .union(.init(refs: lexiconDependencies.map { .absolute($0.lexiconID) }))
        }
        public static var lexiconDependencies: [any NamedLexiconDefinition.Type] {
            [
                BlueskyImages.self,
                BlueskyVideo.self,
                BlueskyGallery.self,
                BlueskyExternal.self,
                BlueskyRecord.self,
                BlueskyRecordWithMedia.self,
            ]
        }

        public var object: [String: Lexicon.JSONValue]

        public init(_ object: [String: Lexicon.JSONValue]) {
            self.object = object
        }

        public init(from decoder: any Decoder) throws {
            let value = try Lexicon.JSONValue(from: decoder)
            let definitions = try LexiconExporter.validationDefinitions(for: Self.lexiconDependencies)
            try SchemaValidator(definitions: definitions, direction: .decoding).validate(value, against: Self.lexiconDefinition, id: "")
            guard let object = value.object else { throw ValidationError("Expected object") }
            self.object = object
        }

        public func encode(to encoder: any Encoder) throws {
            let value = Lexicon.JSONValue.object(object)
            let definitions = try LexiconExporter.validationDefinitions(for: Self.lexiconDependencies)
            try SchemaValidator(definitions: definitions).validate(value, against: Self.lexiconDefinition, id: "")
            try value.encode(to: encoder)
        }
    }
}

private enum BlueskyImages: ExternalLexiconDefinition {
    static let lexiconID: Lexicon.ID = "app.bsky.embed.images"
    static var lexiconDefinition: Definition { .object(.init(properties: [:])) }
    static var lexiconDependencies: [any NamedLexiconDefinition.Type] { [] }
}

private enum BlueskyVideo: ExternalLexiconDefinition {
    static let lexiconID: Lexicon.ID = "app.bsky.embed.video"
    static var lexiconDefinition: Definition { .object(.init(properties: [:])) }
    static var lexiconDependencies: [any NamedLexiconDefinition.Type] { [] }
}

private enum BlueskyGallery: ExternalLexiconDefinition {
    static let lexiconID: Lexicon.ID = "app.bsky.embed.gallery"
    static var lexiconDefinition: Definition { .object(.init(properties: [:])) }
    static var lexiconDependencies: [any NamedLexiconDefinition.Type] { [] }
}

private enum BlueskyExternal: ExternalLexiconDefinition {
    static let lexiconID: Lexicon.ID = "app.bsky.embed.external"
    static var lexiconDefinition: Definition { .object(.init(properties: [:])) }
    static var lexiconDependencies: [any NamedLexiconDefinition.Type] { [] }
}

private enum BlueskyRecord: ExternalLexiconDefinition {
    static let lexiconID: Lexicon.ID = "app.bsky.embed.record"
    static var lexiconDefinition: Definition { .object(.init(properties: [:])) }
    static var lexiconDependencies: [any NamedLexiconDefinition.Type] { [] }
}

private enum BlueskyRecordWithMedia: ExternalLexiconDefinition {
    static let lexiconID: Lexicon.ID = "app.bsky.embed.recordWithMedia"
    static var lexiconDefinition: Definition { .object(.init(properties: [:])) }
    static var lexiconDependencies: [any NamedLexiconDefinition.Type] { [] }
}
