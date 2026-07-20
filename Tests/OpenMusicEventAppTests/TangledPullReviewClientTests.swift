import ATProto
import ATProtoOAuth
import CustomDump
import Dependencies
import Foundation
import Gzip
import HTTPClient
import HTTPTypes
import OpenMusicEventAuthentication
import OpenMusicEventLexicon
import SourceEditing
import Synchronization
import TangledLexicon
import Testing
import XRPCClient

@testable import OpenMusicEventSourceEditing

struct TangledPullReviewClientTests {
    @Test
    func mapsTangledListPullItemToReviewRowWithRawBackup() throws {
        let item = TangledPullListItem(
            uri: try #require(ATProto.URI("at://did:plc:author123/sh.tangled.repo.pull/3pull")),
            cid: "bafyreipull",
            value: TangledPullRecord(
                target: TangledPullRecord.Target(
                    repo: try #require(DID("did:plc:targetrepo")),
                    branch: "main"
                ),
                title: "Update Saturday schedule",
                body: "Move one performance later.",
                rounds: [
                    TangledPullRecord.Round(
                        patchBlob: ATProto.Blob(
                            ref: "bafkreipatch",
                            mimeType: "application/gzip",
                            size: 123
                        ),
                        createdAt: "2026-07-03T12:00:00Z"
                    )
                ],
                source: TangledPullRecord.Source(
                    branch: "ome/proposal-schedule",
                    repo: try #require(DID("did:plc:authorrepo"))
                ),
                createdAt: "2026-07-03T12:01:00Z"
            ),
            state: .open,
            stateUpdatedAt: "2026-07-03T12:02:00Z",
            commentCount: 2
        )

        let review = TangledPullReview(item: item)

        expectNoDifference(
            review,
            TangledPullReview(
                author: "did:plc:author123",
                body: "Move one performance later.",
                commentCount: 2,
                createdAt: "2026-07-03T12:01:00Z",
                patchBlobs: [
                    TangledPullReview.PatchBlob(
                        cid: "bafkreipatch",
                        createdAt: "2026-07-03T12:00:00Z",
                        index: 1,
                        mimeType: "application/gzip",
                        size: 123
                    )
                ],
                sourceBranch: "ome/proposal-schedule",
                sourceRepositoryDID: "did:plc:authorrepo",
                state: "open",
                stateUpdatedAt: "2026-07-03T12:02:00Z",
                targetBranch: "main",
                targetRepositoryDID: "did:plc:targetrepo",
                title: "Update Saturday schedule",
                uri: "at://did:plc:author123/sh.tangled.repo.pull/3pull"
            )
        )
        #expect(review.rawReviewText.contains("patchBlobs:"))
        #expect(review.rawReviewText.contains("cid: bafkreipatch"))
    }

    @Test
    func listBackfillsConstellationBacklinksWhenTangledXRPCMissesPull() async throws {
        let eventID = testEventID("wicked-woods-2026")
        let ownerDID = try #require(DID("did:plc:owner"))
        let authorDID = try #require(DID("did:plc:author"))
        let requests = Mutex<[URL?]>([])

        let reviews = try await withDependencies {
            $0.openMusicEventSourcePatchLocationResolver = OpenMusicEventSourcePatchLocationResolver { request in
                #expect(request.eventID == eventID)
                return SourcePatchLocation(
                    repositoryURL: URL(filePath: "/tmp/wicked-woods-ome"),
                    remote: SourcePatchLocation.Remote(
                        kind: "tangled",
                        reference: "at://did:plc:owner/sh.tangled.repo/wicked-woods-ome",
                        ref: "main"
                    )
                )
            }
            $0.tangledPullReviewListSource = .tangledXRPCWithConstellationBackfill
            $0[Atmosphere.Account.Client.self] = Atmosphere.Account.Client(
                resolveHandle: { handle in
                    Issue.record("Did not expect handle resolution for \(handle.rawValue)")
                    throw UnexpectedAccountResolution.handle(handle.rawValue)
                },
                resolveDID: { did in
                    if did == ownerDID {
                        return (
                            Atmosphere.Account(id: .init(ownerDID), handle: "owner.example"),
                            try didDocument(
                                did: ownerDID,
                                handle: "owner.example",
                                pdsHost: "owner.pds.example"
                            )
                        )
                    } else {
                        #expect(did == authorDID)
                        return (
                            Atmosphere.Account(id: .init(authorDID), handle: "author.example"),
                            try didDocument(
                                did: authorDID,
                                handle: "author.example",
                                pdsHost: "author.pds.example"
                            )
                        )
                    }
                }
            )
            $0[XRPC.Client.self] = .liveValue
            $0.pdsHost = "publisher.pds.example"
            $0.httpClient = HTTPClient { request, _ in
                requests.withLock { $0.append(request.url) }
                let host = request.url?.host
                let path = request.url?.path ?? ""
                let collection = request.url?.queryValue(named: "collection")
                let source = request.url?.queryValue(named: "source")

                switch (host, collection, source) {
                case ("owner.pds.example", "sh.tangled.repo", _)
                    where path.hasSuffix("/com.atproto.repo.listRecords"):
                    return Data(
                        """
                        {
                          "records": [
                            {
                              "uri": "at://did:plc:owner/sh.tangled.repo/3repo",
                              "cid": "bafyreirepo",
                              "value": {
                                "$type": "sh.tangled.repo",
                                "name": "wicked-woods-ome",
                                "repoDid": "did:plc:targetrepo",
                                "knot": "tangled.org",
                                "createdAt": "2026-07-08T12:00:00Z"
                              }
                            }
                          ]
                        }
                        """
                        .utf8
                    )

                case ("api.tangled.org", _, _)
                    where path.hasSuffix("/sh.tangled.repo.listPulls"):
                    return Data(#"{"items":[]}"#.utf8)

                case (
                    "constellation.microcosm.blue",
                    _,
                    "sh.tangled.repo.pull:target.repo"
                ) where path.hasSuffix("/blue.microcosm.links.getBacklinks"):
                    return Data(
                        """
                        {
                          "total": 1,
                          "records": [
                            {
                              "did": "did:plc:author",
                              "collection": "sh.tangled.repo.pull",
                              "rkey": "3pull"
                            }
                          ]
                        }
                        """
                        .utf8
                    )

                case ("author.pds.example", "sh.tangled.repo.pull", _)
                    where path.hasSuffix("/com.atproto.repo.getRecord"):
                    return Data(
                        """
                        {
                          "uri": "at://did:plc:author/sh.tangled.repo.pull/3pull",
                          "cid": "bafyreipull",
                          "value": {
                            "$type": "sh.tangled.repo.pull",
                            "target": {
                              "repo": "did:plc:targetrepo",
                              "branch": "main"
                            },
                            "title": "Add Excision",
                            "body": "Proposed from OME.",
                            "rounds": [
                              {
                                "patchBlob": {
                                  "$type": "blob",
                                  "ref": {"$link": "bafkreipatch"},
                                  "mimeType": "application/gzip",
                                  "size": 123
                                },
                                "createdAt": "2026-07-08T12:01:00Z"
                              }
                            ],
                            "createdAt": "2026-07-08T12:02:00Z"
                          }
                        }
                        """
                        .utf8
                    )

                case (
                    "constellation.microcosm.blue",
                    _,
                    "sh.tangled.repo.pull.status:pull"
                ) where path.hasSuffix("/blue.microcosm.links.getBacklinks"):
                    return Data(#"{"total":0,"records":[]}"#.utf8)

                default:
                    Issue.record("Unexpected request: \(request.url?.absoluteString ?? "<nil>")")
                    return Data("{}".utf8)
                }
            }
        } operation: {
            try await TangledPullReviewClient.openMusicEvent.list(
                OpenMusicEventTangledPullReviewRequest(eventID: eventID)
            )
        }

        expectNoDifference(
            reviews,
            [
                TangledPullReview(
                    author: "did:plc:author",
                    body: "Proposed from OME.",
                    commentCount: 0,
                    createdAt: "2026-07-08T12:02:00Z",
                    patchBlobs: [
                        TangledPullReview.PatchBlob(
                            cid: "bafkreipatch",
                            createdAt: "2026-07-08T12:01:00Z",
                            index: 1,
                            mimeType: "application/gzip",
                            size: 123
                        )
                    ],
                    state: "open",
                    targetBranch: "main",
                    targetRepositoryDID: "did:plc:targetrepo",
                    title: "Add Excision",
                    uri: "at://did:plc:author/sh.tangled.repo.pull/3pull"
                )
            ]
        )
        #expect(
            requests.withLock { urls in
                urls.contains {
                    $0?.host == "constellation.microcosm.blue"
                }
            }
        )
    }

    @Test
    func listUsesConstellationBackfillWithoutCallingTangledXRPC() async throws {
        let eventID = testEventID("wicked-woods-2026")
        let ownerDID = try #require(DID("did:plc:owner"))
        let authorDID = try #require(DID("did:plc:author"))
        let requests = Mutex<[URL?]>([])

        let reviews = try await withDependencies {
            $0.openMusicEventSourcePatchLocationResolver = OpenMusicEventSourcePatchLocationResolver { request in
                #expect(request.eventID == eventID)
                return SourcePatchLocation(
                    repositoryURL: URL(filePath: "/tmp/wicked-woods-ome"),
                    remote: SourcePatchLocation.Remote(
                        kind: "tangled",
                        reference: "woody.fm/wicked-woods-ome",
                        ref: "main"
                    )
                )
            }
            $0.tangledPullReviewListSource = .constellationBackfill
            $0[Atmosphere.Account.Client.self] = Atmosphere.Account.Client(
                resolveHandle: { handle in
                    #expect(handle.rawValue == "woody.fm")
                    return (
                        Atmosphere.Account(id: .init(ownerDID), handle: handle),
                        try didDocument(
                            did: ownerDID,
                            handle: handle,
                            pdsHost: "owner.pds.example"
                        )
                    )
                },
                resolveDID: { did in
                    #expect(did == authorDID)
                    return (
                        Atmosphere.Account(id: .init(authorDID), handle: "author.example"),
                        try didDocument(
                            did: authorDID,
                            handle: "author.example",
                            pdsHost: "author.pds.example"
                        )
                    )
                }
            )
            $0[XRPC.Client.self] = .liveValue
            $0.pdsHost = "publisher.pds.example"
            $0.httpClient = HTTPClient { request, _ in
                requests.withLock { $0.append(request.url) }
                let host = request.url?.host
                let path = request.url?.path ?? ""
                let collection = request.url?.queryValue(named: "collection")
                let source = request.url?.queryValue(named: "source")

                switch (host, collection, source) {
                case ("owner.pds.example", "sh.tangled.repo", _)
                    where path.hasSuffix("/com.atproto.repo.listRecords"):
                    return Data(
                        """
                        {
                          "records": [
                            {
                              "uri": "at://did:plc:owner/sh.tangled.repo/3repo",
                              "cid": "bafyreirepo",
                              "value": {
                                "$type": "sh.tangled.repo",
                                "name": "wicked-woods-ome",
                                "repoDid": "did:plc:targetrepo",
                                "knot": "tangled.org",
                                "createdAt": "2026-07-08T12:00:00Z"
                              }
                            }
                          ]
                        }
                        """
                        .utf8
                    )

                case (
                    "constellation.microcosm.blue",
                    _,
                    "sh.tangled.repo.pull:target.repo"
                ) where path.hasSuffix("/blue.microcosm.links.getBacklinks"):
                    return Data(
                        """
                        {
                          "total": 1,
                          "records": [
                            {
                              "did": "did:plc:author",
                              "collection": "sh.tangled.repo.pull",
                              "rkey": "3pull"
                            }
                          ]
                        }
                        """
                        .utf8
                    )

                case ("author.pds.example", "sh.tangled.repo.pull", _)
                    where path.hasSuffix("/com.atproto.repo.getRecord"):
                    return Data(
                        """
                        {
                          "uri": "at://did:plc:author/sh.tangled.repo.pull/3pull",
                          "cid": "bafyreipull",
                          "value": {
                            "$type": "sh.tangled.repo.pull",
                            "target": {
                              "repo": "did:plc:targetrepo",
                              "branch": "main"
                            },
                            "title": "Add Excision",
                            "body": "Proposed from OME.",
                            "rounds": [
                              {
                                "patchBlob": {
                                  "$type": "blob",
                                  "ref": {"$link": "bafkreipatch"},
                                  "mimeType": "application/gzip",
                                  "size": 123
                                },
                                "createdAt": "2026-07-08T12:01:00Z"
                              }
                            ],
                            "createdAt": "2026-07-08T12:02:00Z"
                          }
                        }
                        """
                        .utf8
                    )

                case (
                    "constellation.microcosm.blue",
                    _,
                    "sh.tangled.repo.pull.status:pull"
                ) where path.hasSuffix("/blue.microcosm.links.getBacklinks"):
                    return Data(#"{"total":0,"records":[]}"#.utf8)

                default:
                    Issue.record("Unexpected request: \(request.url?.absoluteString ?? "<nil>")")
                    return Data("{}".utf8)
                }
            }
        } operation: {
            try await TangledPullReviewClient.openMusicEvent.list(
                OpenMusicEventTangledPullReviewRequest(eventID: eventID)
            )
        }

        #expect(reviews.map(\.title) == ["Add Excision"])
        #expect(
            requests.withLock { urls in
                urls.contains {
                    $0?.host == "constellation.microcosm.blue"
                }
            }
        )
        #expect(
            requests.withLock { urls in
                !urls.contains {
                    $0?.host == "api.tangled.org"
                }
            }
        )
    }

    @Test
    func closeCreatesClosedPullStatusRecord() async throws {
        let review = TangledPullReview(
            author: "did:plc:author123",
            body: "Move one performance later.",
            commentCount: 2,
            createdAt: "2026-07-03T12:01:00Z",
            patchBlobs: [],
            sourceBranch: "ome/proposal-schedule",
            state: "open",
            targetBranch: "main",
            targetRepositoryDID: "did:plc:targetrepo",
            title: "Update Saturday schedule",
            uri: "at://did:plc:author123/sh.tangled.repo.pull/3pull"
        )
        let requests = Mutex([(url: URL?, body: Data?)]())
        let authorizedRequirements = Mutex([OAuth.AuthRequirement]())

        try await withDependencies {
            $0.date.now = Date(timeIntervalSince1970: 1_783_453_261)
            $0[XRPC.Client.self] = .liveValue
            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { requirement in
                authorizedRequirements.withLock { $0.append(requirement) }
            }
            $0.pdsHost = "publisher.pds.example"
            $0.getDefaultSession = { .placeholder }
            $0.httpClient = HTTPClient { request, body in
                requests.withLock {
                    $0.append((url: request.url, body: body))
                }
                return Data(
                    """
                    {
                      "uri": "at://did:plc:placeholder/sh.tangled.repo.pull.status/3status",
                      "cid": "bafyreistatus"
                    }
                    """
                    .utf8
                )
            }
        } operation: {
            try await TangledPullReviewClient.openMusicEvent.close(review)
        }

        let request = try #require(requests.withLock { $0.first })
        #expect(request.url?.host == "publisher.pds.example")
        #expect(request.url?.path.hasSuffix("/com.atproto.repo.createRecord") == true)
        let body = try #require(request.body)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["repo"] as? String == "did:plc:placeholder")
        #expect(json["collection"] as? String == TangledPullStatusRecord.collection.rawValue)
        let record = try #require(json["record"] as? [String: Any])
        #expect(record["$type"] as? String == TangledPullStatusRecord.collection.rawValue)
        #expect(record["pull"] as? String == review.uri)
        #expect(record["status"] as? String == TangledPullStatus.closed.rawValue)
        #expect(record["createdAt"] != nil)
        expectNoDifference(
            authorizedRequirements.withLock { $0 },
            [OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement]
        )
    }

    @Test
    func mergeFetchesPatchFromPullRecordThenWritesMergedStatus() async throws {
        let eventID = testEventID("wicked-woods-2026")
        let ownerDID = try #require(DID("did:plc:owner"))
        let authorDID = try #require(DID("did:plc:author"))
        let patchText = """
        From abc Mon Sep 17 00:00:00 2001
        Subject: [PATCH] Add Excision

        ---
         events/wicked-woods-2026/event.yml | 1 +
         1 file changed, 1 insertion(+)
        """
        let patchBlob = try Data(patchText.utf8).gzipped()
        let review = TangledPullReview(
            author: "did:plc:author",
            body: "Proposed from OME.",
            commentCount: 0,
            createdAt: "2026-07-08T12:02:00Z",
            patchBlobs: [
                TangledPullReview.PatchBlob(
                    cid: "bafkreipatch",
                    createdAt: "2026-07-08T12:01:00Z",
                    index: 1,
                    mimeType: "application/gzip",
                    size: patchBlob.count
                )
            ],
            state: "open",
            targetBranch: "main",
            targetRepositoryDID: "did:plc:targetrepo",
            title: "Add Excision",
            uri: "at://did:plc:author/sh.tangled.repo.pull/3pull"
        )
        let session: OAuth.Session = {
            var grantedPermissions = Set([OAuth.Permission.atproto])
            grantedPermissions.formUnion(
                OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement.permissions
            )
            var session = OAuth.Session.placeholder
            session.scope = OAuth.Scope(
                rawValue: grantedPermissions
                    .map(\.rawValue)
                    .sorted()
                    .joined(separator: " ")
            )
            return OAuth.Session(
                accountID: session.accountID,
                pdsHost: "publisher.pds.example",
                tokenEndpoint: session.tokenEndpoint,
                scope: session.scope,
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                dpopKey: session.dpopKey
            )
        }()
        let now = Date(timeIntervalSince1970: 1_783_453_261)
        let requests = Mutex([(url: URL?, body: Data?, headers: HTTPFields)]())
        let authorizedRequirements = Mutex([OAuth.AuthRequirement]())

        try await withDependencies {
            $0.date = .constant(now)
            $0.defaultPort = 443
            $0.openMusicEventSourcePatchLocationResolver = OpenMusicEventSourcePatchLocationResolver { request in
                #expect(request.eventID == eventID)
                return SourcePatchLocation(
                    repositoryURL: URL(filePath: "/tmp/wicked-woods-ome"),
                    remote: SourcePatchLocation.Remote(
                        kind: "tangled",
                        reference: "woody.fm/wicked-woods-ome",
                        ref: "main"
                    )
                )
            }
            $0[Atmosphere.Account.Client.self] = Atmosphere.Account.Client(
                resolveHandle: { handle in
                    #expect(handle.rawValue == "woody.fm")
                    return (
                        Atmosphere.Account(id: .init(ownerDID), handle: handle),
                        try didDocument(
                            did: ownerDID,
                            handle: handle,
                            pdsHost: "owner.pds.example"
                        )
                    )
                },
                resolveDID: { did in
                    switch did {
                    case authorDID:
                        return (
                            Atmosphere.Account(
                                id: .init(authorDID),
                                handle: "author.example"
                            ),
                            try didDocument(
                                did: authorDID,
                                handle: "author.example",
                                pdsHost: "author.pds.example"
                            )
                        )
                    case ownerDID:
                        return (
                            Atmosphere.Account(id: .init(ownerDID), handle: "woody.fm"),
                            try didDocument(
                                did: ownerDID,
                                handle: "woody.fm",
                                pdsHost: "owner.pds.example"
                            )
                        )
                    default:
                        Issue.record("Unexpected DID resolution: \(did)")
                        return (
                            Atmosphere.Account(id: .init(did), handle: "unexpected.example"),
                            try didDocument(
                                did: did,
                                handle: "unexpected.example",
                                pdsHost: "unexpected.pds.example"
                            )
                        )
                    }
                }
            )
            $0[XRPC.Client.self] = .liveValue
            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { requirement in
                authorizedRequirements.withLock { $0.append(requirement) }
            }
            $0.pdsHost = "publisher.pds.example"
            $0.getDefaultSession = { session }
            $0.getOptionalDefaultSession = { session }
            $0.oauthAppManifest = OpenMusicEventOAuth.appManifest
            $0.p256Sign = { _, _ in Data(repeating: 0xAB, count: 64) }
            $0.uuid = .constant(UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!)
            $0.xrpcAuthorizationGate = .defaultSessionAuthorization
            $0.httpClient = .liveValue
            $0.requestInterceptors = []
            $0.responseInterceptors = []
            $0.errorInterceptors = []
            $0.dataForURL = { request, body in
                requests.withLock {
                    $0.append((url: request.url, body: body, headers: request.headerFields))
                }
                let host = request.url?.host
                let path = request.url?.path ?? ""
                let collection = request.url?.queryValue(named: "collection")
                func ok(_ data: Data) -> (Data, HTTPResponse) {
                    (data, HTTPResponse(status: .ok))
                }

                switch (host, collection) {
                case ("author.pds.example", "sh.tangled.repo.pull")
                    where path.hasSuffix("/com.atproto.repo.getRecord"):
                    return ok(Data(
                        """
                        {
                          "uri": "at://did:plc:author/sh.tangled.repo.pull/3pull",
                          "cid": "bafyreipull",
                          "value": {
                            "$type": "sh.tangled.repo.pull",
                            "target": {
                              "repo": "did:plc:targetrepo",
                              "branch": "main"
                            },
                            "title": "Add Excision",
                            "body": "Proposed from OME.",
                            "rounds": [
                              {
                                "patchBlob": {
                                  "$type": "blob",
                                  "ref": {"$link": "bafkreioldpatch"},
                                  "mimeType": "application/gzip",
                                  "size": 12
                                },
                                "createdAt": "2026-07-08T11:00:00Z"
                              },
                              {
                                "patchBlob": {
                                  "$type": "blob",
                                  "ref": {"$link": "bafkreipatch"},
                                  "mimeType": "application/gzip",
                                  "size": \(patchBlob.count)
                                },
                                "createdAt": "2026-07-08T12:01:00Z"
                              }
                            ],
                            "createdAt": "2026-07-08T12:02:00Z"
                          }
                        }
                        """
                        .utf8
                    ))

                case ("owner.pds.example", "sh.tangled.repo")
                    where path.hasSuffix("/com.atproto.repo.listRecords"):
                    return ok(Data(
                        """
                        {
                          "records": [
                            {
                              "uri": "at://did:plc:owner/sh.tangled.repo/3repo",
                              "cid": "bafyreirepo",
                              "value": {
                                "$type": "sh.tangled.repo",
                                "name": "wicked-woods-ome",
                                "repoDid": "did:plc:targetrepo",
                                "knot": "tangled.org",
                                "createdAt": "2026-07-08T12:00:00Z"
                              }
                            }
                          ]
                        }
                        """
                        .utf8
                    ))

                case ("author.pds.example", _)
                    where path.hasSuffix("/com.atproto.sync.getBlob"):
                    return ok(patchBlob)

                case ("publisher.pds.example", _)
                    where path.hasSuffix("/com.atproto.server.getServiceAuth"):
                    #expect(request.url?.queryValue(named: "aud") == "did:web:tangled.org")
                    #expect(request.url?.queryValue(named: "lxm") == "sh.tangled.repo.merge")
                    return ok(Data(#"{"token":"service-auth-token"}"#.utf8))

                case ("tangled.org", _)
                    where path.hasSuffix("/sh.tangled.repo.merge"):
                    return ok(Data("{}".utf8))

                case ("publisher.pds.example", _)
                    where path.hasSuffix("/com.atproto.repo.createRecord"):
                    return ok(Data(
                        """
                        {
                          "uri": "at://did:plc:placeholder/sh.tangled.repo.pull.status/3status",
                          "cid": "bafyreistatus"
                        }
                        """
                        .utf8
                    ))

                default:
                    Issue.record("Unexpected request: \(request.url?.absoluteString ?? "<nil>")")
                    return ok(Data("{}".utf8))
                }
            }
        } operation: {
            try await TangledPullReviewClient.openMusicEvent.merge(
                OpenMusicEventTangledPullReviewMergeRequest(
                    eventID: eventID,
                    review: review
                )
            )
        }

        let serviceAuthRequest = try #require(
            requests.withLock { requests in
                requests.first {
                    $0.url?.host == "publisher.pds.example"
                        && $0.url?.path.hasSuffix("/com.atproto.server.getServiceAuth") == true
                }
            }
        )
        #expect(serviceAuthRequest.url?.queryValue(named: "aud") == "did:web:tangled.org")
        #expect(serviceAuthRequest.url?.queryValue(named: "lxm") == "sh.tangled.repo.merge")
        #expect(serviceAuthRequest.headers[.authorization] == "DPoP \(session.accessToken.rawValue)")
        #expect(serviceAuthRequest.headers[HTTPField.Name("DPoP")!] != nil)

        let mergeRequest = try #require(
            requests.withLock { requests in
                requests.first {
                    $0.url?.host == "tangled.org"
                        && $0.url?.path.hasSuffix("/sh.tangled.repo.merge") == true
                }
            }
        )
        #expect(mergeRequest.headers[.authorization] == "Bearer service-auth-token")
        #expect(mergeRequest.headers[HTTPField.Name("DPoP")!] == nil)
        let mergeBody = try #require(mergeRequest.body)
        let mergeJSON = try #require(
            JSONSerialization.jsonObject(with: mergeBody) as? [String: Any]
        )
        #expect(mergeJSON["did"] as? String == "did:plc:owner")
        #expect(mergeJSON["name"] as? String == "wicked-woods-ome")
        #expect(mergeJSON["branch"] as? String == "main")
        #expect(mergeJSON["patch"] as? String == patchText)
        #expect(mergeJSON["commitMessage"] as? String == "Add Excision")
        #expect(mergeJSON["commitBody"] as? String == "Proposed from OME.")

        let statusRequest = try #require(
            requests.withLock { requests in
                requests.first {
                    $0.url?.host == "publisher.pds.example"
                        && $0.url?.path.hasSuffix("/com.atproto.repo.createRecord") == true
                }
            }
        )
        let statusBody = try #require(statusRequest.body)
        let statusJSON = try #require(
            JSONSerialization.jsonObject(with: statusBody) as? [String: Any]
        )
        #expect(statusJSON["repo"] as? String == "did:plc:placeholder")
        #expect(statusJSON["collection"] as? String == TangledPullStatusRecord.collection.rawValue)
        let record = try #require(statusJSON["record"] as? [String: Any])
        #expect(record["$type"] as? String == TangledPullStatusRecord.collection.rawValue)
        #expect(record["pull"] as? String == review.uri)
        #expect(record["status"] as? String == TangledPullStatus.merged.rawValue)
        #expect(record["createdAt"] != nil)

        #expect(
            requests.withLock { requests in
                requests.contains {
                    $0.url?.host == "author.pds.example"
                        && $0.url?.path.hasSuffix("/com.atproto.sync.getBlob") == true
                        && $0.url?.queryValue(named: "cid") == "bafkreipatch"
                }
            }
        )
        expectNoDifference(
            authorizedRequirements.withLock { $0 },
            [OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement]
        )
    }

    @Test
    func deleteRemovesPullRecord() async throws {
        let review = TangledPullReview(
            author: "did:plc:author123",
            body: "Move one performance later.",
            commentCount: 2,
            createdAt: "2026-07-03T12:01:00Z",
            patchBlobs: [],
            sourceBranch: "ome/proposal-schedule",
            state: "open",
            targetBranch: "main",
            targetRepositoryDID: "did:plc:targetrepo",
            title: "Update Saturday schedule",
            uri: "at://did:plc:author123/sh.tangled.repo.pull/3pull"
        )
        let requests = Mutex([(url: URL?, body: Data?)]())
        let authorizedRequirements = Mutex([OAuth.AuthRequirement]())

        try await withDependencies {
            $0[XRPC.Client.self] = .liveValue
            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { requirement in
                authorizedRequirements.withLock { $0.append(requirement) }
            }
            $0.pdsHost = "publisher.pds.example"
            $0.getDefaultSession = { .placeholder }
            $0.httpClient = HTTPClient { request, body in
                requests.withLock {
                    $0.append((url: request.url, body: body))
                }
                return Data("{}".utf8)
            }
        } operation: {
            try await TangledPullReviewClient.openMusicEvent.delete(review)
        }

        let request = try #require(requests.withLock { $0.first })
        #expect(request.url?.host == "publisher.pds.example")
        #expect(request.url?.path.hasSuffix("/com.atproto.repo.deleteRecord") == true)
        let body = try #require(request.body)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["repo"] as? String == "did:plc:author123")
        #expect(json["collection"] as? String == TangledCollection.pull.rawValue)
        #expect(json["rkey"] as? String == "3pull")
        expectNoDifference(
            authorizedRequirements.withLock { $0 },
            [OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement]
        )
    }
}

private func testEventID(_ string: String) -> OME.Event.ID {
    OME.Event.ID(
        organizerID: OME.Organizer.ID("did:web:example.com")!,
        eventID: OME.ID<OME.Event>(.init(string))
    )
}

private func didDocument(
    did: DID,
    handle: Atmosphere.Account.Handle,
    pdsHost: String
) throws -> DID.Document {
    try JSONDecoder().decode(
        DID.Document.self,
        from: Data(
            """
            {
              "id": "\(did.description)",
              "alsoKnownAs": ["at://\(handle.rawValue)"],
              "verificationMethod": [],
              "service": [
                {
                  "id": "#atproto_pds",
                  "type": "AtprotoPersonalDataServer",
                  "serviceEndpoint": "https://\(pdsHost)"
                }
              ]
            }
            """
            .utf8
        )
    )
}

private extension URL {
    func queryValue(named name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}

private enum UnexpectedAccountResolution: Error {
    case handle(String)
}
