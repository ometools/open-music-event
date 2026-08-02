import ComposableWorkspace
import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import SourceEditing
import SQLiteData

public extension WorkspaceReferenceUpdateClient {
    static var openMusicEvent: Self {
        Self(
            advance: { source, workspaceID, submission, _ in
                @Dependency(
                    SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self
                ) var patchGenerator
                @Dependency(\.defaultDatabase) var database
                @Dependency(\.sourcePatchApplier) var patchApplier
                @Dependency(\.sourceWorkingTreeMaterializer) var materializer

                let context = try await WorkspaceReferenceContext.load(
                    workspaceID,
                    database: database
                )
                let currentChanges = try await withDependencies {
                    $0.defaultDatabase = source.database
                } operation: {
                    try await patchGenerator.generate(context.patchRequest)
                }

                let referenceTree = try materializer.materialize(
                    context.repositoryURL,
                    nil
                )
                defer {
                    try? FileManager.default.removeItem(at: referenceTree.workingRepositoryURL)
                }
                try patchApplier.apply(
                    submission.changes,
                    referenceTree.workingRepositoryURL
                )

                let workingTree = try materializer.materialize(
                    context.repositoryURL,
                    nil
                )
                defer {
                    try? FileManager.default.removeItem(at: workingTree.workingRepositoryURL)
                }
                try patchApplier.apply(
                    currentChanges,
                    workingTree.workingRepositoryURL
                )

                let referenceInsertion = try context.insertion(
                    repositoryURL: referenceTree.workingRepositoryURL
                )
                let workingInsertion = try context.insertion(
                    repositoryURL: workingTree.workingRepositoryURL
                )
                try await referenceInsertion.migrateAndInsert(
                    rebasedWorkingCopy: workingInsertion,
                    into: database
                )

                // This repository is the filesystem half of the same reference. Applying the
                // frozen capture is idempotent and intentionally excludes later database edits.
                try patchApplier.apply(submission.changes, context.repositoryURL)
            },
            reconcile: { source, workspaceID, reconciliation in
                @Dependency(
                    SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self
                ) var patchGenerator
                @Dependency(\.defaultDatabase) var database
                @Dependency(\.sourcePatchApplier) var patchApplier
                @Dependency(\.sourceRepositoryStorage) var repositoryStorage
                @Dependency(\.sourceWorkingTreeMaterializer) var materializer
                @Dependency(\.tangledSourceCheckout) var checkout
                @Dependency(\.uuid) var uuid

                let context = try await WorkspaceReferenceContext.load(
                    workspaceID,
                    database: database
                )
                guard context.sourceBaseline.sourceKind == .tangled else {
                    return reconciliation.expected
                }
                let currentChanges = try await withDependencies {
                    $0.defaultDatabase = source.database
                } operation: {
                    try await patchGenerator.generate(context.patchRequest)
                }

                let remoteURL = SourceRepositoryStorageClient.temporaryDownloadURL(uuid: uuid())
                defer { try? FileManager.default.removeItem(at: remoteURL) }
                let remote = try await checkout.checkout(
                    TangledSourceCheckoutRequest(
                        repository: try TangledRepositoryReference(
                            sourceReference: context.sourceBaseline.sourceReference
                        ),
                        ref: reconciliation.target.editingReference.branch.rawValue,
                        outputURL: remoteURL
                    )
                )
                let workingTree = try materializer.materialize(remote.repositoryURL, nil)
                defer {
                    try? FileManager.default.removeItem(at: workingTree.workingRepositoryURL)
                }
                try patchApplier.apply(currentChanges, workingTree.workingRepositoryURL)

                let referenceInsertion = try context.insertion(
                    repositoryURL: remote.repositoryURL
                )
                let workingInsertion = try context.insertion(
                    repositoryURL: workingTree.workingRepositoryURL
                )
                try await referenceInsertion.migrateAndInsert(
                    rebasedWorkingCopy: workingInsertion,
                    into: database
                )
                _ = try repositoryStorage.store(
                    remote.repositoryURL,
                    context.sourceBaseline.sourceProvenance
                )

                let revision = reconciliation.observedRevision ?? WorkspaceRevision(
                    rawValue: "\(reconciliation.target.editingReference.branch.rawValue)@reconciled"
                )
                switch reconciliation.target {
                case let .canonical(reference):
                    return .canonical(
                        WorkspaceBranchReference(
                            branch: reference.branch,
                            revision: revision
                        )
                    )
                case let .proposal(proposal):
                    return .proposal(
                        WorkspaceProposal(
                            id: proposal.id,
                            source: WorkspaceBranchReference(
                                branch: proposal.source.branch,
                                revision: revision
                            ),
                            target: proposal.target
                        )
                    )
                }
            }
        )
    }
}

private struct WorkspaceReferenceContext {
    var organizerID: OME.Organizer.ID
    var repositoryURL: URL
    var sourceBaseline: SourceBaselineRecord

    var patchRequest: OpenMusicEventCalendarSourcePatchRequest {
        OpenMusicEventCalendarSourcePatchRequest(
            calendarID: OME.Calendar.ID(
                ownerID: organizerID,
                calendarID: OME.Calendar.defaultID
            ),
            sourceBaselineID: sourceBaseline.id
        )
    }

    static func load(
        _ workspaceID: EditingWorkspaceRecord.ID,
        database: any DatabaseReader
    ) async throws -> Self {
        @Dependency(\.sourceRepositoryStorage) var repositoryStorage
        let (sourceBaseline, organizerID) = try await database.read { db in
            guard let workspace = try EditingWorkspaceRecord.find(workspaceID).fetchOne(db)
            else { throw WorkspaceReferenceUpdateError.workspaceNotFound(workspaceID) }
            guard let sourceBaselineID = workspace.sourceBaselineID,
                  let sourceBaseline = try SourceBaselineRecord.find(sourceBaselineID).fetchOne(db)
            else { throw WorkspaceReferenceUpdateError.sourceBaselineNotFound(workspaceID) }
            let organizerID = try workspace.publicRecord?.author
                ?? EventSourceProvenanceRecord
                    .where { $0.sourceBaselineID.eq(sourceBaselineID) }
                    .fetchOne(db)?
                    .id
                    .organizerID
            guard let organizerID else {
                throw WorkspaceReferenceUpdateError.organizerNotFound(workspaceID)
            }
            return (sourceBaseline, organizerID)
        }
        return Self(
            organizerID: organizerID,
            repositoryURL: try repositoryStorage.repositoryURL(sourceBaseline.sourceProvenance),
            sourceBaseline: sourceBaseline
        )
    }

    func insertion(repositoryURL: URL) throws -> OME.SourceDatabaseInsertion {
        let result = try OpenMusicEventSourceRepositoryFileTree().read(from: repositoryURL)
        return try OME.SourceDatabaseInsertion(
            .init(
                source: try result.output.requiredValue,
                organizerID: organizerID,
                sourceProvenance: sourceBaseline.sourceProvenance,
                sourceRootURL: repositoryURL
            )
        )
    }
}

private enum WorkspaceReferenceUpdateError: Error {
    case organizerNotFound(EditingWorkspaceRecord.ID)
    case sourceBaselineNotFound(EditingWorkspaceRecord.ID)
    case workspaceNotFound(EditingWorkspaceRecord.ID)
}
