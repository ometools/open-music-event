import ATProto
import ATProtoAppView
import Foundation
import GRDB
import OpenMusicEventLexicon
import SQLiteData

/// Processing metadata, never publication identity or a substitute domain model.
@Table("communityCalendarDomainOutcomes")
struct CommunityCalendarDomainOutcome: Equatable, Sendable {
    @Column(primaryKey: true) var uri: String
    var cid: String?
    var sequence: Int64
    var adapterVersion: Int
    var state: String
    var diagnostics: Data

    static func registerMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Track canonical Community Calendar adaptation") { db in
            try db.execute(sql: """
                CREATE TABLE communityCalendarDomainOutcomes (
                  uri TEXT PRIMARY KEY NOT NULL, cid TEXT, sequence INTEGER NOT NULL,
                  adapterVersion INTEGER NOT NULL,
                  state TEXT NOT NULL CHECK (state IN ('projected', 'failed', 'deleted')),
                  diagnostics BLOB NOT NULL
                ) STRICT;
                CREATE TABLE communityCalendarDomainBackfill (
                  version INTEGER PRIMARY KEY NOT NULL, cursor TEXT NOT NULL,
                  complete INTEGER NOT NULL
                ) STRICT;
                """)
        }
    }

    static func save(uri: String, cid: String?, sequence: Int64, state: String,
                     diagnostics: [CommunityCalendarDomainAdapter.Diagnostic], in db: Database) throws {
        let encoded = try JSONEncoder().encode(diagnostics)
        try Self.upsert {
            Self(uri: uri, cid: cid, sequence: sequence,
                 adapterVersion: CommunityCalendarDomainAdapter.version,
                 state: state, diagnostics: encoded)
        }.execute(db)
    }
}

extension CommunityCalendarEventProjection {
    /// Called inside the indexer's transaction. Only adapter errors become
    /// diagnostics; persistence/index failures propagate and roll back ingestion.
    static func ingestCanonical(_ current: AppView.RecordVersion<Data>,
                                updateBrowseProjection: Bool = true, in db: Database) throws {
        let projection: CommunityCalendarDomainAdapter.Projection
        do {
            projection = try CommunityCalendarDomainAdapter.project(current)
        } catch {
            try CommunityCalendarDomainOutcome.save(
                uri: current.uri.description, cid: current.cid.rawValue, sequence: current.sequence,
                state: "failed", diagnostics: [.init(path: "$", message: String(describing: error))], in: db)
            if try Event.find(current.uri).fetchOne(db) == nil {
                try Self.find(current.uri.description).delete().execute(db)
                if updateBrowseProjection {
                    try CalendarEventBrowseProjection.delete(uri: current.uri.description, in: db)
                }
            }
            // A malformed update must not replace the last valid domain content.
            return
        }
        try Event.upsert { projection.event }.execute(db)
        // Temporary response cache, derived only from canonical content. Removed
        // with the calendar API cutover; it is no longer an ingestion authority.
        let response = try OME.CalendarEvent(event: projection.event, profile: nil)
        guard let createdAt = response.createdAt else {
            throw CanonicalBackfillError.invalidCreationDate(current.uri.description)
        }
        let encoded = try JSONEncoder().encode(response)
        try Self.upsert {
            Self(uri: current.uri.description, cid: current.cid.rawValue,
                 startsAt: response.startsAt, createdAt: createdAt,
                 sequence: current.sequence, event: encoded)
        }.execute(db)
        if updateBrowseProjection {
            try CalendarEventBrowseProjection.upsertCanonicalEvent(projection.event, in: db)
        }
        try CommunityCalendarDomainOutcome.save(
            uri: current.uri.description, cid: current.cid.rawValue, sequence: current.sequence,
            state: "projected", diagnostics: projection.diagnostics, in: db)
    }

    static func deleteCanonical(uri: ATProto.URI, sequence: Int64, in db: Database) throws {
        guard uri.collection?.rawValue == CommunityCalendarDomainAdapter.collection else {
            throw CanonicalBackfillError.unexpectedCollection(uri.description)
        }
        try Event.find(uri).where { $0.projectionVersion.isNot(nil) }.delete().execute(db)
        try Self.find(uri.description).delete().execute(db)
        try CalendarEventBrowseProjection.delete(uri: uri.description, in: db)
        try CommunityCalendarDomainOutcome.save(uri: uri.description, cid: nil,
            sequence: sequence, state: "deleted", diagnostics: [], in: db)
    }
}

@Table("communityCalendarDomainBackfill")
struct CommunityCalendarDomainBackfill: Equatable, Sendable {
    @Column(primaryKey: true) var version: Int
    var cursor: String
    var complete: Bool
}

enum CanonicalBackfillError: Error {
    case invalidCreationDate(String)
    case unexpectedCollection(String)
    case corruptRawRecord(String)
    case unreconciledRecords(Int)
}

extension OpenMusicEventAppViewStore {
    /// Each call commits one bounded batch and its checkpoint together. A new
    /// adapter version gets a fresh scan; live ingestion uses the same adapter.
    @discardableResult
    func backfillCommunityCalendarDomainBatch(limit: Int = 100) throws -> Bool {
        precondition(limit > 0 && limit <= 1_000)
        return try database.write { db in
            let version = CommunityCalendarDomainAdapter.version
            var checkpoint = try CommunityCalendarDomainBackfill.find(version).fetchOne(db)
                ?? .init(version: version, cursor: "", complete: false)
            if checkpoint.complete { return true }
            // The upstream raw-store row type is internal and its public API has
            // no cursor. Keep this bounded infrastructure query isolated here.
            let rows = try Row.fetchAll(db, sql: """
                SELECT uri, cid, value, sequence, isDeleted FROM appViewIndexedRecords
                WHERE collection = ? AND uri > ? ORDER BY uri LIMIT ?
                """, arguments: [CommunityCalendarDomainAdapter.collection, checkpoint.cursor, limit])
            for row in rows {
                let text: String = row["uri"]
                guard let uri = ATProto.URI(text) else { throw CanonicalBackfillError.corruptRawRecord(text) }
                let sequence: Int64 = row["sequence"]
                let cid: String? = row["cid"]
                let deleted: Bool = row["isDeleted"]
                let existing = try CommunityCalendarDomainOutcome.find(text).fetchOne(db)
                if existing?.adapterVersion != version || existing?.sequence != sequence || existing?.cid != cid {
                    if deleted {
                        try CommunityCalendarEventProjection.deleteCanonical(uri: uri, sequence: sequence, in: db)
                    } else {
                        guard let cid, let value: Data = row["value"] else {
                            throw CanonicalBackfillError.corruptRawRecord(text)
                        }
                        let record = try AppView.RecordVersion<Data>(
                            collection: ATProto.NSID(CommunityCalendarDomainAdapter.collection),
                            uri: uri, cid: ATProto.CID(rawValue: cid), value: value, sequence: sequence)
                        try CommunityCalendarEventProjection.ingestCanonical(record, in: db)
                    }
                }
                checkpoint.cursor = text
            }
            checkpoint.complete = rows.count < limit
            if checkpoint.complete {
                let missing = try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM appViewIndexedRecords r
                    LEFT JOIN communityCalendarDomainOutcomes o ON o.uri = r.uri
                    WHERE r.collection = ? AND
                      (o.uri IS NULL OR o.adapterVersion != ? OR o.sequence != r.sequence
                       OR o.cid IS NOT r.cid OR (r.isDeleted = 1 AND o.state != 'deleted')
                       OR (r.isDeleted = 0 AND o.state = 'deleted'))
                    """, arguments: [CommunityCalendarDomainAdapter.collection, version]) ?? 0
                guard missing == 0 else { throw CanonicalBackfillError.unreconciledRecords(missing) }
            }
            try CommunityCalendarDomainBackfill.upsert { checkpoint }.execute(db)
            return checkpoint.complete
        }
    }
}
