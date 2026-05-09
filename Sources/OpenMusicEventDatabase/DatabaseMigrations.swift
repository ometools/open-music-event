import OpenMusicEventLexicon
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
                      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "name" TEXT NOT NULL,
                      "description" TEXT,
                      "startDate" TEXT,
                      "endDate" TEXT,
                      "status" TEXT NOT NULL,
                      "mode" TEXT NOT NULL,
                      "locations" TEXT,
                      "uris" TEXT,
                      "timeZone" TEXT NOT NULL,
                      "imageURL" TEXT,
                      "iconImageURL" TEXT,
                      "siteMapImageURL" TEXT,
                      "contactNumbers" TEXT,
                      "categoryConfigs" TEXT
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "eventOrganizers" (
                      "eventID" TEXT NOT NULL REFERENCES "events"("id") ON DELETE CASCADE,
                      "organizerID" TEXT NOT NULL REFERENCES "organizers"("id") ON DELETE CASCADE,
                      PRIMARY KEY ("eventID", "organizerID")
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "stages" (
                      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "name" TEXT NOT NULL,
                      "color" INTEGER NOT NULL,
                      "category" TEXT,
                      "sortIndex" INTEGER,
                      "iconImageURL" TEXT,
                      "systemIconName" TEXT,
                      "iconShortCode" TEXT,
                      "imageURL" TEXT,
                      "posterImageURL" TEXT,
                      "lineup" TEXT
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "schedules" (
                      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "eventID" TEXT NOT NULL REFERENCES "events"("id") ON DELETE CASCADE,
                      "date" TEXT NOT NULL,
                      "startsAt" TEXT,
                      "endsAt" TEXT,
                      "customTitle" TEXT
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "participants" (
                      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "name" TEXT NOT NULL,
                      "bio" TEXT,
                      "imageURL" TEXT,
                      "logoURL" TEXT,
                      "kind" TEXT,
                      "links" TEXT
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "participantClaims" (
                      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "participantID" TEXT NOT NULL REFERENCES "participants"("id") ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "channels" (
                      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "eventID" TEXT NOT NULL REFERENCES "events"("id") ON DELETE CASCADE,
                      "name" TEXT NOT NULL,
                      "description" TEXT NOT NULL,
                      "iconImageURL" TEXT,
                      "headerImageURL" TEXT,
                      "sortIndex" INTEGER,
                      "defaultNotificationState" TEXT NOT NULL,
                      "notificationsRequired" INTEGER NOT NULL DEFAULT 0
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "posters" (
                      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "eventID" TEXT NOT NULL REFERENCES "events"("id") ON DELETE CASCADE,
                      "title" TEXT,
                      "imageURL" TEXT NOT NULL
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "performances" (
                      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "eventID" TEXT NOT NULL REFERENCES "events"("id") ON DELETE CASCADE,
                      "stageID" TEXT NOT NULL REFERENCES "stages"("id") ON DELETE CASCADE,
                      "scheduleID" TEXT REFERENCES "schedules"("id") ON DELETE CASCADE,
                      "startTime" TEXT NOT NULL,
                      "endTime" TEXT NOT NULL,
                      "title" TEXT NOT NULL,
                      "description" TEXT,
                      "recordings" TEXT NOT NULL
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "performanceParticipants" (
                      "performanceID" TEXT NOT NULL REFERENCES "performances"("id") ON DELETE CASCADE,
                      "participantID" TEXT REFERENCES "participants"("id") ON DELETE CASCADE,
                      "anonymousName" TEXT
                    ) STRICT
                    """)
                    .execute(db)
            }
        }
    }
}
