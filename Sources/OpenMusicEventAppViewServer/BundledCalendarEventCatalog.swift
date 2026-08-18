import ATProto
import Foundation
import OpenMusicEventLexicon

enum BundledCalendarEventCatalog {
    struct Configuration: Sendable {
        init(
            appViewHost: ATProto.PDSHost,
            tangledWebhook: TangledWebhookConfiguration?
        ) {
            self.appViewHost = appViewHost
            self.resolvedRepositories = Dictionary(
                uniqueKeysWithValues: (tangledWebhook?.watches ?? []).map { watch in
                    (
                        watch.canonicalSource,
                        OME.CalendarEvent.Source.Repository(
                            reference: "at://\(watch.repositoryOwnerDID)/sh.tangled.repo/\(watch.repositoryKey.rawValue)",
                            ref: BundledCalendarEventCatalog.normalizedBranch(watch.ref)
                        )
                    )
                }
            )
        }

        let appViewHost: ATProto.PDSHost
        let resolvedRepositories: [CanonicalTangledSource: OME.CalendarEvent.Source.Repository]
    }

    static func event(
        uri: ATProto.URI,
        configuration: Configuration
    ) throws -> OME.CalendarEvent? {
        try events(configuration: configuration).first { $0.uri == uri }
    }

    static func event(uri: ATProto.URI) throws -> OME.CalendarEvent? {
        try event(
            uri: uri,
            configuration: Configuration(
                appViewHost: "openmusicevent.app",
                tangledWebhook: nil
            )
        )
    }

    static func page(
        cursor: String?,
        limit: Int,
        configuration: Configuration
    ) throws -> OME.CalendarEvent.Page {
        let offset: Int
        if let cursor {
            guard let parsedOffset = Int(cursor), parsedOffset >= 0 else {
                throw BundledCalendarEventCatalogError.invalidCursor(cursor)
            }
            offset = parsedOffset
        } else {
            offset = 0
        }

        let events = try events(configuration: configuration)
        guard offset <= events.count else {
            throw BundledCalendarEventCatalogError.invalidCursor(String(offset))
        }

        let pageEvents = Array(events.dropFirst(offset).prefix(limit))
        let nextOffset = offset + pageEvents.count
        return OME.CalendarEvent.Page(
            events: pageEvents,
            cursor: nextOffset < events.count ? String(nextOffset) : nil
        )
    }

    static func events(configuration: Configuration) throws -> [OME.CalendarEvent] {
        guard let resourceURL = Bundle.module.url(
            forResource: "TemporaryOMEBrowseCatalog",
            withExtension: "json"
        ) else {
            throw BundledCalendarEventCatalogError.missingResource
        }

        return try JSONDecoder()
            .decode([BundledCalendarEvent].self, from: Data(contentsOf: resourceURL))
            .map { try $0.calendarEvent(configuration: configuration) }
    }

    private static func normalizedBranch(_ ref: String) -> String {
        let prefix = "refs/heads/"
        return ref.hasPrefix(prefix) ? String(ref.dropFirst(prefix.count)) : ref
    }
}

enum BundledCalendarEventCatalogError: Error, Equatable {
    case invalidCursor(String)
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
    var sourceRecordKey: String?
    var startDate: LocalDate
    var status: OME.Event.Status?
    var timeZone: String

    var calendarEvent: OME.CalendarEvent {
        get throws {
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
                    appViewHost: "openmusicevent.app",
                    sourceRecord: source
                ),
                timeZoneIdentifier: timeZone.identifier,
                event: event
            )
        }
    }

    func calendarEvent(
        configuration: BundledCalendarEventCatalog.Configuration
    ) throws -> OME.CalendarEvent {
        var event = try calendarEvent
        event.source.appViewHost = configuration.appViewHost
        if let sourceRecordKey,
           let organizerID = DID(organizerID)
        {
            let canonicalSource = CanonicalTangledSource(
                organizerID: organizerID,
                repositoryRecordKey: ATProto.Record.Key(rawValue: sourceRecordKey)
            )
            event.source.resolvedRepository = configuration.resolvedRepositories[canonicalSource]
        }
        return event
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
