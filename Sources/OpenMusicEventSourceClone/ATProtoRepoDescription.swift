import ATProto
import Dependencies
import Foundation
import XRPCClient

public struct ATProtoRepoDescription: Decodable, Equatable, Sendable {
    public var handle: String
    public var did: DID
    public var collections: [ATProto.NSID]
    public var handleIsCorrect: Bool

    public init(
        handle: String,
        did: DID,
        collections: [ATProto.NSID],
        handleIsCorrect: Bool
    ) {
        self.handle = handle
        self.did = did
        self.collections = collections
        self.handleIsCorrect = handleIsCorrect
    }
}

public struct ATProtoDescribeRepoRequest: XRPC.Request, Sendable {
    public static var nsid: ATProto.NSID { ATProto.NSID("com.atproto.repo.describeRepo") }
    public static var type: XRPC.RequestType { .query }

    public typealias Input = Never
    public typealias Output = ATProtoRepoDescription
    public typealias Parameters = Never

    public var repo: String
    public var pdsHost: ATProto.PDSHost?
    public var authorizationPolicy: XRPC.AuthorizationPolicy

    public init(
        repo: String,
        pdsHost: ATProto.PDSHost? = nil,
        authorizationPolicy: XRPC.AuthorizationPolicy = .none
    ) {
        self.repo = repo
        self.pdsHost = pdsHost
        self.authorizationPolicy = authorizationPolicy
    }

    public init(
        repo: Atmosphere.Account.Identifier,
        pdsHost: ATProto.PDSHost? = nil,
        authorizationPolicy: XRPC.AuthorizationPolicy = .none
    ) {
        self.init(
            repo: repo.description,
            pdsHost: pdsHost,
            authorizationPolicy: authorizationPolicy
        )
    }

    public var routing: XRPC.Routing {
        guard let pdsHost else { return XRPC.Routing() }
        return XRPC.Routing(
            unauthenticated: .host(pdsHost),
            authenticated: .host(pdsHost)
        )
    }

    public var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "repo", value: repo)
        ]
    }
}

public struct ATProtoRepoDescriptionClient: Sendable {
    public var describe: @Sendable (Atmosphere.Account.Identifier) async throws -> ATProtoRepoDescription

    public init(
        describe: @escaping @Sendable (Atmosphere.Account.Identifier) async throws -> ATProtoRepoDescription
    ) {
        self.describe = describe
    }
}

public enum ATProtoRepoDescriptionClientError: Equatable, Error, Sendable {
    case missingPDSHost(String)
    case unimplemented
}

public extension ATProtoRepoDescriptionClient {
    static var live: Self {
        Self { identifier in
            let resolution = try await resolvedRepoHost(for: identifier)
            @Dependency(XRPC.Client.self) var xrpcClient
            return try await xrpcClient.run(
                ATProtoDescribeRepoRequest(
                    repo: resolution.did.description,
                    pdsHost: resolution.pdsHost
                )
            )
        }
    }
}

public extension DependencyValues {
    var atProtoRepoDescription: ATProtoRepoDescriptionClient {
        get { self[ATProtoRepoDescriptionClientKey.self] }
        set { self[ATProtoRepoDescriptionClientKey.self] = newValue }
    }
}

private enum ATProtoRepoDescriptionClientKey: DependencyKey {
    static var liveValue: ATProtoRepoDescriptionClient {
        .live
    }

    static var testValue: ATProtoRepoDescriptionClient {
        ATProtoRepoDescriptionClient { _ in
            throw ATProtoRepoDescriptionClientError.unimplemented
        }
    }
}

private struct RepoHostResolution: Sendable {
    var did: DID
    var pdsHost: ATProto.PDSHost
}

private func resolvedRepoHost(
    for identifier: Atmosphere.Account.Identifier
) async throws -> RepoHostResolution {
    @Dependency(Atmosphere.Account.Client.self) var accountClient

    let account: Atmosphere.Account
    let document: DID.Document
    switch identifier {
    case let .did(did):
        (account, document) = try await accountClient.resolveDID(did)

    case let .handle(handle):
        (account, document) = try await accountClient.resolveHandle(handle)
    }

    guard let pdsHost = document.pdsHost else {
        throw ATProtoRepoDescriptionClientError
            .missingPDSHost(account.id.rawValue.description)
    }

    return RepoHostResolution(
        did: account.id.rawValue,
        pdsHost: pdsHost
    )
}
