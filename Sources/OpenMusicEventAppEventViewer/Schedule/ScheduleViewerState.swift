#if canImport(Combine)
@preconcurrency import Combine
#endif
import Sharing
import SQLiteData

@Table("scheduleViewerState")
public struct ScheduleViewerState: Equatable, Sendable, Identifiable {
    public init(
        id: ID,
        selectedStageID: OMERecord.ID<OMERecord.Stage>? = nil,
        showStageNameLabels: Bool = false,
        filteringFavorites: Bool = false,
        filteringInterested: Bool = false,
        scheduleKind: ScheduleKind = .singleStageAtOnce
    ) {
        self.id = id
        self.selectedStageID = selectedStageID
        self.showStageNameLabels = showStageNameLabels
        self.filteringFavorites = filteringFavorites
        self.filteringInterested = filteringInterested
        self.scheduleKind = scheduleKind
    }

    public init(
        eventID: OMERecord.Event.ID,
        scheduleDivision: ScheduleViewer.ScheduleDivision
    ) {
        self.init(
            id: ID(
                eventID: eventID,
                category: scheduleDivision.id
            )
        )
    }

    @Selection
    public struct ID: Hashable, Sendable {
        public init(
            eventID: OMERecord.Event.ID,
            category: String
        ) {
            self.eventID = eventID
            self.category = category
        }

        public var eventID: OMERecord.Event.ID
        public var category: String
    }

    public enum ScheduleKind: String, Codable, Sendable, CaseIterable, SQLiteType {
        case singleStageAtOnce
        case allStagesAtOnce
        case list
    }

    public var id: ID
    public var selectedStageID: OMERecord.ID<OMERecord.Stage>?
    public var showStageNameLabels = false
    public var filteringFavorites = false
    public var filteringInterested = false
    @Column("scheduleKind") public var scheduleKind: ScheduleKind = .singleStageAtOnce

    public var scheduleMode: ScheduleViewer.ScheduleMode {
        get {
            switch scheduleKind {
            case .singleStageAtOnce, .allStagesAtOnce:
                return .singleStageAtOnce
            case .list:
                return .list
            }
        }
        set {
            switch newValue {
            case .singleStageAtOnce:
                scheduleKind = .singleStageAtOnce
            case .list:
                scheduleKind = .list
            }
        }
    }

    static func rows(
        eventID: OMERecord.Event.ID,
        scheduleDivision: ScheduleViewer.ScheduleDivision
    ) -> some SelectStatementOf<ScheduleViewerState> {
        Self
            .where { $0.id.eventID.eq(eventID) }
            .where { $0.id.category.eq(scheduleDivision.id) }
    }
}

struct ScheduleViewerStateKey: SharedKey {
    struct ID: Hashable {
        var eventID: OMERecord.Event.ID
        var scheduleDivision: ScheduleViewer.ScheduleDivision
    }

    let eventID: OMERecord.Event.ID
    let scheduleDivision: ScheduleViewer.ScheduleDivision
    @Dependency(\.defaultDatabase) var database

    var id: ID {
        ID(
            eventID: eventID,
            scheduleDivision: scheduleDivision
        )
    }

    init(
        eventID: OMERecord.Event.ID,
        scheduleDivision: ScheduleViewer.ScheduleDivision
    ) {
        self.eventID = eventID
        self.scheduleDivision = scheduleDivision
    }

    func load(
        context: LoadContext<ScheduleViewerState>,
        continuation: LoadContinuation<ScheduleViewerState>
    ) {
        do {
            continuation.resume(returning: try database.read { db in
                try ScheduleViewerStateRequest(
                    eventID: eventID,
                    scheduleDivision: scheduleDivision
                )
                .fetch(db)
            })
        } catch {
            continuation.resume(throwing: error)
        }
    }

    func save(
        _ value: ScheduleViewerState,
        context: SaveContext,
        continuation: SaveContinuation
    ) {
        do {
            var value = value
            value.id = ScheduleViewerState.ID(
                eventID: eventID,
                category: scheduleDivision.id
            )
            try database.write { db in
                try ScheduleViewerState
                    .where { $0.id.eventID.eq(eventID) }
                    .where { $0.id.category.eq(scheduleDivision.id) }
                    .delete()
                    .execute(db)
                try ScheduleViewerState.insert { value }.execute(db)
            }
            continuation.resume()
        } catch {
            continuation.resume(throwing: error)
        }
    }

    func subscribe(
        context: LoadContext<ScheduleViewerState>,
        subscriber: SharedSubscriber<ScheduleViewerState>
    ) -> SharedSubscription {
        #if canImport(Combine)
        let fetch = Fetch(
            wrappedValue: ScheduleViewerState(
                eventID: eventID,
                scheduleDivision: scheduleDivision
            ),
            ScheduleViewerStateRequest(
                eventID: eventID,
                scheduleDivision: scheduleDivision
            ),
            database: database
        )
        let subscription = ScheduleViewerStateFetchSubscription(fetch: fetch, subscriber: subscriber)
        return SharedSubscription {
            subscription.cancel()
        }
        #else
        return SharedSubscription {}
        #endif
    }
}

extension SharedKey where Self == ScheduleViewerStateKey.Default {
    static func scheduleViewerState(
        eventID: OMERecord.Event.ID,
        scheduleDivision: ScheduleViewer.ScheduleDivision
    ) -> Self {
        Self[
            ScheduleViewerStateKey(
                eventID: eventID,
                scheduleDivision: scheduleDivision
            ),
            default: ScheduleViewerState(
                eventID: eventID,
                scheduleDivision: scheduleDivision
            )
        ]
    }
}

struct ScheduleViewerStateRequest: FetchKeyRequest {
    let eventID: OMERecord.Event.ID
    let scheduleDivision: ScheduleViewer.ScheduleDivision

    func fetch(_ db: Database) throws -> ScheduleViewerState {
        try ScheduleViewerState
            .rows(eventID: eventID, scheduleDivision: scheduleDivision)
            .fetchOne(db)
        ?? ScheduleViewerState(
            eventID: eventID,
            scheduleDivision: scheduleDivision
        )
    }
}

#if canImport(Combine)
private final class ScheduleViewerStateFetchSubscription: @unchecked Sendable {
    let fetch: Fetch<ScheduleViewerState>
    var cancellable: AnyCancellable?

    init(
        fetch: Fetch<ScheduleViewerState>,
        subscriber: SharedSubscriber<ScheduleViewerState>
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
