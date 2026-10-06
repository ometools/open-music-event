import ATProto
import ATProtoTypes
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData

public struct EventRecordClient: Sendable {
    public var load: @Sendable (Event.ID) async throws -> EventRecordGraph
    public var latestEvent: @Sendable (Event.ID) async throws -> Event

    public init(load: @escaping @Sendable (Event.ID) async throws -> EventRecordGraph) {
        let downloads = EventRecordDownloads()
        self.load = { id in try await downloads.load(id, operation: load) }
        self.latestEvent = { id in try await downloads.load(id, operation: load).event }
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
            downloaded = graph
        }

        try Task.checkCancellation()
        try await database.write { db in
            if let local = try EventRecordGraph.fetch(eventID: eventID, from: db) {
                try local.validateRelationships()
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
        appView(host: "openmusicevent.app")
    }

    public static func appView(host: ATProto.PDSHost) -> Self {
        Self { eventID in
            try LexiconCoding.validateRecordURI(eventID, type: Event.self)
            @Dependency(XRPC.Client.self) var xrpc
            let bundle = try await withDependencies {
                $0.pdsHost = host
            } operation: {
                try await xrpc.run(Event.GetEventBundle(uri: eventID))
            }
            guard bundle.uri == eventID else {
                throw ValidationError("The AppView returned a different event bundle")
            }
            return try EventRecordGraph(bundle: bundle)
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


// A detail preload and Enter Event share one in-flight request. Cancelling one caller
// does not cancel another caller's download; each installer checks cancellation before writing.
actor EventRecordDownloads {
    var tasks: [Event.ID: Task<EventRecordGraph, Error>] = [:]

    func load(
        _ id: Event.ID,
        operation: @escaping @Sendable (Event.ID) async throws -> EventRecordGraph
    ) async throws -> EventRecordGraph {
        if let task = tasks[id] { return try await task.value }
        let task = Task { try await operation(id) }
        tasks[id] = task
        defer { tasks[id] = nil }
        return try await task.value
    }
}
