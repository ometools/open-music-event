import CustomDump
import Dependencies
import Foundation
import GRDB
import SourceEditing
import SQLiteData
import Testing

@Table("todos")
private struct Todo: Equatable, Sendable, Identifiable, SourceEditableTable {
    @Column(primaryKey: true) var id: Int
    var listID: String
    var title: String
    var note: String?
    var localCache: String?

    static var sourceIgnoredColumnNames: Set<String> {
        ["localCache"]
    }

    static var sourceDisplayName: String {
        "Todo"
    }
}

private struct TodoAttachment: Codable, Equatable, Sendable {
    var label: String
    var rank: Int
}

@Table("typed_todos")
private struct TypedTodo: Equatable, Sendable, Identifiable, SourceEditableTable {
    @Column(primaryKey: true) var id: Int
    @Column(as: TodoAttachment.JSONRepresentation.self) var attachment: TodoAttachment
}

@Suite
struct SourceEditingTests {
    @Test
    func descriptorDerivesTableMetadata() {
        expectNoDifference(
            Todo.sourceDescriptor,
            SourceTableDescriptor(
                id: "todos",
                tableName: "todos",
                primaryKeyColumns: ["id"],
                comparedColumns: ["listID", "title", "note"],
                resetColumnNames: ["id", "listID", "title", "note", "localCache"],
                displayName: "Todo"
            )
        )
    }

    @Test
    func summaryCountsAddedModifiedAndDeletedRowsInsideScope() throws {
        let fixture = try SourceEditingFixture()
        try fixture.updateWorking(id: 2, title: "New title")
        try fixture.deleteWorking(id: 3)
        try fixture.updateWorking(id: 4, localCache: "new")
        try fixture.updateWorking(id: 5, title: "Other list changed")
        try fixture.insertWorking(Todo(id: 6, listID: "list-1", title: "Added", note: nil, localCache: nil))

        let summary = try fixture.summary(scope: listScope("list-1"))

        expectNoDifference(
            summary,
            SourceChangeSummary(
                availability: .available,
                groups: [
                    SourceChangeGroup(
                        id: "todos",
                        displayName: "Todo",
                        added: 1,
                        modified: 1,
                        deleted: 1,
                        records: [
                            SourceRecordChange(
                                kind: .added,
                                primaryKeyValues: [
                                    sourceColumnValue("id", 6.databaseValue)
                                ],
                                fieldChanges: [
                                    sourceFieldChange("listID", workingValue: "list-1".databaseValue),
                                    sourceFieldChange("title", workingValue: "Added".databaseValue),
                                    sourceFieldChange("note", workingValue: .null),
                                ]
                            ),
                            SourceRecordChange(
                                kind: .modified,
                                primaryKeyValues: [
                                    sourceColumnValue("id", 2.databaseValue)
                                ],
                                fieldChanges: [
                                    sourceFieldChange(
                                        "title",
                                        baselineValue: "Old title".databaseValue,
                                        workingValue: "New title".databaseValue
                                    )
                                ]
                            ),
                            SourceRecordChange(
                                kind: .deleted,
                                primaryKeyValues: [
                                    sourceColumnValue("id", 3.databaseValue)
                                ],
                                fieldChanges: [
                                    sourceFieldChange("listID", baselineValue: "list-1".databaseValue),
                                    sourceFieldChange("title", baselineValue: "Deleted candidate".databaseValue),
                                    sourceFieldChange("note", baselineValue: .null),
                                ]
                            ),
                        ]
                    )
                ]
            )
        )
        #expect(summary.totalCount == 3)
    }

    @Test
    func nullValuesCompareAsUnchanged() throws {
        let fixture = try SourceEditingFixture()

        let summary = try fixture.summary(scope: listScope("list-1"))

        expectNoDifference(
            summary.groups,
            [
                SourceChangeGroup(
                    id: "todos",
                    displayName: "Todo",
                    added: 0,
                    modified: 0,
                    deleted: 0
                )
            ]
        )
        #expect(summary.totalCount == 0)
    }

    @Test
    func nullAndNonNullValuesCompareAsModified() throws {
        let fixture = try SourceEditingFixture()
        try fixture.updateWorking(id: 1, note: "Updated")

        let summary = try fixture.summary(scope: listScope("list-1"))

        #expect(summary.groups.first?.modified == 1)
        #expect(summary.totalCount == 1)
        let group = try #require(summary.groups.first)
        let record = try #require(group.records.first)
        expectNoDifference(
            record.fieldChanges,
            [
                sourceFieldChange(
                    "note",
                    baselineValue: .null,
                    workingValue: "Updated".databaseValue
                )
            ]
        )
    }

    @Test
    func recordTypesRenderTypedDiffs() throws {
        let fixture = try SourceEditingFixture()
        try fixture.updateWorking(
            id: 2,
            title: "New title",
            localCache: "Hidden cache"
        )

        let summary = try fixture.typedSummary(scope: listScope("list-1"))

        let group = try #require(summary.groups.first)
        let record = try #require(group.records.first)
        #expect(record.recordDiff?.contains("Old title") == true)
        #expect(record.recordDiff?.contains("New title") == true)
        #expect(record.recordDiff?.contains("Hidden cache") == false)
        #expect(record.recordDiff?.contains("localCache") == false)
    }

    @Test
    func recordTypesExposeTypedLeftRightComparisons() throws {
        let fixture = try SourceEditingFixture()
        try fixture.updateWorking(id: 2, title: "New title")
        try fixture.deleteWorking(id: 3)
        try fixture.insertWorking(Todo(id: 6, listID: "list-1", title: "Added", note: nil, localCache: nil))

        let summary = try fixture.typedSummary(scope: listScope("list-1"))

        let group = try #require(summary.groups.first)
        let addedRecord = try #require(group.records.first { $0.kind == .added })
        let addedComparison = try #require(summary.recordComparisons[addedRecord]?.as(Todo.self))
        #expect(addedComparison.left == nil)
        #expect(addedComparison.right?.title == "Added")

        let modifiedRecord = try #require(group.records.first { $0.kind == .modified })
        let modifiedComparison = try #require(summary.recordComparisons[modifiedRecord]?.as(Todo.self))
        #expect(modifiedComparison.left?.title == "Old title")
        #expect(modifiedComparison.right?.title == "New title")

        let deletedRecord = try #require(group.records.first { $0.kind == .deleted })
        let deletedComparison = try #require(summary.recordComparisons[deletedRecord]?.as(Todo.self))
        #expect(deletedComparison.left?.title == "Deleted candidate")
        #expect(deletedComparison.right == nil)
    }

    @Test
    func recordTypesDiffDecodedJSONColumns() throws {
        let fixture = try SourceEditingFixture()
        try fixture.createTypedTodosTable()
        let record = TypedTodo(
            id: 1,
            attachment: TodoAttachment(label: "Before label", rank: 1)
        )
        try fixture.insertWorking(record)
        try fixture.insertBaseline(record)
        try fixture.updateWorkingTypedTodoAttachment(
            id: 1,
            attachment: TodoAttachment(label: "After label", rank: 1)
        )

        let summary = try fixture.typedTodoSummary()

        let group = try #require(summary.groups.first)
        let changedRecord = try #require(group.records.first)
        let recordDiff = try #require(changedRecord.recordDiff)
        #expect(recordDiff.contains("Before label"))
        #expect(recordDiff.contains("After label"))
        #expect(recordDiff.contains("TodoAttachment"))
        #expect(!recordDiff.contains(#"{"label""#))
    }

    @Test
    func recordTypesKeepRawChangesWhenTypedDiffCannotDecodeChangedRow() throws {
        let fixture = try SourceEditingFixture()
        try fixture.createTypedTodosTable()
        let record = TypedTodo(
            id: 1,
            attachment: TodoAttachment(label: "Before label", rank: 1)
        )
        try fixture.insertWorking(record)
        try fixture.insertBaseline(record)

        let malformedAttachment = #"{"label":"Broken""#
        try fixture.updateWorkingTypedTodoAttachmentRaw(
            id: 1,
            attachment: malformedAttachment
        )

        let summary = try fixture.typedTodoSummary()

        let group = try #require(summary.groups.first)
        #expect(group.modified == 1)
        #expect(summary.totalCount == 1)

        let changedRecord = try #require(group.records.first)
        #expect(changedRecord.kind == .modified)
        expectNoDifference(
            changedRecord.primaryKeyValues,
            [
                sourceColumnValue("id", 1.databaseValue)
            ]
        )
        #expect(changedRecord.recordDiff == nil)

        let fieldChange = try #require(changedRecord.fieldChanges.first)
        #expect(fieldChange.columnName == "attachment")
        #expect(fieldChange.workingValue == malformedAttachment.databaseValue)
    }

    @Test
    func recordTypeResolversCanSuppressCandidateChangesAndRecomputeCounts() throws {
        let fixture = try SourceEditingFixture()
        try fixture.updateWorking(id: 2, title: "New title")

        let summary = try fixture.typedSummary(
            recordTypes: [
                AnySourceEditableRecordType(
                    descriptor: Todo.sourceDescriptor,
                    resolveRecordChange: { _, _, _ in nil }
                )
            ],
            scope: listScope("list-1")
        )

        expectNoDifference(
            summary.groups,
            [
                SourceChangeGroup(
                    id: "todos",
                    displayName: "Todo",
                    added: 0,
                    modified: 0,
                    deleted: 0
                )
            ]
        )
        #expect(summary.totalCount == 0)
    }

    @Test
    func schemaMismatchReturnsUnavailableSummary() throws {
        let fixture = try SourceEditingFixture(createBaselineTable: false)
        try fixture.createBaselineTable(columns: [
            #""id" INTEGER PRIMARY KEY NOT NULL"#,
            #""listID" TEXT NOT NULL"#,
            #""note" TEXT"#,
            #""localCache" TEXT"#,
        ])

        let summary = try fixture.summary(scope: listScope("list-1"))

        expectNoDifference(
            summary,
            SourceChangeSummary(
                availability: .unavailable(
                    .schemaMismatch([
                        SourceSchemaMismatch(
                            role: .baseline,
                            tableName: "todos",
                            missingColumnNames: ["title"]
                        )
                    ])
                ),
                groups: []
            )
        )
    }

    @Test
    func sessionUsesAttachedBaselineForSummariesAndWrites() throws {
        let fixture = try SourceEditingFixture()
        let session = try SourceEditingSession(
            workingDatabasePath: fixture.workingDatabasePath,
            baselineDatabasePath: fixture.baselineDatabase.path
        )

        try session.database.write { db in
            try Todo
                .find(2)
                .update { $0.title = "Changed through session" }
                .execute(db)
        }

        let summary = try withDependencies {
            $0.defaultDatabase = session.database
            $0.sourceEditingSession = session
        } operation: {
            try SourceEditingComparer().summary(
                descriptors: [Todo.sourceDescriptor],
                scope: listScope("list-1")
            )
        }

        expectNoDifference(
            summary,
            SourceChangeSummary(
                availability: .available,
                groups: [
                    SourceChangeGroup(
                        id: "todos",
                        displayName: "Todo",
                        added: 0,
                        modified: 1,
                        deleted: 0,
                        records: [
                            SourceRecordChange(
                                kind: .modified,
                                primaryKeyValues: [
                                    sourceColumnValue("id", 2.databaseValue)
                                ],
                                fieldChanges: [
                                    sourceFieldChange(
                                        "title",
                                        baselineValue: "Old title".databaseValue,
                                        workingValue: "Changed through session".databaseValue
                                    )
                                ]
                            )
                        ]
                    )
                ]
            )
        )
    }

    @Test
    func sessionAttachesBaselineReadOnly() throws {
        let fixture = try SourceEditingFixture()
        let session = try SourceEditingSession(
            workingDatabasePath: fixture.workingDatabasePath,
            baselineDatabasePath: fixture.baselineDatabase.path
        )

        try session.database.write { db in
            try Todo
                .find(2)
                .update { $0.title = "Working write succeeds" }
                .execute(db)
        }

        #expect(throws: Error.self) {
            try session.database.write { db in
                try #sql(
                    """
                    UPDATE "source_baseline"."todos"
                    SET "title" = 'Baseline write should fail'
                    WHERE "id" = 2
                    """
                )
                .execute(db)
            }
        }
    }

    @Test
    func sessionResetRestoresScopedChangesFromBaseline() throws {
        let fixture = try SourceEditingFixture()
        let session = try SourceEditingSession(
            workingDatabasePath: fixture.workingDatabasePath,
            baselineDatabasePath: fixture.baselineDatabase.path
        )

        try fixture.updateWorking(id: 2, title: "Changed through session")
        try fixture.deleteWorking(id: 3)
        try fixture.updateWorking(id: 4, localCache: "new local cache")
        try fixture.updateWorking(id: 5, title: "Other list changed")
        try fixture.insertWorking(
            Todo(
                id: 6,
                listID: "list-1",
                title: "Added",
                note: nil,
                localCache: "added local cache"
            )
        )

        try session.reset(
            descriptors: [Todo.sourceDescriptor],
            scope: listScope("list-1")
        )

        let summary = try withDependencies {
            $0.defaultDatabase = session.database
            $0.sourceEditingSession = session
        } operation: {
            try SourceEditingComparer().summary(
                descriptors: [Todo.sourceDescriptor],
                scope: listScope("list-1")
            )
        }
        expectNoDifference(
            summary,
            SourceChangeSummary(
                availability: .available,
                groups: [
                    SourceChangeGroup(
                        id: "todos",
                        displayName: "Todo",
                        added: 0,
                        modified: 0,
                        deleted: 0
                    )
                ]
            )
        )

        let listOneRecords = try session.database.read { db in
            try Todo
                .where { $0.listID.eq("list-1") }
                .fetchAll(db)
                .sorted { $0.id < $1.id }
        }
        expectNoDifference(
            listOneRecords,
            [
                Todo(id: 1, listID: "list-1", title: "Title", note: nil, localCache: nil),
                Todo(id: 2, listID: "list-1", title: "Old title", note: nil, localCache: nil),
                Todo(id: 3, listID: "list-1", title: "Deleted candidate", note: nil, localCache: nil),
                Todo(id: 4, listID: "list-1", title: "Ignored cache", note: nil, localCache: "new local cache"),
            ]
        )

        let otherListRecord = try #require(
            try session.database.read { db in
                try Todo.find(5).fetchOne(db)
            }
        )
        expectNoDifference(
            otherListRecord,
            Todo(id: 5, listID: "list-2", title: "Other list changed", note: nil, localCache: nil)
        )
    }
}

private final class SourceEditingFixture {
    let workingDatabasePath: String
    let workingDatabase: any DatabaseWriter
    let baselineDatabase: SourceBaselineDatabase

    init(createBaselineTable: Bool = true) throws {
        self.workingDatabasePath = FileManager.default.temporaryDirectory
            .appending(path: "SourceEditingTests-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
            .path
        self.workingDatabase = try DatabasePool(path: workingDatabasePath)
        self.baselineDatabase = try defaultBaselineDatabase()

        try workingDatabase.write { db in
            try createTodosTable(in: db)
        }
        if createBaselineTable {
            try baselineDatabase.write { db in
                try createTodosTable(in: db)
            }
        }

        try insertWorking(Self.records)
        if createBaselineTable {
            try insertBaseline(Self.records)
        }
    }

    deinit {
        try? FileManager.default.removeItem(atPath: workingDatabasePath)
        try? FileManager.default.removeItem(atPath: baselineDatabase.path)
    }

    static var records: [Todo] {
        [
            Todo(id: 1, listID: "list-1", title: "Title", note: nil, localCache: nil),
            Todo(id: 2, listID: "list-1", title: "Old title", note: nil, localCache: nil),
            Todo(id: 3, listID: "list-1", title: "Deleted candidate", note: nil, localCache: nil),
            Todo(id: 4, listID: "list-1", title: "Ignored cache", note: nil, localCache: "old"),
            Todo(id: 5, listID: "list-2", title: "Other list", note: nil, localCache: nil),
        ]
    }

    func createBaselineTable(columns: [String]) throws {
        try baselineDatabase.write { db in
            let columnDefinitions = columns.joined(separator: ", ")
            try SQLQueryExpression(
                """
                CREATE TABLE "todos" (
                  \(raw: columnDefinitions)
                ) STRICT
                """
            )
            .execute(db)
        }
    }

    func insertWorking(_ records: [Todo]) throws {
        try workingDatabase.write { db in
            try Todo.insert { records }.execute(db)
        }
    }

    func insertWorking(_ record: Todo) throws {
        try insertWorking([record])
    }

    func insertWorking(_ record: TypedTodo) throws {
        try workingDatabase.write { db in
            try TypedTodo.insert { record }.execute(db)
        }
    }

    func insertBaseline(_ records: [Todo]) throws {
        try baselineDatabase.write { db in
            try Todo.insert { records }.execute(db)
        }
    }

    func insertBaseline(_ record: TypedTodo) throws {
        try baselineDatabase.write { db in
            try TypedTodo.insert { record }.execute(db)
        }
    }

    func updateWorking(
        id: Todo.ID,
        title: String? = nil,
        note: String? = nil,
        localCache: String? = nil
    ) throws {
        try workingDatabase.write { db in
            var record = try Todo.find(id).fetchOne(db)!
            if let title {
                record.title = title
            }
            if let note {
                record.note = note
            }
            if let localCache {
                record.localCache = localCache
            }
            try Todo.update(record).execute(db)
        }
    }

    func deleteWorking(id: Todo.ID) throws {
        try workingDatabase.write { db in
            try Todo.find(id).delete().execute(db)
        }
    }

    func createTypedTodosTable() throws {
        try workingDatabase.write { db in
            try createTypedTodosSQLTable(in: db)
        }
        try baselineDatabase.write { db in
            try createTypedTodosSQLTable(in: db)
        }
    }

    func updateWorkingTypedTodoAttachment(
        id: TypedTodo.ID,
        attachment: TodoAttachment
    ) throws {
        try workingDatabase.write { db in
            var record = try TypedTodo.find(id).fetchOne(db)!
            record.attachment = attachment
            try TypedTodo.update(record).execute(db)
        }
    }

    func updateWorkingTypedTodoAttachmentRaw(
        id: TypedTodo.ID,
        attachment: String
    ) throws {
        try workingDatabase.write { db in
            try db.execute(
                sql: #"UPDATE "typed_todos" SET "attachment" = ? WHERE "id" = ?"#,
                arguments: [attachment, id]
            )
        }
    }

    func summary(scope: SourceRecordScope = .all) throws -> SourceChangeSummary {
        try withDependencies {
            $0.defaultDatabase = workingDatabase
            $0.defaultBaselineDatabase = baselineDatabase
        } operation: {
            try SourceEditingComparer().summary(
                descriptors: [Todo.sourceDescriptor],
                scope: scope
            )
        }
    }

    func typedSummary(
        recordTypes: [AnySourceEditableRecordType] = [Todo.sourceRecordType],
        scope: SourceRecordScope = .all
    ) throws -> SourceChangeSummary {
        try withDependencies {
            $0.defaultDatabase = workingDatabase
            $0.defaultBaselineDatabase = baselineDatabase
        } operation: {
            try SourceEditingComparer().summary(
                recordTypes: recordTypes,
                scope: scope
            )
        }
    }

    func typedTodoSummary(scope: SourceRecordScope = .all) throws -> SourceChangeSummary {
        try withDependencies {
            $0.defaultDatabase = workingDatabase
            $0.defaultBaselineDatabase = baselineDatabase
        } operation: {
            try SourceEditingComparer().summary(
                recordTypes: [TypedTodo.sourceRecordType],
                scope: scope
            )
        }
    }
}

private func createTodosTable(in db: Database) throws {
    try #sql("""
        CREATE TABLE "todos" (
          "id" INTEGER PRIMARY KEY NOT NULL,
          "listID" TEXT NOT NULL,
          "title" TEXT NOT NULL,
          "note" TEXT,
          "localCache" TEXT
        ) STRICT
        """)
        .execute(db)
}

private func createTypedTodosSQLTable(in db: Database) throws {
    try #sql("""
        CREATE TABLE "typed_todos" (
          "id" INTEGER PRIMARY KEY NOT NULL,
          "attachment" TEXT NOT NULL
        ) STRICT
        """)
        .execute(db)
}

private func listScope(_ listID: String) -> SourceRecordScope {
    SourceRecordScope(
        filters: [
            SourceRecordScope.Filter(
                columnName: "listID",
                value: listID.queryBinding
            )
        ]
    )
}

private func sourceColumnValue(
    _ columnName: String,
    _ value: DatabaseValue
) -> SourceColumnValue {
    SourceColumnValue(
        columnName: columnName,
        value: value
    )
}

private func sourceFieldChange(
    _ columnName: String,
    baselineValue: DatabaseValue? = nil,
    workingValue: DatabaseValue? = nil
) -> SourceFieldChange {
    SourceFieldChange(
        columnName: columnName,
        baselineValue: baselineValue,
        workingValue: workingValue
    )
}
