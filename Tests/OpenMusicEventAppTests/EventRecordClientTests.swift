import ATProto
import ATProtoTypes
import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import Testing

@testable import OpenMusicEventApp

struct EventRecordClientTests {
    @Test func overlappingReadersShareOneDownload() async throws {
        try await withMainSerialExecutor {
            let event = try Event(
                id: #require(Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")),
                name: "Wicked Woods", createdAt: "2026-09-01T12:00:00Z",
                timeZone: #require(TimeZone(identifier: "America/Denver"))
            )
            let calls = LockIsolated(0)
            let gate = AsyncStream<Void>.makeStream()
            let client = EventRecordClient { _ in
                calls.withValue { $0 += 1 }
                for await _ in gate.stream { break }
                return EventRecordGraph(event: event)
            }
            let details = Task { try await client.load(event.id) }
            await Task.yield()
            let entry = Task { try await client.load(event.id) }
            await Task.yield()
            #expect(calls.value == 1)
            details.cancel()
            gate.continuation.yield(())
            gate.continuation.finish()
            let loadedEntry = try await entry.value
            expectNoDifference(loadedEntry, EventRecordGraph(event: event))
            _ = try await details.value
            #expect(calls.value == 1)
        }
    }

    @Test(arguments: ["valid", "wrong-id", "unsupported-version"])
    func downloadsOneEventBundleFromAppView(scenario: String) async throws {
        let event = try Event(
            id: #require(Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")),
            name: "Wicked Woods", createdAt: "2026-09-01T12:00:00Z",
            timeZone: #require(TimeZone(identifier: "America/Denver"))
        )
        let requests = LockIsolated<[String]>([])
        var bundle = Event.Bundle(uri: event.id, revision: "event-content-hash",
            records: [.init(uri: event.id, cid: event.cid, value: try event.encodeLexicon())])
        if scenario == "wrong-id" {
            bundle.uri = try #require(Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcai"))
        }
        if scenario == "unsupported-version" { bundle.formatVersion = 2 }
        let data = try JSONEncoder().encode(bundle)
        try await withDependencies {
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = .liveValue
            $0.requestInterceptors = []
            $0.dataForURL = { request, body in
                let url = try #require(request.url)
                #expect(url.host == "metadata.ome-auth.test")
                #expect(url.scheme == "https")
                #expect(body == nil)
                requests.withValue { $0.append(url.path) }
                let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
                #expect(query.queryItems?.first(where: { $0.name == "uri" })?.value == event.id.description)
                return (data, HTTPResponse(status: .ok))
            }
        } operation: {
            let client = EventRecordClient.appView(host: "metadata.ome-auth.test")
            if scenario == "valid" {
                let graph = try await client.load(event.id)
                expectNoDifference(graph, EventRecordGraph(event: event))
            } else {
                await #expect(throws: ValidationError.self) { try await client.load(event.id) }
            }
        }
        expectNoDifference(requests.value, ["/xrpc/events.openmusic.getEventBundle"])
    }
}
