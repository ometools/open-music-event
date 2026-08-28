import ComposableWorkspace
import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import SourceControlClient
import SourceEditing
import SQLiteData

public typealias SourceWorkspaceRevisionResolver = @Sendable (
    _ repository: Repository,
    _ ref: RefName
) async throws -> CommitID

struct SourceWorkspaceCheckoutClient: Sendable {
    var checkout: @Sendable (
        _ workspace: SourceWorkspace,
        _ outputURL: URL
    ) async throws -> SourceWorkspaceCheckout
}

struct SourceWorkspaceCheckout: Equatable, Sendable {
    var repository: Repository
    var reference: WorkspaceBranchReference
}

extension SourceWorkspaceCheckoutClient: DependencyKey {
    static var liveValue: Self {
        Self { workspace, outputURL in
            @Dependency(\.sourceControl) var sourceControl
            @Dependency(\.tangledDefaultBranch) var defaultBranch
            @Dependency(\.tangledSourceCheckout) var sourceCheckout

            let outputExisted = FileManager.default.fileExists(atPath: outputURL.path)
            var completed = false
            defer {
                if !outputExisted && !completed {
                    try? FileManager.default.removeItem(at: outputURL)
                }
            }
            let sourceReference = try TangledRepositoryReference(
                sourceReference: workspace.repository
            )
            let reference = try await defaultBranch.resolve(sourceReference)
            _ = try await sourceCheckout.checkout(
                TangledSourceCheckoutRequest(
                    repository: sourceReference,
                    ref: reference.revision.rawValue,
                    outputURL: outputURL
                )
            )
            let paths = try archiveRepositoryPaths(at: outputURL)
            let repository = try await sourceControl.initialize(outputURL)
            try await sourceControl.stage(
                StageRequest(repository: repository, paths: paths)
            )
            _ = try await sourceControl.commit(
                CommitRequest(
                    repository: repository,
                    message: CommitMessage(
                        rawValue: "Import source at \(reference.revision.rawValue)"
                    ),
                    author: Author(
                        name: PersonName(rawValue: "Open Music Event"),
                        email: EmailAddress(rawValue: "noreply@openmusicevent.app")
                    )
                )
            )
            completed = true
            return SourceWorkspaceCheckout(repository: repository, reference: reference)
        }
    }

    static var testValue: Self { liveValue }
}

public extension SourceWorkspacePreparationClient {
    static func openMusicEvent(
        resolveRevision: @escaping SourceWorkspaceRevisionResolver
    ) -> Self {
        Self { workspace in
            try await SourceWorkspacePreparationCoordinator.shared.prepare(workspace) {
                try await prepareOpenMusicEventSourceWorkspace(
                    workspace,
                    resolveRevision: resolveRevision
                )
            }
        }
    }
}

public extension WorkspaceReferenceUpdateClient {
    static func openMusicEvent(
        resolveRevision: @escaping SourceWorkspaceRevisionResolver
    ) -> Self {
        @Dependency(\.defaultDatabase) var mainDatabase

        return Self(
            advance: { source, workspaceID, submission, proposal in
                guard source.workspace.id == workspaceID else {
                    throw SourceWorkspaceDatabaseError.resourceMismatch(workspaceID)
                }
                guard source.applicationDatabaseID == ObjectIdentifier(mainDatabase) else {
                    throw SourceWorkspaceDatabaseError.applicationDatabaseMismatch(workspaceID)
                }
                guard submission.proposalTarget == proposal.target else {
                    throw SourceWorkspaceDatabaseError.proposalTargetMismatch(proposal.id)
                }
                let referenceRevision = try source.referenceDatabase.read { db in
                    try SourceWorkspaceReferenceRecord.find(workspaceID).fetchOne(db)?.revision
                }
                let persisted = try await mainDatabase.read { db in
                    (
                        installation: try SourceWorkspaceInstallationRecord
                            .find(workspaceID)
                            .fetchOne(db),
                        selection: try SourceWorkspaceSelectionRecord
                            .find(workspaceID)
                            .fetchOne(db)
                    )
                }
                let selectedReference = persisted.selection.map {
                    WorkspaceBranchReference(
                        branch: WorkspaceBranch(rawValue: $0.branch),
                        revision: WorkspaceRevision(rawValue: $0.revision)
                    )
                }
                guard referenceRevision == proposal.target.revision.rawValue,
                      persisted.installation?.revision == proposal.target.revision.rawValue,
                      selectedReference == proposal.target
                else {
                    throw SourceWorkspaceDatabaseError.persistedProposalTargetMismatch(
                        expected: proposal.target,
                        observed: selectedReference
                    )
                }
                @Dependency(\.sourcePatchApplier) var patchApplier
                @Dependency(\.sourceWorkingTreeMaterializer) var materializer
                let proposedTree = try materializer.materialize(
                    source.repositoryURL,
                    nil
                )
                defer {
                    try? FileManager.default.removeItem(
                        at: proposedTree.workingRepositoryURL
                    )
                }
                try patchApplier.apply(
                    submission.changes,
                    proposedTree.workingRepositoryURL
                )
                let proposedInsertion = try sourceInsertion(
                    workspace: source.workspace,
                    repositoryURL: proposedTree.workingRepositoryURL
                )
                try await proposedInsertion.replaceSourceWorkspace(
                    source.workspace,
                    branch: proposal.target.branch.rawValue,
                    revision: proposal.target.revision.rawValue,
                    in: source.referenceDatabase.database
                )
                try await saveReferenceRevision(
                    proposal.target.revision.rawValue,
                    workspaceID: workspaceID,
                    database: source.referenceDatabase.database
                )
                try await SourceWorkspaceOpenProposalStore(database: mainDatabase)
                    .save(proposal, workspaceID: workspaceID)
            },
            reconcile: { source, workspaceID, reconciliation in
                guard source.workspace.id == workspaceID else {
                    throw SourceWorkspaceDatabaseError.resourceMismatch(workspaceID)
                }
                guard source.applicationDatabaseID == ObjectIdentifier(mainDatabase) else {
                    throw SourceWorkspaceDatabaseError.applicationDatabaseMismatch(workspaceID)
                }
                @Dependency(SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self)
                var patchGenerator
                @Dependency(\.sourcePatchApplier) var patchApplier
                @Dependency(\.sourceWorkingTreeMaterializer) var materializer
                @Dependency(SourceWorkspaceCheckoutClient.self) var checkout

                let proposalStore = SourceWorkspaceOpenProposalStore(database: mainDatabase)
                let persistedProposal = try proposalStore.load(workspaceID)
                if case let .proposal(expectedProposal) = reconciliation.expected,
                   persistedProposal != expectedProposal {
                    throw SourceWorkspaceDatabaseError.proposalContextMismatch(
                        expectedProposal.id
                    )
                }
                if case let .proposal(expectedProposal) = reconciliation.expected,
                   case let .published(targetBranch) = reconciliation.destination,
                   expectedProposal.target.branch == targetBranch {
                    // The remote review is already merged. Closing that relationship is durable
                    // even if selecting or refreshing its target branch subsequently fails.
                    try await proposalStore.save(nil, workspaceID: workspaceID)
                }
                let expectedReference = reconciliation.expected.selectedReference
                let destinationBranch = reconciliation.destination.editingBranch
                let repository = Repository(url: source.repositoryURL)
                _ = try await resolveRevision(
                    repository,
                    RefName(rawValue: "HEAD")
                )
                let referenceDatabase = source.referenceDatabase
                let referenceRevision = try referenceDatabase.read { db in
                    try SourceWorkspaceReferenceRecord.find(workspaceID).fetchOne(db)?.revision
                }
                let persisted = try await mainDatabase.read { db in
                    (
                        installation: try SourceWorkspaceInstallationRecord
                            .find(workspaceID)
                            .fetchOne(db),
                        selection: try SourceWorkspaceSelectionRecord
                            .find(workspaceID)
                            .fetchOne(db)
                    )
                }
                let selectedReference = persisted.selection.map {
                    WorkspaceBranchReference(
                        branch: WorkspaceBranch(rawValue: $0.branch),
                        revision: WorkspaceRevision(rawValue: $0.revision)
                    )
                }
                guard referenceRevision == expectedReference.revision.rawValue,
                      persisted.installation?.revision == expectedReference.revision.rawValue,
                      selectedReference == expectedReference
                else {
                    throw SourceWorkspaceDatabaseError.persistedReconciliationReferenceMismatch(
                        expected: expectedReference,
                        observed: selectedReference,
                        referenceRevision: referenceRevision,
                        installationRevision: persisted.installation?.revision
                    )
                }

                if case let .proposal(id, targetBranch) = reconciliation.destination {
                    guard case let .proposal(proposal) = reconciliation.expected,
                          proposal.id == id,
                          proposal.target.branch == targetBranch
                    else {
                        throw SourceWorkspaceDatabaseError.proposalContextMismatch(id)
                    }
                    if let observedRevision = reconciliation.observedRevision,
                       observedRevision != proposal.revision {
                        throw SourceWorkspaceDatabaseError.proposalRevisionRequiresRefresh(
                            expected: proposal.revision.rawValue,
                            observed: observedRevision.rawValue
                        )
                    }
                    return .proposal(proposal)
                }

                guard case .published = reconciliation.destination else {
                    throw SourceWorkspaceDatabaseError.branchSelectionRequiresExactReference(
                        destinationBranch.rawValue
                    )
                }

                // The archive repository remains the upstream replacement-patch base after a
                // proposal is published. Reconstruct the accepted proposal-round baseline from
                // its database, then ask Git for only the unpublished delta beyond that baseline.
                let referenceChanges = try await withDependencies {
                    $0.defaultDatabase = referenceDatabase.database
                } operation: {
                    try await patchGenerator.generate(
                        SourceWorkspacePatchRequest(workspace: source.workspace)
                    )
                }
                let previousReferenceTree = try materializer.materialize(
                    source.repositoryURL,
                    nil
                )
                defer {
                    try? FileManager.default.removeItem(
                        at: previousReferenceTree.workingRepositoryURL
                    )
                }
                if !referenceChanges.isEmpty {
                    try patchApplier.apply(
                        referenceChanges,
                        previousReferenceTree.workingRepositoryURL
                    )
                }
                let previousReferenceInsertion = try sourceInsertion(
                    workspace: source.workspace,
                    repositoryURL: previousReferenceTree.workingRepositoryURL
                )
                let currentChanges = try await patchGenerator.generate(
                    SourceWorkspacePatchRequest(
                        workspace: source.workspace,
                        baseRepositoryURL: previousReferenceTree.workingRepositoryURL
                    )
                )
                let switchesBranch = destinationBranch != expectedReference.branch
                guard !switchesBranch || currentChanges.isEmpty else {
                    throw SourceWorkspaceDatabaseError.localChangesPreventBranchSwitch(
                        expectedReference.branch.rawValue,
                        destinationBranch.rawValue
                    )
                }
                let previousWorkingInsertion: OME.SourceDatabaseInsertion
                var previousWorkingTree: SourceWorkingTree?
                if currentChanges.isEmpty {
                    previousWorkingInsertion = previousReferenceInsertion
                } else {
                    let workingTree = try materializer.materialize(
                        previousReferenceTree.workingRepositoryURL,
                        nil
                    )
                    previousWorkingTree = workingTree
                    try patchApplier.apply(
                        currentChanges,
                        workingTree.workingRepositoryURL
                    )
                    previousWorkingInsertion = try sourceInsertion(
                        workspace: source.workspace,
                        repositoryURL: workingTree.workingRepositoryURL
                    )
                }
                defer {
                    if let previousWorkingTree {
                        try? FileManager.default.removeItem(
                            at: previousWorkingTree.workingRepositoryURL
                        )
                    }
                }
                let preparedRepositoryURL = source.repositoryURL
                    .deletingLastPathComponent()
                    .appending(path: "repository-refresh-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: preparedRepositoryURL) }
                do {
                    let refreshed = try await checkout.checkout(
                        source.workspace,
                        preparedRepositoryURL
                    )
                    guard refreshed.reference.branch == destinationBranch else {
                        throw SourceWorkspaceDatabaseError.defaultBranchChanged(
                            expected: destinationBranch.rawValue,
                            observed: refreshed.reference.branch.rawValue
                        )
                    }
                    if let observedRevision = reconciliation.observedRevision,
                       observedRevision != refreshed.reference.revision {
                        throw SourceWorkspaceDatabaseError.unexpectedRevision(
                            expected: observedRevision.rawValue,
                            observed: refreshed.reference.revision.rawValue
                        )
                    }

                    let referenceInsertion = try sourceInsertion(
                        workspace: source.workspace,
                        repositoryURL: preparedRepositoryURL
                    )
                    let workingInsertion: OME.SourceDatabaseInsertion
                    var workingTree: SourceWorkingTree?
                    if currentChanges.isEmpty {
                        workingInsertion = referenceInsertion
                    } else {
                        let materialized = try materializer.materialize(
                            preparedRepositoryURL,
                            nil
                        )
                        workingTree = materialized
                        try patchApplier.apply(
                            currentChanges,
                            materialized.workingRepositoryURL
                        )
                        workingInsertion = try sourceInsertion(
                            workspace: source.workspace,
                            repositoryURL: materialized.workingRepositoryURL
                        )
                    }
                    defer {
                        if let workingTree {
                            try? FileManager.default.removeItem(
                                at: workingTree.workingRepositoryURL
                            )
                        }
                    }

                    try await referenceInsertion.replaceSourceWorkspace(
                        source.workspace,
                        branch: destinationBranch.rawValue,
                        revision: refreshed.reference.revision.rawValue,
                        in: referenceDatabase.database
                    )
                    try await saveReferenceRevision(
                        refreshed.reference.revision.rawValue,
                        workspaceID: workspaceID,
                        database: referenceDatabase.database
                    )
                    try await workingInsertion.replaceSourceWorkspace(
                        source.workspace,
                        branch: destinationBranch.rawValue,
                        revision: refreshed.reference.revision.rawValue,
                        in: mainDatabase
                    )
                    try await saveWorkspaceSelection(
                        branch: destinationBranch.rawValue,
                        revision: refreshed.reference.revision.rawValue,
                        workspaceID: workspaceID,
                        database: mainDatabase
                    )
                    let backupRepositoryURL = try replaceRepository(
                        at: source.repositoryURL,
                        with: preparedRepositoryURL
                    )
                    try? FileManager.default.removeItem(at: backupRepositoryURL)
                    return .published(refreshed.reference)
                } catch {
                    let reconciliationError = error
                    var rollbackFailures: [String] = []
                    do {
                        try await previousReferenceInsertion.replaceSourceWorkspace(
                            source.workspace,
                            branch: expectedReference.branch.rawValue,
                            revision: expectedReference.revision.rawValue,
                            in: referenceDatabase.database
                        )
                        try await saveReferenceRevision(
                            expectedReference.revision.rawValue,
                            workspaceID: workspaceID,
                            database: referenceDatabase.database
                        )
                    } catch {
                        rollbackFailures.append(
                            "Reference database: \(String(describing: error))"
                        )
                    }
                    do {
                        try await previousWorkingInsertion.replaceSourceWorkspace(
                            source.workspace,
                            branch: expectedReference.branch.rawValue,
                            revision: expectedReference.revision.rawValue,
                            in: mainDatabase
                        )
                        try await saveWorkspaceSelection(
                            branch: expectedReference.branch.rawValue,
                            revision: expectedReference.revision.rawValue,
                            workspaceID: workspaceID,
                            database: mainDatabase
                        )
                    } catch {
                        rollbackFailures.append(
                            "Application database: \(String(describing: error))"
                        )
                    }
                    guard rollbackFailures.isEmpty else {
                        throw SourceWorkspaceDatabaseError.reconciliationRollbackFailed(
                            reconciliation: String(describing: reconciliationError),
                            rollback: rollbackFailures.joined(separator: "\n")
                        )
                    }
                    throw reconciliationError
                }
            }
        )
    }
}

private func prepareOpenMusicEventSourceWorkspace(
    _ workspace: SourceWorkspace,
    resolveRevision: @escaping SourceWorkspaceRevisionResolver
) async throws -> WorkspacePreparation<SourceWorkspaceResource> {
    @Dependency(\.defaultDatabase) var mainDatabase
    @Dependency(\.eventWorkspaceResetter) var workspaceResetter
    @Dependency(\.sourceControl) var sourceControl
    @Dependency(\.sourceWorkspaceStorage) var storage
    @Dependency(SourceWorkspaceCheckoutClient.self) var checkout

    let location = try storage.location(workspace.id)
    try FileManager.default.createDirectory(
        at: location.directoryURL,
        withIntermediateDirectories: true
    )

    let referenceDatabase = try openReferenceDatabase(path: location.referenceDatabaseURL.path)
    let referenceRevision = try referenceDatabase.read { db in
        try SourceWorkspaceReferenceRecord.find(workspace.id).fetchOne(db)?.revision
    }
    let persisted = try await mainDatabase.read { db in
        (
            installation: try SourceWorkspaceInstallationRecord.find(workspace.id).fetchOne(db),
            selection: try SourceWorkspaceSelectionRecord.find(workspace.id).fetchOne(db),
            openProposal: try SourceWorkspaceOpenProposalRequest(workspaceID: workspace.id)
                .fetch(db)
        )
    }
    let installedRevision = persisted.installation?.revision
    let repositoryPathExisted = FileManager.default.fileExists(
        atPath: location.repositoryURL.path
    )
    let repositoryExists = isGitRepository(location.repositoryURL)
    guard repositoryExists || (referenceRevision == nil && installedRevision == nil) else {
        throw SourceWorkspaceDatabaseError.repositoryMissing(workspace.id)
    }
    var freshRepositoryHasDurableReference = repositoryExists
    defer {
        if !repositoryPathExisted && !freshRepositoryHasDurableReference {
            try? FileManager.default.removeItem(at: location.repositoryURL)
        }
    }

    let repository: Repository
    let selectedReference: WorkspaceBranchReference
    if repositoryExists {
        repository = try await sourceControl.open(location.repositoryURL)
        guard let persistedRevision = referenceRevision ?? installedRevision else {
            throw SourceWorkspaceDatabaseError.upstreamReferenceMissing(workspace.id)
        }
        if let selection = persisted.selection {
            selectedReference = WorkspaceBranchReference(
                branch: WorkspaceBranch(rawValue: selection.branch),
                revision: WorkspaceRevision(rawValue: persistedRevision)
            )
        } else if let proposal = persisted.openProposal,
                  proposal.target.revision.rawValue == persistedRevision {
            selectedReference = proposal.target
        } else {
            selectedReference = WorkspaceBranchReference(
                branch: WorkspaceBranch(rawValue: workspace.defaultBranch),
                revision: WorkspaceRevision(rawValue: persistedRevision)
            )
        }
    } else {
        let checkedOut = try await checkout.checkout(workspace, location.repositoryURL)
        repository = checkedOut.repository
        selectedReference = checkedOut.reference
    }

    // The local commit identifies the imported archive only inside the patch engine. Tangled's
    // default-branch head remains the durable upstream identity used by Workspace and proposals.
    _ = try await resolveRevision(repository, RefName(rawValue: "HEAD"))
    let selectedBranch = selectedReference.branch.rawValue
    let selectedRevision = selectedReference.revision.rawValue

    switch (referenceRevision, installedRevision) {
    case (nil, nil):
        let insertion = try sourceInsertion(
            workspace: workspace,
            repositoryURL: location.repositoryURL
        )
        try await insertion.replaceSourceWorkspace(
            workspace,
            branch: selectedBranch,
            revision: selectedRevision,
            in: referenceDatabase.database
        )
        try await saveReferenceRevision(
            selectedRevision,
            workspaceID: workspace.id,
            database: referenceDatabase.database
        )
        freshRepositoryHasDurableReference = true
        try await insertion.replaceSourceWorkspace(
            workspace,
            branch: selectedBranch,
            revision: selectedRevision,
            in: mainDatabase
        )

    case let (.some(referenceRevision), nil)
        where referenceRevision == selectedRevision:
        if persisted.selection != nil {
            // Authoring exit restores published content and removes only the active installation.
            // Reentry restores the accepted proposal-round baseline without changing the upstream
            // archive repository that anchors complete replacement patches.
            try workspaceResetter.resetWorkspace(workspace, referenceDatabase)
            try await saveWorkspaceSelection(
                branch: selectedBranch,
                revision: selectedRevision,
                workspaceID: workspace.id,
                database: mainDatabase
            )
        } else {
            // Resume a first preparation interrupted after the immutable reference was installed.
            let insertion = try sourceInsertion(
                workspace: workspace,
                repositoryURL: location.repositoryURL
            )
            try await insertion.replaceSourceWorkspace(
                workspace,
                branch: selectedBranch,
                revision: selectedRevision,
                in: mainDatabase
            )
        }

    case let (.some(referenceRevision), .some(installedRevision))
        where referenceRevision == selectedRevision
            && installedRevision == selectedRevision:
        // A settled workspace is reopened exactly as persisted. Reentry never installs source.
        break

    case (nil, .some):
        throw SourceWorkspaceDatabaseError.referenceMissing(workspace.id)

    case let (referenceRevision, installedRevision):
        throw SourceWorkspaceDatabaseError.persistedRevisionMismatch(
            workspaceID: workspace.id,
            repositoryRevision: selectedRevision,
            referenceRevision: referenceRevision,
            installationRevision: installedRevision
        )
    }

    if let selection = persisted.selection,
       selection.revision != selectedRevision {
        throw SourceWorkspaceDatabaseError.selectionRevisionMismatch(
            workspaceID: workspace.id,
            branch: selection.branch,
            expectedRevision: selectedRevision,
            persistedRevision: selection.revision
        )
    } else if persisted.selection == nil {
        try await saveWorkspaceSelection(
            branch: selectedBranch,
            revision: selectedRevision,
            workspaceID: workspace.id,
            database: mainDatabase
        )
    }

    let reference = selectedReference
    let context: WorkspaceEditingContext
    if persisted.openProposal?.target == reference,
       let proposal = persisted.openProposal {
        context = .proposal(proposal)
    } else if selectedBranch == workspace.defaultBranch {
        context = .published(reference)
    } else {
        context = .branch(reference)
    }
    return WorkspacePreparation(
        context: context,
        source: SourceWorkspaceResource(
            workspace: workspace,
            repositoryURL: location.repositoryURL,
            mainDatabase: mainDatabase,
            referenceDatabase: referenceDatabase
        )
    )
}

private func sourceInsertion(
    workspace: SourceWorkspace,
    repositoryURL: URL
) throws -> OME.SourceDatabaseInsertion {
    let source = try OpenMusicEventSourceRepositoryFileTree()
        .read(from: repositoryURL)
        .output
        .requiredValue
    return try OME.SourceDatabaseInsertion(
        .init(
            source: source,
            organizerID: workspace.organizerID,
            sourceProvenance: workspace.sourceProvenance,
            sourceRootURL: repositoryURL
        )
    )
}

private func openReferenceDatabase(path: String) throws -> SourceBaselineDatabase {
    @Dependency(\.sourceWorkspaceReferenceMigrator) var migrator
    let database = try defaultBaselineDatabase(path: path)
    try migrator.migrate(database)
    return database
}

private func saveReferenceRevision(
    _ revision: String,
    workspaceID: SourceWorkspace.ID,
    database: any DatabaseWriter
) async throws {
    try await database.write { db in
        try SourceWorkspaceReferenceRecord.upsert {
            SourceWorkspaceReferenceRecord(id: workspaceID, revision: revision)
        }
        .execute(db)
    }
}

private func saveWorkspaceSelection(
    branch: String,
    revision: String,
    workspaceID: SourceWorkspace.ID,
    database: any DatabaseWriter
) async throws {
    try await database.write { db in
        try SourceWorkspaceInstallationRecord.upsert {
            SourceWorkspaceInstallationRecord(id: workspaceID, revision: revision)
        }
        .execute(db)
        try SourceWorkspaceSelectionRecord.upsert {
            SourceWorkspaceSelectionRecord(
                id: workspaceID,
                branch: branch,
                revision: revision
            )
        }
        .execute(db)
    }
}

private func isGitRepository(_ repositoryURL: URL) -> Bool {
    FileManager.default.fileExists(
        atPath: repositoryURL.appending(path: ".git").path(percentEncoded: false)
    )
}

private func replaceRepository(at repositoryURL: URL, with replacementURL: URL) throws -> URL {
    let fileManager = FileManager.default
    let backupURL = repositoryURL
        .deletingLastPathComponent()
        .appending(path: "repository-backup-\(UUID().uuidString)")
    try fileManager.moveItem(at: repositoryURL, to: backupURL)
    do {
        try fileManager.moveItem(at: replacementURL, to: repositoryURL)
    } catch {
        let replacementError = error
        do {
            try fileManager.moveItem(at: backupURL, to: repositoryURL)
        } catch {
            throw SourceWorkspaceRepositoryReplacementError.restoreFailed(
                replacement: String(describing: replacementError),
                restoration: String(describing: error),
                backupPath: backupURL.path
            )
        }
        throw replacementError
    }
    return backupURL
}

enum SourceWorkspaceDatabaseError: Error, Equatable {
    case applicationDatabaseMismatch(SourceWorkspace.ID)
    case branchSelectionRequiresExactReference(String)
    case defaultBranchChanged(expected: String, observed: String)
    case localChangesPreventBranchSwitch(String, String)
    case persistedReconciliationReferenceMismatch(
        expected: WorkspaceBranchReference,
        observed: WorkspaceBranchReference?,
        referenceRevision: String?,
        installationRevision: String?
    )
    case persistedRevisionMismatch(
        workspaceID: SourceWorkspace.ID,
        repositoryRevision: String,
        referenceRevision: String?,
        installationRevision: String?
    )
    case persistedProposalTargetMismatch(
        expected: WorkspaceBranchReference,
        observed: WorkspaceBranchReference?
    )
    case proposalContextMismatch(WorkspaceProposalID?)
    case proposalRevisionRequiresRefresh(expected: String, observed: String)
    case proposalTargetMismatch(WorkspaceProposalID)
    case referenceMissing(SourceWorkspace.ID)
    case reconciliationRollbackFailed(reconciliation: String, rollback: String)
    case repositoryMissing(SourceWorkspace.ID)
    case resourceMismatch(SourceWorkspace.ID)
    case selectionRevisionMismatch(
        workspaceID: SourceWorkspace.ID,
        branch: String,
        expectedRevision: String,
        persistedRevision: String
    )
    case unexpectedRevision(expected: String, observed: String)
    case upstreamReferenceMissing(SourceWorkspace.ID)
}

private enum SourceWorkspaceRepositoryReplacementError: Error, Equatable {
    case restoreFailed(replacement: String, restoration: String, backupPath: String)
}

private enum SourceWorkspaceArchiveError: Error, Equatable {
    case cannotEnumerate(String)
    case containsGitMetadata
    case unsupportedEntry(String)
}

private func archiveRepositoryPaths(at repositoryURL: URL) throws -> [RepositoryPath] {
    let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
    ]
    guard let enumerator = FileManager.default.enumerator(
        at: repositoryURL,
        includingPropertiesForKeys: Array(resourceKeys)
    ) else {
        throw SourceWorkspaceArchiveError.cannotEnumerate(repositoryURL.path)
    }
    let rootPath = repositoryURL.standardizedFileURL.path
    let pathPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    var paths: [RepositoryPath] = []
    for case let fileURL as URL in enumerator {
        let candidatePath = fileURL.standardizedFileURL.path
        guard candidatePath.hasPrefix(pathPrefix) else {
            throw SourceWorkspaceArchiveError.unsupportedEntry(candidatePath)
        }
        let relativePath = String(candidatePath.dropFirst(pathPrefix.count))
        if relativePath == ".git" || relativePath.hasPrefix(".git/") {
            throw SourceWorkspaceArchiveError.containsGitMetadata
        }
        let values = try fileURL.resourceValues(forKeys: resourceKeys)
        if values.isSymbolicLink == true {
            throw SourceWorkspaceArchiveError.unsupportedEntry(relativePath)
        }
        if values.isDirectory == true {
            continue
        }
        guard values.isRegularFile == true else {
            throw SourceWorkspaceArchiveError.unsupportedEntry(relativePath)
        }
        paths.append(RepositoryPath(rawValue: relativePath))
    }
    return paths.sorted { $0.rawValue < $1.rawValue }
}

private extension WorkspaceEditingContextDestination {
    var editingBranch: WorkspaceBranch {
        switch self {
        case let .branch(branch), let .published(branch):
            branch
        case let .proposal(_, targetBranch):
            targetBranch
        }
    }
}

private extension WorkspaceSubmission where ChangeSet == SourcePatch {
    var proposalTarget: WorkspaceBranchReference {
        switch target {
        case let .createProposal(target, _):
            target
        case let .updateProposal(proposal):
            proposal.target
        }
    }
}

private enum SourceWorkspacePreparationCoordinator {
    static let shared = Coordinator()

    actor Coordinator {
        private var operations: [SourceWorkspace.ID: Task<WorkspacePreparation<SourceWorkspaceResource>, Error>] = [:]

        func prepare(
            _ workspace: SourceWorkspace,
            operation: @escaping @Sendable () async throws -> WorkspacePreparation<SourceWorkspaceResource>
        ) async throws -> WorkspacePreparation<SourceWorkspaceResource> {
            if let operation = operations[workspace.id] {
                return try await operation.value
            }
            let task = Task { try await operation() }
            operations[workspace.id] = task
            defer { operations[workspace.id] = nil }
            return try await task.value
        }
    }
}
