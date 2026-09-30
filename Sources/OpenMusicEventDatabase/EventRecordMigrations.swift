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
    }
}
