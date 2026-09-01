import ATProto
import Crypto
import Dependencies
import FileTree
import Foundation
import GRDB
import HTTPClient
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import SourceEditing

struct WorkspaceProposalRenderer: Sendable {
    static let currentVersion = 1

    func render(
        workspace: SourceWorkspace,
        targetSourceURL: URL,
        patchData: Data
    ) async throws -> OME.WorkspaceProposal.Presentation {
        let patch = try SourcePatchGitPatchCodec().parse(patchData)
        let scratchRootURL = FileManager.default.temporaryDirectory
            .appending(
                path: "ome-workspace-proposal-render-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: scratchRootURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: scratchRootURL) }

        let proposedSourceURL = scratchRootURL.appending(
            path: "proposed-source",
            directoryHint: .isDirectory
        )
        try FileManager.default.copyItem(at: targetSourceURL, to: proposedSourceURL)
        try SourcePatchApplier.live.apply(patch, proposedSourceURL)

        let targetInsertion = try sourceInsertion(
            workspace: workspace,
            sourceURL: targetSourceURL
        )
        let proposedInsertion = try sourceInsertion(
            workspace: workspace,
            sourceURL: proposedSourceURL
        )
        let targetDatabase = try DatabaseQueue()
        let proposedDatabase = try DatabaseQueue()

        try await withDependencies {
            $0.localImageFileStore = .workspaceProposalScratch(
                rootURL: scratchRootURL.appending(path: "target-assets")
            )
        } operation: {
            try await targetInsertion.migrateAndInsert(into: targetDatabase)
        }
        try await withDependencies {
            $0.localImageFileStore = .workspaceProposalScratch(
                rootURL: scratchRootURL.appending(path: "proposed-assets")
            )
        } operation: {
            try await proposedInsertion.migrateAndInsert(into: proposedDatabase)
        }

        return try await proposedDatabase.read { workingDatabase in
            try targetDatabase.read { baselineDatabase in
                let summary = try openMusicEventSourceEditSummary(
                    workspace: workspace,
                    workingDatabase: workingDatabase,
                    baselineDatabase: baselineDatabase
                )
                let sourceFiles = try openMusicEventSourceFileAttributions(
                    patch: patch,
                    groups: summary.groups,
                    recordComparisons: summary.recordComparisons,
                    in: workingDatabase
                )
                return try SourceChangePresentationRenderer().render(
                    summary,
                    sourceFiles: sourceFiles
                )
            }
        }
    }
}

struct WorkspaceProposalRenderProcessor: Sendable {
    let configuration: TangledWebhookConfiguration
    let store: OpenMusicEventAppViewStore
    let renderer: WorkspaceProposalRenderer

    init(
        configuration: TangledWebhookConfiguration,
        store: OpenMusicEventAppViewStore,
        renderer: WorkspaceProposalRenderer = WorkspaceProposalRenderer()
    ) {
        self.configuration = configuration
        self.store = store
        self.renderer = renderer
    }

    func candidates() async throws -> [TangledWorkspaceProposal] {
        try await store.workspaceProposalRenderCandidates()
    }

    func process(_ proposal: TangledWorkspaceProposal) async throws {
        guard let request = try await request(for: proposal) else { return }
        if request.matches(proposal.renderInput), case .ready = proposal.renderState {
            return
        }

        @Dependency(\.httpClient) var httpClient
        let patchData: Data = try await withDependencies {
            $0.logBody = false
        } operation: {
            try await httpClient.get(request.patchURL, decodingTo: Data.self)
        }
        let input = TangledWorkspaceProposal.RenderInput(
            proposalRevision: request.proposalRevision,
            targetRevision: request.checkpoint.revision,
            roundNumber: request.roundNumber,
            patchDigest: Data(SHA256.hash(data: patchData)).base64EncodedString(),
            rendererVersion: WorkspaceProposalRenderer.currentVersion
        )
        let prepared = try await store.prepareWorkspaceProposalRender(
            id: proposal.id,
            input: input
        )
        if case .ready = prepared.renderState {
            return
        }

        @Dependency(\.tangledSourceCheckout) var sourceCheckout
        @Dependency(\.uuid) var uuid
        let targetSourceURL = TangledSourceCloner.temporaryOutputURL(uuid: uuid())
        defer { try? FileManager.default.removeItem(at: targetSourceURL) }
        let checkout = try await sourceCheckout.checkout(
            TangledSourceCheckoutRequest(
                repository: request.watch.repository,
                ref: request.checkpoint.revision,
                archive: SourceArchiveReference(
                    url: request.artifact.url,
                    checksumSHA256: request.artifact.checksumSHA256,
                    byteCount: request.artifact.byteCount
                ),
                outputURL: targetSourceURL
            )
        )
        let presentation = try await renderer.render(
            workspace: request.workspace,
            targetSourceURL: checkout.repositoryURL,
            patchData: patchData
        )
        _ = try await store.completeWorkspaceProposalRender(
            id: proposal.id,
            expectedInput: input,
            presentation: presentation
        )
    }

    private func request(
        for proposal: TangledWorkspaceProposal
    ) async throws -> Request? {
        guard proposal.lifecycle == .open,
              let webhook = proposal.webhook,
              case let .present(proposalRevision, _, pull) = proposal.record
        else {
            return nil
        }
        guard let watch = configuration.watchesByID[webhook.watchID] else {
            throw WorkspaceProposalRenderError.watchUnavailable(webhook.watchID)
        }
        guard pull.target.repo == watch.repositoryDID else {
            throw WorkspaceProposalRenderError.targetRepositoryMismatch(
                proposal: proposal.id.description,
                expected: watch.repositoryDID.description,
                actual: pull.target.repo.description
            )
        }
        let targetBranch = SourceWorkspace.normalizedBranch(pull.target.branch)
        let expectedBranch = SourceWorkspace.normalizedBranch(watch.ref)
        let webhookBranch = SourceWorkspace.normalizedBranch(webhook.value.targetBranch)
        guard targetBranch == expectedBranch, webhookBranch == targetBranch else {
            throw WorkspaceProposalRenderError.targetBranchMismatch(
                proposal: proposal.id.description,
                expected: expectedBranch,
                actual: targetBranch
            )
        }
        guard pull.rounds.indices.last == webhook.value.roundNumber else {
            return nil
        }
        guard let checkpoint = try await store.tangledSourceCheckpoint(watchID: watch.id),
              let artifact = checkpoint.publishedArtifact
        else {
            return nil
        }
        guard checkpoint.repositoryOwnerDID == watch.repositoryOwnerDID.description,
              checkpoint.repositoryKey == watch.repositoryKey.rawValue,
              SourceWorkspace.normalizedBranch(checkpoint.ref) == targetBranch,
              checkpoint.canonicalSourceReference == watch.canonicalSource.reference
        else {
            throw OpenMusicEventAppViewStoreError.tangledSourceWatchMismatch(
                watchID: watch.id.rawValue
            )
        }
        return Request(
            proposalRevision: proposalRevision,
            roundNumber: webhook.value.roundNumber,
            patchURL: webhook.value.patchURL,
            watch: watch,
            checkpoint: checkpoint,
            artifact: artifact,
            workspace: SourceWorkspace(
                organizerID: watch.canonicalSource.organizerID,
                repository: watch.canonicalSource.reference,
                branch: targetBranch
            )
        )
    }

    private struct Request: Sendable {
        let proposalRevision: ATProto.CID
        let roundNumber: Int
        let patchURL: URL
        let watch: TangledWebhookWatch
        let checkpoint: TangledSourceCheckpoint
        let artifact: PublishedSourceArtifact
        let workspace: SourceWorkspace

        func matches(_ input: TangledWorkspaceProposal.RenderInput?) -> Bool {
            guard let input else { return false }
            return input.proposalRevision == proposalRevision
                && input.targetRevision == checkpoint.revision
                && input.roundNumber == roundNumber
                && input.rendererVersion == WorkspaceProposalRenderer.currentVersion
        }
    }
}

enum WorkspaceProposalRenderError: Error, Equatable, Sendable {
    case watchUnavailable(WebhookInboxDelivery.WatchID)
    case targetRepositoryMismatch(proposal: String, expected: String, actual: String)
    case targetBranchMismatch(proposal: String, expected: String, actual: String)
}

private func sourceInsertion(
    workspace: SourceWorkspace,
    sourceURL: URL
) throws -> OME.SourceDatabaseInsertion {
    let source = try OpenMusicEventSourceRepositoryFileTree()
        .read(from: sourceURL)
        .output
        .requiredValue
    return try OME.SourceDatabaseInsertion(
        .init(
            source: source,
            organizerID: workspace.organizerID,
            sourceProvenance: workspace.sourceProvenance,
            sourceRootURL: sourceURL
        )
    )
}

private extension LocalImageFileStoreClient {
    static func workspaceProposalScratch(rootURL: URL) -> Self {
        Self { assetKey, data, _ in
            try FileManager.default.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
            let fileName = Data(assetKey.utf8)
                .base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            let imageURL = rootURL
                .appending(path: fileName.isEmpty ? "asset" : fileName)
                .appendingPathExtension("data")
            try data.write(to: imageURL, options: .atomic)
            return imageURL
        }
    }
}
