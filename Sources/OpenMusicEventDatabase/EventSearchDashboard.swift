import OpenMusicEventLexicon
import SQLiteData
import Tagged

public struct EventSearchDashboard: Equatable, Sendable {
    public init(
        stageRows: [StageDashboardRow],
        featureRows: [FeatureShortcutRow],
        channelRows: [ChannelShortcutRow]
    ) {
        self.stageRows = stageRows
        self.featureRows = featureRows
        self.channelRows = channelRows
    }

    public var stageRows: [StageDashboardRow]
    public var featureRows: [FeatureShortcutRow]
    public var channelRows: [ChannelShortcutRow]

    public static func fetch(
        eventID: OME.Event.ID,
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

        return Self(
            stageRows: stages.map(StageDashboardRow.init(stage:)),
            featureRows: EventSearchFeature.indexedFeatures.map(FeatureShortcutRow.init(feature:)),
            channelRows: channels.map(ChannelShortcutRow.init(channel:))
        )
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
