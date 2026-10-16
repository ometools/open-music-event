import ATProto
import ATProtoSQLite
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData

/// Import provenance and protocol identity are local bookkeeping, never public Event fields.
@Table("canonicalSourceEventIdentities")
public struct CanonicalSourceEventIdentity: Equatable, Sendable, Identifiable {
    public let id: Event.ID
    public let source: String
    public let directory: String
    public let publisher: DID
    public let createdAt: ATProto.DateTime
}

public enum CanonicalSourceEventImport {
    /// Imports only the Event surface. Existing canonical edits and identities are never replaced.
    /// The caller may supply a publisher DID without signing in; no network writes occur here.
    public static func insert(
        _ validated: OpenMusicEventSourceValidationResult,
        at date: Date,
        in database: any DatabaseWriter
    ) async throws -> [Event.ID] {
        try await database.write { db in
            var previousKey = try Event.all.fetchAll(db).map(\.id).compactMap(\.rkey)
                .max { $0.rawValue < $1.rawValue }
            var imported: [Event.ID] = []
            for provenance in validated.insertion.eventSourceProvenances.sorted(by: {
                $0.sourceEventDirectory < $1.sourceEventDirectory
            }) {
                guard let draft = validated.insertion.events.first(where: { $0.id == provenance.eventID }) else {
                    throw ValidationError("A source Event is missing its import provenance")
                }
                let source = provenance.source.reference
                let directory = provenance.sourceEventDirectory
                let publisher = validated.organizerID
                let existing = try CanonicalSourceEventIdentity.where {
                    $0.source.eq(source) && $0.directory.eq(directory) && $0.publisher.eq(publisher)
                }.fetchOne(db)
                let identity: CanonicalSourceEventIdentity
                if let existing {
                    identity = existing
                } else {
                    let id = try CanonicalRecordID.next(
                        collection: Event.lexiconID, in: .did(publisher), at: date, after: previousKey
                    )
                    previousKey = id.rkey
                    identity = CanonicalSourceEventIdentity(
                        id: id, source: source, directory: directory, publisher: publisher,
                        createdAt: ATProto.DateTime(rawValue: ISO8601DateFormatter().string(from: date))
                    )
                    try CanonicalSourceEventIdentity.insert { identity }.execute(db)
                }
                if try Event.find(identity.id).fetchOne(db) == nil {
                    let legacy = try JSONDecoder().decode(OME.Event.self, from: JSONEncoder().encode(draft))
                    let event = try Event(id: identity.id, event: legacy, createdAt: identity.createdAt)
                    try EventRecordGraph(event: event).upsert(in: db)
                }
                try InstalledEvent.upsert { InstalledEvent(id: identity.id) }.execute(db)
                imported.append(identity.id)
            }
            guard !imported.isEmpty else { throw ValidationError("The source contains no Events") }
            return imported
        }
    }
}
