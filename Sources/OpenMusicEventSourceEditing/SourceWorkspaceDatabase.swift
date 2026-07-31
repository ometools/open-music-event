import Dependencies
import Foundation
import OpenMusicEventLexicon
import Sharing
import SQLiteData
import SourceEditing

public struct SourceWorkspaceDatabase: Sendable {
    public var database: any DatabaseWriter
    public var sourceEditingSession: SourceEditingSession?

    public init(
        database: any DatabaseWriter,
        sourceEditingSession: SourceEditingSession? = nil
    ) {
        self.database = database
        self.sourceEditingSession = sourceEditingSession
    }

    public init(sourceEditingSession: SourceEditingSession) {
        self.init(
            database: sourceEditingSession.database,
            sourceEditingSession: sourceEditingSession
        )
    }
}

public struct EditingWorkspace: Sendable {
    public var id: EditingWorkspaceRecord.ID
    public var sourceWorkspaceDatabase: SourceWorkspaceDatabase

    public init(
        id: EditingWorkspaceRecord.ID,
        sourceWorkspaceDatabase: SourceWorkspaceDatabase
    ) {
        self.id = id
        self.sourceWorkspaceDatabase = sourceWorkspaceDatabase
    }

    public var database: any DatabaseWriter {
        sourceWorkspaceDatabase.database
    }

    public var sourceEditingSession: SourceEditingSession? {
        sourceWorkspaceDatabase.sourceEditingSession
    }
}

public struct SourceWorkspaceDatabasePreparationClient: Sendable {
    public var prepare: @Sendable (any DatabaseWriter) throws -> Void

    public init(
        prepare: @escaping @Sendable (any DatabaseWriter) throws -> Void
    ) {
        self.prepare = prepare
    }

    public static var noop: Self {
        Self(prepare: { _ in })
    }
}

public enum SourceWorkspaceDatabaseError: Equatable, Error, Sendable {
    case invalidWorkspaceDatabaseFileName(EditingWorkspaceRecord.ID)
    case sourceBaselineNotFound(SourceBaselineRecord.ID)
    case workspaceReferenceDatabaseMissing(EditingWorkspaceRecord.ID)
    case workspaceNotFound(EditingWorkspaceRecord.ID)
}

public struct SourceWorkspaceDatabaseClient: Sendable {
    public var existingWorkspace: @Sendable (
        EditingWorkspaceRecord.ID
    ) throws -> SourceWorkspaceDatabase?
    public var workspace: @Sendable (EditingWorkspaceRecord.ID) throws -> SourceWorkspaceDatabase

    public init(
        existingWorkspace: @escaping @Sendable (
            EditingWorkspaceRecord.ID
        ) throws -> SourceWorkspaceDatabase? = { _ in nil },
        workspace: @escaping @Sendable (EditingWorkspaceRecord.ID) throws -> SourceWorkspaceDatabase
    ) {
        self.existingWorkspace = existingWorkspace
        self.workspace = workspace
    }
}

public extension SourceWorkspaceDatabaseClient {
    static var live: Self {
        fileBacked()
    }

    static func fileBacked(
        workingDirectory: URL? = nil
    ) -> Self {
        Self(
            existingWorkspace: { workspaceID in
                try Self.workspaceDatabase(
                    workspaceID,
                    workingDirectory: workingDirectory,
                    createIfNeeded: false
                )
            },
            workspace: { workspaceID in
                guard let workspaceDatabase = try Self.workspaceDatabase(
                    workspaceID,
                    workingDirectory: workingDirectory,
                    createIfNeeded: true
                ) else {
                    throw SourceWorkspaceDatabaseError.workspaceNotFound(workspaceID)
                }
                return workspaceDatabase
            }
        )
    }

    static var passthrough: Self {
        Self(
            existingWorkspace: { _ in
                @Dependency(\.defaultDatabase) var database
                return SourceWorkspaceDatabase(database: database)
            },
            workspace: { _ in
                @Dependency(\.defaultDatabase) var database
                return SourceWorkspaceDatabase(database: database)
            }
        )
    }

    private static func workspaceDatabase(
        _ workspaceID: EditingWorkspaceRecord.ID,
        workingDirectory: URL?,
        createIfNeeded: Bool
    ) throws -> SourceWorkspaceDatabase? {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.sourceWorkspaceDatabasePreparation) var preparation
        @Dependency(\.workspaceReferenceDatabase) var workspaceReferenceDatabase

        let (workspace, sourceBaseline) = try database.read { db in
            let workspace = try EditingWorkspaceRecord
                .where { $0.id.eq(workspaceID) }
                .fetchOne(db)
            let sourceBaseline = try workspace?.sourceBaselineID.flatMap { sourceBaselineID in
                try SourceBaselineRecord
                    .where { $0.id.eq(sourceBaselineID) }
                    .fetchOne(db)
            }
            return (workspace, sourceBaseline)
        }
        guard let workspace else {
            throw SourceWorkspaceDatabaseError.workspaceNotFound(workspaceID)
        }
        if let sourceBaselineID = workspace.sourceBaselineID,
           sourceBaseline == nil {
            throw SourceWorkspaceDatabaseError.sourceBaselineNotFound(sourceBaselineID)
        }
        let workingDatabaseURL = try workingDatabaseURL(
            workspace: workspace,
            directory: workingDirectory
        )
        let workingDatabaseExists = FileManager.default.fileExists(
            atPath: workingDatabaseURL.path
        )
        guard workingDatabaseExists || createIfNeeded else {
            return nil
        }
        let referenceDatabase = try workspaceReferenceDatabase.existing(
            workspace,
            sourceBaseline: sourceBaseline
        )
        guard workingDatabaseExists || referenceDatabase != nil else {
            throw SourceWorkspaceDatabaseError.workspaceReferenceDatabaseMissing(workspaceID)
        }

        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.foreignKeysEnabled = true

        if !workingDatabaseExists, let referenceDatabase {
            try FileManager.default.createDirectory(
                at: workingDatabaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let workingDatabase = try DatabasePool(path: workingDatabaseURL.path)
            try referenceDatabase.database.backup(to: workingDatabase)
        }

        let workspaceDatabase: SourceWorkspaceDatabase
        if let referenceDatabase {
            workspaceDatabase = SourceWorkspaceDatabase(
                sourceEditingSession: try SourceEditingSession(
                    workingDatabasePath: workingDatabaseURL.path,
                    baselineDatabasePath: referenceDatabase.path,
                    configuration: configuration
                )
            )
        } else {
            workspaceDatabase = SourceWorkspaceDatabase(
                database: try DatabasePool(
                    path: workingDatabaseURL.path,
                    configuration: configuration
                )
            )
        }
        try preparation.prepare(workspaceDatabase.database)
        return workspaceDatabase
    }

    private static func workingDatabaseURL(
        workspace: EditingWorkspaceRecord,
        directory: URL?
    ) throws -> URL {
        let fileName = URL(fileURLWithPath: workspace.databaseFileName).lastPathComponent
        guard !fileName.isEmpty, fileName != "." else {
            throw SourceWorkspaceDatabaseError.invalidWorkspaceDatabaseFileName(workspace.id)
        }
        let directory = try directory ?? FileManager.default
            .url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appending(path: "EditingWorkspaces", directoryHint: .isDirectory)
        return directory
            .standardizedFileURL
            .appending(path: fileName)
    }
}

private enum AuthoringGrantReaderKey: DependencyKey {
    static var liveValue: SharedReader<AuthoringGrant?> {
        SharedReader(value: nil)
    }

    static var testValue: SharedReader<AuthoringGrant?> {
        SharedReader(value: nil)
    }
}

private enum EditingWorkspaceIDKey: DependencyKey {
    static var liveValue: EditingWorkspaceRecord.ID? { nil }
    static var testValue: EditingWorkspaceRecord.ID? { nil }
}

public extension DependencyValues {
    var authoringGrant: SharedReader<AuthoringGrant?> {
        get { self[AuthoringGrantReaderKey.self] }
        set { self[AuthoringGrantReaderKey.self] = newValue }
    }

    var editingWorkspaceID: EditingWorkspaceRecord.ID? {
        get { self[EditingWorkspaceIDKey.self] }
        set { self[EditingWorkspaceIDKey.self] = newValue }
    }

    var sourceWorkspaceDatabase: SourceWorkspaceDatabaseClient {
        get { self[SourceWorkspaceDatabaseClientKey.self] }
        set { self[SourceWorkspaceDatabaseClientKey.self] = newValue }
    }

    var sourceWorkspaceDatabasePreparation: SourceWorkspaceDatabasePreparationClient {
        get { self[SourceWorkspaceDatabasePreparationClientKey.self] }
        set { self[SourceWorkspaceDatabasePreparationClientKey.self] = newValue }
    }

    mutating func mount(
        _ workspace: EditingWorkspace,
        grant: SharedReader<AuthoringGrant?>
    ) {
        if let grantedWorkspaceID = grant.wrappedValue?.workspace.id {
            precondition(
                grantedWorkspaceID == workspace.id,
                "An authoring grant cannot be mounted into a different workspace."
            )
        }
        authoringGrant = grant
        defaultDatabase = workspace.database
        editingWorkspaceID = workspace.id
    }
}

private enum SourceWorkspaceDatabasePreparationClientKey: DependencyKey {
    static var liveValue: SourceWorkspaceDatabasePreparationClient { .noop }
    static var testValue: SourceWorkspaceDatabasePreparationClient { .noop }
}

private enum SourceWorkspaceDatabaseClientKey: DependencyKey {
    static var liveValue: SourceWorkspaceDatabaseClient {
        .live
    }

    static var testValue: SourceWorkspaceDatabaseClient {
        .passthrough
    }
}
