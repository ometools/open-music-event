import ATProto
import CustomDump
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

struct DatabaseMigrationTests {
    @Test
    func eventReportingLinkMigrationAddsNullableColumn() async throws {
        let database = try SQLiteData.defaultDatabase()

        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        try await database.read { db in
            let type = try String.fetchOne(
                db,
                sql: #"SELECT "type" FROM pragma_table_info('events') WHERE "name" = 'reportingLink'"#
            )
            let isNotNull = try Int.fetchOne(
                db,
                sql: #"SELECT "notnull" FROM pragma_table_info('events') WHERE "name" = 'reportingLink'"#
            )

            #expect(type == "TEXT")
            #expect(isNotNull == 0)
        }
    }

    @Test
    func eventSearchSchemaMigrationCreatesDocumentAndTextTables() async throws {
        let database = try SQLiteData.defaultDatabase()

        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        try await database.read { db in
            #expect(try db.tableExists("eventSearchDocuments"))
            #expect(try db.tableExists("eventSearchText"))

            let documentColumns = try String.fetchAll(
                db,
                sql: #"SELECT "name" FROM pragma_table_info('eventSearchDocuments')"#
            )
            #expect(
                documentColumns == [
                    "id",
                    "stableID",
                    "organizerID",
                    "eventID",
                    "kind",
                    "title",
                    "subtitle",
                    "body",
                    "keywords",
                    "target",
                    "baseRank",
                ]
            )

            let ftsColumns = try String.fetchAll(
                db,
                sql: #"SELECT "name" FROM pragma_table_info('eventSearchText')"#
            )
            #expect(ftsColumns == ["title", "keywords", "subtitle", "body"])
        }
    }

    @Test
    func eventSearchTextSupportsFTSMatching() async throws {
        let database = try SQLiteData.defaultDatabase()

        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        try await database.write { db in
            try EventSearchText.insert {
                EventSearchText(
                    rowid: searchDocumentID(1),
                    title: "Meadow Stage",
                    keywords: "main outdoor stage",
                    subtitle: "Stage",
                    body: "Late night music in the meadow."
                )
            }
            .execute(db)

            let matches = try EventSearchText
                .where { $0.match("meadow") }
                .fetchAll(db)

            expectNoDifference(matches.map(\.id), [searchDocumentID(1)])
        }
    }

    @Test
    func eventSearchTermRejectsBlankQueries() {
        #expect(EventSearchTerm(rawValue: "   ") == nil)
    }

    @Test
    func eventSearchTextTriggersInsertDocumentText() async throws {
        let database = try migratedDatabase()
        let eventID = try await seedSearchEvent(in: database)

        try await database.write { db in
            try EventSearchTextTriggers.install(in: db)
            try insertSearchDocument(
                id: searchDocumentID(1),
                eventID: eventID,
                title: "Meadow Stage",
                subtitle: nil,
                body: nil,
                keywords: "main outdoor stage",
                in: db
            )

            let matches = try EventSearchText
                .where { $0.match("meadow") }
                .fetchAll(db)

            expectNoDifference(matches, [
                EventSearchText(
                    rowid: searchDocumentID(1),
                    title: "Meadow Stage",
                    keywords: "main outdoor stage",
                    subtitle: "",
                    body: ""
                ),
            ])
        }
    }

    @Test
    func eventSearchTextTriggersUpdateDocumentText() async throws {
        let database = try migratedDatabase()
        let eventID = try await seedSearchEvent(in: database)

        try await database.write { db in
            try EventSearchTextTriggers.install(in: db)
            try insertSearchDocument(
                id: searchDocumentID(1),
                eventID: eventID,
                title: "Meadow Stage",
                subtitle: "Stage",
                body: "Music in the meadow.",
                keywords: "main",
                in: db
            )

            try EventSearchDocument
                .find(searchDocumentID(1))
                .update {
                    $0.title = "Forest Stage"
                    $0.subtitle = #bind(nil as String?)
                    $0.body = #bind("Late night music in the trees." as String?)
                    $0.keywords = "woodland stage"
                }
                .execute(db)

            let oldMatches = try EventSearchText
                .where { $0.match("meadow") }
                .fetchAll(db)
            expectNoDifference(oldMatches, [])

            let updatedMatches = try EventSearchText
                .where { $0.match("forest") }
                .fetchAll(db)
            expectNoDifference(updatedMatches, [
                EventSearchText(
                    rowid: searchDocumentID(1),
                    title: "Forest Stage",
                    keywords: "woodland stage",
                    subtitle: "",
                    body: "Late night music in the trees."
                ),
            ])
        }
    }

    @Test
    func eventSearchTextTriggersDeleteDocumentText() async throws {
        let database = try migratedDatabase()
        let eventID = try await seedSearchEvent(in: database)

        try await database.write { db in
            try EventSearchTextTriggers.install(in: db)
            try insertSearchDocument(
                id: searchDocumentID(1),
                eventID: eventID,
                title: "Meadow Stage",
                keywords: "main outdoor stage",
                in: db
            )

            try EventSearchDocument
                .find(searchDocumentID(1))
                .delete()
                .execute(db)

            let matches = try EventSearchText
                .where { $0.match("meadow") }
                .fetchAll(db)

            expectNoDifference(matches, [])
        }
    }

    @Test
    func eventSearchResultsRankTitleAboveBody() async throws {
        let database = try migratedDatabase()
        let eventID = try await seedSearchEvent(in: database)

        try await database.write { db in
            try EventSearchTextTriggers.install(in: db)
            try insertSearchDocument(
                id: searchDocumentID(1),
                stableID: searchStableID("stage:moon"),
                eventID: eventID,
                title: "Moon Stage",
                body: nil,
                keywords: "",
                in: db
            )
            try insertSearchDocument(
                id: searchDocumentID(2),
                stableID: searchStableID("contributor:luna"),
                eventID: eventID,
                title: "Luna",
                body: "Bio with moon installations and late-night visuals.",
                keywords: "",
                in: db
            )

            let term = try #require(EventSearchTerm(rawValue: "moon"))
            let results = try EventSearchIndex.results(matching: term, in: eventID, db: db)

            expectNoDifference(results.map(\.id), [
                searchDocumentID(1),
                searchDocumentID(2),
            ])
            expectNoDifference(results.map(\.rank.field), [
                EventSearchRank.Field.title,
                .body,
            ])
        }
    }

    @Test
    func eventSearchResultsAreScopedToEvent() async throws {
        let database = try migratedDatabase()
        let eventID = try await seedSearchEvent(in: database)
        let otherEventID = try await seedSearchEvent(
            in: database,
            organizerKey: "did:plc:searchother",
            eventKey: "other-event"
        )

        try await database.write { db in
            try EventSearchTextTriggers.install(in: db)
            try insertSearchDocument(
                id: searchDocumentID(1),
                stableID: searchStableID("stage:moon"),
                eventID: eventID,
                title: "Moon Stage",
                in: db
            )
            try insertSearchDocument(
                id: searchDocumentID(2),
                stableID: searchStableID("stage:other-moon"),
                eventID: otherEventID,
                title: "Moon Stage",
                in: db
            )

            let term = try #require(EventSearchTerm(rawValue: "moon"))
            let results = try EventSearchIndex.results(matching: term, in: eventID, db: db)

            expectNoDifference(results.map(\.id), [searchDocumentID(1)])
        }
    }

    @Test
    func eventSearchDashboardStartsWithStageRowsThenFeatureAndChannelRows() async throws {
        let database = try migratedDatabase()
        let eventID = try await seedSearchEvent(in: database)
        let otherEventID = try await seedSearchEvent(
            in: database,
            organizerKey: "did:plc:searchother",
            eventKey: "other-event"
        )

        try await database.write { db in
            try insertStage(
                eventID: eventID,
                stageID: "forest",
                name: "Forest Stage",
                sortIndex: 2,
                in: db
            )
            try insertStage(
                eventID: eventID,
                stageID: "meadow",
                name: "Meadow Stage",
                sortIndex: 1,
                in: db
            )
            try insertStage(
                eventID: eventID,
                stageID: "river",
                name: "River Stage",
                sortIndex: nil,
                in: db
            )
            try insertStage(
                eventID: otherEventID,
                stageID: "other",
                name: "Other Stage",
                sortIndex: 0,
                in: db
            )

            try insertChannel(
                eventID: eventID,
                channelID: "announcements",
                name: "Announcements",
                sortIndex: 2,
                in: db
            )
            try insertChannel(
                eventID: eventID,
                channelID: "general",
                name: "General",
                sortIndex: 1,
                in: db
            )
            try insertChannel(
                eventID: otherEventID,
                channelID: "other-channel",
                name: "Other Channel",
                sortIndex: 0,
                in: db
            )

            let dashboard = try EventSearchDashboard.fetch(eventID: eventID, db: db)

            expectNoDifference(dashboard.stageRows.map(\.id.stageID), [
                localID("meadow"),
                localID("forest"),
                localID("river"),
            ])
            expectNoDifference(
                dashboard.featureRows.map(\.id),
                EventSearchFeature.indexedFeatures.map(\.id)
            )
            expectNoDifference(dashboard.channelRows.map(\.id.channelID), [
                localID("general"),
                localID("announcements"),
            ])
        }
    }

    @Test
    func eventSearchDashboardKeepsUnsortedStageNamesStable() async throws {
        let database = try migratedDatabase()
        let eventID = try await seedSearchEvent(in: database)

        try await database.write { db in
            try insertStage(
                eventID: eventID,
                stageID: "zebra",
                name: "Zebra Stage",
                sortIndex: nil,
                in: db
            )
            try insertStage(
                eventID: eventID,
                stageID: "alpha",
                name: "Alpha Stage",
                sortIndex: nil,
                in: db
            )

            let dashboard = try EventSearchDashboard.fetch(eventID: eventID, db: db)

            expectNoDifference(dashboard.stageRows.map(\.id.stageID), [
                localID("alpha"),
                localID("zebra"),
            ])
        }
    }

    @Test
    func featureSearchSourceRebuildIndexesExistingEvents() async throws {
        let database = try migratedDatabase()
        let eventID = try await seedSearchEvent(in: database)

        try await database.write { db in
            try EventSearchTextTriggers.install(in: db)

            try FeatureEventSearchSource.rebuild(in: db)

            let documents = try featureDocuments(in: db)
            let expectedFeatures = expectedFeatureDocumentsOrder(eventID: eventID)
            expectNoDifference(
                documents.map(\.target),
                expectedFeatures.map { .feature($0.id) }
            )
            expectNoDifference(
                documents.map(\.stableID),
                expectedFeatures.map {
                    featureStableID($0.id, eventID: eventID)
                }
            )
            expectNoDifference(
                documents.map(\.title),
                expectedFeatures.map(\.title)
            )

            let matches = try EventSearchText
                .where { $0.match("schedule") }
                .fetchAll(db)
            #expect(matches.map(\.title) == ["Schedule"])
        }
    }

    @Test
    func featureSearchSourceInsertTriggerIndexesEventFeatures() async throws {
        let database = try migratedDatabase()

        try await database.write { db in
            try EventSearchTextTriggers.install(in: db)
            try FeatureEventSearchSource.installTriggers(in: db)
        }

        let eventID = try await seedSearchEvent(in: database)

        try await database.read { db in
            let documents = try featureDocuments(in: db)
            let expectedFeatures = expectedFeatureDocumentsOrder(eventID: eventID)
            expectNoDifference(
                documents.map(\.stableID),
                expectedFeatures.map {
                    featureStableID($0.id, eventID: eventID)
                }
            )
        }
    }

    @Test
    func featureSearchSourceDeleteTriggerRemovesEventFeatures() async throws {
        let database = try migratedDatabase()

        try await database.write { db in
            try EventSearchTextTriggers.install(in: db)
            try FeatureEventSearchSource.installTriggers(in: db)
        }

        let eventID = try await seedSearchEvent(in: database)

        try await database.write { db in
            try OME.Event
                .find(eventID)
                .delete()
                .execute(db)

            let documents = try featureDocuments(in: db)
            expectNoDifference(documents, [])
        }
    }

    @Test
    func eventSearchResultsFindFeatureShortcuts() async throws {
        let database = try migratedDatabase()
        let eventID = try await seedSearchEvent(in: database)

        try await database.write { db in
            try EventSearchTextTriggers.install(in: db)
            try FeatureEventSearchSource.rebuild(in: db)

            let titleTerm = try #require(EventSearchTerm(rawValue: "schedule"))
            let titleResults = try EventSearchIndex.results(matching: titleTerm, in: eventID, db: db)
            expectNoDifference(titleResults.map(\.document.target), [
                EventSearchDocument.Target.feature(EventSearchFeature.KnownID.schedule),
            ])
            expectNoDifference(titleResults.map(\.rank.field), [
                EventSearchRank.Field.title,
            ])

            let keywordTerm = try #require(EventSearchTerm(rawValue: "announcements"))
            let keywordResults = try EventSearchIndex.results(matching: keywordTerm, in: eventID, db: db)
            expectNoDifference(keywordResults.map(\.document.target), [
                EventSearchDocument.Target.feature(EventSearchFeature.KnownID.communications),
            ])
            expectNoDifference(keywordResults.map(\.rank.field), [
                EventSearchRank.Field.keywords,
            ])
        }
    }

    @Test
    func stageSearchSourceRebuildIndexesExistingStages() async throws {
        let database = try migratedDatabase()
        let eventID = try await seedSearchEvent(in: database)

        try await database.write { db in
            try EventSearchTextTriggers.install(in: db)
            try insertStage(eventID: eventID, stageID: "meadow", name: "Meadow Stage", in: db)

            try EventSearchSources.rebuild(in: db)

            let documents = try EventSearchDocument.fetchAll(db)
            try expectStageSearchDocument(
                documents.filter { $0.kind == .stage },
                eventID: eventID,
                stageID: "meadow",
                title: "Meadow Stage"
            )

            let matches = try EventSearchText
                .where { $0.match("meadow") }
                .fetchAll(db)
            #expect(matches.map(\.title) == ["Meadow Stage"])
        }
    }

    @Test
    func stageSearchSourceInsertTriggerIndexesStage() async throws {
        let database = try migratedDatabase()
        let eventID = try await seedSearchEvent(in: database)

        try await database.write { db in
            try EventSearchTextTriggers.install(in: db)
            try EventSearchSources.installTriggers(in: db)

            try insertStage(eventID: eventID, stageID: "meadow", name: "Meadow Stage", in: db)

            let documents = try EventSearchDocument.fetchAll(db)
            try expectStageSearchDocument(
                documents,
                eventID: eventID,
                stageID: "meadow",
                title: "Meadow Stage"
            )

            let matches = try EventSearchText
                .where { $0.match("meadow") }
                .fetchAll(db)
            #expect(matches.map(\.title) == ["Meadow Stage"])
        }
    }

    @Test
    func stageSearchSourceUpdateTriggerReindexesStage() async throws {
        let database = try migratedDatabase()
        let eventID = try await seedSearchEvent(in: database)
        let stageID = makeStageID("meadow", eventID: eventID)

        try await database.write { db in
            try EventSearchTextTriggers.install(in: db)
            try EventSearchSources.installTriggers(in: db)
            try insertStage(eventID: eventID, stageID: "meadow", name: "Meadow Stage", in: db)

            try OME.Stage
                .find(stageID)
                .update {
                    $0.name = "Forest Stage"
                }
                .execute(db)

            let documents = try EventSearchDocument.fetchAll(db)
            try expectStageSearchDocument(
                documents,
                eventID: eventID,
                stageID: "meadow",
                title: "Forest Stage"
            )

            let oldMatches = try EventSearchText
                .where { $0.match("meadow") }
                .fetchAll(db)
            expectNoDifference(oldMatches, [])

            let updatedMatches = try EventSearchText
                .where { $0.match("forest") }
                .fetchAll(db)
            #expect(updatedMatches.map(\.title) == ["Forest Stage"])
        }
    }

    @Test
    func stageSearchSourceDeleteTriggerRemovesStageDocument() async throws {
        let database = try migratedDatabase()
        let eventID = try await seedSearchEvent(in: database)
        let stageID = makeStageID("meadow", eventID: eventID)

        try await database.write { db in
            try EventSearchTextTriggers.install(in: db)
            try EventSearchSources.installTriggers(in: db)
            try insertStage(eventID: eventID, stageID: "meadow", name: "Meadow Stage", in: db)

            try OME.Stage
                .find(stageID)
                .delete()
                .execute(db)

            let documents = try EventSearchDocument.fetchAll(db)
            expectNoDifference(documents, [])

            let matches = try EventSearchText
                .where { $0.match("meadow") }
                .fetchAll(db)
            expectNoDifference(matches, [])
        }
    }

    @Test
    func contributorSchemaMigrationCreatesTablesWithoutCopyingParticipantRows() async throws {
        let database = try SQLiteData.defaultDatabase()

        try await database.write { db in
            try db.execute(sql: """
                CREATE TABLE "grdb_migrations" (
                  "identifier" TEXT NOT NULL PRIMARY KEY
                )
                """)

            for identifier in Self.oldParticipantSchemaMigrationIdentifiers {
                try db.execute(
                    sql: #"INSERT INTO "grdb_migrations" ("identifier") VALUES (?)"#,
                    arguments: [identifier]
                )
            }

            try db.execute(sql: """
                CREATE TABLE "participants" (
                  "organizerID" TEXT NOT NULL,
                  "eventID" TEXT NOT NULL,
                  "participantID" TEXT NOT NULL,
                  "name" TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                INSERT INTO "participants" ("organizerID", "eventID", "participantID", "name")
                VALUES ('did:plc:organizer', 'event-1', 'artist-one', 'Artist One')
                """)
        }

        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        try await database.read { db in
            #expect(try db.tableExists("contributors"))
            #expect(try db.tableExists("contributorClaims"))
            #expect(try db.tableExists("performanceContributors"))

            let contributorCount = try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "contributors""#)
            #expect(contributorCount == 0)

            let performanceContributorColumns = try String.fetchAll(
                db,
                sql: #"SELECT "name" FROM pragma_table_info('performanceContributors')"#
            )
            #expect(performanceContributorColumns.contains("contributorActor"))
        }
    }

    private static let oldParticipantSchemaMigrationIdentifiers = [
        "Create OpenMusicEvent core schema",
        "Add OpenMusicEvent participant actor policies",
        "Add OpenMusicEvent calendars",
        "Add OpenMusicEvent event reporting links",
        "Create OpenMusicEvent source provenance schema",
        "Create OpenMusicEvent source baseline schema",
        "Create OpenMusicEvent local image blob schema",
        "Allow OpenMusicEvent calendar local image blobs",
    ]
}

private func migratedDatabase() throws -> any DatabaseWriter {
    let database = try SQLiteData.defaultDatabase()
    var migrator = DatabaseMigrator()
    OME.DatabaseMigrations.register(into: &migrator)
    try migrator.migrate(database)
    return database
}

private func seedSearchEvent(
    in database: any DatabaseWriter,
    organizerKey: String = "did:plc:search",
    eventKey: String = "test-event"
) async throws -> OME.Event.ID {
    let organizerID = try #require(OME.Organizer.ID(organizerKey))
    let eventID = OME.Event.ID(
        organizerID: organizerID,
        eventID: localID(eventKey)
    )
    let timeZone = try #require(TimeZone(secondsFromGMT: 0))

    try await database.write { db in
        try OME.Organizer.insert {
            OME.Organizer.Draft(id: organizerID)
        }
        .execute(db)
        try OME.Event.insert {
            OME.Event.Draft(
                id: eventID,
                name: "Search Test Event",
                description: nil,
                startDate: nil,
                endDate: nil,
                status: nil,
                mode: nil,
                locations: nil,
                uris: nil,
                timeZone: timeZone,
                images: nil,
                contactNumbers: nil,
                categoryConfigs: nil
            )
        }
        .execute(db)
    }

    return eventID
}

private func insertSearchDocument(
    id: EventSearchDocument.ID,
    stableID: EventSearchDocument.StableID = searchStableID("stage:meadow"),
    eventID: OME.Event.ID,
    title: String,
    subtitle: String? = nil,
    body: String? = nil,
    keywords: String = "",
    in db: Database
) throws {
    try EventSearchDocument.insert {
        EventSearchDocument(
            id: id,
            stableID: stableID,
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            kind: .stage,
            title: title,
            subtitle: subtitle,
            body: body,
            keywords: keywords,
            target: .stage(localID("meadow")),
            baseRank: 100
        )
    }
    .execute(db)
}

private func insertStage(
    eventID: OME.Event.ID,
    stageID: String,
    name: String,
    sortIndex: Int? = 1,
    in db: Database
) throws {
    try OME.Stage.insert {
        OME.Stage.Draft(
            id: makeStageID(stageID, eventID: eventID),
            name: name,
            color: 0x00bbcc,
            sortIndex: sortIndex
        )
    }
    .execute(db)
}

private func insertChannel(
    eventID: OME.Event.ID,
    channelID: String,
    name: String,
    sortIndex: Int?,
    in db: Database
) throws {
    try OME.Channel.insert {
        OME.Channel.Draft(
            id: makeChannelID(channelID, eventID: eventID),
            name: name,
            description: "Updates from \(name).",
            iconImageURL: nil,
            headerImageURL: nil,
            sortIndex: sortIndex,
            defaultNotificationState: .subscribed,
            notificationsRequired: false
        )
    }
    .execute(db)
}

private func expectStageSearchDocument(
    _ documents: [EventSearchDocument],
    eventID: OME.Event.ID,
    stageID: String,
    title: String
) throws {
    #expect(documents.count == 1)

    let document = try #require(documents.first)
    #expect(
        document.stableID
            == searchStableID("stage:\(eventID.organizerID):\(eventID.eventID):\(stageID)")
    )
    #expect(document.organizerID == eventID.organizerID)
    #expect(document.eventID == eventID.eventID)
    #expect(document.kind == .stage)
    #expect(document.title == title)
    #expect(document.subtitle == "Stage")
    #expect(document.body == nil)
    #expect(document.keywords == "stage")
    #expect(document.target == .stage(localID(stageID)))
    #expect(document.baseRank == 900)
}

private func featureDocuments(in db: Database) throws -> [EventSearchDocument] {
    try EventSearchDocument.fetchAll(db)
        .filter { $0.kind == .feature }
        .sorted { $0.stableID < $1.stableID }
}

private func featureStableID(
    _ featureID: EventSearchFeature.ID,
    eventID: OME.Event.ID
) -> EventSearchDocument.StableID {
    searchStableID("feature:\(eventID.organizerID):\(eventID.eventID):\(featureID.rawValue)")
}

private func expectedFeatureDocumentsOrder(eventID: OME.Event.ID) -> [EventSearchFeature] {
    EventSearchFeature.indexedFeatures.sorted {
        featureStableID($0.id, eventID: eventID) < featureStableID($1.id, eventID: eventID)
    }
}

private func makeStageID(
    _ stageID: String,
    eventID: OME.Event.ID
) -> OME.Stage.ID {
    OME.Stage.ID(
        organizerID: eventID.organizerID,
        eventID: eventID.eventID,
        stageID: localID(stageID)
    )
}

private func makeChannelID(
    _ channelID: String,
    eventID: OME.Event.ID
) -> OME.Channel.ID {
    OME.Channel.ID(
        organizerID: eventID.organizerID,
        eventID: eventID.eventID,
        channelID: localID(channelID)
    )
}

private func localID<Record>(_ string: String) -> OME.ID<Record> {
    OME.ID<Record>(ATProto.Record.Key(string))
}

private func searchDocumentID(_ rawValue: Int64) -> EventSearchDocument.ID {
    EventSearchDocument.ID(rawValue: rawValue)
}

private func searchStableID(_ rawValue: String) -> EventSearchDocument.StableID {
    EventSearchDocument.StableID(rawValue: rawValue)
}
