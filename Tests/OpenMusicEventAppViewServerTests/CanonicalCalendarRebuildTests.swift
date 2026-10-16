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
struct CanonicalCalendarRebuildTests {

    @Test func backupCommandPreservesNativeRowsAndRefusesOverwrite() throws {
        let source = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: source)
        let uri = ATProto.URI("at://did:plc:venue/events.openmusic.event/3mrdbziccpcab")!
        let payload = Data(#"{"$type":"events.openmusic.event","name":"Native festival","createdAt":"2026-08-01T12:00:00Z","start":{"$type":"events.openmusic.defs#day","value":"2026-09-04"},"end":{"$type":"events.openmusic.defs#day","value":"2026-09-07"}}"#.utf8)
        try withDependencies { $0.defaultDatabase = source } operation: {
            _ = try store.appViewRecordIndexer(tangledWebhookConfiguration: nil).apply(
                .put(AppView.RecordVersion<Data>(collection: "events.openmusic.event",
                    uri: uri, cid: "bafy-native", value: payload, sequence: 1)),
                checkpointID: "native-rebuild")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ome-rebuild-command-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let backup = directory.appendingPathComponent("source.sqlite")
        do {
            let disk = try DatabaseQueue(path: backup.path)
            try source.backup(to: disk)
        }
        let candidate = directory.appendingPathComponent("candidate.sqlite")
        let report = try OpenMusicEventAppViewServer.rebuildCanonicalCalendar(
            fromBackup: backup, destination: candidate, now: Date(timeIntervalSince1970: 0)) { _ in }
        #expect(report.passed)
        let rebuilt = try OpenMusicEventAppViewStore(databaseURL: candidate)
        expectNoDifference(try rebuilt.event(id: uri), try store.event(id: uri))
        #expect(throws: (any Error).self) {
            try OpenMusicEventAppViewServer.rebuildCanonicalCalendar(fromBackup: backup, destination: candidate) { _ in }
        }
    }
    @Test func automaticValidationAndPreservation() throws {
        let db = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: db)
        let uri = ATProto.URI("at://did:plc:calendar/community.lexicon.calendar.event/3mrdbziccpcab")!
        let payload = Data(#"{"$type":"community.lexicon.calendar.event","name":"Music","createdAt":"2026-08-01T12:00:00Z","startsAt":"2026-09-04T00:00:00Z","locations":[{"$type":"community.lexicon.location.geo","latitude":"50.1","longitude":"-115.5"}]}"#.utf8)
        try withDependencies { $0.defaultDatabase = db } operation: {
            _ = try store.appViewRecordIndexer(tangledWebhookConfiguration: nil).apply(
                .put(AppView.RecordVersion<Data>(collection: "community.lexicon.calendar.event",
                    uri: uri, cid: "bafy-original", value: payload, sequence: 1)),
                checkpointID: "rebuild-test")
        }
        let rawBefore = try db.read { try Row.fetchAll($0, sql: "SELECT * FROM appViewIndexedRecords") }
        let report = try store.rebuildCanonicalCalendar(now: Date(timeIntervalSince1970: 0)) { _ in }
        #expect(report.passed)
        expectNoDifference(report.projected, 1)
        expectNoDifference(report.plotted, 1)
        let outcome = try db.read { try CommunityCalendarDomainOutcome.find(uri.description).fetchOne($0) }
        expectNoDifference(outcome?.validationState, "valid")
        expectNoDifference(try db.read { try Row.fetchAll($0, sql: "SELECT * FROM appViewIndexedRecords") }, rawBefore)
        _ = try OpenMusicEventAppViewStore(database: db)

        // Restored live triggers maintain the rebuilt search and map indexes.
        try withDependencies { $0.defaultDatabase = db } operation: {
            let changed = Data(String(decoding: payload, as: UTF8.self).replacingOccurrences(of: "Music", with: "Updated").utf8)
            _ = try store.appViewRecordIndexer(tangledWebhookConfiguration: nil).apply(
                .put(AppView.RecordVersion<Data>(collection: "community.lexicon.calendar.event",
                    uri: uri, cid: "bafy-new", value: changed, sequence: 2)),
                checkpointID: "rebuild-test")
        }
        expectNoDifference(try db.read { try CalendarMapEvent.all.fetchCount($0) }, 1)
        #expect(try db.read { try CalendarEventBrowseSearch.all.fetchOne($0)?.searchText.contains("Updated") } == true)

        // Rejected inputs are allowed; an invalid projected row still blocks serving.
        try db.write {
            try Event.find(uri).update { $0.name = "" }.execute($0)
        }
        let invalidReport = try store.finishCanonicalCalendarValidation { _ in }
        #expect(!invalidReport.passed)
        expectNoDifference(invalidReport.invalid, 1)
        #expect(throws: (any Error).self) { try OpenMusicEventAppViewStore(database: db) }
    }

    @Test func rejectedSourceIsAccountedForWithoutBlockingServing() throws {
        let db = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: db)
        try db.write {
            try $0.execute(sql: """
                INSERT INTO appViewIndexedRecords (uri,collection,cid,value,sequence,isDeleted)
                VALUES (?,?,?,?,1,0)
                """, arguments: ["at://did:plc:calendar/community.lexicon.calendar.event/bad",
                    "community.lexicon.calendar.event", "bafy-bad", Data(#"{"name":"No creation date"}"#.utf8)])
        }
        let report = try store.rebuildCanonicalCalendar(now: Date(timeIntervalSince1970: 0)) { _ in }
        #expect(report.passed)
        expectNoDifference(report.failed, 1)
        expectNoDifference(report.pending, 0)
        _ = try OpenMusicEventAppViewStore(database: db)
        expectNoDifference(try db.read { try Event.all.fetchCount($0) }, 0)
        expectNoDifference(try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM appViewIndexedRecords") }, 1)
    }

    @Test func interruptedBuildCannotBeServed() throws {
        enum Interrupted: Error { case requested }
        let db = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: db)
        #expect(throws: Interrupted.self) {
            try store.rebuildCanonicalCalendar(now: Date(timeIntervalSince1970: 0)) { _ in throw Interrupted.requested }
        }
        #expect(throws: (any Error).self) { try OpenMusicEventAppViewStore(database: db) }
        let report = try store.rebuildCanonicalCalendar(now: Date(timeIntervalSince1970: 0)) { _ in }
        #expect(report.passed)
    }
}
