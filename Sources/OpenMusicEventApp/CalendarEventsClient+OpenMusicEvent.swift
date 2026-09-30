import ATProto
import ComposableCalendarEvents
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import SQLiteData

extension CalendarEventsClient {
    static func uiAutomation(database: any DatabaseWriter) -> Self {
        Self(
            browse: { request in
                guard request.collection == OME.Event.nsid else {
                    throw CalendarEventsClientError.collectionNotServed(request.collection)
                }
                let events = try await storedOpenMusicEvents(database: database)
                return CalendarEvent.Page(
                    events: Array(events.prefix(request.limit)),
                    cursor: nil
                )
            },
            event: { uri in
                guard let eventID = OME.Event.ID(uri) else {
                    throw CalendarEventsClientError.invalidEventURI(uri.description)
                }
                guard let event = try await storedOpenMusicEvent(
                    eventID,
                    database: database
                ) else {
                    throw CalendarEventsClientError.missingEventRecord
                }
                return event
            },
            organizer: { organizerID in
                let hasOrganizer = try await database.read { db in
                    try OME.Event
                        .where { $0.id.organizerID.eq(organizerID) }
                        .fetchCount(db) > 0
                }
                guard hasOrganizer else {
                    throw CalendarEventsClientError.missingOrganizer(organizerID)
                }
                return CalendarEvent.Organizer(id: organizerID)
            }
        )
    }

    static func openMusicEventAndAtmo(
        database: any DatabaseWriter,
        appViewHost: ATProto.PDSHost = "openmusicevent.app"
    ) -> Self {
        let atmo = Self.atmoRSVP
        return Self(
            browse: { request in
                guard request.collection == OME.Event.nsid
                    || request.collection == Community.CalendarEvent.nsid
                else {
                    return try await atmo.browse(request)
                }
                let page = try await Self.openMusicEventPage(
                    request,
                    appViewHost: appViewHost
                )
                let installedEvents = try await storedOpenMusicEvents(database: database)
                let installedEventsByURI = Dictionary(
                    uniqueKeysWithValues: installedEvents.map { ($0.uri, $0) }
                )
                return CalendarEvent.Page(
                    events: page.events.map { event in
                        installedEventsByURI[event.uri]
                            ?? event.calendarEvent(appViewHost: appViewHost)
                    },
                    cursor: page.cursor
                )
            },
            event: { uri in
                guard uri.collection == OME.Event.nsid
                    || uri.collection == Community.CalendarEvent.nsid
                else {
                    return try await atmo.event(uri)
                }
                if uri.collection == OME.Event.nsid {
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
                }

                let event = try await Self.openMusicEvent(
                    uri,
                    appViewHost: appViewHost
                )
                return event.calendarEvent(appViewHost: appViewHost)
            },
            organizer: { organizerID in
                let page = try await Self.openMusicEventPage(
                    CalendarEvent.PageRequest(
                        collection: OME.Event.nsid,
                        limit: 100
                    ),
                    appViewHost: appViewHost
                )
                if let organizer = page.events
                    .first(where: { $0.organizer.id == organizerID })?
                    .organizer {
                    return organizer.calendarEventOrganizer
                }
                return try await atmo.organizer(organizerID)
            }
        )
    }

    static func storedOpenMusicEvents(
        database: any DatabaseWriter
    ) async throws -> [CalendarEvent] {
        try await database.read { db in
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
    }

    static func storedOpenMusicEvent(
        _ eventID: OME.Event.ID,
        database: any DatabaseWriter
    ) async throws -> CalendarEvent? {
        try await database.read { db in
            guard let event = try OME.Event.find(eventID).fetchOne(db) else {
                return nil
            }
            let posters = try OME.Poster
                .where { $0.id.organizerID.eq(eventID.organizerID) }
                .where { $0.id.eventID.eq(eventID.eventID) }
                .fetchAll(db)
            return event.calendarEvent(posters: posters)
        }
    }

    static func openMusicEventPage(
        _ request: CalendarEvent.PageRequest,
        appViewHost: ATProto.PDSHost? = nil
    ) async throws -> OME.CalendarEvent.Page {
        @Dependency(\.openMusicEventServiceEnvironment) var serviceEnvironment
        @Dependency(XRPC.Client.self) var xrpcClient
        let appViewHost = appViewHost ?? serviceEnvironment.appViewHost
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try await withDependencies {
            $0.pdsHost = appViewHost
            $0.jsonDecoder = decoder
        } operation: {
            try await xrpcClient.run(
                OME.CalendarEvent.GetEvents(
                    catalog: request.collection,
                    cursor: request.cursor,
                    limit: request.limit
                )
            )
        }
    }

    static func openMusicEvent(
        _ uri: ATProto.URI,
        appViewHost: ATProto.PDSHost? = nil
    ) async throws -> OME.CalendarEvent {
        @Dependency(\.openMusicEventServiceEnvironment) var serviceEnvironment
        @Dependency(XRPC.Client.self) var xrpcClient
        let appViewHost = appViewHost ?? serviceEnvironment.appViewHost
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try await withDependencies {
            $0.pdsHost = appViewHost
            $0.jsonDecoder = decoder
        } operation: {
            try await xrpcClient.run(OME.CalendarEvent.GetEvent(uri: uri))
        }
    }
}

extension OME.CalendarEvent.Source {
    func installationRequest(
        organizerID: OME.Organizer.ID
    ) throws -> OpenMusicEventSourceValidationRequest? {
        guard let sourceRecord,
              sourceRecord.kind == .tangled,
              let resolvedArtifact
        else { return nil }
        let canonicalRef = sourceRecord.ref ?? "main"
        guard let sourceProvenance = try OpenMusicEventSourceValidationRequest(
            source: sourceRecord.reference,
            organizerID: organizerID,
            ref: canonicalRef
        )
        .tangledSourceProvenance()
        else { return nil }
        return OpenMusicEventSourceValidationRequest(
            source: sourceRecord.reference,
            organizerID: organizerID,
            sourceProvenance: sourceProvenance,
            ref: resolvedArtifact.revision,
            archive: SourceArchiveReference(
                url: resolvedArtifact.url,
                checksumSHA256: resolvedArtifact.checksumSHA256,
                byteCount: resolvedArtifact.byteCount
            )
        )
    }
}

extension OME.CalendarEvent {
    func calendarEvent(appViewHost: ATProto.PDSHost) -> CalendarEvent {
        CalendarEvent(
            uri: uri,
            cid: cid,
            name: name,
            description: description,
            startsAt: startsAt,
            endsAt: endsAt,
            createdAt: createdAt,
            status: status?.calendarEventStatus,
            mode: mode?.calendarEventMode,
            locations: locations.map {
                CalendarEvent.Location(
                    name: $0.name,
                    street: $0.street,
                    locality: $0.locality,
                    region: $0.region,
                    postalCode: $0.postalCode,
                    country: $0.country,
                    latitude: $0.latitude,
                    longitude: $0.longitude,
                    source: $0.source
                )
            },
            links: links.map {
                CalendarEvent.Link(name: $0.name, uri: $0.uri, source: $0.source)
            },
            media: media.map {
                CalendarEvent.Media(url: $0.url, alt: $0.alt, role: $0.role)
            },
            organizer: organizer.calendarEventOrganizer,
            attendance: CalendarEvent.Attendance(
                going: attendance.going,
                interested: attendance.interested,
                notGoing: attendance.notGoing
            ),
            source: CalendarEvent.Source(
                collection: source.collection,
                appViewHost: source.appViewHost ?? appViewHost
            ),
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}

private extension OME.CalendarEvent.Organizer {
    var calendarEventOrganizer: CalendarEvent.Organizer {
        CalendarEvent.Organizer(
            id: id,
            handle: handle,
            displayName: displayName,
            description: description,
            avatarURL: avatarURL
        )
    }
}

private extension OME.CalendarEvent.Mode {
    var calendarEventMode: CalendarEvent.Mode {
        switch self {
        case .hybrid: .hybrid
        case .inPerson: .inPerson
        case .virtual: .virtual
        case .unknown(let value): .unknown(value)
        }
    }
}

private extension OME.CalendarEvent.Status {
    var calendarEventStatus: CalendarEvent.Status {
        switch self {
        case .cancelled: .cancelled
        case .planned: .planned
        case .postponed: .postponed
        case .rescheduled: .rescheduled
        case .scheduled: .scheduled
        case .unknown(let value): .unknown(value)
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
