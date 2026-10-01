import ATProtoSQLite
import OpenMusicEventLexicon
import SQLiteData

@Table("scheduleViewerState")
public struct ScheduleViewerState: Equatable, Sendable, Identifiable {
    public init(
        id: ID,
        selectedStageID: EventPlace.ID? = nil,
        filteringFavorites: Bool = false,
        scheduleKind: ScheduleKind = .singleStageAtOnce
    ) {
        self.id = id
        self.selectedStageID = selectedStageID
        self.filteringFavorites = filteringFavorites
        self.scheduleKind = scheduleKind
        self.legacyManyStagesOrientation = scheduleKind.legacyManyStagesOrientation
    }

    public init(
        eventID: Event.ID,
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
            eventID: Event.ID,
            category: String
        ) {
            self.eventID = eventID
            self.category = category
        }

        public var eventID: Event.ID
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
    public var selectedStageID: EventPlace.ID?
    public var filteringFavorites = false
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

    static func forEvent(
        eventID: Event.ID
    ) -> some SelectStatementOf<ScheduleViewerState> {
        Self
            .where { $0.id.eventID.eq(eventID) }
    }

    static func rows(
        eventID: Event.ID,
        scheduleDivision: ScheduleViewer.ScheduleDivision
    ) -> some SelectStatementOf<ScheduleViewerState> {
        Self
            .where { $0.id.eventID.eq(eventID) }
            .where { $0.id.category.eq(scheduleDivision.id) }
    }

    static func persistChanges(
        from oldValue: Self,
        to newValue: Self,
        eventID: Event.ID,
        scheduleDivision: ScheduleViewer.ScheduleDivision,
        in db: Database
    ) throws {
        var storedValue = try ScheduleViewerStateRequest(
            eventID: eventID,
            scheduleDivision: scheduleDivision
        )
        .fetch(db)
        var hasChanges = false

        if oldValue.selectedStageID != newValue.selectedStageID {
            storedValue.selectedStageID = newValue.selectedStageID
            hasChanges = true
        }
        if oldValue.filteringFavorites != newValue.filteringFavorites {
            storedValue.filteringFavorites = newValue.filteringFavorites
            hasChanges = true
        }
        if oldValue.scheduleKind != newValue.scheduleKind {
            storedValue.scheduleKind = newValue.scheduleKind
            hasChanges = true
        }

        guard hasChanges else { return }
        storedValue.id = ID(eventID: eventID, category: scheduleDivision.id)
        storedValue.syncScheduleKindStorage()
        try Self
            .where { $0.id.eventID.eq(eventID) }
            .where { $0.id.category.eq(scheduleDivision.id) }
            .delete()
            .execute(db)
        try Self.insert { storedValue }.execute(db)
    }
}

struct ScheduleViewerStateRequest: FetchKeyRequest {
    let eventID: Event.ID
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

        return ScheduleViewerState(
            id: ScheduleViewerState.ID(
                eventID: eventID,
                category: scheduleDivision.id
            )
        )
    }

}
