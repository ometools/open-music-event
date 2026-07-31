import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData
import SourceEditing

public struct StagedSourceReferenceDatabase: Sendable {
    public let database: SourceBaselineDatabase
    public let databaseFileName: String
    private let commitOperation: @Sendable () throws -> Void
    private let discardOperation: @Sendable () throws -> Void

    public init(
        database: SourceBaselineDatabase,
        databaseFileName: String,
        commit: @escaping @Sendable () throws -> Void,
        discard: @escaping @Sendable () throws -> Void
    ) {
        self.database = database
        self.databaseFileName = databaseFileName
        self.commitOperation = commit
        self.discardOperation = discard
    }

    public func commit() throws {
        try commitOperation()
    }

    public func discard() throws {
        try discardOperation()
    }
}

/// Reference databases are snapshots. They may be updated only by controlled import/refresh and
/// must be attached read-only for application comparisons. They must never become
/// `defaultDatabase`.
public struct SourceReferenceDatabaseClient: Sendable {
    public var url: @Sendable (OME.SourceDatabaseInsertion.SourceProvenance) throws -> URL
    public var prepareForImport: @Sendable (OME.SourceDatabaseInsertion.SourceProvenance) throws -> StagedSourceReferenceDatabase
    public var existing: @Sendable (OME.SourceDatabaseInsertion.SourceProvenance) throws -> SourceBaselineDatabase?

    public init(
        url: @escaping @Sendable (OME.SourceDatabaseInsertion.SourceProvenance) throws -> URL,
        prepareForImport: @escaping @Sendable (OME.SourceDatabaseInsertion.SourceProvenance) throws -> StagedSourceReferenceDatabase,
        existing: @escaping @Sendable (OME.SourceDatabaseInsertion.SourceProvenance) throws -> SourceBaselineDatabase?
    ) {
        self.url = url
        self.prepareForImport = prepareForImport
        self.existing = existing
    }
}

public struct SourceReferenceDatabaseMigrator: Sendable {
    public var migrate: @Sendable (SourceBaselineDatabase) throws -> Void

    public init(
        migrate: @escaping @Sendable (SourceBaselineDatabase) throws -> Void
    ) {
        self.migrate = migrate
    }
}

public enum WorkspaceReferenceDatabaseError: Equatable, Error, Sendable {
    case sourceBaselineMissing(EditingWorkspaceRecord.ID)
    case teamWorkspaceMissingSourceBaseline(EditingWorkspaceRecord.ID)
}

public struct WorkspaceReferenceDatabaseClient: Sendable {
    public var urlForWorkspace: @Sendable (EditingWorkspaceRecord, SourceBaselineRecord?) throws -> URL
    public var prepareWorkspace: @Sendable (EditingWorkspaceRecord, SourceBaselineRecord?) throws -> SourceBaselineDatabase
    public var existingWorkspace: @Sendable (EditingWorkspaceRecord, SourceBaselineRecord?) throws -> SourceBaselineDatabase?

    public init(
        url: @escaping @Sendable (EditingWorkspaceRecord, SourceBaselineRecord?) throws -> URL,
        prepare: @escaping @Sendable (EditingWorkspaceRecord, SourceBaselineRecord?) throws -> SourceBaselineDatabase,
        existing: @escaping @Sendable (EditingWorkspaceRecord, SourceBaselineRecord?) throws -> SourceBaselineDatabase?
    ) {
        self.urlForWorkspace = url
        self.prepareWorkspace = prepare
        self.existingWorkspace = existing
    }

    public func url(
        _ workspace: EditingWorkspaceRecord,
        sourceBaseline: SourceBaselineRecord? = nil
    ) throws -> URL {
        try urlForWorkspace(workspace, sourceBaseline)
    }

    public func prepare(
        _ workspace: EditingWorkspaceRecord,
        sourceBaseline: SourceBaselineRecord? = nil
    ) throws -> SourceBaselineDatabase {
        try prepareWorkspace(workspace, sourceBaseline)
    }

    public func existing(
        _ workspace: EditingWorkspaceRecord,
        sourceBaseline: SourceBaselineRecord? = nil
    ) throws -> SourceBaselineDatabase? {
        try existingWorkspace(workspace, sourceBaseline)
    }
}

public extension SourceReferenceDatabaseMigrator {
    static let noop = Self { _ in }
}

public extension SourceReferenceDatabaseClient {
    static let relativePath = ".ome/reference.sqlite"
    static let gitignoreEntry = ".ome/reference.sqlite"

    static var live: Self {
        Self(
            url: { provenance in
                @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage
                return try referenceDatabaseURL(
                    repositoryURL: sourceRepositoryStorage.repositoryURL(provenance)
                )
            },
            prepareForImport: { provenance in
                @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage
                let repositoryURL = try sourceRepositoryStorage.repositoryURL(provenance)
                let referenceDatabaseURL = try referenceDatabaseURL(repositoryURL: repositoryURL)
                try prepareReferenceDirectory(for: referenceDatabaseURL)
                try ensureReferenceDatabaseIgnored(in: repositoryURL)
                return try stagedImport(at: referenceDatabaseURL)
            },
            existing: { provenance in
                @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage
                @Dependency(\.sourceReferenceDatabaseMigrator) var migrator
                let referenceDatabaseURL = try referenceDatabaseURL(
                    repositoryURL: sourceRepositoryStorage.repositoryURL(provenance)
                )
                guard FileManager.default.fileExists(atPath: referenceDatabaseURL.path) else {
                    return nil
                }
                let database = try defaultBaselineDatabase(path: referenceDatabaseURL.path)
                try migrator.migrate(database)
                return database
            }
        )
    }

    static func referenceDatabaseURL(repositoryURL: URL) throws -> URL {
        repositoryURL
            .standardizedFileURL
            .appending(path: ".ome", directoryHint: .isDirectory)
            .appending(path: "reference.sqlite")
    }

    static func prepareReferenceDirectory(for referenceDatabaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: referenceDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    static func stagedImport(
        at referenceDatabaseURL: URL
    ) throws -> StagedSourceReferenceDatabase {
        @Dependency(\.sourceReferenceDatabaseMigrator) var migrator
        try prepareReferenceDirectory(for: referenceDatabaseURL)

        let stagingDirectoryURL = FileManager.default.temporaryDirectory
            .appending(
                path: "open-music-event-source-reference-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        do {
            try FileManager.default.createDirectory(
                at: stagingDirectoryURL,
                withIntermediateDirectories: true
            )
            let stagingDatabaseURL = stagingDirectoryURL
                .appending(path: referenceDatabaseURL.lastPathComponent)
            let stagingDatabase = try defaultBaselineDatabase(
                path: stagingDatabaseURL.path
            )
            try migrator.migrate(stagingDatabase)
            return StagedSourceReferenceDatabase(
                database: stagingDatabase,
                databaseFileName: referenceDatabaseURL.lastPathComponent,
                commit: {
                    let referenceDatabase = try defaultBaselineDatabase(
                        path: referenceDatabaseURL.path
                    )
                    try migrator.migrate(referenceDatabase)
                    try stagingDatabase.database.backup(to: referenceDatabase.database)
                },
                discard: {
                    do {
                        try FileManager.default.removeItem(at: stagingDirectoryURL)
                    } catch {
                        guard error.isMissingFile else { throw error }
                    }
                }
            )
        } catch {
            try? FileManager.default.removeItem(at: stagingDirectoryURL)
            throw error
        }
    }

    static func ensureReferenceDatabaseIgnored(in repositoryURL: URL) throws {
        let gitignoreURL = repositoryURL
            .standardizedFileURL
            .appending(path: ".gitignore")
        let entry = gitignoreEntry
        let existingContents = (try? String(contentsOf: gitignoreURL, encoding: .utf8)) ?? ""
        let existingLines = existingContents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard !existingLines.contains(entry) else { return }

        var contents = existingContents
        if !contents.isEmpty, !contents.hasSuffix("\n") {
            contents.append("\n")
        }
        contents.append(entry)
        contents.append("\n")
        try contents.write(to: gitignoreURL, atomically: true, encoding: .utf8)
    }

    static func removeSQLiteDatabase(at databaseURL: URL) throws {
        let fileManager = FileManager.default
        for url in [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-shm"),
            URL(fileURLWithPath: databaseURL.path + "-wal"),
        ] {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                guard error.isMissingFile else { throw error }
            }
        }
    }
}

public extension WorkspaceReferenceDatabaseClient {
    static let localReferenceDirectoryName = "WorkspaceReferences"

    static var live: Self {
        fileBacked()
    }

    static func fileBacked(localReferenceDirectory: URL? = nil) -> Self {
        Self(
            url: { workspace, resolvedSourceBaseline in
                switch workspace.kind {
                case .local:
                    return try localReferenceDatabaseURL(
                        directory: localReferenceDirectory,
                        workspace: workspace
                    )

                case .team:
                    let sourceBaseline = try sourceBaseline(
                        for: workspace,
                        resolvedSourceBaseline: resolvedSourceBaseline
                    )
                    @Dependency(\.sourceReferenceDatabase) var sourceReferenceDatabase
                    return try sourceReferenceDatabase.url(sourceBaseline.sourceProvenance)
                }
            },
            prepare: { workspace, resolvedSourceBaseline in
                switch workspace.kind {
                case .local:
                    @Dependency(\.sourceReferenceDatabaseMigrator) var migrator
                    let referenceDatabaseURL = try localReferenceDatabaseURL(
                        directory: localReferenceDirectory,
                        workspace: workspace
                    )
                    try SourceReferenceDatabaseClient.prepareReferenceDirectory(
                        for: referenceDatabaseURL
                    )
                    try SourceReferenceDatabaseClient.removeSQLiteDatabase(at: referenceDatabaseURL)
                    let database = try defaultBaselineDatabase(path: referenceDatabaseURL.path)
                    try migrator.migrate(database)
                    return database

                case .team:
                    guard let database = try existingTeamReferenceDatabase(
                        workspace: workspace,
                        resolvedSourceBaseline: resolvedSourceBaseline
                    )
                    else {
                        throw WorkspaceReferenceDatabaseError.sourceBaselineMissing(workspace.id)
                    }
                    return database
                }
            },
            existing: { workspace, resolvedSourceBaseline in
                switch workspace.kind {
                case .local:
                    @Dependency(\.sourceReferenceDatabaseMigrator) var migrator
                    let referenceDatabaseURL = try localReferenceDatabaseURL(
                        directory: localReferenceDirectory,
                        workspace: workspace
                    )
                    guard FileManager.default.fileExists(atPath: referenceDatabaseURL.path) else {
                        return nil
                    }
                    let database = try defaultBaselineDatabase(path: referenceDatabaseURL.path)
                    try migrator.migrate(database)
                    return database

                case .team:
                    return try existingTeamReferenceDatabase(
                        workspace: workspace,
                        resolvedSourceBaseline: resolvedSourceBaseline
                    )
                }
            }
        )
    }

    private static func existingTeamReferenceDatabase(
        workspace: EditingWorkspaceRecord,
        resolvedSourceBaseline: SourceBaselineRecord?
    ) throws -> SourceBaselineDatabase? {
        let sourceBaseline = try sourceBaseline(
            for: workspace,
            resolvedSourceBaseline: resolvedSourceBaseline
        )
        @Dependency(\.sourceReferenceDatabase) var sourceReferenceDatabase
        guard let referenceDatabase = try sourceReferenceDatabase.existing(
            sourceBaseline.sourceProvenance
        ) else {
            return nil
        }
        let containsExpectedBaseline = try referenceDatabase.read { db in
            try SourceBaselineRecord
                .where { $0.id.eq(sourceBaseline.id) }
                .fetchCount(db) == 1
        }
        return containsExpectedBaseline ? referenceDatabase : nil
    }

    private static func localReferenceDatabaseURL(
        directory: URL?,
        workspace: EditingWorkspaceRecord
    ) throws -> URL {
        let directory = try directory ?? defaultLocalReferenceDirectory()
        return directory
            .standardizedFileURL
            .appending(path: workspace.referenceDatabaseFileName)
    }

    private static func defaultLocalReferenceDirectory() throws -> URL {
        try FileManager.default
            .url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appending(path: localReferenceDirectoryName, directoryHint: .isDirectory)
    }

    private static func sourceBaseline(
        for workspace: EditingWorkspaceRecord,
        resolvedSourceBaseline: SourceBaselineRecord?
    ) throws -> SourceBaselineRecord {
        guard let sourceBaselineID = workspace.sourceBaselineID else {
            throw WorkspaceReferenceDatabaseError.teamWorkspaceMissingSourceBaseline(workspace.id)
        }
        if let resolvedSourceBaseline {
            guard resolvedSourceBaseline.id == sourceBaselineID else {
                throw WorkspaceReferenceDatabaseError.sourceBaselineMissing(workspace.id)
            }
            return resolvedSourceBaseline
        }

        @Dependency(\.defaultDatabase) var database
        let sourceBaseline = try database.read { db in
            try SourceBaselineRecord
                .where { $0.id.eq(sourceBaselineID) }
                .fetchOne(db)
        }
        guard let sourceBaseline else {
            throw WorkspaceReferenceDatabaseError.sourceBaselineMissing(workspace.id)
        }
        return sourceBaseline
    }
}

public extension EventSourceProvenanceRecord {
    var sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance {
        OME.SourceDatabaseInsertion.SourceProvenance(
            kind: sourceKind,
            reference: sourceReference,
            ref: ref
        )
    }
}

public extension SourceBaselineRecord {
    var sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance {
        OME.SourceDatabaseInsertion.SourceProvenance(
            kind: sourceKind,
            reference: sourceReference,
            ref: ref
        )
    }
}

public extension DependencyValues {
    var sourceReferenceDatabase: SourceReferenceDatabaseClient {
        get { self[SourceReferenceDatabaseClientKey.self] }
        set { self[SourceReferenceDatabaseClientKey.self] = newValue }
    }

    var sourceReferenceDatabaseMigrator: SourceReferenceDatabaseMigrator {
        get { self[SourceReferenceDatabaseMigratorKey.self] }
        set { self[SourceReferenceDatabaseMigratorKey.self] = newValue }
    }

    var workspaceReferenceDatabase: WorkspaceReferenceDatabaseClient {
        get { self[WorkspaceReferenceDatabaseClientKey.self] }
        set { self[WorkspaceReferenceDatabaseClientKey.self] = newValue }
    }
}

private enum SourceReferenceDatabaseClientKey: DependencyKey {
    static var liveValue: SourceReferenceDatabaseClient {
        .live
    }

    static var testValue: SourceReferenceDatabaseClient {
        .live
    }
}

private enum SourceReferenceDatabaseMigratorKey: DependencyKey {
    static let liveValue = SourceReferenceDatabaseMigrator.noop
    static let testValue = SourceReferenceDatabaseMigrator.noop
}

private enum WorkspaceReferenceDatabaseClientKey: DependencyKey {
    static var liveValue: WorkspaceReferenceDatabaseClient {
        .live
    }

    static var testValue: WorkspaceReferenceDatabaseClient {
        .live
    }
}

private extension Error {
    var isMissingFile: Bool {
        let error = self as NSError
        if error.domain == NSCocoaErrorDomain,
           error.code == NSFileNoSuchFileError {
            return true
        }
        if error.domain == NSPOSIXErrorDomain,
           error.code == Int(ENOENT) {
            return true
        }
        return false
    }
}
