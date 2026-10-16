import ATProto
import Foundation
import GRDB
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

struct SearchDashboardPerformanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OME_DIAGNOSTIC_DATABASE"] != nil))
    func measureInstalledDashboard() throws {
        let path = try #require(ProcessInfo.processInfo.environment["OME_DIAGNOSTIC_DATABASE"])
        var configuration = Configuration()
        configuration.readonly = true
        let database = try DatabaseQueue(path: path, configuration: configuration)
        let eventID = try #require(Event.ID("at://did:plc:a2ln7umogxgflsobz2unqfeu/events.openmusic.event/3mx6isyz5jy22"))
        let now = Date(timeIntervalSince1970: 1_791_374_400)
        try database.read { db in
            let query = PerformanceDashboardRow.all(eventID: eventID)
            let sql = query.query.debugDescription
            print("DASHBOARD_SQL \(sql)")
            print("DASHBOARD_PLAN \(try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + sql))")
            // Warm the same schema and database caches used by repeated event entry.
            let rows = try query.fetchAll(db)
            #expect(rows.count == 175)
            let stageJSONRows = try Row.fetchAll(db, sql: sql)
            let kindData = stageJSONRows.compactMap { (row: Row) -> Data? in
                let value: String? = row["kind"]
                return value.map { Data($0.utf8) }
            }
            let locatorData = stageJSONRows.compactMap { (row: Row) -> Data? in
                let value: String? = row["locators"]
                return value.map { Data($0.utf8) }
            }
            let mediaData = stageJSONRows.compactMap { (row: Row) -> Data? in
                // ProgramItem occupies columns 0...12; EventPlace.media is column 21.
                let value: String? = row[21]
                return value.map { Data($0.utf8) }
            }
            let decoder = JSONDecoder()
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let wholeSeconds = ISO8601DateFormatter()
            wholeSeconds.formatOptions = [.withInternetDateTime]
            for iteration in 0..<5 {
                func measure<T>(_ name: String, _ operation: () throws -> T) rethrows -> T {
                    let start = ProcessInfo.processInfo.systemUptime
                    let result = try operation()
                    print("DASHBOARD_METRIC \(iteration) \(name) \((ProcessInfo.processInfo.systemUptime-start)*1000)")
                    return result
                }
                let raw = try measure("raw_sql_and_row_copy") { try Row.fetchAll(db, sql: sql) }
                #expect(raw.count == rows.count)
                _ = try measure("repeated_stage_kind_json") {
                    try kindData.map { try decoder.decode(Open<EventPlace.Kind>.self, from: $0) }
                }
                _ = try measure("repeated_stage_locators_json") {
                    try locatorData.map { try decoder.decode([Open<Event.Locator>].self, from: $0) }
                }
                _ = try measure("repeated_stage_media_json") {
                    try mediaData.map { try decoder.decode([Open<OME.Media>].self, from: $0) }
                }
                _ = measure("parse_dates_reusing_formatters") {
                    rows.map { row in
                        [row.performance.startsAt, row.performance.endsAt].map { value in
                            value.flatMap { fractional.date(from: $0.rawValue) ?? wholeSeconds.date(from: $0.rawValue) }
                        }
                    }
                }
                _ = try measure("typed_joined_rows") { try query.fetchAll(db) }
                _ = try measure("typed_items_without_stage_join") {
                    try ProgramItem.where { $0.event.eq(eventID) }.fetchAll(db)
                }
                _ = try measure("typed_places") {
                    try EventPlace.where { $0.event.eq(eventID) }.fetchAll(db)
                }
                _ = try measure("dashboard_without_performances") {
                    try EventSearchDashboard.fetch(eventID: eventID, db: db)
                }
                _ = measure("parse_each_start_and_end_once") {
                    rows.map { ($0.performance.startDate, $0.performance.endDate) }
                }
                _ = try measure("whole_dashboard") {
                    try EventSearchDashboard.fetch(eventID: eventID, now: now, db: db)
                }
            }
        }
    }
}
