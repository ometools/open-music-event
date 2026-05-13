#if canImport(Combine)
@preconcurrency import Combine
#endif
import Sharing
import SQLiteData

@Table("eventViewerState")
public struct EventViewerState: Equatable, Sendable, Identifiable {
    public init(
        id: OMERecord.Event.ID,
        selectedScheduleID: OMERecord.ID<OMERecord.Schedule>? = nil
    ) {
        self.id = id
        self.selectedScheduleID = selectedScheduleID
    }

    public var id: OMERecord.Event.ID
    public var selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
}

struct EventViewerStateKey: SharedKey {
    struct ID: Hashable {
        var eventID: OMERecord.Event.ID
    }

    let eventID: OMERecord.Event.ID
    @Dependency(\.defaultDatabase) var database

    var id: ID {
        ID(eventID: eventID)
    }

    init(eventID: OMERecord.Event.ID) {
        self.eventID = eventID
    }

    func load(
        context: LoadContext<EventViewerState>,
        continuation: LoadContinuation<EventViewerState>
    ) {
        do {
            continuation.resume(returning: try database.read { db in
                try EventViewerStateRequest(eventID: eventID).fetch(db)
            })
        } catch {
            continuation.resume(throwing: error)
        }
    }

    func save(
        _ value: EventViewerState,
        context: SaveContext,
        continuation: SaveContinuation
    ) {
        do {
            var value = value
            value.id = eventID
            try database.write { db in
                try EventViewerState.upsert { value }.execute(db)
            }
            continuation.resume()
        } catch {
            continuation.resume(throwing: error)
        }
    }

    func subscribe(
        context: LoadContext<EventViewerState>,
        subscriber: SharedSubscriber<EventViewerState>
    ) -> SharedSubscription {
        #if canImport(Combine)
        let fetch = Fetch(
            wrappedValue: EventViewerState(id: eventID),
            EventViewerStateRequest(eventID: eventID),
            database: database
        )
        let subscription = EventViewerStateFetchSubscription(fetch: fetch, subscriber: subscriber)
        return SharedSubscription {
            subscription.cancel()
        }
        #else
        return SharedSubscription {}
        #endif
    }
}

extension SharedKey where Self == EventViewerStateKey.Default {
    static func eventViewerState(_ eventID: OMERecord.Event.ID) -> Self {
        Self[
            EventViewerStateKey(eventID: eventID),
            default: EventViewerState(id: eventID)
        ]
    }
}

struct EventViewerStateRequest: FetchKeyRequest {
    let eventID: OMERecord.Event.ID

    func fetch(_ db: Database) throws -> EventViewerState {
        try EventViewerState
            .where { $0.id.eq(eventID) }
            .fetchOne(db)
        ?? EventViewerState(id: eventID)
    }
}

#if canImport(Combine)
private final class EventViewerStateFetchSubscription: @unchecked Sendable {
    let fetch: Fetch<EventViewerState>
    var cancellable: AnyCancellable?

    init(
        fetch: Fetch<EventViewerState>,
        subscriber: SharedSubscriber<EventViewerState>
    ) {
        self.fetch = fetch
        self.cancellable = fetch.publisher.sink { value in
            subscriber.yield(value)
        }
    }

    func cancel() {
        cancellable?.cancel()
        cancellable = nil
    }
}
#endif
