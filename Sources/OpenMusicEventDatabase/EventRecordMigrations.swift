import SQLiteData

public enum EventRecordMigrations {
    public static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create canonical Event record storage") { db in
            try #sql("""
                CREATE TABLE "events.openmusic.event" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "cid" TEXT,
                  "name" TEXT NOT NULL,
                  "createdAt" TEXT NOT NULL,
                  "timeZone" TEXT NOT NULL,
                  "description" TEXT,
                  "start" TEXT,
                  "end" TEXT,
                  "status" TEXT,
                  "mode" TEXT,
                  "locations" TEXT,
                  "links" TEXT,
                  "media" TEXT,
                  "programs" TEXT,
                  "schedules" TEXT,
                  "rsvpExpected" INTEGER,
                  "categories" TEXT,
                  "siteMap" TEXT
                ) STRICT
                """)
                .execute(db)
        }
        migrator.registerMigration("Create canonical Event related record storage") { db in
            try #sql("""
                CREATE TABLE "events.openmusic.program" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "cid" TEXT,
                  "event" TEXT NOT NULL,
                  "title" TEXT NOT NULL,
                  "createdAt" TEXT NOT NULL,
                  "description" TEXT,
                  "icon" TEXT,
                  "eventPlaces" TEXT NOT NULL
                ) STRICT
                """).execute(db)
            try #sql(#"CREATE INDEX "events.openmusic.program.event" ON "events.openmusic.program" ("event")"#).execute(db)
            try #sql("""
                CREATE TABLE "events.openmusic.schedule" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "cid" TEXT,
                  "event" TEXT NOT NULL,
                  "date" TEXT NOT NULL,
                  "createdAt" TEXT NOT NULL,
                  "title" TEXT
                ) STRICT
                """).execute(db)
            try #sql(#"CREATE INDEX "events.openmusic.schedule.event" ON "events.openmusic.schedule" ("event")"#).execute(db)
            try #sql("""
                CREATE TABLE "events.openmusic.eventPlace" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "cid" TEXT,
                  "event" TEXT NOT NULL,
                  "name" TEXT NOT NULL,
                  "createdAt" TEXT NOT NULL,
                  "description" TEXT,
                  "locators" TEXT,
                  "links" TEXT,
                  "media" TEXT,
                  "kind" TEXT
                ) STRICT
                """).execute(db)
            try #sql(#"CREATE INDEX "events.openmusic.eventPlace.event" ON "events.openmusic.eventPlace" ("event")"#).execute(db)
            try #sql("""
                CREATE TABLE "events.openmusic.contributor" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "cid" TEXT,
                  "event" TEXT NOT NULL,
                  "name" TEXT NOT NULL,
                  "createdAt" TEXT NOT NULL,
                  "subject" TEXT,
                  "source" TEXT,
                  "description" TEXT,
                  "roles" TEXT,
                  "links" TEXT,
                  "media" TEXT
                ) STRICT
                """).execute(db)
            try #sql(#"CREATE INDEX "events.openmusic.contributor.event" ON "events.openmusic.contributor" ("event")"#).execute(db)
            try #sql("""
                CREATE TABLE "events.openmusic.programItem" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "cid" TEXT,
                  "event" TEXT NOT NULL,
                  "program" TEXT NOT NULL,
                  "title" TEXT NOT NULL,
                  "createdAt" TEXT NOT NULL,
                  "description" TEXT,
                  "schedule" TEXT,
                  "eventPlace" TEXT,
                  "startsAt" TEXT,
                  "endsAt" TEXT,
                  "credits" TEXT,
                  "media" TEXT
                ) STRICT
                """).execute(db)
            try #sql(#"CREATE INDEX "events.openmusic.programItem.event" ON "events.openmusic.programItem" ("event")"#).execute(db)
            try #sql("""
                CREATE TABLE "social.ome.category" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "cid" TEXT,
                  "event" TEXT NOT NULL,
                  "name" TEXT NOT NULL,
                  "createdAt" TEXT NOT NULL,
                  "description" TEXT,
                  "media" TEXT,
                  "defaultNotificationState" TEXT,
                  "notificationsRequired" INTEGER
                ) STRICT
                """).execute(db)
            try #sql(#"CREATE INDEX "social.ome.category.event" ON "social.ome.category" ("event")"#).execute(db)
            try #sql("""
                CREATE TABLE "social.ome.post" (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "cid" TEXT,
                  "title" TEXT,
                  "text" TEXT NOT NULL,
                  "facets" TEXT,
                  "embed" TEXT,
                  "event" TEXT,
                  "category" TEXT,
                  "syndications" TEXT,
                  "createdAt" TEXT NOT NULL,
                  "updatedAt" TEXT,
                  "delivery" TEXT
                ) STRICT
                """).execute(db)
            try #sql(#"CREATE INDEX "social.ome.post.event" ON "social.ome.post" ("event")"#).execute(db)
        }
        migrator.registerMigration("Add canonical category pinned posts") { db in
            try #sql(#"ALTER TABLE "social.ome.category" ADD COLUMN "pinnedPosts" TEXT"#)
                .execute(db)
        }
        migrator.registerMigration("Add Event local projection provenance") { db in
            try #sql(#"ALTER TABLE "events.openmusic.event" ADD COLUMN "projectionVersion" INTEGER"#)
                .execute(db)
        }
    }
}
