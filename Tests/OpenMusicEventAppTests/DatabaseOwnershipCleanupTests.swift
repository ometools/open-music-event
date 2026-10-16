import Foundation
import Testing
@testable import OpenMusicEventApp

@Suite
struct DatabaseOwnershipCleanupTests {
    @Test
    func legacyWorkingDatabaseDirectoryIsDeletedIdempotentlyWithoutTouchingOwnedDatabases() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let obsoleteDirectory = root
            .appending(path: "EditingWorkspaces", directoryHint: .isDirectory)
        let referenceDirectory = root
            .appending(path: "WorkspaceReferences", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: obsoleteDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: referenceDirectory,
            withIntermediateDirectories: true
        )
        let obsoleteDatabase = obsoleteDirectory.appending(path: "workspace.sqlite")
        let obsoleteWAL = obsoleteDirectory.appending(path: "workspace.sqlite-wal")
        let obsoleteSHM = obsoleteDirectory.appending(path: "workspace.sqlite-shm")
        let defaultDatabase = root.appending(path: "OpenMusicEvent.sqlite")
        let referenceDatabase = referenceDirectory.appending(path: "reference.sqlite")
        for url in [
            obsoleteDatabase,
            obsoleteWAL,
            obsoleteSHM,
            defaultDatabase,
            referenceDatabase,
        ] {
            try Data("sentinel".utf8).write(to: url)
        }

        try removeObsoleteEditingWorkspaceDatabases(applicationSupportDirectory: root)
        try removeObsoleteEditingWorkspaceDatabases(applicationSupportDirectory: root)

        #expect(!FileManager.default.fileExists(atPath: obsoleteDirectory.path))
        #expect(FileManager.default.fileExists(atPath: defaultDatabase.path))
        #expect(FileManager.default.fileExists(atPath: referenceDatabase.path))
        #expect(try Data(contentsOf: defaultDatabase) == Data("sentinel".utf8))
        #expect(try Data(contentsOf: referenceDatabase) == Data("sentinel".utf8))
    }
}
