import ATProto
import ATProtoTypes
import ComposableCalendarEvents
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData

public struct EventRecordClient: Sendable {
    public var load: @Sendable (Event.ID) async throws -> EventRecordGraph
    public var latestEvent: @Sendable (Event.ID) async throws -> Event

    public init(
        latestEvent: @escaping @Sendable (Event.ID) async throws -> Event = { _ in
            throw ValidationError("Event detail loading is not configured")
        },
        load: @escaping @Sendable (Event.ID) async throws -> EventRecordGraph
    ) {
        let downloads = EventRecordDownloads()
        self.load = { id in try await downloads.load(id, operation: load) }
        self.latestEvent = latestEvent
    }

    public func install(_ eventID: Event.ID) async throws -> Event.ID {
        AttendeePerformance.mark("install.begin", event: eventID.description)
        defer { AttendeePerformance.mark("install.end", event: eventID.description) }
        try LexiconCoding.validateRecordURI(eventID, type: Event.self)
        @Dependency(\.defaultDatabase) var database
        AttendeePerformance.mark("cache-read.begin", event: eventID.description)
        let installed = try await database.read { db in
            try InstalledEvent.find(eventID).fetchOne(db) != nil
                && Event.find(eventID).fetchCount(db) > 0
        }
        AttendeePerformance.mark("cache-read.end", event: eventID.description)
        AttendeePerformance.mark(installed ? "cache.hit" : "cache.miss", event: eventID.description)
        if installed { return eventID }

        // Local authoring owns its records; browsing alone does not establish a complete graph.
        let locallyAuthored = try await database.read { db in
            try CanonicalSourceEventIdentity.find(eventID).fetchOne(db) != nil
                || LocallyCreatedEvent.find(eventID).fetchOne(db) != nil
        }
        let downloaded: EventRecordGraph?
        if locallyAuthored {
            downloaded = nil
        } else {
            let graph = try await load(eventID)
            guard graph.event.id == eventID else {
                throw ValidationError("The downloaded event has a different record ID")
            }
            downloaded = graph
        }

        try Task.checkCancellation()
        AttendeePerformance.mark("install-write.begin", event: eventID.description)
        try await database.write { db in
            // Another entry may have completed, or local authoring may have started, while downloading.
            if try InstalledEvent.find(eventID).fetchOne(db) != nil,
               try Event.find(eventID).fetchCount(db) > 0 { return }
            let local = try CanonicalSourceEventIdentity.find(eventID).fetchOne(db) != nil
                || LocallyCreatedEvent.find(eventID).fetchOne(db) != nil
            if local {
                guard let graph = try EventRecordGraph.fetch(eventID: eventID, from: db) else {
                    throw ValidationError("The locally authored event is no longer available")
                }
                try graph.validateRelationships()
            } else if let downloaded {
                try downloaded.upsert(in: db)
            } else {
                throw ValidationError("This event is no longer available. Try opening it again.")
            }
            try InstalledEvent.upsert { InstalledEvent(id: eventID) }.execute(db)
        }
        AttendeePerformance.mark("install-write.end", event: eventID.description)
        return eventID
    }
}

extension EventRecordClient: DependencyKey {
    public static var liveValue: Self {
        appView(host: "openmusicevent.app")
    }

    public static func appView(host: ATProto.PDSHost) -> Self {
        Self(latestEvent: { eventID in
            try await CalendarEventsClient.canonicalEvent(eventID, appViewHost: host).event()
        }) { eventID in
            try LexiconCoding.validateRecordURI(eventID, type: Event.self)
            @Dependency(XRPC.Client.self) var xrpc
            AttendeePerformance.mark("bundle-request.begin", event: eventID.description)
            let bundle = try await withDependencies {
                $0.pdsHost = host
            } operation: {
                try await xrpc.run(Event.GetEventBundle(uri: eventID))
            }
            AttendeePerformance.mark("bundle-request.end", event: eventID.description)
            guard bundle.uri == eventID else {
                throw ValidationError("The AppView returned a different event bundle")
            }
            AttendeePerformance.mark("bundle-decode.begin", event: eventID.description)
            defer { AttendeePerformance.mark("bundle-decode.end", event: eventID.description) }
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


// Concurrent entry requests share a download; each installer checks cancellation before writing.
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
