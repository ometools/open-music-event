import ATProto
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData
import Tagged

extension OpenMusicEvent {
    public enum AltTextTag {}
    public typealias AltText = Tagged<AltTextTag, String>

    // Deferred until ThumbHash is wired through the app.
    // public enum ThumbHashTag {}
    // public typealias ThumbHash = Tagged<ThumbHashTag, String>

    @Lexicon("events.openmusic.defs#image", description: "An image attached to an Open Music Event record.")
    public struct Image: Equatable, Sendable {
        @LexiconField(description: "The image content, provided as either a repository blob or a public HTTPS URL.")
        public var source: Open<Source>

        @LexiconField(description: "A short attendee-facing title for this image use, such as the name of a selectable map layer.", minLength: 1, maxLength: 5_000, maxGraphemes: 500)
        public var title: String? = nil

        @LexiconField(description: "A text alternative that conveys the image's meaningful content. An omitted value means no text alternative was supplied.", maxLength: 10_000, maxGraphemes: 1_000)
        public var alt: AltText? = nil

        @LexiconField(description: "The image's intended use in an event experience.")
        public var role: Open<Role>? = nil

        @LexiconField(required: false, default: "original", description: "How clients should render the image. Defaults to original when omitted.")
        public var renderingMode: Open<RenderingMode> = .known(.original)

        @LexiconField(description: "The interface appearance for which this image variant is intended.")
        public var appearance: Open<Appearance>? = nil

        @LexiconField(description: "The preferred focal point to preserve when the image is cropped.")
        public var focalPoint: FocalPoint? = nil

        // @LexiconField(description: "A ThumbHash placeholder encoded as a string.")
        // public var thumbhash: ThumbHash? = nil
    }
}

extension OpenMusicEvent.Image: LexiconValue {}

extension OpenMusicEvent.Image {
    public enum Role: RawRepresentable, Sendable, Equatable, CaseIterable, SQLiteType, LexiconOpenValue {
        case hero
        case logo
        case photo
        case icon(Icon)
        case siteMap
        case poster

        public typealias RawValue = String

        public init?(rawValue: String) {
            switch rawValue {
            case "hero": self = .hero
            case "logo": self = .logo
            case "photo": self = .photo
            case "icon": self = .icon(.init())
            case "siteMap": self = .siteMap
            case "poster": self = .poster
            default: return nil
            }
        }

        public var rawValue: String {
            switch self {
            case .hero: "hero"
            case .logo: "logo"
            case .photo: "photo"
            case .icon: "icon"
            case .siteMap: "siteMap"
            case .poster: "poster"
            }
        }

        public static var allCases: [Self] {
            [.hero, .logo, .photo, .icon(.init()), .siteMap, .poster]
        }

        public var iconMetadata: Icon? {
            guard case .icon(let icon) = self else { return nil }
            return icon
        }

        public func matches(_ role: Self) -> Bool {
            rawValue == role.rawValue
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            guard let role = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown local image role: \(rawValue)"
                )
            }
            self = role
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        public static var lexiconDefinition: Definition {
            get throws { Representation.lexiconDefinition }
        }

        public static var lexiconDependencies: [any NamedLexiconDefinition.Type] {
            Representation.lexiconDependencies
        }

        public static func decodeLexicon(_ value: Lexicon.JSONValue) throws -> Self {
            switch try Representation.decodeLexicon(value) {
            case .hero: .hero
            case .logo: .logo
            case .photo: .photo
            case .icon(let icon): .icon(icon)
            case .siteMap: .siteMap
            case .poster: .poster
            }
        }

        public func encodeLexicon() throws -> Lexicon.JSONValue {
            try representation.encodeLexicon()
        }

        public static func decodeOpen(from decoder: any Decoder) throws -> Open<Self> {
            switch try Open<Representation>(from: decoder) {
            case .known(.hero): .known(.hero)
            case .known(.logo): .known(.logo)
            case .known(.photo): .known(.photo)
            case .known(.icon(let icon)): .known(.icon(icon))
            case .known(.siteMap): .known(.siteMap)
            case .known(.poster): .known(.poster)
            case .unknown(let payload): .unknown(payload)
            }
        }

        public static func encodeOpen(_ value: Open<Self>, to encoder: any Encoder) throws {
            let representation: Open<Representation> = switch value {
            case .known(let role): .known(role.representation)
            case .unknown(let payload): .unknown(payload)
            }
            try representation.encode(to: encoder)
        }

        var representation: Representation {
            switch self {
            case .hero: .hero(.init())
            case .logo: .logo(.init())
            case .photo: .photo(.init())
            case .icon(let icon): .icon(icon)
            case .siteMap: .siteMap(.init())
            case .poster: .poster(.init())
            }
        }

        @LexiconUnion
        enum Representation: Equatable, Sendable {
            case hero(Hero)
            case logo(Logo)
            case photo(Photo)
            case icon(Icon)
            case siteMap(SiteMap)
            case poster(Poster)
        }

        @Lexicon("events.openmusic.defs#heroImage", description: "An image intended as the primary visual for its subject.")
        struct Hero: Equatable, Sendable {}

        @Lexicon("events.openmusic.defs#logoImage", description: "An image intended as its subject's logo or wordmark.")
        struct Logo: Equatable, Sendable {}

        @Lexicon("events.openmusic.defs#photoImage", description: "A photograph of its subject.")
        struct Photo: Equatable, Sendable {}

        @Lexicon("events.openmusic.defs#iconImage", description: "A compact image intended to represent its subject.")
        public struct Icon: Equatable, Sendable {
            public init(canRepresentSubjectWithoutLabel: Bool? = nil) {
                self.canRepresentSubjectWithoutLabel = canRepresentSubjectWithoutLabel
            }

            @LexiconField(description: "Whether a client may use this rendered icon without adjacent visible subject-name text. Missing or false means the visible name remains present.")
            public var canRepresentSubjectWithoutLabel: Bool? = nil
        }

        @Lexicon("events.openmusic.defs#siteMapImage", description: "An image intended as a site-map base layer.")
        struct SiteMap: Equatable, Sendable {}

        @Lexicon("events.openmusic.defs#posterImage", description: "An image intended as a promotional poster.")
        struct Poster: Equatable, Sendable {}
    }

    @Lexicon("events.openmusic.defs#imageAppearance", type: .string, description: "A known interface appearance for an image variant. Other string values may be used by extensions.")
    public enum Appearance: String, Sendable, Equatable, CaseIterable, SQLiteType {
        case light, dark
    }

    @Lexicon("events.openmusic.defs#imageRenderingMode", type: .string, description: "A known way to render an image. Original preserves its colors; template allows a client to apply its own color. Other string values may be used by extensions.")
    public enum RenderingMode: String, Equatable, Sendable {
        case template
        case original
    }

    @Lexicon("events.openmusic.defs#focalPoint", description: "A whole-percentage point in the source image, measured from its top-left before orientation correction.")
    public struct FocalPoint: Equatable, Sendable {
        @LexiconField(encoding: Percentage.self, description: "The horizontal percentage from the source image's left edge.", minimum: 0, maximum: 100)
        public var x: Double

        @LexiconField(encoding: Percentage.self, description: "The vertical percentage from the source image's top edge.", minimum: 0, maximum: 100)
        public var y: Double

        public enum Percentage: LexiconFieldEncoding {
            public static func encode(_ value: Double) throws -> Int {
                guard value.isFinite, (0...1).contains(value) else {
                    throw ValidationError("Expected a normalized focal-point coordinate")
                }
                return Int((value * 100).rounded())
            }

            public static func decode(_ value: Int) throws -> Double {
                guard (0...100).contains(value) else {
                    throw ValidationError("Expected a focal-point percentage from 0 through 100")
                }
                return Double(value) / 100
            }
        }
    }
}

extension OME.Image {
    public enum Source: Equatable, Sendable, LexiconOpenValue {
        case blob(ATProto.Blob)
        case url(URL)

        public static var lexiconDefinition: Definition { get throws { try Representation.lexiconDefinition } }
        public static var lexiconDependencies: [any NamedLexiconDefinition.Type] { Representation.lexiconDependencies }

        public init(from decoder: any Decoder) throws {
            switch try Representation(from: decoder) {
            case .blob(let source): self = .blob(source.blob)
            case .url(let source): self = .url(source.url)
            }
        }
        public func encode(to encoder: any Encoder) throws {
            let representation: Representation = switch self {
            case .blob(let blob): .blob(.init(blob: blob))
            case .url(let url): .url(.init(url: url))
            }
            try representation.encode(to: encoder)
        }

        public static func decodeOpen(from decoder: any Decoder) throws -> Open<Self> {
            switch try Open<Representation>(from: decoder) {
            case .known(.blob(let source)): .known(.blob(source.blob))
            case .known(.url(let source)): .known(.url(source.url))
            case .unknown(let payload): .unknown(payload)
            }
        }

        public static func encodeOpen(_ value: Open<Self>, to encoder: any Encoder) throws {
            let representation: Open<Representation> = switch value {
            case .known(.blob(let blob)): .known(.blob(.init(blob: blob)))
            case .known(.url(let url)): .known(.url(.init(url: url)))
            case .unknown(let payload): .unknown(payload)
            }
            try representation.encode(to: encoder)
        }

        @LexiconUnion
        enum Representation: Equatable, Sendable {
            case blob(Blob)
            case url(Link)
        }
        @Lexicon("events.openmusic.defs#imageBlob", description: "Image content stored as a blob in the repository that contains the referencing record.")
        struct Blob: Equatable, Sendable {
            @LexiconField(description: "A JPEG or PNG image blob.", accept: ["image/jpeg", "image/png"], maxSize: 50_000_000)
            var blob: ATProto.Blob
        }
        @Lexicon("events.openmusic.defs#imageURL", description: "Image content hosted at a public HTTPS URL.")
        struct Link: Equatable, Sendable {
            @LexiconField(encoding: URLString.self, description: "The public HTTPS URL from which the image can be retrieved.", format: "uri")
            var url: URL
        }
        enum URLString: LexiconFieldEncoding {
            static func encode(_ value: URL) -> String { value.absoluteString }
            static func decode(_ value: String) throws -> URL {
                guard let url = URL(string: value) else { throw ValidationError("Invalid image URL") }
                return url
            }
        }
    }

    public func validateForPublication() throws {
        if case .known(.url(let url)) = source {
            guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else {
                throw ValidationError("Public image URLs must use HTTPS", path: ["source"])
            }
        }
        _ = try encodeLexicon()
    }
}
