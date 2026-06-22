import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import SQLiteData

public struct SourceEditModePreparationClient: Sendable {
    public var prepare: @Sendable (SourceBaselineRecord.ID) async throws -> Void

    public init(
        prepare: @escaping @Sendable (SourceBaselineRecord.ID) async throws -> Void
    ) {
        self.prepare = prepare
    }
}

public enum SourceEditModePreparationError: Equatable, Error, Sendable {
    case sourceBaselineNotFound(SourceBaselineRecord.ID)
}

public extension SourceEditModePreparationClient {
    static var live: Self {
        Self { sourceBaselineID in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.sourceRepositoryStorage) var sourceRepositoryStorage
            @Dependency(\.tangledSSHCredentials) var tangledSSHCredentials
            @Dependency(\.uuid) var uuid

            let sourceBaseline = try await database.read { db in
                try SourceBaselineRecord
                    .where { $0.id.eq(sourceBaselineID) }
                    .fetchOne(db)
            }
            guard let sourceBaseline else {
                throw SourceEditModePreparationError.sourceBaselineNotFound(sourceBaselineID)
            }

            let sourceProvenance = sourceBaseline.sourceProvenance
            guard sourceProvenance.kind == .tangled else { return }

            let storedRepositoryURL = try sourceRepositoryStorage
                .repositoryURL(sourceProvenance)
            guard !storedRepositoryURL.isGitBackedSourceRepository else { return }

            let checkoutURL = SourceRepositoryStorageClient
                .temporaryDownloadURL(uuid: uuid())
            let checkout = try await TangledSourceCheckoutClient
                .git(credentials: try await tangledSSHCredentials.credentials())
                .checkout(
                    TangledSourceCheckoutRequest(
                        repository: try TangledRepositoryReference(
                            parsing: sourceProvenance.reference
                        ),
                        ref: sourceProvenance.ref ?? "HEAD",
                        outputURL: checkoutURL
                    )
                )
            defer {
                try? FileManager.default.removeItem(at: checkout.repositoryURL)
            }

            try Self.preserveSourceEditingMetadata(
                from: storedRepositoryURL,
                into: checkout.repositoryURL
            )
            _ = try sourceRepositoryStorage.store(
                checkout.repositoryURL,
                sourceProvenance
            )
        }
    }

    static var noop: Self {
        Self { _ in }
    }

    private static func preserveSourceEditingMetadata(
        from storedRepositoryURL: URL,
        into gitRepositoryURL: URL
    ) throws {
        let fileManager = FileManager.default
        let storedMetadataURL = storedRepositoryURL
            .standardizedFileURL
            .appending(path: ".ome", directoryHint: .isDirectory)
        let gitMetadataURL = gitRepositoryURL
            .standardizedFileURL
            .appending(path: ".ome", directoryHint: .isDirectory)

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(
            atPath: storedMetadataURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue {
            if fileManager.fileExists(atPath: gitMetadataURL.path) {
                try fileManager.removeItem(at: gitMetadataURL)
            }
            try fileManager.copyItem(at: storedMetadataURL, to: gitMetadataURL)
        }

        try SourceReferenceDatabaseClient
            .ensureReferenceDatabaseIgnored(in: gitRepositoryURL)
    }
}

public extension DependencyValues {
    var sourceEditModePreparation: SourceEditModePreparationClient {
        get { self[SourceEditModePreparationClientKey.self] }
        set { self[SourceEditModePreparationClientKey.self] = newValue }
    }
}

private enum SourceEditModePreparationClientKey: DependencyKey {
    static var liveValue: SourceEditModePreparationClient {
        .live
    }

    static var testValue: SourceEditModePreparationClient {
        .noop
    }
}

private extension URL {
    var isGitBackedSourceRepository: Bool {
        FileManager.default.fileExists(
            atPath: standardizedFileURL
                .appending(path: ".git")
                .path
        )
    }
}
