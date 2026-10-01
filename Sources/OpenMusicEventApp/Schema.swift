import Bluesky
import ATProtoSQLite
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SQLiteData
import SourceEditing
#if canImport(OSLog)
import OSLog
#endif

public typealias OMERecord = OpenMusicEventLexicon.OpenMusicEvent

extension ExternalPlatform: SQLiteType {}
#if canImport(OSLog)
let dbLogger: Logger = Logger(subsystem: "fm.woody.openmusicevent", category: "database")
#endif

public extension OpenMusicEventServiceEnvironment {
    var databaseFileName: String {
        switch self {
        case .production:
            "open-music-event.sqlite"
        case .staging:
            "open-music-event-staging.sqlite"
        }
    }

    func databaseURL(in applicationSupportURL: URL) -> URL {
        applicationSupportURL.appendingPathComponent(databaseFileName)
    }
}

extension DependencyValues {
    mutating func bootstrapDatabase(
        environment: OpenMusicEventServiceEnvironment = .production
    ) throws {
        @Dependency(\.context) var context

        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.foreignKeysEnabled = true

        #if DEBUG
        configuration.prepareDatabase { db in
            db.trace(options: .statement) {
                if context == .preview {
                    print($0.expandedDescription)
                } else {
                    #if canImport(OSLog)
                    dbLogger.debug("\($0.expandedDescription)")
                    #else
                    print($0.expandedDescription)
                    #endif
                }
            }
        }
        #endif

        let path: String?
        if context == .live {
            let applicationSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            try FileManager.default.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
            let databaseURL = environment.databaseURL(in: applicationSupportURL)
            #if DEBUG
            let openDatabaseCommand = "open \(databaseURL.path.shellQuotedForTerminal)"
            logger.debug("\(openDatabaseCommand)")
            #endif
            path = databaseURL.path
        } else {
            path = nil
        }
        let database = try SQLiteData.defaultDatabase(path: path, configuration: configuration)

        try prepareOpenMusicEventDatabase(database)

        if context == .live {
            do {
                try removeObsoleteEditingWorkspaceDatabases()
            } catch {
                logger.error("Unable to remove obsolete editing workspace databases: \(String(describing: error))")
            }
        }

        defaultDatabase = database
    }
}

func removeObsoleteEditingWorkspaceDatabases(
    applicationSupportDirectory: URL? = nil
) throws {
    let applicationSupportDirectory = try applicationSupportDirectory ?? FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let obsoleteDirectory = applicationSupportDirectory
        .standardizedFileURL
        .appending(path: "EditingWorkspaces", directoryHint: .isDirectory)
    do {
        try FileManager.default.removeItem(at: obsoleteDirectory)
    } catch {
        let error = error as NSError
        guard error.domain == NSCocoaErrorDomain,
              error.code == NSFileNoSuchFileError
        else { throw error }
    }
}

private func prepareOpenMusicEventDatabase(
    _ database: any DatabaseWriter
) throws {
    var migrator = DatabaseMigrator()
    OME.DatabaseMigrations.register(into: &migrator)
    BlueskyActorCacheMigrations.register(into: &migrator)
    OpenMusicEventAppDatabaseMigrations.register(into: &migrator)

    try migrator.migrate(database)
    try database.write { db in
    }
}

private extension String {
    var shellQuotedForTerminal: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

public enum OpenMusicEventAppDependencies {
    public static func prepareDatabase(
        _ dependencies: inout DependencyValues,
        environment: OpenMusicEventServiceEnvironment = .production
    ) throws {
        try dependencies.bootstrapDatabase(environment: environment)
    }
}

public enum OpenMusicEventAppDatabaseMigrations {
    public static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create OpenMusicEvent app schema") { db in
        try #sql("""
            CREATE TABLE IF NOT EXISTS "organizerPreferences" (
              "organizerID" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
              "isFollowing" INTEGER NOT NULL DEFAULT 0
            ) STRICT
            """)
            .execute(db)

        try #sql("""
            CREATE TABLE IF NOT EXISTS "contributorPreferences" (
              "organizerID" TEXT NOT NULL,
              "eventID" TEXT NOT NULL,
              "contributorID" TEXT NOT NULL,
              "isFavorite" INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY ("organizerID", "eventID", "contributorID") ON CONFLICT REPLACE
            ) STRICT
            """)
            .execute(db)

        try #sql("""
            CREATE TABLE IF NOT EXISTS "performancePreferences" (
              "organizerID" TEXT NOT NULL,
              "eventID" TEXT NOT NULL,
              "performanceID" TEXT NOT NULL,
              "interested" INTEGER NOT NULL DEFAULT 0,
              "seen" INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY ("organizerID", "eventID", "performanceID") ON CONFLICT REPLACE
            ) STRICT
            """)
            .execute(db)

        try #sql("""
            CREATE TABLE IF NOT EXISTS "channelPreferences" (
              "id" TEXT NOT NULL PRIMARY KEY ON CONFLICT REPLACE,
              "notificationState" TEXT NOT NULL
            ) STRICT
            """)
            .execute(db)

        try #sql("""
            CREATE TABLE IF NOT EXISTS "posterPreferences" (
              "organizerID" TEXT NOT NULL,
              "eventID" TEXT NOT NULL,
              "posterID" TEXT NOT NULL,
              "isRead" INTEGER NOT NULL DEFAULT 0,
              "isFavorite" INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY ("organizerID", "eventID", "posterID") ON CONFLICT REPLACE
            ) STRICT
            """)
            .execute(db)

        try #sql("""
            CREATE TABLE IF NOT EXISTS "externalAssetPreferences" (
              "assetURL" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
              "platform" TEXT,
              "cachedTitle" TEXT,
              "cachedDescription" TEXT,
              "cachedThumbnailURL" TEXT,
              "cachedDurationSeconds" INTEGER,
              "lastMetadataFetchAttemptAt" TEXT,
              "isWatched" INTEGER NOT NULL DEFAULT 0,
              "isFavorite" INTEGER NOT NULL DEFAULT 0,
              "lastAccessedAt" TEXT,
              "playbackPositionSeconds" INTEGER
            ) STRICT
            """)
            .execute(db)

        try #sql("""
            CREATE TABLE IF NOT EXISTS "appState" (
              "id" INTEGER PRIMARY KEY CHECK ("id" = 1),
              "organizerID" TEXT,
              "eventID" TEXT
            ) STRICT
            """)
            .execute(db)

        try #sql("""
            INSERT OR IGNORE INTO "appState" ("id", "organizerID", "eventID")
            VALUES (1, NULL, NULL)
            """)
            .execute(db)

        try #sql("""
            CREATE TABLE IF NOT EXISTS "eventViewerState" (
              "organizerID" TEXT NOT NULL,
              "eventID" TEXT NOT NULL,
              "selectedScheduleID" TEXT,
              PRIMARY KEY ("organizerID", "eventID") ON CONFLICT REPLACE
            ) STRICT
            """)
            .execute(db)

        try #sql("""
            CREATE TABLE IF NOT EXISTS "scheduleViewerState" (
              "organizerID" TEXT NOT NULL,
              "eventID" TEXT NOT NULL,
              "category" TEXT,
              "selectedStageID" TEXT,
              "showStageNameLabels" INTEGER NOT NULL DEFAULT 0,
              "filteringFavorites" INTEGER NOT NULL DEFAULT 0,
              "filteringInterested" INTEGER NOT NULL DEFAULT 0,
              "scheduleKind" TEXT NOT NULL DEFAULT 'singleStageAtOnce',
              PRIMARY KEY ("organizerID", "eventID", "category")
            ) STRICT
            """)
            .execute(db)
    }

    migrator.registerMigration("Create OpenMusicEvent contributor preferences") { db in
        try #sql("""
            CREATE TABLE IF NOT EXISTS "contributorPreferences" (
              "organizerID" TEXT NOT NULL,
              "eventID" TEXT NOT NULL,
              "contributorID" TEXT NOT NULL,
              "isFavorite" INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY ("organizerID", "eventID", "contributorID") ON CONFLICT REPLACE
            ) STRICT
            """)
            .execute(db)
    }

    migrator.registerMigration("Add many-stage schedule orientation") { db in
        try #sql("""
            ALTER TABLE "scheduleViewerState"
            ADD COLUMN "manyStagesOrientation" TEXT NOT NULL DEFAULT 'vertical'
            """)
            .execute(db)
    }
    migrator.registerMigration("Add local performance reactions") { db in
        // Device-local reactions follow the stable program item record URI.
        try #sql("""
            CREATE TABLE "performanceReactions" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "performanceID" TEXT NOT NULL,
              "emoji" TEXT NOT NULL,
              "reactedAt" TEXT NOT NULL,
              "userDID" TEXT,
              UNIQUE ("performanceID", "emoji")
            ) STRICT
            """)
            .execute(db)

        try #sql("""
            CREATE INDEX "performanceReactionsByPerformance"
            ON "performanceReactions" ("performanceID")
            """)
            .execute(db)

        try #sql("""
            CREATE TABLE "performanceReactionEmojiUsage" (
              "emoji" TEXT PRIMARY KEY NOT NULL,
              "selectionCount" INTEGER NOT NULL,
              "lastUsedAt" TEXT NOT NULL
            ) STRICT
            """)
            .execute(db)

        try #sql("DROP TABLE \"performancePreferences\"").execute(db)
        try #sql("""
            ALTER TABLE "scheduleViewerState"
            DROP COLUMN "filteringInterested"
            """)
            .execute(db)
    }

    migrator.registerMigration("Create OpenMusicEvent user schedule schema") { db in
        try #sql("""
            CREATE TABLE "userSchedules" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "organizerID" TEXT NOT NULL,
              "eventID" TEXT NOT NULL,
              "title" TEXT NOT NULL CHECK (
                "title" = trim(
                  "title",
                  char(9) || char(10) || char(11) || char(12) || char(13) || ' '
                )
                AND length("title") BETWEEN 1 AND 80
              ),
              "userDID" TEXT
            ) STRICT
            """)
            .execute(db)

        try #sql("""
            CREATE UNIQUE INDEX "userSchedules_event_title"
            ON "userSchedules" ("organizerID", "eventID", "title" COLLATE NOCASE)
            """)
            .execute(db)

        try #sql("""
            CREATE TABLE "userSchedulePerformances" (
              "scheduleID" TEXT NOT NULL REFERENCES "userSchedules" ("id") ON DELETE CASCADE,
              "performanceID" TEXT NOT NULL,
              PRIMARY KEY ("scheduleID", "performanceID")
            ) STRICT
            """)
            .execute(db)

        try #sql("""
            ALTER TABLE "eventViewerState"
            ADD COLUMN "selectedUserScheduleID" TEXT
            """)
            .execute(db)

        try #sql("""
            ALTER TABLE "eventViewerState"
            ADD COLUMN "didInitializeUserSchedules" INTEGER NOT NULL DEFAULT 0
            """)
            .execute(db)
    }

    migrator.registerMigration("Create local communication post read state") { db in
        let tableName = CommsPostRead.tableName
        try #sql(
            """
            CREATE TABLE \(quote: tableName) (
              "id" TEXT NOT NULL PRIMARY KEY
            ) STRICT
            """
        )
        .execute(db)
    }

    migrator.registerMigration("Remove stage label preferences") { db in
        try #sql("""
            ALTER TABLE "scheduleViewerState" DROP COLUMN "showStageNameLabels"
            """).execute(db)
    }

    migrator.registerMigration("Store selected canonical event URI") { db in
        try #sql("""
            ALTER TABLE "appState" ADD COLUMN "selectedEventURI" TEXT
            """).execute(db)
    }

    migrator.registerMigration("Use canonical Event IDs for viewer state") { db in
        try #sql("DROP TABLE \"eventViewerState\"").execute(db)
        try #sql("""
            CREATE TABLE "eventViewerState" (
              "id" TEXT NOT NULL PRIMARY KEY,
              "selectedScheduleID" TEXT,
              "selectedUserScheduleID" TEXT,
              "didInitializeUserSchedules" INTEGER NOT NULL DEFAULT 0
            ) STRICT
            """).execute(db)

        try #sql("DROP TABLE \"scheduleViewerState\"").execute(db)
        try #sql("""
            CREATE TABLE "scheduleViewerState" (
              "eventID" TEXT NOT NULL,
              "category" TEXT NOT NULL,
              "selectedStageID" TEXT,
              "filteringFavorites" INTEGER NOT NULL DEFAULT 0,
              "scheduleKind" TEXT NOT NULL DEFAULT 'singleStageAtOnce',
              "manyStagesOrientation" TEXT NOT NULL DEFAULT 'vertical',
              PRIMARY KEY ("eventID", "category")
            ) STRICT
            """).execute(db)
    }

    migrator.registerMigration("Use canonical Event IDs for user schedules") { db in
        try #sql("DROP INDEX \"userSchedules_event_title\"").execute(db)
        // Keep the full identity of schedules written with the old split key.
        // Their legacy record URIs can be remapped during the one-time import.
        try #sql("""
            UPDATE "userSchedules"
            SET "eventID" = 'at://' || "organizerID" || '/app.openmusicevent.event/' || "eventID"
            WHERE "eventID" NOT LIKE 'at://%'
            """).execute(db)
        try #sql("ALTER TABLE \"userSchedules\" DROP COLUMN \"organizerID\"").execute(db)
        try #sql("""
            CREATE UNIQUE INDEX "userSchedules_event_title"
            ON "userSchedules" ("eventID", "title" COLLATE NOCASE)
            """).execute(db)
    }
    }
}

@Table("appState")
public struct AppState: Equatable, Sendable, Identifiable {
    public let id: Int
    public var selectedEventURI: Event.ID?

    public init(id: Int = 1, selectedEventID: Event.ID? = nil) {
        self.id = id
        self.selectedEventURI = selectedEventID
    }

    public var selectedEventID: Event.ID? {
        selectedEventURI
    }
}

@Table("externalAssetPreferences")
struct ExternalAssetPreferences: Equatable, Sendable, Identifiable {
    @Column(primaryKey: true) var assetURL: URL
    var platform: ExternalPlatform?
    var cachedTitle: String?
    var cachedDescription: String?
    var cachedThumbnailURL: URL?
    var cachedDurationSeconds: Int?
    var lastMetadataFetchAttemptAt: Date?
    var isWatched = false
    var isFavorite = false
    var lastAccessedAt: Date?
    var playbackPositionSeconds: Int?

    var id: URL { assetURL }
}
