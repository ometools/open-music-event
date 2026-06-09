import ATProto
import ATProtoOAuth
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import Gzip
import HTTPClient
import HTTPTypes
import OpenMusicEventSourceClone
import SourceEditing
import SourceControlClient
import Synchronization
import Testing
import XRPCClient

@testable import OpenMusicEventSourceEditing

struct TangledSourcePatchPublisherTests {
    @Test
    func smallPullRecordIncludesInlinePatchCompatibilityField() throws {
        let record = TangledRepoPullRecord(
            body: "Body",
            createdAt: "2026-05-28T00:00:00Z",
            patch: "diff --git a/event.yml b/event.yml\n",
            patchBlob: ATProto.Blob(
                ref: "bafkreipatch",
                mimeType: "application/gzip",
                size: 123
            ),
            pullID: 1_779_800_000_000,
            rounds: [
                TangledRepoPullRecord.Round(
                    createdAt: "2026-05-28T00:00:00Z",
                    patchBlob: ATProto.Blob(
                        ref: "bafkreipatch",
                        mimeType: "application/gzip",
                        size: 123
                    )
                )
            ],
            source: TangledRepoPullRecord.Source(
                branch: "ome/proposal-test",
                sha: "abcdefabcdefabcdefabcdefabcdefabcdefabcd"
            ),
            target: TangledRepoPullRecord.Target(
                branch: "main",
                repo: "did:plc:targetrepo",
                repoDID: "did:plc:targetrepo"
            ),
            title: "Update event source"
        )

        let json = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
                as? [String: Any]
        )

        #expect(json["$type"] as? String == TangledRepoPullRecord.collection)
        #expect(json["patch"] as? String == "diff --git a/event.yml b/event.yml\n")
        #expect(json["patchBlob"] != nil)
        let rounds = try #require(json["rounds"] as? [[String: Any]])
        #expect(!rounds.isEmpty)
        #expect(rounds.first?["patchBlob"] != nil)
        let target = try #require(json["target"] as? [String: Any])
        let targetRepo = try #require(target["repo"] as? String)
        expectNoDifference(targetRepo, "did:plc:targetrepo")
        #expect(DID(targetRepo) != nil)
    }

    @Test
    func getRecordRequestBuildsPDSReadbackQuery() throws {
        let request = TangledGetRecordRequest<TangledRepositoryRecord>(
            repo: "did:plc:publisher",
            collection: TangledRepoPullRecord.collection,
            rkey: "3pull",
            cid: "bafyreipull",
            pdsHost: "publisher.pds.example"
        )

        #expect(
            request.queryItems
                == [
                    URLQueryItem(name: "repo", value: "did:plc:publisher"),
                    URLQueryItem(name: "collection", value: TangledRepoPullRecord.collection),
                    URLQueryItem(name: "rkey", value: "3pull"),
                    URLQueryItem(name: "cid", value: "bafyreipull"),
                ]
        )
        #expect(
            request.routing
                == XRPC.Routing(
                    unauthenticated: .host("publisher.pds.example"),
                    authenticated: .host("publisher.pds.example")
                )
        )
    }

    @Test
    func publishUploadsLargePatchBlobWithoutInlinePatch() async throws {
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
        let branchName = BranchName(
            rawValue: "ome/proposal-00000000-0000-0000-0000-000000000042"
        )
        let commitID = CommitID(rawValue: "fedcbafedcbafedcbafedcbafedcbafedcbafedc")
        let credentials = Credentials(
            ssh: SSHCredentials(
                publicKey: "ssh-ed25519 public-key Open Music Event",
                privateKey: "private-key"
            )
        )
        let openRequests = Mutex([URL]())
        let createBranchRequests = Mutex([CreateBranchRequest]())
        let stageRequests = Mutex([StageRequest]())
        let commitRequests = Mutex([CommitRequest]())
        let pushRequests = Mutex([PushRequest]())
        let largeEventContents = "name: New\n"
            + String(repeating: "description: A long proposal patch line.\n", count: 8_000)

        let publication = try await withDependencies {
            $0.date.now = Date(timeIntervalSince1970: 1_779_800_000)
            $0.uuid = .constant(
                try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000042"))
            )
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
            $0.sourceControl = SourceControlClient(
                clone: { request in Repository(url: request.destinationURL) },
                open: { url in
                    openRequests.withLock { $0.append(url) }
                    return Repository(url: url)
                },
                fetch: { _ in },
                checkout: { _ in },
                createBranch: { request in
                    createBranchRequests.withLock { $0.append(request) }
                    return Branch(name: request.name)
                },
                status: { _ in [] },
                stage: { request in
                    stageRequests.withLock { $0.append(request) }
                },
                commit: { request in
                    commitRequests.withLock { $0.append(request) }
                    return Commit(id: commitID)
                },
                push: { request in
                    pushRequests.withLock { $0.append(request) }
                }
            )
            $0.tangledSSHCredentials = TangledSSHCredentialsClient {
                credentials
            }
        } operation: {
            try await TangledSourcePatchPublisher().publish(
                PreparedSourcePatch(
                    request: SourcePatchPublishRequest(
                        location: SourcePatchLocation(
                            repositoryURL: repositoryURL,
                            remote: SourcePatchLocation.Remote(
                                kind: "tangled",
                                reference: "tangled.org/woody.fm/wicked-woods-ome",
                                ref: "main"
                            )
                        ),
                        patch: SourcePatch(
                            fileChanges: [
                                SourcePatchFileChange(
                                    path: "events/2025/event.yml",
                                    kind: .modified,
                                    oldContents: Data("name: Old\n".utf8),
                                    newContents: Data(largeEventContents.utf8)
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
        #expect(openRequests.withLock { $0.map(\.standardizedFileURL) } == [repositoryURL.standardizedFileURL])
        let createBranchRequest = try #require(createBranchRequests.withLock { $0.first })
        #expect(createBranchRequest.name == branchName)
        #expect(createBranchRequest.startPoint == "HEAD")
        #expect(createBranchRequest.checkout)
        let stageRequest = try #require(stageRequests.withLock { $0.first })
        #expect(stageRequest.paths == ["events/2025/event.yml"])
        let commitRequest = try #require(commitRequests.withLock { $0.first })
        #expect(commitRequest.message == "Update event source")
        #expect(commitRequest.author.name == "Open Music Event")
        #expect(commitRequest.author.email == "noreply@openmusicevent.app")
        let pushRequest = try #require(pushRequests.withLock { $0.first })
        #expect(pushRequest.localBranch == branchName)
        #expect(pushRequest.remoteBranch == branchName)
        let repositoryReference = try TangledRepositoryReference(
            parsing: "tangled.org/woody.fm/wicked-woods-ome"
        )
        #expect(pushRequest.credentials == repositoryReference.sourceControlCredentials(credentials))

        let requests = await requestRecorder.requests
        let uploadRequest = try #require(
            requests.first { $0.url?.path.hasSuffix("/com.atproto.repo.uploadBlob") == true }
        )
        let uploadBody = try #require(uploadRequest.body)
        let uploadedPatch = String(decoding: try uploadBody.gunzipped(), as: UTF8.self)
        #expect(uploadedPatch.utf8.count > 256_000)
        #expect(uploadedPatch.hasPrefix("From \(commitID.rawValue) Mon Sep 17 00:00:00 2001\n"))
        #expect(uploadedPatch.contains("Subject: [PATCH] Update event source\n"))
        #expect(uploadedPatch.contains("diff --git a/events/2025/event.yml b/events/2025/event.yml\n"))

        let createRecordRequest = try #require(
            requests.first { $0.url?.path.hasSuffix("/com.atproto.repo.createRecord") == true }
        )
        let uploadRequestIndex = try #require(
            requests.firstIndex { $0.url?.path.hasSuffix("/com.atproto.repo.uploadBlob") == true }
        )
        let createRecordRequestIndex = try #require(
            requests.firstIndex { $0.url?.path.hasSuffix("/com.atproto.repo.createRecord") == true }
        )
        #expect(uploadRequestIndex < createRecordRequestIndex)
        let createRecordBody = try #require(createRecordRequest.body)
        #expect(createRecordBody.count < 32_000)
        let createRecordJSON = try #require(
            JSONSerialization.jsonObject(with: createRecordBody)
                as? [String: Any]
        )
        let record = try #require(createRecordJSON["record"] as? [String: Any])
        #expect(record["$type"] as? String == "sh.tangled.repo.pull")
        #expect(record["body"] as? String == "")
        #expect(record["patch"] == nil)
        #expect(record["targetBranch"] as? String == "main")
        let legacyTargetRepo = try #require(record["targetRepo"] as? String)
        expectNoDifference(legacyTargetRepo, "did:plc:targetrepo")
        #expect(record["pullId"] as? Int == 1_779_800_000_000)
        #expect(record["patchBlob"] != nil)

        let target = try #require(record["target"] as? [String: Any])
        #expect(target["branch"] as? String == "main")
        let targetRepo = try #require(target["repo"] as? String)
        expectNoDifference(targetRepo, "did:plc:targetrepo")
        #expect(DID(targetRepo) != nil)
        #expect(target["repoDid"] as? String == "did:plc:targetrepo")

        let source = try #require(record["source"] as? [String: Any])
        #expect(source["branch"] as? String == branchName.rawValue)
        #expect(source["sha"] as? String == commitID.rawValue)

        let rounds = try #require(record["rounds"] as? [[String: Any]])
        #expect(!rounds.isEmpty)
        #expect(rounds.count == 1)
        #expect(rounds.first?["patchBlob"] != nil)
    }

    @Test
    func livePDSReadbackCreatesProposalRecordWhenConfigured() async throws {
        guard let configuration = try LiveTangledPDSReadbackConfiguration.loadFromEnvironment()
        else { return }

        let createdAtDate = Date()
        let createdAt = ISO8601DateFormatter().string(from: createdAtDate)
        let uniqueID = UUID().uuidString.lowercased()
        let sourceBranch = configuration.sourceBranch ?? "ome/live-pds-readback-\(uniqueID)"
        let sourceSHA = configuration.sourceSHA
            ?? "0000000000000000000000000000000000000000"
        let patchText = """
        From \(sourceSHA) Mon Sep 17 00:00:00 2001
        From: Open Music Event <noreply@openmusicevent.app>
        Date: Thu, 28 May 2026 00:00:00 +0000
        Subject: [PATCH] Live PDS readback smoke test

        ---

        diff --git a/ome-live-readback.txt b/ome-live-readback.txt
        new file mode 100644
        index 0000000..1111111
        --- /dev/null
        +++ b/ome-live-readback.txt
        @@ -0,0 +1 @@
        +\(uniqueID)
        -- 
        Open Music Event

        """
        let patchData = Data(patchText.utf8)

        let patchBlob = try await configuration.withLiveDependencies {
            try await uploadLivePatchBlob(patchData)
        }
        let record = TangledRepoPullRecord(
            body: "Live PDS readback smoke test from Open Music Event.",
            createdAt: createdAt,
            patch: patchText,
            patchBlob: patchBlob,
            pullID: Int64((createdAtDate.timeIntervalSince1970 * 1000).rounded()),
            rounds: [
                TangledRepoPullRecord.Round(
                    createdAt: createdAt,
                    patchBlob: patchBlob
                )
            ],
            source: TangledRepoPullRecord.Source(
                branch: sourceBranch,
                sha: sourceSHA
            ),
            target: TangledRepoPullRecord.Target(
                branch: configuration.targetBranch,
                repo: configuration.targetRepoDID,
                repoDID: configuration.targetRepoDID
            ),
            title: "Live PDS readback smoke test"
        )

        let created = try await configuration.withLiveDependencies {
            @Dependency(XRPC.Client.self) var xrpcClient
            return try await xrpcClient.run(
                TangledCreateRecordRequest(
                    input: TangledCreateRecordInput(
                        repo: configuration.session.accountID.rawValue.description,
                        collection: TangledRepoPullRecord.collection,
                        record: record
                    ),
                    authorizationPolicy: .required(TangledOAuthRequirements.proposalAuthRequirement)
                )
            )
        }

        let rkey = try #require(created.uri.rkey?.rawValue)
        let readback = try await configuration.withLiveDependencies {
            @Dependency(XRPC.Client.self) var xrpcClient
            return try await xrpcClient.run(
                TangledGetRecordRequest<TangledPullReadbackRecord>(
                    repo: configuration.session.accountID.rawValue.description,
                    collection: TangledRepoPullRecord.collection,
                    rkey: rkey,
                    pdsHost: configuration.session.pdsHost
                )
            )
        }

        #expect(readback.uri == created.uri)
        #expect(readback.value.type == TangledRepoPullRecord.collection)
        #expect(readback.value.title == "Live PDS readback smoke test")
        #expect(readback.value.patch == patchText)
        #expect(readback.value.patchBlob.ref == patchBlob.ref)
        #expect(readback.value.target.repo == configuration.targetRepoDID)
        #expect(readback.value.target.repoDID == configuration.targetRepoDID)
        #expect(readback.value.source?.branch == sourceBranch)
        #expect(readback.value.source?.sha == sourceSHA)
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
        let repositoryURL = FileManager.default.temporaryDirectory
            .appending(path: "TangledSourcePatchPublisherMissingRepo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: repositoryURL.appending(path: ".git"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

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
                            originalRepositoryURL: repositoryURL,
                            originalURL: repositoryURL,
                            relativePath: nil,
                            workingRepositoryURL: repositoryURL,
                            workingURL: repositoryURL
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

    @Test
    func publishingFailsBeforeNetworkWritesForNonGitWorkingTree() async throws {
        let requestRecorder = HTTPRequestRecorder()
        let repositoryURL = FileManager.default.temporaryDirectory
            .appending(path: "TangledSourcePatchPublisherNonGit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: repositoryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        let error = await #expect(throws: TangledSourcePatchPublisherError.self) {
            try await withDependencies {
                $0.httpClient = HTTPClient { request, body in
                    await requestRecorder.record(request, body)
                    return Data()
                }
                $0.sourceControl = SourceControlClient(
                    clone: { request in Repository(url: request.destinationURL) },
                    open: { url in
                        Issue.record("Unexpected source-control open: \(url)")
                        return Repository(url: url)
                    },
                    fetch: { _ in },
                    checkout: { _ in },
                    createBranch: { _ in Branch(name: "unexpected") },
                    status: { _ in [] },
                    stage: { _ in },
                    commit: { _ in Commit(id: "unexpected") },
                    push: { _ in }
                )
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
                            patch: SourcePatch(fileChanges: [])
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
        }

        #expect(error == .missingGitRepository(repositoryURL))
        #expect(await requestRecorder.requests.isEmpty)
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

private struct LiveTangledPDSReadbackConfiguration {
    var session: OAuth.Session
    var targetRepoDID: String
    var targetBranch: String
    var sourceBranch: String?
    var sourceSHA: String?

    static func loadFromEnvironment() throws -> Self? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OME_LIVE_TANGLED_PROPOSAL_READBACK"] == "1" else {
            return nil
        }

        let sessionValue = try requiredEnvironmentValue(
            "OME_LIVE_TANGLED_OAUTH_SESSION_JSON_BASE64",
            environment: environment
        )
        let sessionData = Data(base64Encoded: sessionValue) ?? Data(sessionValue.utf8)
        let session = try JSONDecoder().decode(OAuth.Session.self, from: sessionData)

        return Self(
            session: session,
            targetRepoDID: try requiredEnvironmentValue(
                "OME_LIVE_TANGLED_TARGET_REPO_DID",
                environment: environment
            ),
            targetBranch: environment["OME_LIVE_TANGLED_TARGET_BRANCH"] ?? "main",
            sourceBranch: environment["OME_LIVE_TANGLED_SOURCE_BRANCH"],
            sourceSHA: environment["OME_LIVE_TANGLED_SOURCE_SHA"]
        )
    }

    func withLiveDependencies<Value>(
        operation: @escaping () async throws -> Value
    ) async throws -> Value {
        try await withDependencies {
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = .liveValue
            $0.pdsHost = session.pdsHost
            $0.getDefaultSession = { session }
            $0.getOptionalDefaultSession = { session }
        } operation: {
            try await session.withAuthentication(operation: operation)
        }
    }

    private static func requiredEnvironmentValue(
        _ name: String,
        environment: [String: String]
    ) throws -> String {
        guard let value = environment[name], !value.isEmpty else {
            throw LiveTangledPDSReadbackConfigurationError.missingEnvironmentValue(name)
        }
        return value
    }
}

private enum LiveTangledPDSReadbackConfigurationError: CustomStringConvertible, Error {
    case missingEnvironmentValue(String)

    var description: String {
        switch self {
        case .missingEnvironmentValue(let name):
            "\(name) is required when OME_LIVE_TANGLED_PROPOSAL_READBACK=1"
        }
    }
}

private struct TangledPullReadbackRecord: Decodable, Sendable {
    struct Target: Decodable, Sendable {
        var branch: String
        var repo: String
        var repoDID: String?

        enum CodingKeys: String, CodingKey {
            case branch
            case repo
            case repoDID = "repoDid"
        }
    }

    struct Source: Decodable, Sendable {
        var branch: String
        var sha: String?
    }

    var type: String
    var title: String
    var patch: String?
    var patchBlob: ATProto.Blob
    var target: Target
    var source: Source?

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case title
        case patch
        case patchBlob
        case target
        case source
    }
}

private struct LiveUploadBlobOutput: Decodable, Sendable {
    var blob: ATProto.Blob
}

private func uploadLivePatchBlob(_ patchData: Data) async throws -> ATProto.Blob {
    @Dependency(\.httpClient) var httpClient
    @Dependency(\.pdsHost) var pdsHost

    guard let url = URL(string: "https://\(pdsHost.rawValue)/xrpc/com.atproto.repo.uploadBlob")
    else {
        throw TangledSourcePatchPublisherError.invalidUploadBlobURL(pdsHost.rawValue)
    }

    var request = HTTPRequest(url: url)
    request.method = .post

    @Dependency(\.requestHeaders) var requestHeaders
    request.headerFields = requestHeaders
    request.headerFields[.contentType] = "text/x-patch"

    let responseData = try await httpClient.run(request, try patchData.gzipped())
    return try JSONDecoder()
        .decode(LiveUploadBlobOutput.self, from: responseData ?? Data())
        .blob
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
