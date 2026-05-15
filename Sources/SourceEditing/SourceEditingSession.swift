import Dependencies
import Foundation
import SQLiteData

public struct SourceEditingSession: Sendable {
    public var workingDatabasePath: String
    public var baselineDatabasePath: String
    public var baselineSchemaName: String
    public var database: any DatabaseWriter

    public init(
        workingDatabasePath: String,
        baselineDatabasePath: String,
        baselineSchemaName: String = "source_baseline",
        configuration: Configuration = Configuration()
    ) throws {
        var configuration = configuration
        configuration.prepareDatabase { db in
            try #sql(
                "ATTACH DATABASE \(bind: baselineDatabasePath) AS \(quote: baselineSchemaName)"
            )
            .execute(db)
        }

        self.workingDatabasePath = workingDatabasePath
        self.baselineDatabasePath = baselineDatabasePath
        self.baselineSchemaName = baselineSchemaName
        self.database = try DatabasePool(path: workingDatabasePath, configuration: configuration)
    }
}

public extension DependencyValues {
    var sourceEditingSession: SourceEditingSession? {
        get { self[SourceEditingSessionKey.self] }
        set { self[SourceEditingSessionKey.self] = newValue }
    }

    var sourceEditingWorkingDatabasePath: String? {
        get { self[SourceEditingWorkingDatabasePathKey.self] }
        set { self[SourceEditingWorkingDatabasePathKey.self] = newValue }
    }
}

private enum SourceEditingSessionKey: DependencyKey {
    static let liveValue: SourceEditingSession? = nil
    static let testValue: SourceEditingSession? = nil
}

private enum SourceEditingWorkingDatabasePathKey: DependencyKey {
    static let liveValue: String? = nil
    static let testValue: String? = nil
}
