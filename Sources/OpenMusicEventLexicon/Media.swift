import ATProto
import Foundation
import ATProtoTypes
import ATProtoSQLite

extension OME {
    @LexiconUnion
    public enum Media: Equatable, Sendable {
        case image(Image)
        case record(RecordReference)
        case external(External)
    }
}

extension OME.Media {
    @Lexicon("events.openmusic.defs#mediaRecord", description: "A live reference to an independently published AT Protocol media record. The record keeps its own identity, lifecycle, and social activity.")
    public struct RecordReference: Equatable, Sendable {
        @LexiconField(description: "The DID-based URI of the referenced media record. This is a live identity reference rather than a CID-pinned revision.")
        public var uri: ATProto.URI
    }

    @Lexicon("events.openmusic.defs#externalMedia", description: "Media hosted outside AT Protocol, represented as a portable link card without a closed provider list.")
    public struct External: Equatable, Sendable {
        @LexiconField(encoding: URLString.self, description: "The public HTTPS URL of the external media.", format: "uri")
        public var uri: URL

        @LexiconField(description: "A short human-readable title for the linked media.", minLength: 1, maxLength: 5_000, maxGraphemes: 500)
        public var title: String? = nil

        @LexiconField(description: "Additional human-readable context about the linked media.", maxLength: 30_000, maxGraphemes: 3_000)
        public var description: String? = nil

        @LexiconField(description: "An image used to preview the linked media.")
        public var thumbnail: OME.Image? = nil

        @LexiconField(description: "The kind of media at the external URL.")
        public var mediaKind: Open<Kind>? = nil

        public enum URLString: LexiconFieldEncoding {
            public static func encode(_ value: URL) -> String { value.absoluteString }
            public static func decode(_ value: String) throws -> URL {
                guard let url = URL(string: value) else { throw ValidationError("Invalid external media URL") }
                return url
            }
        }
    }

    @Lexicon("events.openmusic.defs#mediaKind", type: .string, description: "A known external media kind. Other string values may be used by extensions.")
    public enum Kind: String, Equatable, Sendable {
        case audio
        case video
        case livestream
        case playlist
        case document
    }

    public func validateForPublication() throws {
        switch self {
        case .image(let image):
            try image.validateForPublication()
        case .record(let reference):
            guard case .did = reference.uri.authority,
                  reference.uri.collection != nil,
                  reference.uri.rkey != nil
            else {
                throw ValidationError("Media record references require a DID, collection, and record key", path: ["uri"])
            }
        case .external(let external):
            guard external.uri.scheme?.lowercased() == "https",
                  let host = external.uri.host,
                  !host.isEmpty
            else {
                throw ValidationError("External media URLs must use HTTPS", path: ["uri"])
            }
            try external.thumbnail?.validateForPublication()
        }
        _ = try encodeLexicon()
    }
}
