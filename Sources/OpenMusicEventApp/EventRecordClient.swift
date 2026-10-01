import ATProto
import ATProtoTypes
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData

public struct EventRecordClient: Sendable {
    public var load: @Sendable (Event.ID) async throws -> EventRecordGraph

    public init(load: @escaping @Sendable (Event.ID) async throws -> EventRecordGraph) {
        self.load = load
    }

    public func install(_ eventID: Event.ID) async throws -> Event.ID {
        try LexiconCoding.validateRecordURI(eventID, type: Event.self)
        @Dependency(\.defaultDatabase) var database
        let cached = try await database.read { db in
            try Event.find(eventID).fetchOne(db) != nil
        }
        let downloaded: EventRecordGraph?
        if cached {
            downloaded = nil
        } else {
            let graph = try await load(eventID)
            guard graph.event.id == eventID else {
                throw ValidationError("The downloaded event has a different record ID")
            }
            try graph.validate()
            downloaded = graph
        }

        try Task.checkCancellation()
        try await database.write { db in
            if let local = try EventRecordGraph.fetch(eventID: eventID, from: db) {
                try local.validate()
            } else if let downloaded {
                try downloaded.upsert(in: db)
            } else {
                throw ValidationError("This event is no longer available. Try opening it again.")
            }
            try InstalledEvent.upsert { InstalledEvent(id: eventID) }.execute(db)
        }
        return eventID
    }
}

extension EventRecordClient: DependencyKey {
    public static var liveValue: Self {
        Self { eventID in
            try LexiconCoding.validateRecordURI(eventID, type: Event.self)
            @Dependency(ATProto.Repository.PDSHostResolver.self) var hosts
            @Dependency(XRPC.Client.self) var xrpc
            let host = try await hosts.pdsHost(forRecordURI: eventID)
            guard case let .did(did) = eventID.authority else {
                throw ValidationError("An event must have a DID-based record ID")
            }
            let commitRequest = ATProto.Repository.LatestCommitRequest(did: did, pdsHost: host)
            let before = try await xrpc.run(commitRequest)

            func read<Record: RecordCodable & NamedLexiconDefinition>(
                _ type: Record.Type, id: ATProto.URI
            ) async throws -> Record {
                try LexiconCoding.validateRecordURI(id, type: type)
                let response = try await xrpc.getRecord(
                    Lexicon.JSONValue.self,
                    repo: id.authority,
                    collection: ATProto.NSID(Record.lexiconID.rawValue),
                    rkey: id.rkey!,
                    pdsHost: host
                )
                guard response.uri == id else {
                    throw ValidationError("The PDS returned a different record ID")
                }
                return try decode(type, response)
            }

            func list<Record: RecordCodable & NamedLexiconDefinition>(
                _ type: Record.Type
            ) async throws -> [Record] {
                var records: [Record] = []
                var cursor: ATProto.Repository.Cursor?
                var seen: Set<ATProto.Repository.Cursor> = []
                repeat {
                    let page = try await xrpc.listRecords(
                        Lexicon.JSONValue.self,
                        repo: eventID.authority,
                        collection: ATProto.NSID(Record.lexiconID.rawValue),
                        limit: 100, cursor: cursor, pdsHost: host
                    )
                    for record in page.records
                    where record.value.object?["event"]?.string == eventID.description {
                        records.append(try decode(type, record))
                    }
                    cursor = page.cursor
                    if let cursor, !seen.insert(cursor).inserted {
                        throw ValidationError("The PDS repeated a record-list cursor")
                    }
                } while cursor != nil
                return records
            }

            func decode<Record: RecordCodable>(
                _ type: Record.Type,
                _ response: ATProto.Repository.ListedRecord<Lexicon.JSONValue>
            ) throws -> Record {
                try JSONDecoder().decode(
                    type,
                    from: JSONEncoder().encode(response.value),
                    configuration: RecordMetadata(uri: response.uri, cid: response.cid)
                )
            }

            let event = try await read(Event.self, id: eventID)
            try event.validateReferences()
            var programs: [Program] = []
            for id in event.programs ?? [] {
                programs.append(try await read(Program.self, id: id))
            }
            var schedules: [Schedule] = []
            for id in event.schedules ?? [] {
                schedules.append(try await read(Schedule.self, id: id))
            }
            var categories: [Social.Category] = []
            for id in event.categories ?? [] {
                categories.append(try await read(Social.Category.self, id: id))
            }
            let graph = try await EventRecordGraph(
                event: event,
                programs: programs,
                schedules: schedules,
                places: list(EventPlace.self),
                contributors: list(Contributor.self),
                items: list(ProgramItem.self),
                categories: categories
            )
            try graph.validate()
            let after = try await xrpc.run(commitRequest)
            guard before == after else {
                throw ValidationError("The repository changed while downloading the event. Try again.")
            }
            return graph
        }
    }

    public static var testValue: Self {
        Self { _ in throw ValidationError("Event record loading is not configured") }
    }
}

public extension DependencyValues {
    var eventRecords: EventRecordClient {
        get { self[EventRecordClient.self] }
        set { self[EventRecordClient.self] = newValue }
    }
}
