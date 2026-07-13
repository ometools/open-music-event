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

    public static func fetch(
        eventID: OME.Event.ID,
        db: Database
    ) throws -> Self {
        try fetch(eventID: eventID, now: nil, db: db)
    }

    public static func fetch(
        eventID: OME.Event.ID,
        now: Date,
        db: Database
    ) throws -> Self {
        try fetch(eventID: eventID, now: Optional(now), db: db)
    }

    private static func fetch(
        eventID: OME.Event.ID,
        now: Date?,
        db: Database
    ) throws -> Self {
        let stages = try OME.Stage
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { ($0.sortIndex.asc(nulls: .last), $0.name.collate(.nocase)) }
            .fetchAll(db)

        let channels = try OME.Channel
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { ($0.sortIndex.asc(nulls: .last), $0.name.collate(.nocase)) }
            .fetchAll(db)

        let performanceRows: [PerformanceDashboardRow]
        let nowPlayingRows: [PerformanceDashboardRow]
        let comingNextRows: [PerformanceDashboardRow]
        if let now {
            performanceRows = try PerformanceDashboardRow.all(eventID: eventID).fetchAll(db)
            nowPlayingRows = performanceRows.filter {
                $0.performance.startTime <= now && now < $0.performance.endTime
            }
            let comingNextStartTime = performanceRows
                .lazy
                .map(\.performance.startTime)
                .filter { now < $0 }
                .min()
            comingNextRows = comingNextStartTime.map { startTime in
                performanceRows.filter { $0.performance.startTime == startTime }
            } ?? []
        } else {
            performanceRows = []
            nowPlayingRows = []
            comingNextRows = []
        }

        return Self(
            stageRows: stages.map(StageDashboardRow.init(stage:)),
            featureRows: EventSearchFeature.indexedFeatures.map(FeatureShortcutRow.init(feature:)),
            channelRows: channels.map(ChannelShortcutRow.init(channel:)),
            nowPlayingRows: nowPlayingRows,
            comingNextRows: comingNextRows
        )
    }
}

@Selection
public struct PerformanceDashboardRow: Equatable, Identifiable, Sendable {
    public let performance: OME.Performance
    public let stage: OME.Stage?

    public var id: OME.Performance.ID {
        performance.id
    }

    public var performanceID: OME.ID<OME.Performance> {
        performance.id.performanceID
    }

    public var title: String {
        performance.title
    }
}

extension PerformanceDashboardRow {
    public static func all(
        eventID: OME.Event.ID
    ) -> some Statement<PerformanceDashboardRow> {
        OME.Performance
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .leftJoin(OME.Stage.all) { performance, stage in
                stage.id.organizerID.eq(eventID.organizerID)
                    .and(stage.id.eventID.eq(eventID.eventID))
                    .and(stage.id.stageID.eq(performance.stageID))
            }
            .order { performance, _ in
                (performance.startTime, performance.title.collate(.nocase))
            }
            .select { performance, stage -> PerformanceDashboardRow.Columns in
                PerformanceDashboardRow.Columns(
                    performance: performance,
                    stage: stage
                )
            }
    }
}

public struct StageDashboardRow: Equatable, Identifiable, Sendable {
    public init(stage: OME.Stage) {
        self.stage = stage
    }

    public var id: OME.Stage.ID { stage.id }
    public var stage: OME.Stage
}

public struct FeatureShortcutRow: Equatable, Identifiable, Sendable {
    public init(feature: EventSearchFeature) {
        self.feature = feature
    }

    public var id: EventSearchFeature.ID { feature.id }
    public var feature: EventSearchFeature
}

public struct ChannelShortcutRow: Equatable, Identifiable, Sendable {
    public init(channel: OME.Channel) {
        self.channel = channel
    }

    public var id: OME.Channel.ID { channel.id }
    public var channel: OME.Channel
}
