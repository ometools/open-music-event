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
        _ branch: WorkspaceBranch?,
        _ outputURL: URL
    ) async throws -> SourceWorkspaceCheckout
}

struct SourceWorkspaceCheckout: Equatable, Sendable {
    var repository: Repository
    var reference: WorkspaceBranchReference
}

extension SourceWorkspaceCheckoutClient: DependencyKey {
    static var liveValue: Self {
        Self { workspace, branch, outputURL in
            @Dependency(\.sourceControl) var sourceControl
            @Dependency(\.tangledBranchReference) var branchReference
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
            let reference = if let branch {
                try await branchReference.resolve(sourceReference, branch)
            } else {
                try await defaultBranch.resolve(sourceReference)
            }
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
        Self(
            preparePublishedUpdate: { source, workspaceID, attempt in
                try await prepareWorkspacePublishedUpdate(
                    source: source,
                    workspaceID: workspaceID,
                    attempt: attempt
                )
            },
            resetToPublished: { source, workspaceID in
                try await installBranchBaseline(
                    source: source,
                    workspaceID: workspaceID,
                    branch: WorkspaceBranch(rawValue: source.workspace.defaultBranch),
                    resolveRevision: resolveRevision,
                    requireClean: false
                )
            },
            reconcile: { source, workspaceID, attempt in
                try await reconcileWorkspace(
                    source: source,
                    workspaceID: workspaceID,
                    attempt: attempt,
                    resolveRevision: resolveRevision
                )
            },
            refresh: { source, workspaceID, current in
                try await installBranchBaseline(
                    source: source,
                    workspaceID: workspaceID,
                    branch: current.branch,
                    resolveRevision: resolveRevision,
                    requireClean: true
                )
            },
            select: { source, workspaceID, branch in
                try await installBranchBaseline(
                    source: source,
                    workspaceID: workspaceID,
                    branch: branch,
                    resolveRevision: resolveRevision,
                    requireClean: true
                )
            }
        )
    }
}

private func prepareOpenMusicEventSourceWorkspace(
    _ workspace: SourceWorkspace,
    resolveRevision: @escaping SourceWorkspaceRevisionResolver
) async throws -> WorkspaceSession<SourceWorkspaceResource> {
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
    let installation = try await mainDatabase.read { db in
        try SourceWorkspaceInstallationRecord.find(workspace.id).fetchOne(db)
    }
    let baselineStore = SourceWorkspaceBaselineStore(database: mainDatabase)
    var baseline = try baselineStore.load(workspace.id)

    let repositoryExists = isGitRepository(location.repositoryURL)
    guard repositoryExists || (referenceRevision == nil && installation == nil) else {
        throw SourceWorkspaceDatabaseError.repositoryMissing(workspace.id)
    }
    let freshReference: WorkspaceBranchReference?
    if repositoryExists {
        _ = try await sourceControl.open(location.repositoryURL)
        freshReference = nil
    } else {
        let checkedOut = try await checkout.checkout(
            workspace,
            nil,
            location.repositoryURL
        )
        freshReference = checkedOut.reference
    }
    let repositoryRevision = freshReference?.revision.rawValue
        ?? baseline?.revision.rawValue
        ?? referenceRevision
        ?? installation?.revision
        ?? "missing"
    let resource = SourceWorkspaceResource(
        workspace: workspace,
        repositoryURL: location.repositoryURL,
        mainDatabase: mainDatabase,
        referenceDatabase: referenceDatabase
    )
    switch (referenceRevision, installation?.revision, baseline) {
    case (nil, nil, nil):
        guard let freshReference else {
            throw SourceWorkspaceDatabaseError.upstreamReferenceMissing(workspace.id)
        }
        let insertion = try sourceInsertion(
            workspace: workspace,
            repositoryURL: location.repositoryURL
        )
        let replacement = try await insertion.prepareWorkspaceReplacement(workspace)
        try await replacement.replace(
            branch: freshReference.branch.rawValue,
            revision: freshReference.revision.rawValue,
            recordsReferenceRevision: true,
            in: referenceDatabase.database
        )
        try await replacement.replace(
            branch: freshReference.branch.rawValue,
            revision: freshReference.revision.rawValue,
            in: mainDatabase
        )
        try await baselineStore.save(freshReference, workspaceID: workspace.id)
        baseline = freshReference

    case let (.some(reference), .some(installed), .some(persisted)):
        if reference != installed || persisted.revision.rawValue != reference {
            throw SourceWorkspaceDatabaseError.persistedRevisionMismatch(
                workspaceID: workspace.id,
                repositoryRevision: repositoryRevision,
                referenceRevision: referenceRevision,
                installationRevision: installation?.revision
            )
        }
    case let (.some(reference), nil, .some(persisted)):
        // Attendee mode deliberately removes the writable authoring installation while keeping
        // the exact branch baseline and its reference snapshot. Reentering authoring mounts that
        // snapshot and its installation marker in one transaction before exposing a ready session.
        guard persisted.revision.rawValue == reference else {
            throw SourceWorkspaceDatabaseError.persistedRevisionMismatch(
                workspaceID: workspace.id,
                repositoryRevision: repositoryRevision,
                referenceRevision: referenceRevision,
                installationRevision: nil
            )
        }
        try await mountReferenceSnapshot(
            workspace: workspace,
            revision: reference,
            referenceDatabase: referenceDatabase,
            mainDatabase: mainDatabase
        )

    case let (.some(reference), nil, nil):
        // Resume first preparation after the reference database committed.
        let insertion = try sourceInsertion(
            workspace: workspace,
            repositoryURL: location.repositoryURL
        )
        try await insertion.replaceSourceWorkspace(
            workspace,
            branch: workspace.defaultBranch,
            revision: reference,
            in: mainDatabase
        )
        let recoveredBaseline = WorkspaceBranchReference(
            branch: WorkspaceBranch(rawValue: workspace.defaultBranch),
            revision: WorkspaceRevision(rawValue: reference)
        )
        try await baselineStore.save(recoveredBaseline, workspaceID: workspace.id)
        baseline = recoveredBaseline

    default:
        throw SourceWorkspaceDatabaseError.persistedRevisionMismatch(
            workspaceID: workspace.id,
            repositoryRevision: repositoryRevision,
            referenceRevision: referenceRevision,
            installationRevision: installation?.revision
        )
    }

    let selectedBaseline = try baseline.required(
        SourceWorkspaceDatabaseError.contextMissing(workspace.id)
    )

    return WorkspaceSession(source: resource, baseline: selectedBaseline)
}

private func mountReferenceSnapshot(
    workspace: SourceWorkspace,
    revision: String,
    referenceDatabase: SourceBaselineDatabase,
    mainDatabase: any DatabaseWriter
) async throws {
    try await mainDatabase.write { db in
        try referenceDatabase.read { baselineDatabase in
            for projection in OME.sourceProjections {
                try SourceEditingResetter().reset(
                    workingDatabase: db,
                    baselineDatabase: baselineDatabase,
                    descriptors: [projection.recordType.descriptor],
                    scope: sourceScope(for: projection, workspace: workspace)
                )
            }
        }
        try SourceWorkspaceInstallationRecord.upsert {
            SourceWorkspaceInstallationRecord(id: workspace.id, revision: revision)
        }
        .execute(db)
    }
}

private func prepareWorkspacePublishedUpdate(
    source: SourceWorkspaceResource,
    workspaceID: SourceWorkspace.ID,
    attempt: WorkspacePublicationAttempt<SourcePatch>
) async throws -> PreparedWorkspacePublishedUpdate {
    @Dependency(\.defaultDatabase) var mainDatabase
    @Dependency(\.sourcePatchApplier) var patchApplier
    @Dependency(\.sourceWorkingTreeMaterializer) var materializer

    try validate(source: source, workspaceID: workspaceID, database: mainDatabase)
    let persisted = try SourceWorkspaceBaselineStore(database: mainDatabase)
        .load(workspaceID)
    guard persisted == attempt.target else {
        throw SourceWorkspaceDatabaseError.contextMismatch(workspaceID)
    }

    let workingTree = try materializer.materialize(source.repositoryURL, nil)
    defer { try? FileManager.default.removeItem(at: workingTree.workingRepositoryURL) }
    try patchApplier.apply(attempt.changes, workingTree.workingRepositoryURL)
    let insertion = try sourceInsertion(
        workspace: source.workspace,
        repositoryURL: workingTree.workingRepositoryURL
    )
    let replacement = try await insertion.prepareWorkspaceReplacement(source.workspace)
    let patch = attempt.changes

    return PreparedWorkspacePublishedUpdate { published in
        guard published.branch == attempt.target.branch,
              published.revision != attempt.target.revision
        else {
            throw SourceWorkspaceDatabaseError.publishedDestinationMismatch
        }
        try patchApplier.apply(patch, source.repositoryURL)
        try await replacement.replace(
            branch: published.branch.rawValue,
            revision: published.revision.rawValue,
            recordsReferenceRevision: true,
            in: source.referenceDatabase.database
        )
        do {
            try await SourceWorkspaceBaselineStore(database: mainDatabase)
                .install(published, workspaceID: workspaceID)
        } catch {
            throw WorkspaceReferenceUpdateIncomplete(
                mountedBaseline: published,
                message: String(describing: error)
            )
        }
        return published
    }
}

private func installBranchBaseline(
    source: SourceWorkspaceResource,
    workspaceID: SourceWorkspace.ID,
    branch: WorkspaceBranch,
    resolveRevision: @escaping SourceWorkspaceRevisionResolver,
    requireClean: Bool = true
) async throws -> WorkspaceBranchReference {
    @Dependency(\.defaultDatabase) var mainDatabase
    @Dependency(SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self) var patchGenerator
    @Dependency(SourceWorkspaceCheckoutClient.self) var checkout

    try validate(source: source, workspaceID: workspaceID, database: mainDatabase)
    if requireClean {
        let changes = try await patchGenerator.generate(
            SourceWorkspacePatchRequest(workspace: source.workspace)
        )
        guard changes.isEmpty else {
            throw SourceWorkspaceDatabaseError.localChangesPreventContextSelection(workspaceID)
        }
    }
    let baselineStore = SourceWorkspaceBaselineStore(database: mainDatabase)
    let previousBaseline = try baselineStore.load(workspaceID).required(
        SourceWorkspaceDatabaseError.contextMissing(workspaceID)
    )
    let previousInsertion = try sourceInsertion(
        workspace: source.workspace,
        repositoryURL: source.repositoryURL
    )
    let previousReplacement = try await previousInsertion.prepareWorkspaceReplacement(
        source.workspace
    )

    let preparedRepositoryURL = source.repositoryURL
        .deletingLastPathComponent()
        .appending(path: "repository-refresh-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: preparedRepositoryURL) }
    let preparedCheckout = try await checkout.checkout(
        source.workspace,
        branch,
        preparedRepositoryURL
    )
    guard preparedCheckout.reference.branch == branch else {
        throw SourceWorkspaceDatabaseError.contextSelectionRevisionChanged(
            expected: branch.rawValue,
            observed: preparedCheckout.reference.branch.rawValue
        )
    }
    let revision = preparedCheckout.reference.revision
    let preparedInsertion = try sourceInsertion(
        workspace: source.workspace,
        repositoryURL: preparedRepositoryURL
    )
    let preparedReplacement = try await preparedInsertion.prepareWorkspaceReplacement(
        source.workspace
    )
    let baseline = WorkspaceBranchReference(
        branch: branch,
        revision: revision
    )

    do {
        try await preparedReplacement.replace(
            branch: branch.rawValue,
            revision: revision.rawValue,
            recordsReferenceRevision: true,
            in: source.referenceDatabase.database
        )
        try await preparedReplacement.replace(
            branch: branch.rawValue,
            revision: revision.rawValue,
            in: mainDatabase
        )
        try await baselineStore.save(baseline, workspaceID: workspaceID)
        let backupRepositoryURL = try replaceRepository(
            at: source.repositoryURL,
            with: preparedRepositoryURL
        )
        try? FileManager.default.removeItem(at: backupRepositoryURL)
        return baseline
    } catch {
        let selectionError = error
        var rollbackFailures: [String] = []
        do {
            try await previousReplacement.replace(
                branch: previousBaseline.branch.rawValue,
                revision: previousBaseline.revision.rawValue,
                recordsReferenceRevision: true,
                in: source.referenceDatabase.database
            )
        } catch {
            rollbackFailures.append("Reference database: \(String(describing: error))")
        }
        do {
            try await previousReplacement.replace(
                branch: previousBaseline.branch.rawValue,
                revision: previousBaseline.revision.rawValue,
                in: mainDatabase
            )
            try await baselineStore.save(previousBaseline, workspaceID: workspaceID)
        } catch {
            rollbackFailures.append("Application database: \(String(describing: error))")
        }
        guard rollbackFailures.isEmpty else {
            throw SourceWorkspaceDatabaseError.contextSelectionRollbackFailed(
                selection: String(describing: selectionError),
                rollback: rollbackFailures.joined(separator: "\n")
            )
        }
        throw selectionError
    }
}

/// Moves an authoring workspace to the live default branch while carrying the exact edits that
/// were captured for its pending proposal onto the new base.
private func reconcileWorkspace(
    source: SourceWorkspaceResource,
    workspaceID: SourceWorkspace.ID,
    attempt: WorkspaceProposalAttempt<SourcePatch>,
    resolveRevision: @escaping SourceWorkspaceRevisionResolver
) async throws -> WorkspaceBranchReference {
    @Dependency(\.defaultDatabase) var mainDatabase
    @Dependency(\.sourcePatchApplier) var patchApplier
    @Dependency(\.sourceWorkingTreeMaterializer) var materializer
    @Dependency(SourceWorkspaceCheckoutClient.self) var checkout
    @Dependency(SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self) var patchGenerator

    try validate(source: source, workspaceID: workspaceID, database: mainDatabase)
    let baselineStore = SourceWorkspaceBaselineStore(database: mainDatabase)
    let previousBaseline = try baselineStore.load(workspaceID).required(
        SourceWorkspaceDatabaseError.contextMissing(workspaceID)
    )
    guard previousBaseline == attempt.target else {
        throw SourceWorkspaceDatabaseError.contextMismatch(workspaceID)
    }

    let currentChanges = try await patchGenerator.generate(
        SourceWorkspacePatchRequest(workspace: source.workspace)
    )
    guard currentChanges == attempt.changes else {
            throw SourceWorkspaceDatabaseError.localChangesChanged(workspaceID)
    }

    let previousInsertion = try sourceInsertion(
        workspace: source.workspace,
        repositoryURL: source.repositoryURL
    )
    let previousReplacement = try await previousInsertion.prepareWorkspaceReplacement(
        source.workspace
    )
    let preparedRepositoryURL = source.repositoryURL
        .deletingLastPathComponent()
        .appending(path: "repository-reconcile-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: preparedRepositoryURL) }

    let preparedCheckout = try await checkout.checkout(
        source.workspace,
        WorkspaceBranch(rawValue: source.workspace.defaultBranch),
        preparedRepositoryURL
    )
    let baseline = preparedCheckout.reference
    let observedRevision = try await resolveRevision(
        Repository(url: preparedRepositoryURL),
        RefName(rawValue: "HEAD")
    )
    guard observedRevision.rawValue == baseline.revision.rawValue else {
        throw SourceWorkspaceDatabaseError.contextSelectionRevisionChanged(
            expected: baseline.revision.rawValue,
            observed: observedRevision.rawValue
        )
    }
    let workingTree = try materializer.materialize(preparedRepositoryURL, nil)
    defer { try? FileManager.default.removeItem(at: workingTree.workingRepositoryURL) }
    try patchApplier.apply(attempt.changes, workingTree.workingRepositoryURL)

    let referenceInsertion = try sourceInsertion(
        workspace: source.workspace,
        repositoryURL: preparedRepositoryURL
    )
    let workingInsertion = try sourceInsertion(
        workspace: source.workspace,
        repositoryURL: workingTree.workingRepositoryURL
    )
    let referenceReplacement = try await referenceInsertion.prepareWorkspaceReplacement(
        source.workspace
    )
    let workingReplacement = try await workingInsertion.prepareWorkspaceReplacement(
        source.workspace
    )

    do {
        try await referenceReplacement.replace(
            branch: baseline.branch.rawValue,
            revision: baseline.revision.rawValue,
            recordsReferenceRevision: true,
            in: source.referenceDatabase.database
        )
        try await workingReplacement.replace(
            branch: baseline.branch.rawValue,
            revision: baseline.revision.rawValue,
            in: mainDatabase
        )
        try await baselineStore.save(baseline, workspaceID: workspaceID)
        let backupRepositoryURL = try replaceRepository(
            at: source.repositoryURL,
            with: preparedRepositoryURL
        )
        try? FileManager.default.removeItem(at: backupRepositoryURL)
        return baseline
    } catch {
        let reconciliationError = error
        var rollbackFailures: [String] = []
        do {
            try await previousReplacement.replace(
                branch: previousBaseline.branch.rawValue,
                revision: previousBaseline.revision.rawValue,
                recordsReferenceRevision: true,
                in: source.referenceDatabase.database
            )
        } catch {
            rollbackFailures.append("Reference database: \(String(describing: error))")
        }
        do {
            try await previousReplacement.replace(
                branch: previousBaseline.branch.rawValue,
                revision: previousBaseline.revision.rawValue,
                in: mainDatabase
            )
            try await baselineStore.save(previousBaseline, workspaceID: workspaceID)
        } catch {
            rollbackFailures.append("Application database: \(String(describing: error))")
        }
        guard rollbackFailures.isEmpty else {
            throw SourceWorkspaceDatabaseError.contextSelectionRollbackFailed(
                selection: String(describing: reconciliationError),
                rollback: rollbackFailures.joined(separator: "\n")
            )
        }
        throw reconciliationError
    }
}

private func validate(
    source: SourceWorkspaceResource,
    workspaceID: SourceWorkspace.ID,
    database: any DatabaseWriter
) throws {
    guard source.workspace.id == workspaceID else {
        throw SourceWorkspaceDatabaseError.resourceMismatch(workspaceID)
    }
    guard source.applicationDatabaseID == ObjectIdentifier(database) else {
        throw SourceWorkspaceDatabaseError.applicationDatabaseMismatch(workspaceID)
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
    case contextMismatch(SourceWorkspace.ID)
    case contextMissing(SourceWorkspace.ID)
    case contextSelectionRollbackFailed(selection: String, rollback: String)
    case contextSelectionRevisionChanged(expected: String, observed: String)
    case localChangesPreventContextSelection(SourceWorkspace.ID)
    case localChangesChanged(SourceWorkspace.ID)
    case persistedRevisionMismatch(
        workspaceID: SourceWorkspace.ID,
        repositoryRevision: String,
        referenceRevision: String?,
        installationRevision: String?
    )
    case proposalDestinationMismatch
    case publishedDestinationMismatch
    case proposalSnapshotUnavailable(SourceWorkspace.ID)
    case repositoryMissing(SourceWorkspace.ID)
    case resourceMismatch(SourceWorkspace.ID)
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
        if values.isDirectory == true { continue }
        guard values.isRegularFile == true else {
            throw SourceWorkspaceArchiveError.unsupportedEntry(relativePath)
        }
        paths.append(RepositoryPath(rawValue: relativePath))
    }
    return paths.sorted { $0.rawValue < $1.rawValue }
}

private enum SourceWorkspacePreparationCoordinator {
    static let shared = Coordinator()

    actor Coordinator {
        private var operations: [
            SourceWorkspace.ID: Task<WorkspaceSession<SourceWorkspaceResource>, Error>
        ] = [:]

        func prepare(
            _ workspace: SourceWorkspace,
            operation: @escaping @Sendable () async throws
                -> WorkspaceSession<SourceWorkspaceResource>
        ) async throws -> WorkspaceSession<SourceWorkspaceResource> {
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

private extension Optional {
    func required(_ error: @autoclosure () -> any Error) throws -> Wrapped {
        guard let self else { throw error() }
        return self
    }
}
