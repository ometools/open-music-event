import ATProto
import ATProtoOAuth
import Dependencies
import Foundation
import Gzip
import OpenMusicEventSourceClone
#if canImport(OSLog)
import OSLog
#endif
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

        let repository = try TangledRepositoryReference(
            sourceReference: remote.reference
        )
        let targetRepository = try await targetRepository(repository)
        let gitBackedPatch = try await gitBackedPreparedPatch(
            preparedPatch,
            targetRepository: targetRepository
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
            targetRepository: targetRepository,
            branchName: sourceBranch,
            credentials: gitBackedPatch.credentials,
            title: title
        )
        let createdAtDate = Self.now()
        let createdAt = Self.iso8601String(createdAtDate)
        @Dependency(\.sourceControl) var sourceControl
        let formatPatchRequest = FormatPatchRequest(
            repository: Repository(url: publishingPatch.workingTree.workingRepositoryURL),
            commit: commit.id
        )
        let diffData = try await TangledSourcePatchPublisherDiagnostics.run(
            operation: "sourceControl.formatPatch",
            details: [
                "repository: \(formatPatchRequest.repository.url.path)",
                "commit: \(formatPatchRequest.commit.rawValue)",
            ]
        ) {
            try await sourceControl.formatPatch(formatPatchRequest)
        }
        let patchText = try TangledSourcePatchPublisherDiagnostics.runSync(
            operation: "formatPatchText",
            details: [
                "diffBytes: \(diffData.count)",
                "sourceRevision: \(commit.id.rawValue)",
            ]
        ) {
            try Self.formatPatchText(
                diffData: diffData,
                sourceRevision: commit.id.rawValue,
                title: title,
                createdAt: createdAtDate
            )
        }
        let patchData = Data(patchText.utf8)
        let patchBlob = try await TangledSourcePatchPublisherDiagnostics.run(
            operation: "uploadPatchBlob",
            details: [
                "patchBytes: \(patchData.count)",
            ]
        ) {
            try await uploadPatchBlob(patchData)
        }
        let description = preparedPatch.request.description
        let record = TangledPullRecord(
            target: TangledPullRecord.Target(
                repo: targetRepository.repositoryDID,
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
        let session = getDefaultSession()
        let createPullRecordRequest = TangledRepositoryRequests.createRecord(
            repo: session.accountID.rawValue.description,
            collection: .pull,
            record: record,
            authorizationPolicy: .required(TangledOAuthRequirements.proposalAuthRequirement)
        )
        let createdPullRecord = try await TangledSourcePatchPublisherDiagnostics.run(
            operation: "xrpc.createPullRecord",
            details: [
                "repo: \(session.accountID.rawValue.description)",
                "collection: \(TangledPullRecord.collection.rawValue)",
                "targetBranch: \(targetBranch)",
                "sourceBranch: \(sourceBranch.rawValue)",
            ]
        ) {
            try await xrpcClient.run(createPullRecordRequest)
        }

        return SourcePatchPublication(
            sourceChangeID: createdPullRecord.uri.description,
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
        try await targetRepository(repository).repositoryDID.description
    }

    func targetRepository(
        _ repository: TangledRepositoryReference
    ) async throws -> TangledRepositoryTarget {
        do {
            return try await repository.resolvedTangledRepositoryTarget()
        } catch let error as TangledRepositoryResolutionError {
            switch error {
            case let .missingRepositoryPDS(did):
                throw TangledSourcePatchPublisherError.missingRepositoryPDS(did)
            case let .repositoryRecordMissingRepoDID(uri):
                throw TangledSourcePatchPublisherError.repositoryRecordMissingRepoDID(uri)
            case let .repositoryRecordNotFound(owner, repository):
                throw TangledSourcePatchPublisherError.repositoryRecordNotFound(
                    owner: owner,
                    repository: repository
                )
            }
        }
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
        targetRepository: TangledRepositoryTarget
    ) async throws -> GitBackedPreparedPatch {
        guard !Self.isGitRepository(preparedPatch.workingTree.workingRepositoryURL) else {
            TangledSourcePatchPublisherDiagnostics.log(
                operation: "sourceControl.clone",
                status: .skipped,
                details: [
                    "reason: working tree already has .git",
                    "repository: \(preparedPatch.workingTree.workingRepositoryURL.path)",
                ]
            )
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

        let credentials = try await TangledSourcePatchPublisherDiagnostics.run(
            operation: "tangledSSHCredentials.credentials",
            details: [
                "reason: clone temporary git checkout",
                "repository: \(targetRepository.knotHost.rawValue)/\(targetRepository.repositoryDID.description)",
            ]
        ) {
            try await tangledSSHCredentials.credentials()
        }
        let checkoutURL = SourceRepositoryStorageClient.temporaryDownloadURL(uuid: uuid())
        let ref = preparedPatch.request.location.remote?.ref ?? "HEAD"
        let cloneRequest = targetRepository.sourceControlCloneRequest(
            destinationURL: checkoutURL,
            ref: ref,
            credentials: credentials
        )
        _ = try await TangledSourcePatchPublisherDiagnostics.run(
            operation: "sourceControl.clone",
            details: [
                "remote: \(cloneRequest.remote.url.rawValue)",
                "checkout: \(cloneRequest.checkout?.rawValue ?? "nil")",
                "destination: \(cloneRequest.destinationURL.path)",
                "credentials: \(cloneRequest.credentials == nil ? "missing" : "present")",
            ]
        ) {
            try await sourceControl.clone(cloneRequest)
        }
        try TangledSourcePatchPublisherDiagnostics.runSync(
            operation: "sourcePatchApplier.apply",
            details: [
                "repository: \(checkoutURL.path)",
                "fileChanges: \(preparedPatch.request.patch.fileChanges.count)",
            ]
        ) {
            try sourcePatchApplier.apply(
                preparedPatch.request.patch,
                checkoutURL
            )
        }

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
        targetRepository: TangledRepositoryTarget,
        branchName: BranchName,
        credentials: Credentials?,
        title: String
    ) async throws -> Commit {
        @Dependency(\.sourceControl) var sourceControl
        @Dependency(\.tangledSSHCredentials) var tangledSSHCredentials

        let repository = try await TangledSourcePatchPublisherDiagnostics.run(
            operation: "sourceControl.open",
            details: [
                "repository: \(preparedPatch.workingTree.workingRepositoryURL.path)",
            ]
        ) {
            try await sourceControl.open(
                preparedPatch.workingTree.workingRepositoryURL
            )
        }
        let changedPaths = preparedPatch.request.patch.fileChanges.map {
            RepositoryPath(rawValue: $0.path)
        }
        let stageRequest = StageRequest(
            repository: repository,
            paths: changedPaths
        )
        try await TangledSourcePatchPublisherDiagnostics.run(
            operation: "sourceControl.stage",
            details: [
                "repository: \(repository.url.path)",
                "fileChanges: \(changedPaths.count)",
                "paths: \(TangledSourcePatchPublisherDiagnostics.pathSummary(changedPaths))",
            ]
        ) {
            try await sourceControl.stage(stageRequest)
        }
        let commitRequest = CommitRequest(
            repository: repository,
            message: CommitMessage(rawValue: title),
            author: Author(
                name: PersonName(rawValue: "Open Music Event"),
                email: EmailAddress(rawValue: "noreply@openmusicevent.app")
            )
        )
        let commit = try await TangledSourcePatchPublisherDiagnostics.run(
            operation: "sourceControl.commit",
            details: [
                "repository: \(repository.url.path)",
                "message: \(TangledSourcePatchPublisherDiagnostics.singleLine(title))",
            ]
        ) {
            try await sourceControl.commit(commitRequest)
        }
        let createBranchRequest = CreateBranchRequest(
            repository: repository,
            name: branchName,
            startPoint: RefName(rawValue: commit.id.rawValue),
            checkout: false
        )
        let branch = try await TangledSourcePatchPublisherDiagnostics.run(
            operation: "sourceControl.createBranch",
            details: [
                "repository: \(repository.url.path)",
                "branch: \(createBranchRequest.name.rawValue)",
                "startPoint: \(createBranchRequest.startPoint.rawValue)",
                "checkout: \(createBranchRequest.checkout)",
            ]
        ) {
            try await sourceControl.createBranch(createBranchRequest)
        }
        let pushCredentials: Credentials
        if let credentials {
            TangledSourcePatchPublisherDiagnostics.log(
                operation: "tangledSSHCredentials.credentials",
                status: .skipped,
                details: [
                    "reason: temporary clone credentials already available",
                ]
            )
            pushCredentials = credentials
        } else {
            pushCredentials = try await TangledSourcePatchPublisherDiagnostics.run(
                operation: "tangledSSHCredentials.credentials",
                details: [
                    "reason: prepare git push",
                    "repository: \(targetRepository.knotHost.rawValue)/\(targetRepository.repositoryDID.description)",
                ]
            ) {
                try await tangledSSHCredentials.credentials()
            }
        }
        let pushRequest = PushRequest(
            repository: repository,
            localBranch: branch.name,
            remoteBranch: branch.name,
            credentials: targetRepository.sourceControlCredentials(
                pushCredentials
            )
        )
        try await TangledSourcePatchPublisherDiagnostics.run(
            operation: "sourceControl.push",
            details: [
                "repository: \(repository.url.path)",
                "remote: \(pushRequest.remote.rawValue)",
                "localBranch: \(pushRequest.localBranch.rawValue)",
                "remoteBranch: \(pushRequest.remoteBranch.rawValue)",
                "credentials: \(pushRequest.credentials == nil ? "missing" : "present")",
            ]
        ) {
            try await sourceControl.push(pushRequest)
        }
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

enum TangledSourcePatchPublisherDiagnostics {
    enum Status: String {
        case started
        case finished
        case failed
        case skipped
    }

    #if canImport(OSLog)
    private static let logger = Logger(
        subsystem: "fm.woody.openmusicevent",
        category: "TangledSourcePatchPublisher"
    )
    #endif

    static func run<Value>(
        operation: String,
        details: [String],
        _ body: () async throws -> Value
    ) async throws -> Value {
        log(operation: operation, status: .started, details: details)
        do {
            let value = try await body()
            log(operation: operation, status: .finished, details: details)
            return value
        } catch {
            log(operation: operation, status: .failed, details: details, error: error)
            throw error
        }
    }

    static func runSync<Value>(
        operation: String,
        details: [String],
        _ body: () throws -> Value
    ) throws -> Value {
        log(operation: operation, status: .started, details: details)
        do {
            let value = try body()
            log(operation: operation, status: .finished, details: details)
            return value
        } catch {
            log(operation: operation, status: .failed, details: details, error: error)
            throw error
        }
    }

    static func log(
        operation: String,
        status: Status,
        details: [String],
        error: Error? = nil
    ) {
        log(message(operation: operation, status: status, details: details, error: error))
    }

    static func message(
        operation: String,
        status: Status,
        details: [String],
        error: Error? = nil
    ) -> String {
        var lines = ["Tangled source patch \(operation) \(status.rawValue)"]
        lines.append(contentsOf: details)
        if let error {
            lines.append("error: \(String(describing: error))")
        }
        return lines.joined(separator: "\n")
    }

    static func pathSummary(_ paths: [RepositoryPath]) -> String {
        guard !paths.isEmpty else { return "none" }

        let visibleLimit = 12
        let visiblePaths = paths
            .prefix(visibleLimit)
            .map(\.rawValue)
            .joined(separator: ", ")

        if paths.count > visibleLimit {
            return "\(visiblePaths), ... (+\(paths.count - visibleLimit) more)"
        } else {
            return visiblePaths
        }
    }

    static func singleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func log(_ message: String) {
        #if canImport(OSLog)
        logger.log("\(message, privacy: .public)")
        #else
        print(message)
        #endif
    }
}

private struct GitBackedPreparedPatch: Sendable {
    var preparedPatch: PreparedSourcePatch
    var credentials: Credentials?
    var cleanupURL: URL?
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
