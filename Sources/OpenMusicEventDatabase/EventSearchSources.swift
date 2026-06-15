import OpenMusicEventLexicon
import SQLiteData

public protocol EventSearchSource {
    static func installTriggers(in db: Database) throws
    static func rebuild(in db: Database) throws
}

public enum EventSearchSources {
    public static func installTriggers(in db: Database) throws {
        try FeatureEventSearchSource.installTriggers(in: db)
        try StageEventSearchSource.installTriggers(in: db)
    }

    public static func rebuild(in db: Database) throws {
        try FeatureEventSearchSource.rebuild(in: db)
        try StageEventSearchSource.rebuild(in: db)
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
