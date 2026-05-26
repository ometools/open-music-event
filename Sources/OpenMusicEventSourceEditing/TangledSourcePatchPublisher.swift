import ATProto
import ATProtoOAuth
import Dependencies
import Foundation
import Gzip
import HTTPClient
import HTTPTypes
import OpenMusicEventSourceClone
import SourceEditing
import XRPCClient

public struct TangledSourcePatchPublisher: Sendable {
    public var codec: SourcePatchGitPatchCodec
    public var defaultTitle: String

    public init(
        codec: SourcePatchGitPatchCodec = SourcePatchGitPatchCodec(),
        defaultTitle: String = "Update event source"
    ) {
        self.codec = codec
        self.defaultTitle = defaultTitle
    }

    public func publish(_ preparedPatch: PreparedSourcePatch) async throws -> SourcePatchPublication {
        guard let remote = preparedPatch.request.location.remote else {
            throw TangledSourcePatchPublisherError.missingRemote
        }
        guard remote.kind == "tangled" else {
            throw TangledSourcePatchPublisherError.unsupportedRemoteKind(remote.kind)
        }

        let repository = try TangledRepositoryReference(parsing: remote.reference)
        let targetRepo = try await targetRepositoryIdentifier(repository)
        let targetBranch = Self.targetBranch(remote.ref)
        let patchData = try codec.format(preparedPatch.request.patch)
        let patchBlob = try await uploadPatchBlob(patchData)
        let createdAt = Self.iso8601String()
        let description = preparedPatch.request.description
        let record = TangledRepoPullRecord(
            body: description,
            createdAt: createdAt,
            rounds: [
                TangledRepoPullRecord.Round(
                    createdAt: createdAt,
                    patchBlob: patchBlob
                )
            ],
            target: TangledRepoPullRecord.Target(
                branch: targetBranch,
                repo: targetRepo
            ),
            title: defaultTitle
        )

        @Dependency(\.getDefaultSession) var getDefaultSession
        @Dependency(XRPC.Client.self) var xrpcClient
        _ = try await xrpcClient.run(
            CreateRecordRequest(
                input: CreateRecordInput(
                    repo: getDefaultSession().accountID.rawValue.description,
                    collection: "sh.tangled.repo.pull",
                    record: record
                )
            )
        )

        return SourcePatchPublication(
            sourceChangeURL: repository.pullListURL()
        )
    }
}

public enum TangledSourcePatchPublisherError: Equatable, Error, Sendable {
    case invalidUploadBlobURL(String)
    case missingRemote
    case unsupportedRemoteKind(String)
}

public extension SourcePatchPublisher {
    static var openMusicEventTangled: Self {
        .live { preparedPatch in
            try await TangledSourcePatchPublisher().publish(preparedPatch)
        }
    }
}

private extension TangledSourcePatchPublisher {
    static let proposalAuthRequirement = OAuth.AuthRequirement(
        permissions: [
            OAuth.Permission("blob:text/x-patch"),
            OAuth.Permission("repo:sh.tangled.repo.pull?action=create"),
        ]
    )

    static func iso8601String() -> String {
        @Dependency(\.date.now) var now
        return ISO8601DateFormatter().string(from: now)
    }

    static func targetBranch(_ ref: String?) -> String {
        let trimmedRef = ref?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedRef.isEmpty, trimmedRef != "HEAD" else { return "main" }
        if trimmedRef.hasPrefix("refs/heads/") {
            return String(trimmedRef.dropFirst("refs/heads/".count))
        }
        return trimmedRef
    }

    func targetRepositoryIdentifier(
        _ repository: TangledRepositoryReference
    ) async throws -> String {
        let ownerDID = try await repository.resolvedOwnerDID()
        return "\(ownerDID)/\(repository.repository)"
    }

    func uploadPatchBlob(_ patchData: Data) async throws -> ATProto.Blob {
        @Dependency(\.httpClient) var httpClient
        @Dependency(\.jsonDecoder) var jsonDecoder
        @Dependency(\.xrpcAuthorizationGate) var authorizationGate

        let responseData = try await authorizationGate.run(
            policy: .required(Self.proposalAuthRequirement),
            routing: XRPC.Routing()
        ) {
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

            return try await httpClient.run(request, try patchData.gzipped())
        }

        return try jsonDecoder.decode(
            UploadBlobOutput.self,
            from: responseData ?? Data()
        )
        .blob
    }
}

private struct CreateRecordInput<Record: Encodable & Sendable>: Encodable, Sendable {
    var repo: String
    var collection: String
    var record: Record
}

private struct CreateRecordOutput: Decodable, Sendable {
    var uri: ATProto.URI
    var cid: ATProto.CID
}

private struct CreateRecordRequest<Record: Encodable & Sendable>: XRPC.Request, Sendable {
    static var nsid: ATProto.NSID { ATProto.NSID("com.atproto.repo.createRecord") }
    static var type: XRPC.RequestType { .procedure }
    static var authorizationPolicy: XRPC.AuthorizationPolicy {
        .required(TangledSourcePatchPublisher.proposalAuthRequirement)
    }

    typealias Input = CreateRecordInput<Record>
    typealias Output = CreateRecordOutput
    typealias Parameters = Never

    var input: Input
}

private struct UploadBlobOutput: Decodable, Sendable {
    var blob: ATProto.Blob
}

private struct TangledRepoPullRecord: Encodable, Sendable {
    struct Round: Encodable, Sendable {
        var createdAt: String
        var patchBlob: ATProto.Blob
    }

    struct Target: Encodable, Sendable {
        var branch: String
        var repo: String
    }

    var body: String?
    var createdAt: String
    var rounds: [Round]
    var target: Target
    var title: String

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case body
        case createdAt
        case rounds
        case target
        case title
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("sh.tangled.repo.pull", forKey: .type)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(rounds, forKey: .rounds)
        try container.encode(target, forKey: .target)
        try container.encode(title, forKey: .title)
    }
}

private extension TangledRepositoryReference {
    func pullListURL() -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = port
        components.percentEncodedPath = [
            "",
            owner.tangledSourcePatchPercentEncodedPathComponent,
            repository.tangledSourcePatchPercentEncodedPathComponent,
            "pulls",
        ].joined(separator: "/")
        return components.url
    }
}

private extension String {
    var tangledSourcePatchPercentEncodedPathComponent: String {
        addingPercentEncoding(withAllowedCharacters: .tangledSourcePatchPathComponentAllowed)
            ?? self
    }
}

private extension CharacterSet {
    static let tangledSourcePatchPathComponentAllowed = CharacterSet.urlPathAllowed
        .subtracting(CharacterSet(charactersIn: "/"))
}
