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
    func workspaceResourceKeepsTheApplicationDatabaseAsMainAndAttachesTheReferenceReadOnly() throws {
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
        let resource = try SourceWorkspaceResource(
            workspace: workspace,
            repositoryURL: directory.appending(path: "repository"),
            mainDatabase: defaultDatabase,
            referenceDatabase: referenceDatabase
        )

        let observed = try resource.database.write { db in
                let databasePaths = try Dictionary(
                    uniqueKeysWithValues: Row
                        .fetchAll(db, sql: "PRAGMA database_list")
                        .map { row in
                            (row["name"] as String, row["file"] as String)
                        }
                )
                let referenceMarker = try String.fetchOne(
                    db,
                    sql: #"SELECT value FROM "source_baseline"."marker""#
                )
                #expect(throws: Error.self) {
                    try db.execute(
                        sql: #"UPDATE "source_baseline"."marker" SET value = 'forbidden'"#
                    )
                }
                try db.execute(sql: "UPDATE marker SET value = 'current edit'")
                return (
                    databasePaths,
                    try #require(referenceMarker),
                    resource.workspace.id
                )
        }

        #expect(
            URL(fileURLWithPath: try #require(observed.0["main"]))
                .standardizedFileURL
                == URL(fileURLWithPath: defaultDatabase.path).standardizedFileURL
        )
        #expect(
            URL(fileURLWithPath: try #require(observed.0["source_baseline"]))
                .standardizedFileURL
                == URL(fileURLWithPath: referenceDatabase.path).standardizedFileURL
        )
        #expect(observed.1 == "imported baseline")
        #expect(observed.2 == workspace.id)
        #expect(try marker(in: defaultDatabase) == "current edit")
        #expect(try marker(in: referenceDatabase.database) == "imported baseline")

        let parentMarker = try withDependencies {
            $0.defaultDatabase = defaultDatabase
        } operation: {
            @Dependency(\.defaultDatabase) var parentDatabase
            return try marker(in: parentDatabase)
        }
        #expect(parentMarker == "current edit")
    }

    @Test
    func sourceEditingSessionReusesTheExistingReferenceAttachment() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let defaultDatabase = try DatabasePool(
            path: directory.appending(path: "application.sqlite").path
        )
        let referenceDatabase = try defaultBaselineDatabase(
            path: directory.appending(path: "reference.sqlite").path
        )
        try setMarker("imported baseline", in: referenceDatabase.database)
        let sourceEditingSession = try SourceEditingSession(
            mainDatabase: defaultDatabase,
            baselineDatabasePath: referenceDatabase.path
        )

        // Opening the same authoring context again reuses its existing reference attachment.
        let reopenedSession = try SourceEditingSession(
            mainDatabase: sourceEditingSession.database,
            baselineDatabasePath: referenceDatabase.path
        )

        let databaseNames = try reopenedSession.database.read { db in
            try Row.fetchAll(db, sql: "PRAGMA database_list").map { row in
                row["name"] as String
            }
        }
        let referenceMarker = try baselineMarker(in: reopenedSession.database)
        expectNoDifference(databaseNames, ["main", SourceEditingSession.baselineSchemaName])
        expectNoDifference(referenceMarker, "imported baseline")
    }

    @Test
    func sourceEditingSessionRejectsADifferentReferenceAttachment() throws {
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
        let sourceEditingSession = try SourceEditingSession(
            mainDatabase: defaultDatabase,
            baselineDatabasePath: firstReferenceDatabase.path
        )

        #expect(throws: SourceEditingSessionError.self) {
            try SourceEditingSession(
                mainDatabase: sourceEditingSession.database,
                baselineDatabasePath: secondReferenceDatabase.path
            )
        }
    }

    @Test
    func stableReferenceAttachmentObservesAControlledBaselineRefresh() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let defaultDatabase = try DatabasePool(
            path: directory.appending(path: "application.sqlite").path
        )
        try setMarker("current edit", in: defaultDatabase)
        let referenceDatabase = try defaultBaselineDatabase(
            path: directory.appending(path: "reference.sqlite").path
        )
        try setMarker("old baseline", in: referenceDatabase.database)
        let sourceEditingSession = try SourceEditingSession(
            mainDatabase: defaultDatabase,
            baselineDatabasePath: referenceDatabase.path
        )

        #expect(try baselineMarker(in: sourceEditingSession.database) == "old baseline")
        let refreshedReferenceDatabase = try defaultBaselineDatabase(
            path: directory.appending(path: "refreshed-reference.sqlite").path
        )
        try setMarker("refreshed baseline", in: refreshedReferenceDatabase.database)
        try refreshedReferenceDatabase.database.backup(to: referenceDatabase.database)
        #expect(try baselineMarker(in: sourceEditingSession.database) == "refreshed baseline")
    }
}

private func setMarker(_ value: String, in database: any DatabaseWriter) throws {
    try database.write { db in
        try db.execute(sql: "CREATE TABLE marker (value TEXT NOT NULL)")
        try db.execute(sql: "INSERT INTO marker VALUES (?)", arguments: [value])
    }
}

private func marker(in database: any DatabaseWriter) throws -> String {
    try database.read { db in
        let value = try String.fetchOne(db, sql: "SELECT value FROM marker")
        return try #require(value)
    }
}

private func baselineMarker(in database: any DatabaseWriter) throws -> String {
    try database.read { db in
        let value = try String.fetchOne(
            db,
            sql: #"SELECT value FROM "source_baseline"."marker""#
        )
        return try #require(value)
    }
}
