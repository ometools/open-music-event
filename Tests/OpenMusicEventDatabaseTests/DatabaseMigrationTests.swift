import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

struct DatabaseMigrationTests {
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
                    rowid: 1,
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

            #expect(matches.map(\.id) == [1])
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
        "Create OpenMusicEvent source provenance schema",
        "Create OpenMusicEvent source baseline schema",
        "Create OpenMusicEvent local image blob schema",
        "Allow OpenMusicEvent calendar local image blobs",
    ]
}
