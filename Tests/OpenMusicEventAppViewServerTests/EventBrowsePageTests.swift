import ATProto
import ATProtoAppView
import CustomDump
import Dependencies
import Foundation
import HummingbirdTesting
import OpenMusicEventLexicon
import OpenMusicEventRouting
import SQLiteData
import Testing
@testable import OpenMusicEventAppViewServer

@Suite struct EventBrowsePageTests {
    @Test func browseGroupsAndFiltersIndexedEventsAndOpensTheirViewer() async throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let indexer = store.appViewRecordIndexer(tangledWebhookConfiguration: nil)
        // The browse projection receives actual published records, including an event with no announced date.
        let fixtures: [(String, String?, String?, String)] = [
            ("Live Forest", "2026-10-06T01:00:00Z", "2026-10-07T12:00:00Z", "inperson"),
            ("Upcoming Forest", "2026-11-06T12:00:00Z", nil, "hybrid"),
            ("Earlier Forest", "2026-09-06T12:00:00Z", nil, "virtual"),
            ("Unannounced <Forest>", nil, nil, "inperson")
        ]
        try withDependencies { $0.defaultDatabase = database } operation: {
            for (index, fixture) in fixtures.enumerated() {
                var value: [String: Any] = ["$type": "events.openmusic.event", "createdAt": "2026-08-01T12:00:00Z",
                    "name": fixture.0, "timeZone": "America/Edmonton", "mode": "community.lexicon.calendar.event#" + fixture.3]
                if let start = fixture.1 { value["start"] = ["$type": "events.openmusic.defs#time", "value": start] }
                if let end = fixture.2 { value["end"] = ["$type": "events.openmusic.defs#time", "value": end] }
                let record = try AppView.RecordVersion<Data>(collection: ATProto.NSID(Event.lexiconID.rawValue),
                    uri: ATProto.URI("at://did:plc:organizer/events.openmusic.event/3mrdbziccpc\(index + 2)h")!,
                    cid: ATProto.CID(rawValue: "bafy-browse-\(index)"), value: try JSONSerialization.data(withJSONObject: value), sequence: Int64(index + 1))
                _ = try indexer.apply(.put(record), checkpointID: "browse")
            }
        }
        let events = try await database.read { try Event.all.fetchAll($0) }
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-06T18:00:00Z"))
        let resolver = OpenMusicEventRouter()
        let groups = OpenMusicEventAppViewServer.browseSections(events: events, selection: try .init(query: nil), host: "localhost", routeResolver: resolver, now: now)
        expectNoDifference(groups.map(\.title), ["Happening Now", "Upcoming", "More Events", "Past Events"])
        expectNoDifference(groups.map { $0.events.map(\.title) }, [["Live Forest"], ["Upcoming Forest"], ["Unannounced <Forest>"], ["Earlier Forest"]])
        let filtered = OpenMusicEventAppViewServer.browseSections(events: events, selection: try .init(query: "mode=hybrid&q=forest&sort=name"), host: "localhost", routeResolver: resolver, now: now)
        expectNoDifference(filtered.flatMap(\.events).map(\.title), ["Upcoming Forest"])
        let day = OpenMusicEventAppViewServer.browseSections(events: events, selection: try .init(query: "day=2026-10-05"), host: "localhost", routeResolver: resolver, now: now)
        expectNoDifference(day.flatMap(\.events).map(\.title), ["Live Forest"])

        let app = try OpenMusicEventAppViewServer.application(configuration: .init(host: "127.0.0.1", port: 0), store: store)
        try await app.test(.router) { client in
            try await client.execute(uri: "/", method: .get) { response in
                #expect(response.status == .ok)
                let html = String(buffer: response.body)
                #expect(html.contains("The <em>open</em> guide to what’s happening."))
                #expect(html.contains("assets/app.js"))
                #expect(html.contains("ome-mark-sphere-cage"))
            }
            // A record without a configured branded claim still has a working event page and section links.
            let target = try #require(groups.first?.events.first?.url)
            try await client.execute(uri: target + "?feature=about", method: .get) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body).contains("Live Forest"))
            }
            expectNoDifference(try EventBrowseSelection(query: "q=A%2BB+C").query, "A+B C")
            try await client.execute(uri: "/about", method: .get) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body).contains("OpenMusicEvent"))
            }
            await store.readiness.markCatchingUp()
            try await client.execute(uri: "/", method: .get) { response in
                #expect(response.status == .serviceUnavailable)
            }
        }
    }
}
