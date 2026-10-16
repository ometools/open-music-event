import ATProto
import ATProtoAppView
import Dependencies
import Foundation
import Gzip
import HummingbirdTesting
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing
@testable import OpenMusicEventAppViewServer

@Suite(AppViewTestTime()) struct EventBundleRouteTests {
    @Test func downloadRevalidateAndObserveChildChangesAndDeletion() async throws {
        let story = EventViewerIntegrationTests()
        let database = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: database)
        let indexer = store.appViewRecordIndexer(tangledWebhookConfiguration: nil)
        try withDependencies { $0.defaultDatabase = database } operation: {
            for (index, record) in story.records().enumerated() {
                _ = try indexer.apply(.put(story.version(record.0, record.1, sequence: Int64(index + 1))), checkpointID: "bundle")
            }
        }
        let app = try OpenMusicEventAppViewServer.application(
            configuration: .init(host: "127.0.0.1", port: 0), store: store)
        let path = "/xrpc/events.openmusic.getEventBundle?uri=" + story.eventID.description
        try await app.test(.router) { client in
            // A first-time attendee receives every record, including communications, in one response.
            let first = try await client.execute(uri: path, method: .get)
            #expect(first.status == .ok)
            let tag = try #require(first.headers[.eTag])
            let bundle = try JSONDecoder().decode(Event.Bundle.self, from: Data(first.body.readableBytesView))
            let graph = try EventRecordGraph(bundle: bundle)
            #expect(graph.event.name == "Wicked Woods")
            #expect(graph.items.count == 1)
            #expect(graph.posts.first?.title == "Arrival")
            #expect(bundle.records.count == 8)
            // Decode the wire response into an independent attendee database.
            let attendeeDatabase = try DatabaseQueue()
            _ = try OpenMusicEventAppViewStore(database: attendeeDatabase)
            try await attendeeDatabase.write { db in try graph.upsert(in: db) }
            let installed = try await attendeeDatabase.read { db in
                try EventRecordGraph.fetch(eventID: story.eventID, from: db)
            }
            #expect(installed == graph)
            #expect(first.headers[.cacheControl]?.contains("s-maxage=30") == true)

            let unchanged = try await client.execute(uri: path, method: .get, headers: [.ifNoneMatch: tag])
            #expect(unchanged.status == .notModified)
            #expect(unchanged.body.readableBytes == 0)

            let compressed = try await client.execute(uri: path, method: .get, headers: [.acceptEncoding: "gzip"])
            #expect(compressed.headers[.contentEncoding] == "gzip")
            #expect(compressed.headers[.eTag] != tag)
            let uncompressed = try Data(compressed.body.readableBytesView).gunzipped()
            #expect(uncompressed == Data(first.body.readableBytesView))
            let identity = try await client.execute(uri: path, method: .get, headers: [.acceptEncoding: "gzip;q=0"])
            #expect(identity.headers[.contentEncoding] == nil)

            // The Event CID is unchanged, but a contributor edit invalidates the entire snapshot.
            try withDependencies { $0.defaultDatabase = database } operation: {
                var payload = try #require(story.records().first { $0.0 == "events.openmusic.contributor" }?.1)
                payload["name"] = "Updated Artist"
                _ = try indexer.apply(.put(story.version("events.openmusic.contributor", payload, sequence: 20)), checkpointID: "bundle")
            }
            let changed = try await client.execute(uri: path, method: .get, headers: [.ifNoneMatch: tag])
            #expect(changed.status == .ok)
            #expect(changed.headers[.eTag] != tag)
            let updated = try JSONDecoder().decode(Event.Bundle.self, from: Data(changed.body.readableBytesView))
            #expect(try EventRecordGraph(bundle: updated).contributors.first?.name == "Updated Artist")

            // Removed performances disappear from the snapshot, rather than surviving in cached bytes.
            try withDependencies { $0.defaultDatabase = database } operation: {
                _ = try indexer.apply(.delete(.init(collection: "events.openmusic.programItem",
                    uri: #require(ATProto.URI(story.uri("events.openmusic.programItem"))), sequence: 21)), checkpointID: "bundle")
            }
            let deleted = try await client.execute(uri: path, method: .get)
            let deletedBundle = try JSONDecoder().decode(Event.Bundle.self, from: Data(deleted.body.readableBytesView))
            #expect(try EventRecordGraph(bundle: deletedBundle).items.isEmpty)
            #expect(deletedBundle.revision != updated.revision)

            // Never distribute a partial bundle while referenced content is missing.
            try withDependencies { $0.defaultDatabase = database } operation: {
                _ = try indexer.apply(.delete(.init(collection: "social.ome.post",
                    uri: #require(ATProto.URI(story.uri("social.ome.post"))), sequence: 22)), checkpointID: "bundle")
            }
            let incomplete = try await client.execute(uri: path, method: .get)
            #expect(incomplete.status == .serviceUnavailable)
            #expect(incomplete.headers[.cacheControl] == "no-store")
            let invalid = try await client.execute(uri: "/xrpc/events.openmusic.getEventBundle?uri=invalid", method: .get)
            #expect(invalid.status == .badRequest)
            await store.readiness.markCatchingUp()
            let catchingUp = try await client.execute(uri: path, method: .get, headers: [.ifNoneMatch: tag])
            #expect(catchingUp.status == .serviceUnavailable)
            #expect(catchingUp.headers[.cacheControl] == "no-store")
        }
    }
}
