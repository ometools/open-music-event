import ATProto
import ATProtoAppView
import CustomDump
import Dependencies
import Foundation
import GRDB
import OpenMusicEventLexicon
import SQLiteData
import Testing
@testable import OpenMusicEventAppViewServer

@Suite(AppViewTestTime())
struct CommunityCalendarDomainPersistenceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OME_CANONICAL_BACKFILL_TEST_COPY"] != nil))
    func `isolated full sandbox backfill`() throws {
        let path = try #require(ProcessInfo.processInfo.environment["OME_CANONICAL_BACKFILL_TEST_COPY"])
        // Explicit opt-in; this is a disposable copy, never the live volume or backup.
        #expect(URL(fileURLWithPath: path).lastPathComponent.hasPrefix("canonical-validation-"))
        guard URL(fileURLWithPath: path).lastPathComponent.hasPrefix("canonical-validation-") else { return }
        let began = Date()
        let store = try OpenMusicEventAppViewStore(databaseURL: URL(fileURLWithPath: path))
        try store.database.read { db throws -> Void in
            #expect(try String.fetchOne(db, sql: "PRAGMA quick_check") == "ok")
            let counts = try Row.fetchAll(db, sql: "SELECT state, COUNT(*) AS count FROM communityCalendarDomainOutcomes GROUP BY state")
            print("Canonical backfill outcomes: \(counts); elapsed \(Date().timeIntervalSince(began)) seconds")
            let missing = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM appViewIndexedRecords r LEFT JOIN communityCalendarDomainOutcomes o ON r.uri = o.uri
                WHERE r.collection = 'community.lexicon.calendar.event' AND o.uri IS NULL
                """)
            #expect(missing == 0)
        }
    }

    private let uri = ATProto.URI("at://did:plc:calendar/community.lexicon.calendar.event/3mrdbziccpcab")!
    private let payload = Data(#"{"$type":"community.lexicon.calendar.event","name":"Midnight music","createdAt":"2026-08-01T12:00:00Z","startsAt":"2026-09-04T00:00:00Z","locations":[{"$type":"community.lexicon.location.geo","latitude":"50.1","longitude":"-115.5"}]}"#.utf8)

    @Test func `search documents migrate to stable keys and updates replace only their own document`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        try withDependencies { $0.defaultDatabase = database } operation: {
            let indexer = store.appViewRecordIndexer(tangledWebhookConfiguration: nil)
            _ = try indexer.apply(.put(AppView.RecordVersion<Data>(collection: "community.lexicon.calendar.event",
                uri: uri, cid: "bafy-original", value: payload, sequence: 1)), checkpointID: "search-keys")
            // A prior index allocated document IDs independently from browse rows.
            try database.write { db in
                try db.execute(sql: "UPDATE \"\(CalendarEventBrowseSearch.tableName)\" SET rowid = rowid + 1000")
                try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = ?",
                    arguments: ["Key browse search documents by browse rowid"])
            }
            _ = try OpenMusicEventAppViewStore(database: database)
            let originalKey = try database.read { db in
                try #require(try CalendarEventBrowseProjection.find(uri.description).select(\.rowid).fetchOne(db))
            }
            try database.read { db throws -> Void in
                let document = try #require(try CalendarEventBrowseSearch.find(originalKey).fetchOne(db))
                #expect(document.searchText.contains("Midnight music"))
                let plan = try Row.fetchAll(db, sql:
                    "EXPLAIN QUERY PLAN DELETE FROM \"\(CalendarEventBrowseSearch.tableName)\" WHERE rowid = ?",
                    arguments: [originalKey])
                #expect(plan.contains { row in
                    let detail: String = row["detail"]
                    return detail.contains("INDEX 0:=")
                })
            }
            // A real source update changes search text without changing the key.
            let updated = Data(String(decoding: payload, as: UTF8.self)
                .replacingOccurrences(of: "Midnight music", with: "Sunrise concert").utf8)
            _ = try indexer.apply(.put(AppView.RecordVersion<Data>(collection: "community.lexicon.calendar.event",
                uri: uri, cid: "bafy-updated", value: updated, sequence: 2)), checkpointID: "search-keys")
            try database.read { db throws -> Void in
                let document = try #require(try CalendarEventBrowseSearch.find(originalKey).fetchOne(db))
                #expect(document.searchText.contains("Sunrise concert"))
                #expect(!document.searchText.contains("Midnight music"))
                expectNoDifference(try CalendarEventBrowseSearch.all.fetchCount(db), 1)
            }
            _ = try indexer.apply(.delete(AppView.RecordDeletion(collection: "community.lexicon.calendar.event",
                uri: uri, sequence: 3)), checkpointID: "search-keys")
            let count = try database.read { try CalendarEventBrowseSearch.all.fetchCount($0) }
            expectNoDifference(count, 0)
        }
    }

    @Test func `production ingestion preserves content through update failure and deletion`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        try withDependencies { $0.defaultDatabase = database } operation: {
            let indexer = store.appViewRecordIndexer(tangledWebhookConfiguration: nil)
            let original = try AppView.RecordVersion<Data>(collection: "community.lexicon.calendar.event",
                uri: uri, cid: "bafy-original", value: payload, sequence: 1)
            _ = try indexer.apply(.put(original), checkpointID: "canonical-story")
            let saved = try database.read { try #require(try Event.find(uri).fetchOne($0)) }
            expectNoDifference(saved.cid, original.cid)
            expectNoDifference(saved.start, .known(.time(.init(value: "2026-09-04T00:00:00Z"))))
            #expect(saved.timeZone == nil)
            try database.read { db throws -> Void in
                let point = try #require(try CalendarEventBrowseProjection.find(uri.description).fetchOne(db))
                #expect(point.latitude == 50.1)
                #expect(point.catalog == "community.lexicon.calendar.event")
                #expect(!point.hasEventViewer)
            }

            // A malformed replacement is retained raw, but cannot invent domain content.
            let bad = Data(#"{"$type":"community.lexicon.calendar.event","name":"Bad","createdAt":{}}"#.utf8)
            _ = try indexer.apply(.put(AppView.RecordVersion<Data>(collection: original.collection,
                uri: uri, cid: "bafy-bad", value: bad, sequence: 2)), checkpointID: "canonical-story")
            try database.read { db throws -> Void in
                expectNoDifference(try Event.find(uri).fetchOne(db), saved)
                let outcome = try #require(try CommunityCalendarDomainOutcome.find(uri.description).fetchOne(db))
                #expect(outcome.state == "failed")
                #expect(outcome.cid == "bafy-bad")
                #expect(!outcome.diagnostics.isEmpty)
            }
            expectNoDifference(try AppViewIndexDatabase.record(uri: uri)?.value, bad)

            // Deleting the external record clears only its domain and derivative rows.
            _ = try indexer.apply(.delete(AppView.RecordDeletion(collection: original.collection,
                uri: uri, sequence: 3)), checkpointID: "canonical-story")
            try database.read { db throws -> Void in
                #expect(try Event.find(uri).fetchOne(db) == nil)
                #expect(try CalendarEventBrowseProjection.find(uri.description).fetchOne(db) == nil)
                #expect(try CommunityCalendarDomainOutcome.find(uri.description).fetchOne(db)?.state == "deleted")
            }
        }
    }

    @Test func `bounded backfill resumes and a second run is idempotent`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        // Prior-schema raw records have no adapter outcome. Seed only that boundary.
        try database.write { db in
            try CommunityCalendarDomainBackfill.delete().execute(db)
            for key in ["a", "b", "c"] {
                try db.execute(sql: """
                    INSERT INTO appViewIndexedRecords (uri, collection, cid, value, sequence, isDeleted)
                    VALUES (?, 'community.lexicon.calendar.event', 'bafy-original', ?, 1, 0)
                    """, arguments: ["at://did:plc:calendar/community.lexicon.calendar.event/\(key)", payload])
            }
        }
        #expect(try !store.backfillCommunityCalendarDomainBatch(limit: 1))
        #expect(try database.read { try Event.all.fetchCount($0) } == 1)
        // Reopening resumes the committed cursor instead of starting over.
        let reopened = try OpenMusicEventAppViewStore(database: database)
        #expect(try database.read { try Event.all.fetchCount($0) } == 3)
        #expect(try database.read { try CommunityCalendarDomainOutcome.all.fetchCount($0) } == 3)
        #expect(try reopened.backfillCommunityCalendarDomainBatch(limit: 1))
        #expect(try database.read { try Event.all.fetchCount($0) } == 3)
    }

    @Test func `index failure rolls back raw record canonical row and outcome`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        try database.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_browse BEFORE INSERT ON calendarEventBrowseProjections
                BEGIN SELECT RAISE(ABORT, 'test index failure'); END
                """)
        }
        try withDependencies { $0.defaultDatabase = database } operation: {
            let record = try AppView.RecordVersion<Data>(collection: "community.lexicon.calendar.event",
                uri: uri, cid: "bafy-original", value: payload, sequence: 1)
            #expect(throws: (any Error).self) {
                try store.appViewRecordIndexer(tangledWebhookConfiguration: nil)
                    .apply(.put(record), checkpointID: "rollback")
            }
            #expect(try AppViewIndexDatabase.record(uri: uri) == nil)
            try database.read { db throws -> Void in
                #expect(try Event.find(uri).fetchOne(db) == nil)
                #expect(try CommunityCalendarDomainOutcome.find(uri.description).fetchOne(db) == nil)
            }
        }
    }
}
