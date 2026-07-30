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
                  sourceBaselineID TEXT,
                  publicRecord TEXT
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
                  sourceBaselineID TEXT,
                  publicRecord TEXT
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

    @Test
    func `existing workspace database opens without a downloaded reference`() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let workingDirectory = root
            .appending(path: "working", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )

        let appDatabase = try DatabaseQueue()
        try appDatabase.write { db in
            try db.execute(sql: """
                CREATE TABLE editingWorkspaces (
                  id TEXT PRIMARY KEY NOT NULL,
                  kind TEXT NOT NULL,
                  databaseFileName TEXT NOT NULL,
                  createdAt TEXT NOT NULL,
                  updatedAt TEXT NOT NULL,
                  sourceBaselineID TEXT,
                  publicRecord TEXT
                )
                """)
        }
        let workspace = EditingWorkspaceRecord(
            id: EditingWorkspaceRecord.ID(rawValue: "workspace-with-local-draft"),
            kind: .local,
            databaseFileName: "local-draft.sqlite",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        try appDatabase.write { db in
            try EditingWorkspaceRecord.insert { workspace }.execute(db)
        }

        let workingDatabase = try DatabasePool(
            path: workingDirectory.appending(path: workspace.databaseFileName).path
        )
        try workingDatabase.write { db in
            try db.execute(sql: "CREATE TABLE marker (value TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO marker VALUES ('persisted draft')")
        }
        let missingReference = WorkspaceReferenceDatabaseClient(
            url: { _, _ in root.appending(path: "missing-reference.sqlite") },
            prepare: { _, _ in
                throw WorkspaceReferenceDatabaseError.sourceBaselineMissing(workspace.id)
            },
            existing: { _, _ in nil }
        )

        let openedWorkspace = try withDependencies {
            $0.defaultDatabase = appDatabase
            $0.workspaceReferenceDatabase = missingReference
        } operation: {
            try SourceWorkspaceDatabaseClient
                .fileBacked(workingDirectory: workingDirectory)
                .workspace(workspace.id)
        }

        #expect(try marker(in: openedWorkspace.database) == "persisted draft")
        #expect(openedWorkspace.sourceEditingSession == nil)

        let referenceDatabase = try defaultBaselineDatabase(
            path: root.appending(path: "downloaded-reference.sqlite").path
        )
        try referenceDatabase.write { db in
            try db.execute(sql: "CREATE TABLE marker (value TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO marker VALUES ('downloaded baseline')")
        }
        let downloadedReference = WorkspaceReferenceDatabaseClient(
            url: { _, _ in URL(fileURLWithPath: referenceDatabase.path) },
            prepare: { _, _ in referenceDatabase },
            existing: { _, _ in referenceDatabase }
        )
        let upgradedWorkspace = try withDependencies {
            $0.defaultDatabase = appDatabase
            $0.workspaceReferenceDatabase = downloadedReference
        } operation: {
            try SourceWorkspaceDatabaseClient
                .fileBacked(workingDirectory: workingDirectory)
                .workspace(workspace.id)
        }

        #expect(try marker(in: upgradedWorkspace.database) == "persisted draft")
        #expect(upgradedWorkspace.sourceEditingSession != nil)
    }

    @Test
    func `workspace context keeps app database mounted with its reference attached`() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let appDatabase = try DatabaseQueue(path: root.appending(path: "app.sqlite").path)
        let workingDatabasePath = root.appending(path: "working.sqlite").path
        let referenceDatabasePath = root.appending(path: "reference.sqlite").path
        let workingDatabase = try DatabasePool(path: workingDatabasePath)
        let referenceDatabase = try DatabasePool(path: referenceDatabasePath)

        let seededDatabases: [(any DatabaseWriter, String)] = [
            (appDatabase, "app"),
            (workingDatabase, "working"),
            (referenceDatabase, "reference"),
        ]
        for (database, value) in seededDatabases {
            try database.write { db in
                try db.execute(sql: "CREATE TABLE marker (value TEXT NOT NULL)")
                try db.execute(sql: "INSERT INTO marker VALUES (?)", arguments: [value])
            }
        }

        let session = try SourceEditingSession(
            workingDatabasePath: workingDatabasePath,
            baselineDatabasePath: referenceDatabasePath,
            baselineSchemaName: "mounted_reference"
        )
        let workspace = WorkspaceContext(
            id: EditingWorkspaceRecord.ID(rawValue: "mounted-reference"),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(sourceEditingSession: session)
        )

        let mountedValues = try withDependencies {
            $0.defaultDatabase = appDatabase
            $0.useWorkspaceContext(
                workspace.mounting(grant: .init(value: nil))
            )
        } operation: {
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.sourceEditingSession) var mountedSourceEditingSession
            let sourceEditingSession = try #require(mountedSourceEditingSession)

            return try database.read { db in
                let appValue = try #require(
                    try String.fetchOne(db, sql: "SELECT value FROM marker")
                )
                let referenceValue = try sourceEditingSession.withAttachedBaseline(to: db) { schemaName in
                    #expect(schemaName == "mounted_reference")
                    return try #require(
                        try String.fetchOne(
                            db,
                            sql: "SELECT value FROM mounted_reference.marker"
                        )
                    )
                }
                return [appValue, referenceValue]
            }
        }

        expectNoDifference(mountedValues, ["app", "reference"])
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
