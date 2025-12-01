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
        #if os(iOS)
        let root = URL.documentsDirectory
        #else
        let root = URL.documentsDirectory
        #endif
        return root.appendingPathComponent("open-music-event")
    }


    /// Path to user preferences database (app-private)
    static var userPreferencesDatabasePath: URL {
        #if os(iOS)
        let root = URL.documentsDirectory
        #else
        let root = URL.applicationSupportDirectory
        #endif
        return root.appendingPathComponent("user-preferences.db")
    }

    // MARK: - Organization Database

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

        #if DEBUG
        configuration.prepareDatabase { db in
            db.trace(options: .profile) {
                print("\($0.expandedDescription)")
            }
        }
        #endif

        let db = try DatabaseQueue(path: dbPath.path(), configuration: configuration)

        // Run migrations
        var migrator = DatabaseMigrator()
        migrator.registerShippedMigrations()
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

extension OrganizationDatabaseManager {

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
            print("🔍 Attempting to open user prefs DB at:\(dbPath.path())")

            let parentDir = dbPath.deletingLastPathComponent()
            print("🔍 Parent directory: \(parentDir.path())")

            // Check if parent exists
            print("🔍 Parent exists: \(FileManager.default.fileExists(atPath: parentDir.path()))")

            try FileManager.default.createDirectory(
                at: parentDir,
                withIntermediateDirectories: true
            )

            print("🔍 Parent exists after creation: \(FileManager.default.fileExists(atPath: parentDir.path()))")

            database = try DatabasePool(
                path: dbPath.path(),
                configuration: configuration
            )
        }


        // Run user preferences migrations
        var migrator = DatabaseMigrator()
        migrator.registerUserPreferencesMigrations()
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
                    notes TEXT,
                    PRIMARY KEY (organizerID, artistID)
                ) STRICT;
            """)

            // Performance preferences
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS performancePreferences (
                    organizerID TEXT NOT NULL,
                    performanceID TEXT NOT NULL,
                    isFavorite INTEGER NOT NULL DEFAULT 0,
                    reminder TEXT,
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
