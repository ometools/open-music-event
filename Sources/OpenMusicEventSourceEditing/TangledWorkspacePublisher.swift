import ATProto
import ATProtoOAuth
import ComposableWorkspace
import Dependencies
import Foundation
import Gzip
import OpenMusicEventSourceClone
import SQLiteData
#if canImport(OSLog)
import OSLog
#endif
import SourceControlClient
import SourceEditing
import TangledLexicon
import TangledXRPC
import XRPCClient

struct TangledWorkspacePublisher: Sendable {
    func publishProposal(
        workspaceID: SourceWorkspace.ID,
        submission: WorkspaceSubmission<SourcePatch>,
        persistence: WorkspacePublicationPersistence
    ) async throws -> WorkspaceProposal {
        let commit = try await pushCommit(
            workspaceID: workspaceID,
            submission: submission,
            persistence: persistence
        )
        return try await recordProposal(
            workspaceID: workspaceID,
            submission: submission,
            commit: commit,
            persistence: persistence
        )
    }

    func pushCommit(
        workspaceID: SourceWorkspace.ID,
        submission: WorkspaceSubmission<SourcePatch>,
        persistence: WorkspacePublicationPersistence
    ) async throws -> SourceWorkspacePublicationCommit {
        if let commit = try persistence.pushedCommit(
            workspaceID: workspaceID,
            submissionID: submission.id
        ) {
            let context = try await PublishingContext.load(workspaceID)
            @Dependency(\.sourceWorkspaceStorage) var storage
            try await push(
                commit: commit,
                repositoryURL: storage.location(workspaceID).repositoryURL,
                context: context
            )
            return commit
        }

        let context = try await PublishingContext.load(workspaceID)
        @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
        try await authorizationBroker.authorize(
            TangledOAuthRequirements.proposalAuthRequirement
        )

        @Dependency(\.sourceControl) var sourceControl
        @Dependency(\.sourcePatchApplier) var patchApplier
        @Dependency(\.sourceWorkspaceStorage) var storage
        let repositoryURL = try storage.location(workspaceID).repositoryURL
        let repository = try await sourceControl.open(repositoryURL)
        let branch = try persistence.sourceBranch(
            workspaceID: workspaceID,
            submission: submission
        )
        switch submission.target {
        case .createProposal:
            try await sourceControl.checkout(
                CheckoutRequest(
                    repository: repository,
                    ref: RefName(
                        rawValue: submission.baseRevision.rawValue
                    )
                )
            )
            _ = try await sourceControl.createBranch(
                CreateBranchRequest(
                    repository: repository,
                    name: BranchName(rawValue: branch.rawValue),
                    startPoint: RefName(
                        rawValue: submission.baseRevision.rawValue
                    ),
                    checkout: true
                )
            )
        case .updateProposal:
            try await sourceControl.checkout(
                CheckoutRequest(
                    repository: repository,
                    ref: RefName(rawValue: branch.rawValue)
                )
            )
        }
        try patchApplier.apply(submission.changes, repositoryURL)
        try await sourceControl.stage(
            StageRequest(
                repository: repository,
                paths: submission.changes.fileChanges.map {
                    RepositoryPath(rawValue: $0.path)
                }
            )
        )
        let commit = try await sourceControl.commit(
            CommitRequest(
                repository: repository,
                message: CommitMessage(rawValue: submission.commitTitle),
                author: Author(
                    name: PersonName(rawValue: "Open Music Event"),
                    email: EmailAddress(rawValue: "noreply@openmusicevent.app")
                )
            )
        )
        let workspaceCommit = SourceWorkspacePublicationCommit(
            parentRevision: submission.baseRevision,
            source: WorkspaceBranchReference(
                branch: branch,
                revision: WorkspaceRevision(rawValue: commit.id.rawValue)
            )
        )
        try await persistence.savePushedCommit(
            workspaceCommit,
            workspaceID: workspaceID,
            submissionID: submission.id
        )
        try await push(
            commit: workspaceCommit,
            repositoryURL: repositoryURL,
            context: context
        )
        return workspaceCommit
    }

    func recordProposal(
        workspaceID: SourceWorkspace.ID,
        submission: WorkspaceSubmission<SourcePatch>,
        commit: SourceWorkspacePublicationCommit,
        persistence: WorkspacePublicationPersistence
    ) async throws -> WorkspaceProposal {
        if let proposal = try persistence.publishedProposal(
            workspaceID: workspaceID,
            submissionID: submission.id
        ) {
            return proposal
        }

        @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
        @Dependency(\.date.now) var now
        @Dependency(\.getDefaultSession) var getDefaultSession
        @Dependency(XRPC.Client.self) var xrpcClient
        try await authorizationBroker.authorize(
            TangledOAuthRequirements.proposalAuthRequirement
        )

        let session = getDefaultSession()
        let repo = session.accountID.rawValue.description
        let timestamp = try await persistence.proposalTimestamp(
            workspaceID: workspaceID,
            submissionID: submission.id
        ) {
            ISO8601DateFormatter().string(from: now)
        }
        let context = try await PublishingContext.load(workspaceID)
        let patchBlob = try await patchBlob(
            workspaceID: workspaceID,
            submission: submission,
            commit: commit,
            timestamp: timestamp,
            persistence: persistence
        )
        let round = TangledPullRecord.Round(
            patchBlob: patchBlob,
            createdAt: timestamp
        )

        let proposal: WorkspaceProposal
        switch submission.target {
        case let .createProposal(target, details):
            let rkey = ATProto.Record.Key(rawValue: submission.proposalRecordKey)
            let record = TangledPullRecord(
                target: TangledPullRecord.Target(
                    repo: context.targetRepository.repositoryDID,
                    branch: target.branch.rawValue
                ),
                title: details.title.rawValue,
                body: details.description,
                rounds: [round],
                source: TangledPullRecord.Source(branch: commit.source.branch.rawValue),
                createdAt: timestamp
            )
            let output = try await xrpcClient.run(
                TangledRepositoryRequests.putRecord(
                    repo: repo,
                    collection: .pull,
                    rkey: rkey,
                    record: record,
                    authorizationPolicy: .required(
                        TangledOAuthRequirements.proposalAuthRequirement
                    )
                )
            )
            proposal = WorkspaceProposal(
                id: WorkspaceProposalID(rawValue: output.uri.description),
                revision: commit.source.revision,
                target: target
            )

        case let .updateProposal(existingProposal):
            guard let uri = ATProto.URI(existingProposal.id.rawValue),
                  uri.collection == TangledNSID.pull,
                  let rkey = uri.rkey
            else {
                throw TangledWorkspacePublisherError.invalidProposalID(existingProposal.id.rawValue)
            }
            let existing = try await xrpcClient.run(
                TangledRepositoryRequests.getRecord(
                    TangledPullRecord.self,
                    repo: uri.authorDescription,
                    collection: .pull,
                    rkey: rkey
                )
            )
            let observedRevision = try await patchRevision(
                existing.value,
                authorDID: try requireDIDAuthority(uri)
            )
            if observedRevision == commit.source.revision {
                proposal = WorkspaceProposal(
                    id: existingProposal.id,
                    revision: commit.source.revision,
                    target: existingProposal.target
                )
                break
            }
            guard observedRevision == existingProposal.revision else {
                throw WorkspaceHeadMismatch(observedRevision: observedRevision)
            }
            var record = existing.value
            record.rounds.append(round)
            record.source = TangledPullRecord.Source(branch: commit.source.branch.rawValue)
            _ = try await xrpcClient.run(
                TangledRepositoryRequests.putRecord(
                    repo: uri.authorDescription,
                    collection: .pull,
                    rkey: rkey,
                    record: record,
                    swapRecord: existing.cid,
                    authorizationPolicy: .required(
                        TangledOAuthRequirements.proposalAuthRequirement
                    )
                )
            )
            proposal = WorkspaceProposal(
                id: existingProposal.id,
                revision: commit.source.revision,
                target: existingProposal.target
            )
        }

        try await persistence.savePublishedProposal(
            proposal,
            workspaceID: workspaceID,
            submissionID: submission.id
        )
        return proposal
    }

    func targetRepository(
        _ repository: TangledRepositoryReference
    ) async throws -> TangledRepositoryTarget {
        do {
            return try await repository.resolvedTangledRepositoryTarget()
        } catch let error as TangledRepositoryResolutionError {
            switch error {
            case let .missingRepositoryPDS(did):
                throw TangledWorkspacePublisherError.missingRepositoryPDS(did)
            case let .repositoryRecordMissingRepoDID(uri):
                throw TangledWorkspacePublisherError.repositoryRecordMissingRepoDID(uri)
            case let .repositoryRecordNotFound(owner, repository):
                throw TangledWorkspacePublisherError.repositoryRecordNotFound(
                    owner: owner,
                    repository: repository
                )
            }
        }
    }
}

enum TangledWorkspacePublisherError: Equatable, Error, Sendable {
    case invalidProposalID(String)
    case missingRepositoryPDS(String)
    case repositoryRecordMissingRepoDID(String)
    case repositoryRecordNotFound(owner: String, repository: String)
    case sourceCheckoutMissing(String)
    case sourceNotTangled(String)
    case sourceSelectionMissing(SourceWorkspace.ID)
}

private extension TangledWorkspacePublisher {
    func push(
        commit: SourceWorkspacePublicationCommit,
        repositoryURL: URL,
        context: PublishingContext
    ) async throws {
        @Dependency(\.sourceControl) var sourceControl
        let repository = try await sourceControl.open(repositoryURL)
        try await TangledWorkspacePublisherDiagnostics.run(
            operation: "sourceControl.push",
            details: [
                "repository: \(repositoryURL.path)",
                "branch: \(commit.source.branch.rawValue)",
                "revision: \(commit.source.revision.rawValue)",
            ]
        ) {
            try await sourceControl.push(
                PushRequest(
                    repository: repository,
                    localBranch: BranchName(rawValue: commit.source.branch.rawValue),
                    remoteBranch: BranchName(rawValue: commit.source.branch.rawValue),
                    credentials: context.repository.sourceControlCredentials(
                        context.credentials
                    )
                )
            )
        }
    }

    func patchBlob(
        workspaceID: SourceWorkspace.ID,
        submission: WorkspaceSubmission<SourcePatch>,
        commit: SourceWorkspacePublicationCommit,
        timestamp: String,
        persistence: WorkspacePublicationPersistence
    ) async throws -> ATProto.Blob {
        guard try persistence.pushedCommit(
            workspaceID: workspaceID,
            submissionID: submission.id
        ) != nil else {
            throw TangledWorkspacePublisherError.sourceCheckoutMissing(
                submission.id.rawValue.uuidString
            )
        }
        @Dependency(\.sourceControl) var sourceControl
        @Dependency(\.sourceWorkspaceStorage) var storage
        @Dependency(XRPC.Client.self) var xrpcClient
        let repositoryURL = try storage.location(workspaceID).repositoryURL
        let data = try await sourceControl.formatPatch(
            FormatPatchRequest(
                repository: Repository(url: repositoryURL),
                commit: CommitID(rawValue: commit.source.revision.rawValue)
            )
        )
        let createdAt = try ISO8601DateFormatter().date(from: timestamp)
            .required(TangledWorkspacePublisherError.sourceCheckoutMissing(timestamp))
        let text = try Self.formatPatchText(
            diffData: data,
            sourceRevision: commit.source.revision.rawValue,
            title: submission.commitTitle,
            createdAt: createdAt
        )
        return try await xrpcClient.tangledUploadPatchBlob(
            try Data(text.utf8).gzipped(),
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
        return body.hasSuffix("\n")
            ? body + "-- \nOpen Music Event\n"
            : body + "\n-- \nOpen Music Event\n"
    }

    static func formatPatchDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }
}

private struct PublishingContext {
    var credentials: Credentials
    var repository: TangledRepositoryReference
    var targetRepository: TangledRepositoryTarget

    static func load(_ workspaceID: SourceWorkspace.ID) async throws -> Self {
        @Dependency(\.tangledSSHCredentials) var tangledSSHCredentials
        let workspace = try SourceWorkspace(id: workspaceID)
        let repository = try TangledRepositoryReference(
            sourceReference: workspace.repository
        )
        let targetRepository = try await TangledWorkspacePublisher()
            .targetRepository(repository)
        let credentials = try await tangledSSHCredentials.readyCredentials(
            targetRepository.knotHost
        )
        return Self(
            credentials: credentials,
            repository: repository,
            targetRepository: targetRepository
        )
    }
}

private extension WorkspaceSubmission where ChangeSet == SourcePatch {
    var commitTitle: String {
        switch target {
        case let .createProposal(_, details):
            details.title.rawValue
        case .updateProposal:
            "Update proposal"
        }
    }

    var proposalRecordKey: String {
        "ome-" + id.rawValue.uuidString
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
    }

    var baseRevision: WorkspaceRevision {
        switch target {
        case let .createProposal(target, _):
            target.revision
        case let .updateProposal(proposal):
            proposal.revision
        }
    }
}

private extension WorkspacePublicationPersistence {
    func sourceBranch(
        workspaceID: SourceWorkspace.ID,
        submission: WorkspaceSubmission<SourcePatch>
    ) throws -> WorkspaceBranch {
        switch submission.target {
        case .createProposal:
            return WorkspaceBranch(
                rawValue: "ome/proposal-\(submission.id.rawValue.uuidString.lowercased())"
            )
        case .updateProposal:
            guard let selection = try database.read({ db in
                try SourceWorkspaceSelectionRecord.find(workspaceID).fetchOne(db)
            }) else {
                throw TangledWorkspacePublisherError.sourceSelectionMissing(workspaceID)
            }
            return WorkspaceBranch(rawValue: selection.branch)
        }
    }
}

private func patchRevision(
    _ pull: TangledPullRecord,
    authorDID: DID
) async throws -> WorkspaceRevision {
    let patch = try await patchTextForLatestRound(in: pull, authorDID: authorDID)
    guard let firstLine = patch.split(separator: "\n", maxSplits: 1).first,
          firstLine.hasPrefix("From ")
    else { throw TangledWorkspacePublisherError.invalidProposalID(pull.title) }
    let revision = firstLine.dropFirst("From ".count).split(separator: " ").first.map(String.init)
    guard let revision, !revision.isEmpty else {
        throw TangledWorkspacePublisherError.invalidProposalID(pull.title)
    }
    return WorkspaceRevision(rawValue: revision)
}

private func requireDIDAuthority(_ uri: ATProto.URI) throws -> DID {
    switch uri.authority {
    case let .did(did):
        return did
    case .handle:
        throw TangledWorkspacePublisherError.invalidProposalID(uri.description)
    }
}

private extension Optional {
    func required(_ error: @autoclosure () -> any Error) throws -> Wrapped {
        guard let self else { throw error() }
        return self
    }
}

enum TangledWorkspacePublisherDiagnostics {
    enum Status: String {
        case started
        case finished
        case failed
    }

    #if canImport(OSLog)
    private static let logger = Logger(
        subsystem: "fm.woody.openmusicevent",
        category: "TangledWorkspacePublisher"
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

    static func log(
        operation: String,
        status: Status,
        details: [String],
        error: (any Error)? = nil
    ) {
        var lines = ["Tangled workspace \(operation) \(status.rawValue)"]
        lines.append(contentsOf: details)
        if let error { lines.append("error: \(String(describing: error))") }
        let message = lines.joined(separator: "\n")
        #if canImport(OSLog)
        logger.log("\(message, privacy: .public)")
        #endif
        print(message)
    }
}
