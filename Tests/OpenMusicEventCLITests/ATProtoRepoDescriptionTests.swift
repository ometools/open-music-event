import ATProto
import CustomDump
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import Testing
import XRPCClient

@testable import OpenMusicEventSourceClone

struct ATProtoRepoDescriptionTests {
    @Test
    func describeRepoRequestBuildsQuery() {
        let request = ATProtoDescribeRepoRequest(
            repo: "did:plc:actor123",
            pdsHost: "actor.pds.example"
        )

        expectNoDifference(
            request.queryItems,
            [
                URLQueryItem(name: "repo", value: "did:plc:actor123")
            ]
        )
        expectNoDifference(
            request.routing,
            XRPC.Routing(
                unauthenticated: .host("actor.pds.example"),
                authenticated: .host("actor.pds.example")
            )
        )
    }

    @Test
    func repoDescriptionDecodesCollectionsAndIgnoresDIDDocument() throws {
        let description = try JSONDecoder().decode(
            ATProtoRepoDescription.self,
            from: Data(
                """
                {
                  "handle": "artist.example",
                  "did": "did:plc:artist123",
                  "didDoc": {
                    "id": "did:plc:artist123",
                    "alsoKnownAs": ["at://artist.example"],
                    "verificationMethod": [],
                    "service": []
                  },
                  "collections": [
                    "app.bsky.actor.profile",
                    "sh.tangled.repo",
                    "app.openmusicevent.contributor"
                  ],
                  "handleIsCorrect": true
                }
                """
                .utf8
            )
        )

        expectNoDifference(description.handle, "artist.example")
        expectNoDifference(description.did.description, "did:plc:artist123")
        expectNoDifference(
            description.collections.map(\.rawValue),
            [
                "app.bsky.actor.profile",
                "sh.tangled.repo",
                "app.openmusicevent.contributor",
            ]
        )
        #expect(description.handleIsCorrect)
    }

    @Test
    func clientResolvesHandleAndDescribesRepoOnActorPDS() async throws {
        let actorDID = try #require(DID("did:plc:artist123"))
        let actorHandle = Atmosphere.Account.Handle("artist.example")
        let recorder = HTTPRequestRecorder()

        let description = try await withDependencies {
            $0[Atmosphere.Account.Client.self] = Atmosphere.Account.Client(
                resolveHandle: { handle in
                    expectNoDifference(handle, actorHandle)
                    return (
                        Atmosphere.Account(id: .init(actorDID), handle: handle),
                        try didDocument(
                            did: actorDID,
                            handle: handle,
                            pdsHost: "artist.pds.example"
                        )
                    )
                },
                resolveDID: { did in
                    Issue.record("Did not expect DID resolution: \(did)")
                    return (
                        Atmosphere.Account(id: .init(actorDID), handle: actorHandle),
                        try didDocument(
                            did: actorDID,
                            handle: actorHandle,
                            pdsHost: "artist.pds.example"
                        )
                    )
                }
            )
            $0.atProtoRepoDescription = .live
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { request, body in
                await recorder.record(request, body)
                return Data(
                    """
                    {
                      "handle": "artist.example",
                      "did": "did:plc:artist123",
                      "didDoc": {},
                      "collections": [
                        "app.bsky.actor.profile",
                        "app.openmusicevent.contributor"
                      ],
                      "handleIsCorrect": true
                    }
                    """
                    .utf8
                )
            }
        } operation: {
            @Dependency(\.atProtoRepoDescription) var repoDescription
            return try await repoDescription.describe(.handle(actorHandle))
        }

        expectNoDifference(
            description.collections.map(\.rawValue),
            [
                "app.bsky.actor.profile",
                "app.openmusicevent.contributor",
            ]
        )

        let requests = await recorder.requests
        #expect(requests.count == 1)
        #expect(
            requests.first?.url?.absoluteString
                == "https://artist.pds.example/xrpc/com.atproto.repo.describeRepo?repo=did:plc:artist123"
        )
        #expect(requests.first?.body == nil)
    }

    @Test
    func clientFailsWhenResolvedDIDDocumentHasNoPDS() async throws {
        let actorDID = try #require(DID("did:plc:artist123"))
        let actorHandle = Atmosphere.Account.Handle("artist.example")

        let error = await #expect(throws: ATProtoRepoDescriptionClientError.self) {
            try await withDependencies {
                $0[Atmosphere.Account.Client.self] = Atmosphere.Account.Client(
                    resolveHandle: { handle in
                        (
                            Atmosphere.Account(id: .init(actorDID), handle: handle),
                            try didDocument(
                                did: actorDID,
                                handle: handle,
                                pdsHost: nil
                            )
                        )
                    },
                    resolveDID: { did in
                        (
                            Atmosphere.Account(id: .init(did), handle: actorHandle),
                            try didDocument(
                                did: did,
                                handle: actorHandle,
                                pdsHost: nil
                            )
                        )
                    }
                )
                $0.atProtoRepoDescription = .live
            } operation: {
                @Dependency(\.atProtoRepoDescription) var repoDescription
                _ = try await repoDescription.describe(.did(actorDID))
            }
        }

        #expect(error == .missingPDSHost("did:plc:artist123"))
    }
}

private actor HTTPRequestRecorder {
    struct Request: Sendable {
        var url: URL?
        var body: Data?
    }

    private var _requests: [Request] = []

    var requests: [Request] {
        _requests
    }

    func record(_ request: HTTPRequest, _ body: Data?) {
        _requests.append(
            Request(
                url: request.url,
                body: body
            )
        )
    }
}

private func didDocument(
    did: DID,
    handle: Atmosphere.Account.Handle,
    pdsHost: String? = nil
) throws -> DID.Document {
    let service = pdsHost.map {
        """
                "service": [
                    {
                        "id": "#atproto_pds",
                        "type": "AtprotoPersonalDataServer",
                        "serviceEndpoint": "https://\($0)"
                    }
                ]
        """
    } ?? """
                "service": []
    """

    return try JSONDecoder().decode(
        DID.Document.self,
        from: Data(
            """
            {
                "id": "\(did)",
                "alsoKnownAs": ["at://\(handle.rawValue)"],
                "verificationMethod": [],
                \(service)
            }
            """.utf8
        )
    )
}
