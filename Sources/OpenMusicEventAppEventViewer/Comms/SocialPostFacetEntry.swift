import ATProto
import ATProtoTypes
import Dependencies
import Foundation
import OpenMusicEventLexicon

public struct SocialPostFacetEntry: Equatable, Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Equatable, Sendable {
        case link
        case mention
        case tag

        var title: String {
            switch self {
            case .link: "Link"
            case .mention: "Mention"
            case .tag: "Tag"
            }
        }

        var targetTitle: String {
            switch self {
            case .link: "Destination URL"
            case .mention: "Account DID"
            case .tag: "Hashtag"
            }
        }

        var lexiconType: String { "app.bsky.richtext.facet#\(rawValue)" }

        var targetKey: String {
            switch self {
            case .link: "uri"
            case .mention: "did"
            case .tag: "tag"
            }
        }
    }

    init(kind: Kind) {
        @Dependency(\.uuid) var uuid
        self.id = uuid()
        self.kind = kind
        self.selectedText = ""
        self.target = ""
        self.occurrence = 0
        self.original = nil
        self.isSupported = true
    }

    init(facet: Social.Post.Facet, in text: String) {
        @Dependency(\.uuid) var uuid
        self.id = uuid()
        self.original = facet
        self.kind = .link
        self.selectedText = ""
        self.target = ""
        self.occurrence = 0
        self.isSupported = false

        guard let index = facet.object["index"]?.object,
              let byteStart = index["byteStart"]?.integer,
              let byteEnd = index["byteEnd"]?.integer,
              byteStart >= 0, byteEnd > byteStart,
              byteEnd <= Int64(text.utf8.count),
              let selectedText = String(
                bytes: Array(text.utf8)[Int(byteStart)..<Int(byteEnd)],
                encoding: .utf8
              ),
              case let .some(.array(features)) = facet.object["features"],
              features.count == 1,
              let feature = features.first?.object,
              let type = feature["$type"]?.string,
              let kind = Kind.allCases.first(where: { $0.lexiconType == type }),
              let target = feature[kind.targetKey]?.string,
              let occurrence = Self.ranges(of: selectedText, in: text).firstIndex(where: {
                  Self.byteOffset(of: $0.lowerBound, in: text) == byteStart
              }) else { return }

        self.kind = kind
        self.selectedText = selectedText
        self.target = target
        self.occurrence = occurrence
        self.isSupported = true
    }

    public let id: UUID
    var kind: Kind
    var selectedText: String
    var target: String
    var occurrence: Int
    let original: Social.Post.Facet?
    private(set) var isSupported: Bool

    func occurrenceCount(in text: String) -> Int {
        Self.ranges(of: selectedText, in: text).count
    }

    func validationMessage(in text: String, originalText: String?) -> String? {
        guard isSupported else {
            return text == originalText ? nil
                : "Remove this unsupported annotation before changing the post text."
        }
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Enter the exact text to annotate."
        }
        let target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .link:
            guard let url = URL(string: target), url.scheme != nil else {
                return "Enter a complete destination URL."
            }
        case .mention:
            guard DID(target) != nil else { return "Enter the account's DID." }
        case .tag:
            guard !target.isEmpty, !target.hasPrefix("#"),
                  target.utf8.count <= 640, target.count <= 64 else {
                return "Enter a hashtag without #, up to 64 characters."
            }
        }
        guard Self.ranges(of: selectedText, in: text).indices.contains(occurrence) else {
            return "That text occurrence is not in the post."
        }
        return nil
    }

    func preparedFacet(in text: String, originalText: String?) throws -> Social.Post.Facet {
        guard validationMessage(in: text, originalText: originalText) == nil else {
            throw ValidationError("Invalid post annotation")
        }
        guard isSupported else { return original! }
        let range = Self.ranges(of: selectedText, in: text)[occurrence]
        let byteStart = Self.byteOffset(of: range.lowerBound, in: text)
        let byteEnd = Self.byteOffset(of: range.upperBound, in: text)
        var object = original?.object ?? [:]
        object["index"] = .object([
            "byteStart": .integer(byteStart),
            "byteEnd": .integer(byteEnd),
        ])
        var feature: [String: Lexicon.JSONValue] = [:]
        if case let .some(.array(features)) = original?.object["features"],
           let previous = features.first?.object,
           previous["$type"]?.string == kind.lexiconType {
            feature = previous
        }
        feature["$type"] = .string(kind.lexiconType)
        feature[kind.targetKey] = .string(target.trimmingCharacters(in: .whitespacesAndNewlines))
        object["features"] = .array([.object(feature)])
        return Social.Post.Facet(object)
    }

    private static func byteOffset(of index: String.Index, in text: String) -> Int64 {
        Int64(text.utf8.distance(from: text.startIndex, to: index))
    }

    private static func ranges(of phrase: String, in text: String) -> [Range<String.Index>] {
        guard !phrase.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex,
              let range = text.range(of: phrase, options: .literal, range: start..<text.endIndex) {
            ranges.append(range)
            start = range.upperBound
        }
        return ranges
    }
}
