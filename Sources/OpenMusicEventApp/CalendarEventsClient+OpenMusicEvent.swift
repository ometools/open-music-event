import ATProto
import ComposableCalendarEvents
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData

extension CalendarEventsClient {
    static func openMusicEventAndAtmo(database: any DatabaseWriter) -> Self {
        let atmo = Self.atmoRSVP
        return Self(
            browse: { request in
                guard request.collection == OME.Event.nsid else {
                    return try await atmo.browse(request)
                }
                let events = try await database.read { db in
                    try OME.Event
                        .order { ($0.startDate.asc(), $0.name) }
                        .fetchAll(db)
                }
                return CalendarEvent.Page(
                    events: Array(events.prefix(request.limit)).map(\.calendarEvent)
                )
            },
            event: { uri in
                guard uri.collection == OME.Event.nsid else {
                    return try await atmo.event(uri)
                }
                guard let eventID = OME.Event.ID(uri) else {
                    throw CalendarEventsClientError.invalidEventURI(uri.description)
                }
                guard let event = try await database.read({ db in
                    try OME.Event.find(eventID).fetchOne(db)
                }) else {
                    throw CalendarEventsClientError.missingEventRecord
                }
                return event.calendarEvent
            },
            organizer: { organizerID in
                CalendarEvent.Organizer(id: organizerID)
            }
        )
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
    var calendarEvent: CalendarEvent {
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
            organizer: CalendarEvent.Organizer(id: id.organizerID),
            source: CalendarEvent.Source(collection: OME.Event.nsid),
            timeZoneIdentifier: timeZone.identifier
        )
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
