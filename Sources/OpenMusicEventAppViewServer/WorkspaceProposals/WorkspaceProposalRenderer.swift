import Dependencies
import FileTree
import Foundation
import GRDB
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
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
