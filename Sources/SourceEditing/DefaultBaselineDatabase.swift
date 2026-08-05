import Dependencies
import Foundation
import SQLiteData

/// Storage for a reference snapshot during controlled import and refresh operations.
///
/// Editable features use the application's `defaultDatabase` and pass this snapshot explicitly to
/// comparison operations. This database must never become `defaultDatabase`.
public struct SourceBaselineDatabase: Hashable, Sendable {
    public let path: String
    package let database: any DatabaseWriter

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

    package func write<Value>(
        _ updates: (Database) throws -> Value
    ) throws -> Value {
        try database.write(updates)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        ObjectIdentifier(lhs.database) == ObjectIdentifier(rhs.database)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(database))
    }
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
