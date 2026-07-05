import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SQLiteData

public extension OME {
    enum DatabaseMigrations {
        public static func register(into migrator: inout DatabaseMigrator) {
            migrator.registerMigration("Create OpenMusicEvent core schema") { db in
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "organizers" (
                      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "events" (
                      "organizerID" TEXT NOT NULL REFERENCES "organizers"("id") ON DELETE CASCADE,
                      "eventID" TEXT NOT NULL,
                      "name" TEXT NOT NULL,
                      "description" TEXT,
                      "startDate" TEXT,
                      "endDate" TEXT,
                      "status" TEXT,
                      "mode" TEXT,
                      "locations" TEXT,
                      "uris" TEXT,
                      "timeZone" TEXT NOT NULL,
                      "images" TEXT,
                      "contactNumbers" TEXT,
                      "categoryConfigs" TEXT,
                      PRIMARY KEY ("organizerID", "eventID") ON CONFLICT REPLACE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "eventOrganizers" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "eventOrganizerID" TEXT NOT NULL REFERENCES "organizers"("id") ON DELETE CASCADE,
                      PRIMARY KEY ("organizerID", "eventID", "eventOrganizerID"),
                      FOREIGN KEY ("organizerID", "eventID")
                        REFERENCES "events"("organizerID", "eventID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "stages" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "stageID" TEXT NOT NULL,
                      "name" TEXT NOT NULL,
                      "color" INTEGER NOT NULL,
                      "category" TEXT,
                      "sortIndex" INTEGER,
                      "images" TEXT,
                      "systemIconName" TEXT,
                      "iconShortCode" TEXT,
                      "lineup" TEXT,
                      PRIMARY KEY ("organizerID", "eventID", "stageID") ON CONFLICT REPLACE,
                      FOREIGN KEY ("organizerID", "eventID")
                        REFERENCES "events"("organizerID", "eventID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "schedules" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "scheduleID" TEXT NOT NULL,
                      "date" TEXT NOT NULL,
                      "startsAt" TEXT,
                      "endsAt" TEXT,
                      "customTitle" TEXT,
                      PRIMARY KEY ("organizerID", "eventID", "scheduleID") ON CONFLICT REPLACE,
                      FOREIGN KEY ("organizerID", "eventID")
                        REFERENCES "events"("organizerID", "eventID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "contributors" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "contributorID" TEXT NOT NULL,
                      "name" TEXT NOT NULL,
                      "bio" TEXT,
                      "images" TEXT,
                      "kind" TEXT,
                      "links" TEXT,
                      PRIMARY KEY ("organizerID", "eventID", "contributorID") ON CONFLICT REPLACE,
                      FOREIGN KEY ("organizerID", "eventID")
                        REFERENCES "events"("organizerID", "eventID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "contributorClaims" (
                      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "contributorID" TEXT NOT NULL,
                      FOREIGN KEY ("organizerID", "eventID", "contributorID")
                        REFERENCES "contributors"("organizerID", "eventID", "contributorID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "channels" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "channelID" TEXT NOT NULL,
                      "name" TEXT NOT NULL,
                      "description" TEXT NOT NULL,
                      "iconImageURL" TEXT,
                      "headerImageURL" TEXT,
                      "sortIndex" INTEGER,
                      "defaultNotificationState" TEXT NOT NULL,
                      "notificationsRequired" INTEGER NOT NULL DEFAULT 0,
                      PRIMARY KEY ("organizerID", "eventID", "channelID") ON CONFLICT REPLACE,
                      FOREIGN KEY ("organizerID", "eventID")
                        REFERENCES "events"("organizerID", "eventID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "posters" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "posterID" TEXT NOT NULL,
                      "title" TEXT,
                      "image" TEXT NOT NULL,
                      PRIMARY KEY ("organizerID", "eventID", "posterID") ON CONFLICT REPLACE,
                      FOREIGN KEY ("organizerID", "eventID")
                        REFERENCES "events"("organizerID", "eventID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "performances" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "performanceID" TEXT NOT NULL,
                      "stageID" TEXT NOT NULL,
                      "scheduleID" TEXT,
                      "startTime" TEXT NOT NULL,
                      "endTime" TEXT NOT NULL,
                      "title" TEXT NOT NULL,
                      "description" TEXT,
                      "recordings" TEXT NOT NULL,
                      PRIMARY KEY ("organizerID", "eventID", "performanceID") ON CONFLICT REPLACE,
                      FOREIGN KEY ("organizerID", "eventID")
                        REFERENCES "events"("organizerID", "eventID")
                        ON DELETE CASCADE,
                      FOREIGN KEY ("organizerID", "eventID", "stageID")
                        REFERENCES "stages"("organizerID", "eventID", "stageID")
                        ON DELETE CASCADE,
                      FOREIGN KEY ("organizerID", "eventID", "scheduleID")
                        REFERENCES "schedules"("organizerID", "eventID", "scheduleID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "performanceContributors" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "performanceID" TEXT NOT NULL,
                      "contributorID" TEXT,
                      "anonymousName" TEXT,
                      FOREIGN KEY ("organizerID", "eventID", "performanceID")
                        REFERENCES "performances"("organizerID", "eventID", "performanceID")
                        ON DELETE CASCADE,
                      FOREIGN KEY ("organizerID", "eventID", "contributorID")
                        REFERENCES "contributors"("organizerID", "eventID", "contributorID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Add OpenMusicEvent participant actor policies") { db in
                try #sql("""
                    ALTER TABLE "events"
                    ADD COLUMN "policies" TEXT
                    """)
                    .execute(db)

                try #sql("""
                    ALTER TABLE "performanceContributors"
                    ADD COLUMN "contributorActor" TEXT
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Add OpenMusicEvent calendars") { db in
                try #sql("""
                    ALTER TABLE "events"
                    ADD COLUMN "owner" TEXT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "calendars" (
                      "ownerID" TEXT NOT NULL REFERENCES "organizers"("id") ON DELETE CASCADE,
                      "calendarID" TEXT NOT NULL,
                      "name" TEXT NOT NULL,
                      "description" TEXT,
                      "images" TEXT,
                      PRIMARY KEY ("ownerID", "calendarID") ON CONFLICT REPLACE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "calendarEntries" (
                      "calendarOwnerID" TEXT NOT NULL,
                      "calendarID" TEXT NOT NULL,
                      "entryID" TEXT NOT NULL,
                      "event" TEXT NOT NULL,
                      "createdAt" TEXT NOT NULL,
                      "note" TEXT,
                      "pinned" INTEGER NOT NULL DEFAULT 0,
                      PRIMARY KEY ("calendarOwnerID", "calendarID", "entryID") ON CONFLICT REPLACE,
                      FOREIGN KEY ("calendarOwnerID", "calendarID")
                        REFERENCES "calendars"("ownerID", "calendarID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

            }

            migrator.registerMigration("Add OpenMusicEvent event reporting links") { db in
                try #sql("""
                    ALTER TABLE "events"
                    ADD COLUMN "reportingLink" TEXT
                    """)
                    .execute(db)
            }

            OME.SourceEditingMigrations.register(into: &migrator)

            migrator.registerMigration("Create OpenMusicEvent local image blob schema") { db in
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "localImageBlobs" (
                      "assetKey" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT,
                      "parentKind" TEXT NOT NULL,
                      "parentLocalID" TEXT NOT NULL,
                      "role" TEXT NOT NULL,
                      "renderKind" TEXT NOT NULL,
                      "mimeType" TEXT NOT NULL,
                      "data" BLOB NOT NULL,
                      "sourceURL" TEXT,
                      "lastFetchedAt" TEXT
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE INDEX IF NOT EXISTS "localImageBlobs_event_parent_role"
                    ON "localImageBlobs" ("organizerID", "eventID", "parentKind", "parentLocalID", "role")
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Allow OpenMusicEvent calendar local image blobs") { db in
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "localImageBlobs_new" (
                      "assetKey" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT,
                      "parentKind" TEXT NOT NULL,
                      "parentLocalID" TEXT NOT NULL,
                      "role" TEXT NOT NULL,
                      "renderKind" TEXT NOT NULL,
                      "mimeType" TEXT NOT NULL,
                      "data" BLOB NOT NULL,
                      "sourceURL" TEXT,
                      "lastFetchedAt" TEXT
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    INSERT OR REPLACE INTO "localImageBlobs_new" (
                      "assetKey",
                      "organizerID",
                      "eventID",
                      "parentKind",
                      "parentLocalID",
                      "role",
                      "renderKind",
                      "mimeType",
                      "data",
                      "sourceURL",
                      "lastFetchedAt"
                    )
                    SELECT
                      "assetKey",
                      "organizerID",
                      "eventID",
                      "parentKind",
                      "parentLocalID",
                      "role",
                      "renderKind",
                      "mimeType",
                      "data",
                      "sourceURL",
                      "lastFetchedAt"
                    FROM "localImageBlobs"
                    """)
                    .execute(db)

                try #sql("""
                    DROP TABLE "localImageBlobs"
                    """)
                    .execute(db)

                try #sql("""
                    ALTER TABLE "localImageBlobs_new" RENAME TO "localImageBlobs"
                    """)
                    .execute(db)

                try #sql("""
                    CREATE INDEX IF NOT EXISTS "localImageBlobs_event_parent_role"
                    ON "localImageBlobs" ("organizerID", "eventID", "parentKind", "parentLocalID", "role")
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Create OpenMusicEvent contributor schema") { db in
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "contributors" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "contributorID" TEXT NOT NULL,
                      "name" TEXT NOT NULL,
                      "bio" TEXT,
                      "images" TEXT,
                      "kind" TEXT,
                      "links" TEXT,
                      PRIMARY KEY ("organizerID", "eventID", "contributorID") ON CONFLICT REPLACE,
                      FOREIGN KEY ("organizerID", "eventID")
                        REFERENCES "events"("organizerID", "eventID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "contributorClaims" (
                      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "contributorID" TEXT NOT NULL,
                      FOREIGN KEY ("organizerID", "eventID", "contributorID")
                        REFERENCES "contributors"("organizerID", "eventID", "contributorID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "performanceContributors" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "performanceID" TEXT NOT NULL,
                      "contributorID" TEXT,
                      "anonymousName" TEXT,
                      "contributorActor" TEXT,
                      FOREIGN KEY ("organizerID", "eventID", "performanceID")
                        REFERENCES "performances"("organizerID", "eventID", "performanceID")
                        ON DELETE CASCADE,
                      FOREIGN KEY ("organizerID", "eventID", "contributorID")
                        REFERENCES "contributors"("organizerID", "eventID", "contributorID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Create OpenMusicEvent event search schema") { db in
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "eventSearchDocuments" (
                      "id" INTEGER PRIMARY KEY NOT NULL,
                      "stableID" TEXT NOT NULL,
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "kind" TEXT NOT NULL,
                      "title" TEXT NOT NULL,
                      "subtitle" TEXT,
                      "body" TEXT,
                      "keywords" TEXT NOT NULL,
                      "target" TEXT NOT NULL,
                      "baseRank" INTEGER NOT NULL DEFAULT 0,
                      UNIQUE ("stableID"),
                      FOREIGN KEY ("organizerID", "eventID")
                        REFERENCES "events"("organizerID", "eventID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE INDEX IF NOT EXISTS "eventSearchDocuments_event_kind_rank"
                    ON "eventSearchDocuments" ("organizerID", "eventID", "kind", "baseRank")
                    """)
                    .execute(db)

                try #sql("""
                    CREATE VIRTUAL TABLE IF NOT EXISTS "eventSearchText"
                    USING fts5(
                      "title",
                      "keywords",
                      "subtitle",
                      "body",
                      tokenize = 'unicode61',
                      prefix = '2 3'
                    )
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Add OpenMusicEvent contributor DID") { db in
                try #sql("""
                    ALTER TABLE "contributors"
                    ADD COLUMN "did" TEXT
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Add OpenMusicEvent performance contributor credits") { db in
                try #sql("""
                    ALTER TABLE "performanceContributors"
                    ADD COLUMN "billing" TEXT NOT NULL DEFAULT 'primary'
                    """)
                    .execute(db)

                try #sql("""
                    ALTER TABLE "performanceContributors"
                    ADD COLUMN "role" TEXT
                    """)
                    .execute(db)

                try #sql("""
                    ALTER TABLE "performanceContributors"
                    ADD COLUMN "sortIndex" INTEGER NOT NULL DEFAULT 0
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Create OpenMusicEvent relationship schema") { db in
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "relationships" (
                      "type" TEXT NOT NULL,
                      "subject" TEXT NOT NULL,
                      "role" TEXT NOT NULL,
                      "object" TEXT,
                      "createdAt" TEXT NOT NULL
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE INDEX IF NOT EXISTS "relationships_role_createdAt"
                    ON "relationships" ("role", "createdAt")
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "relationshipConfirmations" (
                      "type" TEXT NOT NULL,
                      "relationship" TEXT NOT NULL,
                      "status" TEXT NOT NULL,
                      "createdAt" TEXT NOT NULL
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE INDEX IF NOT EXISTS "relationshipConfirmations_status_createdAt"
                    ON "relationshipConfirmations" ("status", "createdAt")
                    """)
                    .execute(db)
            }
        }
    }
}
