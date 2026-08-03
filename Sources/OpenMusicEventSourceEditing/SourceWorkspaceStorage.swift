import Dependencies
import Foundation
import SourceEditing

public struct SourceWorkspaceLocation: Equatable, Sendable {
    public var directoryURL: URL
    public var referenceDatabaseURL: URL
    public var repositoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL.standardizedFileURL
        self.repositoryURL = directoryURL
            .appending(path: "repository", directoryHint: .isDirectory)
            .standardizedFileURL
        self.referenceDatabaseURL = directoryURL
            .appending(path: "reference.sqlite", directoryHint: .notDirectory)
            .standardizedFileURL
    }
}

/// Resolves durable storage owned by a source workspace.
///
/// The repository and its reference database are siblings. The reference database is never placed
/// inside the Git working tree and never becomes an application-wide dependency.
public struct SourceWorkspaceStorage: Sendable {
    public var location: @Sendable (SourceWorkspace.ID) throws -> SourceWorkspaceLocation

    public init(
        location: @escaping @Sendable (SourceWorkspace.ID) throws -> SourceWorkspaceLocation
    ) {
        self.location = location
    }
}

public extension SourceWorkspaceStorage {
    static func fileBacked(rootURL: URL) -> Self {
        Self { workspaceID in
            SourceWorkspaceLocation(
                directoryURL: rootURL
                    .standardizedFileURL
                    .appending(path: workspaceID.rawValue, directoryHint: .isDirectory)
            )
        }
    }

    static var live: Self {
        Self { workspaceID in
            let applicationSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return SourceWorkspaceLocation(
                directoryURL: applicationSupportURL
                    .appending(path: "OpenMusicEvent", directoryHint: .isDirectory)
                    .appending(path: "SourceWorkspaces", directoryHint: .isDirectory)
                    .appending(path: workspaceID.rawValue, directoryHint: .isDirectory)
            )
        }
    }

    static var test: Self {
        fileBacked(
            rootURL: FileManager.default.temporaryDirectory
                .appending(
                    path: "OpenMusicEvent-SourceWorkspaces-\(UUID().uuidString)",
                    directoryHint: .isDirectory
                )
        )
    }
}

public struct SourceWorkspaceReferenceMigrator: Sendable {
    public var migrate: @Sendable (SourceBaselineDatabase) throws -> Void

    public init(
        migrate: @escaping @Sendable (SourceBaselineDatabase) throws -> Void
    ) {
        self.migrate = migrate
    }
}

public extension SourceWorkspaceReferenceMigrator {
    static let noop = Self { _ in }
}

public extension DependencyValues {
    var sourceWorkspaceStorage: SourceWorkspaceStorage {
        get { self[SourceWorkspaceStorageKey.self] }
        set { self[SourceWorkspaceStorageKey.self] = newValue }
    }

    var sourceWorkspaceReferenceMigrator: SourceWorkspaceReferenceMigrator {
        get { self[SourceWorkspaceReferenceMigratorKey.self] }
        set { self[SourceWorkspaceReferenceMigratorKey.self] = newValue }
    }
}

private enum SourceWorkspaceStorageKey: DependencyKey {
    static var liveValue: SourceWorkspaceStorage { .live }
    static var testValue: SourceWorkspaceStorage { .test }
}

private enum SourceWorkspaceReferenceMigratorKey: DependencyKey {
    static let liveValue = SourceWorkspaceReferenceMigrator.noop
    static let testValue = SourceWorkspaceReferenceMigrator.noop
}
