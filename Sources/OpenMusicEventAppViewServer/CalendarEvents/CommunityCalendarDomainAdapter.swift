import ATProto
import ATProtoAppView
import Foundation
import OpenMusicEventLexicon

enum CommunityCalendarDomainAdapter {
    static let version = 1
    static let collection = "community.lexicon.calendar.event"

    struct Diagnostic: Codable, Equatable, Sendable {
        var path: String
        var message: String
    }

    struct Projection {
        var event: Event
        var diagnostics: [Diagnostic]
    }

    static func project(_ source: AppView.RecordVersion<Data>) throws -> Projection {
        guard source.collection.rawValue == collection,
              source.uri.collection?.rawValue == collection else {
            throw ValidationError("Unexpected Community Calendar source collection")
        }
        let raw = try JSONDecoder().decode(Lexicon.JSONValue.self, from: source.value)
        guard let object = raw.object, object["$type"]?.string == collection else {
            throw ValidationError("Expected a Community Calendar event object")
        }
        guard let name = object["name"]?.string, let createdAt = object["createdAt"]?.string else {
            throw ValidationError("name and createdAt must be strings")
        }
        var event = try Event(projecting: source.uri, cid: source.cid,
            projectionVersion: version, name: name, createdAt: ATProto.DateTime(rawValue: createdAt))
        var diagnostics: [Diagnostic] = []

        func optional<T>(_ key: String, _ transform: (Lexicon.JSONValue) throws -> T) -> T? {
            guard let value = object[key], value != .null else { return nil }
            do { return try transform(value) }
            catch { diagnostics.append(.init(path: key, message: String(describing: error))); return nil }
        }
        func boundary(_ value: Lexicon.JSONValue) throws -> Open<Event.Time> {
            let timestamp = try ATProto.DateTime.decodeLexicon(value)
            try StringFormat.validate(timestamp.rawValue, format: "datetime")
            return .known(.time(.init(value: timestamp)))
        }
        event.description = optional("description") {
            try Event.validateDomainField($0, named: "description")
            return try String.decodeLexicon($0)
        }
        event.start = optional("startsAt", boundary)
        event.end = optional("endsAt", boundary)
        event.status = optional("status") { try Open<Event.Status>.decodeLexicon($0) }
        event.mode = optional("mode") { try Open<Event.Mode>.decodeLexicon($0) }

        func array<T>(_ key: String, _ transform: (Lexicon.JSONValue) throws -> T) -> [T]? {
            optional(key) { value in
                guard case let .array(items) = value else { throw ValidationError("Expected an array") }
                var projected: [T] = []
                for (index, item) in items.enumerated() {
                    do { projected.append(try transform(item)) }
                    catch { diagnostics.append(.init(path: "\(key)[\(index)]", message: String(describing: error))) }
                }
                return projected
            }
        }
        event.locations = array("locations") { value in
            guard let location = value.object else { throw ValidationError("Expected a location object") }
            let name = try location["name"].flatMap { $0 == .null ? nil : try String.decodeLexicon($0) }
            let result: Event.Location
            if location["$type"]?.string == "community.lexicon.calendar.event#uri" {
                guard let text = location["uri"]?.string, let url = URL(string: text) else {
                    throw ValidationError("Location URI cannot be represented by OME.Link; retained in raw record")
                }
                result = .init(name: name, links: [.init(url: url)])
            } else {
                let locator = try Open<Event.Locator>.decodeLexicon(value)
                if case .unknown = locator {
                    diagnostics.append(.init(path: "locations", message: "Unrecognized locator retained as an open-union value"))
                }
                result = .init(name: name, locators: [locator])
            }
            _ = try result.encodeLexicon()
            return result
        }
        event.links = array("uris") { value in
            guard let item = value.object, let text = item["uri"]?.string,
                  let url = URL(string: text) else {
                throw ValidationError("Event URI cannot be represented by OME.Link; retained in raw record")
            }
            let title = try item["name"].flatMap { $0 == .null ? nil : try String.decodeLexicon($0) }
            let link = OME.Link(url: url, title: title)
            _ = try link.encodeLexicon()
            return link
        }
        var media: [Open<OME.Media>] = []
        if let poster: OME.Image = optional("poster", { value in
            guard let item = value.object, let text = item["url"]?.string,
                  let url = CommunityCalendarEventProjection.webImageURL(text) else {
                throw ValidationError("Poster must have a public HTTPS image URL")
            }
            return .init(source: .known(.url(url)), role: .known(.poster))
        }) { media.append(.known(.image(poster))) }
        let images: [Open<OME.Media>]? = array("media") { value in
            guard let item = value.object, let content = item["content"] else {
                throw ValidationError("Unsupported media shape; retained in raw record")
            }
            let blob = try content.decoded(as: ATProto.Blob.self)
            guard ["image/jpeg", "image/png", "image/webp", "image/gif", "image/avif"].contains(blob.mimeType) else {
                throw ValidationError("Unsupported non-image blob; retained in raw record")
            }
            let role = try item["role"].map { try Open<OME.Image.Role>.decodeLexicon($0) }
            let alt = try item["alt"].map { try OME.AltText.decodeLexicon($0) }
            let image = OME.Image(source: .known(.blob(blob)), alt: alt, role: role)
            _ = try image.encodeLexicon()
            return .known(.image(image))
        }
        media += images ?? []
        event.media = media.isEmpty ? nil : media
        let supported: Set<String> = ["$type", "name", "createdAt", "description", "startsAt", "endsAt",
                                      "status", "mode", "locations", "uris", "poster", "media"]
        for key in object.keys.sorted() where !supported.contains(key) {
            diagnostics.append(.init(path: key, message: "Unsupported source field retained in raw record"))
        }
        _ = try event.domainContent()
        return .init(event: event, diagnostics: diagnostics)
    }
}
