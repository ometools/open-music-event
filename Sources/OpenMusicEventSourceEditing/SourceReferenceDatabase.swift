import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import SourceEditing

public struct SourceReferenceDatabaseClient: Sendable {
    public var url: @Sendable (OME.SourceDatabaseInsertion.SourceProvenance) throws -> URL
    public var prepareForImport: @Sendable (OME.SourceDatabaseInsertion.SourceProvenance) throws -> SourceBaselineDatabase
    public var existing: @Sendable (OME.SourceDatabaseInsertion.SourceProvenance) throws -> SourceBaselineDatabase?

    public init(
        url: @escaping @Sendable (OME.SourceDatabaseInsertion.SourceProvenance) throws -> URL,
        prepareForImport: @escaping @Sendable (OME.SourceDatabaseInsertion.SourceProvenance) throws -> SourceBaselineDatabase,
        existing: @escaping @Sendable (OME.SourceDatabaseInsertion.SourceProvenance) throws -> SourceBaselineDatabase?
    ) {
        self.url = url
        self.prepareForImport = prepareForImport
        self.existing = existing
    }
}

public struct SourceReferenceDatabaseMigrator: Sendable {
    public var migrate: @Sendable (SourceBaselineDatabase) throws -> Void

    public init(
        migrate: @escaping @Sendable (SourceBaselineDatabase) throws -> Void
    ) {
        self.migrate = migrate
    }
}

public extension SourceReferenceDatabaseMigrator {
    static let noop = Self { _ in }
}

public extension SourceReferenceDatabaseClient {
    static let relativePath = ".ome/reference.sqlite"
    static let gitignoreEntry = ".ome/reference.sqlite"

    static var live: Self {
        Self(
            url: { provenance in
                @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage
                return try referenceDatabaseURL(
                    repositoryURL: sourceRepositoryStorage.repositoryURL(provenance)
                )
            },
            prepareForImport: { provenance in
                @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage
                @Dependency(\.sourceReferenceDatabaseMigrator) var migrator
                let repositoryURL = try sourceRepositoryStorage.repositoryURL(provenance)
                let referenceDatabaseURL = try referenceDatabaseURL(repositoryURL: repositoryURL)
                try prepareReferenceDirectory(for: referenceDatabaseURL)
                try ensureReferenceDatabaseIgnored(in: repositoryURL)
                try removeSQLiteDatabase(at: referenceDatabaseURL)
                let database = try defaultBaselineDatabase(path: referenceDatabaseURL.path)
                try migrator.migrate(database)
                return database
            },
            existing: { provenance in
                @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage
                @Dependency(\.sourceReferenceDatabaseMigrator) var migrator
                let referenceDatabaseURL = try referenceDatabaseURL(
                    repositoryURL: sourceRepositoryStorage.repositoryURL(provenance)
                )
                guard FileManager.default.fileExists(atPath: referenceDatabaseURL.path) else {
                    return nil
                }
                let database = try defaultBaselineDatabase(path: referenceDatabaseURL.path)
                try migrator.migrate(database)
                return database
            }
        )
    }

    static func referenceDatabaseURL(repositoryURL: URL) throws -> URL {
        repositoryURL
            .standardizedFileURL
            .appending(path: ".ome", directoryHint: .isDirectory)
            .appending(path: "reference.sqlite")
    }

    static func prepareReferenceDirectory(for referenceDatabaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: referenceDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    static func ensureReferenceDatabaseIgnored(in repositoryURL: URL) throws {
        let gitignoreURL = repositoryURL
            .standardizedFileURL
            .appending(path: ".gitignore")
        let entry = gitignoreEntry
        let existingContents = (try? String(contentsOf: gitignoreURL, encoding: .utf8)) ?? ""
        let existingLines = existingContents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard !existingLines.contains(entry) else { return }

        var contents = existingContents
        if !contents.isEmpty, !contents.hasSuffix("\n") {
            contents.append("\n")
        }
        contents.append(entry)
        contents.append("\n")
        try contents.write(to: gitignoreURL, atomically: true, encoding: .utf8)
    }

    static func removeSQLiteDatabase(at databaseURL: URL) throws {
        let fileManager = FileManager.default
        for url in [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-shm"),
            URL(fileURLWithPath: databaseURL.path + "-wal"),
        ] {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                guard error.isMissingFile else { throw error }
            }
        }
    }
}

public extension EventSourceProvenanceRecord {
    var sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance {
        OME.SourceDatabaseInsertion.SourceProvenance(
            kind: sourceKind,
            reference: sourceReference,
            ref: ref
        )
    }
}

public extension SourceBaselineRecord {
    var sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance {
        OME.SourceDatabaseInsertion.SourceProvenance(
            kind: sourceKind,
            reference: sourceReference,
            ref: ref
        )
    }
}

public extension DependencyValues {
    var sourceReferenceDatabase: SourceReferenceDatabaseClient {
        get { self[SourceReferenceDatabaseClientKey.self] }
        set { self[SourceReferenceDatabaseClientKey.self] = newValue }
    }

    var sourceReferenceDatabaseMigrator: SourceReferenceDatabaseMigrator {
        get { self[SourceReferenceDatabaseMigratorKey.self] }
        set { self[SourceReferenceDatabaseMigratorKey.self] = newValue }
    }
}

private enum SourceReferenceDatabaseClientKey: DependencyKey {
    static var liveValue: SourceReferenceDatabaseClient {
        .live
    }

    static var testValue: SourceReferenceDatabaseClient {
        .live
    }
}

private enum SourceReferenceDatabaseMigratorKey: DependencyKey {
    static let liveValue = SourceReferenceDatabaseMigrator.noop
    static let testValue = SourceReferenceDatabaseMigrator.noop
}

private extension Error {
    var isMissingFile: Bool {
        let error = self as NSError
        if error.domain == NSCocoaErrorDomain,
           error.code == NSFileNoSuchFileError {
            return true
        }
        if error.domain == NSPOSIXErrorDomain,
           error.code == Int(ENOENT) {
            return true
        }
        return false
    }
}
