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

            migrator.registerMigration("Create OpenMusicEvent editing workspace schema") { db in
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "editingWorkspaces" (
                      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "kind" TEXT NOT NULL,
                      "databaseFileName" TEXT NOT NULL,
                      "createdAt" TEXT NOT NULL,
                      "updatedAt" TEXT NOT NULL,
                      "sourceBaselineID" TEXT REFERENCES "sourceBaselines"("id") ON DELETE SET NULL
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    CREATE TABLE IF NOT EXISTS "eventEditingWorkspaces" (
                      "organizerID" TEXT NOT NULL,
                      "eventID" TEXT NOT NULL,
                      "workspaceID" TEXT NOT NULL REFERENCES "editingWorkspaces"("id") ON DELETE CASCADE,
                      PRIMARY KEY ("organizerID", "eventID") ON CONFLICT REPLACE,
                      FOREIGN KEY ("organizerID", "eventID")
                        REFERENCES "events"("organizerID", "eventID")
                        ON DELETE CASCADE
                    ) STRICT
                    """)
                    .execute(db)

                try #sql("""
                    INSERT OR REPLACE INTO "editingWorkspaces" (
                      "id",
                      "kind",
                      "databaseFileName",
                      "createdAt",
                      "updatedAt",
                      "sourceBaselineID"
                    )
                    SELECT
                      'team.' || "id",
                      'team',
                      "databaseFileName",
                      "importedAt",
                      "importedAt",
                      "id"
                    FROM "sourceBaselines"
                    """)
                    .execute(db)

                try #sql("""
                    INSERT OR REPLACE INTO "eventEditingWorkspaces" (
                      "organizerID",
                      "eventID",
                      "workspaceID"
                    )
                    SELECT
                      "organizerID",
                      "eventID",
                      'team.' || "sourceBaselineID"
                    FROM "eventSourceProvenances"
                    WHERE "sourceBaselineID" IS NOT NULL
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Identify published OpenMusicEvent workspaces") { db in
                try #sql("""
                    ALTER TABLE "editingWorkspaces"
                    ADD COLUMN "publicRecord" TEXT
                    """)
                    .execute(db)

                try #sql("""
                    UPDATE "editingWorkspaces"
                    SET "publicRecord" = (
                      SELECT json_object(
                        '$type', 'app.openmusicevent.relationship#record',
                        'uri', 'at://' || "eventEditingWorkspaces"."organizerID"
                          || '/app.openmusicevent.source/canonical'
                      )
                      FROM "eventEditingWorkspaces"
                      WHERE "eventEditingWorkspaces"."workspaceID" = "editingWorkspaces"."id"
                      LIMIT 1
                    )
                    WHERE "kind" = 'team'
                      AND EXISTS (
                        SELECT 1
                        FROM "sourceBaselines"
                        WHERE "sourceBaselines"."id" = "editingWorkspaces"."sourceBaselineID"
                          AND "sourceBaselines"."sourceKind" = 'tangled'
                      )
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Create OpenMusicEvent workspace relationship schema") { db in
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "workspaceRelationships" (
                      "workspaceID" TEXT NOT NULL
                        REFERENCES "editingWorkspaces"("id") ON DELETE CASCADE,
                      "actorID" TEXT NOT NULL,
                      "recordKey" TEXT NOT NULL,
                      "relationship" TEXT NOT NULL,
                      PRIMARY KEY ("workspaceID", "actorID") ON CONFLICT REPLACE,
                      UNIQUE ("workspaceID", "recordKey") ON CONFLICT REPLACE
                    ) STRICT
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Create OpenMusicEvent workspace authoring activation schema") { db in
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "workspaceAuthoringActivations" (
                      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE
                        REFERENCES "editingWorkspaces"("id") ON DELETE CASCADE,
                      "principal" TEXT NOT NULL,
                      "role" TEXT NOT NULL,
                      "activatedAt" TEXT NOT NULL
                    ) STRICT
                    """)
                    .execute(db)
            }

            migrator.registerMigration("Name editing workspace reference databases") { db in
                try #sql("""
                    ALTER TABLE "editingWorkspaces"
                    RENAME COLUMN "databaseFileName" TO "referenceDatabaseFileName"
                    """)
                    .execute(db)
            }
        }
    }
}
