import ATProto
import ATProtoAppView
import ATProtoTypes
import Foundation
import OpenMusicEventLexicon
import SQLiteData

extension OpenMusicEventAppViewStore {
    func appViewRecordIndexer(
        tangledWebhookConfiguration: TangledWebhookConfiguration?
    ) -> AppViewRecordIndexer {
        AppViewRecordIndexer {
            eventRecordIndex()
            programRecordIndex()
            scheduleRecordIndex()
            eventplaceRecordIndex()
            contributorRecordIndex()
            programitemRecordIndex()
            socialcategoryRecordIndex()
            socialpostRecordIndex()
            communityCalendarEventRecordIndex()
            venueActorProfileRecordIndex()

            tangledWorkspaceProposalRecordIndex(
                repositoryDIDs: tangledWebhookConfiguration?.repositoryDIDs ?? []
            )
            tangledWorkspaceProposalStatusRecordIndex()
        }
    }

    public func event(id: Event.ID) throws -> Event? {
        guard id.collection?.rawValue == Event.lexiconID.rawValue else { return nil }
        return try database.read { try Event.find(id).fetchOne($0) }
    }

    func indexedEvent(id: Event.ID) throws -> Event.IndexedRecord? {
        guard id.collection?.rawValue == Event.lexiconID.rawValue else { return nil }
        return try database.read { db in
            try #sql("""
                SELECT raw.uri, raw.cid, raw.value
                FROM appViewIndexedRecords AS raw
                JOIN \(Event.self) ON \(Event.id) = raw.uri
                WHERE raw.uri = \(id.description)
                  AND raw.collection = \(Event.lexiconID.rawValue) AND raw.isDeleted = 0
                """, as: NativeEventPayload.self).fetchOne(db)?.record()
        }
    }

    func eventPage(cursor: String?, limit: Int) throws -> Event.Page {
        guard (1...100).contains(limit) else {
            throw OpenMusicEventAppViewStoreError.invalidCursor(cursor ?? "")
        }
        let offset: Int
        if let cursor {
            guard let value = Int(cursor), value >= 0 else {
                throw OpenMusicEventAppViewStoreError.invalidCursor(cursor)
            }
            offset = value
        } else {
            offset = 0
        }
        let (count, rows) = try database.read { db in
            let count = try #sql("""
                SELECT COUNT(*) FROM appViewIndexedRecords AS raw
                JOIN \(Event.self) ON \(Event.id) = raw.uri
                WHERE raw.collection = \(Event.lexiconID.rawValue) AND raw.isDeleted = 0
                """, as: Int.self).fetchOne(db) ?? 0
            let rows = try #sql("""
                SELECT raw.uri, raw.cid, raw.value
                FROM appViewIndexedRecords AS raw
                JOIN \(Event.self) ON \(Event.id) = raw.uri
                LEFT JOIN \(CalendarEventBrowseProjection.self)
                  ON \(CalendarEventBrowseProjection.uri) = raw.uri
                WHERE raw.collection = \(Event.lexiconID.rawValue) AND raw.isDeleted = 0
                ORDER BY \(CalendarEventBrowseProjection.startsAt) IS NULL,
                  \(CalendarEventBrowseProjection.startsAt), \(Event.name) COLLATE NOCASE, raw.uri
                LIMIT \(limit) OFFSET \(offset)
                """, as: NativeEventPayload.self).fetchAll(db)
            return (count, rows)
        }
        guard offset <= count else {
            throw OpenMusicEventAppViewStoreError.invalidCursor(cursor ?? "")
        }
        let records = try rows.map { try $0.record() }
        let nextOffset = offset + records.count
        return Event.Page(events: records, cursor: nextOffset < count ? String(nextOffset) : nil)
    }

    func eventRecordIndex() -> AppViewRecordIndex<Data> {
        AppViewRecordIndex<Data>(
            collection: ATProto.NSID(Event.lexiconID.rawValue),
            decode: { $0 }
        )
        .project { mutation, database in
            switch mutation {
            case let .create(current), let .update(_, current):
                let event = try JSONDecoder().decode(
                    Event.self,
                    from: current.value,
                    configuration: RecordMetadata(uri: current.uri, cid: current.cid)
                )
                try event.validateReferences()
                try Event.upsert { event }.execute(database)
                try CalendarEventBrowseProjection.upsertCanonicalEvent(
                    id: event.id,
                    in: database
                )
            case let .delete(_, current):
                try LexiconCoding.validateRecordURI(current.uri, type: Event.self)
                try Event.find(current.uri).delete().execute(database)
                try CalendarEventBrowseProjection.delete(
                    uri: current.uri.description,
                    in: database
                )
            }
        }
    }
}

@Selection
struct NativeEventPayload {
    let uri: String
    let cid: String
    let value: Data

    func record() throws -> Event.IndexedRecord {
        guard let id = Event.ID(uri), id.collection?.rawValue == Event.lexiconID.rawValue else {
            throw ValidationError("Native event payload has a non-OME identity")
        }
        return try .init(uri: id, cid: ATProto.CID(rawValue: cid),
                         value: JSONDecoder().decode(Lexicon.JSONValue.self, from: value))
    }
}

extension OpenMusicEventAppViewStore {
    func programRecordIndex() -> AppViewRecordIndex<Data> {
        AppViewRecordIndex<Data>(collection: ATProto.NSID(Program.lexiconID.rawValue), decode: { $0 })
            .project { mutation, database in
                switch mutation {
                case let .create(current), let .update(_, current):
                    let record = try JSONDecoder().decode(Program.self, from: current.value,
                        configuration: RecordMetadata(uri: current.uri, cid: current.cid))
                    try record.validateReferences()
                    try Program.upsert { record }.execute(database)
                case let .delete(_, current):
                    try LexiconCoding.validateRecordURI(current.uri, type: Program.self)
                    try Program.find(current.uri).delete().execute(database)
                }
            }
    }
}

extension OpenMusicEventAppViewStore {
    func scheduleRecordIndex() -> AppViewRecordIndex<Data> {
        AppViewRecordIndex<Data>(collection: ATProto.NSID(Schedule.lexiconID.rawValue), decode: { $0 })
            .project { mutation, database in
                switch mutation {
                case let .create(current), let .update(_, current):
                    let record = try JSONDecoder().decode(Schedule.self, from: current.value,
                        configuration: RecordMetadata(uri: current.uri, cid: current.cid))
                    try record.validateReferences()
                    try Schedule.upsert { record }.execute(database)
                case let .delete(_, current):
                    try LexiconCoding.validateRecordURI(current.uri, type: Schedule.self)
                    try Schedule.find(current.uri).delete().execute(database)
                }
            }
    }
}

extension OpenMusicEventAppViewStore {
    func eventplaceRecordIndex() -> AppViewRecordIndex<Data> {
        AppViewRecordIndex<Data>(collection: ATProto.NSID(EventPlace.lexiconID.rawValue), decode: { $0 })
            .project { mutation, database in
                switch mutation {
                case let .create(current), let .update(_, current):
                    let record = try JSONDecoder().decode(EventPlace.self, from: current.value,
                        configuration: RecordMetadata(uri: current.uri, cid: current.cid))
                    try record.validateReferences()
                    try EventPlace.upsert { record }.execute(database)
                    try CalendarEventBrowseProjection.upsertCanonicalEvent(
                        id: record.event,
                        in: database
                    )
                case let .delete(_, current):
                    let eventID = try EventPlace.find(current.uri)
                        .select(\.event)
                        .fetchOne(database)
                    try EventPlace.find(current.uri).delete().execute(database)
                    if let eventID {
                        try CalendarEventBrowseProjection.upsertCanonicalEvent(
                            id: eventID,
                            in: database
                        )
                    }
                }
            }
    }
}

extension OpenMusicEventAppViewStore {
    func contributorRecordIndex() -> AppViewRecordIndex<Data> {
        AppViewRecordIndex<Data>(collection: ATProto.NSID(Contributor.lexiconID.rawValue), decode: { $0 })
            .project { mutation, database in
                switch mutation {
                case let .create(current), let .update(_, current):
                    let record = try JSONDecoder().decode(Contributor.self, from: current.value,
                        configuration: RecordMetadata(uri: current.uri, cid: current.cid))
                    try record.validateReferences()
                    try Contributor.upsert { record }.execute(database)
                    try CalendarEventBrowseProjection.upsertCanonicalEvent(
                        id: record.event,
                        in: database
                    )
                case let .delete(_, current):
                    let eventID = try Contributor.find(current.uri)
                        .select(\.event)
                        .fetchOne(database)
                    try Contributor.find(current.uri).delete().execute(database)
                    if let eventID {
                        try CalendarEventBrowseProjection.upsertCanonicalEvent(
                            id: eventID,
                            in: database
                        )
                    }
                }
            }
    }
}

extension OpenMusicEventAppViewStore {
    func programitemRecordIndex() -> AppViewRecordIndex<Data> {
        AppViewRecordIndex<Data>(collection: ATProto.NSID(ProgramItem.lexiconID.rawValue), decode: { $0 })
            .project { mutation, database in
                switch mutation {
                case let .create(current), let .update(_, current):
                    let record = try JSONDecoder().decode(ProgramItem.self, from: current.value,
                        configuration: RecordMetadata(uri: current.uri, cid: current.cid))
                    try record.validateReferences()
                    try ProgramItem.upsert { record }.execute(database)
                    try CalendarEventBrowseProjection.upsertCanonicalEvent(
                        id: record.event,
                        in: database
                    )
                case let .delete(_, current):
                    let eventID = try ProgramItem.find(current.uri)
                        .select(\.event)
                        .fetchOne(database)
                    try ProgramItem.find(current.uri).delete().execute(database)
                    if let eventID {
                        try CalendarEventBrowseProjection.upsertCanonicalEvent(
                            id: eventID,
                            in: database
                        )
                    }
                }
            }
    }
}

extension OpenMusicEventAppViewStore {
    func socialcategoryRecordIndex() -> AppViewRecordIndex<Data> {
        AppViewRecordIndex<Data>(collection: ATProto.NSID(Social.Category.lexiconID.rawValue), decode: { $0 })
            .project { mutation, database in
                switch mutation {
                case let .create(current), let .update(_, current):
                    let record = try JSONDecoder().decode(Social.Category.self, from: current.value,
                        configuration: RecordMetadata(uri: current.uri, cid: current.cid))
                    try record.validateReferences()
                    try Social.Category.upsert { record }.execute(database)
                case let .delete(_, current):
                    try LexiconCoding.validateRecordURI(current.uri, type: Social.Category.self)
                    try Social.Category.find(current.uri).delete().execute(database)
                }
            }
    }
}

extension OpenMusicEventAppViewStore {
    func socialpostRecordIndex() -> AppViewRecordIndex<Data> {
        AppViewRecordIndex<Data>(collection: ATProto.NSID(Social.Post.lexiconID.rawValue), decode: { $0 })
            .project { mutation, database in
                switch mutation {
                case let .create(current), let .update(_, current):
                    let record = try JSONDecoder().decode(Social.Post.self, from: current.value,
                        configuration: RecordMetadata(uri: current.uri, cid: current.cid))
                    try record.validateReferences()
                    try Social.Post.upsert { record }.execute(database)
                case let .delete(_, current):
                    try LexiconCoding.validateRecordURI(current.uri, type: Social.Post.self)
                    try Social.Post.find(current.uri).delete().execute(database)
                }
            }
    }
}
