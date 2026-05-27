import Dependencies
import Foundation
import SourceControlClient

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
            checkout: RefName(rawValue: ref),
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
