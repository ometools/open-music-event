import Foundation
import OpenMusicEventLexicon
import SQLiteData
import Tagged

public struct EventSearchDashboard: Equatable, Sendable {
    public init(
        stageRows: [StageDashboardRow],
        featureRows: [FeatureShortcutRow],
        channelRows: [ChannelShortcutRow],
        nowPlayingRows: [PerformanceDashboardRow] = [],
        comingNextRows: [PerformanceDashboardRow] = []
    ) {
        self.stageRows = stageRows
        self.featureRows = featureRows
        self.channelRows = channelRows
        self.nowPlayingRows = nowPlayingRows
        self.comingNextRows = comingNextRows
    }

    public var stageRows: [StageDashboardRow]
    public var featureRows: [FeatureShortcutRow]
    public var channelRows: [ChannelShortcutRow]
    public var nowPlayingRows: [PerformanceDashboardRow]
    public var comingNextRows: [PerformanceDashboardRow]

    public static func fetch(eventID: Event.ID, db: Database) throws -> Self {
        try fetch(eventID: eventID, now: nil, db: db)
    }

    public static func fetch(eventID: Event.ID, now: Date, db: Database) throws -> Self {
        try fetch(eventID: eventID, now: Optional(now), db: db)
    }

    private static func fetch(eventID: Event.ID, now: Date?, db: Database) throws -> Self {
        let places = try EventPlace.where { $0.event.eq(eventID) }.fetchAll(db)
        let stages = places
            .filter { if case .known(.stage) = $0.kind { true } else { false } }
            .sorted { lhs, rhs in
                let lhsIndex: Int? = if case let .known(.stage(use)) = lhs.kind { use.sortIndex } else { nil }
                let rhsIndex: Int? = if case let .known(.stage(use)) = rhs.kind { use.sortIndex } else { nil }
                if lhsIndex != rhsIndex {
                    if let lhsIndex, let rhsIndex { return lhsIndex < rhsIndex }
                    return lhsIndex != nil
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        let channels = try Social.Category
            .where { $0.event.eq(eventID) }
            .order { $0.name.collate(.nocase) }
            .fetchAll(db)

        let placesByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        let performanceRows = try now.map { _ in
            try ProgramItem
                .where { $0.event.eq(eventID) }
                .order { ($0.startsAt.asc(nulls: .last), $0.title.collate(.nocase)) }
                .fetchAll(db)
                .map { item in
                    (
                        row: PerformanceDashboardRow(
                            performance: item,
                            stage: item.eventPlace.flatMap { placesByID[$0] }
                        ),
                        start: item.startDate,
                        end: item.endDate
                    )
                }
        } ?? []
        let nowPlayingRows = performanceRows.filter { entry in
            guard let now, let start = entry.start, let end = entry.end else { return false }
            return start <= now && now < end
        }
        let nextStart = now.flatMap { now in
            performanceRows.compactMap(\.start).filter { now < $0 }.min()
        }
        let comingNextRows = nextStart.map { start in
            performanceRows.filter { $0.start == start }
        } ?? []

        let stageRows = stages.map { stage in
            let performances = performanceRows.filter { $0.row.performance.eventPlace == stage.id }
            let current = nowPlayingRows.filter { $0.row.performance.eventPlace == stage.id }
            let nextStart = now.flatMap { now in
                performances.compactMap(\.start).filter { now < $0 }.min()
            }
            let next = nextStart.map { start in
                performances.filter { $0.start == start }
            } ?? []
            return (
                row: StageDashboardRow(
                    stage: stage,
                    nowPlayingRows: current.map(\.row),
                    comingNextRows: next.map(\.row)
                ),
                nextStart: nextStart
            )
        }
        let orderedStageRows = stageRows.enumerated().sorted { lhs, rhs in
            switch (lhs.element.nextStart, rhs.element.nextStart) {
            case let (lhsStart?, rhsStart?) where lhsStart != rhsStart:
                return lhsStart < rhsStart
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.offset < rhs.offset
            }
        }
        .map(\.element.row)

        return Self(
            stageRows: orderedStageRows,
            featureRows: EventSearchFeature.indexedFeatures.map(FeatureShortcutRow.init(feature:)),
            channelRows: channels.map(ChannelShortcutRow.init(channel:)),
            nowPlayingRows: nowPlayingRows.map(\.row),
            comingNextRows: comingNextRows.map(\.row)
        )
    }
}

@Selection
public struct PerformanceDashboardRow: Equatable, Identifiable, Sendable {
    public let performance: ProgramItem
    public let stage: EventPlace?

    public var id: ProgramItem.ID { performance.id }
    public var performanceID: ProgramItem.ID { performance.id }
    public var title: String { performance.title }
}

extension PerformanceDashboardRow {
    public static func all(eventID: Event.ID) -> some Statement<PerformanceDashboardRow> {
        ProgramItem
            .where { $0.event.eq(eventID) }
            .leftJoin(EventPlace.all) { item, place in
                item.eventPlace.eq(place.id).and(place.event.eq(eventID))
            }
            .order { item, _ in
                (item.startsAt.asc(nulls: .last), item.title.collate(.nocase))
            }
            .select { item, place -> PerformanceDashboardRow.Columns in
                PerformanceDashboardRow.Columns(performance: item, stage: place)
            }
    }
}

public struct StageDashboardRow: Equatable, Identifiable, Sendable {
    public init(
        stage: EventPlace,
        nowPlayingRows: [PerformanceDashboardRow] = [],
        comingNextRows: [PerformanceDashboardRow] = []
    ) {
        self.stage = stage
        self.nowPlayingRows = nowPlayingRows
        self.comingNextRows = comingNextRows
    }

    public var id: EventPlace.ID { stage.id }
    public var stage: EventPlace
    public var nowPlayingRows: [PerformanceDashboardRow]
    public var comingNextRows: [PerformanceDashboardRow]
}

public struct FeatureShortcutRow: Equatable, Identifiable, Sendable {
    public init(feature: EventSearchFeature) { self.feature = feature }

    public var id: EventSearchFeature.ID { feature.id }
    public var feature: EventSearchFeature
}

public struct ChannelShortcutRow: Equatable, Identifiable, Sendable {
    public init(channel: Social.Category) { self.channel = channel }

    public var id: Social.Category.ID { channel.id }
    public var channel: Social.Category
}
