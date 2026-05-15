import Dependencies
import Foundation
import SQLiteData

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
            return URL(fileURLWithPath: "/private/tmp", isDirectory: true)
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
