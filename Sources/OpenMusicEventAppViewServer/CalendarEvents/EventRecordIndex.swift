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
