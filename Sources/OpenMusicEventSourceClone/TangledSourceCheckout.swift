import ATProto
import Dependencies
import Foundation
import SourceControlClient
import XRPCClient

public struct TangledSourceCheckoutRequest: Equatable, Sendable {
    public var repository: TangledRepositoryReference
    public var ref: String
    public var outputURL: URL

    public init(
        repository: TangledRepositoryReference,
        ref: String,
        outputURL: URL
    ) {
        self.repository = repository
        self.ref = ref
        self.outputURL = outputURL.standardizedFileURL
    }
}

public struct TangledSourceCheckout: Equatable, Sendable {
    public var repositoryURL: URL

    public init(repositoryURL: URL) {
        self.repositoryURL = repositoryURL.standardizedFileURL
    }
}

public struct TangledSourceCheckoutClient: Sendable {
    public var checkout: @Sendable (TangledSourceCheckoutRequest) async throws -> TangledSourceCheckout

    public init(
        checkout: @escaping @Sendable (TangledSourceCheckoutRequest) async throws -> TangledSourceCheckout
    ) {
        self.checkout = checkout
    }
}

public extension TangledSourceCheckoutClient {
    static var archive: Self {
        Self { request in
            try TangledSourceArchiveExtractor.validateOutputDoesNotExist(request.outputURL)
            try await TangledSourceCloner(
                repository: request.repository,
                ref: request.ref,
                outputURL: request.outputURL
            )
            .clone()
            return TangledSourceCheckout(repositoryURL: request.outputURL)
        }
    }

    static var git: Self {
        git(credentials: .sshAgent())
    }

    static func git(credentials: Credentials?) -> Self {
        Self { request in
            try TangledSourceArchiveExtractor.validateOutputDoesNotExist(request.outputURL)

            let repoDID = try await request.repository.resolvedTangledRepositoryDID()
            @Dependency(\.sourceControl) var sourceControl
            _ = try await sourceControl.clone(
                request.repository.sourceControlCloneRequest(
                    repoDID: repoDID,
                    destinationURL: request.outputURL,
                    ref: request.ref,
                    credentials: credentials
                )
            )
            return TangledSourceCheckout(repositoryURL: request.outputURL)
        }
    }
}

public extension TangledRepositoryReference {
    func sourceControlRemote(repoDID: String) -> Remote {
        Remote(url: RemoteURL(rawValue: sourceControlRemoteURL(repoDID: repoDID)))
    }

    func sourceControlCloneRequest(
        repoDID: String,
        destinationURL: URL,
        ref: String,
        credentials: Credentials? = nil
    ) -> CloneRequest {
        CloneRequest(
            remote: sourceControlRemote(repoDID: repoDID),
            destinationURL: destinationURL,
            checkout: sourceControlCheckoutRef(ref),
            credentials: credentials
        )
    }

    func sourceControlFetchRequest(
        repository: Repository,
        credentials: Credentials? = nil
    ) -> FetchRequest {
        FetchRequest(
            repository: repository,
            credentials: credentials
        )
    }

    private func sourceControlRemoteURL(repoDID: String) -> String {
        if let port {
            return "ssh://git@\(host):\(port)/\(repoDID)"
        } else {
            return "git@\(host):\(repoDID)"
        }
    }

    private func sourceControlCheckoutRef(_ ref: String) -> RefName? {
        let trimmedRef = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRef.isEmpty, trimmedRef != "HEAD" else { return nil }
        if trimmedRef.hasPrefix("refs/heads/") {
            return RefName(rawValue: String(trimmedRef.dropFirst("refs/heads/".count)))
        }
        return RefName(rawValue: trimmedRef)
    }

    func resolvedTangledRepositoryDID() async throws -> String {
        let owner = try await resolvedTangledRepositoryOwner()

        @Dependency(XRPC.Client.self) var xrpcClient
        var cursor: String?

        repeat {
            let output = try await xrpcClient.run(
                ListRecordsRequest<TangledRepositoryRecord>(
                    repo: owner.did.description,
                    collection: "sh.tangled.repo",
                    cursor: cursor,
                    pdsHost: owner.pdsHost
                )
            )

            if let record = output.records.first(where: { listedRecord in
                listedRecord.value.matches(self)
                    || listedRecord.uri.rkey?.rawValue == repository
            }) {
                guard let repoDID = record.value.repoDid else {
                    throw TangledSourceCheckoutError
                        .repositoryRecordMissingRepoDID(record.uri.description)
                }
                return repoDID
            }

            cursor = output.cursor
        } while cursor != nil

        throw TangledSourceCheckoutError.repositoryRecordNotFound(
            owner: owner.did.description,
            repository: repository
        )
    }

    private func resolvedTangledRepositoryOwner() async throws -> TangledRepositoryOwnerResolution {
        let owner = self.owner.hasPrefix("@")
            ? String(self.owner.dropFirst())
            : self.owner

        @Dependency(Atmosphere.Account.Client.self) var accountClient
        let account: Atmosphere.Account
        let document: DID.Document

        if let did = DID(owner) {
            (account, document) = try await accountClient.resolveDID(did)
        } else {
            guard !owner.isEmpty else {
                throw TangledSourceCheckoutError.repositoryRecordNotFound(
                    owner: self.owner,
                    repository: repository
                )
            }
            (account, document) = try await accountClient.resolveHandle(
                Atmosphere.Account.Handle(owner)
            )
        }

        guard let pdsHost = document.pdsHost else {
            throw TangledSourceCheckoutError
                .missingRepositoryPDS(account.id.rawValue.description)
        }

        return TangledRepositoryOwnerResolution(
            did: account.id.rawValue,
            pdsHost: pdsHost
        )
    }
}

public enum TangledSourceCheckoutError: Equatable, Error, Sendable {
    case missingRepositoryPDS(String)
    case repositoryRecordMissingRepoDID(String)
    case repositoryRecordNotFound(owner: String, repository: String)
}

private struct TangledRepositoryOwnerResolution: Sendable {
    var did: DID
    var pdsHost: ATProto.PDSHost
}

private struct ListRecordsRequest<RecordValue: Decodable & Sendable>: XRPC.Request, Sendable {
    static var nsid: ATProto.NSID { ATProto.NSID("com.atproto.repo.listRecords") }
    static var type: XRPC.RequestType { .query }

    typealias Input = Never
    typealias Output = ListRecordsOutput<RecordValue>
    typealias Parameters = Never

    var repo: String
    var collection: String
    var cursor: String?
    var pdsHost: ATProto.PDSHost

    var routing: XRPC.Routing {
        XRPC.Routing(
            unauthenticated: .host(pdsHost),
            authenticated: .host(pdsHost)
        )
    }

    var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "repo", value: repo),
            URLQueryItem(name: "collection", value: collection),
            URLQueryItem(name: "limit", value: "100"),
        ]
        if let cursor {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return items
    }
}

private struct ListRecordsOutput<RecordValue: Decodable & Sendable>: Decodable, Sendable {
    var cursor: String?
    var records: [ListedRecord<RecordValue>]
}

private struct ListedRecord<RecordValue: Decodable & Sendable>: Decodable, Sendable {
    var uri: ATProto.URI
    var value: RecordValue
}

private struct TangledRepositoryRecord: Decodable, Sendable {
    var name: String?
    var repo: String?
    var repoDid: String?

    func matches(_ reference: TangledRepositoryReference) -> Bool {
        (name ?? repo) == reference.repository
    }
}

public extension DependencyValues {
    var tangledSourceCheckout: TangledSourceCheckoutClient {
        get { self[TangledSourceCheckoutClientKey.self] }
        set { self[TangledSourceCheckoutClientKey.self] = newValue }
    }
}

private enum TangledSourceCheckoutClientKey: DependencyKey {
    static var liveValue: TangledSourceCheckoutClient {
        .archive
    }

    static var testValue: TangledSourceCheckoutClient {
        .archive
    }
}
