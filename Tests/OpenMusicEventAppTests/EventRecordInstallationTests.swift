import ATProto
import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@testable import OpenMusicEventApp

struct EventRecordInstallationTests {
    @Test
    func installedCanonicalEventAppearsInMyEvents() async throws {
        let database = try database()
        let graph = try graph()
        let client = EventRecordClient { _ in graph }

        try await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            _ = try await client.install(graph.event.id)
        }

        let events = try await database.read { db in
            try MyEvents.query.fetchAll(db)
        }
        expectNoDifference(events, [graph.event])
    }

    @Test
    func installationSurvivesReopeningAndKeepsLocalEdits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("events.sqlite").path
        let graph = try graph()
        let downloads = LockIsolated(0)
        let client = EventRecordClient { id in
            expectNoDifference(id, graph.event.id)
            downloads.withValue { $0 += 1 }
            return graph
        }
        let edited: EventRecordGraph = {
            var result = graph
            result.event.name = "Locally edited event"
            result.programs[0].title = "Locally edited program"
            return result
        }()

        do {
            let database = try database(path: path)
            try await withDependencies {
                $0.defaultDatabase = database
            } operation: {
                let installed = try await client.install(graph.event.id)
                expectNoDifference(installed, graph.event.id)
            }
            let stored = try await database.read { try EventRecordGraph.fetch(eventID: graph.event.id, from: $0) }
            expectNoDifference(stored, graph)
            try await database.write { try edited.upsert(in: $0) }
        }

        // Relaunch uses persisted records and does not download over the user's changes.
        let reopened = try database(path: path)
        try await withDependencies {
            $0.defaultDatabase = reopened
        } operation: {
            _ = try await client.install(graph.event.id)
        }
        let saved = try await reopened.read { try EventRecordGraph.fetch(eventID: graph.event.id, from: $0) }
        let installed = try await reopened.read { try InstalledEvent.all.fetchAll($0) }
        expectNoDifference(saved, edited)
        expectNoDifference(installed, [InstalledEvent(id: graph.event.id)])
        expectNoDifference(downloads.value, 1)
    }

    @Test(arguments: ["offline", "wrong-record", "incomplete-graph", "marker-write"])
    func failedInstallationDoesNotLeaveRecordsOrAnInstallation(scenario: String) async throws {
        let database = try database()
        let graph = try graph()
        if scenario == "marker-write" {
            try await database.write { db in
                try #sql("""
                    CREATE TRIGGER rejectInstallation BEFORE INSERT ON installedEventRecords
                    BEGIN SELECT RAISE(ABORT, 'Installation could not be recorded'); END
                    """).execute(db)
            }
        }
        let client = EventRecordClient { _ in
            switch scenario {
            case "offline":
                throw URLError(.notConnectedToInternet)
            case "wrong-record":
                return EventRecordGraph(event: try Event(
                    id: #require(Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcai")),
                    name: "Another event", createdAt: graph.event.createdAt,
                    timeZone: graph.event.timeZone
                ))
            case "incomplete-graph":
                return EventRecordGraph(event: graph.event)
            default:
                return graph
            }
        }
        await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            await #expect(throws: (any Error).self) {
                try await client.install(graph.event.id)
            }
        }
        // Even a failure after saving the graph rolls back both the event and its children.
        let counts = try await database.read { db in
            [
                try Event.all.fetchCount(db),
                try Program.all.fetchCount(db),
                try InstalledEvent.all.fetchCount(db),
            ]
        }
        expectNoDifference(counts, [0, 0, 0])
    }

    @Test(arguments: [false, true])
    func installingACachedOrConcurrentlySavedEventPreservesItsLocalGraph(cached: Bool) async throws {
        let database = try database()
        let graph = try graph()
        let local: EventRecordGraph = {
            var result = graph
            result.event.name = "Local event"
            result.programs[0].title = "Local program"
            return result
        }()
        if cached {
            try await database.write { try local.upsert(in: $0) }
        }
        // Caching an event for browsing is not an installation.
        let before = try await database.read { try InstalledEvent.all.fetchAll($0) }
        expectNoDifference(before, [])
        let downloads = LockIsolated(0)
        let client = EventRecordClient { _ in
            downloads.withValue { $0 += 1 }
            try await database.write { try local.upsert(in: $0) }
            return graph
        }
        try await withDependencies {
            $0.defaultDatabase = database
        } operation: {
            _ = try await client.install(graph.event.id)
        }
        let saved = try await database.read { try EventRecordGraph.fetch(eventID: graph.event.id, from: $0) }
        let installed = try await database.read { try InstalledEvent.all.fetchAll($0) }
        expectNoDifference(saved, local)
        expectNoDifference(installed, [InstalledEvent(id: graph.event.id)])
        expectNoDifference(downloads.value, cached ? 0 : 1)
    }

    private func database(path: String = ":memory:") throws -> DatabaseQueue {
        let database = try DatabaseQueue(path: path)
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }

    private func graph() throws -> EventRecordGraph {
        let eventID = try #require(Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"))
        let programID = try #require(Program.ID("at://did:plc:organizer/events.openmusic.program/3mrdbziccpcah"))
        return try EventRecordGraph(
            event: Event(
                id: eventID, name: "Wicked Woods", createdAt: "2026-09-01T12:00:00Z",
                timeZone: #require(TimeZone(identifier: "America/Denver")),
                programs: [programID]
            ),
            programs: [
                Program(id: programID, event: eventID, title: "Music",
                        createdAt: "2026-09-01T12:00:00Z", eventPlaces: [])
            ]
        )
    }
}
