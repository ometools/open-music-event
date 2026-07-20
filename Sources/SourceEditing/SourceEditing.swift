import CustomDump
import Dependencies
import Foundation
import GRDB
import SQLiteData

public protocol SourceEditableTable: PrimaryKeyedTable {
    static var sourceDisplayName: String { get }
    static var sourceColumnPolicies: SourceColumnPolicies<Self> { get }
}

public typealias SourceColumnPolicies<Table: SourceEditableTable> = [
    PartialKeyPath<Table.TableColumns>: SourceColumnPolicy
]

public extension SourceEditableTable {
    static var sourceDisplayName: String {
        String(describing: Self.self)
    }

    static var sourceColumnPolicies: SourceColumnPolicies<Self> {
        [:]
    }

    static var sourceDescriptor: SourceTableDescriptor {
        sourceDescriptor(columnPolicies: sourceColumnPolicies)
    }

    static func sourceDescriptor(
        columnPolicies: SourceColumnPolicies<Self>
    ) -> SourceTableDescriptor {
        let primaryKeyColumns = columns.primaryKey._names
        let resetColumnNames = TableColumns.writableColumns.flatMap(\._names)

        let ignoredColumnNames = Set(
            columnPolicies
                .compactMap { column, policy in
                    policy.ignoresColumn
                        ? sourceColumnName(for: column)
                        : nil
                }
        )
        let excludedColumns = Set(primaryKeyColumns).union(ignoredColumnNames)
        let comparedColumns = resetColumnNames
            .filter { !excludedColumns.contains($0) }

        return SourceTableDescriptor(
            id: tableName,
            tableName: tableName,
            primaryKeyColumns: primaryKeyColumns,
            comparedColumns: comparedColumns,
            resetColumnNames: resetColumnNames,
            displayName: sourceDisplayName
        )
    }

    fileprivate static func sourceColumnName(
        for column: PartialKeyPath<TableColumns>
    ) -> String {
        guard let columnExpression = columns[keyPath: column] as? any _TableColumnExpression else {
            preconditionFailure(
                "Source column policies must be keyed by table columns."
            )
        }

        let columnNames = columnExpression._names
        precondition(
            columnNames.count == 1,
            "Source column policies must reference exactly one column."
        )
        return columnNames[0]
    }
}

public enum SourceColumnPolicyResolution: Sendable {
    case ignored
    case unchanged
    case changed(recordDiff: String?)
    case useRawComparison
}

public struct SourceColumnPolicy: Sendable {
    public var ignoresColumn: Bool
    public var resolve: @Sendable (SourceFieldChange) -> SourceColumnPolicyResolution

    public init(
        resolve: @escaping @Sendable (SourceFieldChange) -> SourceColumnPolicyResolution
    ) {
        self.init(
            ignoresColumn: false,
            resolve: resolve
        )
    }

    public static var ignore: Self {
        Self(
            ignoresColumn: true
        ) { _ in
            .ignored
        }
    }

    public static func comparing<Value>(
        decode: @escaping @Sendable (DatabaseValue?) -> Value?
    ) -> Self
    where
        Value: Equatable & Sendable
    {
        return Self(
            ignoresColumn: false
        ) { fieldChange in
            let baseline = decode(fieldChange.baselineValue)
            let working = decode(fieldChange.workingValue)
            if baseline == nil, working == nil {
                return .useRawComparison
            }

            guard baseline != working else {
                return .unchanged
            }

            return .changed(
                recordDiff: diff(
                    SourceColumnPolicyComparisonValue(
                        columnName: fieldChange.columnName,
                        value: baseline
                    ),
                    SourceColumnPolicyComparisonValue(
                        columnName: fieldChange.columnName,
                        value: working
                    )
                )
            )
        }
    }

    private init(
        ignoresColumn: Bool,
        resolve: @escaping @Sendable (SourceFieldChange) -> SourceColumnPolicyResolution
    ) {
        self.ignoresColumn = ignoresColumn
        self.resolve = resolve
    }
}

private struct SourceColumnPolicyComparisonValue<Value: Sendable>: Sendable, CustomDumpRepresentable {
    var columnName: String
    var value: Value?

    var customDumpValue: Any {
        (
            columnName: columnName,
            value: value
        )
    }
}

private enum SourceRecordSnapshot<Record: Sendable>: Sendable {
    case missing
    case record(Record)
}

private struct SourceRecordDiffSnapshot<Record: Sendable>: Sendable, CustomDumpRepresentable {
    var snapshot: SourceRecordSnapshot<Record>
    var includedColumnNames: Set<String>

    var customDumpValue: Any {
        switch snapshot {
        case .missing:
            "missing"
        case let .record(record):
            SourceRecordDump(
                record: record,
                includedColumnNames: includedColumnNames
            )
        }
    }
}

private struct SourceRecordDump<Record: Sendable>: Sendable, CustomDumpReflectable {
    var record: Record
    var includedColumnNames: Set<String>

    var customDumpMirror: Mirror {
        let mirror = Mirror(reflecting: record)
        let children = mirror.children.compactMap { child -> Mirror.Child? in
            guard let label = child.label,
                  includedColumnNames.contains(label)
            else { return nil }

            return child
        }

        return Mirror(
            record,
            children: children,
            displayStyle: mirror.displayStyle
        )
    }
}

public struct AnySourceEditableRecordType {
    public var descriptor: SourceTableDescriptor
    public var resolveRecordChange: (SourceRecordChange, Database, String) throws -> SourceRecordChange?
    public var recordComparison: (SourceRecordChange, Database, String) throws -> AnySourceRecordComparison?

    public init(
        descriptor: SourceTableDescriptor,
        resolveRecordChange: @escaping (SourceRecordChange, Database, String) throws -> SourceRecordChange?,
        recordComparison: @escaping (SourceRecordChange, Database, String) throws -> AnySourceRecordComparison? = { _, _, _ in nil }
    ) {
        self.descriptor = descriptor
        self.resolveRecordChange = resolveRecordChange
        self.recordComparison = recordComparison
    }

    public init(
        descriptor: SourceTableDescriptor,
        recordDiff: @escaping (SourceRecordChange, Database, String) throws -> String,
        recordComparison: @escaping (SourceRecordChange, Database, String) throws -> AnySourceRecordComparison? = { _, _, _ in nil }
    ) {
        self.init(
            descriptor: descriptor,
            resolveRecordChange: { change, db, baselineSchemaName in
                var change = change
                change.recordDiff = try recordDiff(change, db, baselineSchemaName)
                return change
            },
            recordComparison: recordComparison
        )
    }
}

public extension SourceEditableTable where QueryOutput: Sendable {
    static var sourceRecordType: AnySourceEditableRecordType {
        sourceRecordType(columnPolicies: sourceColumnPolicies)
    }

    static func sourceRecordType(
        columnPolicies: SourceColumnPolicies<Self>
    ) -> AnySourceEditableRecordType {
        let descriptor = sourceDescriptor(columnPolicies: columnPolicies)
        let rawRecordType = rawSourceRecordType(descriptor: descriptor)
        let policiesByColumnName = Dictionary(
            uniqueKeysWithValues: columnPolicies.map { column, policy in
                (sourceColumnName(for: column), policy)
            }
        )

        guard !policiesByColumnName.isEmpty else {
            return rawRecordType
        }

        return AnySourceEditableRecordType(
            descriptor: descriptor,
            resolveRecordChange: { change, db, baselineSchemaName in
                var retainedFieldChanges: [SourceFieldChange] = []
                var rawFieldChanges: [SourceFieldChange] = []
                var policyRecordDiffs: [String] = []

                for fieldChange in change.fieldChanges {
                    guard let policy = policiesByColumnName[fieldChange.columnName] else {
                        retainedFieldChanges.append(fieldChange)
                        rawFieldChanges.append(fieldChange)
                        continue
                    }

                    switch policy.resolve(fieldChange) {
                    case .ignored, .unchanged:
                        continue

                    case let .changed(recordDiff):
                        retainedFieldChanges.append(fieldChange)
                        if let recordDiff, !recordDiff.isEmpty {
                            policyRecordDiffs.append(recordDiff)
                        }

                    case .useRawComparison:
                        retainedFieldChanges.append(fieldChange)
                        rawFieldChanges.append(fieldChange)
                    }
                }

                guard !retainedFieldChanges.isEmpty else {
                    return nil
                }

                var rawRecordDiff: String?
                if !rawFieldChanges.isEmpty {
                    var rawChange = change
                    rawChange.fieldChanges = rawFieldChanges
                    let resolvedRawChange = try rawRecordType
                        .resolveRecordChange(rawChange, db, baselineSchemaName)
                    rawRecordDiff = resolvedRawChange?.recordDiff
                }

                var resolvedChange = change
                resolvedChange.fieldChanges = retainedFieldChanges

                let recordDiffs = ([rawRecordDiff].compactMap(\.self) + policyRecordDiffs)
                    .filter { !$0.isEmpty }
                if !recordDiffs.isEmpty {
                    resolvedChange.recordDiff = recordDiffs.joined(separator: "\n")
                } else if !rawFieldChanges.isEmpty {
                    resolvedChange.recordDiff = rawRecordDiff
                } else {
                    resolvedChange.recordDiff = nil
                }
                return resolvedChange
            },
            recordComparison: { change, db, baselineSchemaName in
                try rawRecordType.recordComparison(change, db, baselineSchemaName)
            }
        )
    }

    private static func rawSourceRecordType(
        descriptor: SourceTableDescriptor
    ) -> AnySourceEditableRecordType {
        AnySourceEditableRecordType(
            descriptor: descriptor,
            recordDiff: { change, db, baselineSchemaName in
                let includedColumnNames = Set(
                    change.fieldChanges.map(\.columnName)
                )
                let baseline = SourceRecordDiffSnapshot(
                    snapshot: try sourceRecordSnapshot(
                        for: change,
                        schemaName: baselineSchemaName,
                        in: db
                    ),
                    includedColumnNames: includedColumnNames
                )
                let working = SourceRecordDiffSnapshot(
                    snapshot: try sourceRecordSnapshot(
                        for: change,
                        schemaName: "main",
                        in: db
                    ),
                    includedColumnNames: includedColumnNames
                )

                return diff(baseline, working) ?? ""
            },
            recordComparison: { change, db, baselineSchemaName in
                AnySourceRecordComparison(
                    SourceRecordComparison(
                        change: change,
                        left: try sourceRecord(
                            for: change,
                            schemaName: baselineSchemaName,
                            in: db
                        ),
                        right: try sourceRecord(
                            for: change,
                            schemaName: "main",
                            in: db
                        )
                    )
                )
            }
        )
    }

    private static func sourceRecordSnapshot(
        for change: SourceRecordChange,
        schemaName: String,
        in db: Database
    ) throws -> SourceRecordSnapshot<QueryOutput> {
        if let record = try sourceRecord(
            for: change,
            schemaName: schemaName,
            in: db
        ) {
            return .record(record)
        }
        return .missing
    }

    static func sourceRecord(
        for change: SourceRecordChange,
        schemaName: String,
        in db: Database
    ) throws -> QueryOutput? {
        do {
            return try SQLQueryExpression<Self>(
                """
                SELECT *
                FROM \(qualifiedTable(tableName, schemaName: schemaName))
                WHERE \(try primaryKeyValuesPredicate(change.primaryKeyValues))
                LIMIT 1
                """,
                as: Self.self
            )
            .fetchOne(db)
        } catch {
            throw SourceRecordDecodingError(
                tableName: tableName,
                schemaName: schemaName,
                primaryKeyValues: change.primaryKeyValues,
                changedColumnNames: change.fieldChanges.map(\.columnName),
                underlyingError: error
            )
        }
    }
}

public struct SourceRecordDecodingError: Error, CustomStringConvertible {
    public var tableName: String
    public var schemaName: String
    public var primaryKeyValues: [SourceColumnValue]
    public var changedColumnNames: [String]
    public var underlyingError: any Error

    public init(
        tableName: String,
        schemaName: String,
        primaryKeyValues: [SourceColumnValue],
        changedColumnNames: [String],
        underlyingError: any Error
    ) {
        self.tableName = tableName
        self.schemaName = schemaName
        self.primaryKeyValues = primaryKeyValues
        self.changedColumnNames = changedColumnNames
        self.underlyingError = underlyingError
    }

    public var description: String {
        let primaryKey = primaryKeyValues
            .map { "\($0.columnName)=\($0.value.sourceRecordDecodingDescription)" }
            .joined(separator: ", ")
        let changedColumns = changedColumnNames.joined(separator: ", ")
        return """
        Unable to decode source record table=\(tableName) schema=\(schemaName) primaryKey=(\(primaryKey)) changedColumns=(\(changedColumns)): \(underlyingError)
        """
    }
}

public struct SourceTableDescriptor: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var tableName: String
    public var primaryKeyColumns: [String]
    public var comparedColumns: [String]
    public var resetColumnNames: [String]
    public var displayName: String

    public init(
        id: String,
        tableName: String,
        primaryKeyColumns: [String],
        comparedColumns: [String],
        resetColumnNames: [String]? = nil,
        displayName: String
    ) {
        self.id = id
        self.tableName = tableName
        self.primaryKeyColumns = primaryKeyColumns
        self.comparedColumns = comparedColumns
        self.resetColumnNames = resetColumnNames ?? primaryKeyColumns + comparedColumns
        self.displayName = displayName
    }
}

public struct SourceRecordScope: Equatable, Hashable, Sendable {
    public struct Filter: Equatable, Hashable, Sendable {
        public var columnName: String
        public var value: QueryBinding

        public init(columnName: String, value: QueryBinding) {
            self.columnName = columnName
            self.value = value
        }
    }

    public var filters: [Filter]

    public init(filters: [Filter] = []) {
        self.filters = filters
    }

    public static var all: Self {
        Self()
    }
}

public enum SourceRecordChangeKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case added
    case modified
    case deleted
}

public struct SourceColumnValue: Equatable, Hashable, Sendable, Identifiable {
    public var id: String { columnName }

    public var columnName: String
    public var value: DatabaseValue

    public init(
        columnName: String,
        value: DatabaseValue
    ) {
        self.columnName = columnName
        self.value = value
    }
}

public struct SourceFieldChange: Equatable, Hashable, Sendable, Identifiable {
    public var id: String { columnName }

    public var columnName: String
    public var baselineValue: DatabaseValue?
    public var workingValue: DatabaseValue?

    public init(
        columnName: String,
        baselineValue: DatabaseValue?,
        workingValue: DatabaseValue?
    ) {
        self.columnName = columnName
        self.baselineValue = baselineValue
        self.workingValue = workingValue
    }
}

public struct SourceRecordChange: Equatable, Hashable, Sendable, Identifiable {
    public var id: String {
        let primaryKey = primaryKeyValues
            .map { "\($0.columnName)=\($0.value)" }
            .joined(separator: ",")
        return "\(tableID):\(kind.rawValue):\(primaryKey)"
    }

    public var tableID: SourceTableDescriptor.ID
    public var kind: SourceRecordChangeKind
    public var primaryKeyValues: [SourceColumnValue]
    public var fieldChanges: [SourceFieldChange]
    public var recordDiff: String?

    public init(
        tableID: SourceTableDescriptor.ID,
        kind: SourceRecordChangeKind,
        primaryKeyValues: [SourceColumnValue],
        fieldChanges: [SourceFieldChange],
        recordDiff: String? = nil
    ) {
        self.tableID = tableID
        self.kind = kind
        self.primaryKeyValues = primaryKeyValues
        self.fieldChanges = fieldChanges
        self.recordDiff = recordDiff
    }
}

public struct SourceRecordComparison<Record: Sendable>: Sendable {
    public var change: SourceRecordChange
    public var left: Record?
    public var right: Record?

    public init(
        change: SourceRecordChange,
        left: Record?,
        right: Record?
    ) {
        self.change = change
        self.left = left
        self.right = right
    }
}

extension SourceRecordComparison: Equatable where Record: Equatable {}

public struct AnySourceRecordComparison: @unchecked Sendable, Equatable, Hashable, Identifiable {
    public var id: SourceRecordChange.ID { change.id }

    public var change: SourceRecordChange
    public var recordTypeID: ObjectIdentifier
    public var recordTypeName: String

    private var left: (any Sendable)?
    private var right: (any Sendable)?

    public init<Record: Sendable>(
        _ comparison: SourceRecordComparison<Record>
    ) {
        self.change = comparison.change
        self.recordTypeID = ObjectIdentifier(Record.self)
        self.recordTypeName = String(reflecting: Record.self)
        self.left = comparison.left
        self.right = comparison.right
    }

    public func `as`<Record: Sendable>(
        _ recordType: Record.Type
    ) -> SourceRecordComparison<Record>? {
        guard recordTypeID == ObjectIdentifier(recordType) else { return nil }
        return SourceRecordComparison(
            change: change,
            left: left as? Record,
            right: right as? Record
        )
    }

    public static func == (
        lhs: AnySourceRecordComparison,
        rhs: AnySourceRecordComparison
    ) -> Bool {
        lhs.change == rhs.change
            && lhs.recordTypeID == rhs.recordTypeID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(change)
        hasher.combine(recordTypeID)
    }
}

extension AnySourceRecordComparison: CustomDumpReflectable {
    public var customDumpMirror: Mirror {
        Mirror(
            self,
            children: [
                "change": change,
                "recordTypeName": recordTypeName,
                "left": left as Any,
                "right": right as Any,
            ],
            displayStyle: .struct
        )
    }
}

public struct SourceRecordComparisons: Equatable, Hashable, Sendable {
    public static var empty: Self { Self() }

    private var comparisonsByChangeID: [SourceRecordChange.ID: AnySourceRecordComparison]

    public init(_ comparisons: [AnySourceRecordComparison] = []) {
        self.comparisonsByChangeID = Dictionary(
            uniqueKeysWithValues: comparisons.map { ($0.id, $0) }
        )
    }

    public subscript(_ change: SourceRecordChange) -> AnySourceRecordComparison? {
        comparisonsByChangeID[change.id]
    }

    public var values: [AnySourceRecordComparison] {
        Array(comparisonsByChangeID.values)
    }
}

public struct SourceChangeGroup: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var added: Int
    public var modified: Int
    public var deleted: Int
    public var records: [SourceRecordChange]

    public init(
        id: String,
        displayName: String,
        added: Int,
        modified: Int,
        deleted: Int,
        records: [SourceRecordChange] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.added = added
        self.modified = modified
        self.deleted = deleted
        self.records = records
    }

    public var totalCount: Int {
        added + modified + deleted
    }
}

public struct SourceChangeSummary: Equatable, Hashable, Sendable {
    public enum Availability: Equatable, Hashable, Sendable {
        case available
        case unavailable(UnavailableReason)
    }

    public enum UnavailableReason: Equatable, Hashable, Sendable {
        case schemaMismatch([SourceSchemaMismatch])
    }

    public var availability: Availability
    public var groups: [SourceChangeGroup]
    public var recordComparisons: SourceRecordComparisons

    public init(
        availability: Availability,
        groups: [SourceChangeGroup],
        recordComparisons: SourceRecordComparisons = .empty
    ) {
        self.availability = availability
        self.groups = groups
        self.recordComparisons = recordComparisons
    }

    public var totalCount: Int {
        groups.reduce(0) { $0 + $1.totalCount }
    }
}

public extension SourceEditingSession {
    func reset(
        descriptors: [SourceTableDescriptor],
        scope: SourceRecordScope = .all
    ) throws {
        try database.write { db in
            try SourceEditingResetter().reset(
                in: db,
                baselineSchemaName: baselineSchemaName,
                descriptors: descriptors,
                scope: scope
            )
        }
    }
}

public struct SourceEditingResetter: Sendable {
    public init() {}

    public func reset(
        in db: Database,
        baselineDatabase: SourceBaselineDatabase,
        descriptors: [SourceTableDescriptor],
        scope: SourceRecordScope = .all
    ) throws {
        try reset(
            in: db,
            baselineDatabasePath: baselineDatabase.path,
            descriptors: descriptors,
            scope: scope
        )
    }

    public func reset(
        in db: Database,
        baselineDatabasePath: String,
        descriptors: [SourceTableDescriptor],
        scope: SourceRecordScope = .all
    ) throws {
        let baselineSchemaName = "source_baseline_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"

        try #sql(
            "ATTACH DATABASE \(bind: baselineDatabasePath) AS \(quote: baselineSchemaName)"
        )
        .execute(db)
        defer {
            try? #sql("DETACH DATABASE \(quote: baselineSchemaName)").execute(db)
        }

        try reset(
            in: db,
            baselineSchemaName: baselineSchemaName,
            descriptors: descriptors,
            scope: scope
        )
    }

    public func reset(
        in db: Database,
        baselineSchemaName: String,
        descriptors: [SourceTableDescriptor],
        scope: SourceRecordScope = .all
    ) throws {
        for descriptor in descriptors.reversed() {
            try deleteAddedRows(
                descriptor: descriptor,
                baselineSchemaName: baselineSchemaName,
                scope: scope,
                in: db
            )
        }

        for descriptor in descriptors {
            try insertDeletedRows(
                descriptor: descriptor,
                baselineSchemaName: baselineSchemaName,
                scope: scope,
                in: db
            )
        }

        for descriptor in descriptors {
            try resetModifiedRows(
                descriptor: descriptor,
                baselineSchemaName: baselineSchemaName,
                scope: scope,
                in: db
            )
        }
    }
}

public struct SourceSchemaMismatch: Equatable, Hashable, Sendable, Identifiable {
    public enum DatabaseRole: String, Equatable, Hashable, Sendable {
        case working
        case baseline
    }

    public var id: String {
        "\(role.rawValue):\(tableName)"
    }

    public var role: DatabaseRole
    public var tableName: String
    public var missingColumnNames: [String]

    public init(
        role: DatabaseRole,
        tableName: String,
        missingColumnNames: [String]
    ) {
        self.role = role
        self.tableName = tableName
        self.missingColumnNames = missingColumnNames
    }
}

public struct SourceEditingComparer: Sendable {
    public init() {}

    public func summary(
        descriptors: [SourceTableDescriptor],
        scope: SourceRecordScope = .all
    ) throws -> SourceChangeSummary {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.sourceEditingSession) var sourceEditingSession

        return try database.read { db in
            if let sourceEditingSession {
                return try summary(
                    in: db,
                    baselineSchemaName: sourceEditingSession.baselineSchemaName,
                    descriptors: descriptors,
                    scope: scope
                )
            }

            @Dependency(\.defaultBaselineDatabase) var baselineDatabase
            return try summary(
                in: db,
                baselineDatabase: baselineDatabase,
                descriptors: descriptors,
                scope: scope
            )
        }
    }

    public func summary(
        recordTypes: [AnySourceEditableRecordType],
        scope: SourceRecordScope = .all
    ) throws -> SourceChangeSummary {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.sourceEditingSession) var sourceEditingSession

        return try database.read { db in
            if let sourceEditingSession {
                return try summary(
                    in: db,
                    baselineSchemaName: sourceEditingSession.baselineSchemaName,
                    recordTypes: recordTypes,
                    scope: scope
                )
            }

            @Dependency(\.defaultBaselineDatabase) var baselineDatabase
            return try summary(
                in: db,
                baselineDatabase: baselineDatabase,
                recordTypes: recordTypes,
                scope: scope
            )
        }
    }

    public func summary(
        in db: Database,
        baselineDatabase: SourceBaselineDatabase,
        descriptors: [SourceTableDescriptor],
        scope: SourceRecordScope = .all
    ) throws -> SourceChangeSummary {
        try summary(
            in: db,
            baselineDatabasePath: baselineDatabase.path,
            descriptors: descriptors,
            scope: scope
        )
    }

    public func summary(
        in db: Database,
        baselineDatabase: SourceBaselineDatabase,
        recordTypes: [AnySourceEditableRecordType],
        scope: SourceRecordScope = .all
    ) throws -> SourceChangeSummary {
        try summary(
            in: db,
            baselineDatabasePath: baselineDatabase.path,
            recordTypes: recordTypes,
            scope: scope
        )
    }

    public func summary(
        in db: Database,
        baselineDatabasePath: String,
        descriptors: [SourceTableDescriptor],
        scope: SourceRecordScope = .all
    ) throws -> SourceChangeSummary {
        let baselineSchemaName = "source_baseline_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"

        try #sql(
            "ATTACH DATABASE \(bind: baselineDatabasePath) AS \(quote: baselineSchemaName)"
        )
        .execute(db)
        defer {
            try? #sql("DETACH DATABASE \(quote: baselineSchemaName)").execute(db)
        }

        return try summary(
            in: db,
            baselineSchemaName: baselineSchemaName,
            descriptors: descriptors,
            scope: scope
        )
    }

    public func summary(
        in db: Database,
        baselineDatabasePath: String,
        recordTypes: [AnySourceEditableRecordType],
        scope: SourceRecordScope = .all
    ) throws -> SourceChangeSummary {
        let baselineSchemaName = "source_baseline_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"

        try #sql(
            "ATTACH DATABASE \(bind: baselineDatabasePath) AS \(quote: baselineSchemaName)"
        )
        .execute(db)
        defer {
            try? #sql("DETACH DATABASE \(quote: baselineSchemaName)").execute(db)
        }

        return try summary(
            in: db,
            baselineSchemaName: baselineSchemaName,
            recordTypes: recordTypes,
            scope: scope
        )
    }

    public func summary(
        in db: Database,
        baselineSchemaName: String,
        descriptors: [SourceTableDescriptor],
        scope: SourceRecordScope = .all
    ) throws -> SourceChangeSummary {
        let mismatches = try schemaMismatches(
            in: db,
            baselineSchemaName: baselineSchemaName,
            descriptors: descriptors,
            scope: scope
        )
        guard mismatches.isEmpty else {
            return SourceChangeSummary(
                availability: .unavailable(.schemaMismatch(mismatches)),
                groups: []
            )
        }

        let groups = try descriptors.map { descriptor in
            try compare(
                descriptor,
                in: db,
                baselineSchemaName: baselineSchemaName,
                scope: scope
            )
        }
        return SourceChangeSummary(
            availability: .available,
            groups: groups
        )
    }

    public func summary(
        in db: Database,
        baselineSchemaName: String,
        recordTypes: [AnySourceEditableRecordType],
        scope: SourceRecordScope = .all
    ) throws -> SourceChangeSummary {
        let summary = try summary(
            in: db,
            baselineSchemaName: baselineSchemaName,
            descriptors: recordTypes.map(\.descriptor),
            scope: scope
        )
        guard case .available = summary.availability else {
            return summary
        }

        let recordTypesByID = Dictionary(
            uniqueKeysWithValues: recordTypes.map { ($0.descriptor.id, $0) }
        )
        var recordComparisons: [AnySourceRecordComparison] = []
        let groups = try summary.groups.map { group in
            guard let recordType = recordTypesByID[group.id] else {
                return group
            }

            var group = group
            group.records = try group.records.compactMap { record in
                do {
                    guard let resolvedRecord = try recordType.resolveRecordChange(
                        record,
                        db,
                        baselineSchemaName
                    ) else { return nil }
                    do {
                        if let comparison = try recordType.recordComparison(
                            resolvedRecord,
                            db,
                            baselineSchemaName
                        ) {
                            recordComparisons.append(comparison)
                        }
                    } catch is SourceRecordDecodingError {
                    }
                    return resolvedRecord
                } catch is SourceRecordDecodingError {
                    return record
                }
            }
            group.added = group.records.filter { $0.kind == .added }.count
            group.modified = group.records.filter { $0.kind == .modified }.count
            group.deleted = group.records.filter { $0.kind == .deleted }.count
            return group
        }

        return SourceChangeSummary(
            availability: summary.availability,
            groups: groups,
            recordComparisons: SourceRecordComparisons(recordComparisons)
        )
    }

    private func schemaMismatches(
        in db: Database,
        baselineSchemaName: String,
        descriptors: [SourceTableDescriptor],
        scope: SourceRecordScope
    ) throws -> [SourceSchemaMismatch] {
        var mismatches: [SourceSchemaMismatch] = []

        for descriptor in descriptors {
            let requiredColumnNames = Set(
                descriptor.primaryKeyColumns
                    + descriptor.comparedColumns
                    + scope.filters.map(\.columnName)
            )

            let workingColumnNames = try tableColumnNames(
                in: db,
                schemaName: "main",
                tableName: descriptor.tableName
            )
            let missingWorkingColumnNames = requiredColumnNames.subtracting(workingColumnNames).sorted()
            if !missingWorkingColumnNames.isEmpty {
                mismatches.append(
                    SourceSchemaMismatch(
                        role: .working,
                        tableName: descriptor.tableName,
                        missingColumnNames: missingWorkingColumnNames
                    )
                )
            }

            let baselineColumnNames = try tableColumnNames(
                in: db,
                schemaName: baselineSchemaName,
                tableName: descriptor.tableName
            )
            let missingBaselineColumnNames = requiredColumnNames.subtracting(baselineColumnNames).sorted()
            if !missingBaselineColumnNames.isEmpty {
                mismatches.append(
                    SourceSchemaMismatch(
                        role: .baseline,
                        tableName: descriptor.tableName,
                        missingColumnNames: missingBaselineColumnNames
                    )
                )
            }
        }

        return mismatches
    }

    private func compare(
        _ descriptor: SourceTableDescriptor,
        in db: Database,
        baselineSchemaName: String,
        scope: SourceRecordScope
    ) throws -> SourceChangeGroup {
        let records =
            try addedRecords(
                descriptor: descriptor,
                baselineSchemaName: baselineSchemaName,
                scope: scope,
                in: db
            )
            + modifiedRecords(
                descriptor: descriptor,
                baselineSchemaName: baselineSchemaName,
                scope: scope,
                in: db
            )
            + deletedRecords(
                descriptor: descriptor,
                baselineSchemaName: baselineSchemaName,
                scope: scope,
                in: db
            )

        return SourceChangeGroup(
            id: descriptor.id,
            displayName: descriptor.displayName,
            added: records.filter { $0.kind == .added }.count,
            modified: records.filter { $0.kind == .modified }.count,
            deleted: records.filter { $0.kind == .deleted }.count,
            records: records
        )
    }

    private func addedRecords(
        descriptor: SourceTableDescriptor,
        baselineSchemaName: String,
        scope: SourceRecordScope,
        in db: Database
    ) throws -> [SourceRecordChange] {
        try fetchRows(
            addedRowsQuery(
                descriptor: descriptor,
                baselineSchemaName: baselineSchemaName,
                scope: scope
            )
            .query,
            in: db
        )
        .map { row in
            SourceRecordChange(
                tableID: descriptor.id,
                kind: .added,
                primaryKeyValues: sourceColumnValues(
                    descriptor.primaryKeyColumns,
                    in: row
                ),
                fieldChanges: descriptor.comparedColumns.map { columnName in
                    SourceFieldChange(
                        columnName: columnName,
                        baselineValue: nil,
                        workingValue: row.databaseValue(forColumn: columnName)
                    )
                }
            )
        }
    }

    private func modifiedRecords(
        descriptor: SourceTableDescriptor,
        baselineSchemaName: String,
        scope: SourceRecordScope,
        in db: Database
    ) throws -> [SourceRecordChange] {
        guard !descriptor.comparedColumns.isEmpty else {
            return []
        }

        return try fetchRows(
            modifiedRowsQuery(
                descriptor: descriptor,
                baselineSchemaName: baselineSchemaName,
                scope: scope
            )
            .query,
            in: db
        )
        .map { row in
            let fieldChanges = descriptor.comparedColumns.compactMap { columnName -> SourceFieldChange? in
                let baselineValue = row.databaseValue(forColumn: "baseline_\(columnName)")
                let workingValue = row.databaseValue(forColumn: "working_\(columnName)")
                guard baselineValue != workingValue else { return nil }
                return SourceFieldChange(
                    columnName: columnName,
                    baselineValue: baselineValue,
                    workingValue: workingValue
                )
            }

            return SourceRecordChange(
                tableID: descriptor.id,
                kind: .modified,
                primaryKeyValues: sourceColumnValues(
                    descriptor.primaryKeyColumns,
                    in: row
                ),
                fieldChanges: fieldChanges
            )
        }
    }

    private func deletedRecords(
        descriptor: SourceTableDescriptor,
        baselineSchemaName: String,
        scope: SourceRecordScope,
        in db: Database
    ) throws -> [SourceRecordChange] {
        try fetchRows(
            deletedRowsQuery(
                descriptor: descriptor,
                baselineSchemaName: baselineSchemaName,
                scope: scope
            )
            .query,
            in: db
        )
        .map { row in
            SourceRecordChange(
                tableID: descriptor.id,
                kind: .deleted,
                primaryKeyValues: sourceColumnValues(
                    descriptor.primaryKeyColumns,
                    in: row
                ),
                fieldChanges: descriptor.comparedColumns.map { columnName in
                    SourceFieldChange(
                        columnName: columnName,
                        baselineValue: row.databaseValue(forColumn: columnName),
                        workingValue: nil
                    )
                }
            )
        }
    }
}

private func tableColumnNames(
    in db: Database,
    schemaName: String,
    tableName: String
) throws -> Set<String> {
    Set(
        try #sql(
            "SELECT name FROM pragma_table_info(\(bind: tableName), \(bind: schemaName))",
            as: String.self
        )
        .fetchAll(db)
    )
}

private func addedRowsQuery(
    descriptor: SourceTableDescriptor,
    baselineSchemaName: String,
    scope: SourceRecordScope
) -> SQLQueryExpression<Any> {
    let workingAlias = "working"
    let baselineAlias = "baseline"

    return #sql(
        """
        SELECT \(columnSelections(
            descriptor.primaryKeyColumns + descriptor.comparedColumns,
            tableAlias: workingAlias
        ))
        FROM \(qualifiedTable(descriptor.tableName)) AS \(quote: workingAlias)
        WHERE \(scopePredicate(scope, alias: workingAlias))
        AND NOT EXISTS (
          SELECT 1
          FROM \(qualifiedTable(descriptor.tableName, schemaName: baselineSchemaName)) AS \(quote: baselineAlias)
          WHERE \(primaryKeyPredicate(descriptor.primaryKeyColumns, workingAlias: workingAlias, baselineAlias: baselineAlias))
          AND \(scopePredicate(scope, alias: baselineAlias))
        )
        ORDER BY \(orderByColumns(descriptor.primaryKeyColumns, tableAlias: workingAlias))
        """,
        as: Int.self
    )
}

private func deletedRowsQuery(
    descriptor: SourceTableDescriptor,
    baselineSchemaName: String,
    scope: SourceRecordScope
) -> SQLQueryExpression<Any> {
    let workingAlias = "working"
    let baselineAlias = "baseline"

    return #sql(
        """
        SELECT \(columnSelections(
            descriptor.primaryKeyColumns + descriptor.comparedColumns,
            tableAlias: baselineAlias
        ))
        FROM \(qualifiedTable(descriptor.tableName, schemaName: baselineSchemaName)) AS \(quote: baselineAlias)
        WHERE \(scopePredicate(scope, alias: baselineAlias))
        AND NOT EXISTS (
          SELECT 1
          FROM \(qualifiedTable(descriptor.tableName)) AS \(quote: workingAlias)
          WHERE \(primaryKeyPredicate(descriptor.primaryKeyColumns, workingAlias: workingAlias, baselineAlias: baselineAlias))
          AND \(scopePredicate(scope, alias: workingAlias))
        )
        ORDER BY \(orderByColumns(descriptor.primaryKeyColumns, tableAlias: baselineAlias))
        """,
        as: Int.self
    )
}

private func deleteAddedRows(
    descriptor: SourceTableDescriptor,
    baselineSchemaName: String,
    scope: SourceRecordScope,
    in db: Database
) throws {
    let workingAlias = descriptor.tableName
    let baselineAlias = "baseline"

    try #sql(
        """
        DELETE FROM \(qualifiedTable(descriptor.tableName))
        WHERE \(scopePredicate(scope, alias: workingAlias))
        AND NOT EXISTS (
          SELECT 1
          FROM \(qualifiedTable(descriptor.tableName, schemaName: baselineSchemaName)) AS \(quote: baselineAlias)
          WHERE \(primaryKeyPredicate(descriptor.primaryKeyColumns, workingAlias: workingAlias, baselineAlias: baselineAlias))
          AND \(scopePredicate(scope, alias: baselineAlias))
        )
        """
    )
    .execute(db)
}

private func insertDeletedRows(
    descriptor: SourceTableDescriptor,
    baselineSchemaName: String,
    scope: SourceRecordScope,
    in db: Database
) throws {
    let workingAlias = "working"
    let baselineAlias = "baseline"

    try #sql(
        """
        INSERT INTO \(qualifiedTable(descriptor.tableName)) (\(columnNames(descriptor.resetColumnNames)))
        SELECT \(columnSelections(descriptor.resetColumnNames, tableAlias: baselineAlias))
        FROM \(qualifiedTable(descriptor.tableName, schemaName: baselineSchemaName)) AS \(quote: baselineAlias)
        WHERE \(scopePredicate(scope, alias: baselineAlias))
        AND NOT EXISTS (
          SELECT 1
          FROM \(qualifiedTable(descriptor.tableName)) AS \(quote: workingAlias)
          WHERE \(primaryKeyPredicate(descriptor.primaryKeyColumns, workingAlias: workingAlias, baselineAlias: baselineAlias))
          AND \(scopePredicate(scope, alias: workingAlias))
        )
        """
    )
    .execute(db)
}

private func modifiedRowsQuery(
    descriptor: SourceTableDescriptor,
    baselineSchemaName: String,
    scope: SourceRecordScope
) -> SQLQueryExpression<Any> {
    let workingAlias = "working"
    let baselineAlias = "baseline"

    return #sql(
        """
        SELECT \(columnSelections(
            descriptor.primaryKeyColumns,
            tableAlias: workingAlias
        )),
        \(columnSelections(
            descriptor.comparedColumns,
            tableAlias: baselineAlias,
            outputPrefix: "baseline_"
        )),
        \(columnSelections(
            descriptor.comparedColumns,
            tableAlias: workingAlias,
            outputPrefix: "working_"
        ))
        FROM \(qualifiedTable(descriptor.tableName)) AS \(quote: workingAlias)
        INNER JOIN \(qualifiedTable(descriptor.tableName, schemaName: baselineSchemaName)) AS \(quote: baselineAlias)
        ON \(primaryKeyPredicate(descriptor.primaryKeyColumns, workingAlias: workingAlias, baselineAlias: baselineAlias))
        WHERE \(scopePredicate(scope, alias: workingAlias))
        AND \(scopePredicate(scope, alias: baselineAlias))
        AND \(modifiedPredicate(descriptor.comparedColumns, workingAlias: workingAlias, baselineAlias: baselineAlias))
        ORDER BY \(orderByColumns(descriptor.primaryKeyColumns, tableAlias: workingAlias))
        """,
        as: Int.self
    )
}

private func resetModifiedRows(
    descriptor: SourceTableDescriptor,
    baselineSchemaName: String,
    scope: SourceRecordScope,
    in db: Database
) throws {
    guard !descriptor.comparedColumns.isEmpty else { return }

    let workingAlias = descriptor.tableName
    let baselineAlias = "baseline"

    try #sql(
        """
        UPDATE \(qualifiedTable(descriptor.tableName))
        SET \(resetAssignments(
            descriptor.comparedColumns,
            descriptor: descriptor,
            baselineSchemaName: baselineSchemaName,
            scope: scope
        ))
        WHERE \(scopePredicate(scope, alias: workingAlias))
        AND EXISTS (
          SELECT 1
          FROM \(qualifiedTable(descriptor.tableName, schemaName: baselineSchemaName)) AS \(quote: baselineAlias)
          WHERE \(primaryKeyPredicate(descriptor.primaryKeyColumns, workingAlias: workingAlias, baselineAlias: baselineAlias))
          AND \(scopePredicate(scope, alias: baselineAlias))
        )
        """
    )
    .execute(db)
}

private func resetAssignments(
    _ columnNames: [String],
    descriptor: SourceTableDescriptor,
    baselineSchemaName: String,
    scope: SourceRecordScope
) -> QueryFragment {
    columnNames
        .map { columnName -> QueryFragment in
            let value = baselineValueSubquery(
                columnName,
                descriptor: descriptor,
                baselineSchemaName: baselineSchemaName,
                scope: scope
            )
            return "\(quote: columnName) = \(value)"
        }
        .joined(separator: ", ")
}

private func baselineValueSubquery(
    _ columnName: String,
    descriptor: SourceTableDescriptor,
    baselineSchemaName: String,
    scope: SourceRecordScope
) -> QueryFragment {
    let workingAlias = descriptor.tableName
    let baselineAlias = "baseline"

    return """
        (
          SELECT \(quote: baselineAlias).\(quote: columnName)
          FROM \(qualifiedTable(descriptor.tableName, schemaName: baselineSchemaName)) AS \(quote: baselineAlias)
          WHERE \(primaryKeyPredicate(descriptor.primaryKeyColumns, workingAlias: workingAlias, baselineAlias: baselineAlias))
          AND \(scopePredicate(scope, alias: baselineAlias))
          LIMIT 1
        )
        """
}

private func columnNames(_ columnNames: [String]) -> QueryFragment {
    columnNames
        .map { "\(quote: $0)" }
        .joined(separator: ", ")
}

private func columnSelections(
    _ columnNames: [String],
    tableAlias: String,
    outputPrefix: String = ""
) -> QueryFragment {
    columnNames
        .map { columnName in
            "\(quote: tableAlias).\(quote: columnName) AS \(quote: "\(outputPrefix)\(columnName)")"
        }
        .joined(separator: ", ")
}

private func orderByColumns(
    _ columnNames: [String],
    tableAlias: String
) -> QueryFragment {
    columnNames
        .map { "\(quote: tableAlias).\(quote: $0)" }
        .joined(separator: ", ")
}

private func qualifiedTable(
    _ tableName: String,
    schemaName: String? = nil
) -> QueryFragment {
    if let schemaName {
        return "\(quote: schemaName).\(quote: tableName)"
    }
    return "\(quote: tableName)"
}

private func primaryKeyPredicate(
    _ columnNames: [String],
    workingAlias: String,
    baselineAlias: String
) -> QueryFragment {
    let predicate = columnNames.map { columnName in
        "\(quote: workingAlias).\(quote: columnName) = \(quote: baselineAlias).\(quote: columnName)"
    }
    .joined(separator: " AND ")
    return "(\(predicate))"
}

private func primaryKeyValuesPredicate(
    _ primaryKeyValues: [SourceColumnValue]
) throws -> QueryFragment {
    guard !primaryKeyValues.isEmpty else {
        return "0"
    }

    let predicate = try primaryKeyValues.map { primaryKeyValue in
        let binding = try queryBinding(for: primaryKeyValue.value)
        return "\(quote: primaryKeyValue.columnName) = \(binding)"
    }
    .joined(separator: " AND ")
    return "(\(predicate))"
}

private func fetchRows(
    _ query: QueryFragment,
    in db: Database
) throws -> [Row] {
    let prepared = query.prepare { _ in "?" }
    return try Row.fetchAll(
        db,
        sql: prepared.sql,
        arguments: StatementArguments(
            try prepared.bindings.map { try databaseValue(for: $0) }
        )
    )
}

private func sourceColumnValues(
    _ columnNames: [String],
    in row: Row
) -> [SourceColumnValue] {
    columnNames.map { columnName in
        SourceColumnValue(
            columnName: columnName,
            value: row.databaseValue(forColumn: columnName)
        )
    }
}

private extension Row {
    func databaseValue(forColumn columnName: String) -> DatabaseValue {
        self[columnName] as DatabaseValue
    }
}

private func databaseValue(for binding: QueryBinding) throws -> DatabaseValue {
    switch binding {
    case let .blob(blob):
        return Data(blob).databaseValue
    case let .bool(bool):
        return (bool ? 1 : 0).databaseValue
    case let .date(date):
        return ISO8601DateFormatter().string(from: date).databaseValue
    case let .double(double):
        return double.databaseValue
    case let .int(int):
        return int.databaseValue
    case .null:
        return .null
    case let .text(text):
        return text.databaseValue
    case let .uint(uint):
        guard uint <= UInt64(Int64.max) else {
            throw SourceEditingUnsignedIntegerOverflow(unsignedInteger: uint)
        }
        return uint.databaseValue
    case let .uuid(uuid):
        return uuid.uuidString.lowercased().databaseValue
    case let .invalid(error):
        throw error
    }
}

private struct SourceEditingUnsignedIntegerOverflow: Error {
    var unsignedInteger: UInt64
}

private extension DatabaseValue {
    var sourceRecordDecodingDescription: String {
        switch storage {
        case .null:
            return "NULL"
        case let .int64(value):
            return String(value)
        case let .double(value):
            return String(value)
        case let .string(value):
            return "\"\(value)\""
        case let .blob(value):
            return "<\(value.count) bytes>"
        }
    }
}

private func queryBinding(for databaseValue: DatabaseValue) throws -> QueryBinding {
    switch databaseValue.storage {
    case .null:
        return .null
    case let .int64(value):
        return .int(value)
    case let .double(value):
        return .double(value)
    case let .string(value):
        return .text(value)
    case let .blob(value):
        return .blob([UInt8](value))
    }
}

private func modifiedPredicate(
    _ columnNames: [String],
    workingAlias: String,
    baselineAlias: String
) -> QueryFragment {
    let predicate = columnNames.map { columnName in
        "\(quote: workingAlias).\(quote: columnName) IS NOT \(quote: baselineAlias).\(quote: columnName)"
    }
    .joined(separator: " OR ")
    return "(\(predicate))"
}

private func scopePredicate(
    _ scope: SourceRecordScope,
    alias: String
) -> QueryFragment {
    guard !scope.filters.isEmpty else {
        return "1"
    }

    let predicate = scope.filters.map { filter in
        "\(quote: alias).\(quote: filter.columnName) = \(filter.value)"
    }
    .joined(separator: " AND ")
    return "(\(predicate))"
}
