import ATProto
import ComposableCalendarEvents
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventAppEventViewer
import OpenMusicEventLexicon
import SQLiteData

extension CalendarEventsClient {
    static func uiAutomation(database: any DatabaseWriter) -> Self {
        Self(
            browse: { request in
                guard request.collection == ATProto.NSID(Event.lexiconID.rawValue) else {
                    throw CalendarEventsClientError.collectionNotServed(request.collection)
                }
                let events = try await database.read { db in
                    try Event.all.fetchAll(db).map { try $0.calendarEvent() }
                        .sorted(by: CalendarEvent.isSooner)
                }
                return CalendarEvent.Page(
                    events: Array(events.prefix(request.limit)),
                    cursor: nil
                )
            },
            event: { uri in
                guard uri.collection == ATProto.NSID(Event.lexiconID.rawValue) else {
                    throw CalendarEventsClientError.invalidEventURI(uri.description)
                }
                guard let event = try await database.read({ db in
                    try Event.find(uri).fetchOne(db)
                }) else {
                    throw CalendarEventsClientError.missingEventRecord
                }
                return try event.calendarEvent()
            },
            organizer: { organizerID in
                let hasOrganizer = try await database.read { db in
                    try Event.all.fetchAll(db).contains {
                        $0.id.authority == .did(organizerID)
                    }
                }
                guard hasOrganizer else {
                    throw CalendarEventsClientError.missingOrganizer(organizerID)
                }
                return CalendarEvent.Organizer(id: organizerID)
            }
        )
    }

    static func openMusicEventAndAtmo(
        appViewHost: ATProto.PDSHost = "openmusicevent.app"
    ) -> Self {
        let atmo = Self.atmoRSVP
        return Self(
            browse: { request in
                if request.collection == ATProto.NSID(Event.lexiconID.rawValue) {
                    let page = try await Self.canonicalEventPage(
                        request,
                        appViewHost: appViewHost
                    )
                    var events: [CalendarEvent] = []
                    for record in page.events {
                        events.append(try await Self.displayEvent(record))
                    }
                    return CalendarEvent.Page(events: events, cursor: page.cursor)
                }
                return try await atmo.browse(request)
            },
            event: { uri in
                if uri.collection == ATProto.NSID(Event.lexiconID.rawValue) {
                    let record = try await Self.canonicalEvent(
                        uri,
                        appViewHost: appViewHost
                    )
                    return try await Self.displayEvent(record)
                }
                return try await atmo.event(uri)
            },
            organizer: { organizerID in
                let canonicalPage = try await Self.canonicalEventPage(
                    CalendarEvent.PageRequest(
                        collection: ATProto.NSID(Event.lexiconID.rawValue),
                        limit: 100
                    ),
                    appViewHost: appViewHost
                )
                if canonicalPage.events.contains(where: {
                    $0.uri.authority == .did(organizerID)
                }) {
                    return CalendarEvent.Organizer(id: organizerID)
                }
                return try await atmo.organizer(organizerID)
            }
        )
    }

    static func canonicalEventPage(
        _ request: CalendarEvent.PageRequest,
        appViewHost: ATProto.PDSHost
    ) async throws -> Event.Page {
        @Dependency(XRPC.Client.self) var xrpcClient
        return try await withDependencies {
            $0.pdsHost = appViewHost
        } operation: {
            try await xrpcClient.run(Event.GetEvents(
                cursor: request.cursor,
                limit: request.limit
            ))
        }
    }

    static func displayEvent(_ record: Event.IndexedRecord) async throws -> CalendarEvent {
        let event = try record.event()
        let hasBlob = (event.media ?? []).contains {
            if case .known(.image(let image)) = $0,
               case .known(.blob) = image.source { return true }
            return false
        }
        let host: ATProto.PDSHost?
        if hasBlob {
            @Dependency(ATProto.Repository.PDSHostResolver.self) var pdsHosts
            host = try await pdsHosts.pdsHost(forRecordURI: event.id)
        } else {
            host = nil
        }
        return try event.calendarEvent(imageHost: host)
    }

    static func canonicalEvent(
        _ uri: ATProto.URI,
        appViewHost: ATProto.PDSHost
    ) async throws -> Event.IndexedRecord {
        @Dependency(XRPC.Client.self) var xrpcClient
        return try await withDependencies {
            $0.pdsHost = appViewHost
        } operation: {
            try await xrpcClient.run(Event.GetEvent(uri: uri))
        }
    }

}

private extension Event {
    func calendarEvent(imageHost: ATProto.PDSHost? = nil) throws -> CalendarEvent {
        guard case let .did(organizerID) = id.authority else {
            throw CalendarEventsClientError.invalidEventURI(id.description)
        }
        let status: CalendarEvent.Status? = switch status {
        case .known(.planned): .planned
        case .known(.scheduled): .scheduled
        case .known(.rescheduled): .rescheduled
        case .known(.cancelled): .cancelled
        case .known(.postponed): .postponed
        case let .unknown(value): .unknown(value.string ?? String(describing: value))
        case nil: nil
        }
        let mode: CalendarEvent.Mode? = switch mode {
        case .known(.inPerson): .inPerson
        case .known(.virtual): .virtual
        case .known(.hybrid): .hybrid
        case let .unknown(value): .unknown(value.string ?? String(describing: value))
        case nil: nil
        }
        return CalendarEvent(
            uri: id,
            cid: cid,
            name: name,
            description: description,
            startsAt: start?.date(in: timeZone),
            endsAt: end?.date(in: timeZone),
            status: status,
            mode: mode,
            locations: (locations ?? []).map { .init(name: $0.name) },
            links: (links ?? []).map { .init(name: $0.title, uri: $0.url) },
            media: (media ?? []).compactMap { medium in
                guard case let .known(.image(image)) = medium else { return nil }
                let url: URL
                switch image.source {
                case let .known(.url(value)):
                    url = value
                case let .known(.blob(blob)):
                    guard let imageHost,
                          var components = URLComponents(string: "https://\(imageHost)") else { return nil }
                    components.path = "/xrpc/com.atproto.sync.getBlob"
                    components.queryItems = [
                        URLQueryItem(name: "did", value: organizerID.description),
                        URLQueryItem(name: "cid", value: blob.ref.rawValue),
                    ]
                    guard let value = components.url else { return nil }
                    url = value
                case .unknown:
                    return nil
                }
                let role: String? = switch image.role {
                case let .known(role): role.rawValue
                case let .unknown(value): value.string
                case nil: nil
                }
                return CalendarEvent.Media(
                    url: url,
                    alt: image.alt?.rawValue,
                    role: role
                )
            },
            organizer: .init(id: organizerID),
            source: .init(collection: ATProto.NSID(Event.lexiconID.rawValue)),
            timeZoneIdentifier: timeZone.identifier
        )
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
