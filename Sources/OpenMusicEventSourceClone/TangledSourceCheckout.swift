import ATProto
import Dependencies
import Foundation
#if canImport(OSLog)
import OSLog
#endif
import SourceControlClient
import TangledLexicon
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
            TangledSourceCheckoutDiagnostics.logCheckoutStarted(request)
            @Dependency(\.tangledSSHCredentials) var tangledSSHCredentials
            do {
                if Self.isGitRepository(request.outputURL) {
                    let credentials = try await tangledSSHCredentials.credentials()
                    let checkout = try await git(credentials: credentials).checkout(request)
                    TangledSourceCheckoutDiagnostics.logCheckoutDone(checkout)
                    return checkout
                }

                TangledSourceCheckoutDiagnostics.logTargetResolutionStarted(request.repository)
                let target = try await request.repository.resolvedTangledRepositoryTarget()
                TangledSourceCheckoutDiagnostics.logTargetResolutionDone(target)
                let credentials = try await tangledSSHCredentials.readyCredentials(target.knotHost)
                let checkout = try await git(
                    credentials: credentials,
                    resolvedTarget: target
                )
                .checkout(request)
                TangledSourceCheckoutDiagnostics.logCheckoutDone(checkout)
                return checkout
            } catch {
                TangledSourceCheckoutDiagnostics.logCheckoutFailure(error, request: request)
                throw error
            }
        }
    }

    static func git(credentials: Credentials?) -> Self {
        git(credentials: credentials, resolvedTarget: nil)
    }

    private static func git(
        credentials: Credentials?,
        resolvedTarget: TangledRepositoryTarget?
    ) -> Self {
        Self { request in
            @Dependency(\.sourceControl) var sourceControl

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
            let target: TangledRepositoryTarget
            if let resolvedTarget {
                target = resolvedTarget
            } else {
                target = try await request.repository.resolvedTangledRepositoryTarget()
            }
            let cloneRequest = request.repository.sourceControlCloneRequest(
                repoDID: target.repositoryDID.description,
                destinationURL: request.outputURL,
                ref: request.ref,
                depth: 1,
                credentials: credentials
            )
            do {
                TangledSourceCheckoutDiagnostics.logCloneStarted(
                    remote: cloneRequest.remote.url,
                    attempt: 1
                )
                _ = try await sourceControl.clone(cloneRequest)
                TangledSourceCheckoutDiagnostics.logCloneDone(
                    remote: cloneRequest.remote.url,
                    attempt: 1
                )
            } catch {
                let cloneError = error
                let willRetry = error.isRetryableSourceControlConnectionFailure
                TangledSourceCheckoutDiagnostics.logCloneFailure(
                    error,
                    remote: cloneRequest.remote.url,
                    attempt: 1,
                    willRetry: willRetry
                )
                try Self.removePartialClone(at: request.outputURL, attempt: 1)
                guard willRetry else { throw cloneError }

                do {
                    TangledSourceCheckoutDiagnostics.logCloneStarted(
                        remote: cloneRequest.remote.url,
                        attempt: 2
                    )
                    _ = try await sourceControl.clone(cloneRequest)
                    TangledSourceCheckoutDiagnostics.logCloneDone(
                        remote: cloneRequest.remote.url,
                        attempt: 2
                    )
                } catch {
                    let cloneError = error
                    TangledSourceCheckoutDiagnostics.logCloneFailure(
                        error,
                        remote: cloneRequest.remote.url,
                        attempt: 2,
                        willRetry: false
                    )
                    try Self.removePartialClone(at: request.outputURL, attempt: 2)
                    throw cloneError
                }
            }
            return TangledSourceCheckout(repositoryURL: request.outputURL)
        }
    }

    private static func removePartialClone(at outputURL: URL, attempt: Int) throws {
        do {
            if FileManager.default.fileExists(
                atPath: outputURL.path(percentEncoded: false)
            ) {
                try FileManager.default.removeItem(at: outputURL)
            }
        } catch {
            TangledSourceCheckoutDiagnostics.logCloneCleanupFailure(
                error,
                outputURL: outputURL,
                attempt: attempt
            )
            throw error
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
            checkout: tangledSourceControlCheckoutRef(ref),
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

    func resolvedTangledRepositoryTarget() async throws -> TangledRepositoryTarget {
        let owner = try await resolvedTangledRepositoryOwner()

        @Dependency(XRPC.Client.self) var xrpcClient
        var cursor: String?

        repeat {
            let output = try await xrpcClient.run(
                TangledListRecordsRequest<TangledRepoRecord>(
                    repo: owner.did.description,
                    collection: TangledRepoRecord.collection.rawValue,
                    cursor: cursor,
                    pdsHost: owner.pdsHost
                )
            )

            if let record = output.records.first(where: { listedRecord in
                listedRecord.value.name == repository
                    || listedRecord.uri.rkey?.rawValue == repository
            }) {
                guard let repositoryDID = record.value.repoDid else {
                    throw TangledRepositoryResolutionError
                        .repositoryRecordMissingRepoDID(record.uri.description)
                }
                return TangledRepositoryTarget(
                    recordURI: record.uri,
                    repositoryDID: repositoryDID,
                    knotHost: ATProto.PDSHost(record.value.knot)
                )
            }

            cursor = output.cursor
        } while cursor != nil

        throw TangledRepositoryResolutionError.repositoryRecordNotFound(
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
                throw TangledRepositoryResolutionError.repositoryRecordNotFound(
                    owner: self.owner,
                    repository: repository
                )
            }
            (account, document) = try await accountClient.resolveHandle(
                Atmosphere.Account.Handle(owner)
            )
        }

        guard let pdsHost = document.pdsHost else {
            throw TangledRepositoryResolutionError
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
        tangledSourceControlHostKeyPolicy(host: host, port: port)
    }

    func sourceControlCredentials(_ credentials: Credentials?) -> Credentials? {
        tangledSourceControlCredentials(credentials, host: host, port: port)
    }
}

public enum TangledRepositoryResolutionError: Equatable, Error, Sendable {
    case missingRepositoryPDS(String)
    case repositoryRecordMissingRepoDID(String)
    case repositoryRecordNotFound(owner: String, repository: String)
}

private func tangledSourceControlCheckoutRef(_ ref: String) -> RefName? {
    let trimmedRef = ref.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedRef.isEmpty, trimmedRef != "HEAD" else { return nil }
    if trimmedRef.hasPrefix("refs/heads/") {
        return RefName(rawValue: String(trimmedRef.dropFirst("refs/heads/".count)))
    }
    return RefName(rawValue: trimmedRef)
}

private func tangledSourceControlHostKeyPolicy(
    host: String,
    port: Int?
) -> HostKeyPolicy {
    guard host.caseInsensitiveCompare("tangled.org") == .orderedSame, port == nil else {
        return .defaultValidation
    }
    return .pinnedSHA256(TangledRepositoryReference.tangledOrgEd25519HostKeySHA256)
}

private func tangledSourceControlCredentials(
    _ credentials: Credentials?,
    host: String,
    port: Int?
) -> Credentials? {
    guard var credentials else { return nil }
    guard credentials.hostKeyPolicy == .defaultValidation else { return credentials }
    credentials.hostKeyPolicy = tangledSourceControlHostKeyPolicy(host: host, port: port)
    return credentials
}

private struct TangledRepositoryOwnerResolution: Sendable {
    var did: DID
    var pdsHost: ATProto.PDSHost
}

private extension Error {
    var isRetryableSourceControlConnectionFailure: Bool {
        guard let sourceControlError = self as? SourceControlError,
              case let .remoteOperationFailed(failure) = sourceControlError else {
            return false
        }
        return failure.kind == .connection
    }
}

private enum TangledSourceCheckoutDiagnostics {
    #if canImport(OSLog)
    private static let logger = Logger(
        subsystem: "fm.woody.openmusicevent",
        category: "TangledSourceCheckout"
    )
    #endif

    static func logCheckoutStarted(_ request: TangledSourceCheckoutRequest) {
        notice("""
        Tangled source checkout started
        repository: \(request.repository.normalizedReference)
        ref: \(request.ref)
        """)
    }

    static func logCheckoutDone(_ checkout: TangledSourceCheckout) {
        notice("""
        Tangled source checkout done
        repository: \(checkout.repositoryURL.path(percentEncoded: false))
        """)
    }

    static func logCheckoutFailure(
        _ error: Error,
        request: TangledSourceCheckoutRequest
    ) {
        failure("""
        Tangled source checkout failed
        repository: \(request.repository.normalizedReference)
        ref: \(request.ref)
        error: \(String(describing: error))
        """)
    }

    static func logTargetResolutionStarted(_ repository: TangledRepositoryReference) {
        notice("""
        Tangled repository target resolution started
        repository: \(repository.normalizedReference)
        """)
    }

    static func logTargetResolutionDone(_ target: TangledRepositoryTarget) {
        notice("""
        Tangled repository target resolution done
        repository DID: \(target.repositoryDID.description)
        knot: \(target.knotHost.rawValue)
        """)
    }

    static func logCloneStarted(remote: RemoteURL, attempt: Int) {
        notice("""
        Tangled source checkout clone started
        remote: \(remote.rawValue)
        attempt: \(attempt)
        """)
    }

    static func logCloneDone(remote: RemoteURL, attempt: Int) {
        notice("""
        Tangled source checkout clone done
        remote: \(remote.rawValue)
        attempt: \(attempt)
        """)
    }

    static func logCloneFailure(
        _ error: Error,
        remote: RemoteURL,
        attempt: Int,
        willRetry: Bool
    ) {
        let message = """
        Tangled source checkout clone failed
        remote: \(remote.rawValue)
        attempt: \(attempt)
        retrying: \(willRetry)
        error: \(String(describing: error))
        """
        failure(message)
    }

    static func logCloneCleanupFailure(
        _ error: Error,
        outputURL: URL,
        attempt: Int
    ) {
        let message = """
        Tangled source checkout clone cleanup failed
        destination: \(outputURL.path(percentEncoded: false))
        attempt: \(attempt)
        error: \(String(describing: error))
        """
        failure(message)
    }

    private static func notice(_ message: String) {
        #if canImport(OSLog)
        logger.notice("\(message, privacy: .public)")
        #else
        print(message)
        #endif
    }

    private static func failure(_ message: String) {
        #if canImport(OSLog)
        logger.error("\(message, privacy: .public)")
        #else
        print(message)
        #endif
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
