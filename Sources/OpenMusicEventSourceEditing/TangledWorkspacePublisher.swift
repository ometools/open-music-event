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

/// Adapts Workspace's ephemeral attempt to OME's durable patch-only transport checkpoint.
///
/// Git is used only inside a temporary copy to create the Git-compatible replacement patch.
/// No proposal branch is created or sent to a remote repository.
struct TangledWorkspacePublisher: Sendable {
    var directPublisher: TangledDirectPublisher
    var patchPublisher: TangledPatchOnlyProposalPublisher
    var patchGenerator: TangledReplacementPatchGenerator

    init(
        directPublisher: TangledDirectPublisher = .init(),
        patchPublisher: TangledPatchOnlyProposalPublisher = .init(),
        patchGenerator: TangledReplacementPatchGenerator = .init()
    ) {
        self.directPublisher = directPublisher
        self.patchPublisher = patchPublisher
        self.patchGenerator = patchGenerator
    }

    func publishProposal(
        source: SourceWorkspaceResource,
        workspaceID: SourceWorkspace.ID,
        attempt: WorkspaceProposalAttempt<SourcePatch>,
        persistence: WorkspacePublicationPersistence
    ) async throws -> WorkspaceProposal {
        guard source.workspace.id == workspaceID else {
            throw TangledWorkspacePublisherError.sourceWorkspaceMismatch(workspaceID)
        }
        let checkpoint = try await persistence.checkpoint(
            workspaceID: workspaceID,
            attempt: attempt
        )
        if let proposal = try persistence.publishedProposal(
            workspaceID: workspaceID,
            checkpointID: checkpoint.id
        ) {
            await completePublication(
                proposal,
                workspaceID: workspaceID,
                persistence: persistence
            )
            return proposal
        }

        let request: TangledPatchOnlyProposalPublicationRequest
        if let prepared = try persistence.preparedPublication(
            workspaceID: workspaceID,
            checkpointID: checkpoint.id
        ) {
            request = prepared
        } else {
            request = try await preparePublication(
                source: source,
                checkpoint: checkpoint
            )
            try await persistence.savePreparedPublication(
                request,
                workspaceID: workspaceID,
                checkpointID: checkpoint.id
            )
        }

        let id = try await patchPublisher.publish(request)
        let proposal = WorkspaceProposal(
            id: id,
            revision: request.patch.currentRevision,
            target: checkpoint.proposalTarget
        )
        do {
            try await persistence.savePublishedProposal(
                proposal,
                checkpoint: checkpoint,
                workspaceID: workspaceID
            )
            await completePublication(
                proposal,
                workspaceID: workspaceID,
                persistence: persistence
            )
        } catch {
            // The Tangled record is the publication commit point. The prepared request retains
            // the same deterministic record key, so a later retry cannot create a duplicate.
            TangledWorkspacePublisherDiagnostics.log(
                operation: "publication.journal",
                status: .failed,
                details: [
                    "workspace: \(workspaceID.rawValue)",
                    "proposal: \(proposal.id.rawValue)",
                    "publication: recorded; local receipt will retry",
                ],
                error: error
            )
        }
        return proposal
    }

    func publishChanges(
        source: SourceWorkspaceResource,
        workspaceID: SourceWorkspace.ID,
        attempt: WorkspacePublicationAttempt<SourcePatch>
    ) async throws -> WorkspaceBranchReference {
        guard source.workspace.id == workspaceID else {
            throw TangledWorkspacePublisherError.sourceWorkspaceMismatch(workspaceID)
        }
        let context = try await PublishingContext.load(workspaceID)
        let patch = try await replacementPatch(
            source: source,
            changes: attempt.changes,
            target: attempt.target,
            title: attempt.details.title.rawValue
        )
        return try await directPublisher.publish(
            TangledDirectPublicationRequest(
                target: TangledPatchOnlyProposalTarget(
                    repositoryDID: context.targetRepository.repositoryDID,
                    repositoryOwnerDID: try proposalDIDAuthority(
                        context.targetRepository.recordURI
                    ),
                    repositoryName: context.repository.repository,
                    knotHost: context.targetRepository.knotHost
                ),
                branch: attempt.target.branch,
                title: attempt.details.title.rawValue,
                body: attempt.details.description,
                patch: patch
            )
        )
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
    func completePublication(
        _ proposal: WorkspaceProposal,
        workspaceID: SourceWorkspace.ID,
        persistence: WorkspacePublicationPersistence
    ) async {
        do {
            try await persistence.completePublication(workspaceID: workspaceID)
        } catch {
            TangledWorkspacePublisherDiagnostics.log(
                operation: "publication.cleanup",
                status: .failed,
                details: [
                    "workspace: \(workspaceID.rawValue)",
                    "proposal: \(proposal.id.rawValue)",
                    "publication: recorded; transport cleanup remains pending",
                ],
                error: error
            )
        }
    }

    func preparePublication(
        source: SourceWorkspaceResource,
        checkpoint: WorkspacePublicationCheckpoint
    ) async throws -> TangledPatchOnlyProposalPublicationRequest {
        @Dependency(\.date.now) var now
        let context = try await PublishingContext.load(source.workspace.id)
        let address = try proposalAddress(checkpoint)
        let patch = try await replacementPatch(
            source: source,
            checkpoint: checkpoint
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
            title: checkpoint.proposalTitle,
            body: checkpoint.proposalBody,
            createdAt: ISO8601DateFormatter().string(from: now),
            patch: patch
        )
    }

    func replacementPatch(
        source: SourceWorkspaceResource,
        checkpoint: WorkspacePublicationCheckpoint
    ) async throws -> TangledReplacementPatch {
        return try await replacementPatch(
            source: source,
            changes: checkpoint.changes,
            target: checkpoint.proposalTarget,
            title: checkpoint.proposalTitle
        )
    }

    func replacementPatch(
        source: SourceWorkspaceResource,
        changes: SourcePatch,
        target: WorkspaceBranchReference,
        title: String
    ) async throws -> TangledReplacementPatch {
        @Dependency(\.sourceControl) var sourceControl
        @Dependency(\.sourcePatchApplier) var patchApplier
        @Dependency(\.sourceWorkingTreeMaterializer) var materializer

        let workingTree = try materializer.materialize(source.repositoryURL, nil)
        defer {
            try? FileManager.default.removeItem(at: workingTree.workingRepositoryURL)
        }
        let repository = try await sourceControl.open(workingTree.workingRepositoryURL)
        let baseCommit = try await sourceControl.resolveRevision(
            ResolveRevisionRequest(
                repository: repository,
                ref: RefName(rawValue: "HEAD")
            )
        )
        try patchApplier.apply(
            changes,
            workingTree.workingRepositoryURL
        )
        try await sourceControl.stage(
            StageRequest(
                repository: repository,
                paths: changes.fileChanges.map {
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
        return try await patchGenerator.generate(
            repository: repository,
            baseRevision: target.revision,
            baseCommit: baseCommit,
            currentRevision: WorkspaceRevision(rawValue: commit.id.rawValue)
        )
    }

    struct ProposalAddress {
        var authorRepository: DID
        var recordKey: ATProto.Record.Key
    }

    func proposalAddress(
        _ checkpoint: WorkspacePublicationCheckpoint
    ) throws -> ProposalAddress {
        @Dependency(\.getDefaultSession) var getDefaultSession
        let description = getDefaultSession().accountID.rawValue.description
        guard let authorRepository = DID(description) else {
            throw TangledWorkspacePublisherError.invalidAuthorRepository(description)
        }
        return ProposalAddress(
            authorRepository: authorRepository,
            recordKey: ATProto.Record.Key(rawValue: checkpoint.proposalRecordKey)
        )
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

private extension WorkspacePublicationCheckpoint {
    var proposalBody: String? {
        return details.description
    }

    var proposalRecordKey: String {
        "ome-" + id.uuidString
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
    }

    var proposalTarget: WorkspaceBranchReference {
        target
    }

    var proposalTitle: String {
        details.title.rawValue
    }
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
