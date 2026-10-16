import Hummingbird
import OpenMusicEventLexicon
import ATProto
import ATProtoHTTP
import ComposableCalendarEvents

extension OpenMusicEventAppViewServer {
    static func installCalendarEventRoutes<Context: RequestContext>(
        on router: Router<Context>,
        store: OpenMusicEventAppViewStore?,
        appViewHost: ATProto.PDSHost
    ) {
        installEventBundleRoute(on: router, store: store)
        installCalendarMapRoutes(on: router, store: store)
        router.register(Event.GetEvent.self) { parameters, _ in
            guard let store else {
                throw XRPC.ResponseError(
                    .serviceUnavailable,
                    error: "EventIndexUnavailable",
                    message: "Event record storage is not configured."
                )
            }
            guard let record = try store.indexedEvent(id: parameters.uri) else {
                throw XRPC.ResponseError(
                    .notFound,
                    error: "EventNotFound",
                    message: "The requested event record is not available."
                )
            }
            return record
        }

        router.register(Event.GetEvents.self) { parameters, _ in
            guard let store else {
                throw XRPC.ResponseError(
                    .serviceUnavailable,
                    error: "EventIndexUnavailable",
                    message: "Event record storage is not configured."
                )
            }
            do {
                return try store.eventPage(cursor: parameters.cursor, limit: parameters.limit)
            } catch OpenMusicEventAppViewStoreError.invalidCursor {
                throw XRPC.ResponseError(
                    .badRequest,
                    error: "InvalidCursor",
                    message: "The XRPC cursor or limit is invalid."
                )
            }
        }

        router.register(OME.CalendarEvent.GetEvent.self) { parameters, _ in
            guard let store,
                  let event = try store.calendarEvent(
                    uri: parameters.uri,
                    appViewHost: appViewHost
                  )
            else {
                throw XRPC.ResponseError(
                    .notFound,
                    error: "EventNotFound",
                    message: "The requested calendar event is not available."
                )
            }
            return event
        }

        router.register(OME.CalendarEvent.GetEvents.self) { parameters, _ in
            guard let store else {
                throw XRPC.ResponseError(
                    .serviceUnavailable,
                    error: "EventIndexUnavailable",
                    message: "Calendar event storage is not configured."
                )
            }
            do {
                return try store.browseCalendarEvents(
                    parameters: OME.CalendarEvent.BrowseEvents.Parameters(
                        catalogs: [parameters.catalog],
                        cursor: parameters.cursor,
                        limit: parameters.limit
                    ),
                    appViewHost: appViewHost
                )
            } catch CalendarEventBrowseProjectionError.unknownCatalog {
                throw XRPC.ResponseError(
                    .notFound,
                    error: "UnknownCatalog",
                    message: "The requested calendar event catalog is not available."
                )
            } catch OpenMusicEventAppViewStoreError.invalidCursor {
                throw XRPC.ResponseError(
                    .badRequest,
                    error: "InvalidCursor",
                    message: "The XRPC cursor is invalid."
                )
            }
        }

        router.register(OME.CalendarEvent.BrowseEvents.self) { parameters, _ in
            guard let store else {
                throw XRPC.ResponseError(
                    .serviceUnavailable,
                    error: "EventIndexUnavailable",
                    message: "Calendar event storage is not configured."
                )
            }
            do {
                return try store.browseCalendarEvents(
                    parameters: parameters,
                    appViewHost: appViewHost
                )
            } catch CalendarEventBrowseProjectionError.unknownCatalog {
                throw XRPC.ResponseError(
                    .notFound,
                    error: "UnknownCatalog",
                    message: "The requested calendar event catalog is not available."
                )
            } catch OpenMusicEventAppViewStoreError.invalidCursor {
                throw XRPC.ResponseError(
                    .badRequest,
                    error: "InvalidCursor",
                    message: "The XRPC cursor is invalid."
                )
            }
        }

    }
}
