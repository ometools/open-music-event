//
//  Database.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/4/25.
//

import GRDB
// import SharingGRDB
import SwiftUI
import Dependencies
import SkipFuse

private let logger = Logger(
    subsystem: "bundle.ome.OpenMusicEvent",
    category: "Database"
)

func appDatabase() throws -> any DatabaseWriter {
    print("Preparing Database")
    let database: any DatabaseWriter
    var configuration = Configuration()

    configuration.foreignKeysEnabled = true

    configuration .prepareDatabase { db in
        #if DEBUG
        db.trace(options: .profile) {
            print("\($0.expandedDescription)")
            logger.debug("\($0.expandedDescription)")
        }
        #endif
    }

    @Dependency(\.context) var context
    if context == .preview {
        database = try DatabaseQueue(configuration: configuration)
    } else {
        #if os(iOS)
        let rootDirectory = URL.documentsDirectory
        #else
        let rootDirectory = URL.applicationSupportDirectory
        #endif



        let path =
        context == .live
        ? rootDirectory.appending(component: "db.sqlite").path()
        : URL.temporaryDirectory.appending(component: "\(UUID().uuidString)-db.sqlite").path()
        logger.info("open \(path)")
        database = try DatabasePool(path: path, configuration: configuration)
    }

    var migrator = DatabaseMigrator()
    #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
    #endif
    migrator.registerMigration("Create tables") { db in
        try sql("""
        CREATE TABLE organizers (
            "url" TEXT PRIMARY KEY NOT NULL,
            "name" TEXT NOT NULL,
            "imageURL" TEXT,
            "iconImageURL" TEXT
        ) STRICT;
        """).execute(db)

        try sql("""
        CREATE TABLE musicEvents(
            "id" INTEGER PRIMARY KEY AUTOINCREMENT,
            "organizerURL" TEXT,
            "name" TEXT NOT NULL,
            "startTime" TEXT,
            "endTime" TEXT,
            "timeZone" TEXT,
            "imageURL" TEXT,
            "iconImageURL" TEXT,
            "siteMapImageURL" TEXT,
            "location" TEXT,
            "contactNumbers" TEXT,
        
            FOREIGN KEY("organizerURL") REFERENCES "organizers"("url") ON DELETE CASCADE
        ) STRICT;
        """).execute(db)

        try sql("""
        CREATE TABLE artists(
            "id" INTEGER PRIMARY KEY AUTOINCREMENT,
            "musicEventID" INTEGER,
            "name" TEXT NOT NULL,
            "bio" TEXT,
            "imageURL" TEXT,
            "links" TEXT,
        
            FOREIGN KEY("musicEventID") REFERENCES "musicEvents"("id") ON DELETE CASCADE
        ) STRICT;
        """).execute(db)

        try sql("""
        CREATE TABLE stages(
            "id" INTEGER PRIMARY KEY AUTOINCREMENT,
            "musicEventID" INTEGER,
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
            "id" INTEGER PRIMARY KEY AUTOINCREMENT,
            "musicEventID" INTEGER,
            "startTime" TEXT,
            "endTime" TEXT,
            "customTitle" TEXT,
        
            FOREIGN KEY("musicEventID") REFERENCES "musicEvents"("id") ON DELETE CASCADE
        ) STRICT;
        """).execute(db)

        try sql("""
        CREATE TABLE performances(
            "id" INTEGER PRIMARY KEY AUTOINCREMENT,
            "stageID" INTEGER NOT NULL,
            "scheduleID" INTEGER,
            "title" TEXT NOT NULL,
            "description" TEXT,
            "startTime" TEXT NOT NULL,
            "endTime" TEXT NOT NULL,
        
            FOREIGN KEY("stageID") REFERENCES "stages"("id") ON DELETE CASCADE,
            FOREIGN KEY("scheduleID") REFERENCES "schedules"("id") ON DELETE CASCADE
        ) STRICT;
        """).execute(db)

        try sql("""
        CREATE TABLE performanceArtists (
            "id" INTEGER PRIMARY KEY AUTOINCREMENT,
            "performanceID" INTEGER NOT NULL,
            "artistID" INTEGER REFERENCES artists(id) ON DELETE CASCADE,
            "anonymousArtistName" TEXT,

            FOREIGN KEY("performanceID") REFERENCES "performances"("id") ON DELETE CASCADE
            FOREIGN KEY("artistID") REFERENCES "artists"("id") ON DELETE CASCADE
        ) STRICT;
        """).execute(db)
    }

    #if DEBUG
    if context == .preview {
        migrator.registerMigration("Seed sample data") { db in
            try db.seedSampleData()
        }
    }
    #endif

    try migrator.migrate(database)

    return database
}


#if DEBUG
extension Database {
    func seedSampleData() throws {
//        try seed {
//            Organizer.wickedWoods
//            Organizer.shambhala
//
////            for artist in Artist.previewValues {
////                artist
////            }
////
////            for stage in Stage.previewValues {
////                stage
////            }
//        }
    }
}
#endif

// MARK: - Default Database Dependency
// Copied from SharingGRDB to avoid Swift/Android compatibility issues

extension DependencyValues {
  /// The default database used by `fetchAll`, `fetchOne`, and `fetch`.
  ///
  /// Configure this as early as possible in your app's lifetime, like the app entry point in
  /// SwiftUI, using `prepareDependencies`:
  ///
  /// ```swift
  /// import  SwiftUI; import SkipFuse
  ///
  /// @main
  /// struct MyApp: App {
  ///   init() {
  ///     prepareDependencies {
  ///       // Create database connection and run migrations...
  ///       $0.defaultDatabase = try! DatabaseQueue(/* ... */)
  ///     }
  ///   }
  ///   // ...
  /// }
  /// ```
  ///
  /// > Note: You can only prepare the database a single time in the lifetime of your app.
  /// > Attempting to do so more than once will produce a runtime warning.
  ///
  /// Once configured, access the database anywhere using `@Dependency`:
  ///
  /// ```swift
  /// @Dependency(\.defaultDatabase) var database
  ///
  /// var newItem = Item(/* ... */)
  /// try database.write { db in
  ///   try newItem.insert(db)
  /// }
  /// ```
  public var defaultDatabase: any DatabaseWriter {
    get { self[DefaultDatabaseKey.self] }
    set { self[DefaultDatabaseKey.self] = newValue }
  }

  private enum DefaultDatabaseKey: DependencyKey {
    static var liveValue: any DatabaseWriter { testValue }
    static var testValue: any DatabaseWriter {
      var message: String {
        @Dependency(\.context) var context
        switch context {
        case .live:
          return """
            A blank, in-memory database is being used. To set the database that is used by \
            the app, use the 'prepareDependencies' tool as early as possible in the lifetime \
            of your app, such as in your app or scene delegate in UIKit, or the app entry point in \
            SwiftUI:

                @main
                struct MyApp: App {
                  init() {
                    prepareDependencies {
                      $0.defaultDatabase = try! DatabaseQueue(/* ... */)
                    }
                  }
                  // ...
                }
            """

        case .preview:
          return """
            A blank, in-memory database is being used. To set the database that is used by \
            the app in a preview, use a tool like 'prepareDependencies':

                #Preview {
                  let _ = prepareDependencies {
                    $0.defaultDatabase = try! DatabaseQueue(/* ... */)
                  }
                  // ...
                }
            """

        case .test:
          return """
            A blank, in-memory database is being used. To set the database that is used by \
            the app in a test, use a tool like the 'dependency' trait from \
            'DependenciesTestSupport':

                import DependenciesTestSupport

                @Suite(.dependency(\\.defaultDatabase, try DatabaseQueue(/* ... */)))
                struct MyTests {
                  // ...
                }
            """
        }
      }
      if shouldReportUnimplemented {
        reportIssue(message)
      }
      var configuration = Configuration()
      #if DEBUG
        configuration.label = .defaultDatabaseLabel
      #endif
      return try! DatabaseQueue(configuration: configuration)
    }
  }
}

#if DEBUG
  extension String {
    static let defaultDatabaseLabel = "co.pointfree.OpenMusicEvent.testValue"
  }
#endif

// MARK: - SQL Macro Replacement
// Replace #sql macro with function for Android compatibility

struct SQLStatement: Sendable {
    var rawValue: String

    func execute(_ db: Database) throws {
        try db.execute(sql: rawValue)
    }
}

@Sendable func sql(_ sql: String) -> SQLStatement {
    return .init(rawValue: sql)
}


