import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import SQLiteData

public struct SourceEditModePreparationClient: Sendable {
    public var prepare: @Sendable (SourceBaselineRecord.ID) async throws -> Void

    public init(
        prepare: @escaping @Sendable (SourceBaselineRecord.ID) async throws -> Void
    ) {
        self.prepare = prepare
    }
}

public struct WorkspacePreparationClient: Sendable {
    public var prepare: @Sendable (EditingWorkspaceRecord.ID) async throws -> WorkspaceContext

    public init(
        prepare: @escaping @Sendable (
            EditingWorkspaceRecord.ID
        ) async throws -> WorkspaceContext
    ) {
        self.prepare = prepare
    }
}

public enum SourceEditModePreparationError: Equatable, Error, Sendable {
    case sourceBaselineNotFound(SourceBaselineRecord.ID)
}

public enum WorkspacePreparationError: Equatable, Error, Sendable {
    case workspaceMissingSourceBaseline(EditingWorkspaceRecord.ID)
    case workspaceNotFound(EditingWorkspaceRecord.ID)
}

public extension SourceEditModePreparationClient {
    static var live: Self {
        Self { sourceBaselineID in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage
            @Dependency(\.uuid) var uuid

            let sourceBaseline = try await database.read { db in
                try SourceBaselineRecord
                    .where { $0.id.eq(sourceBaselineID) }
                    .fetchOne(db)
            }
            guard let sourceBaseline else {
                throw SourceEditModePreparationError.sourceBaselineNotFound(sourceBaselineID)
            }

            let sourceProvenance = sourceBaseline.sourceProvenance
            var storedRepositoryURL = try sourceRepositoryStorage
                .repositoryURL(sourceProvenance)

            if sourceProvenance.kind == .tangled,
               !isGitRepository(storedRepositoryURL) {
                let checkoutURL = SourceRepositoryStorageClient.temporaryDownloadURL(uuid: uuid())
                do {
                    _ = try await withDependencies {
                        $0.tangledSourceCheckout = .git
                    } operation: {
                        @Dependency(\.tangledSourceCheckout) var tangledSourceCheckout
                        return try await tangledSourceCheckout.checkout(
                            TangledSourceCheckoutRequest(
                                repository: try TangledRepositoryReference(
                                    sourceReference: sourceProvenance.reference
                                ),
                                ref: sourceProvenance.ref ?? "HEAD",
                                outputURL: checkoutURL
                            )
                        )
                    }
                    storedRepositoryURL = try sourceRepositoryStorage.store(
                        checkoutURL,
                        sourceProvenance
                    )
                } catch {
                    try? FileManager.default.removeItem(at: checkoutURL)
                    throw error
                }
            }

            try SourceReferenceDatabaseClient
                .ensureReferenceDatabaseIgnored(in: storedRepositoryURL)
        }
    }

    static var noop: Self {
        Self { _ in }
    }
}

public extension WorkspacePreparationClient {
    static var live: Self {
        Self { workspaceID in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.sourceEditModePreparation) var sourceEditModePreparation
            @Dependency(\.sourceWorkspaceDatabase) var sourceWorkspaceDatabase

            let workspace = try await database.read { db in
                try EditingWorkspaceRecord
                    .where { $0.id.eq(workspaceID) }
                    .fetchOne(db)
            }
            guard let workspace else {
                throw WorkspacePreparationError.workspaceNotFound(workspaceID)
            }

            switch workspace.kind {
            case .local:
                break

            case .team:
                guard let sourceBaselineID = workspace.sourceBaselineID else {
                    throw WorkspacePreparationError.workspaceMissingSourceBaseline(workspaceID)
                }
                try await sourceEditModePreparation.prepare(sourceBaselineID)
            }

            return WorkspaceContext(
                id: workspaceID,
                sourceWorkspaceDatabase: try sourceWorkspaceDatabase.workspace(workspaceID)
            )
        }
    }

    static var passthrough: Self {
        Self { workspaceID in
            @Dependency(\.defaultDatabase) var database
            return WorkspaceContext(
                id: workspaceID,
                sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: database)
            )
        }
    }
}

private func isGitRepository(_ repositoryURL: URL) -> Bool {
    FileManager.default.fileExists(
        atPath: repositoryURL
            .standardizedFileURL
            .appending(path: ".git")
            .path(percentEncoded: false)
    )
}

public extension DependencyValues {
    var sourceEditModePreparation: SourceEditModePreparationClient {
        get { self[SourceEditModePreparationClientKey.self] }
        set { self[SourceEditModePreparationClientKey.self] = newValue }
    }
}

private enum SourceEditModePreparationClientKey: DependencyKey {
    static var liveValue: SourceEditModePreparationClient {
        .live
    }

    static var testValue: SourceEditModePreparationClient {
        .noop
    }
}

extension WorkspacePreparationClient: DependencyKey {
    public static var liveValue: Self { .live }
    public static var testValue: Self { .passthrough }
}
