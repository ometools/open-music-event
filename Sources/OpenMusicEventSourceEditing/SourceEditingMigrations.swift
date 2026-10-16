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

            migrator.registerMigration("Create canonical OpenMusicEvent source workspace schema") {
                db in
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "sourceWorkspaceRelationships" (
                      "workspaceID" TEXT NOT NULL,
                      "actorID" TEXT NOT NULL,
                      "recordKey" TEXT NOT NULL,
                      "relationship" TEXT NOT NULL,
                      PRIMARY KEY ("workspaceID", "actorID") ON CONFLICT REPLACE,
                      UNIQUE ("workspaceID", "recordKey") ON CONFLICT REPLACE
                    ) STRICT
                    """)
                    .execute(db)
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "sourceWorkspaceAuthoringActivations" (
                      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                      "principal" TEXT NOT NULL,
                      "role" TEXT NOT NULL,
                      "activatedAt" TEXT NOT NULL
                    ) STRICT
                    """)
                    .execute(db)
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "sourceWorkspaceReferences" (
                      "id" TEXT PRIMARY KEY NOT NULL,
                      "revision" TEXT NOT NULL
                    ) STRICT
                    """)
                    .execute(db)
                try #sql("""
                    CREATE TABLE IF NOT EXISTS "sourceWorkspaceInstallations" (
                      "id" TEXT PRIMARY KEY NOT NULL,
                      "revision" TEXT NOT NULL
                    ) STRICT
                    """)
                    .execute(db)

                // Forward-only cleanup for databases that ran the unshipped parallel workspace
                // experiment. These tables are not part of the current runtime model.
                for tableName in [
                    "workspacePublications",
                    "workspaceAuthoringActivations",
                    "workspaceRelationships",
                    "eventEditingWorkspaces",
                    "editingWorkspaces",
                ] {
                    try #sql("DROP TABLE IF EXISTS \(quote: tableName)").execute(db)
                }
                if try db.columns(in: "eventSourceProvenances")
                    .contains(where: { $0.name == "sourceBaselineID" })
                {
                    try #sql(
                        "ALTER TABLE \"eventSourceProvenances\" DROP COLUMN \"sourceBaselineID\""
                    )
                    .execute(db)
                }
                try #sql("DROP TABLE IF EXISTS \"sourceBaselines\"").execute(db)
            }

            migrator.registerMigration("Persist selected source workspace branches") { db in
                try #sql("""
                    CREATE TABLE "sourceWorkspaceSelections" (
                      "id" TEXT PRIMARY KEY NOT NULL,
                      "branch" TEXT NOT NULL,
                      "revision" TEXT NOT NULL
                    ) STRICT
                    """)
                    .execute(db)

                for installation in try SourceWorkspaceInstallationRecord.all.fetchAll(db) {
                    let workspace = try SourceWorkspace(id: installation.id)
                    try SourceWorkspaceSelectionRecord.insert {
                        SourceWorkspaceSelectionRecord(
                            id: installation.id,
                            branch: workspace.defaultBranch,
                            revision: installation.revision
                        )
                    }
                    .execute(db)
                }
            }
        }
    }
}
