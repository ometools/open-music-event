import ATProto
import Foundation
import OpenMusicEventLexicon

public extension CanonicalWorkspaceRecordChange {
    struct Field: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let before: Value?
        public let after: Value?
    }

    struct Value: Equatable, Sendable {
        public var lines: [String] = []
        public var images: [OME.Image] = []

        init(_ value: Lexicon.JSONValue, timeZone: TimeZone?) throws {
            switch value {
            case .null:
                lines = ["Not set"]
            case .bool(let value):
                lines = [value ? "Yes" : "No"]
            case .integer(let value):
                lines = [String(value)]
            case .number(let value):
                lines = [String(describing: value)]
            case .string(let value):
                if value.hasPrefix("at://") { lines = ["Linked content"] }
                else if value.hasPrefix("did:") { lines = ["Account"] }
                else if value.hasPrefix("community.lexicon.calendar.event#") {
                    lines = [fieldTitle(String(value.split(separator: "#").last!))]
                } else { lines = [value.isEmpty ? "Not set" : value] }
            case .array(let values):
                for value in values {
                    let rendered = try Self(value, timeZone: timeZone)
                    lines += rendered.lines
                    images += rendered.images
                }
                if values.isEmpty { lines = ["None"] }
            case .object(let object):
                if object["$type"]?.string == "events.openmusic.defs#image" {
                    let image = try value.decoded(as: OME.Image.self)
                    images = [image]
                    if let title = image.title { lines.append(title) }
                    if let alt = image.alt { lines.append("Alt text: \(alt.rawValue)") }
                    if case let .known(role) = image.role { lines.append("Use: \(fieldTitle(role.rawValue))") }
                    for key in ["renderingMode", "appearance", "focalPoint"] {
                        if let metadata = object[key] {
                            lines += try Self(metadata, timeZone: timeZone).lines.map { "\(fieldTitle(key)): \($0)" }
                        }
                    }
                } else if object["$type"]?.string == "events.openmusic.defs#time",
                          let value = object["value"]?.string, let timeZone {
                    let date = try Date(value, strategy: Date.ISO8601FormatStyle(
                        includingFractionalSeconds: value.contains(".")
                    ))
                    lines = [date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened,
                        timeZone: timeZone)), timeZone.identifier]
                } else if object["$type"]?.string == "events.openmusic.defs#day" {
                    lines = [object["value"]?.string ?? "Not set"]
                } else {
                    for key in object.keys.sorted() where !technicalFields.contains(key) {
                        let rendered = try Self(object[key]!, timeZone: timeZone)
                        lines += rendered.lines.map { "\(fieldTitle(key)): \($0)" }
                        images += rendered.images
                    }
                    if lines.isEmpty && images.isEmpty { lines = ["Details changed"] }
                }
            }
        }
    }

    static let technicalFields: Set<String> = ["$type", "type", "id", "cid", "createdAt", "ref"]

    static func fieldTitle(_ key: String) -> String {
        switch key {
        case "start": return "Starts"
        case "end": return "Ends"
        case "media": return "Images and media"
        case "siteMap": return "Site map"
        case "rsvpExpected": return "RSVP requested"
        case "eventPlaces": return "Places"
        case "inperson": return "In person"
        case "url", "uri": return "Link"
        default:
            let words = key.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            return words.prefix(1).uppercased() + words.dropFirst()
        }
    }

    static func fields(before: Lexicon.JSONValue?, after: Lexicon.JSONValue?) throws -> [Field] {
        let old = before?.object ?? [:]
        let new = after?.object ?? [:]
        let oldZone = old["timeZone"]?.string.flatMap(TimeZone.init(identifier:))
        let newZone = new["timeZone"]?.string.flatMap(TimeZone.init(identifier:))
        return try Set(old.keys).union(new.keys).subtracting(technicalFields).sorted().compactMap { key in
            guard old[key] != new[key] else { return nil }
            return Field(
                id: key, title: fieldTitle(key),
                before: try old[key].map { try Value($0, timeZone: oldZone) },
                after: try new[key].map { try Value($0, timeZone: newZone) }
            )
        }
    }
}
