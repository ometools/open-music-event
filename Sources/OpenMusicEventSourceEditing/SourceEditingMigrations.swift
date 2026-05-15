import OpenMusicEventLexicon
import SQLiteData

public extension OME {
    enum SourceEditingMigrations {
        public static func register(into migrator: inout DatabaseMigrator) {
            migrator.registerMigration("Create OpenMusicEvent source provenance schema") { db in
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "eventSourceProvenances" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "sourceKind" TEXT NOT NULL,
                      "sourceReference" TEXT NOT NULL,
                      "ref" TEXT,
                      "eventIDOrigin" TEXT NOT NULL,
                      "sourceEventDirectory" TEXT NOT NULL,
                      PRIMARY KEY ("organizerID", "eventID") ON CONFLICT REPLACE,
                      FOREIGN KEY ("organizerID", "eventID")
                        REFERENCES "events"("organizerID", "eventID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Create OpenMusicEvent source baseline schema") { db in
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "sourceBaselines" (
                      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "sourceKind" TEXT NOT NULL,
                      "sourceReference" TEXT NOT NULL,
                      "ref" TEXT,
                      "databaseFileName" TEXT NOT NULL,
                      "importedAt" TEXT NOT NULL
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    ALTER TABLE "eventSourceProvenances"
                    ADD COLUMN "sourceBaselineID" TEXT REFERENCES "sourceBaselines"("id") ON DELETE SET NULL
                    """)
                    .execute(db)
            }
        }
    }
}

