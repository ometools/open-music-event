import Dependencies
import Foundation
import GRDB
import OpenMusicEventLexicon
import SourceEditing
import SQLiteData

/// A durable reference copy for local edits to canonical records.
///
/// Opening an existing baseline never advances it. Edits made after the first capture therefore
/// remain visible when the workspace is reopened.
public enum CanonicalWorkspaceBaseline {
    public enum Error: Swift.Error, Equatable {
        case invalidExistingSnapshot(String)
    }

    public static func openOrCapture(
        for eventID: Event.ID,
        from applicationDatabase: any DatabaseWriter
    ) throws -> SourceBaselineDatabase {
        @Dependency(\.canonicalWorkspaceStorage) var storage
        return try openOrCapture(
            at: storage.path(eventID),
            from: applicationDatabase
        )
    }

    public static func openOrCapture(
        at path: String,
        from applicationDatabase: any DatabaseWriter
    ) throws -> SourceBaselineDatabase {
        let fileURL = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existed = FileManager.default.fileExists(atPath: path)
        let baseline = try defaultBaselineDatabase(path: path)
        if !existed {
            try applicationDatabase.backup(to: baseline.database)
        }
        guard try baseline.read({ try $0.tableExists(Event.tableName) }) else {
            throw Error.invalidExistingSnapshot(path)
        }
        return baseline
    }
}

public struct CanonicalWorkspaceStorage: Sendable {
    public var path: @Sendable (Event.ID) throws -> String

    public init(path: @escaping @Sendable (Event.ID) throws -> String) {
        self.path = path
    }

    public static func fileBacked(rootURL: URL) -> Self {
        Self { eventID in
            rootURL
                .appending(path: eventID.authority.description, directoryHint: .isDirectory)
                .appending(path: "baseline.sqlite", directoryHint: .notDirectory)
                .path
        }
    }
}

private enum CanonicalWorkspaceStorageKey: DependencyKey {
    static var liveValue: CanonicalWorkspaceStorage {
        CanonicalWorkspaceStorage { eventID in
            let applicationSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return try CanonicalWorkspaceStorage.fileBacked(
                rootURL: applicationSupportURL
                    .appending(path: "OpenMusicEvent/CanonicalWorkspaces", directoryHint: .isDirectory)
            ).path(eventID)
        }
    }

    static let testValue = CanonicalWorkspaceStorage.fileBacked(
        rootURL: FileManager.default.temporaryDirectory
            .appending(path: "OpenMusicEvent-CanonicalWorkspaces-\(UUID())", directoryHint: .isDirectory)
    )
}

public extension DependencyValues {
    var canonicalWorkspaceStorage: CanonicalWorkspaceStorage {
        get { self[CanonicalWorkspaceStorageKey.self] }
        set { self[CanonicalWorkspaceStorageKey.self] = newValue }
    }
}
