import ATProto
import Foundation
import OpenMusicEventLexicon

public extension Event {
    /// Legacy values cross into canonical models only at source import.
    init(id: ATProto.URI, event: OME.Event, createdAt: ATProto.DateTime) throws {
        try self.init(id: id, name: event.name, createdAt: createdAt, timeZone: event.timeZone)
        description = event.description
        start = event.startDate.map { .known(.day(.init(value: $0))) }
        end = event.endDate.map { .known(.day(.init(value: $0))) }
        switch event.status {
        case .known(let status):
            self.status = .known(Status(rawValue: "community.lexicon.calendar.event#\(status.rawValue)")!)
        case .unknown(let value): self.status = .unknown(value)
        case nil: break
        }
        mode = try event.mode.map { try Lexicon.JSONValue(encoding: $0).decoded(as: Open<Mode>.self) }
        locations = try event.locations?.map { location in
            guard let name = location.address, !name.isEmpty else {
                throw ValidationError("A source location needs a name or address")
            }
            let locators: [Open<Locator>]? = location.coordinates.map {
                [.known(.geo(.init(latitude: String($0.latitude), longitude: String($0.longitude))))]
            }
            let links = [
                location.appleMapsLink.map { OME.Link(url: $0, title: "Apple Maps") },
                location.googleMapsLink.map { OME.Link(url: $0, title: "Google Maps") },
            ].compactMap { $0 }
            return Location(name: name, description: location.directions, locators: locators,
                            links: links.isEmpty ? nil : links)
        }
        var links = event.uris?.map { OME.Link(url: $0.uri, title: $0.name) } ?? []
        for contact in event.contactNumbers ?? [] {
            let number = contact.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !number.isEmpty else { throw ValidationError("Empty contact phone number") }
            var components = URLComponents()
            components.scheme = "tel"
            components.path = number
            guard let url = components.url else { throw ValidationError("Invalid contact phone number") }
            links.append(OME.Link(url: url, title: contact.title, description: contact.description,
                                  role: .known(.contact(.init()))))
        }
        links += event.reportingLinks?.map {
            OME.Link(url: $0.url, title: $0.name, description: $0.description, role: .known(.reporting(.init())))
        } ?? []
        self.links = links.isEmpty ? nil : links
        media = try event.images?.map { asset in
            let source: Open<OME.Image.Source>
            switch asset.source {
            case .blob(let blob): source = .known(.blob(blob))
            case .url(let url):
                guard url.scheme?.lowercased() == "https", url.host != nil else {
                    throw ValidationError("Import this local image through the Event image form before publishing")
                }
                source = .known(.url(url))
            }
            return .known(.image(OME.Image(
                source: source,
                role: .known(OME.Image.Role(rawValue: asset.role.rawValue)!),
                renderingMode: asset.renderKind == .transparent ? .known(.template) : .known(.original),
                appearance: asset.appearance.map { .known(OME.Image.Appearance(rawValue: $0.rawValue)!) },
                focalPoint: asset.focalPoint.map { .init(x: $0.x, y: $0.y) }
            )))
        }
        try validateReferences()
    }
}
