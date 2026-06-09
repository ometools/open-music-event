import BlueskyActorCache
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SQLiteData
import SourceEditing

public typealias OMERecord = OpenMusicEventLexicon.OpenMusicEvent

extension ExternalPlatform: SQLiteType {}

extension DependencyValues {
    mutating func bootstrapDatabase() throws {
        @Dependency(\.context) var context
        @Dependency(\.sourcePatchInvalidations) var sourcePatchInvalidations

        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.foreignKeysEnabled = true

        #if DEBUG
        configuration.prepareDatabase { db in
            db.trace(options: .profile) {
                if context == .preview {
                    print($0.expandedDescription)
                } else {
                    logger.debug("\($0.expandedDescription)")
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
            let databaseURL = applicationSupportURL.appendingPathComponent("open-music-event.sqlite")
            path = databaseURL.path
        } else {
            path = nil
        }
        let database = try SQLiteData.defaultDatabase(path: path, configuration: configuration)
        sourceEditingWorkingDatabasePath = path

        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        OME.DatabaseMigrations.register(into: &migrator)
        BlueskyActorCacheMigrations.register(into: &migrator)
        registerOpenMusicEventAppMigrations(into: &migrator)

        try migrator.migrate(database)
        try database.write { db in
            try sourcePatchInvalidations.installTriggers(db)
        }
        defaultDatabase = database
    }
}

private func registerOpenMusicEventAppMigrations(into migrator: inout DatabaseMigrator) {
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

@Table("performancePreferences")
struct PerformancePreferences: Equatable, Sendable, Identifiable {
    var id: OMERecord.Performance.ID
    var interested = false
    var seen = false
}

@Table("channelPreferences")
struct ChannelPreferences: Equatable, Sendable, Identifiable {
    var id: OMERecord.Channel.ID
    var notificationState: OMERecord.Channel.NotificationState
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
