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
    public var open: @Sendable (EditingWorkspaceRecord.ID) throws -> WorkspaceContext
    public var prepareSource: @Sendable (EditingWorkspaceRecord.ID) async throws -> Void

    public init(
        open: @escaping @Sendable (
            EditingWorkspaceRecord.ID
        ) throws -> WorkspaceContext,
        prepareSource: @escaping @Sendable (
            EditingWorkspaceRecord.ID
        ) async throws -> Void
    ) {
        self.open = open
        self.prepareSource = prepareSource
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
        return Self(
            open: { workspaceID in
                @Dependency(\.sourceWorkspaceDatabase) var sourceWorkspaceDatabase
                return WorkspaceContext(
                    id: workspaceID,
                    sourceWorkspaceDatabase: try sourceWorkspaceDatabase.workspace(workspaceID)
                )
            },
            prepareSource: { workspaceID in
                try await WorkspaceSourcePreparationCoordination.live.prepare(workspaceID) {
                    try await Self.prepareSource(workspaceID)
                }
            }
        )
    }

    static var passthrough: Self {
        Self(
            open: { workspaceID in
                @Dependency(\.defaultDatabase) var database
                return WorkspaceContext(
                    id: workspaceID,
                    sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: database)
                )
            },
            prepareSource: { _ in }
        )
    }

    private static func prepareSource(
        _ workspaceID: EditingWorkspaceRecord.ID
    ) async throws {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.sourceEditModePreparation) var sourceEditModePreparation

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
    }
}

private enum WorkspaceSourcePreparationCoordination {
    static let live = WorkspaceSourcePreparationCoordinator()
}

private actor WorkspaceSourcePreparationCoordinator {
    struct InFlightPreparation {
        var id: Int
        var task: Task<Void, Error>
    }

    var inFlightPreparations: [
        EditingWorkspaceRecord.ID: InFlightPreparation
    ] = [:]
    var nextID = 0

    func prepare(
        _ workspaceID: EditingWorkspaceRecord.ID,
        operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        if let preparation = inFlightPreparations[workspaceID] {
            try await preparation.task.value
            return
        }

        nextID += 1
        let preparation = InFlightPreparation(
            id: nextID,
            task: Task {
                try await operation()
            }
        )
        inFlightPreparations[workspaceID] = preparation
        defer {
            if inFlightPreparations[workspaceID]?.id == preparation.id {
                inFlightPreparations[workspaceID] = nil
            }
        }
        try await preparation.task.value
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
