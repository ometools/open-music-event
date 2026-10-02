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
        resolveRevision _: @escaping SourceWorkspaceRevisionResolver
    ) -> Self {
        Self(
            preparePublishedUpdate: { source, workspaceID, attempt in
                try await prepareWorkspacePublishedUpdate(
                    source: source,
                    workspaceID: workspaceID,
                    attempt: attempt
                )
            },
            reconcile: { source, workspaceID, current in
                try await reconcileBranchBaseline(
                    source: source,
                    workspaceID: workspaceID,
                    current: current
                )
            },
            discardChangesAndUpdate: { source, workspaceID, current in
                try await discardChangesAndInstallBranchBaseline(
                    source: source,
                    workspaceID: workspaceID,
                    current: current
                )
            },
            select: { source, workspaceID, branch in
                try await installBranchBaseline(
                    source: source,
                    workspaceID: workspaceID,
                    branch: branch
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

private func reconcileBranchBaseline(
    source: SourceWorkspaceResource,
    workspaceID: SourceWorkspace.ID,
    current: WorkspaceBranchReference
) async throws -> WorkspaceReconciliationResult<SourceWorkspaceResource> {
    while true {
        do {
            return try await reconcileBranchBaselineOnce(
                source: source,
                workspaceID: workspaceID,
                current: current
            )
        } catch SourceWorkspaceDatabaseError.concurrentLocalChanges {
            try Task.checkCancellation()
            continue
        }
    }
}

private func reconcileBranchBaselineOnce(
    source: SourceWorkspaceResource,
    workspaceID: SourceWorkspace.ID,
    current: WorkspaceBranchReference
) async throws -> WorkspaceReconciliationResult<SourceWorkspaceResource> {
    @Dependency(\.defaultDatabase) var mainDatabase
    @Dependency(\.sourceControl) var sourceControl
    @Dependency(\.sourcePatchApplier) var patchApplier
    @Dependency(\.sourceWorkingTreeMaterializer) var materializer
    @Dependency(SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self) var patchGenerator
    @Dependency(SourceWorkspaceCheckoutClient.self) var checkout
    @Dependency(SourceWorkspaceRepositoryInstaller.self) var repositoryInstaller

    try validate(source: source, workspaceID: workspaceID, database: mainDatabase)
    let baselineStore = SourceWorkspaceBaselineStore(database: mainDatabase)
    let persisted = try baselineStore.load(workspaceID).required(
        SourceWorkspaceDatabaseError.contextMissing(workspaceID)
    )
    guard persisted == current else {
        throw SourceWorkspaceDatabaseError.contextMismatch(workspaceID)
    }

    let preparedRepositoryURL = source.repositoryURL
        .deletingLastPathComponent()
        .appending(path: "repository-reconcile-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: preparedRepositoryURL) }
    let upstream = try await checkout.checkout(
        source.workspace,
        current.branch,
        preparedRepositoryURL
    )
    guard upstream.reference.branch == current.branch else {
        throw SourceWorkspaceDatabaseError.contextSelectionRevisionChanged(
            expected: current.branch.rawValue,
            observed: upstream.reference.branch.rawValue
        )
    }
    guard upstream.reference != current else {
        return .current(WorkspaceSession(source: source, baseline: current))
    }

    let snapshotBeforeCapture = try await mainDatabase.read { db in
        try SourceWorkspaceDatabaseSnapshot(workspace: source.workspace, in: db)
    }
    let localPatch = try await patchGenerator.generate(
        SourceWorkspacePatchRequest(workspace: source.workspace)
    )
    let capturedSnapshot = try await mainDatabase.read { db in
        try SourceWorkspaceDatabaseSnapshot(workspace: source.workspace, in: db)
    }
    guard snapshotBeforeCapture == capturedSnapshot else {
        throw SourceWorkspaceDatabaseError.concurrentLocalChanges(workspaceID)
    }

    var reconciledChanges: [SourcePatchFileChange] = []
    var conflictingPaths: Set<String> = []
    for change in localPatch.fileChanges {
        let upstreamContents = try sourceFileContents(
            at: change.path,
            under: preparedRepositoryURL
        )
        let result = try await sourceControl.mergeFile(
            SourceControlFileMergeRequest(
                path: RepositoryPath(rawValue: change.path),
                baseContents: change.oldContents,
                localContents: change.newContents,
                upstreamContents: upstreamContents
            )
        )
        switch result {
        case .conflicted:
            conflictingPaths.insert(change.path)

        case let .merged(mergedContents):
            if let reconciled = sourcePatchFileChange(
                path: change.path,
                oldContents: upstreamContents,
                newContents: mergedContents
            ) {
                reconciledChanges.append(reconciled)
            }
        }
    }

    guard conflictingPaths.isEmpty else {
        return .conflicted(
            WorkspaceReconciliationConflict(
                baseline: current,
                upstream: upstream.reference,
                conflictingPaths: conflictingPaths.sorted().map {
                    WorkspaceConflictPath(rawValue: $0)
                }
            )
        )
    }

    let reconciledPatch = SourcePatch(
        fileChanges: reconciledChanges.sorted { $0.path < $1.path }
    )
    let reconciledTree = try materializer.materialize(preparedRepositoryURL, nil)
    defer { try? FileManager.default.removeItem(at: reconciledTree.workingRepositoryURL) }
    try patchApplier.apply(reconciledPatch, reconciledTree.workingRepositoryURL)

    let oldWorkingTree = try materializer.materialize(source.repositoryURL, nil)
    defer { try? FileManager.default.removeItem(at: oldWorkingTree.workingRepositoryURL) }
    try patchApplier.apply(localPatch, oldWorkingTree.workingRepositoryURL)

    let oldCleanReplacement = try await sourceInsertion(
        workspace: source.workspace,
        repositoryURL: source.repositoryURL
    )
    .prepareWorkspaceReplacement(source.workspace)
    let oldWorkingReplacement = try await sourceInsertion(
        workspace: source.workspace,
        repositoryURL: oldWorkingTree.workingRepositoryURL
    )
    .prepareWorkspaceReplacement(source.workspace)
    let upstreamReplacement = try await sourceInsertion(
        workspace: source.workspace,
        repositoryURL: preparedRepositoryURL
    )
    .prepareWorkspaceReplacement(source.workspace)
    let reconciledReplacement = try await sourceInsertion(
        workspace: source.workspace,
        repositoryURL: reconciledTree.workingRepositoryURL
    )
    .prepareWorkspaceReplacement(source.workspace)
    let publicationPersistence = WorkspacePublicationPersistence(database: mainDatabase)
    let recoverySnapshot = try publicationPersistence.recoverySnapshot(workspaceID)
    var referenceDatabaseWasReplaced = false
    var writableDatabaseWasReplaced = false

    do {
        try await upstreamReplacement.replace(
            branch: upstream.reference.branch.rawValue,
            revision: upstream.reference.revision.rawValue,
            recordsReferenceRevision: true,
            in: source.referenceDatabase.database
        )
        referenceDatabaseWasReplaced = true
        try await mainDatabase.write { db in
            let latestSnapshot = try SourceWorkspaceDatabaseSnapshot(
                workspace: source.workspace,
                in: db
            )
            guard latestSnapshot == capturedSnapshot else {
                throw SourceWorkspaceDatabaseError.concurrentLocalChanges(workspaceID)
            }
            try reconciledReplacement.replace(
                branch: upstream.reference.branch.rawValue,
                revision: upstream.reference.revision.rawValue,
                in: db
            )
            try publicationPersistence.reconcileCheckpoint(
                workspaceID: workspaceID,
                from: current,
                to: upstream.reference,
                changes: reconciledPatch,
                in: db
            )
        }
        writableDatabaseWasReplaced = true
        let backupRepositoryURL = try repositoryInstaller.replace(
            source.repositoryURL,
            preparedRepositoryURL
        )
        try? FileManager.default.removeItem(at: backupRepositoryURL)
    } catch {
        let reconciliationError = error
        var rollbackFailures: [String] = []
        if referenceDatabaseWasReplaced {
            do {
                try await oldCleanReplacement.replace(
                    branch: current.branch.rawValue,
                    revision: current.revision.rawValue,
                    recordsReferenceRevision: true,
                    in: source.referenceDatabase.database
                )
            } catch {
                rollbackFailures.append("Reference database: \(String(describing: error))")
            }
        }
        if writableDatabaseWasReplaced {
            do {
                try await mainDatabase.write { db in
                    try oldWorkingReplacement.replace(
                        branch: current.branch.rawValue,
                        revision: current.revision.rawValue,
                        in: db
                    )
                    try publicationPersistence.restoreRecoverySnapshot(
                        recoverySnapshot,
                        workspaceID: workspaceID,
                        in: db
                    )
                }
            } catch {
                rollbackFailures.append("Application database: \(String(describing: error))")
            }
        }
        guard rollbackFailures.isEmpty else {
            throw SourceWorkspaceDatabaseError.reconciliationRollbackFailed(
                reconciliation: String(describing: reconciliationError),
                rollback: rollbackFailures.joined(separator: "\n")
            )
        }
        throw reconciliationError
    }

    return .current(
        WorkspaceSession(source: source, baseline: upstream.reference)
    )
}

private func discardChangesAndInstallBranchBaseline(
    source: SourceWorkspaceResource,
    workspaceID: SourceWorkspace.ID,
    current: WorkspaceBranchReference
) async throws -> WorkspaceSession<SourceWorkspaceResource> {
    @Dependency(\.defaultDatabase) var mainDatabase
    @Dependency(\.sourceWorkingTreeMaterializer) var materializer
    @Dependency(SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self) var patchGenerator
    @Dependency(SourceWorkspaceCheckoutClient.self) var checkout
    @Dependency(SourceWorkspaceRepositoryInstaller.self) var repositoryInstaller

    try validate(source: source, workspaceID: workspaceID, database: mainDatabase)
    let persisted = try SourceWorkspaceBaselineStore(database: mainDatabase)
        .load(workspaceID)
        .required(SourceWorkspaceDatabaseError.contextMissing(workspaceID))
    guard persisted == current else {
        throw SourceWorkspaceDatabaseError.contextMismatch(workspaceID)
    }

    let snapshotBeforeCapture = try await mainDatabase.read { db in
        try SourceWorkspaceDatabaseSnapshot(workspace: source.workspace, in: db)
    }
    let localPatch = try await patchGenerator.generate(
        SourceWorkspacePatchRequest(workspace: source.workspace)
    )
    let capturedSnapshot = try await mainDatabase.read { db in
        try SourceWorkspaceDatabaseSnapshot(workspace: source.workspace, in: db)
    }
    guard snapshotBeforeCapture == capturedSnapshot else {
        throw SourceWorkspaceDatabaseError.concurrentLocalChanges(workspaceID)
    }

    let preparedRepositoryURL = source.repositoryURL
        .deletingLastPathComponent()
        .appending(path: "repository-discard-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: preparedRepositoryURL) }
    let upstream = try await checkout.checkout(
        source.workspace,
        current.branch,
        preparedRepositoryURL
    )
    guard upstream.reference.branch == current.branch else {
        throw SourceWorkspaceDatabaseError.contextSelectionRevisionChanged(
            expected: current.branch.rawValue,
            observed: upstream.reference.branch.rawValue
        )
    }

    let oldWorkingTree = try materializer.materialize(source.repositoryURL, nil)
    defer { try? FileManager.default.removeItem(at: oldWorkingTree.workingRepositoryURL) }
    @Dependency(\.sourcePatchApplier) var patchApplier
    try patchApplier.apply(localPatch, oldWorkingTree.workingRepositoryURL)

    let oldCleanReplacement = try await sourceInsertion(
        workspace: source.workspace,
        repositoryURL: source.repositoryURL
    )
    .prepareWorkspaceReplacement(source.workspace)
    let oldWorkingReplacement = try await sourceInsertion(
        workspace: source.workspace,
        repositoryURL: oldWorkingTree.workingRepositoryURL
    )
    .prepareWorkspaceReplacement(source.workspace)
    let upstreamReplacement = try await sourceInsertion(
        workspace: source.workspace,
        repositoryURL: preparedRepositoryURL
    )
    .prepareWorkspaceReplacement(source.workspace)
    let publicationPersistence = WorkspacePublicationPersistence(database: mainDatabase)
    let recoverySnapshot = try publicationPersistence.recoverySnapshot(workspaceID)
    var referenceDatabaseWasReplaced = false
    var writableDatabaseWasReplaced = false

    do {
        try await upstreamReplacement.replace(
            branch: upstream.reference.branch.rawValue,
            revision: upstream.reference.revision.rawValue,
            recordsReferenceRevision: true,
            in: source.referenceDatabase.database
        )
        referenceDatabaseWasReplaced = true
        try await mainDatabase.write { db in
            let latestSnapshot = try SourceWorkspaceDatabaseSnapshot(
                workspace: source.workspace,
                in: db
            )
            guard latestSnapshot == capturedSnapshot else {
                throw SourceWorkspaceDatabaseError.concurrentLocalChanges(workspaceID)
            }
            try upstreamReplacement.replace(
                branch: upstream.reference.branch.rawValue,
                revision: upstream.reference.revision.rawValue,
                in: db
            )
            try publicationPersistence.discardUnpublishedCheckpoint(
                workspaceID: workspaceID,
                in: db
            )
        }
        writableDatabaseWasReplaced = true
        let backupRepositoryURL = try repositoryInstaller.replace(
            source.repositoryURL,
            preparedRepositoryURL
        )
        try? FileManager.default.removeItem(at: backupRepositoryURL)
    } catch {
        let discardError = error
        var rollbackFailures: [String] = []
        if referenceDatabaseWasReplaced {
            do {
                try await oldCleanReplacement.replace(
                    branch: current.branch.rawValue,
                    revision: current.revision.rawValue,
                    recordsReferenceRevision: true,
                    in: source.referenceDatabase.database
                )
            } catch {
                rollbackFailures.append("Reference database: \(String(describing: error))")
            }
        }
        if writableDatabaseWasReplaced {
            do {
                try await mainDatabase.write { db in
                    try oldWorkingReplacement.replace(
                        branch: current.branch.rawValue,
                        revision: current.revision.rawValue,
                        in: db
                    )
                    try publicationPersistence.restoreRecoverySnapshot(
                        recoverySnapshot,
                        workspaceID: workspaceID,
                        in: db
                    )
                }
            } catch {
                rollbackFailures.append("Application database: \(String(describing: error))")
            }
        }
        guard rollbackFailures.isEmpty else {
            throw SourceWorkspaceDatabaseError.reconciliationRollbackFailed(
                reconciliation: String(describing: discardError),
                rollback: rollbackFailures.joined(separator: "\n")
            )
        }
        throw discardError
    }

    return WorkspaceSession(source: source, baseline: upstream.reference)
}

private func sourcePatchFileChange(
    path: String,
    oldContents: Data?,
    newContents: Data?
) -> SourcePatchFileChange? {
    switch (oldContents, newContents) {
    case (nil, nil):
        return nil
    case (nil, let newContents?):
        return SourcePatchFileChange(path: path, kind: .added, newContents: newContents)
    case (let oldContents?, nil):
        return SourcePatchFileChange(path: path, kind: .deleted, oldContents: oldContents)
    case (let oldContents?, let newContents?):
        guard oldContents != newContents else { return nil }
        return SourcePatchFileChange(
            path: path,
            kind: .modified,
            oldContents: oldContents,
            newContents: newContents
        )
    }
}

private func sourceFileContents(at path: String, under rootURL: URL) throws -> Data? {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    let components = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    guard !trimmed.isEmpty,
          !trimmed.hasPrefix("/"),
          components.joined(separator: "/") == trimmed,
          !components.contains("."),
          !components.contains("..")
    else {
        throw SourcePatchApplierError.invalidPatchPath(path)
    }
    let fileURL = components.reduce(rootURL.standardizedFileURL) { url, component in
        url.appending(path: component)
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
        return nil
    }
    guard !isDirectory.boolValue else {
        throw SourcePatchApplierError.invalidPatchPath(path)
    }
    return try Data(contentsOf: fileURL)
}

private func installBranchBaseline(
    source: SourceWorkspaceResource,
    workspaceID: SourceWorkspace.ID,
    branch: WorkspaceBranch
) async throws -> WorkspaceBranchReference {
    @Dependency(\.defaultDatabase) var mainDatabase
    @Dependency(SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self) var patchGenerator
    @Dependency(SourceWorkspaceCheckoutClient.self) var checkout

    try validate(source: source, workspaceID: workspaceID, database: mainDatabase)
    let changes = try await patchGenerator.generate(
        SourceWorkspacePatchRequest(workspace: source.workspace)
    )
    guard changes.isEmpty else {
        throw SourceWorkspaceDatabaseError.localChangesPreventContextSelection(workspaceID)
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

private struct SourceWorkspaceDatabaseSnapshot: Equatable, Sendable {
    var organizer: OME.Organizer?
    var calendar: OME.Calendar?
    var calendarEntries: [OME.CalendarEntry]
    var collaborators: [WorkspaceRelationshipRecord]
    var provenances: [EventSourceProvenanceRecord]
    var events: [OME.Event]
    var siteMaps: [OME.Event.SiteMap]
    var stages: [OME.Stage]
    var schedules: [OME.Schedule]
    var contributors: [OME.Contributor]
    var channels: [OME.Channel]
    var communicationPosts: [CommsPost]
    var posters: [OME.Poster]
    var scheduleItems: [OME.ScheduleItem]
    var performanceDetails: [OME.ScheduleItem.PerformanceDetails]
    var scheduleItemContributors: [OME.ScheduleItem.Contributor]
    var localImageBlobs: [LocalImageBlob]

    init(workspace: SourceWorkspace, in database: Database) throws {
        let calendarID = OME.Calendar.ID(
            ownerID: workspace.organizerID,
            calendarID: OME.Calendar.defaultID
        )
        let provenances = try EventSourceProvenanceRecord
            .where { $0.id.organizerID.eq(workspace.organizerID) }
            .fetchAll(database)
            .filter { $0.workspace?.id == workspace.id }
        let eventIDs = Set(provenances.map(\.id.eventID))

        self.organizer = try OME.Organizer.find(workspace.organizerID).fetchOne(database)
        self.calendar = try OME.Calendar.find(calendarID).fetchOne(database)
        self.calendarEntries = try OME.CalendarEntry
            .where { $0.id.calendarOwnerID.eq(workspace.organizerID) }
            .where { $0.id.calendarID.eq(OME.Calendar.defaultID) }
            .fetchAll(database)
        self.collaborators = try WorkspaceRelationshipRecord
            .where { $0.id.workspaceID.eq(workspace.id) }
            .fetchAll(database)
        self.provenances = provenances
        self.events = try OME.Event
            .where { $0.id.organizerID.eq(workspace.organizerID) }
            .fetchAll(database)
            .filter { eventIDs.contains($0.id.eventID) }
        self.siteMaps = try OME.Event.SiteMap
            .where { $0.id.organizerID.eq(workspace.organizerID) }
            .fetchAll(database)
            .filter { eventIDs.contains($0.id.eventID) }
        self.stages = try OME.Stage
            .where { $0.id.organizerID.eq(workspace.organizerID) }
            .fetchAll(database)
            .filter { eventIDs.contains($0.id.eventID) }
        self.schedules = try OME.Schedule
            .where { $0.id.organizerID.eq(workspace.organizerID) }
            .fetchAll(database)
            .filter { eventIDs.contains($0.id.eventID) }
        self.contributors = try OME.Contributor
            .where { $0.id.organizerID.eq(workspace.organizerID) }
            .fetchAll(database)
            .filter { eventIDs.contains($0.id.eventID) }
        self.channels = try OME.Channel
            .where { $0.id.organizerID.eq(workspace.organizerID) }
            .fetchAll(database)
            .filter { eventIDs.contains($0.id.eventID) }
        self.communicationPosts = try CommsPost
            .where { $0.id.organizerID.eq(workspace.organizerID) }
            .fetchAll(database)
            .filter { eventIDs.contains($0.id.eventID) }
        self.posters = try OME.Poster
            .where { $0.id.organizerID.eq(workspace.organizerID) }
            .fetchAll(database)
            .filter { eventIDs.contains($0.id.eventID) }
        self.scheduleItems = try OME.ScheduleItem
            .where { $0.id.organizerID.eq(workspace.organizerID) }
            .fetchAll(database)
            .filter { eventIDs.contains($0.id.eventID) }
        self.performanceDetails = try OME.ScheduleItem.PerformanceDetails
            .where { $0.id.organizerID.eq(workspace.organizerID) }
            .fetchAll(database)
            .filter { eventIDs.contains($0.id.eventID) }
        self.scheduleItemContributors = try OME.ScheduleItem.Contributor
            .where { $0.id.organizerID.eq(workspace.organizerID) }
            .fetchAll(database)
            .filter { eventIDs.contains($0.id.eventID) }
        let organizerID = workspace.organizerID
        let organizerImageBlobs = try LocalImageBlob
            .where { blob in blob.organizerID.eq(organizerID) }
            .fetchAll(database)
        self.localImageBlobs = organizerImageBlobs.filter { blob in
            guard let eventID = blob.eventID else {
                return blob.parentKind == .calendar
            }
            return eventIDs.contains(eventID)
        }
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

package struct SourceWorkspaceRepositoryInstaller: Sendable {
    package var replace: @Sendable (_ repositoryURL: URL, _ replacementURL: URL) throws -> URL

    package init(
        replace: @escaping @Sendable (
            _ repositoryURL: URL,
            _ replacementURL: URL
        ) throws -> URL
    ) {
        self.replace = replace
    }
}

extension SourceWorkspaceRepositoryInstaller: DependencyKey {
    package static let liveValue = Self { repositoryURL, replacementURL in
        try replaceRepository(at: repositoryURL, with: replacementURL)
    }

    package static let testValue = liveValue
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
    case concurrentLocalChanges(SourceWorkspace.ID)
    case contextMismatch(SourceWorkspace.ID)
    case contextMissing(SourceWorkspace.ID)
    case contextSelectionRollbackFailed(selection: String, rollback: String)
    case contextSelectionRevisionChanged(expected: String, observed: String)
    case localChangesPreventContextSelection(SourceWorkspace.ID)
    case persistedRevisionMismatch(
        workspaceID: SourceWorkspace.ID,
        repositoryRevision: String,
        referenceRevision: String?,
        installationRevision: String?
    )
    case proposalDestinationMismatch
    case publishedDestinationMismatch
    case proposalSnapshotUnavailable(SourceWorkspace.ID)
    case reconciliationRollbackFailed(reconciliation: String, rollback: String)
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
