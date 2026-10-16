import ATProto
import Foundation
import SQLiteData
import Testing

@testable import OpenMusicEventAppViewServer

@Suite struct CalendarMapCapacityTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OME_GLOBE_BENCHMARK_COUNT"] != nil))
    func `measure synthetic projection capacity separately from browser performance`() throws {
        let count = Int(ProcessInfo.processInfo.environment["OME_GLOBE_BENCHMARK_COUNT"] ?? "") ?? 100_000
        guard (1...10_000_000).contains(count) else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ome-map-capacity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("capacity.sqlite")
        let database = try DatabasePool(path: databaseURL.path)
        let store = try OpenMusicEventAppViewStore(database: database)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let started = ContinuousClock.now
        try database.write { db in
            try #sql("""
                WITH RECURSIVE numbers(i) AS (VALUES(1) UNION ALL SELECT i+1 FROM numbers WHERE i<\(count))
                INSERT INTO \(CalendarEventBrowseProjection.self)
                  (uri,catalog,name,startsAt,latitude,longitude,hasEventViewer,event)
                SELECT 'at://did:plc:capacity/community.lexicon.calendar.event/' || printf('%010d',i),
                  'community.lexicon.calendar.event','Capacity event ' || i,'2028-01-01 00:00:00.000',
                  CASE WHEN i%4=0 THEN (i*104729%160000)/1000.0-80 ELSE 30+(i%300)/20.0 END,
                  CASE WHEN i%4=0 THEN (i*7919%360000)/1000.0-180 ELSE -120+(i%300)/10.0 END,
                  0,CAST('{}' AS BLOB) FROM numbers
                """).execute(db)
            try #sql("""
                INSERT INTO \(CalendarEventBrowseSearch.self) (uri,searchText)
                SELECT uri,name FROM \(CalendarEventBrowseProjection.self)
                """).execute(db)
        }
        let projectionSeconds = started.duration(to: .now).seconds
        FileHandle.standardOutput.write(Data("Capacity fixture: \(count) rows in \(projectionSeconds)s\n".utf8))
        try store.beginMapRebuild()
        var processed = 0
        while try !store.rebuildMapBatch(limit: 2000, now: now) {
            processed += 2000
            if processed % 100_000 == 0 {
                FileHandle.standardOutput.write(Data("Capacity map rebuild: \(processed)/\(count) rows\n".utf8))
            }
        }
        let rebuildSeconds = started.duration(to: .now).seconds - projectionSeconds
        let catalogs = [ATProto.NSID("community.lexicon.calendar.event")]
        var tileMilliseconds: [Double] = [], listMilliseconds: [Double] = []
        var bytes = 0, featureCount = 0
        for _ in 0..<20 {
            let tile = try store.mapTile(.init(z: 0, x: 0, y: 0, catalogs: catalogs, dates: "current"), generation: 2)
            tileMilliseconds.append(tile.databaseMilliseconds)
            bytes = tile.gzip.count; featureCount = tile.featureCount
            let start = ContinuousClock.now
            let page = try store.browseEventSummaries(.init(catalogs: catalogs), now: now)
            #expect(page.events.count == min(50, count))
            listMilliseconds.append(start.duration(to: .now).seconds * 1000)
        }
        let cells = try database.read { try CalendarMapCell.all.fetchCount($0) }
        try database.writeWithoutTransaction { try $0.checkpoint(.truncate) }
        let size = try databaseURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let result: [String: Any] = ["rows": count, "distribution": "75% repeated venues, 25% deterministic global coordinates",
            "databasePath": databaseURL.path, "databaseBytes": size, "mapCells": cells,
            "projectionSeconds": projectionSeconds, "rebuildSeconds": rebuildSeconds,
            "tileDatabaseMilliseconds": tileMilliseconds, "listMilliseconds": listMilliseconds,
            "tileGzipBytes": bytes, "tileFeatures": featureCount,
            "scope": "Synthetic scalar projection, not ingestion or browser performance"]
        let report = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try report.write(to: directory.appendingPathComponent("results.json"))
        FileHandle.standardOutput.write(report + Data("\n".utf8))
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
