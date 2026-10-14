import ATProto
import ComposableCalendarEvents
import Foundation
import GRDB
import OpenMusicEventLexicon
import OpenMusicEventRouting
import SQLiteData

extension OpenMusicEventAppViewStore {
    func rebuildCalendarEventBrowseProjectionIfNeeded(force: Bool = false) throws {
        let isInconsistent = try database.read { database in
            let sourceCount = try Event.all.fetchCount(database)
                + CommunityCalendarEventProjection.all.fetchCount(database)
            let browseCount = try CalendarEventBrowseProjection.all.fetchCount(database)
            let searchCount = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM \"\(CalendarEventBrowseSearch.tableName)\""
            ) ?? 0
            let coordinateCount = try CalendarEventBrowseProjection
                .where { $0.latitude.isNot(nil) && $0.longitude.isNot(nil) }
                .fetchCount(database)
            let spatialCount = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM \"\(CalendarEventBrowseSpatialIndex.tableName)\""
            ) ?? 0
            let incompleteCount = try CalendarEventBrowseProjection
                .where { $0.name.eq("") }
                .fetchCount(database)
            return browseCount != sourceCount
                || searchCount != browseCount
                || spatialCount != coordinateCount
                || incompleteCount != 0
        }
        guard force || isInconsistent else { return }
        try rebuildCalendarEventBrowseProjection()
    }

    func rebuildCalendarEventBrowseProjection() throws {
        try database.write { database in
            let communityEvents = try CommunityCalendarEventProjection.all
                .select(\.event)
                .fetchAll(database)
                .compactMap { try? JSONDecoder().decode(OME.CalendarEvent.self, from: $0) }

            try CalendarEventBrowseProjection.deleteAll(in: database)
            for event in try Event.all.fetchAll(database) {
                try CalendarEventBrowseProjection.upsertCanonicalEvent(
                    id: event.id,
                    deleteExistingSearchDocument: false,
                    in: database
                )
            }
            for event in communityEvents {
                try CalendarEventBrowseProjection.upsert(
                    event,
                    deleteExistingSearchDocument: false,
                    in: database
                )
            }
        }
    }

    func browseCalendarEvents(
        parameters: OME.CalendarEvent.BrowseEvents.Parameters,
        appViewHost: ATProto.PDSHost,
        now: Date = .now
    ) throws -> OME.CalendarEvent.Page {
        let catalogs = try CalendarEventBrowseProjection.catalogs(parameters.catalogs)
        let bounds = try parameters.bounds()
        let query = CalendarEventBrowseProjection.searchQuery(parameters.query)
        let fingerprint = CalendarEventBrowseCursor.fingerprint(
            catalogs: catalogs,
            query: query,
            bounds: bounds
        )
        let cursor = try parameters.cursor.map(CalendarEventBrowseCursor.decode)
        guard cursor?.fingerprint == nil || cursor?.fingerprint == fingerprint else {
            throw OpenMusicEventAppViewStoreError.invalidCursor(parameters.cursor ?? "")
        }
        let evaluationDate = cursor?.evaluationDate ?? now

        let rows = try database.read { database in
            try CalendarEventBrowseProjection.fetchRows(
                catalogs: catalogs,
                query: query,
                bounds: bounds,
                cursor: cursor,
                evaluationDate: evaluationDate,
                limit: parameters.limit + 1,
                in: database
            )
        }
        let pageRows = Array(rows.prefix(parameters.limit))
        let events = try pageRows.map { row in
            var event = try JSONDecoder().decode(OME.CalendarEvent.self, from: row.event)
            event.source.appViewHost = appViewHost
            return event
        }
        let nextCursor = rows.count > parameters.limit
            ? try pageRows.last.map {
                try CalendarEventBrowseCursor(
                    fingerprint: fingerprint,
                    evaluationDate: evaluationDate,
                    temporalRank: $0.temporalRank,
                    orderDate: $0.orderDate,
                    uri: $0.uri
                )
                .encoded()
            }
            : nil
        return OME.CalendarEvent.Page(events: events, cursor: nextCursor)
    }

    func calendarEvent(
        uri: ATProto.URI,
        appViewHost: ATProto.PDSHost
    ) throws -> OME.CalendarEvent? {
        try database.read { database in
            guard let data = try CalendarEventBrowseProjection.find(uri.description)
                .select(\.event)
                .fetchOne(database)
            else { return nil }
            var event = try JSONDecoder().decode(OME.CalendarEvent.self, from: data)
            try CalendarLocationContext.enrich(&event, in: database)
            event.source.appViewHost = appViewHost
            if let canonical = try Event.find(uri).fetchOne(database),
               canonical.hasDetailsBeyondBrowse,
               let viewerURL = URL(
                   string: "https://\(appViewHost.rawValue)" + openMusicEventEventPathRouter.path(for: uri)
               )
            {
                event.links.append(
                    .init(
                        name: "Enter Event",
                        uri: viewerURL,
                        source: "app.openmusicevent.eventViewer"
                    )
                )
            }
            return event
        }
    }
}

extension Event {
    var hasDetailsBeyondBrowse: Bool {
        programs?.isEmpty == false
            || schedules?.isEmpty == false
            || categories?.isEmpty == false
            || siteMap != nil
    }
}

@Table("calendarEventBrowseProjections")
struct CalendarEventBrowseProjection: Codable, Equatable, Sendable {
    @Column(primaryKey: true) var uri: String
    var catalog: String
    var sourceID: String?
    var name: String
    var startsAt: Date?
    var endsAt: Date?
    var createdAt: Date?
    var latitude: Double?
    var longitude: Double?
    var markerMedia: Data?
    var hasEventViewer: Bool
    var event: Data

    static func registerMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create calendar event browse search projection") { database in
            let tableName = Self.tableName
            let catalogIndexName = "\(tableName)_catalog_order"
            let locationIndexName = "\(tableName)_location"
            try #sql(
                """
                CREATE TABLE \(quote: tableName) (
                  "uri" TEXT PRIMARY KEY NOT NULL,
                  "catalog" TEXT NOT NULL,
                  "sourceID" TEXT,
                  "name" TEXT NOT NULL,
                  "startsAt" TEXT,
                  "endsAt" TEXT,
                  "createdAt" TEXT,
                  "latitude" REAL,
                  "longitude" REAL,
                  "markerMedia" BLOB,
                  "hasEventViewer" INTEGER NOT NULL DEFAULT 0,
                  "event" BLOB NOT NULL
                ) STRICT
                """
            )
            .execute(database)
            try #sql(
                """
                CREATE INDEX \(quote: catalogIndexName)
                ON \(quote: tableName) (
                  "catalog",
                  "startsAt",
                  "uri"
                )
                """
            )
            .execute(database)
            try #sql(
                """
                CREATE INDEX \(quote: locationIndexName)
                ON \(quote: tableName) (
                  "latitude",
                  "longitude"
                )
                """
            )
            .execute(database)
            try #sql(
                """
                CREATE VIRTUAL TABLE \(quote: CalendarEventBrowseSearch.tableName)
                USING fts5(
                  "uri" UNINDEXED,
                  "searchText",
                  tokenize = 'unicode61 remove_diacritics 2'
                )
                """
            )
            .execute(database)
        }

        migrator.registerMigration("Add calendar event browse spatial projection") { database in
            let columns = try database.columns(in: Self.tableName).map(\.name)
            if !columns.contains("name") {
                try #sql(
                    "ALTER TABLE \(quote: Self.tableName) ADD COLUMN \"name\" TEXT NOT NULL DEFAULT ''"
                )
                .execute(database)
            }
            if !columns.contains("endsAt") {
                try #sql(
                    "ALTER TABLE \(quote: Self.tableName) ADD COLUMN \"endsAt\" TEXT"
                )
                .execute(database)
            }
            if !columns.contains("markerMedia") {
                try #sql(
                    "ALTER TABLE \(quote: Self.tableName) ADD COLUMN \"markerMedia\" BLOB"
                )
                .execute(database)
            }

            try #sql(
                """
                CREATE VIRTUAL TABLE IF NOT EXISTS \(quote: CalendarEventBrowseSpatialIndex.tableName)
                USING rtree(
                  "id",
                  "minLatitude",
                  "maxLatitude",
                  "minLongitude",
                  "maxLongitude"
                )
                """
            )
            .execute(database)
            try #sql(
                """
                INSERT OR REPLACE INTO \(quote: CalendarEventBrowseSpatialIndex.tableName)
                  ("id", "minLatitude", "maxLatitude", "minLongitude", "maxLongitude")
                SELECT rowid, "latitude", "latitude", "longitude", "longitude"
                FROM \(quote: Self.tableName)
                WHERE "latitude" IS NOT NULL AND "longitude" IS NOT NULL
                """
            )
            .execute(database)
            try Self.createSpatialTriggers(in: database)
        }

        migrator.registerMigration("Add calendar event viewer browse priority") { database in
            let columns = try database.columns(in: Self.tableName).map(\.name)
            if !columns.contains("hasEventViewer") {
                try #sql(
                    "ALTER TABLE \(quote: Self.tableName) ADD COLUMN \"hasEventViewer\" INTEGER NOT NULL DEFAULT 0"
                )
                .execute(database)
            }
            for event in try Event.all.fetchAll(database) where event.hasDetailsBeyondBrowse {
                try #sql(
                    "UPDATE \(quote: Self.tableName) SET \"hasEventViewer\" = 1 WHERE \"uri\" = \(bind: event.id.description)"
                )
                .execute(database)
            }
        }
    }

    static func registerBackfillMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Backfill complete community calendar browse sources") { database in
            try CommunityCalendarEventProjection.backfillPresentRecords(in: database)
        }
    }

    static func createSpatialTriggers(in database: Database) throws {
        let insertTrigger = "\(tableName)_spatial_insert"
        let updateTrigger = "\(tableName)_spatial_update"
        let deleteTrigger = "\(tableName)_spatial_delete"
        try #sql(
            """
            CREATE TRIGGER IF NOT EXISTS \(quote: insertTrigger)
            AFTER INSERT ON \(quote: tableName)
            WHEN NEW."latitude" IS NOT NULL AND NEW."longitude" IS NOT NULL
            BEGIN
              INSERT OR REPLACE INTO \(quote: CalendarEventBrowseSpatialIndex.tableName)
                ("id", "minLatitude", "maxLatitude", "minLongitude", "maxLongitude")
              VALUES (NEW.rowid, NEW."latitude", NEW."latitude", NEW."longitude", NEW."longitude");
            END
            """
        )
        .execute(database)
        try #sql(
            """
            CREATE TRIGGER IF NOT EXISTS \(quote: updateTrigger)
            AFTER UPDATE OF "latitude", "longitude" ON \(quote: tableName)
            BEGIN
              DELETE FROM \(quote: CalendarEventBrowseSpatialIndex.tableName) WHERE "id" = OLD.rowid;
              INSERT INTO \(quote: CalendarEventBrowseSpatialIndex.tableName)
                ("id", "minLatitude", "maxLatitude", "minLongitude", "maxLongitude")
              SELECT NEW.rowid, NEW."latitude", NEW."latitude", NEW."longitude", NEW."longitude"
              WHERE NEW."latitude" IS NOT NULL AND NEW."longitude" IS NOT NULL;
            END
            """
        )
        .execute(database)
        try #sql(
            """
            CREATE TRIGGER IF NOT EXISTS \(quote: deleteTrigger)
            AFTER DELETE ON \(quote: tableName)
            BEGIN
              DELETE FROM \(quote: CalendarEventBrowseSpatialIndex.tableName) WHERE "id" = OLD.rowid;
            END
            """
        )
        .execute(database)
    }

    static func upsert(
        _ event: OME.CalendarEvent,
        hasEventViewer: Bool = false,
        searchText additionalSearchText: String = "",
        sourceID: String? = nil,
        deleteExistingSearchDocument: Bool = true,
        now: Date = .now,
        in database: Database
    ) throws {
        var storedEvent = event
        storedEvent.source.appViewHost = nil
        if event.locations.allSatisfy({ $0.latitude == nil || $0.longitude == nil }),
           let address = event.locations.compactMap(\.geocodingAddress).first {
            switch try CalendarGeocode.cached(address: address, in: database) {
            case let .coordinates(latitude, longitude):
                if let index = storedEvent.locations.firstIndex(where: {
                    $0.geocodingAddress == address
                }) {
                    storedEvent.locations[index].latitude = String(latitude)
                    storedEvent.locations[index].longitude = String(longitude)
                }
            case .noResult:
                break
            case nil:
                try CalendarGeocode.enqueue(address: address, in: database)
            }
        }
        let coordinates = storedEvent.locations.lazy.compactMap { location -> (Double, Double)? in
            guard let latitude = location.latitude.flatMap(Double.init),
                  let longitude = location.longitude.flatMap(Double.init),
                  latitude.isFinite,
                  longitude.isFinite,
                  (-90...90).contains(latitude),
                  (-180...180).contains(longitude)
            else { return nil }
            return (latitude, longitude)
        }
        .first
        if let coordinates {
            try CalendarLocationContext.ensure(latitude: coordinates.0, longitude: coordinates.1, in: database)
        }
        let markerMedia = storedEvent.preferredMarkerMedia
        let markerMediaData = try markerMedia.map { try JSONEncoder().encode($0) }
        let encodedEvent = try JSONEncoder().encode(storedEvent)

        let browseRow = Self(
                uri: event.uri.description,
                catalog: event.source.collection.rawValue,
                sourceID: sourceID,
                name: storedEvent.name,
                startsAt: event.startsAt,
                endsAt: event.endsAt,
                createdAt: event.createdAt,
                latitude: coordinates?.0,
                longitude: coordinates?.1,
                markerMedia: markerMediaData,
                hasEventViewer: hasEventViewer,
                event: encodedEvent
            )
        try Self.upsert { browseRow }.execute(database)
        try CalendarMapEvent.synchronize(browseRow, now: now, in: database)

        if deleteExistingSearchDocument {
            try CalendarEventBrowseSearch
                .where { $0.uri.eq(event.uri.description) }
                .delete()
                .execute(database)
        }
        try CalendarEventBrowseSearch.insert {
            CalendarEventBrowseSearch(
                uri: event.uri.description,
                searchText: storedEvent.searchText(additionalSearchText)
            )
        }
        .execute(database)
    }

    static func delete(uri: String, in database: Database) throws {
        try CalendarEventBrowseSearch
            .where { $0.uri.eq(uri) }
            .delete()
            .execute(database)
        try Self.find(uri).delete().execute(database)
    }

    static func delete(sourceID: String, in database: Database) throws {
        let uris = try Self
            .where { $0.sourceID.eq(sourceID) }
            .select(\.uri)
            .fetchAll(database)
        for uri in uris {
            try delete(uri: uri, in: database)
        }
    }

    static func deleteAll(in database: Database) throws {
        try CalendarEventBrowseSearch.delete().execute(database)
        try Self.delete().execute(database)
    }

    static func fetchRows(
        catalogs: Set<ATProto.NSID>,
        query: String?,
        bounds: OME.CalendarEvent.BrowseEvents.Bounds?,
        cursor: CalendarEventBrowseCursor?,
        evaluationDate: Date,
        limit: Int,
        in database: Database
    ) throws -> [CalendarEventBrowseRow] {
        let catalogPredicate = Self.catalog.in(catalogs.map(\.rawValue))
        let searchPredicate: QueryFragment = query.map {
            "\(Self.uri) IN (SELECT \(CalendarEventBrowseSearch.uri) FROM \(CalendarEventBrowseSearch.self) WHERE \(CalendarEventBrowseSearch.searchText) MATCH \(bind: $0))"
        } ?? "1"
        let spatialPredicate = browseSpatialPredicate(bounds: bounds)
        let cursorPredicate = try cursorPredicate(cursor)
        return try #sql(
            """
            WITH ranked AS (
              SELECT
                \(Self.uri) AS "uri",
                \(Self.startsAt) AS "startsAt",
                CASE
                  WHEN \(Self.startsAt) IS NULL THEN 4
                  WHEN \(Self.startsAt) <= \(evaluationDate)
                    AND COALESCE(\(Self.endsAt), \(Self.startsAt)) >= \(evaluationDate)
                    AND \(Self.hasEventViewer) THEN 0
                  WHEN \(Self.startsAt) > \(evaluationDate) THEN 1
                  WHEN COALESCE(\(Self.endsAt), \(Self.startsAt)) >= \(evaluationDate) THEN 2
                  ELSE 3
                END AS "temporalRank",
                CASE
                  WHEN \(Self.startsAt) IS NULL THEN NULL
                  WHEN COALESCE(\(Self.endsAt), \(Self.startsAt)) < \(evaluationDate)
                    THEN COALESCE(\(Self.endsAt), \(Self.startsAt))
                  ELSE \(Self.startsAt)
                END AS "orderDate"
              FROM \(Self.self)
              WHERE \(catalogPredicate)
                AND \(searchPredicate)
                AND \(spatialPredicate)
            ), page AS MATERIALIZED (
            SELECT * FROM ranked
            WHERE \(cursorPredicate)
            ORDER BY
              "temporalRank" ASC,
              CASE WHEN "temporalRank" IN (0, 1, 2) THEN "orderDate" END ASC,
              CASE WHEN "temporalRank" = 3 THEN "orderDate" END DESC,
              "uri" ASC
            LIMIT \(limit)
            )
            SELECT page.uri,page.startsAt,\(Self.event),page.temporalRank,page.orderDate
            FROM page JOIN \(Self.self) ON \(Self.uri)=page.uri
            ORDER BY page.temporalRank,
              CASE WHEN page.temporalRank<3 THEN page.orderDate END,
              CASE WHEN page.temporalRank=3 THEN page.orderDate END DESC,page.uri
            """,
            as: CalendarEventBrowseRow.self
        )
        .fetchAll(database)
    }

    static func catalogs(_ values: [ATProto.NSID]) throws -> Set<ATProto.NSID> {
        let catalogs = Set(values)
        let supportedCatalogs: Set<ATProto.NSID> = [
            ATProto.NSID(Event.lexiconID.rawValue),
            Community.CalendarEvent.nsid,
        ]
        guard !catalogs.isEmpty, catalogs.isSubset(of: supportedCatalogs) else {
            throw CalendarEventBrowseProjectionError.unknownCatalog
        }
        return catalogs
    }

    static func searchQuery(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty?
            .ftsQuery
    }

    static func spatialPredicate(
        bounds: OME.CalendarEvent.BrowseEvents.Bounds?
    ) -> QueryFragment {
        guard let bounds else { return "1" }
        let latitude: QueryFragment =
            "spatial.\(quote: "minLatitude") <= \(bounds.north) AND spatial.\(quote: "maxLatitude") >= \(bounds.south)"
        if bounds.crossesAntimeridian {
            let westernRange: QueryFragment =
                "spatial.\(quote: "minLongitude") <= 180 AND spatial.\(quote: "maxLongitude") >= \(bounds.west)"
            let easternRange: QueryFragment =
                "spatial.\(quote: "minLongitude") <= \(bounds.east) AND spatial.\(quote: "maxLongitude") >= -180"
            return "\(latitude) AND ((\(westernRange)) OR (\(easternRange)))"
        }
        return "\(latitude) AND spatial.\(quote: "minLongitude") <= \(bounds.east) AND spatial.\(quote: "maxLongitude") >= \(bounds.west)"
    }

    static func browseSpatialPredicate(
        bounds: OME.CalendarEvent.BrowseEvents.Bounds?
    ) -> QueryFragment {
        guard let bounds else { return "1" }
        let latitude: QueryFragment = "\(Self.latitude) >= \(bounds.south) AND \(Self.latitude) <= \(bounds.north)"
        let longitude: QueryFragment = bounds.crossesAntimeridian
            ? "(\(Self.longitude) >= \(bounds.west) OR \(Self.longitude) <= \(bounds.east))"
            : "\(Self.longitude) >= \(bounds.west) AND \(Self.longitude) <= \(bounds.east)"
        let ranges: QueryFragment
        if bounds.crossesAntimeridian {
            ranges = """
              SELECT id FROM \(quote: CalendarEventBrowseSpatialIndex.tableName)
              WHERE minLatitude<=\(bounds.north) AND maxLatitude>=\(bounds.south) AND maxLongitude>=\(bounds.west)
              UNION
              SELECT id FROM \(quote: CalendarEventBrowseSpatialIndex.tableName)
              WHERE minLatitude<=\(bounds.north) AND maxLatitude>=\(bounds.south) AND minLongitude<=\(bounds.east)
              """
        } else {
            ranges = """
              SELECT id FROM \(quote: CalendarEventBrowseSpatialIndex.tableName)
              WHERE minLatitude<=\(bounds.north) AND maxLatitude>=\(bounds.south)
                AND minLongitude<=\(bounds.east) AND maxLongitude>=\(bounds.west)
              """
        }
        return """
            \(quote: tableName).rowid IN (\(ranges)) AND \(latitude) AND \(longitude)
            """
    }

    static func cursorPredicate(_ cursor: CalendarEventBrowseCursor?) throws -> QueryFragment {
        guard let cursor else { return "1" }
        guard (0...4).contains(cursor.temporalRank) else {
            throw OpenMusicEventAppViewStoreError.invalidCursor(cursor.uri)
        }
        if cursor.temporalRank == 4 {
            return "\(quote: "temporalRank") > 4 OR (\(quote: "temporalRank") = 4 AND \(quote: "uri") > \(bind: cursor.uri))"
        }
        guard let orderDate = cursor.orderDate else {
            throw OpenMusicEventAppViewStoreError.invalidCursor(cursor.uri)
        }
        let comparison = cursor.temporalRank == 3 ? "<" : ">"
        return """
            \(quote: "temporalRank") > \(cursor.temporalRank)
            OR (
              \(quote: "temporalRank") = \(cursor.temporalRank)
              AND (
                \(quote: "orderDate") \(raw: comparison) \(bind: orderDate)
                OR (\(quote: "orderDate") = \(bind: orderDate) AND \(quote: "uri") > \(bind: cursor.uri))
              )
            )
            """
    }
}

enum CalendarEventMapClusterer {
    struct Result: Equatable, Sendable {
        var events: [OME.CalendarEvent.MapPoint]
        var clusters: [OME.CalendarEvent.MapCluster]
    }

    struct Bucket: Hashable, Comparable, Sendable {
        var zoom: Int
        var column: Int
        var row: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.zoom, lhs.column, lhs.row) < (rhs.zoom, rhs.column, rhs.row)
        }
    }

    static let tileSize = 512.0
    static let clusterCellSize = 72.0
    static let maximumZoom = 18
    static let maximumMercatorLatitude = 85.05112878

    static func cluster(
        _ points: [OME.CalendarEvent.MapPoint],
        zoom: Double
    ) -> Result {
        let zoomLevel = max(0, min(maximumZoom, Int(zoom.rounded(.down))))
        let grouped = Dictionary(grouping: points) { bucket(for: $0, zoom: zoomLevel) }
        var events: [OME.CalendarEvent.MapPoint] = []
        var clusters: [OME.CalendarEvent.MapCluster] = []
        events.reserveCapacity(grouped.count)
        clusters.reserveCapacity(grouped.count)

        for bucket in grouped.keys.sorted() {
            guard let members = grouped[bucket] else { continue }
            if members.count == 1, let event = members.first {
                events.append(event)
                continue
            }
            let bounds = bounds(for: bucket)
            clusters.append(
                OME.CalendarEvent.MapCluster(
                    id: "z\(bucket.zoom)-x\(bucket.column)-y\(bucket.row)",
                    count: members.count,
                    latitude: members.map(\.latitude).reduce(0, +) / Double(members.count),
                    longitude: members.map(\.longitude).reduce(0, +) / Double(members.count),
                    north: bounds.north,
                    south: bounds.south,
                    east: bounds.east,
                    west: bounds.west,
                    expansionZoom: expansionZoom(for: members, after: zoomLevel)
                )
            )
        }
        return Result(events: events, clusters: clusters)
    }

    static func bucket(
        for point: OME.CalendarEvent.MapPoint,
        zoom: Int
    ) -> Bucket {
        let worldSize = tileSize * pow(2, Double(zoom))
        let longitude = min(0.999999999999, max(0, (point.longitude + 180) / 360))
        let latitude = min(maximumMercatorLatitude, max(-maximumMercatorLatitude, point.latitude))
        let radians = latitude * .pi / 180
        let mercatorY = 0.5 - log((1 + sin(radians)) / (1 - sin(radians))) / (4 * .pi)
        return Bucket(
            zoom: zoom,
            column: Int((longitude * worldSize / clusterCellSize).rounded(.down)),
            row: Int((mercatorY * worldSize / clusterCellSize).rounded(.down))
        )
    }

    static func bounds(
        for bucket: Bucket
    ) -> (north: Double, south: Double, east: Double, west: Double) {
        let worldSize = tileSize * pow(2, Double(bucket.zoom))
        let west = Double(bucket.column) * clusterCellSize / worldSize * 360 - 180
        let east = min(180, Double(bucket.column + 1) * clusterCellSize / worldSize * 360 - 180)
        let north = latitude(forMercatorY: Double(bucket.row) * clusterCellSize / worldSize)
        let south = latitude(forMercatorY: min(1, Double(bucket.row + 1) * clusterCellSize / worldSize))
        return (north: north, south: south, east: east, west: west)
    }

    static func expansionZoom(
        for members: [OME.CalendarEvent.MapPoint],
        after zoom: Int
    ) -> Double {
        guard zoom < maximumZoom else { return Double(maximumZoom) }
        for nextZoom in (zoom + 1)...maximumZoom {
            if Set(members.map { bucket(for: $0, zoom: nextZoom) }).count > 1 {
                return Double(nextZoom)
            }
        }
        return Double(maximumZoom)
    }

    static func latitude(forMercatorY value: Double) -> Double {
        atan(sinh(.pi * (1 - 2 * value))) * 180 / .pi
    }
}

@Table("calendarEventBrowseSearch")
struct CalendarEventBrowseSearch: StructuredQueriesSQLiteCore.FTS5, Equatable, Sendable {
    var uri: String
    var searchText: String
}

enum CalendarEventBrowseSpatialIndex {
    static let tableName = "calendarEventBrowseSpatialIndex"
}

@Selection
struct CalendarEventBrowseRow: Equatable, Sendable {
    let uri: String
    let startsAt: Date?
    let event: Data
    let temporalRank: Int
    let orderDate: Date?
}

@Selection
struct CalendarEventMapPointRow: Equatable, Sendable {
    let uri: String
    let catalog: String
    let name: String
    let startsAt: Date?
    let endsAt: Date?
    let latitude: Double
    let longitude: Double
    let markerMedia: Data?
}

struct CalendarEventBrowseCursor: Codable, Equatable, Sendable {
    init(
        fingerprint: String,
        evaluationDate: Date,
        temporalRank: Int,
        orderDate: Date?,
        uri: String
    ) {
        self.fingerprint = fingerprint
        self.evaluationDate = evaluationDate
        self.temporalRank = temporalRank
        self.orderDate = orderDate
        self.uri = uri
    }

    var fingerprint: String
    var evaluationDate: Date
    var temporalRank: Int
    var orderDate: Date?
    var uri: String

    func encoded() throws -> String {
        try JSONEncoder().encode(self)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ value: String) throws -> Self {
        var encoded = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let cursor = try? JSONDecoder().decode(Self.self, from: data),
              (0...4).contains(cursor.temporalRank),
              cursor.temporalRank == 4 || cursor.orderDate != nil
        else { throw OpenMusicEventAppViewStoreError.invalidCursor(value) }
        return cursor
    }

    static func fingerprint(
        catalogs: Set<ATProto.NSID>,
        query: String?,
        bounds: OME.CalendarEvent.BrowseEvents.Bounds?
    ) -> String {
        [
            "viewer-priority-v1",
            catalogs.map(\.rawValue).sorted().joined(separator: ","),
            query ?? "",
            bounds.map { "\($0.north),\($0.south),\($0.east),\($0.west)" } ?? "",
        ]
        .joined(separator: "|")
    }
}

enum CalendarEventBrowseProjectionError: Error, Equatable, Sendable {
    case invalidProjectedIdentifier
    case unknownCatalog
}

private extension Duration {
    var milliseconds: Double {
        let components = self.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

private extension OME.CalendarEvent {
    var preferredMarkerMedia: Media? {
        let roles = ["icon", "logo", "poster", "hero", "photo", "avatar"]
        if let media = media
            .filter({ roles.contains($0.role ?? "") })
            .sorted(by: {
                (roles.firstIndex(of: $0.role ?? "") ?? roles.count)
                    < (roles.firstIndex(of: $1.role ?? "") ?? roles.count)
            })
            .first {
            return media
        }
        return organizer.avatarURL.map {
            Media(url: $0, role: "avatar", renderKind: .fullImage)
        }
    }

    func searchText(_ additionalSearchText: String) -> String {
        var values = [
            name,
            description,
            organizer.displayName,
            organizer.handle,
            additionalSearchText,
        ]
        for location in locations {
            values.append(contentsOf: [
                location.name,
                location.street,
                location.locality,
                location.region,
                location.postalCode,
                location.country,
            ])
        }
        return values.compactMap { $0 }.joined(separator: " ")
    }
}

extension OME.CalendarEvent.Location {
    var geocodingAddress: String? {
        let parts = [street, locality, region, postalCode, country]
            .compactMap { value -> String? in
                guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty
                else { return nil }
                return value
            }
        if !parts.isEmpty { return parts.joined(separator: ", ") }
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }
        return name
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    var ftsQuery: String? {
        let terms = split { !$0.isLetter && !$0.isNumber }
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        return terms.isEmpty ? nil : terms.joined(separator: " ")
    }
}
