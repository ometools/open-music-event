import ATProto
import Foundation
import OpenMusicEventLexicon

enum BundledCalendarEventCatalog {
    static func event(
        uri: ATProto.URI,
        appViewHost: ATProto.PDSHost
    ) throws -> OME.CalendarEvent? {
        try events(appViewHost: appViewHost).first { $0.uri == uri }
    }

    static func events(appViewHost: ATProto.PDSHost) throws -> [OME.CalendarEvent] {
        guard let resourceURL = Bundle.module.url(
            forResource: "TemporaryOMEBrowseCatalog",
            withExtension: "json"
        ) else {
            throw BundledCalendarEventCatalogError.missingResource
        }

        return try JSONDecoder()
            .decode([BundledCalendarEvent].self, from: Data(contentsOf: resourceURL))
            .map { try $0.baseCalendarEvent(appViewHost: appViewHost) }
    }
}

enum BundledCalendarEventCatalogError: Error, Equatable {
    case invalidOrganizerID(String)
    case invalidTimeZone(String)
    case missingResource
}

private struct BundledCalendarEvent: Decodable {
    var description: String?
    var endDate: LocalDate
    var eventID: String
    var location: String?
    var media: [Media]
    var mode: Mode?
    var name: String
    var organizerAvatarURL: URL?
    var organizerID: String
    var organizerName: String
    var source: OME.SourceRecord?
    var startDate: LocalDate
    var status: OME.Event.Status?
    var timeZone: String

    func baseCalendarEvent(
        appViewHost: ATProto.PDSHost
    ) throws -> OME.CalendarEvent {
        guard let organizerID = DID(organizerID) else {
            throw BundledCalendarEventCatalogError.invalidOrganizerID(organizerID)
        }
        guard let timeZone = TimeZone(identifier: timeZone) else {
            throw BundledCalendarEventCatalogError.invalidTimeZone(self.timeZone)
        }

        let id = OME.Event.ID(
            organizerID: organizerID,
            eventID: OME.ID<OME.Event>(.init(eventID))
        )
        let images = media.map(\.imageAsset)
        let eventDraft = OME.Event.Draft(
            id: id,
            name: name,
            description: description,
            startDate: startDate,
            endDate: endDate,
            status: status.map { .known($0) },
            mode: mode.map { .known($0.eventMode) },
            locations: location.map { [OME.Event.Location(address: $0)] },
            uris: nil,
            timeZone: timeZone,
            images: images,
            contactNumbers: nil,
            categoryConfigs: nil,
            reportingLinks: nil,
            owner: nil
        )
        let event = try JSONDecoder().decode(
            OME.Event.self,
            from: JSONEncoder().encode(eventDraft)
        )

        return OME.CalendarEvent(
            uri: OME.Event.reference(id: id).uri,
            name: name,
            description: description,
            startsAt: startDate.atStartOfDay(in: timeZone),
            endsAt: endDate.at(hour: 23, minute: 59, second: 59, in: timeZone),
            status: status.map(\.calendarEventStatus),
            mode: mode.map(\.calendarEventMode),
            locations: location.map { [OME.CalendarEvent.Location(name: $0)] } ?? [],
            media: media.map(\.calendarEventMedia),
            organizer: OME.CalendarEvent.Organizer(
                id: organizerID,
                displayName: organizerName,
                avatarURL: organizerAvatarURL
            ),
            source: OME.CalendarEvent.Source(
                collection: OME.Event.nsid,
                appViewHost: appViewHost,
                sourceRecord: source
            ),
            timeZoneIdentifier: timeZone.identifier,
            event: event
        )
    }

    struct Media: Decodable {
        var alt: String?
        var role: OME.ImageAsset.Role
        var url: URL

        var calendarEventMedia: OME.CalendarEvent.Media {
            OME.CalendarEvent.Media(url: url, alt: alt, role: role.rawValue)
        }

        var imageAsset: OME.ImageAsset {
            OME.ImageAsset(
                source: .url(url),
                role: role,
                renderKind: role == .icon || role == .logo ? .transparent : .fullImage,
                materializationPolicy: .lazy
            )
        }
    }

    enum Mode: String, Decodable {
        case hybrid
        case inPerson
        case virtual

        var calendarEventMode: OME.CalendarEvent.Mode {
            switch self {
            case .hybrid: .hybrid
            case .inPerson: .inPerson
            case .virtual: .virtual
            }
        }

        var eventMode: OME.Event.Mode {
            switch self {
            case .hybrid: .hybrid
            case .inPerson: .inPerson
            case .virtual: .virtual
            }
        }
    }
}

private extension OME.Event.Status {
    var calendarEventStatus: OME.CalendarEvent.Status {
        switch self {
        case .cancelled: .cancelled
        case .planned: .planned
        case .postponed: .postponed
        case .rescheduled: .rescheduled
        case .scheduled: .scheduled
        }
    }
}
