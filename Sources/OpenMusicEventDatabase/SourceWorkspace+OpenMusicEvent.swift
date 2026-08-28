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
        TangledSourceCheckoutRequest
    ) async throws -> TangledSourceCheckout
}

extension SourceWorkspaceCheckoutClient: DependencyKey {
    static var liveValue: Self {
        Self(checkout: TangledSourceCheckoutClient.git.checkout)
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
                let revision = try await resolveRevision(
                    Repository(url: source.repositoryURL),
                    RefName(rawValue: "HEAD")
                )
                guard revision.rawValue == proposal.revision.rawValue else {
                    throw SourceWorkspaceDatabaseError.unexpectedRevision(
                        expected: proposal.revision.rawValue,
                        observed: revision.rawValue
                    )
                }
                let branch = try publicationSourceBranch(
                    submission,
                    workspaceID: workspaceID,
                    database: mainDatabase
                )

                let insertion = try sourceInsertion(
                    workspace: source.workspace,
                    repositoryURL: source.repositoryURL
                )
                let referenceDatabase = source.referenceDatabase
                try await insertion.replaceSourceWorkspace(
                    source.workspace,
                    branch: branch.rawValue,
                    revision: revision.rawValue,
                    in: referenceDatabase.database
                )
                try await saveReferenceRevision(
                    revision.rawValue,
                    workspaceID: workspaceID,
                    database: referenceDatabase.database
                )
                try await saveWorkspaceSelection(
                    branch: branch.rawValue,
                    revision: revision.rawValue,
                    workspaceID: workspaceID,
                    database: mainDatabase
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
                @Dependency(\.sourceControl) var sourceControl
                @Dependency(\.sourcePatchApplier) var patchApplier
                @Dependency(\.sourceWorkingTreeMaterializer) var materializer

                let proposalStore = SourceWorkspaceOpenProposalStore(database: mainDatabase)
                let expectedReference = try workspaceReference(
                    reconciliation.expected,
                    workspaceID: workspaceID,
                    database: mainDatabase
                )
                let destinationBranch = try reconciliationBranch(
                    reconciliation,
                    workspaceID: workspaceID,
                    database: mainDatabase
                )
                if case let .proposal(expectedProposal) = reconciliation.expected,
                   case let .published(branch) = reconciliation.destination,
                   branch == expectedProposal.target.branch,
                   try proposalStore.load(workspaceID)?.id == expectedProposal.id {
                    // The remote review is already merged. Closing that relationship is durable
                    // even if selecting or refreshing its target branch subsequently fails.
                    try await proposalStore.save(nil, workspaceID: workspaceID)
                }
                let currentChanges = try await patchGenerator.generate(
                    SourceWorkspacePatchRequest(workspace: source.workspace)
                )
                let switchesBranch = destinationBranch != expectedReference.branch
                guard !switchesBranch || currentChanges.isEmpty else {
                    throw SourceWorkspaceDatabaseError.localChangesPreventBranchSwitch(
                        expectedReference.branch.rawValue,
                        destinationBranch.rawValue
                    )
                }
                let repository = Repository(url: source.repositoryURL)
                let startingRevision = try await resolveRevision(
                    repository,
                    RefName(rawValue: "HEAD")
                )
                guard startingRevision.rawValue == expectedReference.revision.rawValue else {
                    throw SourceWorkspaceDatabaseError.unexpectedRevision(
                        expected: expectedReference.revision.rawValue,
                        observed: startingRevision.rawValue
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
                let previousReferenceInsertion = try sourceInsertion(
                    workspace: source.workspace,
                    repositoryURL: previousReferenceTree.workingRepositoryURL
                )
                let previousWorkingInsertion: OME.SourceDatabaseInsertion
                var previousWorkingTree: SourceWorkingTree?
                if currentChanges.isEmpty {
                    previousWorkingInsertion = previousReferenceInsertion
                } else {
                    let workingTree = try materializer.materialize(
                        source.repositoryURL,
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
                let referenceDatabase = source.referenceDatabase
                do {
                    _ = try await TangledSourceCheckoutClient.git.checkout(
                        TangledSourceCheckoutRequest(
                            repository: try TangledRepositoryReference(
                                sourceReference: source.workspace.repository
                            ),
                            ref: destinationBranch.rawValue,
                            outputURL: source.repositoryURL
                        )
                    )
                    let revision = try await resolveRevision(
                        repository,
                        RefName(rawValue: "HEAD")
                    )
                    if let observedRevision = reconciliation.observedRevision,
                       observedRevision.rawValue != revision.rawValue {
                        throw SourceWorkspaceDatabaseError.unexpectedRevision(
                            expected: observedRevision.rawValue,
                            observed: revision.rawValue
                        )
                    }

                    let referenceInsertion = try sourceInsertion(
                        workspace: source.workspace,
                        repositoryURL: source.repositoryURL
                    )
                    let workingInsertion: OME.SourceDatabaseInsertion
                    var workingTree: SourceWorkingTree?
                    if currentChanges.isEmpty {
                        workingInsertion = referenceInsertion
                    } else {
                        let materialized = try materializer.materialize(
                            source.repositoryURL,
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
                        revision: revision.rawValue,
                        in: referenceDatabase.database
                    )
                    try await saveReferenceRevision(
                        revision.rawValue,
                        workspaceID: workspaceID,
                        database: referenceDatabase.database
                    )
                    try await workingInsertion.replaceSourceWorkspace(
                        source.workspace,
                        branch: destinationBranch.rawValue,
                        revision: revision.rawValue,
                        in: mainDatabase
                    )
                    try await saveWorkspaceSelection(
                        branch: destinationBranch.rawValue,
                        revision: revision.rawValue,
                        workspaceID: workspaceID,
                        database: mainDatabase
                    )
                    return try await reconciledEditingContext(
                        reconciliation,
                        revision: WorkspaceRevision(rawValue: revision.rawValue),
                        proposalStore: proposalStore,
                        workspaceID: workspaceID
                    )
                } catch {
                    let reconciliationError = error
                    var rollbackFailures: [String] = []
                    do {
                        try await sourceControl.checkout(
                            CheckoutRequest(
                                repository: repository,
                                ref: RefName(
                                    rawValue: expectedReference.revision.rawValue
                                )
                            )
                        )
                    } catch {
                        rollbackFailures.append("Git: \(String(describing: error))")
                    }
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
    let requestedBranch = persisted.selection?.branch
        ?? workspace.defaultBranch

    let repositoryExists = isGitRepository(location.repositoryURL)
    guard repositoryExists || (referenceRevision == nil && installedRevision == nil) else {
        throw SourceWorkspaceDatabaseError.repositoryMissing(workspace.id)
    }

    let repository: Repository
    if repositoryExists {
        repository = try await sourceControl.open(location.repositoryURL)
    } else {
        _ = try await checkout.checkout(
            TangledSourceCheckoutRequest(
                repository: try TangledRepositoryReference(
                    sourceReference: workspace.repository
                ),
                ref: requestedBranch,
                outputURL: location.repositoryURL
            )
        )
        repository = try await sourceControl.open(location.repositoryURL)
    }

    let revision = try await resolveRevision(repository, RefName(rawValue: "HEAD"))
    let selectedBranch = persisted.selection?.branch ?? workspace.defaultBranch
    var selectedRevision = revision.rawValue

    switch (referenceRevision, installedRevision) {
    case (nil, nil):
        let insertion = try sourceInsertion(
            workspace: workspace,
            repositoryURL: location.repositoryURL
        )
        try await insertion.replaceSourceWorkspace(
            workspace,
            branch: selectedBranch,
            revision: revision.rawValue,
            in: referenceDatabase.database
        )
        try await saveReferenceRevision(
            revision.rawValue,
            workspaceID: workspace.id,
            database: referenceDatabase.database
        )
        try await insertion.replaceSourceWorkspace(
            workspace,
            branch: selectedBranch,
            revision: revision.rawValue,
            in: mainDatabase
        )

    case let (.some(referenceRevision), nil)
        where referenceRevision == revision.rawValue:
        // Resume a first preparation interrupted after the immutable reference was installed.
        let insertion = try sourceInsertion(
            workspace: workspace,
            repositoryURL: location.repositoryURL
        )
        try await insertion.replaceSourceWorkspace(
            workspace,
            branch: selectedBranch,
            revision: revision.rawValue,
            in: mainDatabase
        )

    case let (.some(referenceRevision), .some(installedRevision))
        where referenceRevision == revision.rawValue
            && installedRevision == revision.rawValue:
        // A settled workspace is reopened exactly as persisted. Reentry never installs source.
        break

    case (nil, .some):
        throw SourceWorkspaceDatabaseError.referenceMissing(workspace.id)

    case let (.some(referenceRevision), .some(installedRevision))
        where referenceRevision == installedRevision:
        guard let checkpoint = try SourceWorkspacePublicationCheckpointStore(database: mainDatabase)
            .load(workspace.id),
              checkpoint.commit.parentRevision.rawValue == referenceRevision,
              publicationBaseRevision(checkpoint.submission).rawValue == referenceRevision,
              checkpoint.commit.source.revision.rawValue == revision.rawValue
        else {
            throw SourceWorkspaceDatabaseError.persistedRevisionMismatch(
                workspaceID: workspace.id,
                repositoryRevision: revision.rawValue,
                referenceRevision: referenceRevision,
                installationRevision: installedRevision
            )
        }

        // Publication persisted its local proposal commit before its external push failed. Keep
        // that commit checked out and preserve its branch/files for diagnosis or continuation,
        // while exposing the settled parent as the selected branch beneath the durable submission.
        selectedRevision = referenceRevision

    case let (referenceRevision, installedRevision):
        throw SourceWorkspaceDatabaseError.persistedRevisionMismatch(
            workspaceID: workspace.id,
            repositoryRevision: revision.rawValue,
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

    let reference = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: selectedBranch),
            revision: WorkspaceRevision(rawValue: selectedRevision)
        )
    let context: WorkspaceEditingContext
    if let proposal = persisted.openProposal {
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

private func publicationSourceBranch(
    _ submission: WorkspaceSubmission<SourcePatch>,
    workspaceID: SourceWorkspace.ID,
    database: any DatabaseWriter
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
            throw SourceWorkspaceDatabaseError.selectionMissing(workspaceID)
        }
        return WorkspaceBranch(rawValue: selection.branch)
    }
}

private func publicationBaseRevision(
    _ submission: WorkspaceSubmission<SourcePatch>
) -> WorkspaceRevision {
    switch submission.target {
    case let .createProposal(target, _):
        target.revision
    case let .updateProposal(proposal):
        proposal.revision
    }
}

private func workspaceReference(
    _ context: WorkspaceEditingContext,
    workspaceID: SourceWorkspace.ID,
    database: any DatabaseWriter
) throws -> WorkspaceBranchReference {
    switch context {
    case let .branch(reference), let .published(reference):
        return reference
    case let .proposal(proposal):
        guard let selection = try database.read({ db in
            try SourceWorkspaceSelectionRecord.find(workspaceID).fetchOne(db)
        }) else {
            throw SourceWorkspaceDatabaseError.selectionMissing(workspaceID)
        }
        return WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: selection.branch),
            revision: proposal.revision
        )
    }
}

private func reconciliationBranch(
    _ reconciliation: WorkspaceReconciliation,
    workspaceID: SourceWorkspace.ID,
    database: any DatabaseWriter
) throws -> WorkspaceBranch {
    switch reconciliation.destination {
    case let .branch(branch), let .published(branch):
        return branch
    case .proposal:
        return try workspaceReference(
            reconciliation.expected,
            workspaceID: workspaceID,
            database: database
        ).branch
    }
}

private func reconciledEditingContext(
    _ reconciliation: WorkspaceReconciliation,
    revision: WorkspaceRevision,
    proposalStore: SourceWorkspaceOpenProposalStore,
    workspaceID: SourceWorkspace.ID
) async throws -> WorkspaceEditingContext {
    switch reconciliation.destination {
    case let .branch(branch):
        return .branch(WorkspaceBranchReference(branch: branch, revision: revision))
    case let .published(branch):
        return .published(WorkspaceBranchReference(branch: branch, revision: revision))
    case let .proposal(id, targetBranch):
        guard case let .proposal(existing) = reconciliation.expected,
              existing.id == id,
              existing.target.branch == targetBranch
        else {
            throw SourceWorkspaceDatabaseError.proposalDestinationMismatch(workspaceID)
        }
        let proposal = WorkspaceProposal(
            id: id,
            revision: revision,
            target: existing.target
        )
        try await proposalStore.save(proposal, workspaceID: workspaceID)
        return .proposal(proposal)
    }
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

enum SourceWorkspaceDatabaseError: Error, Equatable {
    case applicationDatabaseMismatch(SourceWorkspace.ID)
    case localChangesPreventBranchSwitch(String, String)
    case persistedRevisionMismatch(
        workspaceID: SourceWorkspace.ID,
        repositoryRevision: String,
        referenceRevision: String?,
        installationRevision: String?
    )
    case referenceMissing(SourceWorkspace.ID)
    case proposalDestinationMismatch(SourceWorkspace.ID)
    case reconciliationRollbackFailed(reconciliation: String, rollback: String)
    case repositoryMissing(SourceWorkspace.ID)
    case resourceMismatch(SourceWorkspace.ID)
    case selectionMissing(SourceWorkspace.ID)
    case selectionRevisionMismatch(
        workspaceID: SourceWorkspace.ID,
        branch: String,
        expectedRevision: String,
        persistedRevision: String
    )
    case unexpectedRevision(expected: String, observed: String)
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
