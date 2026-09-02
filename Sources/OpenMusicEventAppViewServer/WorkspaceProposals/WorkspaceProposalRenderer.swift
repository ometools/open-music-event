import ATProto
import Crypto
import Dependencies
import FileTree
import Foundation
import GRDB
import IssueReporting
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import ServiceLifecycle

struct WorkspaceProposalRenderer: Sendable {
    static let currentVersion = 1

    func render(
        workspace: SourceWorkspace,
        targetSourceURL: URL,
        patchData: Data
    ) async throws -> OME.WorkspaceProposal.Presentation {
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
        try applyGitPatch(
            patchData,
            to: proposedSourceURL,
            scratchRootURL: scratchRootURL
        )

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

enum WorkspaceProposalGitPatchError: Equatable, Error, Sendable {
    case applicationFailed(status: Int32, message: String)
    case symbolicLink(String)
}

private func applyGitPatch(
    _ patchData: Data,
    to sourceURL: URL,
    scratchRootURL: URL
) throws {
    let patchURL = scratchRootURL.appending(path: "proposal.patch")
    try patchData.write(to: patchURL, options: .atomic)

    let standardErrorURL = scratchRootURL.appending(path: "git-apply.stderr")
    try Data().write(to: standardErrorURL)
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/env")
    process.arguments = [
        "git",
        "-C",
        sourceURL.path(percentEncoded: false),
        "apply",
        "--no-index",
        "--",
        patchURL.path(percentEncoded: false),
    ]
    do {
        let standardError = try FileHandle(forWritingTo: standardErrorURL)
        defer { try? standardError.close() }
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
    }

    let standardErrorReader = try FileHandle(forReadingFrom: standardErrorURL)
    defer { try? standardErrorReader.close() }
    let message = String(
        decoding: try standardErrorReader.read(upToCount: 4_096) ?? Data(),
        as: UTF8.self
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    guard process.terminationStatus == 0 else {
        throw WorkspaceProposalGitPatchError.applicationFailed(
            status: process.terminationStatus,
            message: message
        )
    }

    let resourceKeys: Set<URLResourceKey> = [.isSymbolicLinkKey]
    guard let enumerator = FileManager.default.enumerator(
        at: sourceURL,
        includingPropertiesForKeys: Array(resourceKeys)
    ) else {
        return
    }
    for case let url as URL in enumerator {
        guard try url.resourceValues(forKeys: resourceKeys).isSymbolicLink == true else {
            continue
        }
        throw WorkspaceProposalGitPatchError.symbolicLink(
            url.path(percentEncoded: false)
        )
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

        let patchData: Data = try await withDependencies {
            $0.logBody = false
        } operation: {
            try await tangledPullPatchData(
                for: request.patchBlob,
                authorDID: request.authorDID
            )
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
              case let .present(proposalRevision, _, pull) = proposal.record
        else {
            return nil
        }
        guard case let .did(authorDID) = proposal.id.authority else {
            throw WorkspaceProposalRenderError.invalidProposalAuthor(
                proposal.id.description
            )
        }
        guard let watch = configuration.watches.first(where: {
            $0.repositoryDID == pull.target.repo
        }) else {
            throw WorkspaceProposalRenderError.targetRepositoryUnavailable(
                pull.target.repo.description
            )
        }
        let targetBranch = SourceWorkspace.normalizedBranch(pull.target.branch)
        let expectedBranch = SourceWorkspace.normalizedBranch(watch.ref)
        guard targetBranch == expectedBranch else {
            throw WorkspaceProposalRenderError.targetBranchMismatch(
                proposal: proposal.id.description,
                expected: expectedBranch,
                actual: targetBranch
            )
        }
        guard let latestRound = pull.rounds.enumerated().max(by: {
            $0.element.createdAt < $1.element.createdAt
        }) else {
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
            authorDID: authorDID,
            roundNumber: latestRound.offset,
            patchBlob: latestRound.element.patchBlob,
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
        let authorDID: DID
        let roundNumber: Int
        let patchBlob: ATProto.Blob
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

struct WorkspaceProposalRenderService: Service {
    let processor: WorkspaceProposalRenderProcessor
    let clock = ContinuousClock()

    func run() async throws {
        do {
            try await cancelWhenGracefulShutdown {
                while true {
                    for proposal in try await processor.candidates() {
                        do {
                            try await processor.process(proposal)
                        } catch {
                            reportIssue(error)
                        }
                    }
                    try await clock.sleep(for: .seconds(2))
                }
            }
        } catch is CancellationError {
        }
    }
}

enum WorkspaceProposalRenderError: Error, Equatable, Sendable {
    case invalidProposalAuthor(String)
    case targetRepositoryUnavailable(String)
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
