import ATProto
import Bluesky
import Dependencies
import Foundation

public enum OpenMusicEventActorTypeahead {
    public static func prepareDependencies(_ dependencies: inout DependencyValues) {
        dependencies.actorTypeaheadSearch = .openMusicEvent
    }
}

extension ActorTypeaheadSearchClient {
    static var openMusicEvent: Self {
        Self { query in
            let query = ActorTypeaheadSearchQuery(
                query.normalizedText,
                limit: query.limit
            )
            guard !query.normalizedText.isEmpty else {
                return []
            }

            @Dependency(XRPC.Client.self) var xrpcClient
            let response = try await xrpcClient.run(
                OpenMusicEventActorTypeaheadRequest(query)
            )
            return response.actors.map(\.actorIdentity)
        }
    }
}

private struct OpenMusicEventActorTypeaheadRequest: XRPC.Request, Sendable {
    static let nsid: ATProto.NSID = "app.bsky.actor.searchActorsTypeahead"
    static let type: XRPC.RequestType = .query
    static let routing = XRPC.Routing(
        unauthenticated: .host("typeahead.waow.tech"),
        authenticated: .host("typeahead.waow.tech")
    )

    typealias Input = Never
    typealias Output = OpenMusicEventActorTypeaheadResponse

    var parameters: Parameters

    init(_ query: ActorTypeaheadSearchQuery) {
        self.parameters = Parameters(
            q: query.normalizedText,
            limit: query.limit
        )
    }

    struct Parameters: Encodable, Equatable, Sendable {
        var q: String
        var limit: Int
    }
}

private struct OpenMusicEventActorTypeaheadResponse: Decodable, Equatable, Sendable {
    var actors: [OpenMusicEventActorTypeaheadActor]
}

private struct OpenMusicEventActorTypeaheadActor: Decodable, Equatable, Identifiable, Sendable {
    var id: DID { did }
    var did: DID
    var handle: Atmosphere.Account.Handle
    var displayName: String?
    var avatar: URL?

    var actorIdentity: ActorIdentity {
        ActorIdentity(
            did: did,
            handle: handle,
            displayName: displayName,
            avatar: avatar,
            source: .typeahead
        )
    }
}
