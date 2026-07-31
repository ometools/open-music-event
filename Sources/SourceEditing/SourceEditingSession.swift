import Dependencies
import Foundation
import GRDB
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
        let baselineDatabaseURI = readOnlyDatabaseURI(path: baselineDatabasePath)
        configuration.prepareDatabase { db in
            try #sql(
                "ATTACH DATABASE \(bind: baselineDatabaseURI) AS \(quote: baselineSchemaName)"
            )
            .execute(db)
        }

        self.workingDatabasePath = workingDatabasePath
        self.baselineDatabasePath = baselineDatabasePath
        self.baselineSchemaName = baselineSchemaName
        self.database = try DatabasePool(path: workingDatabasePath, configuration: configuration)
    }

    public func withAttachedBaseline<Value>(
        to db: Database,
        operation: (String) throws -> Value
    ) throws -> Value {
        let baselineDatabaseURI = readOnlyDatabaseURI(path: baselineDatabasePath)
        let attachedDatabasePath = try attachedDatabasePath(
            schemaName: baselineSchemaName,
            in: db
        )
        if let attachedDatabasePath {
            if databasePath(attachedDatabasePath, matches: baselineDatabasePath) {
                return try operation(baselineSchemaName)
            }
            try #sql("DETACH DATABASE \(quote: baselineSchemaName)").execute(db)
        }

        try #sql(
            "ATTACH DATABASE \(bind: baselineDatabaseURI) AS \(quote: baselineSchemaName)"
        )
        .execute(db)
        defer {
            try? #sql("DETACH DATABASE \(quote: baselineSchemaName)").execute(db)
        }

        return try operation(baselineSchemaName)
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

private func databasePath(_ lhs: String, matches rhs: String) -> Bool {
    normalizedDatabasePath(lhs) == normalizedDatabasePath(rhs)
}

private func normalizedDatabasePath(_ path: String) -> String {
    if let components = URLComponents(string: path),
       components.scheme == "file"
    {
        return URL(fileURLWithPath: components.path).standardizedFileURL.path
    }
    return URL(fileURLWithPath: path).standardizedFileURL.path
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
