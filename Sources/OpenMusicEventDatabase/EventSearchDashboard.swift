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
        let performanceRows: [(row: PerformanceDashboardRow, start: Date?, end: Date?)] = try now.map { instantDate in
            let itemTable = ProgramItem.tableName
            let instant = instantDate.timeIntervalSince1970
            let artwork = ContributorArtworkQuery.image(media: Contributor.media.queryFragment)
            return try ProgramItem
                .where { $0.event.eq(eventID) }
                .where { item in
                    #sql(
                        """
                        ((unixepoch(\(item.startsAt), 'subsec') <= \(instant)
                          AND unixepoch(\(item.endsAt), 'subsec') > \(instant))
                         OR unixepoch(\(item.startsAt), 'subsec') = (
                             SELECT MIN(unixepoch(next.startsAt, 'subsec')) FROM \(quote: itemTable) AS next
                             WHERE next.event = \(eventID) AND next.eventPlace IS \(item.eventPlace)
                               AND unixepoch(next.startsAt, 'subsec') > \(instant))
                         OR unixepoch(\(item.startsAt), 'subsec') = (
                             SELECT MIN(unixepoch(next.startsAt, 'subsec')) FROM \(quote: itemTable) AS next
                             WHERE next.event = \(eventID) AND unixepoch(next.startsAt, 'subsec') > \(instant)))
                        """, as: Bool.self
                    )
                }
                .order { ($0.startsAt.asc(nulls: .last), $0.title.collate(.nocase)) }
                .select { item -> DashboardItem.Columns in
                    .init(performance: item, artwork: #sql(
                        """
                        (SELECT \(artwork) FROM \(Contributor.self)
                         WHERE \(Contributor.event) = \(eventID) AND \(Contributor.id) = (
                           SELECT json_extract(value, '$.contributor') FROM json_each(\(item.credits))
                           WHERE json_extract(value, '$.billing') = 'primary'
                             AND json_extract(value, '$.contributor') IS NOT NULL
                           ORDER BY CAST(key AS INTEGER) LIMIT 1
                         ))
                        """, as: OME.Image.JSONRepresentation?.self
                    ))
                }
                .fetchAll(db)
                .map { entry in
                    let item = entry.performance
                    return (
                        row: PerformanceDashboardRow(
                            performance: item,
                            stage: item.eventPlace.flatMap { placesByID[$0] },
                            artwork: entry.artwork
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
    @Column(as: OME.Image.JSONRepresentation?.self)
    public var artwork: OME.Image? = nil

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
                PerformanceDashboardRow.Columns(performance: item, stage: place, artwork: #sql("NULL", as: OME.Image.JSONRepresentation?.self))
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

@Selection
private struct DashboardItem {
    let performance: ProgramItem
    @Column(as: OME.Image.JSONRepresentation?.self)
    let artwork: OME.Image?
}
