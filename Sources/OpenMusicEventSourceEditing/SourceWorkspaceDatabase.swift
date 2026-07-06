import Dependencies
import Foundation
import OpenMusicEventLexicon
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

public enum SourceWorkspaceDatabaseError: Equatable, Error, Sendable {
    case referenceDatabaseMissing(SourceBaselineRecord.ID)
    case sourceBaselineNotFound(SourceBaselineRecord.ID)
    case workingDatabasePathMissing
}

public struct SourceWorkspaceDatabaseClient: Sendable {
    public var event: @Sendable (OME.Event.ID) throws -> SourceWorkspaceDatabase?
    public var sourceBaseline: @Sendable (SourceBaselineRecord.ID) throws -> SourceWorkspaceDatabase

    public init(
        event: @escaping @Sendable (OME.Event.ID) throws -> SourceWorkspaceDatabase?,
        sourceBaseline: @escaping @Sendable (SourceBaselineRecord.ID) throws -> SourceWorkspaceDatabase
    ) {
        self.event = event
        self.sourceBaseline = sourceBaseline
    }
}

public extension SourceWorkspaceDatabaseClient {
    static var live: Self {
        Self(
            event: { eventID in
                @Dependency(\.defaultDatabase) var database

                let sourceBaselineID = try database.read { db in
                    try EventSourceProvenanceRecord
                        .where { $0.id.eq(eventID) }
                        .fetchOne(db)?
                        .sourceBaselineID
                }
                guard let sourceBaselineID else { return nil }
                return try Self.sourceBaselineWorkspace(sourceBaselineID)
            },
            sourceBaseline: { sourceBaselineID in
                try Self.sourceBaselineWorkspace(sourceBaselineID)
            }
        )
    }

    static var passthrough: Self {
        Self(
            event: { _ in nil },
            sourceBaseline: { _ in
                @Dependency(\.defaultDatabase) var database
                return SourceWorkspaceDatabase(database: database)
            }
        )
    }

    private static func sourceBaselineWorkspace(
        _ sourceBaselineID: SourceBaselineRecord.ID
    ) throws -> SourceWorkspaceDatabase {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.sourceEditingWorkingDatabasePath) var workingDatabasePath
        @Dependency(\.sourceReferenceDatabase) var sourceReferenceDatabase

        guard let workingDatabasePath else {
            throw SourceWorkspaceDatabaseError.workingDatabasePathMissing
        }

        let sourceBaseline = try database.read { db in
            try SourceBaselineRecord
                .where { $0.id.eq(sourceBaselineID) }
                .fetchOne(db)
        }
        guard let sourceBaseline else {
            throw SourceWorkspaceDatabaseError.sourceBaselineNotFound(sourceBaselineID)
        }

        guard let baselineDatabase = try sourceReferenceDatabase.existing(
            sourceBaseline.sourceProvenance
        ) else {
            throw SourceWorkspaceDatabaseError.referenceDatabaseMissing(sourceBaselineID)
        }

        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.foreignKeysEnabled = true

        return SourceWorkspaceDatabase(
            sourceEditingSession: try SourceEditingSession(
                workingDatabasePath: workingDatabasePath,
                baselineDatabasePath: baselineDatabase.path,
                configuration: configuration
            )
        )
    }
}

public extension DependencyValues {
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
}

private enum SourceWorkspaceDatabaseClientKey: DependencyKey {
    static var liveValue: SourceWorkspaceDatabaseClient {
        .live
    }

    static var testValue: SourceWorkspaceDatabaseClient {
        .passthrough
    }
}
