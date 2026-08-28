import ATProto
import ComposableWorkspace
import Dependencies
import Foundation
import OpenMusicEventSourceClone
#if canImport(OSLog)
import OSLog
#endif
import SourceControlClient
import SourceEditing
import TangledLexicon

/// Adapts Workspace's durable submission to Tangled's patch-only pull model.
///
/// Git is used only inside a temporary copy to create the Git-compatible replacement patch.
/// No proposal branch is created or sent to a remote repository.
struct TangledWorkspacePublisher: Sendable {
    var patchPublisher: TangledPatchOnlyProposalPublisher
    var patchGenerator: TangledReplacementPatchGenerator

    init(
        patchPublisher: TangledPatchOnlyProposalPublisher = .init(),
        patchGenerator: TangledReplacementPatchGenerator = .init()
    ) {
        self.patchPublisher = patchPublisher
        self.patchGenerator = patchGenerator
    }

    func publishProposal(
        source: SourceWorkspaceResource,
        workspaceID: SourceWorkspace.ID,
        submission: WorkspaceSubmission<SourcePatch>,
        persistence: WorkspacePublicationPersistence
    ) async throws -> WorkspaceProposal {
        guard source.workspace.id == workspaceID else {
            throw TangledWorkspacePublisherError.sourceWorkspaceMismatch(workspaceID)
        }
        if let proposal = try persistence.publishedProposal(
            workspaceID: workspaceID,
            submissionID: submission.id
        ) {
            return proposal
        }

        let request: TangledPatchOnlyProposalPublicationRequest
        if let prepared = try persistence.preparedPublication(
            workspaceID: workspaceID,
            submissionID: submission.id
        ) {
            request = prepared
        } else {
            request = try await preparePublication(
                source: source,
                submission: submission
            )
            try await persistence.savePreparedPublication(
                request,
                workspaceID: workspaceID,
                submissionID: submission.id
            )
        }

        let id = try await patchPublisher.publish(request)
        let proposal = WorkspaceProposal(
            id: id,
            revision: request.patch.currentRevision,
            target: submission.proposalTarget
        )
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
    case invalidAuthorRepository(String)
    case invalidProposalID(String)
    case missingRepositoryPDS(String)
    case repositoryRecordMissingRepoDID(String)
    case repositoryRecordNotFound(owner: String, repository: String)
    case sourceWorkspaceMismatch(SourceWorkspace.ID)
    case sourceNotTangled(String)
}

private extension TangledWorkspacePublisher {
    func preparePublication(
        source: SourceWorkspaceResource,
        submission: WorkspaceSubmission<SourcePatch>
    ) async throws -> TangledPatchOnlyProposalPublicationRequest {
        @Dependency(\.date.now) var now
        let context = try await PublishingContext.load(source.workspace.id)
        let address = try proposalAddress(submission)
        let patch = try await replacementPatch(
            source: source,
            submission: submission
        )
        return TangledPatchOnlyProposalPublicationRequest(
            authorRepository: address.authorRepository,
            recordKey: address.recordKey,
            target: TangledPatchOnlyProposalTarget(
                repositoryDID: context.targetRepository.repositoryDID,
                repositoryOwnerDID: try proposalDIDAuthority(
                    context.targetRepository.recordURI
                ),
                repositoryName: context.repository.repository,
                knotHost: context.targetRepository.knotHost
            ),
            title: submission.proposalTitle,
            body: submission.proposalBody,
            createdAt: ISO8601DateFormatter().string(from: now),
            patch: patch,
            previousProposal: submission.previousProposal
        )
    }

    func replacementPatch(
        source: SourceWorkspaceResource,
        submission: WorkspaceSubmission<SourcePatch>
    ) async throws -> TangledReplacementPatch {
        @Dependency(\.sourceControl) var sourceControl
        @Dependency(\.sourcePatchApplier) var patchApplier
        @Dependency(\.sourceWorkingTreeMaterializer) var materializer

        let workingTree = try materializer.materialize(source.repositoryURL, nil)
        defer {
            try? FileManager.default.removeItem(at: workingTree.workingRepositoryURL)
        }
        let repository = try await sourceControl.open(workingTree.workingRepositoryURL)
        let target = submission.proposalTarget
        try await sourceControl.checkout(
            CheckoutRequest(
                repository: repository,
                ref: RefName(rawValue: target.revision.rawValue)
            )
        )
        try patchApplier.apply(
            submission.changes,
            workingTree.workingRepositoryURL
        )
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
                message: CommitMessage(rawValue: submission.proposalTitle),
                author: Author(
                    name: PersonName(rawValue: "Open Music Event"),
                    email: EmailAddress(rawValue: "noreply@openmusicevent.app")
                )
            )
        )
        return try await patchGenerator.generate(
            repository: repository,
            baseRevision: target.revision,
            currentRevision: WorkspaceRevision(rawValue: commit.id.rawValue)
        )
    }

    struct ProposalAddress {
        var authorRepository: DID
        var recordKey: ATProto.Record.Key
    }

    func proposalAddress(
        _ submission: WorkspaceSubmission<SourcePatch>
    ) throws -> ProposalAddress {
        switch submission.target {
        case .createProposal:
            @Dependency(\.getDefaultSession) var getDefaultSession
            let description = getDefaultSession().accountID.rawValue.description
            guard let authorRepository = DID(description) else {
                throw TangledWorkspacePublisherError.invalidAuthorRepository(description)
            }
            return ProposalAddress(
                authorRepository: authorRepository,
                recordKey: ATProto.Record.Key(rawValue: submission.proposalRecordKey)
            )

        case let .updateProposal(proposal):
            guard let uri = ATProto.URI(proposal.id.rawValue),
                  uri.collection == TangledNSID.pull,
                  let recordKey = uri.rkey
            else {
                throw TangledWorkspacePublisherError.invalidProposalID(proposal.id.rawValue)
            }
            return ProposalAddress(
                authorRepository: try proposalDIDAuthority(uri),
                recordKey: recordKey
            )
        }
    }
}

private struct PublishingContext {
    var repository: TangledRepositoryReference
    var targetRepository: TangledRepositoryTarget

    static func load(_ workspaceID: SourceWorkspace.ID) async throws -> Self {
        let workspace = try SourceWorkspace(id: workspaceID)
        let repository = try TangledRepositoryReference(
            sourceReference: workspace.repository
        )
        let targetRepository = try await TangledWorkspacePublisher()
            .targetRepository(repository)
        return Self(
            repository: repository,
            targetRepository: targetRepository
        )
    }
}

private extension WorkspaceSubmission where ChangeSet == SourcePatch {
    var previousProposal: WorkspaceProposal? {
        guard case let .updateProposal(proposal) = target else { return nil }
        return proposal
    }

    var proposalBody: String? {
        guard case let .createProposal(_, details) = target else { return nil }
        return details.description
    }

    var proposalRecordKey: String {
        "ome-" + id.rawValue.uuidString
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
    }

    var proposalTarget: WorkspaceBranchReference {
        switch target {
        case let .createProposal(target, _):
            target
        case let .updateProposal(proposal):
            proposal.target
        }
    }

    var proposalTitle: String {
        switch target {
        case let .createProposal(_, details):
            details.title.rawValue
        case .updateProposal:
            "Update proposal"
        }
    }
}

func patchRevision(
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

func proposalDIDAuthority(_ uri: ATProto.URI) throws -> DID {
    switch uri.authority {
    case let .did(did):
        return did
    case .handle:
        throw TangledWorkspacePublisherError.invalidProposalID(uri.description)
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
