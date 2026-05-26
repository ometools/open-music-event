import ATProto
import Dependencies
import DependenciesTestSupport
import Foundation
import Gzip
import HTTPClient
import HTTPTypes
import OpenMusicEventSourceClone
import SourceEditing
import Testing
import XRPCClient

@testable import OpenMusicEventSourceEditing

struct TangledSourcePatchPublisherTests {
    @Test
    func publishUploadsFormatPatchAndCompatibilityRecord() async throws {
        let ownerDID = try #require(DID("did:plc:owner123"))
        let requestRecorder = HTTPRequestRecorder()
        let repositoryURL = FileManager.default.temporaryDirectory
            .appending(path: "TangledSourcePatchPublisherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: repositoryURL.appending(path: ".git/refs/heads"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        let sourceSHA = "abcdefabcdefabcdefabcdefabcdefabcdefabcd"
        try "ref: refs/heads/main\n".write(
            to: repositoryURL.appending(path: ".git/HEAD"),
            atomically: true,
            encoding: .utf8
        )
        try "\(sourceSHA)\n".write(
            to: repositoryURL.appending(path: ".git/refs/heads/main"),
            atomically: true,
            encoding: .utf8
        )

        let publication = try await withDependencies {
            $0.date.now = Date(timeIntervalSince1970: 1_779_800_000)
            $0[Atmosphere.Account.Client.self] = .testClient(
                did: ownerDID,
                handle: "woody.fm",
                pdsHost: "owner.pds.example"
            )
            $0[XRPC.Client.self] = .liveValue
            $0.pdsHost = "publisher.pds.example"
            $0.httpClient = HTTPClient { request, body in
                await requestRecorder.record(request, body)
                switch request.url?.host {
                case "owner.pds.example":
                    return Data(
                        """
                        {
                          "records": [
                            {
                              "uri": "at://did:plc:owner123/sh.tangled.repo/3repo",
                              "cid": "bafyreifakerepo",
                              "value": {
                                "$type": "sh.tangled.repo",
                                "name": "wicked-woods-ome",
                                "repoDid": "did:plc:targetrepo",
                                "knot": "tangled.org",
                                "createdAt": "2026-05-26T17:30:42Z"
                              }
                            }
                          ]
                        }
                        """
                        .utf8
                    )

                case "publisher.pds.example":
                    if request.url?.path.hasSuffix("/com.atproto.repo.uploadBlob") == true {
                        return Data(
                            """
                            {
                              "blob": {
                                "$type": "blob",
                                "ref": {"$link": "bafkreipatch"},
                                "mimeType": "application/gzip",
                                "size": 123
                              }
                            }
                            """
                            .utf8
                        )
                    }
                    return Data(
                        """
                        {
                          "uri": "at://did:plc:placeholder/sh.tangled.repo.pull/3pull",
                          "cid": "bafyreipull"
                        }
                        """
                        .utf8
                    )

                default:
                    throw TestAccountClientFailure.unexpectedResolution
                }
            }
        } operation: {
            try await TangledSourcePatchPublisher().publish(
                PreparedSourcePatch(
                    request: SourcePatchPublishRequest(
                        location: SourcePatchLocation(
                            repositoryURL: repositoryURL,
                            remote: SourcePatchLocation.Remote(
                                kind: "tangled",
                                reference: "woody.fm/wicked-woods-ome",
                                ref: "main"
                            )
                        ),
                        patch: SourcePatch(
                            fileChanges: [
                                SourcePatchFileChange(
                                    path: "events/2025/event.yml",
                                    kind: .modified,
                                    oldContents: Data("name: Old\n".utf8),
                                    newContents: Data("name: New\n".utf8)
                                )
                            ]
                        )
                    ),
                    workingTree: SourceWorkingTree(
                        originalRepositoryURL: repositoryURL,
                        originalURL: repositoryURL,
                        relativePath: nil,
                        workingRepositoryURL: repositoryURL,
                        workingURL: repositoryURL
                    )
                )
            )
        }

        #expect(publication.sourceChangeURL?.absoluteString == "https://tangled.org/woody.fm/wicked-woods-ome/pulls")

        let requests = await requestRecorder.requests
        let uploadRequest = try #require(
            requests.first { $0.url?.path.hasSuffix("/com.atproto.repo.uploadBlob") == true }
        )
        let uploadBody = try #require(uploadRequest.body)
        let uploadedPatch = String(decoding: try uploadBody.gunzipped(), as: UTF8.self)
        #expect(uploadedPatch.hasPrefix("From \(sourceSHA) Mon Sep 17 00:00:00 2001\n"))
        #expect(uploadedPatch.contains("Subject: [PATCH] Update event source\n"))
        #expect(uploadedPatch.contains("diff --git a/events/2025/event.yml b/events/2025/event.yml\n"))

        let createRecordRequest = try #require(
            requests.first { $0.url?.path.hasSuffix("/com.atproto.repo.createRecord") == true }
        )
        let createRecordBody = try #require(createRecordRequest.body)
        let createRecordJSON = try #require(
            JSONSerialization.jsonObject(with: createRecordBody)
                as? [String: Any]
        )
        let record = try #require(createRecordJSON["record"] as? [String: Any])
        #expect(record["$type"] as? String == "sh.tangled.repo.pull")
        #expect(record["patch"] as? String == uploadedPatch)
        #expect(record["targetBranch"] as? String == "main")
        #expect(record["targetRepo"] as? String == "at://did:plc:owner123/sh.tangled.repo/3repo")
        #expect(record["pullId"] as? Int == 1_779_800_000_000)
        #expect(record["patchBlob"] != nil)

        let target = try #require(record["target"] as? [String: Any])
        #expect(target["branch"] as? String == "main")
        #expect(target["repo"] as? String == "at://did:plc:owner123/sh.tangled.repo/3repo")
        #expect(target["repoDid"] as? String == "did:plc:targetrepo")

        let source = try #require(record["source"] as? [String: Any])
        #expect(source["branch"] as? String == "main")
        #expect(source["sha"] as? String == sourceSHA)

        let rounds = try #require(record["rounds"] as? [[String: Any]])
        #expect(rounds.count == 1)
        #expect(rounds.first?["patchBlob"] != nil)
    }

    @Test
    func resolvesTargetRepositoryToTangledRepoDID() async throws {
        let ownerDID = try #require(DID("did:plc:owner123"))
        let requestRecorder = HTTPRequestRecorder()

        let target = try await withDependencies {
            $0[Atmosphere.Account.Client.self] = .testClient(
                did: ownerDID,
                handle: "woody.fm",
                pdsHost: "owner.pds.example"
            )
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { request, body in
                await requestRecorder.record(request, body)
                return Data(
                    """
                    {
                      "records": [
                        {
                          "uri": "at://did:plc:owner123/sh.tangled.repo/3wrong",
                          "cid": "bafyreifakewrong",
                          "value": {
                            "$type": "sh.tangled.repo",
                            "name": "other-repo",
                            "repoDid": "did:plc:wrongrepo",
                            "knot": "tangled.org",
                            "createdAt": "2026-05-26T17:30:42Z"
                          }
                        },
                        {
                          "uri": "at://did:plc:owner123/sh.tangled.repo/3repo",
                          "cid": "bafyreifakerepo",
                          "value": {
                            "$type": "sh.tangled.repo",
                            "name": "wicked-woods-ome",
                            "repoDid": "did:plc:targetrepo",
                            "knot": "tangled.org",
                            "createdAt": "2026-05-26T17:30:42Z"
                          }
                        }
                      ]
                    }
                    """
                    .utf8
                )
            }
        } operation: {
            try await TangledSourcePatchPublisher().targetRepositoryDID(
                TangledRepositoryReference(
                    host: "tangled.org",
                    owner: "woody.fm",
                    repository: "wicked-woods-ome"
                )
            )
        }

        #expect(target == "did:plc:targetrepo")
        let requests = await requestRecorder.requests
        #expect(requests.count == 1)
        #expect(
            requests.first?.url?.absoluteString
                == "https://owner.pds.example/xrpc/com.atproto.repo.listRecords?repo=did:plc:owner123&collection=sh.tangled.repo&limit=100"
        )
        #expect(requests.first?.body == nil)
    }

    @Test
    func publishingFailsBeforeUploadingWhenRepoRecordCannotBeResolved() async throws {
        let ownerDID = try #require(DID("did:plc:owner123"))
        let requestRecorder = HTTPRequestRecorder()

        let error = await #expect(throws: TangledSourcePatchPublisherError.self) {
            try await withDependencies {
                $0[Atmosphere.Account.Client.self] = .testClient(
                    did: ownerDID,
                    handle: "woody.fm",
                    pdsHost: "owner.pds.example"
                )
                $0[XRPC.Client.self] = .liveValue
                $0.httpClient = HTTPClient { request, body in
                    await requestRecorder.record(request, body)
                    return Data(
                        """
                        {
                          "records": []
                        }
                        """
                        .utf8
                    )
                }
            } operation: {
                try await TangledSourcePatchPublisher().publish(
                    PreparedSourcePatch(
                        request: SourcePatchPublishRequest(
                            location: SourcePatchLocation(
                                repositoryURL: URL(fileURLWithPath: "/tmp/source"),
                                remote: SourcePatchLocation.Remote(
                                    kind: "tangled",
                                    reference: "woody.fm/wicked-woods-ome",
                                    ref: "main"
                                )
                            ),
                            patch: SourcePatch(
                                fileChanges: [
                                    SourcePatchFileChange(
                                        path: "events/2025/event.yml",
                                        kind: .modified,
                                        oldContents: Data("name: Old\n".utf8),
                                        newContents: Data("name: New\n".utf8)
                                    )
                                ]
                            )
                        ),
                        workingTree: SourceWorkingTree(
                            originalRepositoryURL: URL(fileURLWithPath: "/tmp/source"),
                            originalURL: URL(fileURLWithPath: "/tmp/source"),
                            relativePath: nil,
                            workingRepositoryURL: URL(fileURLWithPath: "/tmp/working"),
                            workingURL: URL(fileURLWithPath: "/tmp/working")
                        )
                    )
                )
            }
        }

        #expect(
            error == .repositoryRecordNotFound(
                owner: "did:plc:owner123",
                repository: "wicked-woods-ome"
            )
        )
        #expect(await requestRecorder.requests.count == 1)
    }
}

private actor HTTPRequestRecorder {
    struct Request: Sendable {
        var url: URL?
        var body: Data?
    }

    private(set) var requests: [Request] = []

    func record(_ request: HTTPRequest, _ body: Data?) {
        requests.append(Request(url: request.url, body: body))
    }
}

private enum TestAccountClientFailure: Error {
    case unexpectedResolution
}

private extension Atmosphere.Account.Client {
    static func testClient(
        did: DID,
        handle: Atmosphere.Account.Handle,
        pdsHost: String
    ) -> Self {
        Self(
            resolveHandle: { resolvedHandle in
                guard resolvedHandle == handle else {
                    throw TestAccountClientFailure.unexpectedResolution
                }
                return (
                    Atmosphere.Account(id: .init(did), handle: handle),
                    try didDocument(did: did, handle: handle, pdsHost: pdsHost)
                )
            },
            resolveDID: { resolvedDID in
                guard resolvedDID == did else {
                    throw TestAccountClientFailure.unexpectedResolution
                }
                return (
                    Atmosphere.Account(id: .init(did), handle: handle),
                    try didDocument(did: did, handle: handle, pdsHost: pdsHost)
                )
            }
        )
    }
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
