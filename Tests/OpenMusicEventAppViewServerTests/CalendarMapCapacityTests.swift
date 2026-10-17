import ATProto
import Foundation
import SQLiteData
import Testing

@testable import OpenMusicEventAppViewServer

@Suite struct CalendarMapCapacityTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OME_GLOBE_HTTP_FIXTURE_COUNT"] != nil))
    func `prepare a restartable synthetic domain fixture for HTTP request stress`() async throws {
        let count = Int(ProcessInfo.processInfo.environment["OME_GLOBE_HTTP_FIXTURE_COUNT"] ?? "") ?? 10_000
        try #require((1...100_000).contains(count))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ome-http-stress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("fixture.sqlite")
        let database = try DatabasePool(path: databaseURL.path)
        let store = try OpenMusicEventAppViewStore(rebuilding: database)
        try await database.write { db in
            for index in 1...count {
                let latitude = index % 4 == 0 ? Double(index * 104729 % 160000) / 1000 - 80 : 30 + Double(index % 300) / 20
                let longitude = index % 4 == 0 ? Double(index * 7919 % 360000) / 1000 - 180 : -120 + Double(index % 300) / 10
                let uri = String(format: "at://did:plc:capacity/community.lexicon.calendar.event/%010d", index)
                let payload = try JSONSerialization.data(withJSONObject: [
                    "$type": "community.lexicon.calendar.event", "name": "Capacity event \(index)",
                    "createdAt": "2026-01-01T00:00:00Z", "startsAt": "2028-01-01T00:00:00Z",
                    "locations": [["$type": "community.lexicon.location.geo", "latitude": String(latitude), "longitude": String(longitude)]]
                ])
                try #sql("""
                    INSERT INTO appViewIndexedRecords (uri, collection, cid, value, sequence, isDeleted)
                    VALUES (\(uri), 'community.lexicon.calendar.event', 'bafy-synthetic-capacity', \(payload), \(index), 0)
                    """).execute(db)
            }
        }
        _ = try store.rebuildCanonicalCalendar(now: Date(timeIntervalSince1970: 1_800_000_000)) { print($0) }
        // Exercise normal startup too: a scalar-only projection fixture would
        // be discarded when its canonical source count does not match.
        let reopened = try OpenMusicEventAppViewStore(database: database)
        let projected = try await database.read { try CalendarEventBrowseProjection.all.fetchCount($0) }
        #expect(projected == count)
        let page = try await reopened.browseEventSummaries(.init(catalogs: [ATProto.NSID("community.lexicon.calendar.event")], dates: "all"))
        #expect(page.events.count == min(50, count))
        try await database.writeWithoutTransaction { try $0.checkpoint(.truncate) }
        print("HTTP fixture: rows=\(projected), database=\(databaseURL.path)")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OME_GLOBE_BENCHMARK_COUNT"] != nil))
    func `measure synthetic projection capacity separately from browser performance`() async throws {
        let count = Int(ProcessInfo.processInfo.environment["OME_GLOBE_BENCHMARK_COUNT"] ?? "") ?? 100_000
        guard (1...10_000_000).contains(count) else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ome-map-capacity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("capacity.sqlite")
        let database = try DatabasePool(path: databaseURL.path)
        let store = try OpenMusicEventAppViewStore(database: database)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let started = ContinuousClock.now
        try await database.write { db in
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
            let tile = try await store.mapTile(.init(z: 0, x: 0, y: 0, catalogs: catalogs, dates: "current"), generation: 2)
            tileMilliseconds.append(tile.databaseMilliseconds)
            bytes = tile.gzip.count; featureCount = tile.featureCount
            let start = ContinuousClock.now
            let page = try await store.browseEventSummaries(.init(catalogs: catalogs), now: now)
            #expect(page.events.count == min(50, count))
            listMilliseconds.append(start.duration(to: .now).seconds * 1000)
        }
        let cells = try await database.read { try CalendarMapCell.all.fetchCount($0) }
        try await database.writeWithoutTransaction { try $0.checkpoint(.truncate) }
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
