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

public struct WorkspaceContext: Sendable {
    public var id: EditingWorkspaceRecord.ID
    public var sourceWorkspaceDatabase: SourceWorkspaceDatabase
    @SharedReader public var grant: AuthoringGrant?

    public init(
        id: EditingWorkspaceRecord.ID,
        sourceWorkspaceDatabase: SourceWorkspaceDatabase,
        grant: SharedReader<AuthoringGrant?> = SharedReader(value: nil)
    ) {
        if let grantedWorkspaceID = grant.wrappedValue?.workspace.id {
            precondition(
                grantedWorkspaceID == id,
                "An authoring grant cannot be mounted into a different workspace."
            )
        }
        self.id = id
        self.sourceWorkspaceDatabase = sourceWorkspaceDatabase
        self._grant = grant
    }

    public var database: any DatabaseWriter {
        sourceWorkspaceDatabase.database
    }

    public var sourceEditingSession: SourceEditingSession? {
        sourceWorkspaceDatabase.sourceEditingSession
    }

    public var access: AuthoringAccess {
        grant?.access ?? .attendee
    }

    public var canEditContent: Bool {
        access.canEditContent
    }

    public var canManageWorkspace: Bool {
        access.canManageWorkspace
    }

    public func mounting(grant: SharedReader<AuthoringGrant?>) -> Self {
        Self(
            id: id,
            sourceWorkspaceDatabase: sourceWorkspaceDatabase,
            grant: grant
        )
    }
}

public enum SourceWorkspaceDatabaseError: Equatable, Error, Sendable {
    case invalidWorkspaceDatabaseFileName(EditingWorkspaceRecord.ID)
    case sourceBaselineNotFound(SourceBaselineRecord.ID)
    case workspaceReferenceDatabaseMissing(EditingWorkspaceRecord.ID)
    case workspaceNotFound(EditingWorkspaceRecord.ID)
}

public struct SourceWorkspaceDatabaseClient: Sendable {
    public var workspace: @Sendable (EditingWorkspaceRecord.ID) throws -> SourceWorkspaceDatabase

    public init(
        workspace: @escaping @Sendable (EditingWorkspaceRecord.ID) throws -> SourceWorkspaceDatabase
    ) {
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
            workspace: { workspaceID in
                try Self.workspaceDatabase(
                    workspaceID,
                    workingDirectory: workingDirectory
                )
            }
        )
    }

    static var passthrough: Self {
        Self(
            workspace: { _ in
                @Dependency(\.defaultDatabase) var database
                return SourceWorkspaceDatabase(database: database)
            }
        )
    }

    private static func workspaceDatabase(
        _ workspaceID: EditingWorkspaceRecord.ID,
        workingDirectory: URL?
    ) throws -> SourceWorkspaceDatabase {
        @Dependency(\.defaultDatabase) var database
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

        guard let referenceDatabase else {
            return SourceWorkspaceDatabase(
                database: try DatabasePool(
                    path: workingDatabaseURL.path,
                    configuration: configuration
                )
            )
        }

        return SourceWorkspaceDatabase(
            sourceEditingSession: try SourceEditingSession(
                workingDatabasePath: workingDatabaseURL.path,
                baselineDatabasePath: referenceDatabase.path,
                baselineSchemaName: sourceBaselineSchemaName(),
                configuration: configuration
            )
        )
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

    private static func sourceBaselineSchemaName() -> String {
        "source_baseline_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
    }
}

private enum WorkspaceContextKey: DependencyKey {
    static var liveValue: WorkspaceContext? { nil }
    static var testValue: WorkspaceContext? { nil }
}

public extension DependencyValues {
    var workspaceContext: WorkspaceContext? {
        get { self[WorkspaceContextKey.self] }
        set { self[WorkspaceContextKey.self] = newValue }
    }

    var sourceWorkspaceDatabase: SourceWorkspaceDatabaseClient {
        get { self[SourceWorkspaceDatabaseClientKey.self] }
        set { self[SourceWorkspaceDatabaseClientKey.self] = newValue }
    }

    mutating func useSourceWorkspaceDatabase(
        _ sourceWorkspaceDatabase: SourceWorkspaceDatabase
    ) {
        defaultDatabase = sourceWorkspaceDatabase.database
        sourceEditingSession = sourceWorkspaceDatabase.sourceEditingSession
    }

    mutating func useWorkspaceContext(
        _ workspaceContext: WorkspaceContext
    ) {
        // EventViewer keeps the app database as its read/write authority. The source
        // session attaches the workspace reference database to that connection on demand.
        self.sourceEditingSession = workspaceContext.sourceEditingSession
        self.workspaceContext = workspaceContext
    }
}

private enum SourceWorkspaceDatabaseClientKey: DependencyKey {
    static var liveValue: SourceWorkspaceDatabaseClient {
        .live
    }

    static var testValue: SourceWorkspaceDatabaseClient {
        .passthrough
    }
}
