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
        Self(
            advance: { source, workspaceID, _, proposal in
                guard source.workspace.id == workspaceID else {
                    throw SourceWorkspaceDatabaseError.resourceMismatch(workspaceID)
                }
                let mainDatabase = source.database
                let revision = try await resolveRevision(
                    Repository(url: source.repositoryURL),
                    RefName(rawValue: "HEAD")
                )
                guard revision.rawValue == proposal.source.revision.rawValue else {
                    throw SourceWorkspaceDatabaseError.unexpectedRevision(
                        expected: proposal.source.revision.rawValue,
                        observed: revision.rawValue
                    )
                }

                let insertion = try sourceInsertion(
                    workspace: source.workspace,
                    repositoryURL: source.repositoryURL
                )
                let referenceDatabase = try openReferenceDatabase(
                    path: source.sourceEditingSession.baselineDatabasePath
                )
                try await insertion.replaceSourceWorkspace(
                    source.workspace,
                    revision: revision.rawValue,
                    in: referenceDatabase.database
                )
                try await saveReferenceRevision(
                    revision.rawValue,
                    workspaceID: workspaceID,
                    database: referenceDatabase.database
                )
                try await saveInstallationRevision(
                    revision.rawValue,
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
                let mainDatabase = source.database
                @Dependency(SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self)
                var patchGenerator
                @Dependency(\.sourcePatchApplier) var patchApplier
                @Dependency(\.sourceWorkingTreeMaterializer) var materializer

                let currentChanges = try await withDependencies {
                    $0.defaultDatabase = source.database
                } operation: {
                    try await patchGenerator.generate(
                        SourceWorkspacePatchRequest(workspace: source.workspace)
                    )
                }

                _ = try await TangledSourceCheckoutClient.git.checkout(
                    TangledSourceCheckoutRequest(
                        repository: try TangledRepositoryReference(
                            sourceReference: source.workspace.repository
                        ),
                        ref: reconciliation.target.editingReference.branch.rawValue,
                        outputURL: source.repositoryURL
                    )
                )
                let repository = Repository(url: source.repositoryURL)
                let revision = try await resolveRevision(repository, RefName(rawValue: "HEAD"))
                if let observedRevision = reconciliation.observedRevision,
                   observedRevision.rawValue != revision.rawValue {
                    throw SourceWorkspaceDatabaseError.unexpectedRevision(
                        expected: observedRevision.rawValue,
                        observed: revision.rawValue
                    )
                }

                let workingTree = try materializer.materialize(source.repositoryURL, nil)
                defer { try? FileManager.default.removeItem(at: workingTree.workingRepositoryURL) }
                try patchApplier.apply(currentChanges, workingTree.workingRepositoryURL)

                let referenceInsertion = try sourceInsertion(
                    workspace: source.workspace,
                    repositoryURL: source.repositoryURL
                )
                let workingInsertion = try sourceInsertion(
                    workspace: source.workspace,
                    repositoryURL: workingTree.workingRepositoryURL
                )
                let referenceDatabase = try openReferenceDatabase(
                    path: source.sourceEditingSession.baselineDatabasePath
                )
                try await referenceInsertion.replaceSourceWorkspace(
                    source.workspace,
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
                    revision: revision.rawValue,
                    in: mainDatabase
                )

                let line = reconciliation.target.replacingRevision(
                    WorkspaceRevision(rawValue: revision.rawValue)
                )
                try await SourceWorkspaceOpenProposalStore(database: mainDatabase)
                    .save(line.proposal, workspaceID: workspaceID)
                return line
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

    let location = try storage.location(workspace.id)
    try FileManager.default.createDirectory(
        at: location.directoryURL,
        withIntermediateDirectories: true
    )

    let referenceDatabase = try openReferenceDatabase(path: location.referenceDatabaseURL.path)
    let referenceRevision = try referenceDatabase.read { db in
        try SourceWorkspaceReferenceRecord.find(workspace.id).fetchOne(db)?.revision
    }
    let installedRevision = try await mainDatabase.read { db in
        try SourceWorkspaceInstallationRecord.find(workspace.id).fetchOne(db)?.revision
    }

    let repositoryExists = isGitRepository(location.repositoryURL)
    guard repositoryExists || (referenceRevision == nil && installedRevision == nil) else {
        throw SourceWorkspaceDatabaseError.repositoryMissing(workspace.id)
    }

    let repository: Repository
    if repositoryExists {
        repository = try await sourceControl.open(location.repositoryURL)
    } else {
        _ = try await TangledSourceCheckoutClient.git.checkout(
            TangledSourceCheckoutRequest(
                repository: try TangledRepositoryReference(
                    sourceReference: workspace.repository
                ),
                ref: workspace.branch,
                outputURL: location.repositoryURL
            )
        )
        repository = try await sourceControl.open(location.repositoryURL)
    }

    let revision = try await resolveRevision(repository, RefName(rawValue: "HEAD"))

    switch (referenceRevision, installedRevision) {
    case (nil, nil):
        let insertion = try sourceInsertion(
            workspace: workspace,
            repositoryURL: location.repositoryURL
        )
        try await insertion.replaceSourceWorkspace(
            workspace,
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

    case let (referenceRevision, installedRevision):
        throw SourceWorkspaceDatabaseError.persistedRevisionMismatch(
            workspaceID: workspace.id,
            repositoryRevision: revision.rawValue,
            referenceRevision: referenceRevision,
            installationRevision: installedRevision
        )
    }

    return WorkspacePreparation(
        line: .canonical(
            WorkspaceBranchReference(
                branch: WorkspaceBranch(rawValue: workspace.branch),
                revision: WorkspaceRevision(rawValue: revision.rawValue)
            )
        ),
        source: try SourceWorkspaceResource(
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
        try SourceWorkspaceReferenceRecord.insert {
            SourceWorkspaceReferenceRecord(id: workspaceID, revision: revision)
        } onConflict: {
            $0.id
        }
        .execute(db)
    }
}

private func saveInstallationRevision(
    _ revision: String,
    workspaceID: SourceWorkspace.ID,
    database: any DatabaseWriter
) async throws {
    try await database.write { db in
        try SourceWorkspaceInstallationRecord.insert {
            SourceWorkspaceInstallationRecord(id: workspaceID, revision: revision)
        } onConflict: {
            $0.id
        }
        .execute(db)
    }
}

private func isGitRepository(_ repositoryURL: URL) -> Bool {
    FileManager.default.fileExists(
        atPath: repositoryURL.appending(path: ".git").path(percentEncoded: false)
    )
}

private extension WorkspaceEditingLine {
    func replacingRevision(_ revision: WorkspaceRevision) -> Self {
        switch self {
        case let .canonical(reference):
            return .canonical(
                WorkspaceBranchReference(branch: reference.branch, revision: revision)
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

    var proposal: WorkspaceProposal? {
        guard case let .proposal(proposal) = self else { return nil }
        return proposal
    }
}

private enum SourceWorkspaceDatabaseError: Error, Equatable {
    case persistedRevisionMismatch(
        workspaceID: SourceWorkspace.ID,
        repositoryRevision: String,
        referenceRevision: String?,
        installationRevision: String?
    )
    case referenceMissing(SourceWorkspace.ID)
    case repositoryMissing(SourceWorkspace.ID)
    case resourceMismatch(SourceWorkspace.ID)
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
