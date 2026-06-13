import ATProto
import ATProtoOAuth
import Dependencies
import Foundation
import Gzip
import HTTPClient
import HTTPTypes
import OpenMusicEventSourceClone
import SourceEditing
import SourceControlClient
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
        try Self.requireGitRepository(preparedPatch.workingTree.workingRepositoryURL)

        let repository = try TangledRepositoryReference(parsing: remote.reference)
        let targetRepository = try await targetRepository(repository)
        let targetBranch = Self.targetBranch(remote.ref)
        let sourceBranch = Self.proposalBranchName()
        let commit = try await pushBranch(
            preparedPatch,
            repository: repository,
            branchName: sourceBranch
        )
        let createdAtDate = Self.now()
        let createdAt = Self.iso8601String(createdAtDate)
        let title = preparedPatch.request.title?.sourcePatchTitleValue ?? defaultTitle
        let patchText = try Self.formatPatchText(
            diffData: codec.formatReviewPatch(preparedPatch.request.patch),
            sourceRevision: commit.id.rawValue,
            title: title,
            createdAt: createdAtDate
        )
        let patchData = Data(patchText.utf8)
        let patchBlob = try await uploadPatchBlob(patchData)
        let description = preparedPatch.request.description
        let record = TangledRepoPullRecord(
            body: description ?? "",
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
                branch: sourceBranch.rawValue,
                sha: commit.id.rawValue
            ),
            target: TangledRepoPullRecord.Target(
                branch: targetBranch,
                repo: targetRepository.repoDID,
                repoDID: targetRepository.repoDID
            ),
            title: title
        )

        @Dependency(\.getDefaultSession) var getDefaultSession
        @Dependency(XRPC.Client.self) var xrpcClient
        _ = try await xrpcClient.run(
            TangledCreateRecordRequest(
                input: TangledCreateRecordInput(
                    repo: getDefaultSession().accountID.rawValue.description,
                    collection: TangledRepoPullRecord.collection,
                    record: record
                ),
                authorizationPolicy: .required(TangledOAuthRequirements.proposalAuthRequirement)
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
    case missingGitRepository(URL)
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
                TangledListRecordsRequest<TangledRepositoryRecord>(
                    repo: owner.did.description,
                    collection: TangledRepositoryRecord.collection,
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

    static func proposalBranchName() -> BranchName {
        @Dependency(\.uuid) var uuid
        return BranchName(rawValue: "ome/proposal-\(uuid().uuidString.lowercased())")
    }

    static func requireGitRepository(_ repositoryURL: URL) throws {
        let dotGitURL = repositoryURL.appending(path: ".git")
        guard FileManager.default.fileExists(atPath: dotGitURL.path) else {
            throw TangledSourcePatchPublisherError.missingGitRepository(repositoryURL)
        }
    }

    func pushBranch(
        _ preparedPatch: PreparedSourcePatch,
        repository repositoryReference: TangledRepositoryReference,
        branchName: BranchName
    ) async throws -> Commit {
        @Dependency(\.sourceControl) var sourceControl
        @Dependency(\.tangledSSHCredentials) var tangledSSHCredentials

        let repository = try await sourceControl.open(
            preparedPatch.workingTree.workingRepositoryURL
        )
        let branch = try await sourceControl.createBranch(
            CreateBranchRequest(
                repository: repository,
                name: branchName,
                startPoint: "HEAD",
                checkout: true
            )
        )
        try await sourceControl.stage(
            StageRequest(
                repository: repository,
                paths: preparedPatch.request.patch.fileChanges.map {
                    RepositoryPath(rawValue: $0.path)
                }
            )
        )
        let commit = try await sourceControl.commit(
            CommitRequest(
                repository: repository,
                message: CommitMessage(
                    rawValue: preparedPatch.request.title?.sourcePatchTitleValue
                        ?? defaultTitle
                ),
                author: Author(
                    name: PersonName(rawValue: "Open Music Event"),
                    email: EmailAddress(rawValue: "noreply@openmusicevent.app")
                )
            )
        )
        try await sourceControl.push(
            PushRequest(
                repository: repository,
                localBranch: branch.name,
                remoteBranch: branch.name,
                credentials: repositoryReference.sourceControlCredentials(
                    try await tangledSSHCredentials.credentials()
                )
            )
        )
        return commit
    }

    func uploadPatchBlob(_ patchData: Data) async throws -> ATProto.Blob {
        @Dependency(\.httpClient) var httpClient
        @Dependency(\.jsonDecoder) var jsonDecoder
        @Dependency(\.xrpcAuthorizationGate) var authorizationGate

        let responseData = try await authorizationGate.run(
            policy: .required(TangledOAuthRequirements.proposalAuthRequirement),
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
        sourceRevision: String,
        title: String,
        createdAt: Date
    ) throws -> String {
        guard let diff = String(data: diffData, encoding: .utf8) else {
            throw SourcePatchGitPatchCodecError.binaryPatch
        }

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
}

private struct TangledRepositoryOwnerResolution: Sendable {
    var did: DID
    var pdsHost: ATProto.PDSHost
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

private struct UploadBlobOutput: Decodable, Sendable {
    var blob: ATProto.Blob
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
    var sourcePatchTitleValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var tangledSourcePatchPercentEncodedPathComponent: String {
        addingPercentEncoding(withAllowedCharacters: .tangledSourcePatchPathComponentAllowed)
            ?? self
    }
}

private extension CharacterSet {
    static let tangledSourcePatchPathComponentAllowed = CharacterSet.urlPathAllowed
        .subtracting(CharacterSet(charactersIn: "/"))
}
