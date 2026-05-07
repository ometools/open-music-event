import Foundation
import OpenMusicEventLexicon
import SQLiteData

public typealias OMERecord = OpenMusicEventLexicon.OpenMusicEvent

extension ExternalPlatform: SQLiteType {}



extension DependencyValues {
    mutating func bootstrapDatabase() throws {
        @Dependency(\.context) var context

        var configuration = Configuration()
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

        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        migrator.registerMigration("Create v1 schema") { db in
            try #sql("""
                CREATE TABLE "organizers" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "events" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "name" TEXT NOT NULL,
                  "description" TEXT,
                  "startDate" TEXT,
                  "endDate" TEXT,
                  "status" TEXT NOT NULL,
                  "mode" TEXT NOT NULL,
                  "locations" TEXT,
                  "uris" TEXT,
                  "timeZone" TEXT NOT NULL,
                  "imageURL" TEXT,
                  "iconImageURL" TEXT,
                  "siteMapImageURL" TEXT,
                  "contactNumbers" TEXT,
                  "categoryConfigs" TEXT
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "eventOrganizers" (
                  "eventID" TEXT NOT NULL REFERENCES "events"("id") ON DELETE CASCADE,
                  "organizerID" TEXT NOT NULL REFERENCES "organizers"("id") ON DELETE CASCADE,
                  PRIMARY KEY ("eventID", "organizerID")
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "stages" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "name" TEXT NOT NULL,
                  "color" INTEGER NOT NULL,
                  "category" TEXT,
                  "sortIndex" INTEGER,
                  "iconImageURL" TEXT,
                  "systemIconName" TEXT,
                  "iconShortCode" TEXT,
                  "imageURL" TEXT,
                  "posterImageURL" TEXT,
                  "lineup" TEXT
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "schedules" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "eventID" TEXT NOT NULL REFERENCES "events"("id") ON DELETE CASCADE,
                  "date" TEXT NOT NULL,
                  "startsAt" TEXT,
                  "endsAt" TEXT,
                  "customTitle" TEXT
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "participants" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "name" TEXT NOT NULL,
                  "bio" TEXT,
                  "imageURL" TEXT,
                  "logoURL" TEXT,
                  "kind" TEXT,
                  "links" TEXT
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "participantClaims" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "participantID" TEXT NOT NULL REFERENCES "participants"("id") ON DELETE CASCADE
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "channels" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "eventID" TEXT NOT NULL REFERENCES "events"("id") ON DELETE CASCADE,
                  "name" TEXT NOT NULL,
                  "description" TEXT NOT NULL,
                  "iconImageURL" TEXT,
                  "headerImageURL" TEXT,
                  "sortIndex" INTEGER,
                  "defaultNotificationState" TEXT NOT NULL,
                  "notificationsRequired" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "posters" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "eventID" TEXT NOT NULL REFERENCES "events"("id") ON DELETE CASCADE,
                  "title" TEXT,
                  "imageURL" TEXT NOT NULL
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "performances" (
                  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "eventID" TEXT NOT NULL REFERENCES "events"("id") ON DELETE CASCADE,
                  "stageID" TEXT NOT NULL REFERENCES "stages"("id") ON DELETE CASCADE,
                  "scheduleID" TEXT REFERENCES "schedules"("id") ON DELETE CASCADE,
                  "startTime" TEXT NOT NULL,
                  "endTime" TEXT NOT NULL,
                  "title" TEXT NOT NULL,
                  "description" TEXT,
                  "recordings" TEXT NOT NULL
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "performanceParticipants" (
                  "performanceID" TEXT NOT NULL REFERENCES "performances"("id") ON DELETE CASCADE,
                  "participantID" TEXT REFERENCES "participants"("id") ON DELETE CASCADE,
                  "anonymousName" TEXT
                ) STRICT
                """)
                .execute(db)




            // MARK: OMERecord+OrganizerPreferencces
            try #sql("""
                CREATE TABLE "organizerPreferences" (
                  "organizerID" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "isFollowing" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "participantPreferences" (
                  "participantID" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "isFavorite" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "performancePreferences" (
                  "performanceID" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "interested" INTEGER NOT NULL DEFAULT 0,
                  "seen" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "channelPreferences" (
                  "channelID" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "notificationState" TEXT NOT NULL
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "posterPreferences" (
                  "posterID" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "isRead" INTEGER NOT NULL DEFAULT 0,
                  "isFavorite" INTEGER NOT NULL DEFAULT 0
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "externalAssetPreferences" (
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


            // MARK: OME App State
            try #sql("""
                CREATE TABLE "appState" (
                  "id" INTEGER PRIMARY KEY CHECK ("id" = 1),
                  "selectedEventID" TEXT
                ) STRICT
                """)
                .execute(db)

            try AppState.insert()
                .execute(db)

            try #sql("""
                CREATE TABLE "eventViewerState" (
                  "musicEventID" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "selectedScheduleID" TEXT
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE "scheduleViewerState" (
                  "musicEventID" TEXT NOT NULL,
                  "category" TEXT,
                  "selectedStageID" TEXT,
                  "showStageNameLabels" INTEGER NOT NULL DEFAULT 0,
                  "filteringFavorites" INTEGER NOT NULL DEFAULT 0,
                  "filteringInterested" INTEGER NOT NULL DEFAULT 0,
                  "scheduleKind" TEXT NOT NULL DEFAULT 'singleStageAtOnce',
                  PRIMARY KEY ("musicEventID", "category")
                ) STRICT
                """)
                .execute(db)


        }



        try migrator.migrate(database)
        defaultDatabase = database
    }
}

@Table("appState")
struct AppState: Equatable, Sendable, Identifiable {
    let id: Int
    var selectedEventID: OMERecord.Event.ID?

    init(id: Int = 1, selectedEventID: OMERecord.Event.ID? = nil) {
        self.id = id
        self.selectedEventID = selectedEventID
    }

}

@Table("organizerPreferences")
public struct OrganizerPreferences: Equatable, Sendable, Identifiable {
    @Column(primaryKey: true) public var organizerID: OMERecord.Organizer.ID
    public var isFollowing = false

    public var id: OMERecord.Organizer.ID { organizerID }
}

@Table("participantPreferences")
struct ParticipantPreferences: Equatable, Sendable, Identifiable {
    @Column(primaryKey: true) var participantID: OMERecord.Participant.ID
    var isFavorite = false

    var id: OMERecord.Participant.ID { participantID }
}

@Table("performancePreferences")
struct PerformancePreferences: Equatable, Sendable, Identifiable {
    @Column(primaryKey: true) var performanceID: OMERecord.Performance.ID
    var interested = false
    var seen = false

    var id: OMERecord.Performance.ID { performanceID }
}

@Table("channelPreferences")
struct ChannelPreferences: Equatable, Sendable, Identifiable {
    @Column(primaryKey: true) var channelID: OMERecord.Channel.ID
    var notificationState: OMERecord.Channel.NotificationState

    var id: OMERecord.Channel.ID { channelID }
}

@Table("posterPreferences")
struct PosterPreferences: Equatable, Sendable, Identifiable {
    @Column(primaryKey: true) var posterID: OMERecord.Poster.ID
    var isRead = false
    var isFavorite = false

    var id: OMERecord.Poster.ID { posterID }
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

@Table("eventViewerState")
struct EventViewerState: Equatable, Sendable, Identifiable {
    @Column(primaryKey: true) var musicEventID: OMERecord.Event.ID
    var selectedScheduleID: OMERecord.Schedule.ID?

    var id: OMERecord.Event.ID { musicEventID }
}

enum ScheduleKind: String, Codable, Sendable, CaseIterable, SQLiteType {
    case singleStageAtOnce
    case allStagesAtOnce
}

@Table("scheduleViewerState")
struct ScheduleViewerState: Equatable, Sendable, Identifiable {
    @Selection struct ID: Hashable, Sendable {
        var musicEventID: OMERecord.Event.ID
        var category: OMERecord.Stage.Category?
    }

    let id: ID
    var selectedStageID: OMERecord.Stage.ID?
    var showStageNameLabels = false
    var filteringFavorites = false
    var filteringInterested = false
    var scheduleKind: ScheduleKind = .singleStageAtOnce
}
