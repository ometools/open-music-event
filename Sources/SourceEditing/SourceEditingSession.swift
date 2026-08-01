import Foundation
import GRDB
import SQLiteData

public enum SourceEditingSessionError: Error, Equatable, Sendable {
    case baselineDatabaseMismatch(attachedPath: String, requestedPath: String)
}

public struct SourceEditingSession: Sendable {
    public static let baselineSchemaName = "source_baseline"

    public var mainDatabasePath: String
    public var baselineDatabasePath: String
    public var database: any DatabaseWriter

    public init(
        mainDatabase: any DatabaseWriter,
        baselineDatabasePath: String
    ) throws {
        let mainDatabasePath = mainDatabase.path
        let attachedBaselineDatabasePath = try mainDatabase.read { db in
            try attachedDatabasePath(schemaName: Self.baselineSchemaName, in: db)
        }
        if let attachedBaselineDatabasePath {
            guard databasePathsMatch(
                attachedBaselineDatabasePath,
                baselineDatabasePath
            ) else {
                throw SourceEditingSessionError.baselineDatabaseMismatch(
                    attachedPath: attachedBaselineDatabasePath,
                    requestedPath: baselineDatabasePath
                )
            }

            self.mainDatabasePath = mainDatabasePath
            self.baselineDatabasePath = baselineDatabasePath
            self.database = mainDatabase
            return
        }

        var configuration = mainDatabase.configuration
        configuration.label = "OpenMusicEvent.SourceEditingSession"
        let baselineDatabaseURI = readOnlyDatabaseURI(path: baselineDatabasePath)
        configuration.prepareDatabase { db in
            try #sql(
                "ATTACH DATABASE \(bind: baselineDatabaseURI) AS \(quote: Self.baselineSchemaName)"
            )
            .execute(db)
        }

        self.mainDatabasePath = mainDatabasePath
        self.baselineDatabasePath = baselineDatabasePath
        self.database = try DatabasePool(
            path: mainDatabasePath,
            configuration: configuration
        )
    }

    public static func attachedBaselineSchemaName(
        in db: Database
    ) throws -> String? {
        try attachedDatabasePath(schemaName: baselineSchemaName, in: db)
            .map { _ in baselineSchemaName }
    }
}

private func databasePathsMatch(_ lhs: String, _ rhs: String) -> Bool {
    URL(fileURLWithPath: lhs).standardizedFileURL
        == URL(fileURLWithPath: rhs).standardizedFileURL
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
