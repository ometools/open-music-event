import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource

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
        Self(
            store: { repositoryURL, provenance in
                guard provenance.kind == .tangled else { return repositoryURL.standardizedFileURL }
                let destinationURL = try storedRepositoryURL(for: provenance)
                let sourceURL = repositoryURL.standardizedFileURL
                let standardizedDestinationURL = destinationURL.standardizedFileURL
                guard sourceURL != standardizedDestinationURL else {
                    return standardizedDestinationURL
                }
                try replaceItem(at: sourceURL, withItemAt: standardizedDestinationURL)
                return standardizedDestinationURL
            },
            remove: { provenance in
                guard provenance.kind == .tangled else { return }
                let url = try storedRepositoryURL(for: provenance)
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    guard error.isMissingFile else { throw error }
                }
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
        switch provenance.kind {
        case .local:
            URL(fileURLWithPath: provenance.reference).standardizedFileURL
        case .tangled:
            try storedRepositoryURL(for: provenance)
        }
    }

    static func temporaryDownloadURL(uuid: UUID) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ome-source-clone-\(uuid.uuidString)")
            .standardizedFileURL
    }

    static func rootURL() throws -> URL {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootURL = applicationSupportURL
            .appendingPathComponent("SourceRepositories", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        return rootURL
    }

    static func storedRepositoryURL(
        for provenance: OME.SourceDatabaseInsertion.SourceProvenance
    ) throws -> URL {
        try rootURL()
            .appendingPathComponent(directoryName(for: provenance), isDirectory: true)
    }

    static func directoryName(
        for provenance: OME.SourceDatabaseInsertion.SourceProvenance
    ) -> String {
        let components = [
            provenance.kind.rawValue,
            provenance.reference,
            provenance.ref ?? "",
        ]
        return Data(components.joined(separator: "\u{1F}").utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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
                try? fileManager.removeItem(at: oldDestinationURL)
            }
        } catch {
            if movedOldDestination {
                try? fileManager.moveItem(at: oldDestinationURL, to: destinationURL)
            }
            throw error
        }
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

private enum SourceRepositoryStorageClientKey: DependencyKey {
    static var liveValue: SourceRepositoryStorageClient {
        .live
    }

    static var testValue: SourceRepositoryStorageClient {
        .noop
    }
}

public extension DependencyValues {
    var sourceRepositoryStorage: SourceRepositoryStorageClient {
        get { self[SourceRepositoryStorageClientKey.self] }
        set { self[SourceRepositoryStorageClientKey.self] = newValue }
    }
}
