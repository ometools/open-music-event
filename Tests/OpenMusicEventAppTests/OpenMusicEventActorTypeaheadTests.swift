import ATProto
import CustomDump
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import Testing
import XRPCClient

@testable import OpenMusicEventApp

struct OpenMusicEventActorTypeaheadTests {
    @Test
    func preparedDependenciesRouteActorTypeaheadThroughWAOW() async throws {
        let requestRecorder = ActorTypeaheadHTTPRequestRecorder()

        let identities = try await withDependencies {
            $0.context = .test
            try OpenMusicEventDependencies.prepare(&$0)
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { request, body in
                await requestRecorder.record(request, body)
                return Data(
                    """
                    {
                      "actors": [
                        {
                          "did": "did:plc:alice123",
                          "handle": "alice.example.com",
                          "displayName": "Alice",
                          "avatar": "https://example.com/alice.jpg"
                        },
                        {
                          "did": "did:web:bob.example.com",
                          "handle": "bob.example.com"
                        }
                      ]
                    }
                    """
                    .utf8
                )
            }
        } operation: {
            @Dependency(\.actorTypeaheadSearch) var actorTypeaheadSearch
            return try await actorTypeaheadSearch.search(
                ActorTypeaheadSearchQuery(" alice ", limit: 2)
            )
        }

        let requests = await requestRecorder.requests
        let request = try #require(requests.first)
        #expect(requests.count == 1)
        #expect(request.url?.host == "typeahead.waow.tech")
        #expect(request.url?.path == "/xrpc/app.bsky.actor.searchActorsTypeahead")
        #expect(request.body == nil)

        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let parameters = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }
        )
        #expect(parameters["q"] == "alice")
        #expect(parameters["limit"] == "2")

        expectNoDifference(
            identities,
            [
                ActorIdentity(
                    did: try #require(DID("did:plc:alice123")),
                    handle: Atmosphere.Account.Handle(rawValue: "alice.example.com"),
                    displayName: "Alice",
                    avatar: URL(string: "https://example.com/alice.jpg"),
                    source: .typeahead
                ),
                ActorIdentity(
                    did: try #require(DID("did:web:bob.example.com")),
                    handle: Atmosphere.Account.Handle(rawValue: "bob.example.com"),
                    source: .typeahead
                ),
            ]
        )
    }

    @Test
    func preparedDependenciesDoNotCallTypeaheadForEmptyQueries() async throws {
        let requestRecorder = ActorTypeaheadHTTPRequestRecorder()

        let identities = try await withDependencies {
            $0.context = .test
            try OpenMusicEventDependencies.prepare(&$0)
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { request, body in
                await requestRecorder.record(request, body)
                return Data(#"{"actors":[]}"#.utf8)
            }
        } operation: {
            @Dependency(\.actorTypeaheadSearch) var actorTypeaheadSearch
            return try await actorTypeaheadSearch.search(
                ActorTypeaheadSearchQuery("   ")
            )
        }

        expectNoDifference(identities, [])
        #expect(await requestRecorder.requests.isEmpty)
    }
}

private actor ActorTypeaheadHTTPRequestRecorder {
    struct Request: Sendable {
        var url: URL?
        var body: Data?
    }

    private(set) var requests: [Request] = []

    func record(_ request: HTTPRequest, _ body: Data?) {
        requests.append(Request(url: request.url, body: body))
    }
}
