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
        let targetRepository = try await targetRepository(repository)
        let targetBranch = Self.targetBranch(remote.ref)
        let createdAtDate = Self.now()
        let createdAt = Self.iso8601String(createdAtDate)
        let patchText = try Self.formatPatchText(
            diffData: codec.format(preparedPatch.request.patch),
            repositoryURL: preparedPatch.workingTree.originalRepositoryURL,
            title: defaultTitle,
            createdAt: createdAtDate
        )
        let patchData = Data(patchText.utf8)
        let patchBlob = try await uploadPatchBlob(patchData)
        let description = preparedPatch.request.description
        let record = TangledRepoPullRecord(
            body: description,
            createdAt: createdAt,
            patch: Self.legacyPatchText(patchText),
            patchBlob: patchBlob,
            pullID: Self.legacyPullID(createdAtDate),
            rounds: [
                TangledRepoPullRecord.Round(
                    createdAt: createdAt,
                    patchBlob: patchBlob
                )
            ],
            source: TangledRepoPullRecord.Source(
                branch: targetBranch,
                sha: Self.gitHEADSHA(in: preparedPatch.workingTree.originalRepositoryURL)
            ),
            target: TangledRepoPullRecord.Target(
                branch: targetBranch,
                repo: targetRepository.recordURI,
                repoDID: targetRepository.repoDID
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
    case missingRepositoryPDS(String)
    case repositoryRecordMissingKey(String)
    case repositoryRecordMissingRepoDID(String)
    case repositoryRecordNotFound(owner: String, repository: String)
    case unsupportedRemoteKind(String)
}

public extension SourcePatchPublisher {
    static var openMusicEventTangled: Self {
        .live { preparedPatch in
            try await TangledSourcePatchPublisher().publish(preparedPatch)
        }
    }
}

extension TangledSourcePatchPublisher {
    func targetRepositoryDID(
        _ repository: TangledRepositoryReference
    ) async throws -> String {
        try await targetRepository(repository).repoDID
    }

    func targetRepository(
        _ repository: TangledRepositoryReference
    ) async throws -> TangledRepositoryTarget {
        let owner = try await resolvedOwner(for: repository)

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
                listedRecord.value.matches(repository)
                    || listedRecord.uri.rkey?.rawValue == repository.repository
            }) {
                guard let repoDID = record.value.repoDid else {
                    throw TangledSourcePatchPublisherError
                        .repositoryRecordMissingRepoDID(record.uri.description)
                }
                return TangledRepositoryTarget(
                    recordURI: record.uri.description,
                    repoDID: repoDID
                )
            }

            cursor = output.cursor
        } while cursor != nil

        throw TangledSourcePatchPublisherError.repositoryRecordNotFound(
            owner: owner.did.description,
            repository: repository.repository
        )
    }
}

private extension TangledSourcePatchPublisher {
    static let proposalAuthRequirement = OAuth.AuthRequirement(
        permissions: [
            OAuth.Permission("blob:text/x-patch"),
            OAuth.Permission("repo:sh.tangled.repo.pull?action=create"),
        ]
    )

    static func now() -> Date {
        @Dependency(\.date.now) var now
        return now
    }

    static func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func targetBranch(_ ref: String?) -> String {
        let trimmedRef = ref?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedRef.isEmpty, trimmedRef != "HEAD" else { return "main" }
        if trimmedRef.hasPrefix("refs/heads/") {
            return String(trimmedRef.dropFirst("refs/heads/".count))
        }
        return trimmedRef
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

    static func formatPatchText(
        diffData: Data,
        repositoryURL: URL,
        title: String,
        createdAt: Date
    ) throws -> String {
        guard let diff = String(data: diffData, encoding: .utf8) else {
            throw SourcePatchGitPatchCodecError.binaryPatch
        }

        let sourceRevision = gitHEADSHA(in: repositoryURL)
            ?? "0000000000000000000000000000000000000000"
        let subject = title
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let body = """
        From \(sourceRevision) Mon Sep 17 00:00:00 2001
        From: Open Music Event <noreply@openmusicevent.app>
        Date: \(formatPatchDate(createdAt))
        Subject: [PATCH] \(subject)

        ---

        \(diff)
        """

        if body.hasSuffix("\n") {
            return body + "-- \nOpen Music Event\n"
        } else {
            return body + "\n-- \nOpen Music Event\n"
        }
    }

    static func formatPatchDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }

    static func legacyPullID(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func legacyPatchText(_ patchText: String) -> String? {
        patchText.utf8.count <= 256_000 ? patchText : nil
    }

    static func gitHEADSHA(in repositoryURL: URL) -> String? {
        let fileManager = FileManager.default
        let dotGitURL = repositoryURL.appending(path: ".git")
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: dotGitURL.path, isDirectory: &isDirectory) else {
            return nil
        }

        let gitDirectoryURL: URL
        if isDirectory.boolValue {
            gitDirectoryURL = dotGitURL
        } else if let contents = try? String(contentsOf: dotGitURL, encoding: .utf8),
                  contents.hasPrefix("gitdir:") {
            let path = contents
                .dropFirst("gitdir:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            gitDirectoryURL = URL(fileURLWithPath: path, relativeTo: repositoryURL)
                .standardizedFileURL
        } else {
            return nil
        }

        guard let head = try? String(
            contentsOf: gitDirectoryURL.appending(path: "HEAD"),
            encoding: .utf8
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }

        if isGitSHA(head) { return head }
        guard head.hasPrefix("ref:") else { return nil }

        let ref = head
            .dropFirst("ref:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let sha = try? String(
            contentsOf: gitDirectoryURL.appending(path: ref),
            encoding: .utf8
        )
        .trimmingCharacters(in: .whitespacesAndNewlines),
           isGitSHA(sha) {
            return sha
        }

        guard let packedRefs = try? String(
            contentsOf: gitDirectoryURL.appending(path: "packed-refs"),
            encoding: .utf8
        ) else { return nil }
        for line in packedRefs.split(separator: "\n") {
            guard !line.hasPrefix("#"), !line.hasPrefix("^") else { continue }
            let fields = line.split(separator: " ", maxSplits: 1).map(String.init)
            if fields.count == 2, fields[1] == ref, isGitSHA(fields[0]) {
                return fields[0]
            }
        }
        return nil
    }

    static func isGitSHA(_ value: String) -> Bool {
        value.utf8.count == 40 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

private struct TangledRepositoryOwnerResolution: Sendable {
    var did: DID
    var pdsHost: ATProto.PDSHost
}

struct TangledRepositoryTarget: Equatable, Sendable {
    var recordURI: String
    var repoDID: String
}

private func resolvedOwner(
    for repository: TangledRepositoryReference
) async throws -> TangledRepositoryOwnerResolution {
    let owner = repository.owner.hasPrefix("@")
        ? String(repository.owner.dropFirst())
        : repository.owner

    @Dependency(Atmosphere.Account.Client.self) var accountClient
    let account: Atmosphere.Account
    let document: DID.Document

    if let did = DID(owner) {
        (account, document) = try await accountClient.resolveDID(did)
    } else {
        guard !owner.isEmpty else {
            throw TangledSourcePatchPublisherError.repositoryRecordNotFound(
                owner: repository.owner,
                repository: repository.repository
            )
        }
        (account, document) = try await accountClient.resolveHandle(
            Atmosphere.Account.Handle(owner)
        )
    }

    guard let pdsHost = document.pdsHost else {
        throw TangledSourcePatchPublisherError
            .missingRepositoryPDS(account.id.rawValue.description)
    }

    return TangledRepositoryOwnerResolution(
        did: account.id.rawValue,
        pdsHost: pdsHost
    )
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
        var repoDID: String

        enum CodingKeys: String, CodingKey {
            case branch
            case repo
            case repoDID = "repoDid"
        }
    }

    struct Source: Encodable, Sendable {
        var branch: String
        var sha: String?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(branch, forKey: .branch)
            try container.encodeIfPresent(sha, forKey: .sha)
        }

        enum CodingKeys: String, CodingKey {
            case branch
            case sha
        }
    }

    var body: String?
    var createdAt: String
    var patch: String?
    var patchBlob: ATProto.Blob
    var pullID: Int64
    var rounds: [Round]
    var source: Source?
    var target: Target
    var title: String

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case body
        case createdAt
        case patch
        case patchBlob
        case pullID = "pullId"
        case rounds
        case source
        case target
        case targetBranch
        case targetRepo
        case title
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("sh.tangled.repo.pull", forKey: .type)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(patch, forKey: .patch)
        try container.encode(patchBlob, forKey: .patchBlob)
        try container.encode(pullID, forKey: .pullID)
        try container.encode(rounds, forKey: .rounds)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encode(target, forKey: .target)
        try container.encode(target.branch, forKey: .targetBranch)
        try container.encode(target.repo, forKey: .targetRepo)
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
