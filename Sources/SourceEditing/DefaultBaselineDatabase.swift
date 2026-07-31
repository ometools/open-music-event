import Dependencies
import Foundation
import SQLiteData

public enum SourceBaselineDatabaseAttachmentError: Error, Equatable, Sendable {
    case activeTransaction
}

public struct SourceBaselineDatabase: Sendable {
    public var path: String
    public var database: any DatabaseWriter

    public init(
        path: String,
        database: any DatabaseWriter
    ) {
        self.path = path
        self.database = database
    }

    public func read<Value>(
        _ value: (Database) throws -> Value
    ) throws -> Value {
        try database.read(value)
    }

    public func write<Value>(
        _ updates: (Database) throws -> Value
    ) throws -> Value {
        try database.write(updates)
    }

    /// Reference databases are snapshots. They may be updated only by controlled import/refresh
    /// and must be attached read-only for application comparisons. They must never become
    /// `defaultDatabase`.
    public func withAttached<Value>(
        to db: Database,
        operation: (String) throws -> Value
    ) throws -> Value {
        try Self.withAttached(path: path, to: db, operation: operation)
    }

    public static func withAttached<Value>(
        path: String,
        to db: Database,
        operation: (String) throws -> Value
    ) throws -> Value {
        // SQLite cannot detach a database while a transaction is active. Keeping the entire
        // attachment scope in autocommit also ensures that an inner mutation transaction can
        // finish before the reference is detached.
        guard !db.isInsideTransaction else {
            throw SourceBaselineDatabaseAttachmentError.activeTransaction
        }
        let schemaName = "source_baseline_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
        let databaseURI = readOnlyDatabaseURI(path: path)

        try #sql(
            "ATTACH DATABASE \(bind: databaseURI) AS \(quote: schemaName)"
        )
        .execute(db)
        db.clearSchemaCache()

        let result = Result { try operation(schemaName) }
        // Queries against an attached schema can remain in GRDB's statement cache after their
        // values have been fetched. Clearing that cache is required before SQLite can detach the
        // schema, including when the operation itself failed.
        db.clearSchemaCache()
        try #sql("DETACH DATABASE \(quote: schemaName)").execute(db)
        db.clearSchemaCache()
        return try result.get()
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

public func defaultBaselineDatabase(
    path: String? = nil,
    configuration: Configuration = Configuration()
) throws -> SourceBaselineDatabase {
    @Dependency(\.context) var context

    let path = try path ?? {
        switch context {
        case .live:
            let applicationSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            try FileManager.default.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
            return applicationSupportURL
                .appendingPathComponent("SourceEditingBaseline.sqlite")
                .path

        case .preview, .test:
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("SourceEditingBaseline-\(UUID().uuidString)")
                .appendingPathExtension("sqlite")
                .path
        }
    }()

    return SourceBaselineDatabase(
        path: path,
        database: try DatabasePool(path: path, configuration: configuration)
    )
}

public extension DependencyValues {
    var defaultBaselineDatabase: SourceBaselineDatabase {
        get { self[DefaultBaselineDatabaseKey.self] }
        set { self[DefaultBaselineDatabaseKey.self] = newValue }
    }
}

private enum DefaultBaselineDatabaseKey: DependencyKey {
    static var liveValue: SourceBaselineDatabase {
        try! defaultBaselineDatabase()
    }

    static var testValue: SourceBaselineDatabase {
        try! defaultBaselineDatabase()
    }
}
