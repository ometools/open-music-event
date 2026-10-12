import ATProto
import Foundation
import GRDB
import OpenMusicEventLexicon
import SQLiteData

struct CalendarBrowseQuery: XRPC.Query, Sendable {
    static let nsid = ATProto.NSID("app.openmusicevent.calendar.browseEventSummaries")
    typealias Input = Never
    typealias Output = CalendarSummaryPage
    var parameters: Parameters

    struct Parameters: Codable, Equatable, Sendable {
        var catalogs: [ATProto.NSID]
        var query: String? = nil
        var north: Double? = nil
        var south: Double? = nil
        var east: Double? = nil
        var west: Double? = nil
        var cursor: String? = nil
        var limit: Int? = nil
        var dates: String? = nil
        var cell: String? = nil
        var publisherMode: String? = nil
        var publishers: [Int]? = nil
    }
}

struct CalendarSearchMapQuery: XRPC.Query, Sendable {
    static let nsid = ATProto.NSID("app.openmusicevent.calendar.getSearchMapItems")
    typealias Input = Never
    typealias Output = CalendarSearchMapPage
    var parameters: Parameters

    struct Parameters: Codable, Equatable, Sendable {
        var uris: [String]
        var zoom: Double
    }
}

struct CalendarSearchMapPage: Codable, Sendable {
    var events: [OME.CalendarEvent.MapPoint]
    var clusters: [OME.CalendarEvent.MapCluster]
    var clusterMembers: [String: [String]]
    var metrics: OME.CalendarEvent.MapItemPage.Metrics
}

struct CalendarSummaryPage: Codable, Sendable {
    var events: [CalendarEventSummary]
    var cursor: String?
    var hasMore: Bool
    var evaluatedAt: Date
}

struct CalendarEventSummary: Codable, Equatable, Sendable {
    var uri: String
    var catalog: String
    var name: String
    var startsAt: Date?
    var endsAt: Date?
    var latitude: Double?
    var longitude: Double?
    var markerMedia: OME.CalendarEvent.Media?
    var timeZoneIdentifier: String?
    var locationSummary: String?
    var dateOnly: Bool
    var hasEventViewer: Bool
}

@Selection
struct CalendarSummaryRow: Sendable {
    let uri: String
    let catalog: String
    let name: String
    let startsAt: Date?
    let endsAt: Date?
    let latitude: Double?
    let longitude: Double?
    let markerMedia: Data?
    let timeZoneIdentifier: String?
    let locationSummary: String?
    let dateOnly: Bool
    let hasEventViewer: Bool
    let temporalRank: Int
    let orderDate: Date?

    func summary() throws -> CalendarEventSummary {
        try .init(uri: uri, catalog: catalog, name: name, startsAt: startsAt, endsAt: endsAt,
                  latitude: latitude, longitude: longitude,
                  markerMedia: markerMedia.map { try JSONDecoder().decode(OME.CalendarEvent.Media.self, from: $0) },
                  timeZoneIdentifier: timeZoneIdentifier, locationSummary: locationSummary,
                  dateOnly: dateOnly, hasEventViewer: hasEventViewer)
    }
}

enum CalendarBrowseError: Error {
    case invalidParameters
    case mapNotReady
    case mapBusy
    case mapGenerationChanged
}

extension OpenMusicEventAppViewStore {
    func browseEventSummaries(_ parameters: CalendarBrowseQuery.Parameters, now: Date = .now) throws -> CalendarSummaryPage {
        let catalogs = try CalendarEventBrowseProjection.catalogs(parameters.catalogs)
        let lens = try CalendarPublisherLens(mode: parameters.publisherMode, publishers: parameters.publishers)
        let limit = parameters.limit ?? 50
        let dates = parameters.dates ?? "current"
        guard (1...50).contains(limit), ["current", "all"].contains(dates),
              (parameters.query?.count ?? 0) <= 256,
              (parameters.cursor?.count ?? 0) <= 4096 else { throw CalendarBrowseError.invalidParameters }
        let bounds = try OME.CalendarEvent.BrowseEvents.Parameters(catalogs: parameters.catalogs,
            north: parameters.north, south: parameters.south, east: parameters.east, west: parameters.west).bounds()
        let query = CalendarEventBrowseProjection.searchQuery(parameters.query)
        let cell = try parameters.cell.map(Self.decodeMapCell)
        let fingerprintData = [catalogs.map(\.rawValue).sorted().joined(separator: ","), query ?? "",
                               bounds.map { "\($0.north),\($0.south),\($0.east),\($0.west)" } ?? "",
                               dates, cell ?? "", lens.fingerprint]
        let fingerprint = try JSONEncoder().encode(fingerprintData).base64EncodedString()
        let cursor = try parameters.cursor.map(CalendarEventBrowseCursor.decode)
        guard cursor == nil || cursor?.fingerprint == fingerprint else {
            throw OpenMusicEventAppViewStoreError.invalidCursor(parameters.cursor ?? "")
        }
        let clock = cursor?.evaluationDate ?? now
        let rows = try database.read { db in
            typealias P = CalendarEventBrowseProjection
            let search: QueryFragment = query.map {
                "\(P.uri) IN (SELECT \(CalendarEventBrowseSearch.uri) FROM \(CalendarEventBrowseSearch.self) WHERE \(CalendarEventBrowseSearch.searchText) MATCH \(bind: $0))"
            } ?? "1"
            let spatial = P.browseSpatialPredicate(bounds: bounds)
            var membership = lens.predicate(uri: "\(P.uri)", catalog: "\(P.catalog)")
            if let cell {
                let generation = try CalendarMapBuild.find(0).select(\.active).fetchOne(db) ?? 0
                let selectedCatalogs = CalendarMapEvent.catalog.in(catalogs.map(\.rawValue))
                let clusterMembership: QueryFragment = """
                    \(P.uri) IN (SELECT \(CalendarMapEvent.uri) FROM \(CalendarMapEvent.self)
                      WHERE \(CalendarMapEvent.generation) = \(generation)
                      AND \(selectedCatalogs)
                      AND \(CalendarMapEvent.cell) >= \(cell) AND \(CalendarMapEvent.cell) < \(cell + "4"))
                    """
                membership = "(\(membership)) AND (\(clusterMembership))"
            }
            let keys = try Self.summaryPageKeys(catalogs: catalogs.map(\.rawValue), search: search,
                spatial: spatial, membership: membership, now: clock, allDates: dates == "all",
                cursor: cursor, limit: limit + 1)
            return try #sql("""
                WITH page AS MATERIALIZED (\(keys))
                SELECT \(P.uri),\(P.catalog),\(P.name),\(P.startsAt),\(P.endsAt),\(P.latitude),\(P.longitude),\(P.markerMedia),
                  json_extract(\(P.event),'$.timeZoneIdentifier') AS timeZoneIdentifier,
                  COALESCE(json_extract(\(P.event),'$.locations[0].name'),json_extract(\(P.event),'$.locations[0].locality')) AS locationSummary,
                  COALESCE(length(json_extract(\(P.event),'$.event.startDate'))=10,0) AS dateOnly,
                  \(P.hasEventViewer),page.temporalRank,page.orderDate
                FROM page JOIN \(P.self) ON \(P.uri)=page.uri
                ORDER BY page.temporalRank, CASE WHEN page.temporalRank<3 THEN page.orderDate END,
                  CASE WHEN page.temporalRank=3 THEN page.orderDate END DESC,page.uri
                """, as: CalendarSummaryRow.self).fetchAll(db)
        }
        let page = Array(rows.prefix(limit))
        let next = try rows.count > limit ? page.last.map {
            try CalendarEventBrowseCursor(fingerprint: fingerprint, evaluationDate: clock,
                temporalRank: $0.temporalRank, orderDate: $0.orderDate, uri: $0.uri).encoded()
        } : nil
        return try .init(events: page.map { try $0.summary() }, cursor: next,
                         hasMore: next != nil, evaluatedAt: clock)
    }

    private static func summaryPageKeys(
        catalogs: [String], search: QueryFragment, spatial: QueryFragment, membership: QueryFragment,
        now: Date, allDates: Bool, cursor: CalendarEventBrowseCursor?, limit: Int
    ) throws -> QueryFragment {
        typealias P = CalendarEventBrowseProjection
        let end: QueryFragment = "COALESCE(\(P.endsAt),\(P.startsAt))"
        let periods: [QueryFragment] = [
            "\(P.startsAt)<=\(now) AND \(end)>=\(now) AND \(P.hasEventViewer)=1",
            "\(P.startsAt)>\(now)",
            "\(P.startsAt)<=\(now) AND \(end)>=\(now) AND \(P.hasEventViewer)=0",
            "\(P.startsAt) IS NOT NULL AND \(end)<\(now)",
            "\(P.startsAt) IS NULL"
        ]
        var branches: [QueryFragment] = []
        for rank in 0...(allDates ? 4 : 2) where rank >= (cursor?.temporalRank ?? 0) {
            let orderDate: QueryFragment = rank == 4 ? "NULL" : (rank == 3 ? end : "\(P.startsAt)")
            let direction: QueryFragment = rank == 3 ? "DESC" : "ASC"
            let index: QueryFragment = rank == 0 || rank == 2 ? "INDEXED BY calendar_browse_current" : ""
            var continuation: QueryFragment = "1"
            if let cursor, cursor.temporalRank == rank {
                if rank == 4 { continuation = "\(P.uri)>\(cursor.uri)" }
                else {
                    guard let date = cursor.orderDate else { throw CalendarBrowseError.invalidParameters }
                    let comparison: QueryFragment = rank == 3 ? "<" : ">"
                    continuation = "(\(orderDate)\(comparison)\(date) OR (\(orderDate)=\(date) AND \(P.uri)>\(cursor.uri)))"
                }
            }
            for catalog in catalogs {
                branches.append("""
                    SELECT * FROM (
                      SELECT \(P.uri) AS uri,\(rank) AS temporalRank,\(orderDate) AS orderDate
                      FROM \(P.self) \(index) WHERE \(P.catalog)=\(catalog) AND \(periods[rank])
                        AND \(search) AND \(spatial) AND \(membership) AND \(continuation)
                      ORDER BY \(orderDate) \(direction),\(P.uri) LIMIT \(limit)
                    )
                    """)
            }
        }
        guard !branches.isEmpty else { return "SELECT NULL AS uri,0 AS temporalRank,NULL AS orderDate WHERE 0" }
        return """
            SELECT * FROM (\(branches.joined(separator: " UNION ALL ")))
            ORDER BY temporalRank,CASE WHEN temporalRank<3 THEN orderDate END,
              CASE WHEN temporalRank=3 THEN orderDate END DESC,uri LIMIT \(limit)
            """
    }

    static func decodeMapCell(_ value: String) throws -> String {
        guard value.hasPrefix("q1:"), (3...21).contains(value.count - 3),
              value.dropFirst(3).allSatisfy({ "0123".contains($0) }) else { throw CalendarBrowseError.invalidParameters }
        return String(value.dropFirst(3))
    }

    func searchMapItems(_ parameters: CalendarSearchMapQuery.Parameters) throws -> CalendarSearchMapPage {
        guard parameters.uris.count <= 50, parameters.zoom.isFinite, (0...18).contains(parameters.zoom),
              parameters.uris.allSatisfy({ $0.count <= 2048 && ATProto.URI($0) != nil })
        else { throw CalendarBrowseError.invalidParameters }
        let started = ContinuousClock.now
        let rows = try database.read { try Self.mapPointRows(uris: parameters.uris, in: $0) }
        let points = try rows.compactMap { row -> OME.CalendarEvent.MapPoint? in
            let latitude = row.latitude, longitude = row.longitude
            guard latitude.isFinite, longitude.isFinite,
                  abs(latitude) <= CalendarMapCell.maximumLatitude, abs(longitude) <= 180,
                  let uri = ATProto.URI(row.uri), let catalog = ATProto.NSID(row.catalog) else { return nil }
            return try .init(uri: uri, catalog: catalog, name: row.name, startsAt: row.startsAt,
                endsAt: row.endsAt, latitude: latitude, longitude: longitude,
                markerMedia: row.markerMedia.map { try JSONDecoder().decode(OME.CalendarEvent.Media.self, from: $0) })
        }
        let clusteringStarted = ContinuousClock.now
        let grouped = CalendarEventMapClusterer.cluster(points, zoom: parameters.zoom)
        let zoom = Int(parameters.zoom.rounded(.down))
        let members = Dictionary(grouping: points) { point in
            let bucket = CalendarEventMapClusterer.bucket(for: point, zoom: zoom)
            return "z\(bucket.zoom)-x\(bucket.column)-y\(bucket.row)"
        }.filter { $0.value.count > 1 }.mapValues { $0.map { $0.uri.description } }
        func milliseconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        }
        return .init(events: grouped.events, clusters: grouped.clusters, clusterMembers: members,
            metrics: .init(candidateCount: points.count, itemCount: grouped.events.count + grouped.clusters.count,
                           databaseDurationMilliseconds: milliseconds(started.duration(to: clusteringStarted)),
                           clusteringDurationMilliseconds: milliseconds(clusteringStarted.duration(to: .now))))
    }

    static func mapPointRows(uris: [String], in db: Database) throws -> [CalendarEventMapPointRow] {
        typealias P = CalendarEventBrowseProjection
        let predicate = P.uri.in(uris)
        return try #sql("""
          SELECT \(P.uri),\(P.catalog),\(P.name),\(P.startsAt),\(P.endsAt),\(P.latitude),\(P.longitude),\(P.markerMedia)
          FROM \(P.self) WHERE \(predicate) AND \(P.latitude) IS NOT NULL AND \(P.longitude) IS NOT NULL
          ORDER BY \(P.uri)
          """, as: CalendarEventMapPointRow.self).fetchAll(db)
    }
}
