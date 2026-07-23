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
        self.legacyManyStagesOrientation = scheduleKind.legacyManyStagesOrientation
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

    public enum ScheduleKind: Codable, Equatable, Hashable, RawRepresentable, Sendable, SQLiteType {
        case singleStageAtOnce
        case allStagesAtOnce(Orientation)
        case list

        public init?(rawValue: String) {
            switch rawValue {
            case "singleStageAtOnce":
                self = .singleStageAtOnce
            case "allStagesAtOnce",
                "allStagesAtOnce.vertical":
                self = .allStagesAtOnce(.vertical)
            case "allStagesAtOnce.horizontal":
                self = .allStagesAtOnce(.horizontal)
            case "list":
                self = .list
            default:
                return nil
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self = Self(rawValue: try container.decode(String.self)) ?? .singleStageAtOnce
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        public var rawValue: String {
            switch self {
            case .singleStageAtOnce:
                return "singleStageAtOnce"
            case .allStagesAtOnce(.vertical):
                return "allStagesAtOnce.vertical"
            case .allStagesAtOnce(.horizontal):
                return "allStagesAtOnce.horizontal"
            case .list:
                return "list"
            }
        }

        public var title: String {
            switch self {
            case .singleStageAtOnce:
                return "Single Stage"
            case .allStagesAtOnce(.vertical):
                return "Many (V)"
            case .allStagesAtOnce(.horizontal):
                return "Many (H)"
            case .list:
                return "List"
            }
        }

        public var systemImage: String? {
            switch self {
            case .singleStageAtOnce:
                return "calendar.day.timeline.leading"
            case .allStagesAtOnce(.vertical):
                return "rectangle.split.3x1"
            case .allStagesAtOnce(.horizontal):
                return "rectangle.split.1x2"
            case .list:
                return "list.bullet"
            }
        }

        public var orientation: Orientation? {
            guard case let .allStagesAtOnce(orientation) = self else {
                return nil
            }
            return orientation
        }

        public static var allCases: [Self] {
            [
                .singleStageAtOnce,
                .allStagesAtOnce(.horizontal),
                .allStagesAtOnce(.vertical),
                .list,
            ]
        }

        var legacyManyStagesOrientation: Orientation {
            orientation ?? .vertical
        }

        public enum Orientation: String, Codable, Equatable, Hashable, Sendable, CaseIterable, SQLiteType {
            case vertical
            case horizontal

            public var title: String {
                switch self {
                case .vertical:
                    return "Vertical"
                case .horizontal:
                    return "Horizontal"
                }
            }
        }
    }

    public var id: ID
    public var selectedStageID: OMERecord.ID<OMERecord.Stage>?
    public var showStageNameLabels = false
    public var filteringFavorites = false
    public var filteringInterested = false
    @Column("scheduleKind") public var scheduleKind: ScheduleKind = .singleStageAtOnce
    @Column("manyStagesOrientation") var legacyManyStagesOrientation: ScheduleKind.Orientation = .vertical

    mutating func migrateLegacyScheduleKind() {
        if case .allStagesAtOnce(.vertical) = scheduleKind,
            legacyManyStagesOrientation == .horizontal
        {
            scheduleKind = .allStagesAtOnce(.horizontal)
        }
        syncScheduleKindStorage()
    }

    mutating func syncScheduleKindStorage() {
        legacyManyStagesOrientation = scheduleKind.legacyManyStagesOrientation
    }

    static func all(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<ScheduleViewerState> {
        Self
            .where { $0.id.eventID.eq(eventID) }
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
            value.syncScheduleKindStorage()
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
            )
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
        if let state = try ScheduleViewerState
            .rows(eventID: eventID, scheduleDivision: scheduleDivision)
            .fetchOne(db)
        {
            var state = state
            state.migrateLegacyScheduleKind()
            return state
        }

        let showStageNameLabels = try defaultShowStageNameLabels(db)
        return ScheduleViewerState(
            id: ScheduleViewerState.ID(
                eventID: eventID,
                category: scheduleDivision.id
            ),
            showStageNameLabels: showStageNameLabels
        )
    }

    private func defaultShowStageNameLabels(_ db: Database) throws -> Bool {
        guard let category = scheduleDivision.category else {
            return false
        }
        let event = try OMERecord.Event
            .where { $0.id.eq(eventID) }
            .fetchOne(db)
        return event?.categoryConfigs?[category]?.showStageNameLabels ?? false
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
