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
                    CREATE TABLE IF NOT EXISTS "participants" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "participantID" TEXT NOT NULL,
                      "name" TEXT NOT NULL,
                      "bio" TEXT,
                      "images" TEXT,
                      "kind" TEXT,
                      "links" TEXT,
                      PRIMARY KEY ("organizerID", "eventID", "participantID") ON CONFLICT REPLACE,
                      FOREIGN KEY ("organizerID", "eventID")
                        REFERENCES "events"("organizerID", "eventID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "participantClaims" (
                      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "participantID" TEXT NOT NULL,
                      FOREIGN KEY ("organizerID", "eventID", "participantID")
                        REFERENCES "participants"("organizerID", "eventID", "participantID")
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
                    CREATE TABLE IF NOT EXISTS "performanceParticipants" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "performanceID" TEXT NOT NULL,
                      "participantID" TEXT,
                      "anonymousName" TEXT,
                      FOREIGN KEY ("organizerID", "eventID", "performanceID")
                        REFERENCES "performances"("organizerID", "eventID", "performanceID")
                        ON DELETE CASCADE,
                      FOREIGN KEY ("organizerID", "eventID", "participantID")
                        REFERENCES "participants"("organizerID", "eventID", "participantID")
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
                    ALTER TABLE "performanceParticipants"
                    ADD COLUMN "participantActor" TEXT
                    """)
                    .execute(db)
            }

            OME.SourceEditingMigrations.register(into: &migrator)

            migrator.registerMigration("Create OpenMusicEvent local image blob schema") { db in
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "localImageBlobs" (
                      "assetKey" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
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
        }
    }
}
