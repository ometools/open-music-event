import Hummingbird
import OpenMusicEventLexicon
import ATProto
import ATProtoHTTP

extension OpenMusicEventAppViewServer {
    static func installCalendarEventRoutes<Context: RequestContext>(
        on router: Router<Context>,
        store: OpenMusicEventAppViewStore?
    ) {
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

    }
}
