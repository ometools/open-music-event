import Foundation
import GRDB
import SQLiteData

@Table("calendarMapEvents")
struct CalendarMapEvent: Codable, Equatable, Sendable {
    @Column(primaryKey: true) var id: String
    var generation: Int
    var uri: String
    var catalog: String
    var cell: String
    var x: Double
    var y: Double
    var effectiveEnd: Date?
    var active: Bool

    static func project(_ row: CalendarEventBrowseProjection, generation: Int, now: Date) -> Self? {
        guard let latitude = row.latitude, let longitude = row.longitude,
              latitude.isFinite, longitude.isFinite,
              Swift.abs(latitude) <= CalendarMapCell.maximumLatitude, Swift.abs(longitude) <= 180
        else { return nil }
        let x = ((longitude + 180) / 360).truncatingRemainder(dividingBy: 1)
        let radians = latitude * .pi / 180
        let mercatorY = (1 - Foundation.log(Foundation.tan(radians) + 1 / Foundation.cos(radians)) / Double.pi) / 2
        let y = Swift.min(Double(1).nextDown, Swift.max(0, mercatorY))
        let end = row.endsAt ?? row.startsAt
        return Self(id: "\(generation)|\(row.uri)", generation: generation, uri: row.uri,
                    catalog: row.catalog, cell: CalendarMapCell.key(x: x, y: y, depth: 21),
                    x: x, y: y, effectiveEnd: end,
                    active: row.startsAt != nil && end.map { $0 >= now } == true)
    }

    static func synchronize(_ row: CalendarEventBrowseProjection, now: Date, in db: Database) throws {
        guard let build = try CalendarMapBuild.find(0).fetchOne(db) else { return }
        let generations = Set([build.active, build.building].compactMap { $0 }.filter { $0 > 0 })
        for generation in generations {
            let id = "\(generation)|\(row.uri)"
            if let projected = project(row, generation: generation, now: now) {
                try upsert { projected }.execute(db)
            } else {
                try find(id).delete().execute(db)
            }
        }
    }
}

@Table("calendarMapCells")
struct CalendarMapCell: Codable, Equatable, Sendable {
    @Column(primaryKey: true) var id: String
    var generation: Int
    var depth: Int
    var cell: String
    var catalog: String
    var count: Int
    var activeCount: Int
    var x: Double
    var y: Double
    var activeX: Double
    var activeY: Double

    static let maximumLatitude = 85.0511287798066

    static func key(x: Double, y: Double, depth: Int) -> String {
        let scale = 1 << depth
        let column = Swift.min(scale - 1, Swift.max(0, Int(x * Double(scale))))
        let row = Swift.min(scale - 1, Swift.max(0, Int(y * Double(scale))))
        var result = ""
        for bit in (0..<depth).reversed() {
            let horizontal = (column >> bit) & 1
            let vertical = (row >> bit) & 1
            result.append(String(horizontal + 2 * vertical))
        }
        return result
    }

    static func origin(_ cell: String) -> (x: Int, y: Int) {
        cell.reduce((0, 0)) { result, digit in
            let value = digit.wholeNumberValue!
            return (result.0 * 2 + value % 2, result.1 * 2 + value / 2)
        }
    }

    static func latitude(y: Double) -> Double {
        Foundation.atan(Foundation.sinh(.pi * (1 - 2 * y))) * 180 / .pi
    }
}

@Table("calendarMapBuilds")
struct CalendarMapBuild: Codable, Equatable, Sendable {
    @Column(primaryKey: true) var id: Int
    var active: Int
    var building: Int?
    var afterURI: String?
    var retiring: Int = 1

    static func registerMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Add incremental calendar map cells") { db in
            try db.execute(sql: """
                CREATE TABLE "\(tableName)" (id INTEGER PRIMARY KEY, active INTEGER NOT NULL,
                  building INTEGER, afterURI TEXT) STRICT;
                INSERT INTO "\(tableName)" VALUES (0, 0, 1, NULL);
                CREATE TABLE "calendarMapLevels" (depth INTEGER PRIMARY KEY) STRICT;
                WITH RECURSIVE levels(depth) AS (VALUES(3) UNION ALL SELECT depth+1 FROM levels WHERE depth<21)
                INSERT INTO "calendarMapLevels" SELECT depth FROM levels;
                CREATE TABLE "\(CalendarMapEvent.tableName)" (
                  id TEXT PRIMARY KEY NOT NULL, generation INTEGER NOT NULL, uri TEXT NOT NULL,
                  catalog TEXT NOT NULL, cell TEXT NOT NULL, x REAL NOT NULL, y REAL NOT NULL,
                  effectiveEnd TEXT, active INTEGER NOT NULL,
                  FOREIGN KEY (uri) REFERENCES "\(CalendarEventBrowseProjection.tableName)"(uri) ON DELETE CASCADE
                ) STRICT;
                CREATE INDEX calendar_map_members ON "\(CalendarMapEvent.tableName)" (generation, catalog, cell, active, uri);
                CREATE INDEX calendar_map_expiration ON "\(CalendarMapEvent.tableName)" (effectiveEnd) WHERE active=1;
                CREATE INDEX calendar_map_uri ON "\(CalendarMapEvent.tableName)" (uri);
                CREATE TABLE "\(CalendarMapCell.tableName)" (
                  id TEXT PRIMARY KEY NOT NULL, generation INTEGER NOT NULL, depth INTEGER NOT NULL,
                  cell TEXT NOT NULL, catalog TEXT NOT NULL, count INTEGER NOT NULL,
                  activeCount INTEGER NOT NULL, x REAL NOT NULL, y REAL NOT NULL,
                  activeX REAL NOT NULL, activeY REAL NOT NULL
                ) STRICT;
                CREATE INDEX calendar_map_tiles ON "\(CalendarMapCell.tableName)" (generation, depth, catalog, cell);
                CREATE TABLE "\(CalendarMapRevision.tableName)" (id TEXT PRIMARY KEY NOT NULL, revision INTEGER NOT NULL) STRICT;
                CREATE INDEX calendar_browse_end ON "\(CalendarEventBrowseProjection.tableName)"
                  (catalog, COALESCE(endsAt, startsAt) DESC, uri);
                CREATE INDEX calendar_browse_viewer ON "\(CalendarEventBrowseProjection.tableName)"
                  (catalog, hasEventViewer, startsAt, uri);
                """)
            let add = """
                INSERT INTO "\(CalendarMapCell.tableName)"
                  (id,generation,depth,cell,catalog,count,activeCount,x,y,activeX,activeY)
                SELECT NEW.generation || '|' || substr(NEW.cell,1,depth) || '|' || NEW.catalog,
                  NEW.generation,depth,substr(NEW.cell,1,depth),NEW.catalog,1,NEW.active,
                  NEW.x,NEW.y,NEW.x*NEW.active,NEW.y*NEW.active
                FROM calendarMapLevels WHERE 1
                ON CONFLICT(id) DO UPDATE SET count=count+1,activeCount=activeCount+NEW.active,
                  x=x+NEW.x,y=y+NEW.y,activeX=activeX+NEW.x*NEW.active,activeY=activeY+NEW.y*NEW.active;
                """
            let remove = """
                UPDATE "\(CalendarMapCell.tableName)" SET count=count-1,activeCount=activeCount-OLD.active,
                  x=x-OLD.x,y=y-OLD.y,activeX=activeX-OLD.x*OLD.active,activeY=activeY-OLD.y*OLD.active
                WHERE id IN (SELECT OLD.generation || '|' || substr(OLD.cell,1,depth) || '|' || OLD.catalog
                  FROM calendarMapLevels);
                DELETE FROM "\(CalendarMapCell.tableName)" WHERE count=0 AND generation=OLD.generation
                  AND catalog=OLD.catalog AND cell IN (SELECT substr(OLD.cell,1,depth) FROM calendarMapLevels);
                """
            func revision(_ record: String) -> String {
                """
                INSERT INTO "\(CalendarMapRevision.tableName)" (id,revision)
                SELECT \(record).generation || '|' || substr(\(record).cell,1,depth-3) || '|' || \(record).catalog,1
                FROM calendarMapLevels WHERE 1 ON CONFLICT(id) DO UPDATE SET revision=revision+1;
                """
            }
            try db.execute(sql: """
                CREATE TRIGGER calendar_map_insert AFTER INSERT ON "\(CalendarMapEvent.tableName)" BEGIN \(add) \(revision("NEW")) END;
                CREATE TRIGGER calendar_map_delete AFTER DELETE ON "\(CalendarMapEvent.tableName)" BEGIN \(remove) \(revision("OLD")) END;
                CREATE TRIGGER calendar_map_update AFTER UPDATE ON "\(CalendarMapEvent.tableName)" BEGIN \(remove) \(add) \(revision("OLD")) \(revision("NEW")) END;
                """)
        }
        migrator.registerMigration("Cover active calendar browse ordering") { db in
            try db.execute(sql: """
                CREATE INDEX calendar_browse_current ON "\(CalendarEventBrowseProjection.tableName)"
                  (catalog, hasEventViewer, COALESCE(endsAt, startsAt), startsAt, uri)
                """)
        }
        migrator.registerMigration("Track retired calendar map generations") { db in
            try db.execute(sql: "ALTER TABLE \"\(tableName)\" ADD COLUMN retiring INTEGER NOT NULL DEFAULT 1")
        }
    }
}

@Table("calendarMapRevisions")
struct CalendarMapRevision: Codable, Sendable {
    @Column(primaryKey: true) var id: String
    var revision: Int
}

extension OpenMusicEventAppViewStore {
    func beginMapRebuild() throws {
        try database.write { db in
            guard let build = try CalendarMapBuild.find(0).fetchOne(db), build.building == nil else { return }
            try CalendarMapBuild.find(0).update {
                $0.building = #bind(build.active + 1)
                $0.afterURI = #bind(nil)
            }.execute(db)
        }
    }

    @discardableResult
    func rebuildMapBatch(limit: Int = 500, now: Date = .now) throws -> Bool {
        try database.write { db in
            guard let build = try CalendarMapBuild.find(0).fetchOne(db), let generation = build.building else { return true }
            let rows = try CalendarEventBrowseProjection
                .where { $0.uri > (build.afterURI ?? "") }
                .order(by: \.uri).limit(limit).fetchAll(db)
            for row in rows {
                if let event = CalendarMapEvent.project(row, generation: generation, now: now) {
                    try CalendarMapEvent.upsert { event }.execute(db)
                }
            }
            if let last = rows.last {
                try CalendarMapBuild.find(0).update { $0.afterURI = #bind(last.uri) }.execute(db)
                return false
            }
            let expected = try CalendarEventBrowseProjection.where {
                $0.latitude >= #bind(Optional(-CalendarMapCell.maximumLatitude))
                    && $0.latitude <= #bind(Optional(CalendarMapCell.maximumLatitude))
                    && $0.longitude >= #bind(Optional(-180.0)) && $0.longitude <= #bind(Optional(180.0))
            }.fetchCount(db)
            let actual = try CalendarMapEvent.where { $0.generation.eq(generation) }.fetchCount(db)
            guard expected == actual else { throw CalendarBrowseError.mapNotReady }
            try CalendarMapBuild.find(0).update {
                $0.active = #bind(generation)
                $0.building = #bind(nil)
                $0.afterURI = #bind(nil)
            }.execute(db)
            return true
        }
    }

    @discardableResult
    func expireMapEvents(now: Date = .now, limit: Int = 500) throws -> Int {
        try database.write { db in
            let ids = try CalendarMapEvent.where { $0.active && $0.effectiveEnd < #bind(Optional(now)) }
                .order(by: \.effectiveEnd).limit(limit).select(\.id).fetchAll(db)
            try CalendarMapEvent.where { $0.id.in(ids) }.update { $0.active = false }.execute(db)
            var reclaimed = 0
            if let build = try CalendarMapBuild.find(0).fetchOne(db), build.retiring < build.active {
                let obsolete = try CalendarMapEvent.where { $0.generation.eq(build.retiring) }
                    .limit(limit).select(\.id).fetchAll(db)
                try CalendarMapEvent.where { $0.id.in(obsolete) }.delete().execute(db)
                reclaimed = obsolete.count
                // Delete revisions only after the old points: point-deletion triggers bump them.
                if obsolete.isEmpty {
                    let prefix = "\(build.retiring)|"
                    let revisions = try CalendarMapRevision.where { $0.id >= prefix && $0.id < prefix + "~" }
                        .limit(limit).select(\.id).fetchAll(db)
                    try CalendarMapRevision.where { $0.id.in(revisions) }.delete().execute(db)
                    reclaimed = revisions.count
                    if revisions.isEmpty {
                        try CalendarMapBuild.find(0).update { $0.retiring = #bind(build.retiring + 1) }.execute(db)
                    }
                }
            }
            return max(ids.count, reclaimed)
        }
    }
}
