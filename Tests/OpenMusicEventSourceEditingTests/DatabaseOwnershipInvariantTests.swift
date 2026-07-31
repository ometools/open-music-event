import CustomDump
import Dependencies
import Foundation
import GRDB
import OpenMusicEventSourceEditing
import Sharing
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
    func workspaceContextPreservesTheRootDefaultDatabase() throws {
        let defaultDatabase = try DatabaseQueue()
        try setMarker("populated default", in: defaultDatabase)
        let workspaceID = EditingWorkspaceRecord.ID(rawValue: "workspace")
        let grant = AuthoringGrant(
            principal: .local,
            role: .owner,
            workspaceID: workspaceID
        )

        let observed = try withDependencies {
            $0.defaultDatabase = defaultDatabase
            $0.useAuthoringContext(
                workspaceID,
                grant: SharedReader(value: Optional(grant))
            )
        } operation: {
            @Dependency(\.defaultDatabase) var inheritedDatabase
            @Dependency(\.editingWorkspaceID) var inheritedWorkspaceID
            return (
                try marker(in: inheritedDatabase),
                inheritedWorkspaceID
            )
        }

        #expect(observed.0 == "populated default")
        #expect(observed.1 == workspaceID)
    }

    @Test
    func defaultAndReadOnlyReferenceAreReadableTogetherAndAlwaysDetach() throws {
        let defaultDatabase = try DatabaseQueue()
        try setMarker("current edit", in: defaultDatabase)
        let referenceDatabase = try defaultBaselineDatabase()
        defer { try? FileManager.default.removeItem(atPath: referenceDatabase.path) }
        try referenceDatabase.write { db in
            try db.execute(sql: "CREATE TABLE marker (value TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO marker VALUES ('imported baseline')")
        }

        try defaultDatabase.writeWithoutTransaction { db in
            let values = try referenceDatabase.withAttached(to: db) { schemaName in
                let defaultValue = try String.fetchOne(db, sql: "SELECT value FROM marker")
                let referenceValue = try String.fetchOne(
                    db,
                    sql: #"SELECT value FROM "\#(schemaName)"."marker""#
                )
                return (
                    try #require(defaultValue),
                    try #require(referenceValue)
                )
            }
            #expect(values.0 == "current edit")
            #expect(values.1 == "imported baseline")

            #expect(throws: Error.self) {
                try referenceDatabase.withAttached(to: db) { schemaName in
                    try db.execute(
                        sql: #"UPDATE "\#(schemaName)"."marker" SET value = 'forbidden'"#
                    )
                }
            }

            expectNoDifference(
                try String.fetchAll(db, sql: "SELECT name FROM pragma_database_list"),
                ["main"]
            )
        }
        #expect(try marker(in: defaultDatabase) == "current edit")
        #expect(try marker(in: referenceDatabase.database) == "imported baseline")
    }

    @Test
    func referenceAttachmentRejectsAnExistingTransaction() throws {
        let defaultDatabase = try DatabaseQueue()
        let referenceDatabase = try defaultBaselineDatabase()
        defer { try? FileManager.default.removeItem(atPath: referenceDatabase.path) }

        try defaultDatabase.write { db in
            #expect(throws: SourceBaselineDatabaseAttachmentError.activeTransaction) {
                try referenceDatabase.withAttached(to: db) { _ in }
            }
            expectNoDifference(
                try String.fetchAll(db, sql: "SELECT name FROM pragma_database_list"),
                ["main"]
            )
        }
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
