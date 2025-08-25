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
import CoreModels

private let logger = Logger(
    subsystem: "bundle.ome.OpenMusicEvent",
    category: "Database"
)

extension Tagged {

}

func appDatabase(whiteLabeledOrganizationID: Organizer.ID? = nil) throws -> any DatabaseWriter {
    print("Preparing Database")
    let database: any DatabaseWriter
    var configuration = Configuration()

    configuration.foreignKeysEnabled = true

    configuration.prepareDatabase { db in
        #if DEBUG
        db.trace(options: .profile) {
            print("\($0.expandedDescription)")
            logger.debug("\($0.expandedDescription)")
        }
        #endif

        db.add(
          function: DatabaseFunction(
            "handleChannelSubscriptionChanged",
            argumentCount: 3
          ) { dbValues in
            // Arguments: channelID, firebaseTopicName, oldState, newState, isRequired
              guard let channelID = CommunicationChannel.ID.fromDatabaseValue(dbValues[0]),
                    let newValue = CommunicationChannel.UserNotificationState.fromDatabaseValue(dbValues[1])
              else {
                  reportIssue("Failed to parse Database Values")
                  return nil
              }

              if let topic = CommunicationChannel.FirebaseTopicName.fromDatabaseValue(dbValues[2]) {
                  logger.log("""
                  channelID: \(channelID),
                  newValue: \(newValue.rawValue),
                  topic: \(topic.rawValue)
                  """)

                  Task {
                      @Dependency(\.notificationManager) var notificationManager
                      await withErrorReporting {
                          try await notificationManager.updateTopicSubscription(topic, to: newValue)
                      }
                  }
              }



            return nil
          }
        )
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
            "userNotificationState" TEXT,
            "notificationsRequired" INTEGER NOT NULL DEFAULT 0,
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

    migrator.registerMigration("Create preferences tables") { db in
        try sql("""
        CREATE TABLE artistPreferences(
            "artistID" TEXT PRIMARY KEY NOT NULL,
            "isFavorite" INTEGER NOT NULL DEFAULT 0,
        
            FOREIGN KEY("artistID") REFERENCES "artists" ON DELETE CASCADE
        ) STRICT;
        """)
        .execute(db)

        try sql("""
        CREATE TABLE performancePreferences(
            "performanceID" TEXT PRIMARY KEY NOT NULL,
            "seen" INTEGER NOT NULL DEFAULT 0,
        
            FOREIGN KEY("performanceID") REFERENCES "performances" ON DELETE CASCADE
        ) STRICT;
        """)
        .execute(db)
    }



    #if DEBUG
//    if context == .preview {
        migrator.registerMigration("Seed sample data") { db in
            try db.seedSampleData()
        }
//    }
    #endif

    try migrator.migrate(database)

    // MARK: Triggers
    try database.write { db in
        try sql("""
        CREATE TEMPORARY TRIGGER on_channel_subscription_changed
        AFTER UPDATE OF userNotificationState ON channels
        FOR EACH ROW
        WHEN OLD.userNotificationState IS DISTINCT FROM NEW.userNotificationState
        BEGIN
            SELECT handleChannelSubscriptionChanged(NEW.id, NEW.userNotificationState, NEW.firebaseTopicName);
        END;
        """).execute(db)
    }

    return database
}


#if DEBUG
extension Database {
    func seedSampleData() throws {
        // Insert organizers
        try Organizer.Draft(Organizer.omeTools).upsert(self)
        try Organizer.Draft(Organizer.wickedWoods).upsert(self)
        try Organizer.Draft(Organizer.shambhala).upsert(self)

        // Insert music event
        try MusicEvent.Draft(MusicEvent.testival).upsert(self)

        // Insert artists
        for artist in Artist.previewValues {
            try Artist.Draft(artist).upsert(self)
        }
        
        // Insert stages
        for stage in Stage.previewValues {
            try Stage.Draft(stage).upsert(self)
        }
        
        // Insert channels
        for channel in CommunicationChannel.previewData {
            try channel.upsert(self)
        }
        
//        // Insert posts
//        for post in CommunicationChannel.Post.previewData {
//            try post.upsert(self)
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


