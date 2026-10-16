import ATProto
import ATProtoAppView
import Foundation
import GRDB
import OpenMusicEventLexicon
import SQLiteData


extension OpenMusicEventAppViewStore {
    func buildCanonicalCalendar(now: Date, progress: (String) throws -> Void) throws {
        try database.write { db in
            let clock = ContinuousClock()
            let started = clock.now
            let triggers = try Row.fetchAll(db, sql: """
                SELECT name, sql FROM sqlite_master WHERE type='trigger' AND tbl_name IN (?, ?)
                """, arguments: [CalendarEventBrowseProjection.tableName, CalendarMapEvent.tableName])
            for trigger in triggers {
                let name: String = trigger["name"]
                try db.execute(sql: "DROP TRIGGER \"\(name.replacingOccurrences(of: "\"", with: "\"\""))\"")
            }
            try CalendarMapEvent.delete().execute(db)
            try CalendarMapCell.delete().execute(db)
            try CalendarPublisherMapCell.delete().execute(db)
            try CalendarMapRevision.delete().execute(db)
            try CalendarPublisherEvent.delete().execute(db)
            try CalendarEventBrowseProjection.delete().execute(db)
            try db.execute(sql: "DELETE FROM \"\(CalendarEventBrowseSearch.tableName)\"")
            try db.execute(sql: "DELETE FROM \"\(CalendarEventBrowseSpatialIndex.tableName)\"")
            try Event.where { $0.projectionVersion.isNot(nil) }.delete().execute(db)
            try CommunityCalendarEventProjection.delete().execute(db)
            try CommunityCalendarDomainOutcome.delete().execute(db)
            try CommunityCalendarDomainBackfill.delete().execute(db)
            try db.execute(sql: "CREATE TEMP TABLE \"\(CalendarEventBrowseSearchStage.tableName)\" (rowid INTEGER PRIMARY KEY, uri TEXT NOT NULL, searchText TEXT NOT NULL)")

            var rawCursor = ""
            var processed = 0
            while true {
                let records = try Row.fetchAll(db, sql: """
                    SELECT uri, cid, value, sequence, isDeleted FROM appViewIndexedRecords
                    WHERE collection = ? AND uri > ? ORDER BY uri LIMIT 100
                    """, arguments: [CommunityCalendarDomainAdapter.collection, rawCursor])
                guard !records.isEmpty else { break }
                for row in records {
                let text: String = row["uri"]
                guard let uri = ATProto.URI(text) else { throw CanonicalBackfillError.corruptRawRecord(text) }
                let sequence: Int64 = row["sequence"]
                let deleted: Bool = row["isDeleted"]
                if deleted {
                    try CommunityCalendarEventProjection.deleteCanonical(uri: uri, sequence: sequence, in: db)
                } else {
                    let cid: String = row["cid"]
                    let value: Data = row["value"]
                    let record = try AppView.RecordVersion<Data>(collection: ATProto.NSID(CommunityCalendarDomainAdapter.collection),
                        uri: uri, cid: ATProto.CID(rawValue: cid), value: value, sequence: sequence)
                    try CommunityCalendarEventProjection.ingestCanonical(record, updateBrowseProjection: false, in: db)
                }
            }

                rawCursor = records.last!["uri"]
                processed += records.count
                if processed % 1000 == 0 { try progress("canonical rows processed=\(processed)") }
            }
            try CommunityCalendarDomainBackfill.upsert {
                CommunityCalendarDomainBackfill(version: CommunityCalendarDomainAdapter.version, cursor: rawCursor, complete: true)
            }.execute(db)
            let domainFinished = clock.now
            // Read canonical rows in bounded pages and stage search documents without indexing them.
            var eventCursor: Event.ID?
            var browseCount = 0
            while true {
                let rows: [Event]
                if let eventCursor {
                    rows = try Event.where { $0.id > eventCursor }.order(by: \.id).limit(100).fetchAll(db)
                } else {
                    rows = try Event.order(by: \.id).limit(100).fetchAll(db)
                }
                guard !rows.isEmpty else { break }
                for event in rows {
                    try CalendarEventBrowseProjection.upsertCanonicalEvent(event, stageIndexes: true, in: db)
                }
                eventCursor = rows.last!.id
                browseCount += rows.count
                if browseCount % 1000 == 0 { try progress("browse rows built=\(browseCount)") }
            }
            let browseFinished = clock.now
            try db.execute(sql: """
                INSERT INTO "\(CalendarEventBrowseSearch.tableName)" (rowid,uri,searchText)
                SELECT rowid,uri,searchText FROM "\(CalendarEventBrowseSearchStage.tableName)";
                INSERT INTO "\(CalendarEventBrowseSpatialIndex.tableName)"
                SELECT rowid,latitude,latitude,longitude,longitude
                FROM "\(CalendarEventBrowseProjection.tableName)" WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
                INSERT OR IGNORE INTO "\(CalendarPublisher.tableName)" (did)
                SELECT DISTINCT substr(uri,6,instr(substr(uri,6),'/')-1)
                FROM "\(CalendarEventBrowseProjection.tableName)" WHERE catalog='community.lexicon.calendar.event';
                INSERT INTO "\(CalendarPublisherEvent.tableName)" (uri,publisherID)
                SELECT b.uri,p.id FROM "\(CalendarEventBrowseProjection.tableName)" b
                JOIN "\(CalendarPublisher.tableName)" p ON p.did=substr(b.uri,6,instr(substr(b.uri,6),'/')-1)
                WHERE b.catalog='community.lexicon.calendar.event';
                """)
            let generation = (try CalendarMapBuild.find(0).select(\.active).fetchOne(db) ?? 0) + 1
            var cursor = ""
            var mapCount = 0
            while true {
                let rows = try CalendarEventBrowseProjection.where { $0.uri > cursor }.order(by: \.uri).limit(100).fetchAll(db)
                guard !rows.isEmpty else { break }
                for row in rows {
                    if let point = CalendarMapEvent.project(row, generation: generation, now: now) {
                        try CalendarMapEvent.insert { point }.execute(db)
                    }
                }
                cursor = rows.last!.uri
                mapCount += rows.count
                if mapCount % 1000 == 0 { try progress("map rows examined=\(mapCount)") }
            }
            // Each aggregate is constructed once instead of updated once per event per zoom level.
            try db.execute(sql: """
                INSERT INTO "\(CalendarMapCell.tableName)"
                SELECT p.generation||'|'||substr(p.cell,1,l.depth)||'|'||p.catalog,
                  p.generation,l.depth,substr(p.cell,1,l.depth),p.catalog,COUNT(*),SUM(p.active),
                  SUM(p.x),SUM(p.y),SUM(p.x*p.active),SUM(p.y*p.active)
                FROM "\(CalendarMapEvent.tableName)" p CROSS JOIN calendarMapLevels l
                GROUP BY p.generation,l.depth,substr(p.cell,1,l.depth),p.catalog;
                INSERT INTO "\(CalendarPublisherMapCell.tableName)"
                SELECT p.generation||'|'||substr(p.cell,1,l.depth)||'|'||e.publisherID,
                  p.generation,l.depth,substr(p.cell,1,l.depth),e.publisherID,COUNT(*),SUM(p.active),
                  SUM(p.x),SUM(p.y),SUM(p.x*p.active),SUM(p.y*p.active)
                FROM "\(CalendarMapEvent.tableName)" p CROSS JOIN calendarMapLevels l
                JOIN "\(CalendarPublisherEvent.tableName)" e ON e.uri=p.uri
                GROUP BY p.generation,l.depth,substr(p.cell,1,l.depth),e.publisherID;
                INSERT INTO "\(CalendarMapRevision.tableName)" (id,revision)
                SELECT DISTINCT p.generation||'|'||substr(p.cell,1,l.depth-3)||'|'||p.catalog,1
                FROM "\(CalendarMapEvent.tableName)" p CROSS JOIN calendarMapLevels l;
                DROP TABLE "\(CalendarEventBrowseSearchStage.tableName)";
                """)
            for trigger in triggers {
                let sql: String = trigger["sql"]
                try db.execute(sql: sql)
            }
            try CalendarMapBuild.upsert {
                CalendarMapBuild(id: 0, active: generation, building: nil, afterURI: nil, retiring: generation)
            }.execute(db)
            try CanonicalCalendarRebuildState.upsert {
                CanonicalCalendarRebuildState(id: 0, phase: "validating")
            }.execute(db)
            try progress("Fresh build phases: canonical=\(started.duration(to: domainFinished)), browse=\(domainFinished.duration(to: browseFinished)), indexes=\(browseFinished.duration(to: clock.now))")
        }
    }
}
