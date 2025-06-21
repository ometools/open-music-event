//
//  DownloadAndStoreOrganizationTests.swift
//  open-music-event
//
//  Created by Woodrow Melling on 6/19/25.
//

import Testing
import InlineSnapshotTesting
@testable import OpenMusicEvent
import OpenMusicEventParser
import DependenciesTestSupport
import Foundation
import SharingGRDB
import GRDBSnapshotTesting
import InlineSnapshotTesting



extension Tag {
    @Tag static var liveNetworkTests: Self
}


extension OpenMusicEventBaseTestSuite {
    @Suite(.snapshots(record: .failed))
    struct OrganizationStoringTests {
        @Test
        func storeSimpleOrganization() async throws {
            let database = try appDatabase()
            let organization = OrganizerConfiguration(
                info: .init(
                    url: URL(string: "https://github.com/woodymelling/testival"),
                    name: "Testival",
                    imageURL: URL(string: "https://github.com/woodymelling/testival/raw/main/images/testival-logo.png"),
                    iconImageURL: URL(string: "https://github.com/woodymelling/testival/raw/main/images/testival-icon-imageURL.png")
                ),
                events: []
            )

            try await organization.insert(
                url: organization.info.url!,
                into: database
            )

            assertInlineSnapshot(of: AnyDatabaseReader(database), as: .dumpContent()) {
                """
                sqlite_master
                CREATE TABLE artists(
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "musicEventID" INTEGER,
                    "name" TEXT NOT NULL,
                    "bio" TEXT,
                    "imageURL" TEXT,
                    "links" TEXT,
                
                    FOREIGN KEY("musicEventID") REFERENCES "musicEvents"("id") ON DELETE CASCADE
                ) STRICT;
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
                CREATE TABLE organizers (
                    "url" TEXT PRIMARY KEY NOT NULL,
                    "name" TEXT NOT NULL,
                    "imageURL" TEXT,
                    "iconImageURL" TEXT
                ) STRICT;
                CREATE TABLE performanceArtists (
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "performanceID" INTEGER NOT NULL,
                    "artistID" INTEGER REFERENCES artists(id) ON DELETE CASCADE,
                    "anonymousArtistName" TEXT,
                
                    FOREIGN KEY("performanceID") REFERENCES "performances"("id") ON DELETE CASCADE
                    FOREIGN KEY("artistID") REFERENCES "artists"("id") ON DELETE CASCADE
                ) STRICT;
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
                CREATE TABLE schedules(
                    "id" INTEGER PRIMARY KEY AUTOINCREMENT,
                    "musicEventID" INTEGER,
                    "startTime" TEXT,
                    "endTime" TEXT,
                    "customTitle" TEXT,
                
                    FOREIGN KEY("musicEventID") REFERENCES "musicEvents"("id") ON DELETE CASCADE
                ) STRICT;
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
                
                artists
                
                musicEvents
                
                organizers
                - url: 'https://github.com/woodymelling/testival'
                  name: 'Testival'
                  imageURL: 'https://github.com/woodymelling/testival/raw/main/images/testival-logo.png'
                  iconImageURL: 'https://github.com/woodymelling/testival/raw/main/images/testival-icon-imageURL.png'
                
                performanceArtists
                
                performances
                
                schedules
                
                stages
                
                """
            }
        }
    }

    // MARK: Live Download Tests
    @MainActor
    @Suite(
        .dependency(\.organizationFetchingClient, .liveValue),
        .dependency(\.zipClient, .liveValue),
        .tags(.liveNetworkTests)
    )
    struct LiveDownloadTests {
        @Dependency(\.defaultDatabase) var database

        @Test
        func shambhala420() async throws {

            try await downloadAndStoreOrganizer(from: .url(URL(string: "https://github.com/woodymelling/shambhala-ome/archive/966ff5b45aadfdcdb325a6f85c5f744c1e792e68.zip")!))

            assertInlineSnapshot(of: AnyDatabaseReader(database), as: .dumpStatistics()) {
                """
                artists: 548 rows
                grdb_migrations: 1 rows
                musicEvents: 5 rows
                organizers: 4 rows
                performanceArtists: 565 rows
                performances: 542 rows
                schedules: 9 rows
                stages: 22 rows

                """
            }
        }

        @Test
        func wickedwoods420() async throws {
            try await downloadAndStoreOrganizer(from: .url(URL(string: "https://github.com/wicked-woods/wicked-woods-ome/archive/be070e28249b150522f548d1b965f0fed74b7248.zip")!))

            assertInlineSnapshot(of: AnyDatabaseReader(database), as: .dumpStatistics()) {
                """
                artists: 607 rows
                grdb_migrations: 1 rows
                musicEvents: 7 rows
                organizers: 4 rows
                performanceArtists: 593 rows
                performances: 522 rows
                schedules: 13 rows
                stages: 23 rows

                """
            }
        }
    }
}

extension Snapshotting {
    public static func dumpStatistics() -> Snapshotting
    where Value: DatabaseReader, Format == String
    {
        SimplySnapshotting.lines.pullback { (reader: Value) in
            let stream = SnapshotStream()
            try! reader.dumpStatistics(to: stream)
            return stream.output
        }
    }
}

import GRDBSnapshotTesting
extension DatabaseReader {
    func dumpStatistics(to stream: SnapshotStream) throws {
        try read { db in
            let tables = try db.allTables()
            for table in tables {
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"\(table)\"") ?? 0
                stream.write("\(table): \(count) rows\n")
            }
        }
    }
}
//
private extension Database {
    func allTables() throws -> [String] {
        try String.fetchAll(self, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
                ORDER BY name
            """)
    }
}

final class SnapshotStream: TextOutputStream {
    var output: String

    init() {
        output = ""
    }

    func write(_ string: String) {
        output.append(string)
    }
}




