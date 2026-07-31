import Dependencies
import Foundation
import GRDB
import SQLiteData

public struct SourceEditingSession: Sendable {
    public static let baselineSchemaName = "source_baseline"

    public var workingDatabasePath: String
    public var baselineDatabasePath: String
    public var database: any DatabaseWriter

    public init(
        workingDatabasePath: String,
        baselineDatabasePath: String,
        configuration: Configuration = Configuration()
    ) throws {
        var configuration = configuration
        let baselineDatabaseURI = readOnlyDatabaseURI(path: baselineDatabasePath)
        configuration.prepareDatabase { db in
            try #sql(
                "ATTACH DATABASE \(bind: baselineDatabaseURI) AS \(quote: Self.baselineSchemaName)"
            )
            .execute(db)
        }

        self.workingDatabasePath = workingDatabasePath
        self.baselineDatabasePath = baselineDatabasePath
        self.database = try DatabasePool(path: workingDatabasePath, configuration: configuration)
    }

    public static func attachedBaselineSchemaName(
        in db: Database
    ) throws -> String? {
        try attachedDatabasePath(schemaName: baselineSchemaName, in: db)
            .map { _ in baselineSchemaName }
    }
}

private func readOnlyDatabaseURI(path: String) -> String {
    var components = URLComponents()
    components.scheme = "file"
    components.path = path
    components.queryItems = [
        URLQueryItem(name: "mode", value: "ro")
    ]
    return components.string ?? "file:\(path)?mode=ro"
}

private func attachedDatabasePath(
    schemaName: String,
    in db: Database
) throws -> String? {
    try Row
        .fetchAll(db, sql: "PRAGMA database_list")
        .first { row in
            row["name"] == schemaName
        }
        .map { row in
            row["file"]
        }
}

public extension DependencyValues {
    var sourceEditingWorkingDatabasePath: String? {
        get { self[SourceEditingWorkingDatabasePathKey.self] }
        set { self[SourceEditingWorkingDatabasePathKey.self] = newValue }
    }
}

private enum SourceEditingWorkingDatabasePathKey: DependencyKey {
    static let liveValue: String? = nil
    static let testValue: String? = nil
}
