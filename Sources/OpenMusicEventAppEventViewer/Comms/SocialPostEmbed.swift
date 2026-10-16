import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventLexicon

enum SocialPostEmbedContent: Equatable, Sendable {
    case images([OME.Image])
    case external(SocialPostExternalCard)
    case record(String)
    case unsupported

    init(_ embed: Social.Post.Embed) {
        switch embed.object["$type"]?.string {
        case "app.bsky.embed.images":
            guard let imagesValue = embed.object["images"],
                  case let .array(entries) = imagesValue,
                  !entries.isEmpty else {
                self = .unsupported
                return
            }
            let images = entries.compactMap { entry -> OME.Image? in
                guard let object = entry.object,
                      let value = object["image"],
                      let blob = try? value.decoded(as: ATProto.Blob.self) else {
                    return nil
                }
                return OME.Image(
                    source: .known(.blob(blob)),
                    alt: object["alt"]?.string.map { OME.AltText(rawValue: $0) },
                    role: .known(.photo)
                )
            }
            self = images.count == entries.count ? .images(images) : .unsupported

        case "app.bsky.embed.external":
            if let card = SocialPostExternalCard(embed: embed) {
                self = .external(card)
            } else {
                self = .unsupported
            }

        case "app.bsky.embed.record", "app.bsky.embed.recordWithMedia":
            if let reference = SocialPostRecordEmbed(embed: embed) {
                self = .record(reference.reference.uri)
            } else {
                self = .unsupported
            }

        default:
            self = .unsupported
        }
    }
}

struct SocialPostStrongReference: Equatable, Sendable {
    var uri = ""
    var cid = ""

    init() {}

    init(_ source: Contributor.Source) {
        uri = source.uri.description
        cid = source.cid.rawValue
    }

    var source: Contributor.Source? {
        let uriText = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        let cidText = cid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uri = ATProto.URI(uriText),
              case .did = uri.authority,
              uri.collection != nil,
              uri.rkey != nil,
              !cidText.isEmpty else { return nil }
        return Contributor.Source(uri: uri, cid: ATProto.CID(rawValue: cidText))
    }
}

struct SocialPostRecordEmbed: Equatable, Sendable {
    var reference = SocialPostStrongReference()
    var original: [String: Lexicon.JSONValue]?

    init() {}

    init?(embed: Social.Post.Embed) {
        let object = embed.object
        let strongReference: [String: Lexicon.JSONValue]?
        switch object["$type"]?.string {
        case "app.bsky.embed.record":
            strongReference = object["record"]?.object
        case "app.bsky.embed.recordWithMedia":
            strongReference = object["record"]?.object?["record"]?.object
        default:
            return nil
        }
        guard let strongReference,
              let uri = strongReference["uri"]?.string,
              let cid = strongReference["cid"]?.string else { return nil }
        reference.uri = uri
        reference.cid = cid
        guard reference.source != nil else { return nil }
        original = object
    }

    var embed: Social.Post.Embed? {
        guard let source = reference.source else { return nil }
        let strongReference: Lexicon.JSONValue = .object([
            "uri": .string(source.uri.description),
            "cid": .string(source.cid.rawValue),
        ])
        var object = original ?? [:]
        if object["$type"]?.string == "app.bsky.embed.recordWithMedia" {
            var record = object["record"]?.object ?? [:]
            record["$type"] = "app.bsky.embed.record"
            record["record"] = strongReference
            object["record"] = .object(record)
        } else {
            object["$type"] = "app.bsky.embed.record"
            object["record"] = strongReference
        }
        return Social.Post.Embed(object)
    }
}

struct SocialPostExternalCard: Equatable, Sendable {
    var uri = ""
    var title = ""
    var summary = ""
    var original: [String: Lexicon.JSONValue]?

    init() {}

    init?(embed: Social.Post.Embed) {
        guard embed.object["$type"]?.string == "app.bsky.embed.external",
              let external = embed.object["external"]?.object else { return nil }
        self.uri = external["uri"]?.string ?? ""
        self.title = external["title"]?.string ?? ""
        self.summary = external["description"]?.string ?? ""
        self.original = embed.object
    }

    var url: URL? {
        let value = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }

    var isValid: Bool {
        url != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var thumbnail: OME.Image? {
        guard let value = original?["external"]?.object?["thumb"],
              let blob = try? value.decoded(as: ATProto.Blob.self) else { return nil }
        return OME.Image(source: .known(.blob(blob)), role: .known(.photo))
    }

    var embed: Social.Post.Embed? {
        guard isValid else { return nil }
        var object = original ?? [:]
        var external = object["external"]?.object ?? [:]
        external["uri"] = .string(uri.trimmingCharacters(in: .whitespacesAndNewlines))
        external["title"] = .string(title.trimmingCharacters(in: .whitespacesAndNewlines))
        external["description"] = .string(summary.trimmingCharacters(in: .whitespacesAndNewlines))
        object["$type"] = "app.bsky.embed.external"
        object["external"] = .object(external)
        return Social.Post.Embed(object)
    }
}
