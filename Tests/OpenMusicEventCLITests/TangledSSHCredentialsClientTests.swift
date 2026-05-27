import CustomDump
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import Sharing
import SourceControlClient
import Testing
import XRPCClient

@testable import OpenMusicEventSourceClone

struct TangledSSHCredentialsClientTests {
    @Test
    func missingKeyGeneratesStoresCreatesRecordAndReturnsCredentials() async throws {
        let storage = Shared<TangledStoredSSHCredentials?>(value: nil)
        let keyPair = TangledSSHKeyPair(
            publicKey: "ssh-ed25519 public-key Open Music Event",
            privateKey: "-----BEGIN OPENSSH PRIVATE KEY-----\nprivate-key\n-----END OPENSSH PRIVATE KEY-----\n"
        )
        let recorder = HTTPRequestRecorder()

        let credentials = try await withDependencies {
            $0.date.now = Date(timeIntervalSince1970: 1_779_800_000)
            $0.pdsHost = "publisher.pds.example"
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { request, body in
                await recorder.record(request, body)
                if request.url?.path.hasSuffix("/com.atproto.repo.listRecords") == true {
                    return Data(#"{"records":[]}"#.utf8)
                }
                return Data(
                    """
                    {
                      "uri": "at://did:plc:placeholder/sh.tangled.publicKey/3key",
                      "cid": "bafyreikey"
                    }
                    """
                    .utf8
                )
            }
        } operation: {
            try await TangledSSHCredentialsClient
                .live(storage: storage, generateKeyPair: { keyPair })
                .credentials()
        }

        expectNoDifference(
            credentials,
            Credentials(
                ssh: SSHCredentials(
                    publicKey: SSHPublicKey(rawValue: keyPair.publicKey),
                    privateKey: SSHPrivateKey(rawValue: keyPair.privateKey)
                )
            )
        )
        expectNoDifference(
            try #require(storage.withLock { $0 }),
            TangledStoredSSHCredentials(
                publicKey: keyPair.publicKey,
                privateKey: keyPair.privateKey,
                name: "Open Music Event",
                createdAt: "2026-05-26T12:53:20Z",
                recordURI: "at://did:plc:placeholder/sh.tangled.publicKey/3key",
                recordCID: "bafyreikey"
            )
        )

        let requests = await recorder.requests
        #expect(
            requests.contains {
                $0.url?.absoluteString
                    == "https://publisher.pds.example/xrpc/com.atproto.repo.listRecords?repo=did:plc:placeholder&collection=sh.tangled.publicKey&limit=100"
            }
        )
        let createRecordRequest = try #require(
            requests.first { $0.url?.path.hasSuffix("/com.atproto.repo.createRecord") == true }
        )
        let body = try #require(createRecordRequest.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["collection"] as? String == "sh.tangled.publicKey")
        let record = try #require(json["record"] as? [String: Any])
        #expect(record["$type"] as? String == "sh.tangled.publicKey")
        #expect(record["key"] as? String == keyPair.publicKey)
    }

    @Test
    func existingStoredRecordSkipsGenerationAndNetwork() async throws {
        let stored = TangledStoredSSHCredentials(
            publicKey: "ssh-ed25519 public-key Open Music Event",
            privateKey: "private-key",
            name: "Open Music Event",
            createdAt: "2026-05-27T00:26:40Z",
            recordURI: "at://did:plc:placeholder/sh.tangled.publicKey/3key",
            recordCID: "bafyreikey"
        )
        let storage = Shared<TangledStoredSSHCredentials?>(value: stored)

        let credentials = try await withDependencies {
            $0.httpClient = HTTPClient { request, _ in
                Issue.record("Unexpected request: \(String(describing: request.url))")
                return Data()
            }
        } operation: {
            try await TangledSSHCredentialsClient.live(
                storage: storage,
                generateKeyPair: {
                    Issue.record("Unexpected key generation")
                    return TangledSSHKeyPair(publicKey: "new", privateKey: "new")
                }
            )
            .credentials()
        }

        expectNoDifference(credentials, stored.sourceControlCredentials)
        expectNoDifference(try #require(storage.withLock { $0 }), stored)
    }

    @Test
    func matchingExistingPublicKeyRecordAvoidsDuplicateCreation() async throws {
        let stored = TangledStoredSSHCredentials(
            publicKey: "ssh-ed25519 public-key Open Music Event",
            privateKey: "private-key",
            name: "Open Music Event",
            createdAt: "2026-05-27T00:26:40Z"
        )
        let storage = Shared<TangledStoredSSHCredentials?>(value: stored)
        let recorder = HTTPRequestRecorder()

        _ = try await withDependencies {
            $0.pdsHost = "publisher.pds.example"
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { request, body in
                await recorder.record(request, body)
                return Data(
                    """
                    {
                      "records": [
                        {
                          "uri": "at://did:plc:placeholder/sh.tangled.publicKey/3key",
                          "cid": "bafyreikey",
                          "value": {
                            "$type": "sh.tangled.publicKey",
                            "key": "ssh-ed25519 public-key Open Music Event",
                            "name": "Open Music Event",
                            "createdAt": "2026-05-27T00:26:40Z"
                          }
                        }
                      ]
                    }
                    """
                    .utf8
                )
            }
        } operation: {
            try await TangledSSHCredentialsClient.live(
                storage: storage,
                generateKeyPair: {
                    Issue.record("Unexpected key generation")
                    return TangledSSHKeyPair(publicKey: "new", privateKey: "new")
                }
            )
            .credentials()
        }

        expectNoDifference(
            storage.withLock { $0?.recordURI },
            String?.some("at://did:plc:placeholder/sh.tangled.publicKey/3key")
        )
        #expect(
            await recorder.requests.allSatisfy {
                $0.url?.path.hasSuffix("/com.atproto.repo.createRecord") != true
            }
        )
    }

    @Test
    func encodesEd25519OpenSSHKeyMaterial() throws {
        let keyPair = try TangledSSHKeyPair.ed25519(
            seed: Data(repeating: 1, count: 32),
            publicKey: Data(repeating: 2, count: 32),
            comment: "Open Music Event"
        )

        #expect(keyPair.publicKey.hasPrefix("ssh-ed25519 "))
        #expect(keyPair.publicKey.hasSuffix(" Open Music Event"))
        #expect(keyPair.privateKey.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----\n"))
        #expect(keyPair.privateKey.hasSuffix("-----END OPENSSH PRIVATE KEY-----\n"))
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
