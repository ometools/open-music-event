import ATProto
import Crypto
import Foundation
import GRDB
import Gzip
import Hummingbird
import OpenMusicEventLexicon
import SQLiteData
import SwiftProtobuf

struct CalendarMapTileRequest: Hashable, Sendable {
    let z: Int
    let x: Int
    let y: Int
    let catalogs: [String]
    let allDates: Bool

    init(z: Int, x: Int, y: Int, catalogs: [ATProto.NSID], dates: String) throws {
        guard (0...18).contains(z), (0..<(1 << z)).contains(x), (0..<(1 << z)).contains(y),
              ["current", "all"].contains(dates) else { throw CalendarBrowseError.invalidParameters }
        self.z = z; self.x = x; self.y = y
        self.catalogs = try CalendarEventBrowseProjection.catalogs(catalogs).map(\.rawValue).sorted()
        self.allDates = dates == "all"
    }

    var neighbors: [String] {
        let scale = 1 << z
        var keys = Set<String>()
        for dy in -1...1 where (0..<scale).contains(y + dy) {
            for dx in -1...1 {
                let column = (x + dx + scale) % scale
                keys.insert(CalendarMapCell.key(x: (Double(column) + 0.5) / Double(scale),
                    y: (Double(y + dy) + 0.5) / Double(scale), depth: z))
            }
        }
        return keys.sorted()
    }
}

@Selection
struct CalendarTileCell: Sendable {
    let cell: String
    let count: Int
    let x: Double
    let y: Double
}

struct CalendarMapTile: Sendable {
    var data: Data
    var gzip: Data
    var etag: String
    var featureCount: Int
    var databaseMilliseconds: Double
    var cacheHit = false
}

actor CalendarMapTileCache {
    struct Key: Hashable { var tile: CalendarMapTileRequest; var generation: Int; var revision: Int }
    var entries: [Key: CalendarMapTile] = [:]
    var recency: [Key] = []
    var pending: [Key: Task<CalendarMapTile, any Error>] = [:]
    var bytes = 0
    let capacity = 32 * 1024 * 1024

    func tile(_ request: CalendarMapTileRequest, store: OpenMusicEventAppViewStore) async throws -> CalendarMapTile {
        let lookupStarted = ContinuousClock.now
        let key = try await store.database.read { db in
            let generation = try CalendarMapBuild.find(0).select(\.active).fetchOne(db) ?? 0
            guard generation > 0 else { throw CalendarBrowseError.mapNotReady }
            let ids = request.neighbors.flatMap { prefix in request.catalogs.map { "\(generation)|\(prefix)|\($0)" } }
            let revision = (try CalendarMapRevision.where { $0.id.in(ids) }.select { $0.revision.sum() }.fetchOne(db)).flatMap { $0 } ?? 0
            return Key(tile: request, generation: generation, revision: revision)
        }
        let lookupDuration = lookupStarted.duration(to: .now)
        let lookupMilliseconds = Double(lookupDuration.components.seconds) * 1000
            + Double(lookupDuration.components.attoseconds) / 1e15
        if let cached = entries[key] {
            recency.removeAll { $0 == key }; recency.append(key)
            var result = cached
            result.databaseMilliseconds = lookupMilliseconds
            result.cacheHit = true
            return result
        }
        if let task = pending[key] {
            var result = try await task.value
            result.databaseMilliseconds += lookupMilliseconds
            return result
        }
        guard pending.count < 8 else { throw CalendarBrowseError.mapBusy }
        let task = Task.detached { try store.mapTile(request, generation: key.generation) }
        pending[key] = task
        do {
            let value = try await task.value
            pending[key] = nil
            entries[key] = value; recency.append(key)
            bytes += value.data.count + value.gzip.count
            while bytes > capacity || entries.count > 2048, let first = recency.first {
                recency.removeFirst()
                if let removed = entries.removeValue(forKey: first) { bytes -= removed.data.count + removed.gzip.count }
            }
            var result = value
            result.databaseMilliseconds += lookupMilliseconds
            return result
        } catch CalendarBrowseError.mapGenerationChanged {
            pending[key] = nil
            return try await tile(request, store: store)
        } catch { pending[key] = nil; throw error }
    }
}

extension OpenMusicEventAppViewStore {
    func mapTile(_ request: CalendarMapTileRequest, generation: Int) throws -> CalendarMapTile {
        let started = ContinuousClock.now
        let features: [(Double, Double, [String: String])] = try database.read { db in
            guard try CalendarMapBuild.find(0).select(\.active).fetchOne(db) == generation else {
                throw CalendarBrowseError.mapGenerationChanged
            }
            typealias C = CalendarMapCell
            let count: QueryFragment = request.allDates ? "\(C.columns.count)" : "\(C.activeCount)"
            let xSum: QueryFragment = request.allDates ? "\(C.x)" : "\(C.activeX)"
            let ySum: QueryFragment = request.allDates ? "\(C.y)" : "\(C.activeY)"
            let catalogs = C.catalog.in(request.catalogs)
            var cells: [CalendarTileCell] = []
            for prefix in request.neighbors {
                cells += try #sql("""
                    SELECT \(C.cell),sum(\(count)) AS count,sum(\(xSum)) AS x,sum(\(ySum)) AS y
                    FROM \(C.self) WHERE \(C.generation)=\(generation) AND \(C.depth)=\(request.z + 3)
                      AND \(catalogs) AND \(C.cell)>=\(prefix) AND \(C.cell)<\(prefix + "4")
                    GROUP BY \(C.cell) HAVING sum(\(count))>0 ORDER BY \(C.cell)
                    """, as: CalendarTileCell.self).fetchAll(db)
            }
            let scale = Double(1 << request.z)
            var features: [(Double, Double, [String: String])] = []
            for cell in cells {
                let worldX = cell.x / Double(cell.count), worldY = cell.y / Double(cell.count)
                var tileX = worldX * scale - Double(request.x)
                if tileX < -0.125 { tileX += scale }
                if tileX > 1.125 { tileX -= scale }
                let tileY = worldY * scale - Double(request.y)
                guard (-0.125...1.125).contains(tileX), (-0.125...1.125).contains(tileY) else { continue }
                let members = CalendarMapEvent.where {
                    $0.generation.eq(generation) && $0.catalog.in(request.catalogs)
                      && $0.cell >= cell.cell && $0.cell < cell.cell + "4"
                }.where { request.allDates || $0.active }
                var properties: [String: String] = ["kind": "cluster", "clusterID": "q1:\(cell.cell)", "count": String(cell.count)]
                if cell.count == 1,
                   let uri = try members.select(\.uri).limit(1).fetchOne(db),
                   let row = try Self.mapPointRows(uris: [uri], in: db).first {
                    let media = try row.markerMedia.map { try JSONDecoder().decode(OME.CalendarEvent.Media.self, from: $0) }
                    properties = ["kind": "event", "uri": uri, "name": row.name,
                        "catalog": row.catalog, "color": "#a05cff",
                        "markerImage": media?.url.absoluteString ?? "",
                        "markerImageRenderKind": media?.renderKind?.rawValue ?? ""]
                } else {
                    var first: [String] = [], last: [String] = []
                    for catalog in request.catalogs {
                        let scoped = members.where { $0.catalog.eq(catalog) }
                        if let key = try scoped.order(by: \.cell).select(\.cell).limit(1).fetchOne(db) { first.append(key) }
                        if let key = try scoped.order { $0.cell.desc() }.select(\.cell).limit(1).fetchOne(db) { last.append(key) }
                    }
                    let common = zip(first.min() ?? cell.cell, last.max() ?? cell.cell).prefix { $0 == $1 }.count
                    properties["expansionZoom"] = String(min(18, max(request.z + 1, common - 2)))
                }
                features.append((tileX, tileY, properties))
            }
            return features
        }
        let duration = started.duration(to: .now)
        let milliseconds = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        var layer = OmeVectorTile_Tile.Layer()
        layer.version = 2; layer.name = "events"; layer.extent = 4096
        for (x, y, properties) in features {
            var feature = OmeVectorTile_Tile.Feature()
            feature.type = .point
            func zigzag(_ value: Int32) -> UInt32 { UInt32(bitPattern: (value << 1) ^ (value >> 31)) }
            feature.geometry = [9, zigzag(Int32((x * 4096).rounded())), zigzag(Int32((y * 4096).rounded()))]
            for (key, text) in properties.sorted(by: { $0.key < $1.key }) {
                let index: Int
                if let existing = layer.keys.firstIndex(of: key) { index = existing }
                else { index = layer.keys.count; layer.keys.append(key) }
                var value = OmeVectorTile_Tile.Value()
                if key == "count" || key == "expansionZoom" { value.intValue = Int64(text)! }
                else { value.stringValue = text }
                feature.tags.append(contentsOf: [UInt32(index), UInt32(layer.values.count)])
                layer.values.append(value)
            }
            layer.features.append(feature)
        }
        var tile = OmeVectorTile_Tile(); tile.layers = [layer]
        let data = try tile.serializedData()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return try .init(data: data, gzip: data.gzipped(), etag: digest,
                         featureCount: features.count, databaseMilliseconds: milliseconds)
    }
}
