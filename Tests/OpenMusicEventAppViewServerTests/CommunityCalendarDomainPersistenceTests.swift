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
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OME_CANONICAL_SAMPLE_SOURCE"] != nil))
    func `bounded real record backfill benchmark`() throws {
        let path = try #require(ProcessInfo.processInfo.environment["OME_CANONICAL_SAMPLE_SOURCE"])
        let sampleLimit = Int(ProcessInfo.processInfo.environment["OME_CANONICAL_SAMPLE_LIMIT"] ?? "1000") ?? 1000
        try #require((1...10_000).contains(sampleLimit))
        var configuration = Configuration()
        configuration.readonly = true
        // This opt-in source must be a completed backup, never an actively written database.
        let source = try DatabaseQueue(path: "file:\(path)?mode=ro&immutable=1", configuration: configuration)
        // Spread the sample across the URI range, then include large payloads and tombstones.
        // Selection is outside the timed ingestion path and never writes to the source database.
        let records = try source.read { db in
            try Row.fetchAll(db, sql: """
                WITH numbered AS (
                  SELECT uri, ROW_NUMBER() OVER (ORDER BY uri) AS ordinal,
                    COUNT(*) OVER () AS total
                  FROM appViewIndexedRecords WHERE collection = 'community.lexicon.calendar.event'
                ), sampled AS (
                  SELECT uri FROM numbered WHERE (ordinal-1) % MAX(1, (total+?-1)/?) = 0
                ), largest AS (
                  SELECT uri FROM appViewIndexedRecords
                  WHERE collection = 'community.lexicon.calendar.event' AND isDeleted = 0
                  ORDER BY length(value) DESC, uri LIMIT 25
                ), deleted AS (
                  SELECT uri FROM appViewIndexedRecords
                  WHERE collection = 'community.lexicon.calendar.event' AND isDeleted = 1
                  ORDER BY uri LIMIT 25
                )
                SELECT uri, collection, cid, value, sequence, isDeleted FROM appViewIndexedRecords
                WHERE uri IN (SELECT uri FROM sampled UNION SELECT uri FROM largest UNION SELECT uri FROM deleted)
                ORDER BY uri
                """, arguments: [sampleLimit, sampleLimit])
        }
        #expect(!records.isEmpty && records.count <= sampleLimit + 50)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ome-canonical-sample-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try DatabaseQueue(path: directory.appendingPathComponent("sample.sqlite").path)
        let store = try OpenMusicEventAppViewStore(database: database)
        try database.write { db in
            try CommunityCalendarDomainBackfill.delete().execute(db)
            for record in records {
                try db.execute(sql: """
                    INSERT INTO appViewIndexedRecords (uri, collection, cid, value, sequence, isDeleted)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: StatementArguments(record.databaseValues))
            }
        }
        let clock = ContinuousClock()
        let initial = try clock.measure {
            while try !store.backfillCommunityCalendarDomainBatch(limit: 100) {}
        }
        let events = try database.read { try Event.all.fetchCount($0) }
        let revisions = try database.read { try CalendarMapRevision.order(by: \.id).select(\.revision).fetchAll($0) }
        try database.write { db in
            try CommunityCalendarDomainBackfill.delete().execute(db)
            try db.execute(sql: """
                CREATE TEMP TRIGGER reject_sample_replay BEFORE INSERT ON "\(Event.tableName)"
                BEGIN SELECT RAISE(ABORT, 'unchanged sample rewrote domain content'); END;
                """)
        }
        let replay = try clock.measure {
            while try !store.backfillCommunityCalendarDomainBatch(limit: 100) {}
        }
        let cells = try database.read { try CalendarMapCell.order(by: \.id).fetchAll($0) }
        // An adapter upgrade must reproject real content against populated indexes, not skip it.
        try database.write { db in
            try db.execute(sql: "DROP TRIGGER reject_sample_replay")
            try CommunityCalendarDomainBackfill.delete().execute(db)
            try CommunityCalendarDomainOutcome.update { $0.adapterVersion = -1 }.execute(db)
        }
        let rebuild = try clock.measure {
            while try !store.backfillCommunityCalendarDomainBatch(limit: 100) {}
        }
        let freshDatabase = try DatabaseQueue(path: directory.appendingPathComponent("fresh.sqlite").path)
        let freshStore = try OpenMusicEventAppViewStore(rebuilding: freshDatabase)
        let fresh = try clock.measure {
            try freshBuild(records: records, database: freshDatabase)
        }
        let validation = try clock.measure {
            while try freshStore.validateCommunityCalendarDomainBatch() > 0 {}
        }
        let invalid = try freshDatabase.read {
            try CommunityCalendarDomainOutcome.where { $0.validationState.eq("invalid") }.fetchCount($0)
        }
        #expect(invalid == 0)
        let expectedEvents = try database.read { try Event.order(by: \.id).fetchAll($0) }
        let rebuiltEvents = try freshDatabase.read { try Event.order(by: \.id).fetchAll($0) }
        expectNoDifference(rebuiltEvents, expectedEvents)
        let expectedSearch = try database.read { try CalendarEventBrowseSearch.order(by: \.uri).select { ($0.uri, $0.searchText) }.fetchAll($0) }
        let rebuiltSearch = try freshDatabase.read { try CalendarEventBrowseSearch.order(by: \.uri).select { ($0.uri, $0.searchText) }.fetchAll($0) }
        expectNoDifference(rebuiltSearch.map(\.0), expectedSearch.map(\.0))
        expectNoDifference(rebuiltSearch.map(\.1), expectedSearch.map(\.1))
        let rebuiltCells = try freshDatabase.read { try CalendarMapCell.order(by: \.id).fetchAll($0) }
        #expect(rebuiltCells.count == cells.count)
        for (actual, expected) in zip(rebuiltCells, cells) {
            #expect(actual.id == expected.id && actual.count == expected.count && actual.activeCount == expected.activeCount)
            #expect(abs(actual.x - expected.x) < 0.00000001 && abs(actual.y - expected.y) < 0.00000001)
        }
        let expectedOutcomes = try database.read { try CommunityCalendarDomainOutcome.order(by: \.uri).fetchAll($0) }
        let rebuiltOutcomes = try freshDatabase.read { try CommunityCalendarDomainOutcome.order(by: \.uri).fetchAll($0) }
        for (actual, expected) in zip(rebuiltOutcomes, expectedOutcomes) {
            #expect(actual.uri == expected.uri && actual.cid == expected.cid && actual.state == expected.state)
        }
        #expect(rebuiltOutcomes.count == expectedOutcomes.count)
        // Serving queries use the same compact rows and indexed search after the bulk build.
        let query = CalendarBrowseQuery.Parameters(catalogs: [ATProto.NSID(CommunityCalendarDomainAdapter.collection)], query: "music", limit: 50)
        expectNoDifference(try freshStore.browseEventSummaries(query).events.map(\.uri), try store.browseEventSummaries(query).events.map(\.uri))
        print("Fresh canonical sample: records=\(records.count), fresh=\(fresh), validation=\(validation), invalid=\(invalid), incrementalInitial=\(initial), incrementalRebuild=\(rebuild)")
        try database.read { db throws -> Void in
            #expect(try CommunityCalendarDomainOutcome.all.fetchCount(db) == records.count)
            expectNoDifference(try Event.all.fetchCount(db), events)
            expectNoDifference(try CalendarMapRevision.order(by: \.id).select(\.revision).fetchAll(db), revisions)
            expectNoDifference(try CalendarMapCell.order(by: \.id).fetchAll(db), cells)
            #expect(try CommunityCalendarDomainOutcome.where { $0.adapterVersion.eq(-1) }.fetchCount(db) == 0)
            let preserved = try Row.fetchAll(db, sql: "SELECT uri, collection, cid, value, sequence, isDeleted FROM appViewIndexedRecords ORDER BY uri")
            #expect(preserved == records)
            #expect(try String.fetchOne(db, sql: "PRAGMA quick_check") == "ok")
            let outcomes = try Row.fetchAll(db, sql: "SELECT state, COUNT(*) AS count FROM communityCalendarDomainOutcomes GROUP BY state")
            let plotted = try CalendarMapEvent.all.fetchCount(db)
            print("Real canonical sample: records=\(records.count), events=\(events), plotted=\(plotted), outcomes=\(outcomes), initial=\(initial), replay=\(replay), rebuild=\(rebuild), database=\(directory.path)")
        }
    }

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
            #expect(try database.read { try CommunityCalendarDomainOutcome.find(uri.description).fetchOne($0)?.validationState } == "pending")
            #expect(try store.validateCommunityCalendarDomainBatch(limit: 1) == 1)
            #expect(try store.validateCommunityCalendarDomainBatch(limit: 1) == 0)
            #expect(try database.read { try CommunityCalendarDomainOutcome.find(uri.description).fetchOne($0)?.validationState } == "valid")
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

    @Test(arguments: [false, true])
    func `deferred validation records a semantic failure without deleting source content`(nested: Bool) throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        try withDependencies { $0.defaultDatabase = database } operation: {
            let record = try AppView.RecordVersion<Data>(collection: "community.lexicon.calendar.event",
                uri: uri, cid: "bafy-original", value: payload, sequence: 1)
            _ = try store.appViewRecordIndexer(tangledWebhookConfiguration: nil).apply(.put(record), checkpointID: "validation")
            // Simulate a structurally decodable but semantically invalid derived row.
            try database.write { db in
                if nested {
                    try Event.find(uri).update {
                        $0.locations = #bind([Event.Location(name: "", links: [
                            OME.Link(url: URL(string: "https://example.com/venue")!, title: "")
                        ])])
                    }.execute(db)
                } else {
                    try Event.find(uri).update { $0.name = "" }.execute(db)
                }
            }
            #expect(try store.validateCommunityCalendarDomainBatch(limit: 1) == 1)
            try database.read { db throws -> Void in
                let outcome = try #require(try CommunityCalendarDomainOutcome.find(uri.description).fetchOne(db))
                #expect(outcome.validationState == "invalid")
                #expect(outcome.validationError?.isEmpty == false)
                #expect(try Event.find(uri).fetchCount(db) == 1)
            }
            expectNoDifference(try AppViewIndexDatabase.record(uri: uri)?.value, payload)
            // A later source revision must be validated anew, not inherit the previous result.
            _ = try store.appViewRecordIndexer(tangledWebhookConfiguration: nil).apply(.put(
                AppView.RecordVersion<Data>(collection: record.collection, uri: uri, cid: "bafy-new", value: payload, sequence: 2)), checkpointID: "validation")
            #expect(try database.read { try CommunityCalendarDomainOutcome.find(uri.description).fetchOne($0)?.validationState } == "pending")
        }
    }

    @Test func `small mixed backfill reconciles and unchanged replay avoids domain writes`() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        // A bounded prior-schema dataset includes located, unlocated, invalid, and deleted records.
        try database.write { db in
            try CommunityCalendarDomainBackfill.delete().execute(db)
            for number in 0..<120 {
                let kind = number % 4
                let value = kind == 1
                    ? Data(#"{"$type":"community.lexicon.calendar.event","name":"Unlocated music","createdAt":"2026-08-01T12:00:00Z"}"#.utf8)
                    : kind == 2 ? Data(#"{"name":"Invalid creation","createdAt":{}}"#.utf8) : payload
                try db.execute(sql: """
                    INSERT INTO appViewIndexedRecords (uri, collection, cid, value, sequence, isDeleted)
                    VALUES (?, 'community.lexicon.calendar.event', ?, ?, 1, ?)
                    """, arguments: ["at://did:plc:calendar/community.lexicon.calendar.event/sample-\(number)",
                        kind == 3 ? nil : "bafy-original", kind == 3 ? nil : value, kind == 3])
            }
        }
        let clock = ContinuousClock()
        let initial = try clock.measure {
            while try !store.backfillCommunityCalendarDomainBatch(limit: 10) {}
        }
        try database.read { db throws -> Void in
            #expect(try Event.all.fetchCount(db) == 60)
            #expect(try CommunityCalendarDomainOutcome.all.fetchCount(db) == 120)
            #expect(try CommunityCalendarDomainOutcome.where { $0.state.eq("failed") }.fetchCount(db) == 30)
            #expect(try CommunityCalendarDomainOutcome.where { $0.state.eq("deleted") }.fetchCount(db) == 30)
            #expect(try CalendarMapEvent.all.fetchCount(db) == 30)
        }

        // Restart the scan, not just the completed checkpoint. No unchanged event may be written.
        try database.write { db in
            try CommunityCalendarDomainBackfill.delete().execute(db)
            try db.execute(sql: """
                CREATE TEMP TRIGGER reject_replay_insert BEFORE INSERT ON "\(Event.tableName)"
                BEGIN SELECT RAISE(ABORT, 'unchanged replay wrote canonical event'); END;
                CREATE TEMP TRIGGER reject_replay_update BEFORE UPDATE ON "\(Event.tableName)"
                BEGIN SELECT RAISE(ABORT, 'unchanged replay updated canonical event'); END;
                """)
        }
        let replay = try clock.measure {
            while try !store.backfillCommunityCalendarDomainBatch(limit: 10) {}
        }
        try database.read { db throws -> Void in
            #expect(try Event.all.fetchCount(db) == 60)
            #expect(try CommunityCalendarDomainOutcome.all.fetchCount(db) == 120)
        }
        print("Bounded canonical backfill: 120 records, initial=\(initial), unchanged rescan=\(replay)")
    }
}
