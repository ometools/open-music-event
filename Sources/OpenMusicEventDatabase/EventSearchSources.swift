import OpenMusicEventLexicon
import SQLiteData

public protocol EventSearchSource {
    static func installTriggers(in db: Database) throws
    static func rebuild(in db: Database) throws
}

public enum EventSearchSources {
    public static func installTriggers(in db: Database) throws {
        try ChannelEventSearchSource.installTriggers(in: db)
        try ContributorEventSearchSource.installTriggers(in: db)
        try FeatureEventSearchSource.installTriggers(in: db)
        try PerformanceEventSearchSource.installTriggers(in: db)
        try StageEventSearchSource.installTriggers(in: db)
    }

    public static func rebuild(in db: Database) throws {
        try ChannelEventSearchSource.rebuild(in: db)
        try ContributorEventSearchSource.rebuild(in: db)
        try FeatureEventSearchSource.rebuild(in: db)
        try PerformanceEventSearchSource.rebuild(in: db)
        try StageEventSearchSource.rebuild(in: db)
    }
}

public enum ChannelEventSearchSource: EventSearchSource {
    public static func installTriggers(in db: Database) throws {
        try OME.Channel
            .createTemporaryTrigger(
                "channels_eventSearchDocuments_insert",
                ifNotExists: true,
                after: .insert { new in
                    insertDocument(for: new)
                }
            )
            .execute(db)

        try OME.Channel
            .createTemporaryTrigger(
                "channels_eventSearchDocuments_update",
                ifNotExists: true,
                after: .update { old, new in
                    deleteDocument(for: old)
                    insertDocument(for: new)
                }
            )
            .execute(db)

        try OME.Channel
            .createTemporaryTrigger(
                "channels_eventSearchDocuments_delete",
                ifNotExists: true,
                after: .delete { old in
                    deleteDocument(for: old)
                }
            )
            .execute(db)
    }

    public static func rebuild(in db: Database) throws {
        try EventSearchDocument
            .where { $0.kind.eq(EventSearchDocument.Kind.channel) }
            .delete()
            .execute(db)

        try #sql("""
            INSERT INTO "eventSearchDocuments" (
              "stableID", "organizerID", "eventID", "kind", "title", "subtitle", "body", "keywords", "target", "baseRank"
            )
            SELECT
              'channel:' || "organizerID" || ':' || "eventID" || ':' || "channelID",
              "organizerID", "eventID", 'channel', "name", 'Comms', NULLIF("description", ''),
              'channel announcements updates communications',
              json_object('channel', json_object('_0', "channelID")),
              700
            FROM "channels"
            """).execute(db)
    }

    private static func deleteDocument(
        for channel: TemporaryTrigger<OME.Channel>.Operation.Old
    ) -> some Statement<Void> {
        EventSearchDocument
            .where { $0.stableID.eq(stableID(for: channel)) }
            .delete()
    }

    private static func insertDocument(
        for channel: TemporaryTrigger<OME.Channel>.Operation.New
    ) -> some Statement<Void> {
        #sql("""
            INSERT INTO "eventSearchDocuments" (
              "stableID", "organizerID", "eventID", "kind", "title", "subtitle", "body", "keywords", "target", "baseRank"
            ) VALUES (
              'channel:' || \(channel.id.organizerID) || ':' || \(channel.id.eventID) || ':' || \(channel.id.channelID),
              \(channel.id.organizerID), \(channel.id.eventID), 'channel', \(channel.name), 'Comms', NULLIF(\(channel.description), ''),
              'channel announcements updates communications',
              json_object('channel', json_object('_0', \(channel.id.channelID))),
              700
            )
            """)
    }

    private static func columns(
        for channel: OME.Channel.TableColumns
    ) -> EventSearchDocument.Columns {
        EventSearchDocument.Columns(
            id: #sql("NULL", as: EventSearchDocument.ID.self),
            stableID: stableID(for: channel),
            organizerID: channel.id.organizerID,
            eventID: channel.id.eventID,
            kind: #sql("'channel'", as: EventSearchDocument.Kind.self),
            title: channel.name,
            subtitle: #sql("'Comms'", as: String?.self),
            body: #sql("NULLIF(\(channel.description), '')", as: String?.self),
            keywords: #sql("'channel announcements updates communications'", as: String.self),
            target: target(for: channel),
            baseRank: #sql("700", as: Int.self)
        )
    }

    private static func columns(
        for channel: TemporaryTrigger<OME.Channel>.Operation.New
    ) -> EventSearchDocument.Columns {
        EventSearchDocument.Columns(
            id: #sql("NULL", as: EventSearchDocument.ID.self),
            stableID: stableID(for: channel),
            organizerID: channel.id.organizerID,
            eventID: channel.id.eventID,
            kind: #sql("'channel'", as: EventSearchDocument.Kind.self),
            title: channel.name,
            subtitle: #sql("'Comms'", as: String?.self),
            body: #sql("NULLIF(\(channel.description), '')", as: String?.self),
            keywords: #sql("'channel announcements updates communications'", as: String.self),
            target: target(for: channel),
            baseRank: #sql("700", as: Int.self)
        )
    }

    private static func stableID(
        for channel: OME.Channel.TableColumns
    ) -> some QueryExpression<EventSearchDocument.StableID> {
        #sql(
            "'channel:' || \(channel.id.organizerID) || ':' || \(channel.id.eventID) || ':' || \(channel.id.channelID)",
            as: EventSearchDocument.StableID.self
        )
    }

    private static func stableID(
        for channel: TemporaryTrigger<OME.Channel>.Operation.New
    ) -> some QueryExpression<EventSearchDocument.StableID> {
        #sql(
            "'channel:' || \(channel.id.organizerID) || ':' || \(channel.id.eventID) || ':' || \(channel.id.channelID)",
            as: EventSearchDocument.StableID.self
        )
    }

    private static func stableID(
        for channel: TemporaryTrigger<OME.Channel>.Operation.Old
    ) -> some QueryExpression<EventSearchDocument.StableID> {
        #sql(
            "'channel:' || \(channel.id.organizerID) || ':' || \(channel.id.eventID) || ':' || \(channel.id.channelID)",
            as: EventSearchDocument.StableID.self
        )
    }

    private static func target(
        for channel: OME.Channel.TableColumns
    ) -> some QueryExpression<EventSearchDocument.Target.JSONRepresentation> {
        #sql(
            "json_object('channel', json_object('_0', \(channel.id.channelID)))",
            as: EventSearchDocument.Target.JSONRepresentation.self
        )
    }

    private static func target(
        for channel: TemporaryTrigger<OME.Channel>.Operation.New
    ) -> some QueryExpression<EventSearchDocument.Target.JSONRepresentation> {
        #sql(
            "json_object('channel', json_object('_0', \(channel.id.channelID)))",
            as: EventSearchDocument.Target.JSONRepresentation.self
        )
    }
}

public enum ContributorEventSearchSource: EventSearchSource {
    public static func installTriggers(in db: Database) throws {
        try OME.Contributor
            .createTemporaryTrigger(
                "contributors_eventSearchDocuments_insert",
                ifNotExists: true,
                after: .insert { new in
                    insertDocument(for: new)
                }
            )
            .execute(db)

        try OME.Contributor
            .createTemporaryTrigger(
                "contributors_eventSearchDocuments_update",
                ifNotExists: true,
                after: .update { old, new in
                    deleteDocument(for: old)
                    insertDocument(for: new)
                }
            )
            .execute(db)

        try OME.Contributor
            .createTemporaryTrigger(
                "contributors_eventSearchDocuments_delete",
                ifNotExists: true,
                after: .delete { old in
                    deleteDocument(for: old)
                }
            )
            .execute(db)
    }

    public static func rebuild(in db: Database) throws {
        try EventSearchDocument
            .where { $0.kind.eq(EventSearchDocument.Kind.contributor) }
            .delete()
            .execute(db)

        try #sql("""
            INSERT INTO "eventSearchDocuments" (
              "stableID", "organizerID", "eventID", "kind", "title", "subtitle", "body", "keywords", "target", "baseRank"
            )
            SELECT
              'contributor:' || "organizerID" || ':' || "eventID" || ':' || "contributorID",
              "organizerID", "eventID", 'contributor', "name", 'Artist', "bio",
              'artist contributor performer lineup',
              json_object('contributor', json_object('_0', "contributorID")),
              850
            FROM "contributors"
            """).execute(db)
    }

    private static func deleteDocument(
        for contributor: TemporaryTrigger<OME.Contributor>.Operation.Old
    ) -> some Statement<Void> {
        EventSearchDocument
            .where { $0.stableID.eq(stableID(for: contributor)) }
            .delete()
    }

    private static func insertDocument(
        for contributor: TemporaryTrigger<OME.Contributor>.Operation.New
    ) -> some Statement<Void> {
        #sql("""
            INSERT INTO "eventSearchDocuments" (
              "stableID", "organizerID", "eventID", "kind", "title", "subtitle", "body", "keywords", "target", "baseRank"
            ) VALUES (
              'contributor:' || \(contributor.id.organizerID) || ':' || \(contributor.id.eventID) || ':' || \(contributor.id.contributorID),
              \(contributor.id.organizerID), \(contributor.id.eventID), 'contributor', \(contributor.name), 'Artist', \(contributor.bio),
              'artist contributor performer lineup',
              json_object('contributor', json_object('_0', \(contributor.id.contributorID))),
              850
            )
            """)
    }

    private static func columns(
        for contributor: OME.Contributor.TableColumns
    ) -> EventSearchDocument.Columns {
        EventSearchDocument.Columns(
            id: #sql("NULL", as: EventSearchDocument.ID.self),
            stableID: stableID(for: contributor),
            organizerID: contributor.id.organizerID,
            eventID: contributor.id.eventID,
            kind: #sql("'contributor'", as: EventSearchDocument.Kind.self),
            title: contributor.name,
            subtitle: #sql("'Artist'", as: String?.self),
            body: contributor.bio,
            keywords: #sql("'artist contributor performer lineup'", as: String.self),
            target: target(for: contributor),
            baseRank: #sql("850", as: Int.self)
        )
    }

    private static func columns(
        for contributor: TemporaryTrigger<OME.Contributor>.Operation.New
    ) -> EventSearchDocument.Columns {
        EventSearchDocument.Columns(
            id: #sql("NULL", as: EventSearchDocument.ID.self),
            stableID: stableID(for: contributor),
            organizerID: contributor.id.organizerID,
            eventID: contributor.id.eventID,
            kind: #sql("'contributor'", as: EventSearchDocument.Kind.self),
            title: contributor.name,
            subtitle: #sql("'Artist'", as: String?.self),
            body: contributor.bio,
            keywords: #sql("'artist contributor performer lineup'", as: String.self),
            target: target(for: contributor),
            baseRank: #sql("850", as: Int.self)
        )
    }

    private static func stableID(
        for contributor: OME.Contributor.TableColumns
    ) -> some QueryExpression<EventSearchDocument.StableID> {
        #sql(
            "'contributor:' || \(contributor.id.organizerID) || ':' || \(contributor.id.eventID) || ':' || \(contributor.id.contributorID)",
            as: EventSearchDocument.StableID.self
        )
    }

    private static func stableID(
        for contributor: TemporaryTrigger<OME.Contributor>.Operation.New
    ) -> some QueryExpression<EventSearchDocument.StableID> {
        #sql(
            "'contributor:' || \(contributor.id.organizerID) || ':' || \(contributor.id.eventID) || ':' || \(contributor.id.contributorID)",
            as: EventSearchDocument.StableID.self
        )
    }

    private static func stableID(
        for contributor: TemporaryTrigger<OME.Contributor>.Operation.Old
    ) -> some QueryExpression<EventSearchDocument.StableID> {
        #sql(
            "'contributor:' || \(contributor.id.organizerID) || ':' || \(contributor.id.eventID) || ':' || \(contributor.id.contributorID)",
            as: EventSearchDocument.StableID.self
        )
    }

    private static func target(
        for contributor: OME.Contributor.TableColumns
    ) -> some QueryExpression<EventSearchDocument.Target.JSONRepresentation> {
        #sql(
            "json_object('contributor', json_object('_0', \(contributor.id.contributorID)))",
            as: EventSearchDocument.Target.JSONRepresentation.self
        )
    }

    private static func target(
        for contributor: TemporaryTrigger<OME.Contributor>.Operation.New
    ) -> some QueryExpression<EventSearchDocument.Target.JSONRepresentation> {
        #sql(
            "json_object('contributor', json_object('_0', \(contributor.id.contributorID)))",
            as: EventSearchDocument.Target.JSONRepresentation.self
        )
    }
}

public enum FeatureEventSearchSource: EventSearchSource {
    public static func installTriggers(in db: Database) throws {
        try OME.Event
            .createTemporaryTrigger(
                "events_eventSearchDocuments_insert",
                ifNotExists: true,
                after: .insert { new in
                    deleteDocuments(for: new)
                    insertDocuments(for: new)
                }
            )
            .execute(db)

        try OME.Event
            .createTemporaryTrigger(
                "events_eventSearchDocuments_update",
                ifNotExists: true,
                after: .update { old, new in
                    deleteDocuments(for: old)
                    insertDocuments(for: new)
                }
            )
            .execute(db)

        try OME.Event
            .createTemporaryTrigger(
                "events_eventSearchDocuments_delete",
                ifNotExists: true,
                after: .delete { old in
                    deleteDocuments(for: old)
                }
            )
            .execute(db)
    }

    public static func rebuild(in db: Database) throws {
        try EventSearchDocument
            .where { $0.kind.eq(EventSearchDocument.Kind.feature) }
            .delete()
            .execute(db)

        for feature in EventSearchFeature.indexedFeatures {
            try insertDocuments(feature: feature)
                .execute(db)
        }
    }

    private static func deleteDocuments(
        for event: TemporaryTrigger<OME.Event>.Operation.New
    ) -> some Statement<Void> {
        EventSearchDocument
            .where { $0.kind.eq(EventSearchDocument.Kind.feature) }
            .where { $0.organizerID.eq(event.id.organizerID) }
            .where { $0.eventID.eq(event.id.eventID) }
            .delete()
    }

    private static func deleteDocuments(
        for event: TemporaryTrigger<OME.Event>.Operation.Old
    ) -> some Statement<Void> {
        EventSearchDocument
            .where { $0.kind.eq(EventSearchDocument.Kind.feature) }
            .where { $0.organizerID.eq(event.id.organizerID) }
            .where { $0.eventID.eq(event.id.eventID) }
            .delete()
    }

    private static func insertDocuments(
        for event: TemporaryTrigger<OME.Event>.Operation.New
    ) -> some Statement<Void> {
        EventSearchDocument.insert {
            (
                $0.stableID,
                $0.organizerID,
                $0.eventID,
                $0.kind,
                $0.title,
                $0.subtitle,
                $0.body,
                $0.keywords,
                $0.target,
                $0.baseRank
            )
        } values: {
            for feature in EventSearchFeature.indexedFeatures {
                (
                    stableID(for: event, featureID: feature.id),
                    event.id.organizerID,
                    event.id.eventID,
                    featureKind(),
                    text(feature.title),
                    optionalText(feature.subtitle),
                    optionalText(feature.body),
                    text(feature.keywords),
                    target(forFeatureID: feature.id),
                    integer(feature.baseRank)
                )
            }
        }
    }

    private static func insertDocuments(
        feature: EventSearchFeature
    ) -> some Statement<Void> {
        EventSearchDocument.insert {
            (
                $0.stableID,
                $0.organizerID,
                $0.eventID,
                $0.kind,
                $0.title,
                $0.subtitle,
                $0.body,
                $0.keywords,
                $0.target,
                $0.baseRank
            )
        } select: {
            OME.Event.select { event in
                (
                    stableID(for: event, featureID: feature.id),
                    event.id.organizerID,
                    event.id.eventID,
                    featureKind(),
                    text(feature.title),
                    optionalText(feature.subtitle),
                    optionalText(feature.body),
                    text(feature.keywords),
                    target(forFeatureID: feature.id),
                    integer(feature.baseRank)
                )
            }
        }
    }

    private static func stableID(
        for event: OME.Event.TableColumns,
        featureID: EventSearchFeature.ID
    ) -> some QueryExpression<EventSearchDocument.StableID> {
        #sql(
            """
            'feature:' || \(event.id.organizerID) || ':' || \(event.id.eventID) || ':' || \(quote: featureID.rawValue, delimiter: .text)
            """,
            as: EventSearchDocument.StableID.self
        )
    }

    private static func stableID(
        for event: TemporaryTrigger<OME.Event>.Operation.New,
        featureID: EventSearchFeature.ID
    ) -> some QueryExpression<EventSearchDocument.StableID> {
        #sql(
            """
            'feature:' || \(event.id.organizerID) || ':' || \(event.id.eventID) || ':' || \(quote: featureID.rawValue, delimiter: .text)
            """,
            as: EventSearchDocument.StableID.self
        )
    }

    private static func featureKind() -> some QueryExpression<EventSearchDocument.Kind> {
        #sql("'feature'", as: EventSearchDocument.Kind.self)
    }

    private static func text(_ value: String) -> some QueryExpression<String> {
        #sql("\(quote: value, delimiter: .text)", as: String.self)
    }

    private static func optionalText(_ value: String?) -> some QueryExpression<String?> {
        guard let value
        else { return #sql("NULL", as: String?.self) }

        return #sql("\(quote: value, delimiter: .text)", as: String?.self)
    }

    private static func target(
        forFeatureID featureID: EventSearchFeature.ID
    ) -> some QueryExpression<EventSearchDocument.Target.JSONRepresentation> {
        #sql(
            "json_object('feature', json_object('_0', \(quote: featureID.rawValue, delimiter: .text)))",
            as: EventSearchDocument.Target.JSONRepresentation.self
        )
    }

    private static func integer(_ value: Int) -> some QueryExpression<Int> {
        #sql("\(raw: value)", as: Int.self)
    }
}

public enum PerformanceEventSearchSource: EventSearchSource {
    public static func installTriggers(in db: Database) throws {
        try OME.Performance
            .createTemporaryTrigger(
                "performances_eventSearchDocuments_insert",
                ifNotExists: true,
                after: .insert { new in
                    insertDocument(for: new)
                }
            )
            .execute(db)

        try OME.Performance
            .createTemporaryTrigger(
                "performances_eventSearchDocuments_update",
                ifNotExists: true,
                after: .update { old, new in
                    deleteDocument(for: old)
                    insertDocument(for: new)
                }
            )
            .execute(db)

        try OME.Performance
            .createTemporaryTrigger(
                "performances_eventSearchDocuments_delete",
                ifNotExists: true,
                after: .delete { old in
                    deleteDocument(for: old)
                }
            )
            .execute(db)
    }

    public static func rebuild(in db: Database) throws {
        try EventSearchDocument
            .where { $0.kind.eq(EventSearchDocument.Kind.performance) }
            .delete()
            .execute(db)

        try #sql("""
            INSERT INTO "eventSearchDocuments" (
              "stableID", "organizerID", "eventID", "kind", "title", "subtitle", "body", "keywords", "target", "baseRank"
            )
            SELECT
              'performance:' || "organizerID" || ':' || "eventID" || ':' || "performanceID",
              "organizerID", "eventID", 'performance', "title", 'Performance', "description",
              'performance set show music lineup',
              json_object('performance', json_object('_0', "performanceID")),
              950
            FROM "performances"
            """).execute(db)
    }

    private static func deleteDocument(
        for performance: TemporaryTrigger<OME.Performance>.Operation.Old
    ) -> some Statement<Void> {
        EventSearchDocument
            .where { $0.stableID.eq(stableID(for: performance)) }
            .delete()
    }

    private static func insertDocument(
        for performance: TemporaryTrigger<OME.Performance>.Operation.New
    ) -> some Statement<Void> {
        #sql("""
            INSERT INTO "eventSearchDocuments" (
              "stableID", "organizerID", "eventID", "kind", "title", "subtitle", "body", "keywords", "target", "baseRank"
            ) VALUES (
              'performance:' || \(performance.id.organizerID) || ':' || \(performance.id.eventID) || ':' || \(performance.id.performanceID),
              \(performance.id.organizerID), \(performance.id.eventID), 'performance', \(performance.title), 'Performance', \(performance.description),
              'performance set show music lineup',
              json_object('performance', json_object('_0', \(performance.id.performanceID))),
              950
            )
            """)
    }

    private static func columns(
        for performance: OME.Performance.TableColumns
    ) -> EventSearchDocument.Columns {
        EventSearchDocument.Columns(
            id: #sql("NULL", as: EventSearchDocument.ID.self),
            stableID: stableID(for: performance),
            organizerID: performance.id.organizerID,
            eventID: performance.id.eventID,
            kind: #sql("'performance'", as: EventSearchDocument.Kind.self),
            title: performance.title,
            subtitle: #sql("'Performance'", as: String?.self),
            body: performance.description,
            keywords: #sql("'performance set show music lineup'", as: String.self),
            target: target(for: performance),
            baseRank: #sql("950", as: Int.self)
        )
    }

    private static func columns(
        for performance: TemporaryTrigger<OME.Performance>.Operation.New
    ) -> EventSearchDocument.Columns {
        EventSearchDocument.Columns(
            id: #sql("NULL", as: EventSearchDocument.ID.self),
            stableID: stableID(for: performance),
            organizerID: performance.id.organizerID,
            eventID: performance.id.eventID,
            kind: #sql("'performance'", as: EventSearchDocument.Kind.self),
            title: performance.title,
            subtitle: #sql("'Performance'", as: String?.self),
            body: performance.description,
            keywords: #sql("'performance set show music lineup'", as: String.self),
            target: target(for: performance),
            baseRank: #sql("950", as: Int.self)
        )
    }

    private static func stableID(
        for performance: OME.Performance.TableColumns
    ) -> some QueryExpression<EventSearchDocument.StableID> {
        #sql(
            "'performance:' || \(performance.id.organizerID) || ':' || \(performance.id.eventID) || ':' || \(performance.id.performanceID)",
            as: EventSearchDocument.StableID.self
        )
    }

    private static func stableID(
        for performance: TemporaryTrigger<OME.Performance>.Operation.New
    ) -> some QueryExpression<EventSearchDocument.StableID> {
        #sql(
            "'performance:' || \(performance.id.organizerID) || ':' || \(performance.id.eventID) || ':' || \(performance.id.performanceID)",
            as: EventSearchDocument.StableID.self
        )
    }

    private static func stableID(
        for performance: TemporaryTrigger<OME.Performance>.Operation.Old
    ) -> some QueryExpression<EventSearchDocument.StableID> {
        #sql(
            "'performance:' || \(performance.id.organizerID) || ':' || \(performance.id.eventID) || ':' || \(performance.id.performanceID)",
            as: EventSearchDocument.StableID.self
        )
    }

    private static func target(
        for performance: OME.Performance.TableColumns
    ) -> some QueryExpression<EventSearchDocument.Target.JSONRepresentation> {
        #sql(
            "json_object('performance', json_object('_0', \(performance.id.performanceID)))",
            as: EventSearchDocument.Target.JSONRepresentation.self
        )
    }

    private static func target(
        for performance: TemporaryTrigger<OME.Performance>.Operation.New
    ) -> some QueryExpression<EventSearchDocument.Target.JSONRepresentation> {
        #sql(
            "json_object('performance', json_object('_0', \(performance.id.performanceID)))",
            as: EventSearchDocument.Target.JSONRepresentation.self
        )
    }
}

public enum StageEventSearchSource: EventSearchSource {
    public static func installTriggers(in db: Database) throws {
        try OME.Stage
            .createTemporaryTrigger(
                "stages_eventSearchDocuments_insert",
                ifNotExists: true,
                after: .insert { new in
                    deleteDocument(for: new)
                    insertDocument(for: new)
                }
            )
            .execute(db)

        try OME.Stage
            .createTemporaryTrigger(
                "stages_eventSearchDocuments_update",
                ifNotExists: true,
                after: .update { old, new in
                    deleteDocument(for: old)
                    insertDocument(for: new)
                }
            )
            .execute(db)

        try OME.Stage
            .createTemporaryTrigger(
                "stages_eventSearchDocuments_delete",
                ifNotExists: true,
                after: .delete { old in
                    deleteDocument(for: old)
                }
            )
            .execute(db)
    }

    public static func rebuild(in db: Database) throws {
        try EventSearchDocument
            .where { $0.kind.eq(EventSearchDocument.Kind.stage) }
            .delete()
            .execute(db)

        try EventSearchDocument.insert {
            (
                $0.stableID,
                $0.organizerID,
                $0.eventID,
                $0.kind,
                $0.title,
                $0.subtitle,
                $0.body,
                $0.keywords,
                $0.target,
                $0.baseRank
            )
        } select: {
            OME.Stage.select { stage in
                (
                    stableID(for: stage),
                    stage.id.organizerID,
                    stage.id.eventID,
                    #sql("'stage'", as: EventSearchDocument.Kind.self),
                    stage.name,
                    #sql("'Stage'", as: String?.self),
                    #sql("NULL", as: String?.self),
                    #sql("'stage'", as: String.self),
                    target(for: stage),
                    #sql("900", as: Int.self)
                )
            }
        }
        .execute(db)
    }

    private static func deleteDocument(
        for stage: TemporaryTrigger<OME.Stage>.Operation.New
    ) -> some Statement<Void> {
        EventSearchDocument
            .where { $0.stableID.eq(stableID(for: stage)) }
            .delete()
    }

    private static func deleteDocument(
        for stage: TemporaryTrigger<OME.Stage>.Operation.Old
    ) -> some Statement<Void> {
        EventSearchDocument
            .where { $0.stableID.eq(stableID(for: stage)) }
            .delete()
    }

    private static func insertDocument(
        for stage: TemporaryTrigger<OME.Stage>.Operation.New
    ) -> some Statement<Void> {
        EventSearchDocument.insert {
            (
                $0.stableID,
                $0.organizerID,
                $0.eventID,
                $0.kind,
                $0.title,
                $0.subtitle,
                $0.body,
                $0.keywords,
                $0.target,
                $0.baseRank
            )
        } values: {
            (
                stableID(for: stage),
                stage.id.organizerID,
                stage.id.eventID,
                #sql("'stage'", as: EventSearchDocument.Kind.self),
                stage.name,
                #sql("'Stage'", as: String?.self),
                #sql("NULL", as: String?.self),
                #sql("'stage'", as: String.self),
                target(for: stage),
                #sql("900", as: Int.self)
            )
        }
    }

    private static func stableID(
        for stage: OME.Stage.TableColumns
    ) -> some QueryExpression<EventSearchDocument.StableID> {
        #sql(
            """
            'stage:' || \(stage.id.organizerID) || ':' || \(stage.id.eventID) || ':' || \(stage.id.stageID)
            """,
            as: EventSearchDocument.StableID.self
        )
    }

    private static func stableID(
        for stage: TemporaryTrigger<OME.Stage>.Operation.New
    ) -> some QueryExpression<EventSearchDocument.StableID> {
        #sql(
            """
            'stage:' || \(stage.id.organizerID) || ':' || \(stage.id.eventID) || ':' || \(stage.id.stageID)
            """,
            as: EventSearchDocument.StableID.self
        )
    }

    private static func stableID(
        for stage: TemporaryTrigger<OME.Stage>.Operation.Old
    ) -> some QueryExpression<EventSearchDocument.StableID> {
        #sql(
            """
            'stage:' || \(stage.id.organizerID) || ':' || \(stage.id.eventID) || ':' || \(stage.id.stageID)
            """,
            as: EventSearchDocument.StableID.self
        )
    }

    private static func target(
        for stage: OME.Stage.TableColumns
    ) -> some QueryExpression<EventSearchDocument.Target.JSONRepresentation> {
        #sql(
            "json_object('stage', json_object('_0', \(stage.id.stageID)))",
            as: EventSearchDocument.Target.JSONRepresentation.self
        )
    }

    private static func target(
        for stage: TemporaryTrigger<OME.Stage>.Operation.New
    ) -> some QueryExpression<EventSearchDocument.Target.JSONRepresentation> {
        #sql(
            "json_object('stage', json_object('_0', \(stage.id.stageID)))",
            as: EventSearchDocument.Target.JSONRepresentation.self
        )
    }
}
