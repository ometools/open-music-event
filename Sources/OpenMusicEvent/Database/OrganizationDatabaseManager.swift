//
//  OrganizationDatabaseManager.swift
//  open-music-event
//
//  Created by Claude on 12/8/24.
//

import GRDB
import Foundation
import Dependencies
import CoreModels

/// Manages per-organization databases with co-located file storage
struct OrganizationDatabaseManager {

    // MARK: - Paths

    /// Root directory for all organizations
    /// iOS: ~/Documents/open-music-event/
    /// macOS: ~/Documents/open-music-event/
    static var organizationsDirectory: URL {
        #if os(Android)
        let root = URL.applicationSupportDirectory
        #else
        let root = URL.documentsDirectory
        #endif
        return root.appendingPathComponent("open-music-event")
    }


    /// Path to user preferences database (app-private)
    static var userPreferencesDatabasePath: URL {
        organizationsDirectory.appendingPathComponent("user-preferences.sqlite")
    }

    // MARK: - Organization Database

    func openDatabase(id: Organizer.ID) throws -> DatabaseQueue {
        let orgPath = OrganizationDatabaseManager.organizationsDirectory
            .appendingPathComponent("\(id.rawValue)")
        return try openDatabase(at: orgPath)
    }

    /// Opens database for a specific organization
    /// Database is co-located with files at: {orgPath}/.ome/org.db
    func openDatabase(at orgPath: URL) throws -> DatabaseQueue {
        let omeDir = orgPath.appendingPathComponent(".ome")
        let dbPath = omeDir.appendingPathComponent("organization.db")

        // Create .ome directory if needed
        try FileManager.default.createDirectory(
            at: omeDir,
            withIntermediateDirectories: true
        )

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true

        // ATTACH user preferences database on every connection
        configuration.prepareDatabase { db in

            #if DEBUG
            db.trace(options: .profile) {
                print("[\(orgPath.lastPathComponent)] \($0.expandedDescription)")
            }
            #endif

            let userPrefsPath = OrganizationDatabaseManager.userPreferencesDatabasePath.path()
            try db.execute(sql: "ATTACH DATABASE '\(userPrefsPath)' AS userprefs")
        }

        let db = try DatabaseQueue(path: dbPath.path(), configuration: configuration)

        // Run migrations
        var migrator = DatabaseMigrator()

        migrator.registerMigration("Create tables") { db in
            try sql("""
            CREATE TABLE organizers (
                "id" TEXT PRIMARY KEY NOT NULL,
                "url" TEXT,
                "name" TEXT NOT NULL,
                "imageURL" TEXT,
                "iconImageURL" TEXT
            ) STRICT;
            """).execute(db)

            try sql("""
            CREATE TABLE musicEvents(
                "id" TEXT PRIMARY KEY NOT NULL,
                "organizerID" TEXT,
                "name" TEXT NOT NULL,
                "startTime" TEXT,
                "endTime" TEXT,
                "timeZone" TEXT,
                "imageURL" TEXT,
                "iconImageURL" TEXT,
                "siteMapImageURL" TEXT,
                "location" TEXT,
                "contactNumbers" TEXT,
            
                FOREIGN KEY("organizerID") REFERENCES "organizers"("id") ON DELETE CASCADE
            ) STRICT;
            """).execute(db)

            try sql("""
            CREATE TABLE artists(
                "id" TEXT PRIMARY KEY NOT NULL,
                "musicEventID" TEXT,
                "name" TEXT NOT NULL,
                "bio" TEXT,
                "imageURL" TEXT,
                "logoURL" TEXT,
                "kind" TEXT,
                "links" TEXT,
            
                FOREIGN KEY("musicEventID") REFERENCES "musicEvents"("id") ON DELETE CASCADE
            ) STRICT;
            """).execute(db)

            try sql("""
            CREATE TABLE stages(
                "id" TEXT PRIMARY KEY NOT NULL,
                "musicEventID" TEXT,
                "category" TEXT,
                "sortIndex" TEXT NOT NULL,
                "name" TEXT NOT NULL,
                "iconImageURL" TEXT,
                "imageURL" TEXT,
                "posterImageURL" TEXT,
                "color" INTEGER NOT NULL,
                "lineup" TEXT,
            
                FOREIGN KEY("musicEventID") REFERENCES "musicEvents"("id") ON DELETE CASCADE
            ) STRICT;
            """).execute(db)


            try sql("""
            CREATE TABLE schedules(
                "id" TEXT PRIMARY KEY NOT NULL,
                "musicEventID" TEXT,
                "startTime" TEXT,
                "endTime" TEXT,
                "customTitle" TEXT,
            
                FOREIGN KEY("musicEventID") REFERENCES "musicEvents"("id") ON DELETE CASCADE
            ) STRICT;
            """).execute(db)

            try sql("""
            CREATE TABLE performances(
                "id" TEXT PRIMARY KEY NOT NULL,
                "stageID" TEXT NOT NULL,
                "scheduleID" TEXT,
                "title" TEXT NOT NULL,
                "description" TEXT,
                "startTime" TEXT NOT NULL,
                "endTime" TEXT NOT NULL,
                "performanceRecordings" TEXT,

                FOREIGN KEY("stageID") REFERENCES "stages"("id") ON DELETE CASCADE,
                FOREIGN KEY("scheduleID") REFERENCES "schedules"("id") ON DELETE CASCADE
            ) STRICT;
            """).execute(db)

            try sql("""
            CREATE TABLE performanceArtists (
                "performanceID" TEXT NOT NULL,
                "artistID" TEXT,
                "anonymousArtistName" TEXT,

                PRIMARY KEY("performanceID", "artistID"),
                FOREIGN KEY("performanceID") REFERENCES "performances"("id") ON DELETE CASCADE,
                FOREIGN KEY("artistID") REFERENCES "artists"("id") ON DELETE CASCADE
            ) STRICT;
            """).execute(db)

            try sql("""
            CREATE TABLE channels (
                "id" TEXT PRIMARY KEY NOT NULL,
                "musicEventID" TEXT,
                "name" TEXT NOT NULL, 
                "description" TEXT NOT NULL,
                "iconImageURL" TEXT,
                "headerImageURL" TEXT,
                "sortIndex" INTEGER,
                "defaultNotificationState" TEXT NOT NULL,
                "notificationsRequired" INTEGER NOT NULL DEFAULT 0,
                "notificationState" TEXT,
                "firebaseTopicName" TEXT,
            
                

                FOREIGN KEY("musicEventID") REFERENCES "musicEvents"("id") ON DELETE CASCADE
            ) STRICT;
            """).execute(db)

            try sql("""
            CREATE TABLE posts (
                "id" TEXT PRIMARY KEY NOT NULL,
                "stub" TEXT NOT NULL,
                "channelID" TEXT NOT NULL,
                "title" TEXT NOT NULL,
                "contents" TEXT NOT NULL,
                "headerImageURL" TEXT,
                "timestamp" TEXT,
                "isPinned" INTEGER NOT NULL DEFAULT 0,

                FOREIGN KEY("channelID") REFERENCES "channels"("id") ON DELETE CASCADE
            
            ) STRICT;
            """).execute(db)
        }


        migrator.registerMigration("Add posters table") { db in
            try db.execute(sql: """
            CREATE TABLE posters(
                "id" TEXT PRIMARY KEY NOT NULL,
                "musicEventID" TEXT,
                "title" TEXT,
                "imageURL" TEXT NOT NULL,
                
                FOREIGN KEY("musicEventID") REFERENCES "musicEvents"("id") ON DELETE CASCADE
            ) STRICT;
            """)
        }
        try migrator.migrate(db)

        return db
    }

    /// Creates organization folder structure
    func createOrganizationFolder(
        organizerID: Organizer.ID,
        branch: String = "main"
    ) throws -> URL {
        let orgPath = Self.organizationsDirectory
            .appendingPathComponent("\(organizerID)-\(branch)")

        try FileManager.default.createDirectory(
            at: orgPath,
            withIntermediateDirectories: true
        )

        return orgPath
    }

    /// Lists all organization folders
    func listOrganizations() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: Self.organizationsDirectory.path()) else {
            return []
        }

        return try FileManager.default.contentsOfDirectory(
            at: Self.organizationsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        .filter { url in
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path(), isDirectory: &isDirectory)


            return isDirectory.boolValue
        }
    }



    /// Represents an organization available on disk
    struct AvailableOrganization: Identifiable, Equatable {
        let id: Organizer.ID
        let filesPath: URL
        let databasePath: URL

        /// Loads a specific organization's database
        func loadOrganization() throws -> DatabaseQueue {
            @Dependency(\.organizationDatabaseManager) var organizationDatabaseManager

            return try organizationDatabaseManager.openDatabase(at: databasePath)
        }
    }

    /// Lists all available organizations with parsed metadata
    func listAvailableOrganizations() throws -> [AvailableOrganization] {
        let orgFolders = try listOrganizations()

        return orgFolders.compactMap { folderURL in
            // Parse folder name: {organizerID}-{branch}
            let folderName = folderURL.lastPathComponent
            let components = folderName.split(separator: "-", maxSplits: 1)


            let organizerID = Organizer.ID(rawValue: String(components[0]))

            // Verify database exists
            let dbPath = folderURL
                .appendingPathComponent(".ome")
                .appendingPathComponent("org.db")

            

            guard FileManager.default.fileExists(atPath: dbPath.path()) else {
                struct FileDoesNotExist: Error {}
                return nil
            }

            return AvailableOrganization(
                id: organizerID,
                filesPath: folderURL,
                databasePath: dbPath
            )
        }
    }
}


// MARK: - User Preferences Database
import OSLog
extension OrganizationDatabaseManager {

    private static let logger = Logger(
        subsystem: "bundle.ome.OpenMusicEvent",
        category: "Database"
    )
    /// Opens or creates the shared user preferences database
    static func openUserPreferencesDatabase() throws -> any DatabaseWriter {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true


        #if DEBUG
        configuration.prepareDatabase { db in
            db.trace(options: .profile) {
                print("[UserPrefs] \($0.expandedDescription)")
            }
        }
        #endif

        @Dependency(\.context) var context
        let database: any DatabaseWriter

        if context == .preview {
            database = try DatabaseQueue(configuration: configuration)
        } else {
            let dbPath = userPreferencesDatabasePath
            logger.info("Attempting to open user prefs DB at:\(dbPath.path())")

            let parentDir = dbPath.deletingLastPathComponent()
            logger.info("Parent directory: \(parentDir.path())")

            // Check if parent exists
            logger.info("Parent exists: \(FileManager.default.fileExists(atPath: parentDir.path()))")

            try FileManager.default.createDirectory(
                at: parentDir,
                withIntermediateDirectories: true
            )

            logger.info("Parent exists after creation: \(FileManager.default.fileExists(atPath: parentDir.path()))")

            database = try DatabasePool(
                path: dbPath.path(),
                configuration: configuration
            )
        }

        // Run user preferences migrations
        var migrator = DatabaseMigrator()
        migrator.registerUserPreferencesMigrations()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        try migrator.migrate(database)
        

        return database
    }

}

// MARK: - Migrations

extension DatabaseMigrator {

    /// Register migrations for user preferences database
    mutating func registerUserPreferencesMigrations() {
        registerMigration("Create user preferences tables") { db in
            // App state (singleton table for global app state)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS appState (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    selectedOrganizationID TEXT,
                    selectedOrganizationURL TEXT,
                    selectedEventID TEXT
                ) STRICT;
            """)

            // Organization state (per-org session state)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS organizationState (
                    organizerID TEXT PRIMARY KEY,
                    selectedEventID TEXT,
                    selectedStageID TEXT,
                    selectedScheduleID TEXT,
                    lastViewedAt TEXT DEFAULT CURRENT_TIMESTAMP
                ) STRICT;
            """)

            // Artist preferences
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS artistPreferences (
                    organizerID TEXT NOT NULL,
                    artistID TEXT NOT NULL,
                    isFavorite INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (organizerID, artistID)
                ) STRICT;
            """)

            // Performance preferences
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS performancePreferences (
                    organizerID TEXT NOT NULL,
                    performanceID TEXT NOT NULL,
                    isFavorite INTEGER NOT NULL DEFAULT 0,
                    seen INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (organizerID, performanceID)
                ) STRICT;
            """)

            // Channel preferences
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS channelPreferences (
                    organizerID TEXT NOT NULL,
                    channelID TEXT NOT NULL,
                    notificationState TEXT NOT NULL,
                    PRIMARY KEY (organizerID, channelID)
                ) STRICT;
            """)

            // Post preferences
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS postPreferences (
                    organizerID TEXT NOT NULL,
                    postID TEXT NOT NULL,
                    isRead INTEGER NOT NULL DEFAULT 0,
                    isFavorite INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (organizerID, postID)
                ) STRICT;
            """)

            // External asset preferences (videos, recordings, etc.)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS externalAssetPreferences (
                    assetURL TEXT PRIMARY KEY NOT NULL,
                    platform TEXT,
                    cachedTitle TEXT,
                    cachedDescription TEXT,
                    cachedThumbnailURL TEXT,
                    cachedDurationSeconds INTEGER,
                    lastMetadataFetchAttemptAt TEXT,
                    isWatched INTEGER NOT NULL DEFAULT 0,
                    isFavorite INTEGER NOT NULL DEFAULT 0,
                    lastAccessedAt TEXT,
                    playbackPositionSeconds INTEGER
                ) STRICT;
            """)
        }

        registerMigration("Create posterPreferences Table") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS posterPreferences (
                    id TEXT PRIMARY KEY NOT NULL,
                    isRead INTEGER NOT NULL DEFAULT 0,
                    isFavorite INTEGER NOT NULL DEFAULT 0
                ) STRICT;
            """)
        }
    }
}

// MARK: - Dependencies

extension DependencyValues {
    var organizationDatabaseManager: OrganizationDatabaseManager {
        get { self[OrganizationDatabaseManagerKey.self] }
        set { self[OrganizationDatabaseManagerKey.self] = newValue }
    }

    var userPreferencesDatabase: any DatabaseWriter {
        get { self[UserPreferencesDatabaseKey.self] }
        set { self[UserPreferencesDatabaseKey.self] = newValue }
    }
}

private enum OrganizationDatabaseManagerKey: DependencyKey {
    static let liveValue = OrganizationDatabaseManager()
}

private enum UserPreferencesDatabaseKey: TestDependencyKey {
    static let testValue: any DatabaseWriter = DependencyValues.DefaultDatabaseKey.testValue
}

