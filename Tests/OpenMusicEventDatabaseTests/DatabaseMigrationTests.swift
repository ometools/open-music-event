import ATProto
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SQLiteData
import Testing

struct DatabaseMigrationTests {
    @Test
    func `existing comms posts migrate to standard notification delivery`() async throws {
        let database = try SQLiteData.defaultDatabase()

        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(
            database,
            upTo: "Add attached images to OpenMusicEvent comms posts"
        )

        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO "organizers" ("id")
                VALUES ('did:plc:festival');

                INSERT INTO "events" (
                  "organizerID", "eventID", "name", "timeZone"
                ) VALUES (
                  'did:plc:festival', 'summer-2026', 'Summer Festival', 'America/Denver'
                );

                INSERT INTO "channels" (
                  "organizerID", "eventID", "channelID", "name", "description",
                  "defaultNotificationState"
                ) VALUES (
                  'did:plc:festival', 'summer-2026', 'announcements', 'Announcements',
                  'Official updates.', 'subscribed'
                );

                INSERT INTO "commsPosts" (
                  "organizerID", "eventID", "channelID", "postID", "title", "contents",
                  "sortIndex"
                ) VALUES (
                  'did:plc:festival', 'summer-2026', 'announcements', 'gates-open',
                  'Gates are open', 'Welcome to the festival.', 0
                );
                """)
        }

        try migrator.migrate(database)

        let delivery = try await database.read { db in
            try String.fetchOne(
                db,
                sql: #"SELECT "delivery" FROM "commsPosts" WHERE "postID" = 'gates-open'"#
            )
        }
        expectNoDifference(delivery, "standard")

        await #expect(throws: (any Error).self) {
            try await database.write { db in
                try db.execute(
                    sql: #"UPDATE "commsPosts" SET "delivery" = 'unknown'"#
                )
            }
        }
    }

    @Test
    func migratesPerformanceIntoPerformanceScheduleItemWithoutChangingItsScheduleData() async throws {
        let database = try SQLiteData.defaultDatabase()

        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database, upTo: "Create OpenMusicEvent relationship schema")

        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO "organizers" ("id")
                VALUES ('did:plc:festival');

                INSERT INTO "events" (
                  "organizerID", "eventID", "name", "timeZone"
                ) VALUES (
                  'did:plc:festival', 'summer-2026', 'Summer Festival', 'America/Denver'
                );

                INSERT INTO "stages" (
                  "organizerID", "eventID", "stageID", "name", "color"
                ) VALUES (
                  'did:plc:festival', 'summer-2026', 'main-stage', 'Main Stage', 0
                );

                INSERT INTO "schedules" (
                  "organizerID", "eventID", "scheduleID", "date"
                ) VALUES (
                  'did:plc:festival', 'summer-2026', 'friday', '2026-07-31'
                );

                INSERT INTO "contributors" (
                  "organizerID", "eventID", "contributorID", "name", "did"
                ) VALUES (
                  'did:plc:festival', 'summer-2026', 'example-band',
                  'The Example Band', 'did:plc:exampleband'
                );

                INSERT INTO "performances" (
                  "organizerID", "eventID", "performanceID", "stageID", "scheduleID",
                  "startTime", "endTime", "title", "description", "recordings"
                ) VALUES (
                  'did:plc:festival', 'summer-2026', 'friday-main-1900',
                  'main-stage', 'friday',
                  '2026-07-31T19:00:00Z', '2026-07-31T20:00:00Z',
                  'The Example Band', 'Opening-night performance',
                  '[{"url":"https://example.com/live-set"}]'
                );

                INSERT INTO "performanceContributors" (
                  "organizerID", "eventID", "performanceID", "contributorID",
                  "contributorActor", "billing", "role", "sortIndex"
                ) VALUES (
                  'did:plc:festival', 'summer-2026', 'friday-main-1900',
                  'example-band', 'did:plc:exampleband', 'primary', 'performer', 3
                );
                """)
        }

        try migrator.migrate(database)

        try await database.write { db in
            #expect(try db.tableExists("scheduleItems"))
            #expect(try db.tableExists("scheduleItemPerformanceDetails"))
            #expect(try db.tableExists("scheduleItemContributors"))
            #expect(!(try db.tableExists("performances")))
            #expect(!(try db.tableExists("performanceContributors")))

            let recordProjectionTypes = try String.fetchAll(
                db,
                sql: """
                    SELECT "type"
                    FROM "sqlite_schema"
                    WHERE "name" IN (
                      'app.openmusicevent.performance',
                      'performanceContributors'
                    )
                    ORDER BY "name"
                    """
            )
            expectNoDifference(recordProjectionTypes, ["view", "view"])

            let scheduleItem = try String.fetchOne(
                db,
                sql: """
                    SELECT json_object(
                      'organizerID', "organizerID",
                      'eventID', "eventID",
                      'scheduleItemID', "scheduleItemID",
                      'stageID', "stageID",
                      'scheduleID', "scheduleID",
                      'kind', "kind",
                      'startTime', "startTime",
                      'endTime', "endTime",
                      'title', "title",
                      'description', "description"
                    )
                    FROM "scheduleItems"
                    """
            )
            expectNoDifference(
                scheduleItem,
                #"{"organizerID":"did:plc:festival","eventID":"summer-2026","scheduleItemID":"friday-main-1900","stageID":"main-stage","scheduleID":"friday","kind":"performance","startTime":"2026-07-31T19:00:00Z","endTime":"2026-07-31T20:00:00Z","title":"The Example Band","description":"Opening-night performance"}"#
            )

            let recordings = try String.fetchOne(
                db,
                sql: #"SELECT "recordings" FROM "scheduleItemPerformanceDetails""#
            )
            expectNoDifference(recordings, #"[{"url":"https://example.com/live-set"}]"#)

            let contributor = try String.fetchOne(
                db,
                sql: """
                    SELECT json_object(
                      'scheduleItemID', "scheduleItemID",
                      'contributorID', "contributorID",
                      'contributorActor', "contributorActor",
                      'billing', "billing",
                      'role', "role",
                      'sortIndex', "sortIndex"
                    )
                    FROM "scheduleItemContributors"
                    """
            )
            expectNoDifference(
                contributor,
                #"{"scheduleItemID":"friday-main-1900","contributorID":"example-band","contributorActor":"did:plc:exampleband","billing":"primary","role":"performer","sortIndex":3}"#
            )

            #expect(try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "scheduleItems""#) == 1)
            #expect(try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "scheduleItemPerformanceDetails""#) == 1)
            #expect(try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "scheduleItemContributors""#) == 1)
            expectNoDifference(
                try String.fetchAll(
                    db,
                    sql: """
                        SELECT "name"
                        FROM pragma_index_info('scheduleItemContributors_item_sortIndex')
                        ORDER BY "seqno"
                        """
                ),
                ["organizerID", "eventID", "scheduleItemID", "sortIndex"]
            )

            // The current app can keep using its shipped performance model while call sites migrate.
            try db.execute(sql: """
                UPDATE "app.openmusicevent.performance"
                SET
                  "title" = 'The Example Band - Updated',
                  "recordings" = '[{"url":"https://example.com/encore"}]'
                WHERE "organizerID" = 'did:plc:festival'
                  AND "eventID" = 'summer-2026'
                  AND "performanceID" = 'friday-main-1900'
                """)

            #expect(
                try String.fetchOne(
                    db,
                    sql: #"SELECT "title" FROM "scheduleItems""#
                ) == "The Example Band - Updated"
            )
            #expect(
                try String.fetchOne(
                    db,
                    sql: #"SELECT "recordings" FROM "scheduleItemPerformanceDetails""#
                ) == #"[{"url":"https://example.com/encore"}]"#
            )
            try db.execute(sql: """
                DELETE FROM "app.openmusicevent.performance"
                WHERE "organizerID" = 'did:plc:festival'
                  AND "eventID" = 'summer-2026'
                  AND "performanceID" = 'friday-main-1900'
                """)

            #expect(try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "scheduleItems""#) == 0)
            #expect(try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "scheduleItemPerformanceDetails""#) == 0)
            #expect(try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "scheduleItemContributors""#) == 0)
        }
    }

    @Test
    func failedScheduleItemMigrationLeavesThePerformanceSchemaRecoverable() async throws {
        let database = try SQLiteData.defaultDatabase()

        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database, upTo: "Create OpenMusicEvent relationship schema")

        try await database.write { db in
            try db.execute(sql: """
                INSERT INTO "organizers" ("id")
                VALUES ('did:plc:festival');

                INSERT INTO "events" (
                  "organizerID", "eventID", "name", "timeZone"
                ) VALUES (
                  'did:plc:festival', 'summer-2026', 'Summer Festival', 'America/Denver'
                );

                INSERT INTO "stages" (
                  "organizerID", "eventID", "stageID", "name", "color"
                ) VALUES (
                  'did:plc:festival', 'summer-2026', 'main-stage', 'Main Stage', 0
                );

                INSERT INTO "performances" (
                  "organizerID", "eventID", "performanceID", "stageID",
                  "startTime", "endTime", "title", "recordings"
                ) VALUES (
                  'did:plc:festival', 'summer-2026', 'friday-main-1900', 'main-stage',
                  '2026-07-31T19:00:00Z', '2026-07-31T20:00:00Z',
                  'The Example Band', '[]'
                );

                CREATE TABLE "scheduleItemPerformanceDetails" ("sentinel" TEXT);
                INSERT INTO "scheduleItemPerformanceDetails" ("sentinel") VALUES ('keep me');
                """)
        }

        #expect(throws: (any Error).self) {
            try migrator.migrate(database)
        }

        try await database.read { db in
            let scheduleItemsExist = try db.tableExists("scheduleItems")
            let performancesExist = try db.tableExists("performances")
            let performanceTitle = try String.fetchOne(
                db,
                sql: #"SELECT "title" FROM "performances" WHERE "performanceID" = 'friday-main-1900'"#
            )
            let sentinel = try String.fetchOne(
                db,
                sql: #"SELECT "sentinel" FROM "scheduleItemPerformanceDetails""#
            )

            #expect(!scheduleItemsExist)
            #expect(performancesExist)
            #expect(performanceTitle == "The Example Band")
            #expect(sentinel == "keep me")
        }
    }

    @Test
    func eventReportingLinkMigrationAddsNullableColumn() async throws {
        let database = try SQLiteData.defaultDatabase()

        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        try await database.read { db in
            let type = try String.fetchOne(
                db,
                sql: #"SELECT "type" FROM pragma_table_info('app.openmusicevent.event') WHERE "name" = 'reportingLink'"#
            )
            let isNotNull = try Int.fetchOne(
                db,
                sql: #"SELECT "notnull" FROM pragma_table_info('app.openmusicevent.event') WHERE "name" = 'reportingLink'"#
            )

            #expect(type == "TEXT")
            #expect(isNotNull == 0)
        }
    }

    @Test
    func eventReportingLinksMigrationAddsNullablePluralColumn() async throws {
        let database = try SQLiteData.defaultDatabase()

        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        try await database.read { db in
            let type = try String.fetchOne(
                db,
                sql: #"SELECT "type" FROM pragma_table_info('app.openmusicevent.event') WHERE "name" = 'reportingLinks'"#
            )
            let isNotNull = try Int.fetchOne(
                db,
                sql: #"SELECT "notnull" FROM pragma_table_info('app.openmusicevent.event') WHERE "name" = 'reportingLinks'"#
            )

            #expect(type == "TEXT")
            #expect(isNotNull == 0)
        }
    }

    @Test
    func eventReportingLinksMigrationWrapsLegacyLinkWithoutChangingEventData() async throws {
        let database = try SQLiteData.defaultDatabase()
        let organizerID = try #require(OME.Organizer.ID("did:plc:festival"))
        let eventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: localID("summer-2026")
        )
        let legacyReportingLink = #"{"name":"Report an Incident","url":"https://example.org/report","description":"Event support form."}"#

        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database, upTo: "Add OpenMusicEvent relationship capabilities")

        try await database.write { db in
            try db.execute(
                sql: #"INSERT INTO "organizers" ("id") VALUES (?)"#,
                arguments: [organizerID.description]
            )
            try db.execute(
                sql: """
                    INSERT INTO "events" (
                      "organizerID", "eventID", "name", "description", "timeZone", "reportingLink"
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    organizerID.description,
                    eventID.eventID.rawValue.rawValue,
                    "Summer Festival",
                    "Keep this event description.",
                    "America/Denver",
                    legacyReportingLink,
                ]
            )
        }

        try migrator.migrate(database)

        let migratedEvent = try await database.read { db in
            try #require(
                try OME.Event.where { $0.id.eq(eventID) }.fetchOne(db)
            )
        }
        #expect(migratedEvent.name == "Summer Festival")
        #expect(migratedEvent.description == "Keep this event description.")
        expectNoDifference(
            migratedEvent.reportingLinks,
            [
                OME.Event.ReportingLink(
                    name: "Report an Incident",
                    url: try #require(URL(string: "https://example.org/report")),
                    description: "Event support form."
                )
            ]
        )
    }

    @Test
    func invalidLegacyReportingLinkRollsBackPluralMigrationAndPreservesEvent() async throws {
        let database = try SQLiteData.defaultDatabase()

        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database, upTo: "Add OpenMusicEvent relationship capabilities")

        try await database.write { db in
            try db.execute(sql: #"INSERT INTO "organizers" ("id") VALUES ('did:plc:festival')"#)
            try db.execute(
                sql: """
                    INSERT INTO "events" (
                      "organizerID", "eventID", "name", "timeZone", "reportingLink"
                    ) VALUES ('did:plc:festival', 'summer-2026', 'Do Not Lose Me', 'America/Denver', '{invalid')
                    """
            )
        }

        #expect(throws: (any Error).self) {
            try migrator.migrate(database)
        }

        try await database.read { db in
            let eventName = try String.fetchOne(
                db,
                sql: #"SELECT "name" FROM "events" WHERE "eventID" = 'summer-2026'"#
            )
            let legacyValue = try String.fetchOne(
                db,
                sql: #"SELECT "reportingLink" FROM "events" WHERE "eventID" = 'summer-2026'"#
            )
            let pluralColumnCount = try Int.fetchOne(
                db,
                sql: #"SELECT COUNT(*) FROM pragma_table_info('events') WHERE "name" = 'reportingLinks'"#
            )

            #expect(eventName == "Do Not Lose Me")
            #expect(legacyValue == "{invalid")
            #expect(pluralColumnCount == 0)
        }
    }

    @Test
    func eventSearchTermRejectsBlankQueries() {
        #expect(EventSearchTerm(rawValue: "   ") == nil)
    }

    @Test
    func relationshipSchemaMigrationCreatesRelationshipTables() async throws {
        let database = try migratedDatabase()

        try await database.write { db in
            #expect(try db.tableExists("app.openmusicevent.relationship"))
            #expect(try db.tableExists("app.openmusicevent.relationship.confirmation"))

            let relationshipColumns = try String.fetchAll(
                db,
                sql: #"SELECT "name" FROM pragma_table_info('app.openmusicevent.relationship')"#
            )
            #expect(relationshipColumns == [
                "type",
                "subject",
                "role",
                "object",
                "createdAt",
                "capabilities",
            ])

            let confirmationColumns = try String.fetchAll(
                db,
                sql: #"SELECT "name" FROM pragma_table_info('app.openmusicevent.relationship.confirmation')"#
            )
            #expect(confirmationColumns == [
                "type",
                "relationship",
                "status",
                "createdAt",
            ])

            let owner = try #require(DID("did:plc:owner"))
            let contributor = OME.Relationship.RecordReference(
                author: owner,
                collection: OME.Contributor.nsid,
                rkey: ATProto.Record.Key("runekey")
            )
            let performance = OME.Relationship.RecordReference(
                author: owner,
                collection: OME.Performance.nsid,
                rkey: ATProto.Record.Key("friday-the-portal-1")
            )
            let relationship = OME.Relationship(
                subject: contributor,
                role: .performer,
                object: performance,
                createdAt: "2026-07-04T12:00:00Z"
            )

            try OME.Relationship.insert { relationship }.execute(db)

            #expect(try OME.Relationship.fetchAll(db) == [relationship])
        }
    }


    @Test
    func sourceWorkspaceMigrationCreatesOnlyCurrentStorage() async throws {
        let database = try migratedDatabase()

        try await database.read { db in
            let tableNames = Set(
                try String.fetchAll(
                    db,
                    sql: #"SELECT "name" FROM sqlite_master WHERE "type" = 'table'"#
                )
            )
            #expect(tableNames.contains("sourceWorkspaceRelationships"))
            #expect(tableNames.contains("sourceWorkspaceAuthoringActivations"))
            #expect(tableNames.contains("sourceWorkspaceReferences"))
            #expect(tableNames.contains("sourceWorkspaceInstallations"))

            for removedTable in [
                "workspacePublications",
                "workspaceAuthoringActivations",
                "workspaceRelationships",
                "eventEditingWorkspaces",
                "editingWorkspaces",
                "sourceBaselines",
            ] {
                #expect(tableNames.contains(removedTable) == false)
            }

            let provenanceColumns = try String.fetchAll(
                db,
                sql: #"SELECT "name" FROM pragma_table_info('eventSourceProvenances')"#
            )
            #expect(provenanceColumns.contains("sourceBaselineID") == false)
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
                CREATE TABLE "eventSourceProvenances" (
                  "organizerID" TEXT NOT NULL,
                  "eventID" TEXT NOT NULL,
                  "sourceKind" TEXT NOT NULL,
                  "sourceReference" TEXT NOT NULL,
                  "ref" TEXT,
                  "eventIDOrigin" TEXT NOT NULL,
                  "sourceEventDirectory" TEXT NOT NULL,
                  "sourceBaselineID" TEXT,
                  PRIMARY KEY ("organizerID", "eventID") ON CONFLICT REPLACE
                ) STRICT
                """)
            try db.execute(sql: """
                CREATE TABLE "sourceBaselines" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "sourceKind" TEXT NOT NULL,
                  "sourceReference" TEXT NOT NULL,
                  "ref" TEXT,
                  "databaseFileName" TEXT NOT NULL,
                  "importedAt" TEXT NOT NULL
                ) STRICT
                """)
            try db.execute(sql: """
                INSERT INTO "participants" ("organizerID", "eventID", "participantID", "name")
                VALUES ('did:plc:organizer', 'event-1', 'artist-one', 'Artist One')
                """)
        }

        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database, upTo: "Add OpenMusicEvent performance contributor credits")

        try await database.read { db in
            #expect(try db.tableExists("contributors"))
            #expect(try db.tableExists("contributorClaims"))
            #expect(try db.tableExists("performanceContributors"))

            let contributorCount = try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "contributors""#)
            #expect(contributorCount == 0)

            let contributorColumns = try String.fetchAll(
                db,
                sql: #"SELECT "name" FROM pragma_table_info('contributors')"#
            )
            #expect(contributorColumns.contains("did"))
            #expect(!contributorColumns.contains("kind"))

            let performanceContributorColumns = try String.fetchAll(
                db,
                sql: #"SELECT "name" FROM pragma_table_info('performanceContributors')"#
            )
            #expect(performanceContributorColumns.contains("contributorActor"))
            #expect(performanceContributorColumns.contains("billing"))
            #expect(performanceContributorColumns.contains("role"))
            #expect(performanceContributorColumns.contains("sortIndex"))
        }
    }

    @Test
    func `existing event records keep their identity when record tables adopt lexicon names`() async throws {
        let database = try SQLiteData.defaultDatabase()
        let organizerID = try #require(OME.Organizer.ID("did:plc:festival"))
        let eventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: localID("summer-2026")
        )

        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(
            database,
            upTo: "Create OpenMusicEvent local RSVP records"
        )

        try await database.write { db in
            try db.execute(
                sql: #"INSERT INTO "organizers" ("id") VALUES (?)"#,
                arguments: [organizerID.description]
            )
            try db.execute(
                sql: """
                    INSERT INTO "events" (
                      "organizerID", "eventID", "name", "timeZone"
                    ) VALUES (?, ?, 'Summer Festival', 'America/Denver')
                    """,
                arguments: [organizerID.description, eventID.eventID.rawValue.rawValue]
            )
        }

        // A normal app migration moves the records; it does not rebuild their identity.
        try migrator.migrate(database)

        try await database.read { db in
            #expect(!(try db.tableExists("events")))
            #expect(try db.tableExists(OME.Event.nsid.rawValue))
            #expect(try db.tableExists(OME.Organizer.nsid.rawValue))

            let event = try #require(try OME.Event.find(eventID).fetchOne(db))
            expectNoDifference(event.id, eventID)
            expectNoDifference(event.name, "Summer Festival")

            let referencedRecordTables = try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT "table"
                    FROM pragma_foreign_key_list('scheduleItems')
                    ORDER BY "table"
                    """
            )
            expectNoDifference(
                referencedRecordTables,
                [OME.Event.nsid, OME.Schedule.nsid, OME.Stage.nsid].map(\.rawValue)
            )
        }
    }

    @Test
    func `existing events become explicit installations and replacement does not erase intent`() async throws {
        let database = try SQLiteData.defaultDatabase()
        let organizerID = try #require(OME.Organizer.ID("did:plc:installed-event"))
        let eventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: localID("summer-2026")
        )
        let authoringOnlyEventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: localID("summer-2025")
        )
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/example/summer-workspace",
            branch: "main"
        )
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))

        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(
            database,
            upTo: "Name OpenMusicEvent record tables after their lexicons"
        )
        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: organizerID)
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Summer Festival",
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
                    reportingLinks: nil
                )
            }
            .execute(db)
            try OME.Event.insert {
                OME.Event.Draft(
                    id: authoringOnlyEventID,
                    name: "Materialized only for authoring",
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
                    reportingLinks: nil
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .tangled,
                    sourceReference: workspace.repository,
                    ref: "main",
                    eventIDOrigin: .explicit,
                    sourceEventDirectory: "summer-2026"
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: authoringOnlyEventID,
                    sourceKind: .tangled,
                    sourceReference: workspace.repository,
                    ref: "main",
                    eventIDOrigin: .explicit,
                    sourceEventDirectory: "summer-2025"
                )
            }
            .execute(db)
            try SourceWorkspaceInstallationRecord.insert {
                SourceWorkspaceInstallationRecord(id: workspace.id, revision: "prepared")
            }
            .execute(db)
            try db.execute(sql: """
                CREATE TABLE "appState" (
                  "id" INTEGER PRIMARY KEY CHECK ("id" = 1),
                  "organizerID" TEXT,
                  "eventID" TEXT
                ) STRICT;
                INSERT INTO "appState" ("id", "organizerID", "eventID")
                VALUES (1, ?, ?);
                """, arguments: [
                    eventID.organizerID.description,
                    eventID.eventID.rawValue.rawValue,
                ]
            )
        }

        try migrator.migrate(database)

        try await database.write { db in
            let installation = try #require(try InstalledEventRecord.fetchOne(db))
            expectNoDifference(installation.id, eventID)
            expectNoDifference(
                installation.workspace?.repository,
                "tangled.org/example/summer-workspace"
            )
            expectNoDifference(installation.workspace?.defaultBranch, "main")
            #expect(
                try InstalledEventRecord.find(authoringOnlyEventID).fetchOne(db) == nil
            )
            #expect(try OME.Event.find(authoringOnlyEventID).fetchOne(db) != nil)

            // Published-content refresh deletes and reinserts event content. Installation intent is a
            // separate local decision and must survive that replacement boundary.
            try OME.Event.find(eventID).delete().execute(db)
            expectNoDifference(
                try InstalledEventRecord.fetchAll(db).map(\.id),
                [eventID]
            )
        }
    }

    @Test
    func `persistent Stage storage upgrades an installed canonical Event database`() throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database, upTo: "Track installed canonical Events")

        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let event = try Event(
            id: eventID,
            name: "Existing Event",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        try database.write { db in
            try Event.insert { event }.execute(db)
            try InstalledEvent.insert {
                InstalledEvent(id: eventID)
            }.execute(db)
            #expect(!(try db.tableExists("events.openmusic.stage")))
        }

        try migrator.migrate(database)

        try database.read { db in
            #expect(try db.tableExists("events.openmusic.stage"))
            expectNoDifference(try Event.find(eventID).fetchOne(db), event)
            expectNoDifference(
                try InstalledEvent.find(eventID).fetchOne(db)?.id,
                eventID
            )
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

private func localID<Record>(_ string: String) -> OME.ID<Record> {
    OME.ID<Record>(ATProto.Record.Key(string))
}
