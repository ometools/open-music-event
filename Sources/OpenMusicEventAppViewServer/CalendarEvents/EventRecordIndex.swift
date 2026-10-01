import ATProto
import ATProtoAppView
import ATProtoTypes
import Foundation
import OpenMusicEventLexicon
import SQLiteData

extension OpenMusicEventAppViewStore {
    public func event(id: Event.ID) throws -> Event? {
        try database.read { try Event.find(id).fetchOne($0) }
    }

    func indexedEvent(id: Event.ID) throws -> Event.IndexedRecord? {
        try event(id: id).map(Self.indexedRecord)
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
        let events = try database.read { try Event.all.fetchAll($0) }
            .sorted(by: Self.eventIsSooner)
        guard offset <= events.count else {
            throw OpenMusicEventAppViewStoreError.invalidCursor(cursor ?? "")
        }
        let records = try events.dropFirst(offset).prefix(limit).map(Self.indexedRecord)
        let nextOffset = offset + records.count
        return Event.Page(
            events: records,
            cursor: nextOffset < events.count ? String(nextOffset) : nil
        )
    }

    private static func indexedRecord(_ event: Event) throws -> Event.IndexedRecord {
        try Event.IndexedRecord(
            uri: event.id,
            cid: event.cid,
            value: event.encodeLexicon()
        )
    }

    private static func eventIsSooner(_ lhs: Event, _ rhs: Event) -> Bool {
        switch (lhs.start?.date(in: lhs.timeZone), rhs.start?.date(in: rhs.timeZone)) {
        case let (.some(left), .some(right)) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            return nameOrder == .orderedSame
                ? lhs.id.description < rhs.id.description
                : nameOrder == .orderedAscending
        }
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
            case let .delete(_, current):
                try LexiconCoding.validateRecordURI(current.uri, type: Event.self)
                try Event.find(current.uri).delete().execute(database)
            }
        }
    }
}
