import CustomDump
import Dependencies
import Foundation
import SourceEditing
import SQLiteData
import Testing

@Table("sourceRecords")
private struct SourceRecord: Equatable, Sendable, Identifiable, SourceEditableTable {
    @Column(primaryKey: true) var id: Int
    var eventID: String
    var title: String
    var note: String?
    var localCache: String?

    static var sourceIgnoredColumnNames: Set<String> {
        ["localCache"]
    }

    static var sourceDisplayName: String {
        "Source Record"
    }
}

@Suite
struct SourceEditingTests {
    @Test
    func descriptorDerivesTableMetadata() {
        expectNoDifference(
            SourceRecord.sourceDescriptor,
            SourceTableDescriptor(
                id: "sourceRecords",
                tableName: "sourceRecords",
                primaryKeyColumns: ["id"],
                comparedColumns: ["eventID", "title", "note"],
                displayName: "Source Record"
            )
        )
    }

    @Test
    func summaryCountsAddedModifiedAndDeletedRowsInsideScope() throws {
        let fixture = try SourceEditingFixture()
        try fixture.updateWorking(id: 2, title: "New title")
        try fixture.deleteWorking(id: 3)
        try fixture.updateWorking(id: 4, localCache: "new")
        try fixture.updateWorking(id: 5, title: "Other event changed")
        try fixture.insertWorking(SourceRecord(id: 6, eventID: "event-1", title: "Added", note: nil, localCache: nil))

        let summary = try fixture.summary(scope: eventScope("event-1"))

        expectNoDifference(
            summary,
            SourceChangeSummary(
                availability: .available,
                groups: [
                    SourceChangeGroup(
                        id: "sourceRecords",
                        displayName: "Source Record",
                        added: 1,
                        modified: 1,
                        deleted: 1
                    )
                ]
            )
        )
        #expect(summary.totalCount == 3)
    }

    @Test
    func nullValuesCompareAsUnchanged() throws {
        let fixture = try SourceEditingFixture()

        let summary = try fixture.summary(scope: eventScope("event-1"))

        expectNoDifference(
            summary.groups,
            [
                SourceChangeGroup(
                    id: "sourceRecords",
                    displayName: "Source Record",
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

        let summary = try fixture.summary(scope: eventScope("event-1"))

        #expect(summary.groups.first?.modified == 1)
        #expect(summary.totalCount == 1)
    }

    @Test
    func schemaMismatchReturnsUnavailableSummary() throws {
        let fixture = try SourceEditingFixture(createBaselineTable: false)
        try fixture.createBaselineTable(columns: [
            #""id" INTEGER PRIMARY KEY NOT NULL"#,
            #""eventID" TEXT NOT NULL"#,
            #""note" TEXT"#,
            #""localCache" TEXT"#,
        ])

        let summary = try fixture.summary(scope: eventScope("event-1"))

        expectNoDifference(
            summary,
            SourceChangeSummary(
                availability: .unavailable(
                    .schemaMismatch([
                        SourceSchemaMismatch(
                            role: .baseline,
                            tableName: "sourceRecords",
                            missingColumnNames: ["title"]
                        )
                    ])
                ),
                groups: []
            )
        )
    }
}

private final class SourceEditingFixture {
    let workingDatabase: any DatabaseWriter
    let baselineDatabase: SourceBaselineDatabase

    init(createBaselineTable: Bool = true) throws {
        self.workingDatabase = try SQLiteData.defaultDatabase()
        self.baselineDatabase = try defaultBaselineDatabase()

        try workingDatabase.write { db in
            try createSourceRecordsTable(in: db)
        }
        if createBaselineTable {
            try baselineDatabase.write { db in
                try createSourceRecordsTable(in: db)
            }
        }

        try insertWorking(Self.records)
        if createBaselineTable {
            try insertBaseline(Self.records)
        }
    }

    deinit {
        try? FileManager.default.removeItem(atPath: baselineDatabase.path)
    }

    static var records: [SourceRecord] {
        [
            SourceRecord(id: 1, eventID: "event-1", title: "Title", note: nil, localCache: nil),
            SourceRecord(id: 2, eventID: "event-1", title: "Old title", note: nil, localCache: nil),
            SourceRecord(id: 3, eventID: "event-1", title: "Deleted candidate", note: nil, localCache: nil),
            SourceRecord(id: 4, eventID: "event-1", title: "Ignored cache", note: nil, localCache: "old"),
            SourceRecord(id: 5, eventID: "event-2", title: "Other event", note: nil, localCache: nil),
        ]
    }

    func createBaselineTable(columns: [String]) throws {
        try baselineDatabase.write { db in
            let columnDefinitions = columns.joined(separator: ", ")
            try SQLQueryExpression(
                """
                CREATE TABLE "sourceRecords" (
                  \(raw: columnDefinitions)
                ) STRICT
                """
            )
            .execute(db)
        }
    }

    func insertWorking(_ records: [SourceRecord]) throws {
        try workingDatabase.write { db in
            try SourceRecord.insert { records }.execute(db)
        }
    }

    func insertWorking(_ record: SourceRecord) throws {
        try insertWorking([record])
    }

    func insertBaseline(_ records: [SourceRecord]) throws {
        try baselineDatabase.write { db in
            try SourceRecord.insert { records }.execute(db)
        }
    }

    func updateWorking(
        id: SourceRecord.ID,
        title: String? = nil,
        note: String? = nil,
        localCache: String? = nil
    ) throws {
        try workingDatabase.write { db in
            var record = try SourceRecord.find(id).fetchOne(db)!
            if let title {
                record.title = title
            }
            if let note {
                record.note = note
            }
            if let localCache {
                record.localCache = localCache
            }
            try SourceRecord.update(record).execute(db)
        }
    }

    func deleteWorking(id: SourceRecord.ID) throws {
        try workingDatabase.write { db in
            try SourceRecord.find(id).delete().execute(db)
        }
    }

    func summary(scope: SourceRecordScope = .all) throws -> SourceChangeSummary {
        try withDependencies {
            $0.defaultDatabase = workingDatabase
            $0.defaultBaselineDatabase = baselineDatabase
        } operation: {
            try SourceEditingComparer().summary(
                descriptors: [SourceRecord.sourceDescriptor],
                scope: scope
            )
        }
    }
}

private func createSourceRecordsTable(in db: Database) throws {
    try #sql("""
        CREATE TABLE "sourceRecords" (
          "id" INTEGER PRIMARY KEY NOT NULL,
          "eventID" TEXT NOT NULL,
          "title" TEXT NOT NULL,
          "note" TEXT,
          "localCache" TEXT
        ) STRICT
        """)
        .execute(db)
}

private func eventScope(_ eventID: String) -> SourceRecordScope {
    SourceRecordScope(
        filters: [
            SourceRecordScope.Filter(
                columnName: "eventID",
                value: eventID.queryBinding
            )
        ]
    )
}
