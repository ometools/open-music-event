import ComposableCalendarEvents
import Hummingbird
import OpenMusicEventLexicon
import ATProto
import ATProtoHTTP

extension OpenMusicEventAppViewServer {
    static func installCalendarEventRoutes<Context: RequestContext>(
        on router: Router<Context>,
        store: OpenMusicEventAppViewStore?,
        openMusicEventCatalog: OpenMusicEventCalendarCatalog
    ) {
        router.register(OME.CalendarEvent.GetEvent.self) { parameters, _ in
            let event: OME.CalendarEvent?
            if parameters.uri.collection == OME.Event.nsid {
                event = try openMusicEventCatalog.event(uri: parameters.uri)
            } else if parameters.uri.collection == Community.CalendarEvent.nsid, let store {
                event = try store.communityCalendarEvent(uri: parameters.uri)
            } else {
                event = nil
            }

            guard let event else {
                throw XRPC.ResponseError(
                    .notFound,
                    error: "EventNotFound",
                    message: "The requested calendar event is not available."
                )
            }
            return event
        }

        router.register(OME.CalendarEvent.GetEvents.self) { parameters, _ in
            do {
                if parameters.catalog == OME.Event.nsid {
                    return try openMusicEventCatalog.page(
                        cursor: parameters.cursor,
                        limit: parameters.limit
                    )
                }
                if parameters.catalog == Community.CalendarEvent.nsid, let store {
                    return try store.communityCalendarEventPage(
                        cursor: parameters.cursor,
                        limit: parameters.limit
                    )
                }
                throw XRPC.ResponseError(
                    .notFound,
                    error: "UnknownCatalog",
                    message: "The requested calendar event catalog is not available."
                )
            } catch OpenMusicEventCalendarCatalogError.invalidCursor {
                throw XRPC.ResponseError(
                    .badRequest,
                    error: "InvalidCursor",
                    message: "The XRPC cursor is invalid."
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
