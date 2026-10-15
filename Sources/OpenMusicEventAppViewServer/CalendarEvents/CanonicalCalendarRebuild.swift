import ATProto
import Foundation
import GRDB
import OpenMusicEventLexicon
import SQLiteData

@Table("canonicalCalendarRebuildState")
struct CanonicalCalendarRebuildState: Sendable {
    @Column(primaryKey: true) var id: Int
    var phase: String

    static func registerMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Track isolated canonical calendar rebuild") { db in
            try db.execute(sql: """
                CREATE TABLE "\(tableName)" (id INTEGER PRIMARY KEY CHECK(id=0), phase TEXT NOT NULL) STRICT;
                CREATE INDEX canonical_validation_pending ON "\(CommunityCalendarDomainOutcome.tableName)" (uri)
                WHERE state='projected' AND validationState='pending';
                """)
        }
    }
}

public struct CanonicalCalendarRebuildReport: Sendable, CustomStringConvertible {
    public var projected: Int
    public var failed: Int
    public var deleted: Int
    public var invalid: Int
    public var pending: Int
    public var plotted: Int
    public var passed: Bool { invalid == 0 && pending == 0 }
    public var description: String {
        "\(passed ? "PASSED" : "COMPLETED WITH ERRORS"): projected=\(projected), rejected=\(failed), deleted=\(deleted), invalid=\(invalid), pending=\(pending), plotted=\(plotted)"
    }
}

enum CanonicalCalendarRebuildError: Error {
    case destinationExists
    case incomplete(String)
    case preservationMismatch(String)
    case validationFailed
}

extension OpenMusicEventAppViewStore {
    func requireCompletedCanonicalRebuild() throws {
        let state = try database.read { try CanonicalCalendarRebuildState.find(0).fetchOne($0) }
        if let state, state.phase != "passed" {
            throw CanonicalCalendarRebuildError.incomplete(state.phase)
        }
    }

    func rebuildCanonicalCalendar(now: Date, progress: (String) throws -> Void) throws -> CanonicalCalendarRebuildReport {
        try database.write {
            try CanonicalCalendarRebuildState.upsert {
                CanonicalCalendarRebuildState(id: 0, phase: "building")
            }.execute($0)
        }
        try buildCanonicalCalendar(now: now, progress: progress)
        return try finishCanonicalCalendarValidation(progress: progress)
    }

    func finishCanonicalCalendarValidation(progress: (String) throws -> Void) throws -> CanonicalCalendarRebuildReport {
        var processed = 0
        while true {
            let count = try validateCommunityCalendarDomainBatch()
            guard count > 0 else { break }
            processed += count
            if processed % 1000 == 0 { try progress("validated=\(processed)") }
        }
        return try database.write { db in
            let missing = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM appViewIndexedRecords r
                LEFT JOIN "\(CommunityCalendarDomainOutcome.tableName)" o ON o.uri=r.uri
                WHERE r.collection=? AND (o.uri IS NULL OR o.cid IS NOT r.cid
                  OR o.sequence != r.sequence OR o.adapterVersion != ?
                  OR (r.isDeleted=1 AND o.state!='deleted')
                  OR (r.isDeleted=0 AND o.state='deleted'))
                """, arguments: [CommunityCalendarDomainAdapter.collection, CommunityCalendarDomainAdapter.version]) ?? 0
            guard missing == 0 else { throw CanonicalBackfillError.unreconciledRecords(missing) }
            let report = CanonicalCalendarRebuildReport(
                projected: try CommunityCalendarDomainOutcome.where { $0.state.eq("projected") }.fetchCount(db),
                failed: try CommunityCalendarDomainOutcome.where { $0.state.eq("failed") }.fetchCount(db),
                deleted: try CommunityCalendarDomainOutcome.where { $0.state.eq("deleted") }.fetchCount(db),
                invalid: try CommunityCalendarDomainOutcome.where { $0.validationState.eq("invalid") }.fetchCount(db),
                pending: try CommunityCalendarDomainOutcome.where { $0.validationState.eq("pending") }.fetchCount(db),
                plotted: try CalendarMapEvent.all.fetchCount(db))
            let domainCount = try Event.all.fetchCount(db)
            let coordinateCount = try CalendarEventBrowseProjection.where {
                $0.latitude.isNot(nil) && $0.longitude.isNot(nil)
            }.fetchCount(db)
            let spatialCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"\(CalendarEventBrowseSpatialIndex.tableName)\"") ?? 0
            let missingSearch = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM "\(CalendarEventBrowseProjection.tableName)" b
                LEFT JOIN "\(CalendarEventBrowseSearch.tableName)" s ON s.rowid=b.rowid AND s.uri=b.uri
                WHERE s.rowid IS NULL
                """) ?? 0
            guard try CalendarEventBrowseProjection.all.fetchCount(db) == domainCount,
                  try CalendarEventBrowseSearch.all.fetchCount(db) == domainCount,
                  spatialCount == coordinateCount, missingSearch == 0,
                  try String.fetchOne(db, sql: "PRAGMA quick_check") == "ok",
                  try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty else {
                throw CanonicalCalendarRebuildError.preservationMismatch("derived counts or database integrity")
            }
            try CanonicalCalendarRebuildState.upsert {
                CanonicalCalendarRebuildState(id: 0, phase: report.passed ? "passed" : "failed")
            }.execute(db)
            return report
        }
    }
}

extension OpenMusicEventAppViewServer {
    public static func validateCanonicalCalendar(
        databaseURL: URL, progress: (String) throws -> Void
    ) throws -> CanonicalCalendarRebuildReport {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CanonicalCalendarRebuildError.incomplete("candidate does not exist")
        }
        let store = try OpenMusicEventAppViewStore(rebuilding: DatabaseQueue(path: databaseURL.path))
        let phase = try store.database.read { try CanonicalCalendarRebuildState.find(0).fetchOne($0)?.phase }
        guard let phase, ["validating", "failed", "passed"].contains(phase) else {
            throw CanonicalCalendarRebuildError.incomplete(phase ?? "no rebuild")
        }
        let report = try store.finishCanonicalCalendarValidation(progress: progress)
        try progress(report.description)
        return report
    }

    public static func rebuildCanonicalCalendar(
        fromBackup sourceURL: URL, destination: URL, now: Date = .now,
        progress: (String) throws -> Void
    ) throws -> CanonicalCalendarRebuildReport {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CanonicalCalendarRebuildError.destinationExists
        }
        var sourceConfiguration = Configuration()
        sourceConfiguration.readonly = true
        // This command takes a completed backup, not a live database with outstanding WAL data.
        var components = URLComponents()
        components.scheme = "file"
        components.path = sourceURL.standardizedFileURL.path
        components.queryItems = [.init(name: "mode", value: "ro"), .init(name: "immutable", value: "1")]
        let source = try DatabaseQueue(path: components.string!, configuration: sourceConfiguration)
        guard try source.read({ try String.fetchOne($0, sql: "PRAGMA quick_check") }) == "ok" else {
            throw CanonicalCalendarRebuildError.preservationMismatch("source integrity")
        }
        let output = try DatabaseQueue(path: destination.path)
        try progress("Copying completed backup to \(destination.path)")
        try source.backup(to: output)
        let store = try OpenMusicEventAppViewStore(rebuilding: output)
        let natives = try output.read {
            try Event.where { $0.projectionVersion.is(nil) }.order(by: \.id).fetchAll($0)
        }
        let report = try store.rebuildCanonicalCalendar(now: now, progress: progress)
        try output.write {
            try CanonicalCalendarRebuildState.upsert {
                CanonicalCalendarRebuildState(id: 0, phase: "reconciling")
            }.execute($0)
        }
        try progress("Reconciling retained raw payloads and native OME rows")
        var cursor = ""
        while true {
            let rows = try source.read {
                try Row.fetchAll($0, sql: "SELECT * FROM appViewIndexedRecords WHERE uri > ? ORDER BY uri LIMIT 100", arguments: [cursor])
            }
            guard !rows.isEmpty else { break }
            let last: String = rows.last!["uri"]
            let copied = try output.read {
                try Row.fetchAll($0, sql: "SELECT * FROM appViewIndexedRecords WHERE uri > ? AND uri <= ? ORDER BY uri", arguments: [cursor, last])
            }
            guard rows == copied else { throw CanonicalCalendarRebuildError.preservationMismatch("raw payloads after \(cursor)") }
            cursor = last
        }
        let retained = try output.read {
            try Event.where { $0.projectionVersion.is(nil) }.order(by: \.id).fetchAll($0)
        }
        guard natives == retained else { throw CanonicalCalendarRebuildError.preservationMismatch("native domain rows") }
        try output.write {
            try CanonicalCalendarRebuildState.upsert {
                CanonicalCalendarRebuildState(id: 0, phase: report.passed ? "passed" : "failed")
            }.execute($0)
        }
        try progress(report.description)
        return report
    }
}
