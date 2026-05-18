import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource

struct SourceRepositoryStorageClient: Sendable {
    var store: @Sendable (URL, OMERecord.SourceDatabaseInsertion.SourceProvenance) throws -> URL
    var remove: @Sendable (OMERecord.SourceDatabaseInsertion.SourceProvenance) throws -> Void

    init(
        store: @escaping @Sendable (URL, OMERecord.SourceDatabaseInsertion.SourceProvenance) throws -> URL,
        remove: @escaping @Sendable (OMERecord.SourceDatabaseInsertion.SourceProvenance) throws -> Void
    ) {
        self.store = store
        self.remove = remove
    }
}

extension SourceRepositoryStorageClient {
    static var live: Self {
        Self(
            store: { repositoryURL, provenance in
                guard provenance.kind == .tangled else { return repositoryURL }
                let destinationURL = try storedRepositoryURL(for: provenance)
                let sourceURL = repositoryURL.standardizedFileURL
                let standardizedDestinationURL = destinationURL.standardizedFileURL
                guard sourceURL != standardizedDestinationURL else {
                    return standardizedDestinationURL
                }
                if FileManager.default.fileExists(atPath: standardizedDestinationURL.path()) {
                    try FileManager.default.removeItem(at: standardizedDestinationURL)
                }
                try FileManager.default.moveItem(at: sourceURL, to: standardizedDestinationURL)
                return standardizedDestinationURL
            },
            remove: { provenance in
                guard provenance.kind == .tangled else { return }
                let url = try storedRepositoryURL(for: provenance)
                guard FileManager.default.fileExists(atPath: url.path()) else { return }
                try FileManager.default.removeItem(at: url)
            }
        )
    }

    static var noop: Self {
        Self(
            store: { repositoryURL, _ in repositoryURL },
            remove: { _ in }
        )
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
        for provenance: OMERecord.SourceDatabaseInsertion.SourceProvenance
    ) throws -> URL {
        try rootURL()
            .appendingPathComponent(directoryName(for: provenance), isDirectory: true)
    }

    static func directoryName(
        for provenance: OMERecord.SourceDatabaseInsertion.SourceProvenance
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
}

private enum SourceRepositoryStorageClientKey: DependencyKey {
    static var liveValue: SourceRepositoryStorageClient {
        .live
    }

    static var testValue: SourceRepositoryStorageClient {
        .noop
    }
}

extension DependencyValues {
    var sourceRepositoryStorage: SourceRepositoryStorageClient {
        get { self[SourceRepositoryStorageClientKey.self] }
        set { self[SourceRepositoryStorageClientKey.self] = newValue }
    }
}
