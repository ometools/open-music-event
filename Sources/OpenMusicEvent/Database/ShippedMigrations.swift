//
//  ShippedMigrations.swift
//  open-music-event
//
//  Created by Woodrow Melling on 9/17/25.
//

import GRDB

extension DatabaseMigrator {
    mutating func registerShippedMigrations() {
        self.registerMigration("Create tables") { db in
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

        
    }
}
