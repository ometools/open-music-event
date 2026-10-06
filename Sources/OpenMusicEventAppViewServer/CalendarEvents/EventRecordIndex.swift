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

            tangledWorkspaceProposalRecordIndex(
                repositoryDIDs: tangledWebhookConfiguration?.repositoryDIDs ?? []
            )
            tangledWorkspaceProposalStatusRecordIndex()
        }
    }

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
                case let .delete(_, current):
                    try LexiconCoding.validateRecordURI(current.uri, type: EventPlace.self)
                    try EventPlace.find(current.uri).delete().execute(database)
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
                case let .delete(_, current):
                    try LexiconCoding.validateRecordURI(current.uri, type: Contributor.self)
                    try Contributor.find(current.uri).delete().execute(database)
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
                case let .delete(_, current):
                    try LexiconCoding.validateRecordURI(current.uri, type: ProgramItem.self)
                    try ProgramItem.find(current.uri).delete().execute(database)
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
