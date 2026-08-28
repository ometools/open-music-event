import ArgumentParser
import ATProto
import CustomDump
import Dependencies
import Foundation
import Gzip
import HTTPClient
import HTTPTypes
import SourceControlClient
import Synchronization
import Testing
import XRPCClient

@testable import OpenMusicEventSourceClone

struct TangledSourceCloneTests {
    @Test(arguments: [
        (
            "https://tangled.org/tangled.org/core",
            TangledRepositoryReference(
                host: "tangled.org",
                port: nil,
                owner: "tangled.org",
                repository: "core"
            )
        ),
        (
            "tangled.org/core",
            TangledRepositoryReference(
                host: "tangled.org",
                port: nil,
                owner: "tangled.org",
                repository: "core"
            )
        ),
        (
            "@tangled.org/core",
            TangledRepositoryReference(
                host: "tangled.org",
                port: nil,
                owner: "@tangled.org",
                repository: "core"
            )
        ),
        (
            "https://tangled.org/did:plc:wshs7t2adsemcrrd4snkeqli/core",
            TangledRepositoryReference(
                host: "tangled.org",
                port: nil,
                owner: "did:plc:wshs7t2adsemcrrd4snkeqli",
                repository: "core"
            )
        ),
        (
            "https://tangled.org/tangled.org/core/",
            TangledRepositoryReference(
                host: "tangled.org",
                port: nil,
                owner: "tangled.org",
                repository: "core"
            )
        ),
        (
            "https://tangled.org/tangled.org/core.git",
            TangledRepositoryReference(
                host: "tangled.org",
                port: nil,
                owner: "tangled.org",
                repository: "core"
            )
        ),
        (
            "https://tangled.org/woody.fm/shambhala-ome",
            TangledRepositoryReference(
                host: "tangled.org",
                port: nil,
                owner: "woody.fm",
                repository: "shambhala-ome"
            )
        ),
        (
            "tangled.org/woody.fm/shambhala-ome",
            TangledRepositoryReference(
                host: "tangled.org",
                port: nil,
                owner: "woody.fm",
                repository: "shambhala-ome"
            )
        ),
        (
            "tangled.org/did:plc:wshs7t2adsemcrrd4snkeqli/core",
            TangledRepositoryReference(
                host: "tangled.org",
                port: nil,
                owner: "did:plc:wshs7t2adsemcrrd4snkeqli",
                repository: "core"
            )
        ),
    ])
    func parsesRepositoryReferences(
        rawValue: String,
        expectedReference: TangledRepositoryReference
    ) throws {
        expectNoDifference(
            try TangledRepositoryReference(parsing: rawValue),
            expectedReference
        )
    }

    @Test
    func normalizedReferenceRoundTripsThroughParser() throws {
        let reference = TangledRepositoryReference(
            host: "tangled.org",
            owner: "woody.fm",
            repository: "wicked-woods-ome"
        )

        expectNoDifference(
            try TangledRepositoryReference(parsing: reference.normalizedReference),
            reference
        )
    }

    @Test(arguments: [
        (
            "HEAD",
            "https://tangled.org/tangled.org/core/archive/HEAD.tar.gz"
        ),
        (
            "master",
            "https://tangled.org/tangled.org/core/archive/master.tar.gz"
        ),
        (
            "v1.13.0-alpha",
            "https://tangled.org/tangled.org/core/archive/v1.13.0-alpha.tar.gz"
        ),
        (
            "sl/spindle-rewrite",
            "https://tangled.org/tangled.org/core/archive/sl%2Fspindle-rewrite.tar.gz"
        ),
        (
            "refs/heads/main",
            "https://tangled.org/tangled.org/core/archive/refs%2Fheads%2Fmain.tar.gz"
        ),
    ])
    func buildsArchiveURL(ref: String, expectedURLString: String) throws {
        let repository = try TangledRepositoryReference(parsing: "https://tangled.org/tangled.org/core")

        expectNoDifference(
            try repository.archiveURL(ref: ref).absoluteString,
            expectedURLString
        )
    }

    @Test
    func buildsSourceControlCloneRequestForResolvedRepoDID() throws {
        let repository = try TangledRepositoryReference(
            parsing: "https://tangled.org/woody.fm/wicked-woods-ome"
        )
        let destinationURL = URL(fileURLWithPath: "/tmp/wicked-woods-ome")
        let request = repository.sourceControlCloneRequest(
            repoDID: "did:plc:targetrepo",
            destinationURL: destinationURL,
            ref: "main"
        )

        #expect(request.remote.name == RemoteName(rawValue: "origin"))
        #expect(request.remote.url == RemoteURL(rawValue: "git@tangled.org:did:plc:targetrepo"))
        #expect(request.destinationURL == destinationURL.standardizedFileURL)
        #expect(request.checkout == RefName(rawValue: "main"))
        #expect(request.credentials == nil)
    }

    @Test
    func buildsSourceControlCloneRequestForCustomHostPort() throws {
        let repository = TangledRepositoryReference(
            host: "source.example",
            port: 2222,
            owner: "woody.fm",
            repository: "wicked-woods-ome"
        )
        let request = repository.sourceControlCloneRequest(
            repoDID: "did:plc:targetrepo",
            destinationURL: URL(fileURLWithPath: "/tmp/wicked-woods-ome"),
            ref: "refs/heads/release",
            credentials: .sshAgent()
        )

        #expect(request.remote.url == RemoteURL(rawValue: "ssh://git@source.example:2222/did:plc:targetrepo"))
        #expect(request.checkout == RefName(rawValue: "release"))
        #expect(request.credentials == Credentials.sshAgent())
    }

    @Test
    func buildsSourceControlCloneRequestWithoutCheckoutForHEAD() throws {
        let repository = try TangledRepositoryReference(
            parsing: "https://tangled.org/woody.fm/wicked-woods-ome"
        )
        let request = repository.sourceControlCloneRequest(
            repoDID: "did:plc:targetrepo",
            destinationURL: URL(fileURLWithPath: "/tmp/wicked-woods-ome"),
            ref: "HEAD"
        )

        #expect(request.checkout == nil)
    }

    @Test(arguments: [
        (
            SourceControlRemoteFailure.Kind.connection,
            "failed to start SSH session",
            2
        ),
        (
            SourceControlRemoteFailure.Kind.timedOut,
            "failed to authenticate SSH session: Timed out waiting on socket",
            1
        ),
        (
            SourceControlRemoteFailure.Kind.timedOut,
            "SSH could not read data: Timed out waiting on socket",
            1
        ),
    ])
    func gitCheckoutRetriesOnlyConnectionFailuresAndRemovesPartialClone(
        failureKind: SourceControlRemoteFailure.Kind,
        failureMessage: String,
        expectedCloneAttempts: Int
    ) async throws {
        let ownerDID = try #require(DID("did:plc:owner123"))
        let ownerHandle = Atmosphere.Account.Handle("woody.fm")
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-git-checkout-\(UUID().uuidString)")
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let repository = TangledRepositoryReference(
            host: "tangled.org",
            owner: "woody.fm",
            repository: "wicked-woods-ome"
        )
        let credentials = Credentials(
            ssh: SSHCredentials(
                publicKey: "ssh-ed25519 public-key Open Music Event",
                privateKey: "private-key"
            )
        )
        let cloneRequests = Mutex([CloneRequest]())
        let cloneAttempts = Mutex(0)
        let expectedError = SourceControlError.remoteOperationFailed(
            SourceControlRemoteFailure(
                kind: failureKind,
                message: failureMessage
            )
        )

        var checkout: TangledSourceCheckout?
        do {
            checkout = try await withDependencies {
            $0[Atmosphere.Account.Client.self] = Atmosphere.Account.Client(
                resolveHandle: { handle in
                    expectNoDifference(handle, ownerHandle)
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
                    Issue.record("Did not expect DID resolution: \(did)")
                    return (
                        Atmosphere.Account(id: .init(ownerDID), handle: ownerHandle),
                        try didDocument(
                            did: ownerDID,
                            handle: ownerHandle,
                            pdsHost: "owner.pds.example"
                        )
                    )
                }
            )
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { request, _ in
                expectNoDifference(request.url?.host, "owner.pds.example")
                expectNoDifference(request.url?.path, "/xrpc/com.atproto.repo.listRecords")
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
                            "knot": "knot1.tangled.sh",
                            "createdAt": "2026-05-26T17:30:42Z"
                          }
                        }
                      ]
                    }
                    """
                    .utf8
                )
            }
            $0.sourceControl = SourceControlClient(
                initialize: { Repository(url: $0) },
                clone: { request in
                    cloneRequests.withLock { $0.append(request) }
                    let attempt = cloneAttempts.withLock { attempts in
                        attempts += 1
                        return attempts
                    }
                    if attempt == 1 {
                        try FileManager.default.createDirectory(
                            at: request.destinationURL,
                            withIntermediateDirectories: true
                        )
                        throw expectedError
                    }
                    #expect(
                        !FileManager.default.fileExists(
                            atPath: request.destinationURL.path(percentEncoded: false)
                        )
                    )
                    return Repository(url: request.destinationURL)
                },
                open: { Repository(url: $0) },
                fetch: { _ in },
                checkout: { _ in },
                resolveRevision: { _ in "commit-id" },
                createBranch: { request in Branch(name: request.name) },
                status: { _ in [] },
                stage: { _ in },
                commit: { _ in Commit(id: "commit-id") },
                formatPatch: { _ in Data() },
                emailPatch: { _ in Data() },
                push: { _ in }
            )
            $0.tangledSSHCredentials = TangledSSHCredentialsClient {
                credentials
            }
            } operation: {
                try await TangledSourceCheckoutClient.git.checkout(
                    TangledSourceCheckoutRequest(
                        repository: repository,
                        repositoryDID: "did:plc:reviewsource",
                        ref: "refs/heads/main",
                        outputURL: outputURL
                    )
                )
            }
        } catch let error as SourceControlError {
            guard expectedCloneAttempts == 1 else { throw error }
            expectNoDifference(error, expectedError)
        }

        if expectedCloneAttempts == 2 {
            #expect(checkout?.repositoryURL == outputURL)
        } else {
            #expect(checkout == nil)
            #expect(
                !FileManager.default.fileExists(
                    atPath: outputURL.path(percentEncoded: false)
                )
            )
        }
        #expect(cloneAttempts.withLock { $0 } == expectedCloneAttempts)
        let request = try #require(cloneRequests.withLock { $0.first })
        #expect(cloneRequests.withLock { $0.count } == expectedCloneAttempts)
        #expect(request.remote.url == "git@tangled.org:did:plc:reviewsource")
        #expect(request.checkout == "main")
        #expect(request.destinationURL == outputURL)
        #expect(request.depth == nil)
        #expect(request.credentials == repository.sourceControlCredentials(credentials))
    }

    @Test
    func gitCheckoutUpdatesExistingRepositoryInPlace() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-existing-git-checkout-\(UUID().uuidString)")
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try FileManager.default.createDirectory(
            at: outputURL.appending(path: ".git"),
            withIntermediateDirectories: true
        )
        let expectedOutputURL = outputURL.standardizedFileURL

        let repositoryReference = TangledRepositoryReference(
            host: "tangled.org",
            owner: "did:plc:owner123",
            repository: "wicked-woods-ome"
        )
        let credentials = Credentials(
            ssh: SSHCredentials(
                publicKey: "ssh-ed25519 public-key Open Music Event",
                privateKey: "private-key"
            )
        )
        let cloneRequests = Mutex([CloneRequest]())
        let openRequests = Mutex([URL]())
        let fetchRequests = Mutex([FetchRequest]())
        let checkoutRequests = Mutex([CheckoutRequest]())

        let checkout = try await withDependencies {
            $0.sourceControl = SourceControlClient(
                initialize: { Repository(url: $0) },
                clone: { request in
                    cloneRequests.withLock { $0.append(request) }
                    return Repository(url: request.destinationURL)
                },
                open: { url in
                    openRequests.withLock { $0.append(url) }
                    return Repository(url: url)
                },
                fetch: { request in
                    fetchRequests.withLock { $0.append(request) }
                },
                checkout: { request in
                    checkoutRequests.withLock { $0.append(request) }
                },
                resolveRevision: { _ in "commit-id" },
                createBranch: { request in Branch(name: request.name) },
                status: { _ in [] },
                stage: { _ in },
                commit: { _ in Commit(id: "commit-id") },
                formatPatch: { _ in Data() },
                emailPatch: { _ in Data() },
                push: { _ in }
            )
            $0.tangledSSHCredentials = TangledSSHCredentialsClient {
                credentials
            }
        } operation: {
            try await TangledSourceCheckoutClient.git.checkout(
                TangledSourceCheckoutRequest(
                    repository: repositoryReference,
                    ref: "refs/heads/main",
                    outputURL: outputURL
                )
            )
        }

        #expect(checkout.repositoryURL == expectedOutputURL)
        #expect(cloneRequests.withLock { $0.isEmpty })
        #expect(openRequests.withLock { $0 } == [expectedOutputURL])
        let fetchRequest = try #require(fetchRequests.withLock { $0.first })
        #expect(fetchRequest.repository == Repository(url: outputURL))
        #expect(
            fetchRequest.credentials
                == repositoryReference.sourceControlCredentials(credentials)
        )
        let checkoutRequest = try #require(checkoutRequests.withLock { $0.first })
        #expect(checkoutRequest.repository == Repository(url: outputURL))
        #expect(checkoutRequest.ref == "origin/main")
    }

    @Test
    func explicitGitCheckoutCanUseSSHAgentCredentials() async throws {
        let ownerDID = try #require(DID("did:plc:owner123"))
        let ownerHandle = Atmosphere.Account.Handle("woody.fm")
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-git-checkout-ssh-agent-\(UUID().uuidString)")
            .standardizedFileURL
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let repository = TangledRepositoryReference(
            host: "tangled.org",
            owner: "woody.fm",
            repository: "wicked-woods-ome"
        )
        let credentials = Credentials.sshAgent()
        let cloneRequests = Mutex([CloneRequest]())

        _ = try await withDependencies {
            $0[Atmosphere.Account.Client.self] = Atmosphere.Account.Client(
                resolveHandle: { handle in
                    expectNoDifference(handle, ownerHandle)
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
                    Issue.record("Did not expect DID resolution: \(did)")
                    return (
                        Atmosphere.Account(id: .init(ownerDID), handle: ownerHandle),
                        try didDocument(
                            did: ownerDID,
                            handle: ownerHandle,
                            pdsHost: "owner.pds.example"
                        )
                    )
                }
            )
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { request, _ in
                expectNoDifference(request.url?.host, "owner.pds.example")
                expectNoDifference(request.url?.path, "/xrpc/com.atproto.repo.listRecords")
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
            }
            $0.sourceControl = SourceControlClient(
                initialize: { Repository(url: $0) },
                clone: { request in
                    cloneRequests.withLock { $0.append(request) }
                    return Repository(url: request.destinationURL)
                },
                open: { Repository(url: $0) },
                fetch: { _ in },
                checkout: { _ in },
                resolveRevision: { _ in "commit-id" },
                createBranch: { request in Branch(name: request.name) },
                status: { _ in [] },
                stage: { _ in },
                commit: { _ in Commit(id: "commit-id") },
                formatPatch: { _ in Data() },
                emailPatch: { _ in Data() },
                push: { _ in }
            )
        } operation: {
            try await TangledSourceCheckoutClient.git(credentials: credentials).checkout(
                TangledSourceCheckoutRequest(
                    repository: repository,
                    ref: "refs/heads/main",
                    outputURL: outputURL
                )
            )
        }

        let request = try #require(cloneRequests.withLock { $0.first })
        #expect(request.remote.url == "git@tangled.org:did:plc:targetrepo")
        #expect(request.credentials == repository.sourceControlCredentials(credentials))
    }

    @Test
    func resolvesDIDOwnerWithoutHTTP() async throws {
        let repository = try TangledRepositoryReference(
            parsing: "https://tangled.org/did:plc:wshs7t2adsemcrrd4snkeqli/core"
        )

        let did = try await withDependencies {
            $0.httpClient = .testClient { _, path, _ in
                Issue.record("Did not expect HTTP request for DID owner: \(path)")
                return Data()
            }
        } operation: {
            try await repository.resolvedOwnerDID()
        }

        expectNoDifference(did, "did:plc:wshs7t2adsemcrrd4snkeqli")
    }

    @Test
    func resolvesHandleOwnerThroughATProtoClient() async throws {
        let repository = try TangledRepositoryReference(
            parsing: "https://tangled.org/woody.fm/shambhala-ome"
        )
        let expectedDID = try #require(DID("did:plc:cqqtuv75m7e5s4uj6nw4czyu"))
        let expectedHandle = Atmosphere.Account.Handle("woody.fm")

        let did = try await withDependencies {
            $0[Atmosphere.Account.Client.self] = Atmosphere.Account.Client(
                resolveHandle: { handle in
                    expectNoDifference(handle, expectedHandle)
                    return (
                        Atmosphere.Account(id: .init(expectedDID), handle: handle),
                        try didDocument(did: expectedDID, handle: handle)
                    )
                },
                resolveDID: { did in
                    Issue.record("Did not expect DID resolution: \(did)")
                    return (
                        Atmosphere.Account(id: .init(expectedDID), handle: expectedHandle),
                        try didDocument(did: expectedDID, handle: expectedHandle)
                    )
                }
            )
        } operation: {
            try await repository.resolvedOwnerDID()
        }

        expectNoDifference(did, "did:plc:cqqtuv75m7e5s4uj6nw4czyu")
    }

    @Test
    func resolvesAtHandleOwnerThroughATProtoClient() async throws {
        let repository = try TangledRepositoryReference(parsing: "@woody.fm/shambhala-ome")
        let expectedDID = try #require(DID("did:plc:cqqtuv75m7e5s4uj6nw4czyu"))
        let expectedHandle = Atmosphere.Account.Handle("woody.fm")

        let did = try await withDependencies {
            $0[Atmosphere.Account.Client.self] = Atmosphere.Account.Client(
                resolveHandle: { handle in
                    expectNoDifference(handle, expectedHandle)
                    return (
                        Atmosphere.Account(id: .init(expectedDID), handle: handle),
                        try didDocument(did: expectedDID, handle: handle)
                    )
                },
                resolveDID: { did in
                    Issue.record("Did not expect DID resolution: \(did)")
                    return (
                        Atmosphere.Account(id: .init(expectedDID), handle: expectedHandle),
                        try didDocument(did: expectedDID, handle: expectedHandle)
                    )
                }
            )
        } operation: {
            try await repository.resolvedOwnerDID()
        }

        expectNoDifference(did, "did:plc:cqqtuv75m7e5s4uj6nw4czyu")
    }

    @Test
    func rejectsHandleOwnerResolutionWithoutDID() async throws {
        let repository = try TangledRepositoryReference(parsing: "woody.fm/shambhala-ome")

        do {
            _ = try await withDependencies {
                $0[Atmosphere.Account.Client.self] = Atmosphere.Account.Client(
                    resolveHandle: { _ in
                        throw ValidationError("not a did")
                    },
                    resolveDID: { did in
                        Issue.record("Did not expect DID resolution: \(did)")
                        throw ValidationError("not a did")
                    }
                )
            } operation: {
                try await repository.resolvedOwnerDID()
            }
            Issue.record("Expected handle owner resolution to reject a non-DID response.")
        } catch is ValidationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(arguments: [
        "git@tangled.org:tangled.org/core",
        "ssh://tangled.org/tangled.org/core",
        "file:///tmp/core",
        "tangled.org",
        "tangled.org/core/extra/more",
    ])
    func rejectsInvalidRepositoryReferences(rawValue: String) {
        do {
            _ = try TangledRepositoryReference(parsing: rawValue)
            Issue.record("Expected repository reference to be rejected: \(rawValue)")
        } catch is ValidationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func resolvesExistingSourcePathAsLocalRepositoryLocation() throws {
        let localURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-cli-local-source-\(UUID().uuidString)")
            .standardizedFileURL
        try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: localURL)
        }

        expectNoDifference(
            try SourceRepositoryLocation(parsing: localURL.path()),
            .local(localURL)
        )
    }

    @Test
    func resolvesTangledReferenceAsRemoteRepositoryLocation() throws {
        expectNoDifference(
            try SourceRepositoryLocation(parsing: "woody.fm/shambhala-ome"),
            .tangled(
                TangledRepositoryReference(
                    host: "tangled.org",
                    owner: "woody.fm",
                    repository: "shambhala-ome"
                )
            )
        )
    }

    @Test
    func resolvesTangledRepositoryATURIAsRemoteRepositoryLocation() throws {
        let sourceReference = "at://did:plc:5df2u7ief6m6tn77jznicxob/sh.tangled.repo/ome-workspace"
        let recordReference = try TangledRepositoryRecordReference(parsing: sourceReference)

        expectNoDifference(
            try SourceRepositoryLocation(parsing: sourceReference),
            .tangledRepositoryURI(recordReference)
        )
        expectNoDifference(
            recordReference.repositoryReference,
            TangledRepositoryReference(
                host: "tangled.org",
                owner: "did:plc:5df2u7ief6m6tn77jznicxob",
                repository: "ome-workspace"
            )
        )
    }

    @Test
    func resolvesTangledRepositoryATURIAsCheckoutRepositoryReference() throws {
        expectNoDifference(
            try TangledRepositoryReference(
                sourceReference: "at://did:plc:5df2u7ief6m6tn77jznicxob/sh.tangled.repo/ome-workspace"
            ),
            TangledRepositoryReference(
                host: "tangled.org",
                owner: "did:plc:5df2u7ief6m6tn77jznicxob",
                repository: "ome-workspace"
            )
        )
    }

    @Test
    func rejectsMissingExplicitLocalSourcePath() {
        let localURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-cli-missing-source-\(UUID().uuidString)")
            .standardizedFileURL

        do {
            _ = try SourceRepositoryLocation(parsing: localURL.path())
            Issue.record("Expected missing local source path to be rejected.")
        } catch is ValidationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func resolvesTemporaryOutputPathWhenOutputIsOmitted() throws {
        let uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let expectedURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-source-clone-\(uuid.uuidString)")
            .standardizedFileURL

        expectNoDifference(
            TangledSourceCloneCommand.temporaryOutputURL(uuid: uuid),
            expectedURL
        )
    }

    @Test
    func rejectsEmptyOutputPath() {
        do {
            _ = try TangledSourceCloneCommand.resolvedOutputURL("  ")
            Issue.record("Expected empty output path to be rejected.")
        } catch is ValidationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func rejectsExistingOutputPath() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-cli-existing-output-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        do {
            try TangledSourceArchiveExtractor.validateOutputDoesNotExist(outputURL)
            Issue.record("Expected existing output path to be rejected.")
        } catch is ValidationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func ignoresASeparatePathWhoseNameContainsPercentEncodedCharacters() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(
                path: "Open Music Event Source Workspaces \(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let outputURL = rootURL
            .appending(path: "repository", directoryHint: .isDirectory)

        // An older libgit2 bridge created this separate directory by passing an encoded URL path to C.
        let incorrectlyEncodedRootURL = URL(
            filePath: rootURL.path(percentEncoded: true)
        )
        let incorrectlyEncodedOutputURL = incorrectlyEncodedRootURL
            .appending(path: "repository", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
            try? FileManager.default.removeItem(at: incorrectlyEncodedRootURL)
        }
        try FileManager.default.createDirectory(
            at: incorrectlyEncodedOutputURL,
            withIntermediateDirectories: true
        )

        #expect(
            !FileManager.default.fileExists(
                atPath: outputURL.path(percentEncoded: false)
            )
        )
        try TangledSourceArchiveExtractor.validateOutputDoesNotExist(outputURL)
    }

    @Test
    func archiveExtractorExtractsGzippedTarAndFlattensTopLevelDirectory() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-cli-source-extract-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        // Gzipped tar containing repo/event.yml, so the flattening behavior is observable.
        let fixture = try #require(Data(base64Encoded: """
        H4sIAAAAAAAAEytKLcjXZ6AtMDAwMDA3NQXTBgYG6DQWtpm5oRGDgimN3QUGpcUliUUMBgb0sGsQgiJQ/KeWpeaV6FXm5tDGDlCkmpmY4I5/Q2PU+Dc0MDU1YFCgS5yM8PjPS8xNtVIISS0u4Rpop4yCUTAKRsEooCMAAN9H+rQACgAA
        """))

        try TangledSourceArchiveExtractor().extract(fixture, to: outputURL)

        expectNoDifference(
            try String(contentsOf: outputURL.appending(path: "event.yml"), encoding: .utf8),
            "name: Test\n"
        )
        #expect(!FileManager.default.fileExists(atPath: outputURL.appending(path: "repo").path()))
    }

    @Test
    func archiveExtractorKeepsEventsDirectoryAtSourceRoot() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-cli-source-extract-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        // Gzipped tar containing events/minimal-event/event.yml.
        let fixture = try #require(Data(base64Encoded: """
        H4sIAMVeFmoAA+2X0U7CMBSG0UtuvfKuL+A469p1M+ECjJElRCcSE7lroEaSdSNjCDyH7+HL+EJWQM0IbiHZMGH9bpqla85pz/6/Zz5fdAQfibghXkWYTGslAACMUrQa7fWo+B4BsAnIpBgoocwCisAklLIaWpSRzDazacJjlco8ikbLjPfmL0IEGfPpTaGCsywNC5BMxlI0TcZch4JLXANsVQnLAVKnDHW9dqt31fEer40FT5LYGEbS4JNJIIxJHKlvhodD0Wzde63b9t3sZuD3B4FXJy56UIu6T1mLTk5r5Oz9/O3juVf/73OoKmvVN0qNkaf/r4e0/rFtK/3TUrPaUHH9b+rv/1wDchyOJQ8uVhPFxMj1f2Bb9WeWhbX/HwLs7vR/h1CHavs/fjb6T6m+6Ntgf/+nxCLa/w/Bzvr76Z8CYymzdp6LOg+bkD36f2xiov3/IPzR/7sUsO3oC+Do2an/QlT/S57+wbS2+z/MlP6hmPDZVFz/IZfiEvXFNNES1Gg0mirxCWrAhOAAGAAA
        """))

        try TangledSourceArchiveExtractor().extract(fixture, to: outputURL)

        expectNoDifference(
            try String(
                contentsOf: outputURL
                    .appending(path: "events")
                    .appending(path: "minimal-event")
                    .appending(path: "event.yml"),
                encoding: .utf8
            ),
            "name: Test\n"
        )
        #expect(!FileManager.default.fileExists(atPath: outputURL.appending(path: "minimal-event").path()))
    }

    @Test
    func archiveExtractorExtractsPlainTarAndFlattensTopLevelDirectory() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-cli-source-extract-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let gzippedFixture = try #require(Data(base64Encoded: """
        H4sIAAAAAAAAEytKLcjXZ6AtMDAwMDA3NQXTBgYG6DQWtpm5oRGDgimN3QUGpcUliUUMBgb0sGsQgiJQ/KeWpeaV6FXm5tDGDlCkmpmY4I5/Q2PU+Dc0MDU1YFCgS5yM8PjPS8xNtVIISS0u4Rpop4yCUTAKRsEooCMAAN9H+rQACgAA
        """))
        let fixture = try gzippedFixture.gunzipped()

        try TangledSourceArchiveExtractor().extract(fixture, to: outputURL)

        expectNoDifference(
            try String(contentsOf: outputURL.appending(path: "event.yml"), encoding: .utf8),
            "name: Test\n"
        )
        #expect(!FileManager.default.fileExists(atPath: outputURL.appending(path: "repo").path()))
    }

    @Test
    func archiveExtractorSurfacesShortTextErrorBodies() {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-cli-source-extract-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let error = #expect(throws: ValidationError.self) {
            try TangledSourceArchiveExtractor().extract(
                Data("error code: 520".utf8),
                to: outputURL
            )
        }
        #expect(error?.message.contains("Tangled did not return an archive: error code: 520") == true)
    }

    @Test
    func archiveExtractorSurfacesGzippedTextErrorBodies() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-cli-source-extract-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let error = #expect(throws: ValidationError.self) {
            try TangledSourceArchiveExtractor().extract(
                try Data("error code: 520".utf8).gzipped(),
                to: outputURL
            )
        }
        #expect(error?.message.contains("Tangled did not return an archive: error code: 520") == true)
        #expect(error?.message.contains("checksum") == false)
    }

    @Test
    func cloneCommandDownloadsExpectedArchivePathWithExplicitOutput() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-cli-source-clone-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let command = try TangledSourceCloneCommand.parse([
            "@tangled.org/core",
            "--output",
            outputURL.path(),
            "--ref",
            "sl/spindle-rewrite",
        ])

        try await withDependencies {
            $0.httpClient = .testClient { _, path, _ in
                expectNoDifference(
                    path,
                    "/@tangled.org/core/archive/sl%2Fspindle-rewrite.tar.gz"
                )
                return Data("archive".utf8)
            }
            $0.tangledSourceArchiveExtractor = TangledSourceArchiveExtractorClient { archiveData, output in
                expectNoDifference(archiveData, Data("archive".utf8))
                expectNoDifference(output, outputURL.standardizedFileURL)
            }
        } operation: {
            try await command.run()
        }
    }

    @Test
    func archiveCheckoutResolvesWickedWoodsDIDBeforeDownloadingProposalBranch() async throws {
        let wickedWoodsDID = try #require(
            DID("did:plc:5df2u7ief6m6tn77jznicxob")
        )
        let wickedWoodsHandle = Atmosphere.Account.Handle("wickedwoods.ca")
        let proposalBranch = "ome/proposal-9ada21bf-9319-4997-824b-8de5e16d9d42"
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-wicked-woods-review-\(UUID().uuidString)")
            .standardizedFileURL
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        let resolvedDIDs = Mutex([DID]())
        let requestedURLs = Mutex([URL]())

        _ = try await withDependencies {
            $0[Atmosphere.Account.Client.self] = Atmosphere.Account.Client(
                resolveHandle: { handle in
                    Issue.record("Did not expect handle resolution: \(handle)")
                    return (
                        Atmosphere.Account(id: .init(wickedWoodsDID), handle: wickedWoodsHandle),
                        try didDocument(did: wickedWoodsDID, handle: wickedWoodsHandle)
                    )
                },
                resolveDID: { did in
                    resolvedDIDs.withLock { $0.append(did) }
                    return (
                        Atmosphere.Account(id: .init(did), handle: wickedWoodsHandle),
                        try didDocument(did: did, handle: wickedWoodsHandle)
                    )
                }
            )
            $0.httpClient = HTTPClient { request, _ in
                if let url = request.url {
                    requestedURLs.withLock { $0.append(url) }
                }
                return Data("archive".utf8)
            }
            $0.tangledSourceArchiveExtractor = TangledSourceArchiveExtractorClient { archiveData, output in
                expectNoDifference(archiveData, Data("archive".utf8))
                expectNoDifference(output, outputURL)
            }
        } operation: {
            try await TangledSourceCheckoutClient.archive.checkout(
                TangledSourceCheckoutRequest(
                    repository: TangledRepositoryReference(
                        host: "tangled.org",
                        owner: wickedWoodsDID.description,
                        repository: "ome-workspace"
                    ),
                    ref: proposalBranch,
                    outputURL: outputURL
                )
            )
        }

        expectNoDifference(resolvedDIDs.withLock { $0 }, [wickedWoodsDID])
        expectNoDifference(
            requestedURLs.withLock { $0.map(\.absoluteString) },
            [
                "https://tangled.org/wickedwoods.ca/ome-workspace/archive/ome%2Fproposal-9ada21bf-9319-4997-824b-8de5e16d9d42.tar.gz"
            ]
        )
    }

    @Test
    func archiveCheckoutDownloadsTheAdvertisedArtifactWithoutResolvingTheRepositoryOwner() async throws {
        let wickedWoodsDID = try #require(
            DID("did:plc:5df2u7ief6m6tn77jznicxob")
        )
        let wickedWoodsHandle = Atmosphere.Account.Handle("wickedwoods.ca")
        let artifactURL = try #require(
            URL(
                string: "https://stg-resources.openmusicevent.app/woody.fm/wicked-woods-ome-stg/archive/3cc283a5d07218f4dfc55652513e9191d2040a06.tar.gz"
            )
        )
        let archiveData = Data("archive".utf8)
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-wicked-woods-artifact-\(UUID().uuidString)")
            .standardizedFileURL
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        let resolvedDIDs = Mutex([DID]())
        let requestedURLs = Mutex([URL]())

        _ = try await withDependencies {
            $0[Atmosphere.Account.Client.self] = Atmosphere.Account.Client(
                resolveHandle: { handle in
                    Issue.record("Did not expect handle resolution: \(handle)")
                    return (
                        Atmosphere.Account(id: .init(wickedWoodsDID), handle: wickedWoodsHandle),
                        try didDocument(did: wickedWoodsDID, handle: wickedWoodsHandle)
                    )
                },
                resolveDID: { did in
                    resolvedDIDs.withLock { $0.append(did) }
                    return (
                        Atmosphere.Account(id: .init(did), handle: wickedWoodsHandle),
                        try didDocument(did: did, handle: wickedWoodsHandle)
                    )
                }
            )
            $0.httpClient = HTTPClient { request, _ in
                if let url = request.url {
                    requestedURLs.withLock { $0.append(url) }
                }
                return archiveData
            }
            $0.tangledSourceArchiveExtractor = TangledSourceArchiveExtractorClient { downloaded, output in
                expectNoDifference(downloaded, archiveData)
                expectNoDifference(output, outputURL)
            }
        } operation: {
            try await TangledSourceCheckoutClient.archive.checkout(
                TangledSourceCheckoutRequest(
                    repository: TangledRepositoryReference(
                        host: "tangled.org",
                        owner: wickedWoodsDID.description,
                        repository: "ome-workspace"
                    ),
                    ref: "3cc283a5d07218f4dfc55652513e9191d2040a06",
                    archive: SourceArchiveReference(
                        url: artifactURL,
                        checksumSHA256: "DrPja/sk3Nm7HRvs4VMSFrWVOaj94X7oAiSvBlPJKqM=",
                        byteCount: archiveData.count
                    ),
                    outputURL: outputURL
                )
            )
        }

        expectNoDifference(resolvedDIDs.withLock { $0 }, [])
        expectNoDifference(requestedURLs.withLock { $0 }, [artifactURL])
    }

    @Test
    func advertisedArchiveRejectsAnUnexpectedByteCountBeforeExtraction() async throws {
        let archiveData = Data("archive".utf8)
        let didExtractArchive = Mutex(false)
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-artifact-size-mismatch-\(UUID().uuidString)")

        let error = await #expect(throws: SourceArchiveIntegrityError.self) {
            try await withDependencies {
                $0.httpClient = HTTPClient { _, _ in archiveData }
                $0.tangledSourceArchiveExtractor = TangledSourceArchiveExtractorClient { _, _ in
                    didExtractArchive.withLock { $0 = true }
                }
            } operation: {
                try await TangledSourceCloner(
                    repository: TangledRepositoryReference(
                        host: "tangled.org",
                        owner: "wickedwoods.ca",
                        repository: "ome-workspace"
                    ),
                    ref: "revision",
                    archive: SourceArchiveReference(
                        url: try #require(URL(string: "https://resources.example/archive.tar.gz")),
                        checksumSHA256: "DrPja/sk3Nm7HRvs4VMSFrWVOaj94X7oAiSvBlPJKqM=",
                        byteCount: archiveData.count + 1
                    ),
                    outputURL: outputURL
                )
                .clone()
            }
        }

        expectNoDifference(
            error,
            SourceArchiveIntegrityError.byteCount(
                expected: archiveData.count + 1,
                actual: archiveData.count
            )
        )
        expectNoDifference(didExtractArchive.withLock { $0 }, false)
    }

    @Test
    func advertisedArchiveRejectsAnUnexpectedChecksumBeforeExtraction() async throws {
        let archiveData = Data("archive".utf8)
        let didExtractArchive = Mutex(false)
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-artifact-checksum-mismatch-\(UUID().uuidString)")

        let error = await #expect(throws: SourceArchiveIntegrityError.self) {
            try await withDependencies {
                $0.httpClient = HTTPClient { _, _ in archiveData }
                $0.tangledSourceArchiveExtractor = TangledSourceArchiveExtractorClient { _, _ in
                    didExtractArchive.withLock { $0 = true }
                }
            } operation: {
                try await TangledSourceCloner(
                    repository: TangledRepositoryReference(
                        host: "tangled.org",
                        owner: "wickedwoods.ca",
                        repository: "ome-workspace"
                    ),
                    ref: "revision",
                    archive: SourceArchiveReference(
                        url: try #require(URL(string: "https://resources.example/archive.tar.gz")),
                        checksumSHA256: "unexpected-checksum",
                        byteCount: archiveData.count
                    ),
                    outputURL: outputURL
                )
                .clone()
            }
        }

        expectNoDifference(
            error,
            SourceArchiveIntegrityError.checksumSHA256(
                expected: "unexpected-checksum",
                actual: "DrPja/sk3Nm7HRvs4VMSFrWVOaj94X7oAiSvBlPJKqM="
            )
        )
        expectNoDifference(didExtractArchive.withLock { $0 }, false)
    }

    @Test
    func cloneCommandDownloadsBinaryArchiveWithoutBodyLogging() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-cli-source-clone-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let command = try TangledSourceCloneCommand.parse([
            "woody.fm/wicked-woods-ome",
            "--output",
            outputURL.path(),
        ])
        let archiveData = Data([0x1f, 0x8b, 0x08, 0x00, 0x41, 0x52, 0x43, 0x48])
        nonisolated(unsafe) var didInspectResponseLogging = false

        try await withDependencies {
            $0.httpClient = .liveValue
            $0.requestInterceptors = []
            $0.dataForURL = { request, body in
                #expect(body == nil)
                #expect(request.method == .get)
                expectNoDifference(
                    request.url?.absoluteString,
                    "https://tangled.org/woody.fm/wicked-woods-ome/archive/HEAD.tar.gz"
                )
                return (archiveData, HTTPResponse(status: 200))
            }
            $0.responseInterceptors = [
                ResponseInterceptor { _, _, responseData in
                    @Dependency(\.logBody) var logBody
                    didInspectResponseLogging = true
                    expectNoDifference(logBody, false)
                    expectNoDifference(responseData, archiveData)
                }
            ]
            $0.tangledSourceArchiveExtractor = TangledSourceArchiveExtractorClient { downloadedArchiveData, output in
                expectNoDifference(downloadedArchiveData, archiveData)
                expectNoDifference(output, outputURL.standardizedFileURL)
            }
        } operation: {
            try await command.run()
        }

        #expect(didInspectResponseLogging)
    }

    @Test
    func cloneCommandUsesTemporaryOutputWhenOutputIsOmitted() async throws {
        let uuid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let expectedOutputURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-source-clone-\(uuid.uuidString)")
            .standardizedFileURL
        defer {
            try? FileManager.default.removeItem(at: expectedOutputURL)
        }

        let command = try TangledSourceCloneCommand.parse([
            "https://tangled.org/woody.fm/shambhala-ome",
        ])

        try await withDependencies {
            $0.uuid = .constant(uuid)
            $0.httpClient = .testClient { _, path, _ in
                expectNoDifference(
                    path,
                    "/woody.fm/shambhala-ome/archive/HEAD.tar.gz"
                )
                return Data("archive".utf8)
            }
            $0.tangledSourceArchiveExtractor = TangledSourceArchiveExtractorClient { archiveData, output in
                expectNoDifference(archiveData, Data("archive".utf8))
                expectNoDifference(output, expectedOutputURL)
            }
        } operation: {
            try await command.run()
        }
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
