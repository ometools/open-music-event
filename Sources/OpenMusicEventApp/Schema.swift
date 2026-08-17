import BlueskyActorCache
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SQLiteData
import SourceEditing
import OSLog

public typealias OMERecord = OpenMusicEventLexicon.OpenMusicEvent

extension ExternalPlatform: SQLiteType {}
let dbLogger: Logger = Logger(subsystem: "fm.woody.openmusicevent", category: "database")

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
                    dbLogger.debug("\($0.expandedDescription)")
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
    #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
    #endif
    OME.DatabaseMigrations.register(into: &migrator)
    BlueskyActorCacheMigrations.register(into: &migrator)
    OpenMusicEventAppDatabaseMigrations.register(into: &migrator)

    try migrator.migrate(database)
    try database.write { db in
        try EventSearchTextTriggers.install(in: db)
        try EventSearchSources.installTriggers(in: db)
        try EventSearchSources.rebuild(in: db)
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
              "organizerID" TEXT NOT NULL,
              "eventID" TEXT NOT NULL,
              "channelID" TEXT NOT NULL,
              "notificationState" TEXT NOT NULL,
              PRIMARY KEY ("organizerID", "eventID", "channelID") ON CONFLICT REPLACE
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
        // Reactions intentionally have no foreign key to performances. Source imports replace
        // performance rows, while this device-local state is keyed by their stable identity.
        try #sql("""
            CREATE TABLE "performanceReactions" (
              "id" TEXT PRIMARY KEY NOT NULL,
              "organizerID" TEXT NOT NULL,
              "eventID" TEXT NOT NULL,
              "performanceID" TEXT NOT NULL,
              "emoji" TEXT NOT NULL,
              "reactedAt" TEXT NOT NULL,
              "userDID" TEXT,
              UNIQUE ("organizerID", "eventID", "performanceID", "emoji")
            ) STRICT
            """)
            .execute(db)

        try #sql("""
            CREATE INDEX "performanceReactionsByEvent"
            ON "performanceReactions" ("organizerID", "eventID")
            """)
            .execute(db)

        try #sql("""
            CREATE INDEX "performanceReactionsByPerformance"
            ON "performanceReactions" ("organizerID", "eventID", "performanceID")
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
              "organizerID" TEXT NOT NULL,
              "eventID" TEXT NOT NULL,
              "channelID" TEXT NOT NULL,
              "postID" TEXT NOT NULL,
              PRIMARY KEY ("organizerID", "eventID", "channelID", "postID")
            ) STRICT
            """
        )
        .execute(db)
    }
    }
}

@Table("appState")
public struct AppState: Equatable, Sendable, Identifiable {
    public let id: Int
    public var organizerID: OMERecord.Organizer.ID?
    public var eventID: OMERecord.ID<OMERecord.Event>?

    public init(id: Int = 1, selectedEventID: OMERecord.Event.ID? = nil) {
        self.id = id
        self.organizerID = selectedEventID?.organizerID
        self.eventID = selectedEventID?.eventID
    }

    public var selectedEventID: OMERecord.Event.ID? {
        guard let organizerID, let eventID else { return nil }
        return OMERecord.Event.ID(organizerID: organizerID, eventID: eventID)
    }
}

@Table("organizerPreferences")
public struct OrganizerPreferences: Equatable, Sendable, Identifiable {
    @Column(primaryKey: true) public var organizerID: OMERecord.Organizer.ID
    public var isFollowing = false

    public var id: OMERecord.Organizer.ID { organizerID }
}

@Table("contributorPreferences")
struct ContributorPreferences: Equatable, Sendable, Identifiable {
    var id: OMERecord.Contributor.ID
    var isFavorite = false
}

@Table("posterPreferences")
struct PosterPreferences: Equatable, Sendable, Identifiable {
    var id: OMERecord.Poster.ID
    var isRead = false
    var isFavorite = false
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
