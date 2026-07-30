import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource

public struct SourceRepositoryStorageRootClient: Sendable {
    public var rootURL: @Sendable () throws -> URL

    public init(rootURL: @escaping @Sendable () throws -> URL) {
        self.rootURL = rootURL
    }
}

public extension SourceRepositoryStorageRootClient {
    static var live: Self {
        Self {
            let applicationSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let rootURL = applicationSupportURL
                .appendingPathComponent("SourceRepositories", isDirectory: true)
                .standardizedFileURL
            try FileManager.default.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
            return rootURL
        }
    }

    static func rooted(at rootURL: URL) -> Self {
        Self {
            let rootURL = rootURL.standardizedFileURL
            try FileManager.default.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
            return rootURL
        }
    }
}

public struct SourceRepositoryStorageClient: Sendable {
    public var repositoryURL: @Sendable (OME.SourceDatabaseInsertion.SourceProvenance) throws -> URL
    public var store: @Sendable (URL, OME.SourceDatabaseInsertion.SourceProvenance) throws -> URL
    public var remove: @Sendable (OME.SourceDatabaseInsertion.SourceProvenance) throws -> Void

    public init(
        repositoryURL: @escaping @Sendable (OME.SourceDatabaseInsertion.SourceProvenance) throws -> URL = Self.repositoryURL,
        store: @escaping @Sendable (URL, OME.SourceDatabaseInsertion.SourceProvenance) throws -> URL,
        remove: @escaping @Sendable (OME.SourceDatabaseInsertion.SourceProvenance) throws -> Void
    ) {
        self.repositoryURL = repositoryURL
        self.store = store
        self.remove = remove
    }
}

public extension SourceRepositoryStorageClient {
    static var live: Self {
        @Dependency(\.sourceRepositoryStorageRoot) var sourceRepositoryStorageRoot

        return Self(
            repositoryURL: { provenance in
                try Self.repositoryURL(
                    for: provenance,
                    rootURL: sourceRepositoryStorageRoot.rootURL()
                )
            },
            store: { repositoryURL, provenance in
                guard provenance.kind == .tangled else { return repositoryURL.standardizedFileURL }
                let rootURL = try sourceRepositoryStorageRoot.rootURL()
                let destinationURL = storedRepositoryURL(
                    for: provenance,
                    rootURL: rootURL
                )
                let sourceURL = repositoryURL.standardizedFileURL
                let standardizedDestinationURL = destinationURL.standardizedFileURL
                try removeStoredRepository(
                    at: legacyStoredRepositoryURL(
                        for: provenance,
                        rootURL: rootURL
                    )
                )
                guard sourceURL != standardizedDestinationURL else {
                    return standardizedDestinationURL
                }
                try replaceItem(at: sourceURL, withItemAt: standardizedDestinationURL)
                return standardizedDestinationURL
            },
            remove: { provenance in
                guard provenance.kind == .tangled else { return }
                let rootURL = try sourceRepositoryStorageRoot.rootURL()
                try removeStoredRepository(
                    at: storedRepositoryURL(
                        for: provenance,
                        rootURL: rootURL
                    )
                )
                try removeStoredRepository(
                    at: legacyStoredRepositoryURL(
                        for: provenance,
                        rootURL: rootURL
                    )
                )
            }
        )
    }

    static var noop: Self {
        Self(
            store: { repositoryURL, _ in repositoryURL },
            remove: { _ in }
        )
    }

    static func repositoryURL(
        for provenance: OME.SourceDatabaseInsertion.SourceProvenance
    ) throws -> URL {
        @Dependency(\.sourceRepositoryStorageRoot) var sourceRepositoryStorageRoot

        return try repositoryURL(
            for: provenance,
            rootURL: sourceRepositoryStorageRoot.rootURL()
        )
    }

    static func repositoryURL(
        for provenance: OME.SourceDatabaseInsertion.SourceProvenance,
        rootURL: URL
    ) throws -> URL {
        switch provenance.kind {
        case .local:
            URL(fileURLWithPath: provenance.reference).standardizedFileURL
        case .tangled:
            storedRepositoryURL(for: provenance, rootURL: rootURL)
        }
    }

    static func temporaryDownloadURL(uuid: UUID) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ome-source-clone-\(uuid.uuidString)")
            .standardizedFileURL
    }

    static func rootURL() throws -> URL {
        @Dependency(\.sourceRepositoryStorageRoot) var sourceRepositoryStorageRoot

        return try sourceRepositoryStorageRoot.rootURL()
    }

    static func storedRepositoryURL(
        for provenance: OME.SourceDatabaseInsertion.SourceProvenance
    ) throws -> URL {
        storedRepositoryURL(for: provenance, rootURL: try rootURL())
    }

    static func storedRepositoryURL(
        for provenance: OME.SourceDatabaseInsertion.SourceProvenance,
        rootURL: URL
    ) -> URL {
        rootURL
            .standardizedFileURL
            .appendingPathComponent(directoryName(for: provenance), isDirectory: true)
    }

    static func directoryName(
        for provenance: OME.SourceDatabaseInsertion.SourceProvenance
    ) -> String {
        directoryName(
            components: [
                provenance.kind.rawValue,
                provenance.reference,
            ]
        )
    }

    private static func legacyStoredRepositoryURL(
        for provenance: OME.SourceDatabaseInsertion.SourceProvenance,
        rootURL: URL
    ) -> URL {
        rootURL
            .standardizedFileURL
            .appendingPathComponent(
                directoryName(
                    components: [
                        provenance.kind.rawValue,
                        provenance.reference,
                        provenance.ref ?? "",
                    ]
                ),
                isDirectory: true
            )
    }

    private static func directoryName(components: [String]) -> String {
        Data(components.joined(separator: "\u{1F}").utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func removeStoredRepository(at url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            guard error.isMissingFile else { throw error }
        }
    }

    private static func replaceItem(
        at sourceURL: URL,
        withItemAt destinationURL: URL
    ) throws {
        let fileManager = FileManager.default
        let parentURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parentURL,
            withIntermediateDirectories: true
        )

        let destinationReferenceDatabaseURL = referenceDatabaseURL(in: destinationURL)
        if sourceReferenceDatabaseExists(at: destinationReferenceDatabaseURL) {
            try removeContents(
                of: destinationURL,
                preservingReferenceDatabaseAt: destinationReferenceDatabaseURL.standardizedFileURL.path
            )
            try removeSQLiteDatabase(at: referenceDatabaseURL(in: sourceURL))
            try moveContents(of: sourceURL, to: destinationURL)
            return
        }

        let oldDestinationURL = parentURL
            .appendingPathComponent(
                ".\(destinationURL.lastPathComponent).old-\(UUID().uuidString)",
                isDirectory: true
            )

        let movedOldDestination: Bool
        do {
            try fileManager.moveItem(at: destinationURL, to: oldDestinationURL)
            movedOldDestination = true
        } catch {
            if error.isMissingFile {
                movedOldDestination = false
            } else {
                throw error
            }
        }

        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            if movedOldDestination {
                try? removeStoredRepositoryBackup(at: oldDestinationURL)
            }
        } catch {
            if movedOldDestination {
                try? fileManager.moveItem(at: oldDestinationURL, to: destinationURL)
            }
            throw error
        }
    }

    private static func removeStoredRepositoryBackup(at repositoryURL: URL) throws {
        let referenceDatabaseURL = referenceDatabaseURL(in: repositoryURL)
        guard sourceReferenceDatabaseExists(at: referenceDatabaseURL) else {
            try FileManager.default.removeItem(at: repositoryURL)
            return
        }

        // Open workspace sessions can still have this SQLite database attached.
        try removeContents(
            of: repositoryURL,
            preservingReferenceDatabaseAt: referenceDatabaseURL.standardizedFileURL.path
        )
    }

    private static func sourceReferenceDatabaseExists(at databaseURL: URL) -> Bool {
        let fileManager = FileManager.default
        let databasePath = databaseURL.standardizedFileURL.path
        return sqliteDatabasePaths(for: databasePath)
            .contains { fileManager.fileExists(atPath: $0) }
    }

    private static func removeSQLiteDatabase(at databaseURL: URL) throws {
        for url in sqliteDatabaseURLs(for: databaseURL) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                guard error.isMissingFile else { throw error }
            }
        }
    }

    private static func referenceDatabaseURL(in repositoryURL: URL) -> URL {
        repositoryURL
            .standardizedFileURL
            .appending(path: ".ome", directoryHint: .isDirectory)
            .appending(path: "reference.sqlite")
    }

    private static func sqliteDatabaseURLs(for databaseURL: URL) -> [URL] {
        sqliteDatabasePaths(for: databaseURL.standardizedFileURL.path)
            .map { URL(fileURLWithPath: $0) }
    }

    private static func sqliteDatabasePaths(for databasePath: String) -> [String] {
        [
            databasePath,
            databasePath + "-shm",
            databasePath + "-wal",
            databasePath + "-journal",
        ]
    }

    private static func moveContents(
        of sourceDirectoryURL: URL,
        to destinationDirectoryURL: URL
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationDirectoryURL,
            withIntermediateDirectories: true
        )

        let contents = try fileManager.contentsOfDirectory(
            at: sourceDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        for sourceURL in contents {
            let destinationURL = destinationDirectoryURL
                .appendingPathComponent(sourceURL.lastPathComponent)
            if try shouldMergeDirectory(from: sourceURL, into: destinationURL) {
                try moveContents(of: sourceURL, to: destinationURL)
            } else {
                do {
                    try fileManager.removeItem(at: destinationURL)
                } catch {
                    guard error.isMissingFile else { throw error }
                }
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            }
        }

        try fileManager.removeItem(at: sourceDirectoryURL)
    }

    private static func shouldMergeDirectory(
        from sourceURL: URL,
        into destinationURL: URL
    ) throws -> Bool {
        guard try isDirectoryThatCanBeDescended(sourceURL),
              FileManager.default.fileExists(atPath: destinationURL.path),
              try isDirectoryThatCanBeDescended(destinationURL)
        else { return false }
        return true
    }

    private static func removeContents(
        of directoryURL: URL,
        preservingReferenceDatabaseAt referenceDatabasePath: String
    ) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )

        for url in contents {
            let path = url.standardizedFileURL.path
            if isReferenceDatabaseSidecar(path, referenceDatabasePath: referenceDatabasePath) {
                continue
            }

            if referenceDatabasePath.hasPrefix(path + "/"),
               try isDirectoryThatCanBeDescended(url)
            {
                try removeContents(
                    of: url,
                    preservingReferenceDatabaseAt: referenceDatabasePath
                )
                let remainingContents = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil
                )
                if remainingContents.isEmpty {
                    try fileManager.removeItem(at: url)
                }
            } else {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private static func isReferenceDatabaseSidecar(
        _ path: String,
        referenceDatabasePath: String
    ) -> Bool {
        path == referenceDatabasePath || path.hasPrefix(referenceDatabasePath + "-")
    }

    private static func isDirectoryThatCanBeDescended(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values.isDirectory == true && values.isSymbolicLink != true
    }
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

private enum SourceRepositoryStorageRootClientKey: DependencyKey {
    static var liveValue: SourceRepositoryStorageRootClient {
        .live
    }

    static var testValue: SourceRepositoryStorageRootClient {
        .rooted(
            at: FileManager.default.temporaryDirectory
                .appending(
                    path: "ome-source-repositories-\(UUID().uuidString)",
                    directoryHint: .isDirectory
                )
        )
    }
}

private enum SourceRepositoryStorageClientKey: DependencyKey {
    static var liveValue: SourceRepositoryStorageClient {
        .live
    }

    static var testValue: SourceRepositoryStorageClient {
        .noop
    }
}

public extension DependencyValues {
    var sourceRepositoryStorageRoot: SourceRepositoryStorageRootClient {
        get { self[SourceRepositoryStorageRootClientKey.self] }
        set { self[SourceRepositoryStorageRootClientKey.self] = newValue }
    }

    var sourceRepositoryStorage: SourceRepositoryStorageClient {
        get { self[SourceRepositoryStorageClientKey.self] }
        set { self[SourceRepositoryStorageClientKey.self] = newValue }
    }
}
