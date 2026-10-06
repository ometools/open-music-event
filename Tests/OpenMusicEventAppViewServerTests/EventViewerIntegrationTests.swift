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

@Suite struct EventViewerIntegrationTests {
    let owner = "did:plc:organizer"
    func uri(_ collection: String) -> String { "at://\(owner)/\(collection)/3mrdbziccpcah" }
    var eventID: Event.ID { Event.ID(uri("events.openmusic.event"))! }

    func records() -> [(String, [String: Any])] {
        let event = uri("events.openmusic.event")
        let program = uri("events.openmusic.program")
        let day = uri("events.openmusic.schedule")
        let place = uri("events.openmusic.eventPlace")
        let contributor = uri("events.openmusic.contributor")
        let category = uri("social.ome.category")
        let post = uri("social.ome.post")
        // Dependencies intentionally arrive before their parent Event.
        return [
            ("events.openmusic.programItem", ["event": event, "program": program, "title": "Midnight set", "schedule": day, "eventPlace": place,
                "startsAt": "2026-08-30T05:30:00Z", "endsAt": "2026-08-30T07:00:00Z", "credits": [["name": "Forest Artist", "contributor": contributor]]]),
            ("events.openmusic.program", ["event": event, "title": "Music", "eventPlaces": [place]]),
            ("events.openmusic.schedule", ["event": event, "date": "2026-08-29", "title": "Saturday"]),
            ("events.openmusic.eventPlace", ["event": event, "name": "Forest", "kind": ["$type": "events.openmusic.defs#eventPlaceStage", "color": 0x009af7]]),
            ("events.openmusic.contributor", ["event": event, "name": "Forest Artist", "description": "A real biography"]),
            ("social.ome.category", ["event": event, "name": "General", "pinnedPosts": [post]]),
            ("social.ome.post", ["event": event, "category": category, "title": "Arrival", "text": "Bring water <script>alert(1)</script>", "embed": ["$type": "app.bsky.embed.images", "images": [["alt": "Arrival map", "image": ["$type": "blob", "ref": ["$link": "bafkreigh2akiscaildcw4533wvg6wlj3n6yqun26ucfqocgpamdfhhx5lq"], "mimeType": "image/png", "size": 4]]]]]),
            ("events.openmusic.event", ["name": "Wicked Woods", "timeZone": "America/Edmonton", "programs": [program], "schedules": [day], "categories": [category]])
        ]
    }

    func version(_ collection: String, _ payload: [String: Any], sequence: Int64) throws -> AppView.RecordVersion<Data> {
        var object = payload
        object["$type"] = collection
        object["createdAt"] = "2026-08-01T12:00:00Z"
        return try .init(collection: ATProto.NSID(collection), uri: ATProto.URI(uri(collection))!,
            cid: ATProto.CID(rawValue: "bafy-test-\(sequence)"), value: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), sequence: sequence)
    }

    @Test func recordsReachServerRenderedPagesAndUpdatesSurviveReplay() async throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let indexer = store.appViewRecordIndexer(tangledWebhookConfiguration: nil)
        try withDependencies { $0.defaultDatabase = database } operation: {
            for (index, record) in records().enumerated() {
                _ = try indexer.apply(.put(version(record.0, record.1, sequence: Int64(index + 1))), checkpointID: "graph-v1")
            }
        }
        let content = try #require(try store.eventViewerContent(id: eventID))
        let model = try content.presentation(selection: .init(query: nil))
        expectNoDifference(model.schedulePerformances.map(\.time), ["11:30 PM"])
        expectNoDifference(model.schedulePerformances.map(\.endTime), ["1:00 AM"])
        expectNoDifference(model.schedulePerformances.map(\.startMinute), [1410])
        expectNoDifference(model.schedulePerformances.map(\.endMinute), [1500])
        // The published stage color reaches cards and lanes, retaining leading zeroes.
        expectNoDifference(model.schedulePerformances.map(\.stageColor), ["#009af7"])
        expectNoDifference(model.scheduleStages.map(\.stageColor), ["#009af7"])
        expectNoDifference(model.stagePerformances.map(\.stageColor), ["#009af7"])
        #expect(model.posts.first?.pinned == true)
        #expect(model.contributors.first?.performanceIDs == [uri("events.openmusic.programItem")])
        var configuration = AppViewConfiguration(host: "127.0.0.1", port: 0)
        configuration.webPDSHosts = [owner: "pds.example.test"]
        configuration.brandedEventRouteClaims = [.init(host: "localhost", eventClaim: "woods", eventID: eventID)]
        let app = try OpenMusicEventAppViewServer.application(configuration: configuration, store: store)
        try await app.test(.router) { client in
            // The initial HTTP document contains the schedule, without client-side fetching.
            for kind in ["single-stage", "many-horizontal", "many-vertical", "list"] {
                try await client.execute(uri: "/events/woods?schedule-kind=\(kind)", method: .get) { response in
                    #expect(response.status == .ok)
                    let html = String(buffer: response.body)
                    #expect(html.contains("Midnight set"))
                    #expect(html.contains("11:30 PM"))
                    #expect(html.contains("--stage-color: #009af7"))
                    #expect(!html.contains("fetch("))
                    #expect(!html.contains("feature=workspace"))
                }
            }
            try await client.execute(uri: "/events/woods?feature=communications", method: .get) { response in
                #expect(String(buffer: response.body).contains("Bring water &lt;script&gt;"))
                #expect(String(buffer: response.body).contains("Pinned"))
            }
            try await client.execute(uri: "/events/woods?feature=contributors&q=missing", method: .get) { response in
                #expect(!String(buffer: response.body).contains("Forest Artist"))
            }
            try await client.execute(uri: "/events/woods?stage=unrelated", method: .get) { response in
                #expect(response.status == .notFound)
            }
            try await client.execute(uri: "/event-media?record=not-a-record&cid=anything", method: .get) { response in
                #expect(response.status == .notFound)
            }
            let imageURL = try #require(model.posts.first?.images.first?.imageURL)
            try await client.execute(uri: imageURL, method: .get) { response in
                #expect(response.status == .temporaryRedirect)
                #expect(response.headers[.location]?.hasPrefix("https://pds.example.test/xrpc/com.atproto.sync.getBlob?") == true)
                #expect(response.headers[.location]?.contains("did=did:plc:organizer") == true)
            }
            await store.readiness.markCatchingUp()
            try await client.execute(uri: "/events/woods", method: .get) { response in
                #expect(response.status == .serviceUnavailable)
            }
            await store.readiness.markReady(cursor: 8)
            // A newer record changes the page; replaying the old revision cannot undo it.
            try withDependencies { $0.defaultDatabase = database } operation: {
                let original = records().first { $0.0 == "events.openmusic.contributor" }!
                var edited = original.1; edited["name"] = "Updated Artist"
                _ = try indexer.apply(.put(version(original.0, edited, sequence: 20)), checkpointID: "graph-v1")
                _ = try indexer.apply(.put(version(original.0, original.1, sequence: 5)), checkpointID: "graph-v1")
            }
            try await client.execute(uri: "/events/woods?feature=contributors", method: .get) { response in
                #expect(String(buffer: response.body).contains("Updated Artist"))
                #expect(!String(buffer: response.body).contains("Forest Artist"))
            }
            // Incomplete referenced content is unavailable, not silently displayed as empty.
            try withDependencies { $0.defaultDatabase = database } operation: {
                _ = try indexer.apply(.delete(.init(collection: "events.openmusic.contributor", uri: ATProto.URI(uri("events.openmusic.contributor"))!, sequence: 21)), checkpointID: "graph-v1")
            }
            try await client.execute(uri: "/events/woods", method: .get) { response in
                #expect(response.status == .serviceUnavailable)
            }
        }
    }

    @Test func expandingTheProjectionBackfillsPreviouslyIgnoredRecords() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        try withDependencies { $0.defaultDatabase = database } operation: {
            let oldIndexer = AppViewRecordIndexer { store.eventRecordIndex() }
            for (index, record) in records().enumerated() {
                _ = try oldIndexer.apply(.put(version(record.0, record.1, sequence: Int64(index + 1))), checkpointID: "events-only")
            }
            #expect(throws: (any Error).self) { try store.eventViewerContent(id: eventID) }
            let expanded = store.appViewRecordIndexer(tangledWebhookConfiguration: nil)
            for (index, record) in records().enumerated() {
                _ = try expanded.apply(.put(version(record.0, record.1, sequence: Int64(index + 1))), checkpointID: "events-only|event-graph-v1")
            }
            #expect(try store.eventViewerContent(id: eventID)?.graph.items.count == 1)
            #expect(try AppViewIndexDatabase.checkpoint(id: "events-only")?.sequence == 8)
            #expect(try AppViewIndexDatabase.checkpoint(id: "events-only|event-graph-v1")?.sequence == 8)
        }
    }
    @Test func scheduleSelectionKeepsDifferentDaysSeparateAndUsesStageIdentity() throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let indexer = store.appViewRecordIndexer(tangledWebhookConfiguration: nil)
        try withDependencies { $0.defaultDatabase = database } operation: {
            for (index, record) in records().enumerated() {
                _ = try indexer.apply(.put(version(record.0, record.1, sequence: Int64(index + 1))), checkpointID: "graph")
            }
        }
        var content = try #require(try store.eventViewerContent(id: eventID))
        let secondDayID = ATProto.URI("at://did:plc:organizer/events.openmusic.schedule/3mrdbziccpcaq")!
        let secondItemID = ATProto.URI("at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcaq")!
        content.graph.schedules.append(try Schedule(id: secondDayID, event: eventID, date: .init("2026-08-30")!, createdAt: "2026-08-01T12:00:00Z"))
        content.graph.event.schedules?.append(secondDayID)
        content.graph.items.append(try ProgramItem(id: secondItemID, event: eventID, program: content.graph.programs[0].id,
            title: "Sunday set", createdAt: "2026-08-01T12:00:00Z", schedule: secondDayID,
            eventPlace: content.graph.places[0].id, startsAt: "2026-08-31T05:00:00Z", endsAt: "2026-08-31T06:00:00Z"))
        let first = try content.presentation(selection: .init(query: nil))
        expectNoDifference(first.schedulePerformances.map(\.title), ["Midnight set"])
        let second = try content.presentation(selection: .init(query: String(webQuery(["day": secondDayID.description]).dropFirst())))
        expectNoDifference(second.schedulePerformances.map(\.title), ["Sunday set"])
        #expect(second.dayChoices.count == 2)
        #expect(second.stagePerformances[0].stageID == uri("events.openmusic.eventPlace"))
        #expect(second.contributors[0].performanceIDs == [uri("events.openmusic.programItem")])
    }

    @Test(arguments: ["events.openmusic.event", "events.openmusic.program", "events.openmusic.schedule", "events.openmusic.eventPlace", "events.openmusic.contributor", "events.openmusic.programItem", "social.ome.category", "social.ome.post"])
    func deletionAndStaleReplayAreHandledForEveryCollection(_ collection: String) throws {
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let indexer = store.appViewRecordIndexer(tangledWebhookConfiguration: nil)
        try withDependencies { $0.defaultDatabase = database } operation: {
            let record = try #require(records().first { $0.0 == collection })
            let initial = try version(collection, record.1, sequence: 1)
            _ = try indexer.apply(.put(initial), checkpointID: "graph")
            _ = try indexer.apply(.put(version(collection, record.1, sequence: 2)), checkpointID: "graph")
            _ = try indexer.apply(.delete(.init(collection: ATProto.NSID(collection), uri: initial.uri, sequence: 3)), checkpointID: "graph")
            _ = try indexer.apply(.put(initial), checkpointID: "graph")
            let count = try database.read { db in
                try Int.fetchOne(db, sql: "SELECT count(*) FROM \"" + collection + "\"")
            }
            #expect(count == 0)
            #expect(try AppViewIndexDatabase.checkpoint(id: "graph")?.sequence == 3)
        }
    }

}
