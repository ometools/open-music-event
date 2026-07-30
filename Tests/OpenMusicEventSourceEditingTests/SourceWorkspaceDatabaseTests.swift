import Dependencies
import CustomDump
import Foundation
import GRDB
import OpenMusicEventSourceEditing
import Testing

@Suite
struct SourceWorkspaceDatabaseTests {
    @Test
    func `workspace source preparation is single flight`() async throws {
        let database = try DatabaseQueue()
        try await database.write { db in
            try db.execute(sql: """
                CREATE TABLE editingWorkspaces (
                  id TEXT PRIMARY KEY NOT NULL,
                  kind TEXT NOT NULL,
                  databaseFileName TEXT NOT NULL,
                  createdAt TEXT NOT NULL,
                  updatedAt TEXT NOT NULL,
                  sourceBaselineID TEXT
                )
                """)
        }
        let sourceBaselineID = SourceBaselineRecord.ID(rawValue: "single-flight-source")
        let workspace = EditingWorkspaceRecord(
            id: EditingWorkspaceRecord.ID(sourceBaselineID: sourceBaselineID),
            kind: .team,
            databaseFileName: "reference.sqlite",
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
            expectNoDifference(
                completedSourceBaselineIDs,
                [sourceBaselineID]
            )
        }
    }

    @Test
    func `file backed workspace databases are isolated from the app and each other`() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let referenceDirectory = root
            .appending(path: "references", directoryHint: .isDirectory)
        let workingDirectory = root
            .appending(path: "working", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let appDatabase = try DatabaseQueue()
        try appDatabase.write { db in
            try db.execute(sql: """
                CREATE TABLE editingWorkspaces (
                  id TEXT PRIMARY KEY NOT NULL,
                  kind TEXT NOT NULL,
                  databaseFileName TEXT NOT NULL,
                  createdAt TEXT NOT NULL,
                  updatedAt TEXT NOT NULL,
                  sourceBaselineID TEXT
                )
                """)
        }

        let workspaceA = EditingWorkspaceRecord(
            id: EditingWorkspaceRecord.ID(rawValue: "workspace-a"),
            kind: .local,
            databaseFileName: "workspace-a.sqlite",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let workspaceB = EditingWorkspaceRecord(
            id: EditingWorkspaceRecord.ID(rawValue: "workspace-b"),
            kind: .local,
            databaseFileName: "workspace-b.sqlite",
            createdAt: Date(timeIntervalSince1970: 2),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        try appDatabase.write { db in
            try EditingWorkspaceRecord.insert { workspaceA }.execute(db)
            try EditingWorkspaceRecord.insert { workspaceB }.execute(db)
        }

        let referenceClient = WorkspaceReferenceDatabaseClient.fileBacked(
            localReferenceDirectory: referenceDirectory
        )
        let (referenceA, referenceB) = try withDependencies {
            $0.defaultDatabase = appDatabase
            $0.sourceReferenceDatabaseMigrator = .noop
        } operation: {
            (
                try referenceClient.prepare(workspaceA),
                try referenceClient.prepare(workspaceB)
            )
        }
        try referenceA.write { db in
            try db.execute(sql: "CREATE TABLE marker (value TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO marker VALUES ('A')")
        }
        try referenceB.write { db in
            try db.execute(sql: "CREATE TABLE marker (value TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO marker VALUES ('B')")
        }

        let databaseClient = SourceWorkspaceDatabaseClient.fileBacked(
            workingDirectory: workingDirectory
        )
        let (databaseA, databaseB) = try withDependencies {
            $0.defaultDatabase = appDatabase
            $0.sourceReferenceDatabaseMigrator = .noop
            $0.workspaceReferenceDatabase = referenceClient
        } operation: {
            (
                try databaseClient.workspace(workspaceA.id),
                try databaseClient.workspace(workspaceB.id)
            )
        }

        #expect(try marker(in: databaseA.database) == "A")
        #expect(try marker(in: databaseB.database) == "B")
        #expect(throws: (any Error).self) {
            try marker(in: appDatabase)
        }

        try databaseA.database.write { db in
            try db.execute(sql: "UPDATE marker SET value = 'A draft'")
        }
        #expect(try marker(in: databaseA.database) == "A draft")
        #expect(try marker(in: databaseB.database) == "B")
        #expect(try marker(in: referenceA.database) == "A")
    }

    private func marker(in database: any DatabaseReader) throws -> String? {
        try database.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM marker")
        }
    }
}

private actor TaskStartGate {
    private var hasStarted = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func start() {
        hasStarted = true
        let waiters = waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitForStart() async {
        if hasStarted { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor WorkspaceSourcePreparationGate {
    private(set) var sourceBaselineIDs: [SourceBaselineRecord.ID] = []
    private var isFinished = false
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<[SourceBaselineRecord.ID], Never>] = []

    func finish() {
        isFinished = true
        let waiters = finishWaiters
        finishWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

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
        if !sourceBaselineIDs.isEmpty {
            return sourceBaselineIDs
        }
        return await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }
}
