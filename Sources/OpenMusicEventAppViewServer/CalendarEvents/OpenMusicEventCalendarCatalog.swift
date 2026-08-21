import ATProto
import Foundation
import OpenMusicEventLexicon

/// The OME catalog has one owner for each organizer.
///
/// Configured Tangled watches are served exclusively from durable source projections. The bundled
/// catalog remains a temporary source only for organizers that do not yet have a server watch.
struct OpenMusicEventCalendarCatalog {
    init(
        appViewHost: ATProto.PDSHost,
        tangledWebhook: TangledWebhookConfiguration?,
        store: OpenMusicEventAppViewStore?
    ) {
        self.appViewHost = appViewHost
        self.store = store
        watchesByOrganizerID = Dictionary(
            grouping: tangledWebhook?.watches ?? [],
            by: { $0.canonicalSource.organizerID }
        )
    }

    private let appViewHost: ATProto.PDSHost
    private let store: OpenMusicEventAppViewStore?
    private let watchesByOrganizerID: [OME.Organizer.ID: [TangledWebhookWatch]]

    func event(uri: ATProto.URI) throws -> OME.CalendarEvent? {
        guard uri.collection == OME.Event.nsid,
              case let .did(organizerID) = uri.authority
        else { return nil }

        if let watches = watchesByOrganizerID[organizerID] {
            return try store?.tangledSourceCalendarEvent(
                uri: uri,
                watchIDs: watches.map(\.id),
                appViewHost: appViewHost
            )
        }
        return try BundledCalendarEventCatalog.event(
            uri: uri,
            appViewHost: appViewHost
        )
    }

    func page(cursor: String?, limit: Int) throws -> OME.CalendarEvent.Page {
        let offset: Int
        if let cursor {
            guard let parsedOffset = Int(cursor), parsedOffset >= 0 else {
                throw OpenMusicEventCalendarCatalogError.invalidCursor(cursor)
            }
            offset = parsedOffset
        } else {
            offset = 0
        }

        let events = try allEvents()
        guard offset <= events.count else {
            throw OpenMusicEventCalendarCatalogError.invalidCursor(String(offset))
        }
        let pageEvents = Array(events.dropFirst(offset).prefix(limit))
        let nextOffset = offset + pageEvents.count
        return OME.CalendarEvent.Page(
            events: pageEvents,
            cursor: nextOffset < events.count ? String(nextOffset) : nil
        )
    }

    private func allEvents() throws -> [OME.CalendarEvent] {
        let sourceEvents = try store?.tangledSourceCalendarEvents(
            watchIDs: watchesByOrganizerID.values.flatMap { $0.map(\.id) },
            appViewHost: appViewHost
        ) ?? []
        let bundledEvents = try BundledCalendarEventCatalog.events(
            appViewHost: appViewHost
        )
        .filter { watchesByOrganizerID[$0.organizer.id] == nil }
        return sourceEvents + bundledEvents
    }
}

enum OpenMusicEventCalendarCatalogError: Error, Equatable {
    case invalidCursor(String)
}
