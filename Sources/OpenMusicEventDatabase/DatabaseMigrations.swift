import ATProto
import ATProtoTypes
import Foundation
import GRDB
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

            migrator.registerMigration("Create OpenMusicEvent comms post schema") { db in
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "commsPosts" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "channelID" TEXT NOT NULL,
                      "postID" TEXT NOT NULL,
                      "title" TEXT NOT NULL,
                      "contents" TEXT NOT NULL,
                      "headerImageURL" TEXT,
                      "timestamp" TEXT,
                      "isPinned" INTEGER NOT NULL DEFAULT 0,
                      "sortIndex" INTEGER NOT NULL,
                      PRIMARY KEY ("organizerID", "eventID", "channelID", "postID") ON CONFLICT REPLACE,
                      FOREIGN KEY ("organizerID", "eventID", "channelID")
                        REFERENCES "channels"("organizerID", "eventID", "channelID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE INDEX IF NOT EXISTS "commsPosts_channel_sort"
                    ON "commsPosts" ("organizerID", "eventID", "channelID", "sortIndex")
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Add attached images to OpenMusicEvent comms posts") { db in
                try #sql("""
                    ALTER TABLE "commsPosts"
                    ADD COLUMN "images" TEXT
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Add notification delivery to OpenMusicEvent comms posts") { db in
                try #sql("""
                    ALTER TABLE "commsPosts"
                    ADD COLUMN "delivery" TEXT NOT NULL DEFAULT 'standard'
                    CHECK ("delivery" IN ('standard', 'silent', 'emergency'))
                    """)
                    .execute(db)
            }

            OME.SourceEditingMigrations.register(into: &migrator)
            WorkspacePublicationMigrations.register(into: &migrator)

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

            migrator.registerMigration("Migrate OpenMusicEvent performances to schedule items") { db in
                try #sql("""
                    CREATE TABLE "scheduleItems" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "scheduleItemID" TEXT NOT NULL,
                      "stageID" TEXT NOT NULL,
                      "scheduleID" TEXT,
                      "kind" TEXT NOT NULL,
                      "startTime" TEXT NOT NULL,
                      "endTime" TEXT NOT NULL,
                      "title" TEXT NOT NULL,
                      "description" TEXT,
                      PRIMARY KEY ("organizerID", "eventID", "scheduleItemID") ON CONFLICT REPLACE,
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
                    CREATE TABLE "scheduleItemPerformanceDetails" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "scheduleItemID" TEXT NOT NULL,
                      "recordings" TEXT NOT NULL,
                      PRIMARY KEY ("organizerID", "eventID", "scheduleItemID") ON CONFLICT REPLACE,
                      FOREIGN KEY ("organizerID", "eventID", "scheduleItemID")
                        REFERENCES "scheduleItems"("organizerID", "eventID", "scheduleItemID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE "scheduleItemContributors" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "scheduleItemID" TEXT NOT NULL,
                      "contributorID" TEXT,
                      "anonymousName" TEXT,
                      "contributorActor" TEXT,
                      "billing" TEXT NOT NULL,
                      "role" TEXT,
                      "sortIndex" INTEGER NOT NULL,
                      FOREIGN KEY ("organizerID", "eventID", "scheduleItemID")
                        REFERENCES "scheduleItems"("organizerID", "eventID", "scheduleItemID")
                        ON DELETE CASCADE,
                      FOREIGN KEY ("organizerID", "eventID", "contributorID")
                        REFERENCES "contributors"("organizerID", "eventID", "contributorID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    INSERT INTO "scheduleItems" (
                      "organizerID", "eventID", "scheduleItemID", "stageID", "scheduleID",
                      "kind", "startTime", "endTime", "title", "description"
                    )
                    SELECT
                      "organizerID", "eventID", "performanceID", "stageID", "scheduleID",
                      'performance', "startTime", "endTime", "title", "description"
                    FROM "performances"
                    """)
                    .execute(db)

                try #sql("""
                    INSERT INTO "scheduleItemPerformanceDetails" (
                      "organizerID", "eventID", "scheduleItemID", "recordings"
                    )
                    SELECT "organizerID", "eventID", "performanceID", "recordings"
                    FROM "performances"
                    """)
                    .execute(db)

                try #sql("""
                    INSERT INTO "scheduleItemContributors" (
                      "organizerID", "eventID", "scheduleItemID", "contributorID",
                      "anonymousName", "contributorActor", "billing", "role", "sortIndex"
                    )
                    SELECT
                      "organizerID", "eventID", "performanceID", "contributorID",
                      "anonymousName", "contributorActor", "billing", "role", "sortIndex"
                    FROM "performanceContributors"
                    """)
                    .execute(db)

                try #sql("DROP TABLE \"performanceContributors\"").execute(db)
                try #sql("DROP TABLE \"performances\"").execute(db)

                try #sql("""
                    CREATE VIEW "performances" AS
                    SELECT
                      "scheduleItems"."organizerID",
                      "scheduleItems"."eventID",
                      "scheduleItems"."scheduleItemID" AS "performanceID",
                      "scheduleItems"."stageID",
                      "scheduleItems"."scheduleID",
                      "scheduleItems"."startTime",
                      "scheduleItems"."endTime",
                      "scheduleItems"."title",
                      "scheduleItems"."description",
                      "scheduleItemPerformanceDetails"."recordings"
                    FROM "scheduleItems"
                    JOIN "scheduleItemPerformanceDetails" USING (
                      "organizerID", "eventID", "scheduleItemID"
                    )
                    WHERE "scheduleItems"."kind" = 'performance'
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TRIGGER "performances_insert"
                    INSTEAD OF INSERT ON "performances"
                    BEGIN
                      INSERT OR REPLACE INTO "scheduleItems" (
                        "organizerID", "eventID", "scheduleItemID", "stageID", "scheduleID",
                        "kind", "startTime", "endTime", "title", "description"
                      ) VALUES (
                        NEW."organizerID", NEW."eventID", NEW."performanceID", NEW."stageID",
                        NEW."scheduleID", 'performance', NEW."startTime", NEW."endTime",
                        NEW."title", NEW."description"
                      );

                      INSERT OR REPLACE INTO "scheduleItemPerformanceDetails" (
                        "organizerID", "eventID", "scheduleItemID", "recordings"
                      ) VALUES (
                        NEW."organizerID", NEW."eventID", NEW."performanceID", NEW."recordings"
                      );
                    END
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TRIGGER "performances_update"
                    INSTEAD OF UPDATE ON "performances"
                    BEGIN
                      UPDATE "scheduleItems"
                      SET
                        "stageID" = NEW."stageID",
                        "scheduleID" = NEW."scheduleID",
                        "startTime" = NEW."startTime",
                        "endTime" = NEW."endTime",
                        "title" = NEW."title",
                        "description" = NEW."description"
                      WHERE "organizerID" = OLD."organizerID"
                        AND "eventID" = OLD."eventID"
                        AND "scheduleItemID" = OLD."performanceID";

                      UPDATE "scheduleItemPerformanceDetails"
                      SET "recordings" = NEW."recordings"
                      WHERE "organizerID" = OLD."organizerID"
                        AND "eventID" = OLD."eventID"
                        AND "scheduleItemID" = OLD."performanceID";
                    END
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TRIGGER "performances_delete"
                    INSTEAD OF DELETE ON "performances"
                    BEGIN
                      DELETE FROM "scheduleItems"
                      WHERE "organizerID" = OLD."organizerID"
                        AND "eventID" = OLD."eventID"
                        AND "scheduleItemID" = OLD."performanceID";
                    END
                    """)
                    .execute(db)

                try #sql("""
                    CREATE VIEW "performanceContributors" AS
                    SELECT
                      "scheduleItemContributors"."organizerID",
                      "scheduleItemContributors"."eventID",
                      "scheduleItemContributors"."scheduleItemID" AS "performanceID",
                      "scheduleItemContributors"."contributorID",
                      "scheduleItemContributors"."anonymousName",
                      "scheduleItemContributors"."contributorActor",
                      "scheduleItemContributors"."billing",
                      "scheduleItemContributors"."role",
                      "scheduleItemContributors"."sortIndex"
                    FROM "scheduleItemContributors"
                    JOIN "scheduleItems" USING (
                      "organizerID", "eventID", "scheduleItemID"
                    )
                    WHERE "scheduleItems"."kind" = 'performance'
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TRIGGER "performanceContributors_insert"
                    INSTEAD OF INSERT ON "performanceContributors"
                    BEGIN
                      INSERT INTO "scheduleItemContributors" (
                        "organizerID", "eventID", "scheduleItemID", "contributorID",
                        "anonymousName", "contributorActor", "billing", "role", "sortIndex"
                      ) VALUES (
                        NEW."organizerID", NEW."eventID", NEW."performanceID", NEW."contributorID",
                        NEW."anonymousName", NEW."contributorActor", NEW."billing", NEW."role",
                        NEW."sortIndex"
                      );
                    END
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TRIGGER "performanceContributors_update"
                    INSTEAD OF UPDATE ON "performanceContributors"
                    BEGIN
                      UPDATE "scheduleItemContributors"
                      SET
                        "contributorID" = NEW."contributorID",
                        "anonymousName" = NEW."anonymousName",
                        "contributorActor" = NEW."contributorActor",
                        "billing" = NEW."billing",
                        "role" = NEW."role",
                        "sortIndex" = NEW."sortIndex"
                      WHERE "organizerID" = OLD."organizerID"
                        AND "eventID" = OLD."eventID"
                        AND "scheduleItemID" = OLD."performanceID"
                        AND "contributorID" IS OLD."contributorID"
                        AND "anonymousName" IS OLD."anonymousName"
                        AND "contributorActor" IS OLD."contributorActor"
                        AND "billing" = OLD."billing"
                        AND "role" IS OLD."role"
                        AND "sortIndex" = OLD."sortIndex";
                    END
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TRIGGER "performanceContributors_delete"
                    INSTEAD OF DELETE ON "performanceContributors"
                    BEGIN
                      DELETE FROM "scheduleItemContributors"
                      WHERE "organizerID" = OLD."organizerID"
                        AND "eventID" = OLD."eventID"
                        AND "scheduleItemID" = OLD."performanceID"
                        AND "contributorID" IS OLD."contributorID"
                        AND "anonymousName" IS OLD."anonymousName"
                        AND "contributorActor" IS OLD."contributorActor"
                        AND "billing" = OLD."billing"
                        AND "role" IS OLD."role"
                        AND "sortIndex" = OLD."sortIndex";
                    END
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Key OpenMusicEvent schedule item contributors") { db in
                try #sql("""
                    DELETE FROM "scheduleItemContributors"
                    WHERE "rowid" NOT IN (
                      SELECT MAX("rowid")
                      FROM "scheduleItemContributors"
                      GROUP BY "organizerID", "eventID", "scheduleItemID", "sortIndex"
                    )
                    """)
                    .execute(db)

                try #sql("""
                    CREATE UNIQUE INDEX IF NOT EXISTS "scheduleItemContributors_item_sortIndex"
                    ON "scheduleItemContributors" (
                      "organizerID", "eventID", "scheduleItemID", "sortIndex"
                    )
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Add OpenMusicEvent relationship capabilities") { db in
                try #sql("""
                    ALTER TABLE "relationships"
                    ADD COLUMN "capabilities" TEXT
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Add OpenMusicEvent event reporting links collection") { db in
                try #sql("""
                    ALTER TABLE "events"
                    ADD COLUMN "reportingLinks" TEXT
                    """)
                    .execute(db)

                try #sql("""
                    UPDATE "events"
                    SET "reportingLinks" = json_array(json("reportingLink"))
                    WHERE "reportingLink" IS NOT NULL
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Create OpenMusicEvent local RSVP records") { db in
                // There is deliberately no event foreign key. A catalog refresh or a later
                // transactional event installation must not erase the attendee's local choice.
                try #sql("""
                    CREATE TABLE "app.openmusicevent.rsvp" (
                      "eventURI" TEXT NOT NULL,
                      "consumer" TEXT NOT NULL,
                      "eventCID" TEXT,
                      "status" TEXT NOT NULL,
                      "createdAt" TEXT NOT NULL,
                      PRIMARY KEY ("eventURI", "consumer") ON CONFLICT REPLACE
                    ) STRICT
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Name OpenMusicEvent record tables after their lexicons") { db in
                // These are record stores, so their database names are their collection NSIDs.
                // SQLite updates the existing foreign-key references as each table is renamed.
                try #sql("PRAGMA legacy_alter_table = OFF").execute(db)
                try #sql("ALTER TABLE \"organizers\" RENAME TO \"app.openmusicevent.organizer\"")
                    .execute(db)
                try #sql("ALTER TABLE \"events\" RENAME TO \"app.openmusicevent.event\"")
                    .execute(db)
                try #sql("ALTER TABLE \"calendars\" RENAME TO \"app.openmusicevent.calendar\"")
                    .execute(db)
                try #sql("ALTER TABLE \"calendarEntries\" RENAME TO \"app.openmusicevent.calendar.entry\"")
                    .execute(db)
                try #sql("ALTER TABLE \"eventOrganizers\" RENAME TO \"app.openmusicevent.event.organizer\"")
                    .execute(db)
                try #sql("ALTER TABLE \"stages\" RENAME TO \"app.openmusicevent.stage\"")
                    .execute(db)
                try #sql("ALTER TABLE \"schedules\" RENAME TO \"app.openmusicevent.schedule\"")
                    .execute(db)
                try #sql("ALTER TABLE \"contributors\" RENAME TO \"app.openmusicevent.contributor\"")
                    .execute(db)
                try #sql("ALTER TABLE \"contributorClaims\" RENAME TO \"app.openmusicevent.contributor.claim\"")
                    .execute(db)
                try #sql("ALTER TABLE \"channels\" RENAME TO \"app.openmusicevent.channel\"")
                    .execute(db)
                try #sql("ALTER TABLE \"posters\" RENAME TO \"app.openmusicevent.poster\"")
                    .execute(db)
                try #sql("ALTER TABLE \"relationships\" RENAME TO \"app.openmusicevent.relationship\"")
                    .execute(db)
                try #sql("ALTER TABLE \"relationshipConfirmations\" RENAME TO \"app.openmusicevent.relationship.confirmation\"")
                    .execute(db)

                // Performance remains a compatibility projection over schedule-item storage.
                // Recreate only its public record view; its internal join tables keep local names.
                try #sql("DROP TRIGGER \"performances_insert\"").execute(db)
                try #sql("DROP TRIGGER \"performances_update\"").execute(db)
                try #sql("DROP TRIGGER \"performances_delete\"").execute(db)
                try #sql("DROP VIEW \"performances\"").execute(db)

                try #sql("""
                    CREATE VIEW "app.openmusicevent.performance" AS
                    SELECT
                      "scheduleItems"."organizerID",
                      "scheduleItems"."eventID",
                      "scheduleItems"."scheduleItemID" AS "performanceID",
                      "scheduleItems"."stageID",
                      "scheduleItems"."scheduleID",
                      "scheduleItems"."startTime",
                      "scheduleItems"."endTime",
                      "scheduleItems"."title",
                      "scheduleItems"."description",
                      "scheduleItemPerformanceDetails"."recordings"
                    FROM "scheduleItems"
                    JOIN "scheduleItemPerformanceDetails" USING (
                      "organizerID", "eventID", "scheduleItemID"
                    )
                    WHERE "scheduleItems"."kind" = 'performance'
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TRIGGER "performances_insert"
                    INSTEAD OF INSERT ON "app.openmusicevent.performance"
                    BEGIN
                      INSERT OR REPLACE INTO "scheduleItems" (
                        "organizerID", "eventID", "scheduleItemID", "stageID", "scheduleID",
                        "kind", "startTime", "endTime", "title", "description"
                      ) VALUES (
                        NEW."organizerID", NEW."eventID", NEW."performanceID", NEW."stageID",
                        NEW."scheduleID", 'performance', NEW."startTime", NEW."endTime",
                        NEW."title", NEW."description"
                      );

                      INSERT OR REPLACE INTO "scheduleItemPerformanceDetails" (
                        "organizerID", "eventID", "scheduleItemID", "recordings"
                      ) VALUES (
                        NEW."organizerID", NEW."eventID", NEW."performanceID", NEW."recordings"
                      );
                    END
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TRIGGER "performances_update"
                    INSTEAD OF UPDATE ON "app.openmusicevent.performance"
                    BEGIN
                      UPDATE "scheduleItems"
                      SET
                        "stageID" = NEW."stageID",
                        "scheduleID" = NEW."scheduleID",
                        "startTime" = NEW."startTime",
                        "endTime" = NEW."endTime",
                        "title" = NEW."title",
                        "description" = NEW."description"
                      WHERE "organizerID" = OLD."organizerID"
                        AND "eventID" = OLD."eventID"
                        AND "scheduleItemID" = OLD."performanceID";

                      UPDATE "scheduleItemPerformanceDetails"
                      SET "recordings" = NEW."recordings"
                      WHERE "organizerID" = OLD."organizerID"
                        AND "eventID" = OLD."eventID"
                        AND "scheduleItemID" = OLD."performanceID";
                    END
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TRIGGER "performances_delete"
                    INSTEAD OF DELETE ON "app.openmusicevent.performance"
                    BEGIN
                      DELETE FROM "scheduleItems"
                      WHERE "organizerID" = OLD."organizerID"
                        AND "eventID" = OLD."eventID"
                        AND "scheduleItemID" = OLD."performanceID";
                    END
                    """)
                    .execute(db)
            }
            migrator.registerMigration("Track explicitly installed OpenMusicEvent events") { db in
                // There is deliberately no event foreign key. Published refresh replaces event
                // records transactionally and must not erase the attendee's installation intent.
                try #sql("""
                    CREATE TABLE "installedEvents" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "sourceKind" TEXT,
                      "sourceReference" TEXT,
                      "ref" TEXT,
                      PRIMARY KEY ("organizerID", "eventID") ON CONFLICT REPLACE
                    ) STRICT
                    """)
                    .execute(db)

                // Older attendee databases treated every visible event as installed. Preserve
                // those events unless they were expanded into the writable database by an active
                // source workspace. For that ambiguous legacy case, retain only the app's selected
                // event: authoring must not silently turn every event in the repository into an
                // attendee installation.
                let selectedOrganizerID = try db.tableExists("appState")
                    ? String.fetchOne(
                        db,
                        sql: #"SELECT "organizerID" FROM "appState" WHERE "id" = 1"#
                    )
                    : nil
                let selectedEventID = try db.tableExists("appState")
                    ? String.fetchOne(
                        db,
                        sql: #"SELECT "eventID" FROM "appState" WHERE "id" = 1"#
                    )
                    : nil
                let selectedCoordinates = selectedOrganizerID.flatMap { organizerID in
                    selectedEventID.map { eventID in (organizerID, eventID) }
                }
                let preparedWorkspaceIDs = Set(
                    try SourceWorkspaceInstallationRecord.fetchAll(db).map(\.id)
                )
                let provenancesByEventID = Dictionary(
                    uniqueKeysWithValues: try EventSourceProvenanceRecord.fetchAll(db)
                        .map { ($0.id, $0) }
                )

                for event in try OME.Event.fetchAll(db) {
                    let provenance = provenancesByEventID[event.id]
                    let belongsToPreparedWorkspace = provenance?.workspace.map {
                        preparedWorkspaceIDs.contains($0.id)
                    } ?? false
                    let wasSelected = selectedCoordinates.map {
                        $0.0 == event.id.organizerID.description
                            && $0.1 == event.id.eventID.rawValue.rawValue
                    } ?? false
                    guard !belongsToPreparedWorkspace || wasSelected else { continue }
                    try InstalledEventRecord.insert {
                        InstalledEventRecord(
                            id: event.id,
                            sourceProvenance: provenance?.sourceProvenance
                        )
                    }
                    .execute(db)
                }
            }

            migrator.registerMigration("Track confirmed source workspace canonical resets") { db in
                try #sql("""
                    CREATE TABLE "sourceWorkspaceCanonicalResets" (
                      "id" TEXT PRIMARY KEY NOT NULL
                    ) STRICT
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Create OpenMusicEvent event site maps") { db in
                try #sql("""
                    CREATE TABLE "eventSiteMaps" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "title" TEXT NOT NULL,
                      "defaultStyleID" TEXT,
                      "styles" TEXT NOT NULL,
                      PRIMARY KEY ("organizerID", "eventID") ON CONFLICT REPLACE,
                      FOREIGN KEY ("organizerID", "eventID")
                        REFERENCES "app.openmusicevent.event"("organizerID", "eventID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)
            }
            EventRecordMigrations.register(into: &migrator)

            migrator.registerMigration("Remove retired Event settings") { db in
                try #sql("""
                    ALTER TABLE "app.openmusicevent.event" DROP COLUMN "policies"
                    """).execute(db)
                try #sql("""
                    ALTER TABLE "app.openmusicevent.event" DROP COLUMN "categoryConfigs"
                    """).execute(db)
            }

            migrator.registerMigration("Track installed canonical Events") { db in
                // Keep the attendee's installation choice across a temporary gap or replacement
                // of the published Event record. The Event may arrive again with the same URI.
                try #sql("""
                    CREATE TABLE installedEventRecords (
                      id TEXT PRIMARY KEY NOT NULL
                    ) STRICT
                    """).execute(db)
            }

            migrator.registerMigration("Preserve canonical installations across Event refresh") { db in
                let hasEventForeignKey = try Int.fetchOne(
                    db,
                    sql: "SELECT count(*) FROM pragma_foreign_key_list('installedEventRecords')"
                ) ?? 0
                guard hasEventForeignKey > 0 else { return }

                try #sql("""
                    CREATE TABLE installedEventRecordsWithoutEventForeignKey (
                      id TEXT PRIMARY KEY NOT NULL
                    ) STRICT
                    """).execute(db)
                try #sql("""
                    INSERT INTO installedEventRecordsWithoutEventForeignKey (id)
                    SELECT id FROM installedEventRecords
                    """).execute(db)
                try #sql("DROP TABLE installedEventRecords").execute(db)
                try #sql("""
                    ALTER TABLE installedEventRecordsWithoutEventForeignKey
                    RENAME TO installedEventRecords
                    """).execute(db)
            }

            migrator.registerMigration("Create canonical persistent Stage storage") { db in
                try #sql("""
                    CREATE TABLE "events.openmusic.stage" (
                      "id" TEXT PRIMARY KEY NOT NULL,
                      "cid" TEXT,
                      "name" TEXT NOT NULL,
                      "createdAt" TEXT NOT NULL,
                      "description" TEXT,
                      "links" TEXT,
                      "media" TEXT
                    ) STRICT
                    """).execute(db)
            }

            migrator.registerMigration("Key OpenMusicEvent relationships by record URI") { db in
                try #sql("ALTER TABLE \"app.openmusicevent.relationship\" ADD COLUMN \"id\" TEXT")
                    .execute(db)
                try #sql("ALTER TABLE \"app.openmusicevent.relationship\" ADD COLUMN \"cid\" TEXT")
                    .execute(db)

                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT rowid AS localRowID, "subject", "object", "createdAt"
                        FROM "app.openmusicevent.relationship"
                        ORDER BY rowid
                        """
                )
                var previousIDs: [DID: ATProto.URI] = [:]
                let decoder = JSONDecoder()
                let timestampFormatter = ISO8601DateFormatter()
                for row in rows {
                    let rowID: Int64 = row["localRowID"]
                    let subjectJSON: String = row["subject"]
                    let objectJSON: String? = row["object"]
                    let createdAt: String = row["createdAt"]
                    let subject = try decoder.decode(
                        Open<OME.Relationship.Entity>.self,
                        from: Data(subjectJSON.utf8)
                    )
                    let object = try objectJSON.map {
                        try decoder.decode(
                            Open<OME.Relationship.Entity>.self,
                            from: Data($0.utf8)
                        )
                    }
                    guard let author = OME.Relationship.assertionAuthor(subject: subject, object: object),
                          let date = timestampFormatter.date(from: createdAt)
                    else { throw RelationshipIdentityMigrationError.unaddressableRow(rowID) }
                    let id = try OME.Relationship.nextRecordID(
                        author: author,
                        at: date,
                        after: previousIDs[author]?.rkey
                    )
                    previousIDs[author] = id
                    try #sql("""
                        UPDATE "app.openmusicevent.relationship"
                        SET "id" = \(id.description)
                        WHERE rowid = \(rowID)
                        """).execute(db)
                }

                try #sql("""
                    CREATE TABLE "app.openmusicevent.relationship_canonical" (
                      "id" TEXT PRIMARY KEY NOT NULL,
                      "cid" TEXT,
                      "type" TEXT NOT NULL,
                      "subject" TEXT NOT NULL,
                      "role" TEXT NOT NULL,
                      "object" TEXT,
                      "createdAt" TEXT NOT NULL,
                      "capabilities" TEXT
                    ) STRICT
                    """).execute(db)
                try #sql("""
                    INSERT INTO "app.openmusicevent.relationship_canonical" (
                      "id", "cid", "type", "subject", "role", "object", "createdAt", "capabilities"
                    )
                    SELECT "id", "cid", "type", "subject", "role", "object", "createdAt", "capabilities"
                    FROM "app.openmusicevent.relationship"
                    """).execute(db)
                try #sql("DROP TABLE \"app.openmusicevent.relationship\"").execute(db)
                try #sql("""
                    ALTER TABLE "app.openmusicevent.relationship_canonical"
                    RENAME TO "app.openmusicevent.relationship"
                    """).execute(db)
                try #sql("""
                    CREATE INDEX "relationships_role_createdAt"
                    ON "app.openmusicevent.relationship" ("role", "createdAt")
                    """).execute(db)
            }

            migrator.registerMigration("Persist verified Event record publication receipts") { db in
                try #sql("""
                    CREATE TABLE \(quote: EventRecordPublicationReceipt.tableName) (
                      "id" TEXT PRIMARY KEY NOT NULL,
                      "cid" TEXT NOT NULL,
                      "payloadSHA256" TEXT NOT NULL,
                      "images" TEXT NOT NULL
                    ) STRICT
                    """).execute(db)
            }
            migrator.registerMigration("Preserve canonical source Event identities") { db in
                try #sql("""
                    CREATE TABLE "canonicalSourceEventIdentities" (
                      "id" TEXT PRIMARY KEY NOT NULL,
                      "source" TEXT NOT NULL,
                      "directory" TEXT NOT NULL,
                      "publisher" TEXT NOT NULL,
                      "createdAt" TEXT NOT NULL,
                      UNIQUE("source", "directory", "publisher")
                    ) STRICT
                    """).execute(db)
            }
            migrator.registerMigration("Retain verified Event content for workspace review") { db in
                try #sql("""
                    ALTER TABLE \(quote: EventRecordPublicationReceipt.tableName)
                    ADD COLUMN "event" TEXT
                """).execute(db)
            }
            migrator.registerMigration("Track locally created Events") { db in
                try #sql("""
                    CREATE TABLE \(quote: LocallyCreatedEvent.tableName) (
                      "id" TEXT PRIMARY KEY NOT NULL
                        REFERENCES \(quote: OpenMusicEventLexicon.Event.tableName)("id") ON DELETE CASCADE
                    ) STRICT
                    """).execute(db)
            }
        }
    }
}

private enum RelationshipIdentityMigrationError: Error {
    case unaddressableRow(Int64)
}
