import CustomDump
import Dependencies
import Foundation
import GRDB
import OpenMusicEventSourceEditing
import Sharing
import SourceEditing
import Testing

@Suite
struct DatabaseOwnershipInvariantTests {
    @Test
    func workspaceSourcePreparationIsSingleFlight() async throws {
        let database = try DatabaseQueue()
        try await database.write { db in
            try db.execute(sql: """
                CREATE TABLE editingWorkspaces (
                  id TEXT PRIMARY KEY NOT NULL,
                  kind TEXT NOT NULL,
                  referenceDatabaseFileName TEXT NOT NULL,
                  createdAt TEXT NOT NULL,
                  updatedAt TEXT NOT NULL,
                  sourceBaselineID TEXT,
                  publicRecord TEXT
                )
                """)
        }
        let sourceBaselineID = SourceBaselineRecord.ID(rawValue: "single-flight-source")
        let workspace = EditingWorkspaceRecord(
            id: EditingWorkspaceRecord.ID(sourceBaselineID: sourceBaselineID),
            kind: .team,
            referenceDatabaseFileName: "reference.sqlite",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            sourceBaselineID: sourceBaselineID
        )
        try await database.write { db in
            try EditingWorkspaceRecord.insert { workspace }.execute(db)
        }
        let preparationGate = WorkspaceSourcePreparationGate()
        let secondCallerGate = TaskStartGate()

        try await withDependencies {
            $0.defaultDatabase = database
            $0.sourceEditModePreparation = SourceEditModePreparationClient { sourceBaselineID in
                await preparationGate.prepare(sourceBaselineID)
            }
            $0[WorkspacePreparationClient.self] = .live
        } operation: {
            @Dependency(WorkspacePreparationClient.self) var preparation
            let prepareSource = preparation.prepareSource
            let first = Task {
                try await prepareSource(workspace.id)
            }
            let recordedSourceBaselineIDs = await preparationGate.waitForPreparationToStart()
            let second = Task {
                await secondCallerGate.start()
                try await prepareSource(workspace.id)
            }

            expectNoDifference(recordedSourceBaselineIDs, [sourceBaselineID])
            await secondCallerGate.waitForStart()
            await Task.yield()
            await preparationGate.finish()
            try await first.value
            try await second.value
            let completedSourceBaselineIDs = await preparationGate.sourceBaselineIDs
            expectNoDifference(completedSourceBaselineIDs, [sourceBaselineID])
        }
    }

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
        let workspaceID = EditingWorkspaceRecord.ID(rawValue: "workspace")
        let workspaceDatabase = try SourceWorkspaceDatabase(
            workspaceID: workspaceID,
            mainDatabase: defaultDatabase,
            referenceDatabase: referenceDatabase
        )

        let observed = try workspaceDatabase.database.write { db in
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
                    workspaceDatabase.workspaceID
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
        #expect(observed.2 == workspaceID)
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
        let workspaceDatabase = try SourceWorkspaceDatabase(
            workspaceID: EditingWorkspaceRecord.ID(rawValue: "workspace"),
            mainDatabase: defaultDatabase,
            referenceDatabase: referenceDatabase
        )

        #expect(try baselineMarker(in: workspaceDatabase.database) == "old baseline")
        let refreshedReferenceDatabase = try defaultBaselineDatabase(
            path: directory.appending(path: "refreshed-reference.sqlite").path
        )
        try setMarker("refreshed baseline", in: refreshedReferenceDatabase.database)
        try refreshedReferenceDatabase.database.backup(to: referenceDatabase.database)
        #expect(try baselineMarker(in: workspaceDatabase.database) == "refreshed baseline")
    }

    @Test
    func missingLocalReferenceIsReportedWithoutCreatingADatabase() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = EditingWorkspaceRecord(
            id: EditingWorkspaceRecord.ID(rawValue: "missing-reference"),
            kind: .local,
            referenceDatabaseFileName: "missing.sqlite",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let client = WorkspaceReferenceDatabaseClient.fileBacked(
            localReferenceDirectory: root
        )

        #expect(try client.existing(workspace) == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "missing.sqlite").path))
    }
}

private actor WorkspaceSourcePreparationGate {
    private var isFinished = false
    private(set) var sourceBaselineIDs: [SourceBaselineRecord.ID] = []
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<[SourceBaselineRecord.ID], Never>] = []

    func prepare(_ sourceBaselineID: SourceBaselineRecord.ID) async {
        sourceBaselineIDs.append(sourceBaselineID)
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume(returning: sourceBaselineIDs) }
        guard !isFinished else { return }
        await withCheckedContinuation { continuation in
            finishWaiters.append(continuation)
        }
    }

    func waitForPreparationToStart() async -> [SourceBaselineRecord.ID] {
        if !sourceBaselineIDs.isEmpty { return sourceBaselineIDs }
        return await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finish() {
        isFinished = true
        let waiters = finishWaiters
        finishWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor TaskStartGate {
    private var hasStarted = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func start() {
        hasStarted = true
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }

    func waitForStart() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
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
