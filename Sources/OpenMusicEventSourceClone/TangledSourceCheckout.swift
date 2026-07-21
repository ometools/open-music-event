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
            var repository = request.repository
            if let ownerDID = DID(repository.owner) {
                @Dependency(Atmosphere.Account.Client.self) var accountClient
                let (account, _) = try await accountClient.resolveDID(ownerDID)
                repository.owner = account.handle.rawValue
            }
            try await TangledSourceCloner(
                repository: repository,
                ref: request.ref,
                outputURL: request.outputURL
            )
            .clone()
            return TangledSourceCheckout(repositoryURL: request.outputURL)
        }
    }

    static var git: Self {
        Self { request in
            @Dependency(\.tangledSSHCredentials) var tangledSSHCredentials
            return try await git(credentials: tangledSSHCredentials.credentials())
                .checkout(request)
        }
    }

    static func git(credentials: Credentials?) -> Self {
        Self { request in
            @Dependency(\.sourceControl) var sourceControl
            let credentials = request.repository.sourceControlCredentials(credentials)

            if Self.isGitRepository(request.outputURL) {
                let repository = try await sourceControl.open(request.outputURL)
                try await sourceControl.fetch(
                    request.repository.sourceControlFetchRequest(
                        repository: repository,
                        credentials: credentials
                    )
                )
                try await sourceControl.checkout(
                    CheckoutRequest(
                        repository: repository,
                        ref: request.repository.sourceControlFetchedCheckoutRef(request.ref)
                    )
                )
                return TangledSourceCheckout(repositoryURL: request.outputURL)
            }

            try TangledSourceArchiveExtractor.validateOutputDoesNotExist(request.outputURL)
            let repoDID = try await request.repository.resolvedTangledRepositoryDID()
            _ = try await sourceControl.clone(
                request.repository.sourceControlCloneRequest(
                    repoDID: repoDID,
                    destinationURL: request.outputURL,
                    ref: request.ref,
                    depth: 1,
                    credentials: credentials
                )
            )
            return TangledSourceCheckout(repositoryURL: request.outputURL)
        }
    }

    private static func isGitRepository(_ repositoryURL: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: repositoryURL
                .standardizedFileURL
                .appending(path: ".git")
                .path(percentEncoded: false)
        )
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
        depth: Int? = nil,
        credentials: Credentials? = nil
    ) -> CloneRequest {
        CloneRequest(
            remote: sourceControlRemote(repoDID: repoDID),
            destinationURL: destinationURL,
            checkout: sourceControlCheckoutRef(ref),
            depth: depth,
            credentials: sourceControlCredentials(credentials)
        )
    }

    func sourceControlFetchRequest(
        repository: Repository,
        credentials: Credentials? = nil
    ) -> FetchRequest {
        FetchRequest(
            repository: repository,
            credentials: sourceControlCredentials(credentials)
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

    func sourceControlFetchedCheckoutRef(_ ref: String) -> RefName {
        let trimmedRef = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRef.isEmpty, trimmedRef != "HEAD" else {
            return RefName(rawValue: "origin/HEAD")
        }
        if trimmedRef.hasPrefix("refs/heads/") {
            return RefName(rawValue: "origin/\(trimmedRef.dropFirst("refs/heads/".count))")
        }
        if trimmedRef.hasPrefix("refs/") {
            return RefName(rawValue: trimmedRef)
        }
        return RefName(rawValue: "origin/\(trimmedRef)")
    }

    func resolvedTangledRepositoryDID() async throws -> String {
        let owner = try await resolvedTangledRepositoryOwner()

        @Dependency(XRPC.Client.self) var xrpcClient
        var cursor: String?

        repeat {
            let output = try await xrpcClient.run(
                TangledListRecordsRequest<TangledRepositoryRecord>(
                    repo: owner.did.description,
                    collection: TangledRepositoryRecord.collection,
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

public extension TangledRepositoryReference {
    // Verified with: ssh-keyscan -T 10 -t ed25519 tangled.org
    static let tangledOrgEd25519HostKeySHA256 = HostKeySHA256(
        rawValue: "SHA256:fLyp6ivr5HqmGI8yJiPYstTiJa2AXF/RAa9kF/ur1xo"
    )

    var sourceControlHostKeyPolicy: HostKeyPolicy {
        guard host.caseInsensitiveCompare("tangled.org") == .orderedSame, port == nil else {
            return .defaultValidation
        }
        return .pinnedSHA256(Self.tangledOrgEd25519HostKeySHA256)
    }

    func sourceControlCredentials(_ credentials: Credentials?) -> Credentials? {
        guard var credentials else { return nil }
        guard credentials.hostKeyPolicy == .defaultValidation else { return credentials }
        credentials.hostKeyPolicy = sourceControlHostKeyPolicy
        return credentials
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
