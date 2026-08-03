import ATProto
import ComposableCalendarEvents
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData

extension CalendarEventsClient {
    static func openMusicEventAndAtmo(database: any DatabaseWriter) -> Self {
        let atmo = Self.atmoRSVP
        return Self(
            browse: { request in
                guard request.collection == OME.Event.nsid else {
                    return try await atmo.browse(request)
                }
                let installedEvents = try await database.read { db in
                    let events = try OME.Event
                        .order { ($0.startDate.asc(), $0.name) }
                        .fetchAll(db)
                    let posters = try OME.Poster.fetchAll(db)
                    let postersByEventID = Dictionary(grouping: posters) { poster in
                        OME.Event.ID(
                            organizerID: poster.id.organizerID,
                            eventID: poster.id.eventID
                        )
                    }
                    return events.map { event in
                        event.calendarEvent(posters: postersByEventID[event.id] ?? [])
                    }
                }
                var eventsByURI = Dictionary(
                    uniqueKeysWithValues: try Self.temporaryOpenMusicEvents().map {
                        ($0.uri, $0)
                    }
                )
                for event in installedEvents {
                    eventsByURI[event.uri] = event
                }
                return CalendarEvent.Page(
                    events: Array(
                        eventsByURI.values
                            .sorted(by: CalendarEvent.isSooner)
                            .prefix(request.limit)
                    )
                )
            },
            event: { uri in
                guard uri.collection == OME.Event.nsid else {
                    return try await atmo.event(uri)
                }
                guard let eventID = OME.Event.ID(uri) else {
                    throw CalendarEventsClientError.invalidEventURI(uri.description)
                }
                if let event = try await database.read({ db -> CalendarEvent? in
                    guard let event = try OME.Event.find(eventID).fetchOne(db) else {
                        return nil
                    }
                    let posters = try OME.Poster
                        .where { $0.id.organizerID.eq(eventID.organizerID) }
                        .where { $0.id.eventID.eq(eventID.eventID) }
                        .fetchAll(db)
                    return event.calendarEvent(posters: posters)
                }) {
                    return event
                }
                guard let event = try Self.temporaryOpenMusicEvents().first(where: {
                    $0.uri == uri
                }) else {
                    throw CalendarEventsClientError.missingEventRecord
                }
                return event
            },
            organizer: { organizerID in
                if let organizer = try Self.temporaryOpenMusicEvents()
                    .first(where: { $0.organizer.id == organizerID })?
                    .organizer {
                    return organizer
                }
                return CalendarEvent.Organizer(id: organizerID)
            }
        )
    }

    static func temporaryOpenMusicEvents() throws -> [CalendarEvent] {
        try temporaryOpenMusicEventRecords().map { try $0.calendarEvent }
    }

    static func temporaryOpenMusicEventRecords() throws -> [TemporaryOMEBrowseEvent] {
        guard let resourceURL = Bundle.module.url(
            forResource: "TemporaryOMEBrowseCatalog",
            withExtension: "json"
        ) else {
            throw TemporaryOMEBrowseCatalogError.missingResource
        }
        return try JSONDecoder()
            .decode([TemporaryOMEBrowseEvent].self, from: Data(contentsOf: resourceURL))
    }
}

enum TemporaryOMEBrowseCatalogError: Error, Equatable {
    case invalidOrganizerID(String)
    case invalidTimeZone(String)
    case invalidURI(String)
    case missingResource
}

struct TemporaryOMEBrowseEvent: Decodable {
    var description: String?
    var endDate: LocalDate
    var eventID: String
    var location: String?
    var media: [Media]
    var mode: Mode
    var name: String
    var organizerID: String
    var organizerAvatarURL: URL?
    var organizerName: String
    /// The organizer's canonical source record resolved by the AppView for this event.
    /// The temporary browse catalog carries it inline until the AppView endpoint does.
    var source: OME.SourceRecord?
    var startDate: LocalDate
    var status: Status
    var timeZone: String

    var calendarEvent: CalendarEvent {
        get throws {
            guard let organizerID = DID(organizerID) else {
                throw TemporaryOMEBrowseCatalogError.invalidOrganizerID(organizerID)
            }
            guard let timeZone = TimeZone(identifier: timeZone) else {
                throw TemporaryOMEBrowseCatalogError.invalidTimeZone(self.timeZone)
            }
            let uriString = "at://\(organizerID)/\(OME.Event.nsid)/\(eventID)"
            guard let uri = ATProto.URI(uriString) else {
                throw TemporaryOMEBrowseCatalogError.invalidURI(uriString)
            }
            return CalendarEvent(
                uri: uri,
                name: name,
                description: description,
                startsAt: startDate.atStartOfDay(in: timeZone),
                endsAt: endDate.at(hour: 23, minute: 59, second: 59, in: timeZone),
                status: status.calendarEventStatus,
                mode: mode.calendarEventMode,
                locations: location.map { [CalendarEvent.Location(name: $0)] } ?? [],
                media: media.map {
                    CalendarEvent.Media(url: $0.url, alt: $0.alt, role: $0.role)
                },
                organizer: CalendarEvent.Organizer(
                    id: organizerID,
                    displayName: organizerName,
                    avatarURL: organizerAvatarURL
                ),
                source: CalendarEvent.Source(collection: OME.Event.nsid),
                timeZoneIdentifier: timeZone.identifier
            )
        }
    }

    func installationRequest(
        organizerID: OME.Organizer.ID
    ) -> OpenMusicEventSourceValidationRequest? {
        guard let source, source.kind == .tangled else { return nil }
        return OpenMusicEventSourceValidationRequest(
            source: source.reference,
            organizerID: organizerID,
            ref: source.ref ?? "main"
        )
    }

    struct Media: Decodable {
        var alt: String?
        var role: String?
        var url: URL
    }

    enum Mode: String, Decodable {
        case hybrid
        case inPerson
        case virtual

        var calendarEventMode: CalendarEvent.Mode {
            switch self {
            case .hybrid: .hybrid
            case .inPerson: .inPerson
            case .virtual: .virtual
            }
        }
    }

    enum Status: String, Decodable {
        case cancelled
        case planned
        case postponed
        case rescheduled
        case scheduled

        var calendarEventStatus: CalendarEvent.Status {
            switch self {
            case .cancelled: .cancelled
            case .planned: .planned
            case .postponed: .postponed
            case .rescheduled: .rescheduled
            case .scheduled: .scheduled
            }
        }
    }
}

extension CalendarEvent {
    static func isSooner(_ lhs: Self, _ rhs: Self) -> Bool {
        switch (lhs.startsAt, rhs.startsAt) {
        case let (.some(lhsDate), .some(rhsDate)):
            lhsDate == rhsDate
                ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                : lhsDate < rhsDate
        case (.some, .none):
            true
        case (.none, .some):
            false
        case (.none, .none):
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

extension OME.Event.ID {
    init?(_ uri: ATProto.URI) {
        guard case let .did(organizerID) = uri.authority,
              uri.collection == OME.Event.nsid,
              let rkey = uri.rkey
        else { return nil }
        self.init(
            organizerID: organizerID,
            eventID: OME.ID<OME.Event>(rawValue: rkey)
        )
    }
}

extension OME.Event {
    func calendarEvent(posters: [OME.Poster] = []) -> CalendarEvent {
        CalendarEvent(
            uri: OME.Event.reference(id: id).uri,
            name: name,
            description: description,
            startsAt: startDate?.atStartOfDay(in: timeZone),
            endsAt: endDate?.at(hour: 23, minute: 59, second: 59, in: timeZone),
            status: calendarEventStatus,
            mode: calendarEventMode,
            locations: (locations ?? []).compactMap { location in
                guard let address = location.address, !address.isEmpty else { return nil }
                return CalendarEvent.Location(name: address)
            },
            links: (uris ?? []).map {
                CalendarEvent.Link(name: $0.name, uri: $0.uri)
            },
            media: calendarMedia(posters: posters),
            organizer: CalendarEvent.Organizer(id: id.organizerID),
            source: CalendarEvent.Source(collection: OME.Event.nsid),
            timeZoneIdentifier: timeZone.identifier
        )
    }

    private func calendarMedia(posters: [OME.Poster]) -> [CalendarEvent.Media] {
        let posterMedia = posters
            .sorted { lhs, rhs in
                lhs.id.posterID.rawValue.rawValue.localizedStandardCompare(
                    rhs.id.posterID.rawValue.rawValue
                ) == .orderedAscending
            }
            .compactMap { poster -> CalendarEvent.Media? in
                guard let url = poster.image.url else { return nil }
                return CalendarEvent.Media(
                    url: url,
                    alt: poster.title ?? name,
                    role: OME.ImageAsset.Role.poster.rawValue
                )
            }
        let eventMedia = (images ?? [])
            .enumerated()
            .filter { _, image in image.role != .siteMap }
            .sorted { lhs, rhs in
                let lhsPriority = Self.calendarMediaPriority(lhs.element.role)
                let rhsPriority = Self.calendarMediaPriority(rhs.element.role)
                return lhsPriority == rhsPriority
                    ? lhs.offset < rhs.offset
                    : lhsPriority < rhsPriority
            }
            .compactMap { _, image -> CalendarEvent.Media? in
                guard let url = image.url else { return nil }
                return CalendarEvent.Media(
                    url: url,
                    alt: name,
                    role: image.role.rawValue
                )
            }

        var seenURLs = Set<URL>()
        return (posterMedia + eventMedia).filter { media in
            seenURLs.insert(media.url).inserted
        }
    }

    private static func calendarMediaPriority(_ role: OME.ImageAsset.Role) -> Int {
        switch role {
        case .poster: 0
        case .hero: 1
        case .photo: 2
        case .icon: 3
        case .logo: 4
        case .siteMap: 5
        }
    }

    var calendarEventStatus: CalendarEvent.Status? {
        switch status {
        case .known(.cancelled): .cancelled
        case .known(.planned): .planned
        case .known(.postponed): .postponed
        case .known(.rescheduled): .rescheduled
        case .known(.scheduled): .scheduled
        case .unknown(let value): .unknown(String(describing: value))
        case nil: nil
        }
    }

    var calendarEventMode: CalendarEvent.Mode? {
        switch mode {
        case .known(.hybrid): .hybrid
        case .known(.inPerson): .inPerson
        case .known(.virtual): .virtual
        case .unknown(let value): .unknown(String(describing: value))
        case nil: nil
        }
    }
}
