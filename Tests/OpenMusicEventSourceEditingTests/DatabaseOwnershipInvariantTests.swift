import CustomDump
import Dependencies
import Foundation
import GRDB
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import Sharing
import SourceEditing
import Testing

@Suite
struct DatabaseOwnershipInvariantTests {
    @Test
    func workspaceResourcePreservesApplicationDatabaseIdentityWithoutAttachingReference() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let defaultDatabase = try DatabasePool(
            path: directory.appending(path: "application.sqlite").path
        )
        try setMarker("populated default", in: defaultDatabase)
        let referenceDatabase = try defaultBaselineDatabase(
            path: directory.appending(path: "reference.sqlite").path
        )
        try setMarker("imported baseline", in: referenceDatabase.database)
        let organizerID = try #require(OME.Organizer.ID("did:plc:workspace"))
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/example/source",
            branch: "main"
        )
        let resource = SourceWorkspaceResource(
            workspace: workspace,
            repositoryURL: directory.appending(path: "repository"),
            mainDatabase: defaultDatabase,
            referenceDatabase: referenceDatabase
        )

        #expect(resource.applicationDatabaseID == ObjectIdentifier(defaultDatabase))
        #expect(resource.referenceDatabase == referenceDatabase)
        let databaseNames = try defaultDatabase.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_database_list")
        }
        expectNoDifference(databaseNames, ["main"])

        try defaultDatabase.write { db in
            try db.execute(sql: "UPDATE marker SET value = 'current edit'")
        }
        #expect(try marker(in: defaultDatabase) == "current edit")
        #expect(try referenceDatabase.read(marker) == "imported baseline")

        let parentMarker = try withDependencies {
            $0.defaultDatabase = defaultDatabase
        } operation: {
            @Dependency(\.defaultDatabase) var parentDatabase
            return try marker(in: parentDatabase)
        }
        #expect(parentMarker == "current edit")
    }

    @Test
    func distinctReferencesNeverCreateDistinctApplicationWriters() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let defaultDatabase = try DatabasePool(
            path: directory.appending(path: "application.sqlite").path
        )
        let firstReferenceDatabase = try defaultBaselineDatabase(
            path: directory.appending(path: "first-reference.sqlite").path
        )
        let secondReferenceDatabase = try defaultBaselineDatabase(
            path: directory.appending(path: "second-reference.sqlite").path
        )
        let organizerID = try #require(OME.Organizer.ID("did:plc:workspace"))
        let workspace = SourceWorkspace(
            organizerID: organizerID,
            repository: "tangled.org/example/source",
            branch: "main"
        )

        let firstResource = SourceWorkspaceResource(
            workspace: workspace,
            repositoryURL: directory.appending(path: "repository"),
            mainDatabase: defaultDatabase,
            referenceDatabase: firstReferenceDatabase
        )
        let secondResource = SourceWorkspaceResource(
            workspace: workspace,
            repositoryURL: directory.appending(path: "repository"),
            mainDatabase: defaultDatabase,
            referenceDatabase: secondReferenceDatabase
        )

        #expect(firstResource.applicationDatabaseID == ObjectIdentifier(defaultDatabase))
        #expect(secondResource.applicationDatabaseID == ObjectIdentifier(defaultDatabase))
        #expect(firstResource.referenceDatabase != secondResource.referenceDatabase)
    }

    @Test
    func stableReferenceReaderObservesAControlledBaselineRefresh() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let referenceDatabase = try defaultBaselineDatabase(
            path: directory.appending(path: "reference.sqlite").path
        )
        try setMarker("old baseline", in: referenceDatabase.database)

        #expect(try referenceDatabase.read(marker) == "old baseline")
        let refreshedReferenceDatabase = try defaultBaselineDatabase(
            path: directory.appending(path: "refreshed-reference.sqlite").path
        )
        try setMarker("refreshed baseline", in: refreshedReferenceDatabase.database)
        try refreshedReferenceDatabase.database.backup(to: referenceDatabase.database)
        #expect(try referenceDatabase.read(marker) == "refreshed baseline")
    }
}

private func setMarker(_ value: String, in database: any DatabaseWriter) throws {
    try database.write { db in
        try db.execute(sql: "CREATE TABLE marker (value TEXT NOT NULL)")
        try db.execute(sql: "INSERT INTO marker VALUES (?)", arguments: [value])
    }
}

private func marker(in database: any DatabaseWriter) throws -> String {
    try database.read(marker)
}

private func marker(in db: Database) throws -> String {
    let value = try String.fetchOne(db, sql: "SELECT value FROM marker")
    return try #require(value)
}
