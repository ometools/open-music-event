import ATProto
import ATProtoOAuth
import Dependencies
import Foundation
import Gzip
import OpenMusicEventSourceClone
import SourceEditing
import SourceControlClient
import TangledLexicon
import TangledXRPC
import XRPCClient

public struct TangledSourcePatchPublisher: Sendable {
    public var codec: SourcePatchGitPatchCodec

    public init(
        codec: SourcePatchGitPatchCodec = SourcePatchGitPatchCodec()
    ) {
        self.codec = codec
    }

    public func publish(_ preparedPatch: PreparedSourcePatch) async throws -> SourcePatchPublication {
        guard let remote = preparedPatch.request.location.remote else {
            throw TangledSourcePatchPublisherError.missingRemote
        }
        guard remote.kind == "tangled" else {
            throw TangledSourcePatchPublisherError.unsupportedRemoteKind(remote.kind)
        }
        guard let title = preparedPatch.request.title?.sourcePatchTitleValue else {
            throw TangledSourcePatchPublisherError.missingTitle
        }

        let repository = try TangledRepositoryReference(parsing: remote.reference)
        let targetRepository = try await targetRepository(repository)
        @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
        try await authorizationBroker.authorize(TangledOAuthRequirements.proposalAuthRequirement)
        let gitBackedPatch = try await gitBackedPreparedPatch(
            preparedPatch,
            repository: repository,
            repoDID: targetRepository.repoDID
        )
        defer {
            if let cleanupURL = gitBackedPatch.cleanupURL {
                try? FileManager.default.removeItem(at: cleanupURL)
            }
        }
        let publishingPatch = gitBackedPatch.preparedPatch
        try Self.requireGitRepository(publishingPatch.workingTree.workingRepositoryURL)

        let targetBranch = Self.targetBranch(remote.ref)
        let sourceBranch = Self.proposalBranchName()
        let commit = try await pushBranch(
            publishingPatch,
            repository: repository,
            branchName: sourceBranch,
            credentials: gitBackedPatch.credentials,
            title: title
        )
        let createdAtDate = Self.now()
        let createdAt = Self.iso8601String(createdAtDate)
        @Dependency(\.sourceControl) var sourceControl
        let diffData = try await sourceControl.formatPatch(
            FormatPatchRequest(
                repository: Repository(url: publishingPatch.workingTree.workingRepositoryURL),
                commit: commit.id
            )
        )
        let patchText = try Self.formatPatchText(
            diffData: diffData,
            sourceRevision: commit.id.rawValue,
            title: title,
            createdAt: createdAtDate
        )
        let patchData = Data(patchText.utf8)
        let patchBlob = try await uploadPatchBlob(patchData)
        let description = preparedPatch.request.description
        guard let targetRepositoryDID = DID(targetRepository.repoDID) else {
            throw TangledSourcePatchPublisherError
                .repositoryRecordInvalidRepoDID(targetRepository.recordURI)
        }
        let record = TangledPullRecord(
            target: TangledPullRecord.Target(
                repo: targetRepositoryDID,
                branch: targetBranch
            ),
            title: title,
            body: description,
            rounds: [
                TangledPullRecord.Round(
                    patchBlob: patchBlob,
                    createdAt: createdAt
                )
            ],
            source: TangledPullRecord.Source(
                branch: sourceBranch.rawValue
            ),
            createdAt: createdAt
        )

        @Dependency(\.getDefaultSession) var getDefaultSession
        @Dependency(XRPC.Client.self) var xrpcClient
        _ = try await xrpcClient.run(
            TangledRepositoryRequests.createRecord(
                repo: getDefaultSession().accountID.rawValue.description,
                collection: .pull,
                record: record,
                authorizationPolicy: .required(TangledOAuthRequirements.proposalAuthRequirement)
            )
        )

        return SourcePatchPublication(
            sourceChangeURL: repository.pullListURL()
        )
    }
}

public enum TangledSourcePatchPublisherError: Equatable, Error, Sendable {
    case missingRemote
    case missingTitle
    case missingRepositoryPDS(String)
    case missingGitRepository(URL)
    case repositoryRecordMissingKey(String)
    case repositoryRecordInvalidRepoDID(String)
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

    static func isGitRepository(_ repositoryURL: URL) -> Bool {
        let dotGitURL = repositoryURL.appending(path: ".git")
        return FileManager.default.fileExists(atPath: dotGitURL.path)
    }

    static func requireGitRepository(_ repositoryURL: URL) throws {
        guard isGitRepository(repositoryURL) else {
            throw TangledSourcePatchPublisherError.missingGitRepository(repositoryURL)
        }
    }

    func gitBackedPreparedPatch(
        _ preparedPatch: PreparedSourcePatch,
        repository: TangledRepositoryReference,
        repoDID: String
    ) async throws -> GitBackedPreparedPatch {
        guard !Self.isGitRepository(preparedPatch.workingTree.workingRepositoryURL) else {
            return GitBackedPreparedPatch(
                preparedPatch: preparedPatch,
                credentials: nil,
                cleanupURL: nil
            )
        }

        @Dependency(\.sourceControl) var sourceControl
        @Dependency(\.sourcePatchApplier) var sourcePatchApplier
        @Dependency(\.tangledSSHCredentials) var tangledSSHCredentials
        @Dependency(\.uuid) var uuid

        let credentials = try await tangledSSHCredentials.credentials()
        let checkoutURL = SourceRepositoryStorageClient.temporaryDownloadURL(uuid: uuid())
        let ref = preparedPatch.request.location.remote?.ref ?? "HEAD"
        _ = try await sourceControl.clone(
            repository.sourceControlCloneRequest(
                repoDID: repoDID,
                destinationURL: checkoutURL,
                ref: ref,
                credentials: credentials
            )
        )
        try sourcePatchApplier.apply(
            preparedPatch.request.patch,
            checkoutURL
        )

        return GitBackedPreparedPatch(
            preparedPatch: PreparedSourcePatch(
                request: preparedPatch.request,
                workingTree: SourceWorkingTree(
                    originalRepositoryURL: preparedPatch.workingTree.originalRepositoryURL,
                    originalURL: preparedPatch.workingTree.originalURL,
                    relativePath: preparedPatch.workingTree.relativePath,
                    workingRepositoryURL: checkoutURL,
                    workingURL: Self.appending(
                        preparedPatch.workingTree.relativePath,
                        to: checkoutURL
                    )
                )
            ),
            credentials: credentials,
            cleanupURL: checkoutURL
        )
    }

    static func appending(_ relativePath: String?, to repositoryURL: URL) -> URL {
        guard let relativePath else { return repositoryURL.standardizedFileURL }
        return relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(repositoryURL.standardizedFileURL) { url, component in
                url.appending(path: String(component))
            }
            .standardizedFileURL
    }

    func pushBranch(
        _ preparedPatch: PreparedSourcePatch,
        repository repositoryReference: TangledRepositoryReference,
        branchName: BranchName,
        credentials: Credentials?,
        title: String
    ) async throws -> Commit {
        @Dependency(\.sourceControl) var sourceControl
        @Dependency(\.tangledSSHCredentials) var tangledSSHCredentials

        let repository = try await sourceControl.open(
            preparedPatch.workingTree.workingRepositoryURL
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
                message: CommitMessage(rawValue: title),
                author: Author(
                    name: PersonName(rawValue: "Open Music Event"),
                    email: EmailAddress(rawValue: "noreply@openmusicevent.app")
                )
            )
        )
        let branch = try await sourceControl.createBranch(
            CreateBranchRequest(
                repository: repository,
                name: branchName,
                startPoint: RefName(rawValue: commit.id.rawValue),
                checkout: false
            )
        )
        let pushCredentials = if let credentials {
            credentials
        } else {
            try await tangledSSHCredentials.credentials()
        }
        try await sourceControl.push(
            PushRequest(
                repository: repository,
                localBranch: branch.name,
                remoteBranch: branch.name,
                credentials: repositoryReference.sourceControlCredentials(
                    pushCredentials
                )
            )
        )
        return commit
    }

    func uploadPatchBlob(_ patchData: Data) async throws -> ATProto.Blob {
        @Dependency(XRPC.Client.self) var xrpcClient
        return try await xrpcClient.tangledUploadPatchBlob(
            try patchData.gzipped(),
            authorizationPolicy: .required(TangledOAuthRequirements.proposalAuthRequirement)
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

}

private struct GitBackedPreparedPatch: Sendable {
    var preparedPatch: PreparedSourcePatch
    var credentials: Credentials?
    var cleanupURL: URL?
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
