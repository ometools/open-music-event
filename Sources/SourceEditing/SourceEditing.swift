import CustomDump
import Foundation
import GRDB
import IssueReporting
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
    case changed(AnySourceFieldComparison)
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
                AnySourceFieldComparison(
                    SourceFieldComparison(
                        change: fieldChange,
                        baseline: baseline,
                        working: working
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
    public var resolveRecordChange: (
        SourceRecordChange,
        Database,
        Database
    ) throws -> SourceResolvedRecordChange?
    public var recordComparison: (
        SourceRecordChange,
        Database,
        Database
    ) throws -> AnySourceRecordComparison?

    public init(
        descriptor: SourceTableDescriptor,
        resolveRecordChange: @escaping (
            SourceRecordChange,
            Database,
            Database
        ) throws -> SourceResolvedRecordChange?,
        recordComparison: @escaping (
            SourceRecordChange,
            Database,
            Database
        ) throws -> AnySourceRecordComparison? = { _, _, _ in nil }
    ) {
        self.descriptor = descriptor
        self.resolveRecordChange = resolveRecordChange
        self.recordComparison = recordComparison
    }

    public init(
        descriptor: SourceTableDescriptor,
        recordDiff: @escaping (
            SourceRecordChange,
            Database,
            Database
        ) throws -> String,
        recordComparison: @escaping (
            SourceRecordChange,
            Database,
            Database
        ) throws -> AnySourceRecordComparison? = { _, _, _ in nil }
    ) {
        self.init(
            descriptor: descriptor,
            resolveRecordChange: { change, workingDatabase, baselineDatabase in
                var change = change
                change.recordDiff = try recordDiff(change, workingDatabase, baselineDatabase)
                return SourceResolvedRecordChange(change: change)
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
            resolveRecordChange: { change, workingDatabase, baselineDatabase in
                var retainedFieldChanges: [SourceFieldChange] = []
                var rawFieldChanges: [SourceFieldChange] = []
                var fieldComparisons: [AnySourceFieldComparison] = []

                for fieldChange in change.fieldChanges {
                    guard let policy = policiesByColumnName[fieldChange.columnName] else {
                        retainedFieldChanges.append(fieldChange)
                        rawFieldChanges.append(fieldChange)
                        continue
                    }

                    switch policy.resolve(fieldChange) {
                    case .ignored, .unchanged:
                        continue

                    case let .changed(comparison):
                        retainedFieldChanges.append(fieldChange)
                        fieldComparisons.append(comparison)

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
                        .resolveRecordChange(rawChange, workingDatabase, baselineDatabase)
                    rawRecordDiff = resolvedRawChange?.change.recordDiff
                }

                var resolvedChange = change
                resolvedChange.fieldChanges = retainedFieldChanges

                let policyRecordDiffs = fieldComparisons
                    .compactMap(\.difference)
                let recordDiffs = ([rawRecordDiff].compactMap(\.self) + policyRecordDiffs)
                    .filter { !$0.isEmpty }
                if !recordDiffs.isEmpty {
                    resolvedChange.recordDiff = recordDiffs.joined(separator: "\n")
                } else if !rawFieldChanges.isEmpty {
                    resolvedChange.recordDiff = rawRecordDiff
                } else {
                    resolvedChange.recordDiff = nil
                }
                return SourceResolvedRecordChange(
                    change: resolvedChange,
                    fieldComparisons: fieldComparisons
                )
            },
            recordComparison: { change, workingDatabase, baselineDatabase in
                try rawRecordType.recordComparison(change, workingDatabase, baselineDatabase)
            }
        )
    }

    private static func rawSourceRecordType(
        descriptor: SourceTableDescriptor
    ) -> AnySourceEditableRecordType {
        AnySourceEditableRecordType(
            descriptor: descriptor,
            recordDiff: { change, workingDatabase, baselineDatabase in
                let includedColumnNames = Set(
                    change.fieldChanges.map(\.columnName)
                )
                let baseline = SourceRecordDiffSnapshot(
                    snapshot: try sourceRecordSnapshot(
                        for: change,
                        in: baselineDatabase
                    ),
                    includedColumnNames: includedColumnNames
                )
                let working = SourceRecordDiffSnapshot(
                    snapshot: try sourceRecordSnapshot(
                        for: change,
                        in: workingDatabase
                    ),
                    includedColumnNames: includedColumnNames
                )

                return diff(baseline, working) ?? ""
            },
            recordComparison: { change, workingDatabase, baselineDatabase in
                AnySourceRecordComparison(
                    SourceRecordComparison(
                        change: change,
                        left: try sourceRecord(
                            for: change,
                            in: baselineDatabase
                        ),
                        right: try sourceRecord(
                            for: change,
                            in: workingDatabase
                        )
                    )
                )
            }
        )
    }

    private static func sourceRecordSnapshot(
        for change: SourceRecordChange,
        in db: Database
    ) throws -> SourceRecordSnapshot<QueryOutput> {
        if let record = try sourceRecord(
            for: change,
            in: db
        ) {
            return .record(record)
        }
        return .missing
    }

    static func sourceRecord(
        for change: SourceRecordChange,
        in db: Database
    ) throws -> QueryOutput? {
        do {
            return try SQLQueryExpression<Self>(
                """
                SELECT *
                FROM \(qualifiedTable(tableName))
                WHERE \(try primaryKeyValuesPredicate(change.primaryKeyValues))
                LIMIT 1
                """,
                as: Self.self
            )
            .fetchOne(db)
        } catch {
            throw SourceRecordDecodingError(
                tableName: tableName,
                schemaName: "main",
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

public struct SourceFieldComparison<Value>: Sendable
where Value: Equatable & Sendable {
    public var change: SourceFieldChange
    public var baseline: Value?
    public var working: Value?

    public init(
        change: SourceFieldChange,
        baseline: Value?,
        working: Value?
    ) {
        self.change = change
        self.baseline = baseline
        self.working = working
    }
}

extension SourceFieldComparison: Equatable {}

public struct AnySourceFieldComparison: Sendable, Equatable, Hashable, Identifiable {
    public var id: SourceFieldChange.ID { change.id }

    public var change: SourceFieldChange
    public var valueTypeID: ObjectIdentifier
    public var valueTypeName: String

    private var baseline: (any Sendable)?
    private var working: (any Sendable)?
    private var differenceValue: @Sendable () -> String?

    public init<Value>(
        _ comparison: SourceFieldComparison<Value>
    ) where Value: Equatable & Sendable {
        self.change = comparison.change
        self.valueTypeID = ObjectIdentifier(Value.self)
        self.valueTypeName = String(reflecting: Value.self)
        self.baseline = comparison.baseline
        self.working = comparison.working
        self.differenceValue = {
            diff(
                SourceColumnPolicyComparisonValue(
                    columnName: comparison.change.columnName,
                    value: comparison.baseline
                ),
                SourceColumnPolicyComparisonValue(
                    columnName: comparison.change.columnName,
                    value: comparison.working
                )
            )
        }
    }

    public var difference: String? {
        differenceValue()
    }

    public func `as`<Value>(
        _ valueType: Value.Type
    ) -> SourceFieldComparison<Value>?
    where Value: Equatable & Sendable {
        guard valueTypeID == ObjectIdentifier(valueType) else { return nil }
        return SourceFieldComparison(
            change: change,
            baseline: baseline as? Value,
            working: working as? Value
        )
    }

    public static func == (
        lhs: AnySourceFieldComparison,
        rhs: AnySourceFieldComparison
    ) -> Bool {
        lhs.change == rhs.change
            && lhs.valueTypeID == rhs.valueTypeID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(change)
        hasher.combine(valueTypeID)
    }
}

extension AnySourceFieldComparison: CustomDumpReflectable {
    public var customDumpMirror: Mirror {
        Mirror(
            self,
            children: [
                "change": change,
                "valueTypeName": valueTypeName,
                "baseline": baseline as Any,
                "working": working as Any,
            ],
            displayStyle: .struct
        )
    }
}

public struct SourceFieldComparisons: Equatable, Hashable, Sendable {
    public static var empty: Self { Self() }

    private var comparisonsByRecordChangeID:
        [SourceRecordChange.ID: [SourceFieldChange.ID: AnySourceFieldComparison]]

    public init() {
        self.comparisonsByRecordChangeID = [:]
    }

    public subscript(
        _ recordChange: SourceRecordChange,
        _ fieldChange: SourceFieldChange
    ) -> AnySourceFieldComparison? {
        comparisonsByRecordChangeID[recordChange.id]?[fieldChange.id]
    }

    public mutating func insert(
        _ comparison: AnySourceFieldComparison,
        for recordChange: SourceRecordChange
    ) {
        comparisonsByRecordChangeID[recordChange.id, default: [:]][comparison.id] = comparison
    }

    public mutating func append(contentsOf other: Self) {
        for (recordChangeID, comparisons) in other.comparisonsByRecordChangeID {
            comparisonsByRecordChangeID[recordChangeID, default: [:]]
                .merge(comparisons) { _, new in new }
        }
    }
}

public struct SourceResolvedRecordChange: Equatable, Hashable, Sendable {
    public var change: SourceRecordChange
    public var fieldComparisons: [AnySourceFieldComparison]

    public init(
        change: SourceRecordChange,
        fieldComparisons: [AnySourceFieldComparison] = []
    ) {
        self.change = change
        self.fieldComparisons = fieldComparisons
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
    public var recordTypeDisplayName: String

    private var left: (any Sendable)?
    private var right: (any Sendable)?

    public init<Record: Sendable>(
        _ comparison: SourceRecordComparison<Record>
    ) {
        self.change = comparison.change
        self.recordTypeID = ObjectIdentifier(Record.self)
        self.recordTypeName = String(reflecting: Record.self)
        self.recordTypeDisplayName = String(describing: Record.self)
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
    public var fieldComparisons: SourceFieldComparisons
    public var recordComparisons: SourceRecordComparisons

    public init(
        availability: Availability,
        groups: [SourceChangeGroup],
        fieldComparisons: SourceFieldComparisons = .empty,
        recordComparisons: SourceRecordComparisons = .empty
    ) {
        self.availability = availability
        self.groups = groups
        self.fieldComparisons = fieldComparisons
        self.recordComparisons = recordComparisons
    }

    public var totalCount: Int {
        groups.reduce(0) { $0 + $1.totalCount }
    }
}

public struct SourceEditingResetter: Sendable {
    public init() {}

    public func reset(
        workingDatabase: Database,
        baselineDatabase: Database,
        descriptors: [SourceTableDescriptor],
        scope: SourceRecordScope = .all
    ) throws {
        for descriptor in descriptors.reversed() {
            let changes = try sourceRecordChanges(
                descriptor: descriptor,
                workingDatabase: workingDatabase,
                baselineDatabase: baselineDatabase,
                scope: scope
            )
            for change in changes where change.kind == .added {
                try deleteRecord(change, descriptor: descriptor, in: workingDatabase)
            }
        }

        for descriptor in descriptors {
            let changes = try sourceRecordChanges(
                descriptor: descriptor,
                workingDatabase: workingDatabase,
                baselineDatabase: baselineDatabase,
                scope: scope
            )
            for change in changes where change.kind == .deleted {
                try insertBaselineRecord(
                    change,
                    descriptor: descriptor,
                    baselineDatabase: baselineDatabase,
                    workingDatabase: workingDatabase
                )
            }
        }

        for descriptor in descriptors {
            let changes = try sourceRecordChanges(
                descriptor: descriptor,
                workingDatabase: workingDatabase,
                baselineDatabase: baselineDatabase,
                scope: scope
            )
            for change in changes where change.kind == .modified {
                try resetModifiedRecord(
                    change,
                    descriptor: descriptor,
                    baselineDatabase: baselineDatabase,
                    workingDatabase: workingDatabase
                )
            }
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
        workingDatabase: Database,
        baselineDatabase: Database,
        descriptors: [SourceTableDescriptor],
        scope: SourceRecordScope = .all
    ) throws -> SourceChangeSummary {
        let mismatches = try schemaMismatches(
            workingDatabase: workingDatabase,
            baselineDatabase: baselineDatabase,
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
                workingDatabase: workingDatabase,
                baselineDatabase: baselineDatabase,
                scope: scope
            )
        }
        return SourceChangeSummary(
            availability: .available,
            groups: groups
        )
    }

    public func summary(
        workingDatabase: Database,
        baselineDatabase: Database,
        recordTypes: [AnySourceEditableRecordType],
        scope: SourceRecordScope = .all
    ) throws -> SourceChangeSummary {
        let summary = try summary(
            workingDatabase: workingDatabase,
            baselineDatabase: baselineDatabase,
            descriptors: recordTypes.map(\.descriptor),
            scope: scope
        )
        guard case .available = summary.availability else {
            return summary
        }

        let recordTypesByID = Dictionary(
            uniqueKeysWithValues: recordTypes.map { ($0.descriptor.id, $0) }
        )
        var fieldComparisons = SourceFieldComparisons.empty
        var recordComparisons: [AnySourceRecordComparison] = []
        let groups = try summary.groups.map { group in
            guard let recordType = recordTypesByID[group.id] else {
                return group
            }

            var group = group
            group.records = try group.records.compactMap { record in
                do {
                    guard let resolution = try recordType.resolveRecordChange(
                        record,
                        workingDatabase,
                        baselineDatabase
                    ) else { return nil }
                    let resolvedRecord = resolution.change
                    for comparison in resolution.fieldComparisons {
                        fieldComparisons.insert(
                            comparison,
                            for: resolvedRecord
                        )
                    }
                    do {
                        if let comparison = try recordType.recordComparison(
                            resolvedRecord,
                            workingDatabase,
                            baselineDatabase
                        ) {
                            recordComparisons.append(comparison)
                        }
                    } catch let error as SourceRecordDecodingError {
                        reportIssue("Unable to build typed source record comparison. \(error)")
                    }
                    return resolvedRecord
                } catch let error as SourceRecordDecodingError {
                    reportIssue("Unable to resolve source record fields. \(error)")
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
            fieldComparisons: fieldComparisons,
            recordComparisons: SourceRecordComparisons(recordComparisons)
        )
    }

    private func schemaMismatches(
        workingDatabase: Database,
        baselineDatabase: Database,
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
                in: workingDatabase,
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
                in: baselineDatabase,
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
        workingDatabase: Database,
        baselineDatabase: Database,
        scope: SourceRecordScope
    ) throws -> SourceChangeGroup {
        let records = try sourceRecordChanges(
            descriptor: descriptor,
            workingDatabase: workingDatabase,
            baselineDatabase: baselineDatabase,
            scope: scope
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

}

private func tableColumnNames(
    in db: Database,
    tableName: String
) throws -> Set<String> {
    Set(
        try #sql(
            "SELECT name FROM pragma_table_info(\(bind: tableName))",
            as: String.self
        )
        .fetchAll(db)
    )
}

private struct SourceDatabaseRow {
    var primaryKeyValues: [SourceColumnValue]
    var values: [String: DatabaseValue]
}

private func sourceRecordChanges(
    descriptor: SourceTableDescriptor,
    workingDatabase: Database,
    baselineDatabase: Database,
    scope: SourceRecordScope
) throws -> [SourceRecordChange] {
    let columnNames = descriptor.primaryKeyColumns + descriptor.comparedColumns
    let workingRows = try sourceDatabaseRows(
        descriptor: descriptor,
        columnNames: columnNames,
        scope: scope,
        in: workingDatabase
    )
    let baselineRows = try sourceDatabaseRows(
        descriptor: descriptor,
        columnNames: columnNames,
        scope: scope,
        in: baselineDatabase
    )
    let workingRowsByPrimaryKey = Dictionary(
        uniqueKeysWithValues: workingRows.map { ($0.primaryKeyValues, $0) }
    )
    let baselineRowsByPrimaryKey = Dictionary(
        uniqueKeysWithValues: baselineRows.map { ($0.primaryKeyValues, $0) }
    )

    let added = workingRows.compactMap { workingRow -> SourceRecordChange? in
        guard baselineRowsByPrimaryKey[workingRow.primaryKeyValues] == nil else { return nil }
        return SourceRecordChange(
            tableID: descriptor.id,
            kind: .added,
            primaryKeyValues: workingRow.primaryKeyValues,
            fieldChanges: descriptor.comparedColumns.map { columnName in
                SourceFieldChange(
                    columnName: columnName,
                    baselineValue: nil,
                    workingValue: workingRow.values[columnName]
                )
            }
        )
    }
    let modified = workingRows.compactMap { workingRow -> SourceRecordChange? in
        guard let baselineRow = baselineRowsByPrimaryKey[workingRow.primaryKeyValues] else {
            return nil
        }
        let fieldChanges = descriptor.comparedColumns.compactMap {
            columnName -> SourceFieldChange? in
            let baselineValue = baselineRow.values[columnName]
            let workingValue = workingRow.values[columnName]
            guard baselineValue != workingValue else { return nil }
            return SourceFieldChange(
                columnName: columnName,
                baselineValue: baselineValue,
                workingValue: workingValue
            )
        }
        guard !fieldChanges.isEmpty else { return nil }
        return SourceRecordChange(
            tableID: descriptor.id,
            kind: .modified,
            primaryKeyValues: workingRow.primaryKeyValues,
            fieldChanges: fieldChanges
        )
    }
    let deleted = baselineRows.compactMap { baselineRow -> SourceRecordChange? in
        guard workingRowsByPrimaryKey[baselineRow.primaryKeyValues] == nil else { return nil }
        return SourceRecordChange(
            tableID: descriptor.id,
            kind: .deleted,
            primaryKeyValues: baselineRow.primaryKeyValues,
            fieldChanges: descriptor.comparedColumns.map { columnName in
                SourceFieldChange(
                    columnName: columnName,
                    baselineValue: baselineRow.values[columnName],
                    workingValue: nil
                )
            }
        )
    }
    return added + modified + deleted
}

private func sourceDatabaseRows(
    descriptor: SourceTableDescriptor,
    columnNames: [String],
    scope: SourceRecordScope,
    in db: Database
) throws -> [SourceDatabaseRow] {
    let alias = "record"
    let query: QueryFragment =
        """
        SELECT \(columnSelections(columnNames, tableAlias: alias))
        FROM \(qualifiedTable(descriptor.tableName)) AS \(quote: alias)
        WHERE \(scopePredicate(scope, alias: alias))
        ORDER BY \(orderByColumns(descriptor.primaryKeyColumns, tableAlias: alias))
        """
    return try fetchRows(query, in: db).map { row in
        SourceDatabaseRow(
            primaryKeyValues: sourceColumnValues(descriptor.primaryKeyColumns, in: row),
            values: Dictionary(
                uniqueKeysWithValues: columnNames.map { columnName in
                    (columnName, row.databaseValue(forColumn: columnName))
                }
            )
        )
    }
}

private func sourceDatabaseRow(
    for change: SourceRecordChange,
    descriptor: SourceTableDescriptor,
    columnNames: [String],
    in db: Database
) throws -> SourceDatabaseRow? {
    let alias = "record"
    let query: QueryFragment =
        """
        SELECT \(columnSelections(columnNames, tableAlias: alias))
        FROM \(qualifiedTable(descriptor.tableName)) AS \(quote: alias)
        WHERE \(try primaryKeyValuesPredicate(change.primaryKeyValues))
        LIMIT 1
        """
    return try fetchRows(query, in: db).first.map { row in
        SourceDatabaseRow(
            primaryKeyValues: sourceColumnValues(descriptor.primaryKeyColumns, in: row),
            values: Dictionary(
                uniqueKeysWithValues: columnNames.map { columnName in
                    (columnName, row.databaseValue(forColumn: columnName))
                }
            )
        )
    }
}

private func deleteRecord(
    _ change: SourceRecordChange,
    descriptor: SourceTableDescriptor,
    in db: Database
) throws {
    let query: QueryFragment =
        """
        DELETE FROM \(qualifiedTable(descriptor.tableName))
        WHERE \(try primaryKeyValuesPredicate(change.primaryKeyValues))
        """
    try execute(query, in: db)
}

private func insertBaselineRecord(
    _ change: SourceRecordChange,
    descriptor: SourceTableDescriptor,
    baselineDatabase: Database,
    workingDatabase: Database
) throws {
    guard let baselineRow = try sourceDatabaseRow(
        for: change,
        descriptor: descriptor,
        columnNames: descriptor.resetColumnNames,
        in: baselineDatabase
    ) else { return }
    let values = try descriptor.resetColumnNames
        .map { columnName -> QueryFragment in
            guard let value = baselineRow.values[columnName] else { return "NULL" }
            return "\(try queryBinding(for: value))"
        }
        .joined(separator: ", ")
    let query: QueryFragment =
        """
        INSERT INTO \(qualifiedTable(descriptor.tableName)) (\(columnNames(descriptor.resetColumnNames)))
        VALUES (\(values))
        """
    try execute(query, in: workingDatabase)
}

private func resetModifiedRecord(
    _ change: SourceRecordChange,
    descriptor: SourceTableDescriptor,
    baselineDatabase: Database,
    workingDatabase: Database
) throws {
    guard !descriptor.comparedColumns.isEmpty,
          let baselineRow = try sourceDatabaseRow(
              for: change,
              descriptor: descriptor,
              columnNames: descriptor.primaryKeyColumns + descriptor.comparedColumns,
              in: baselineDatabase
          )
    else { return }
    let assignments = try descriptor.comparedColumns
        .map { columnName -> QueryFragment in
            guard let value = baselineRow.values[columnName] else {
                return "\(quote: columnName) = NULL"
            }
            return "\(quote: columnName) = \(try queryBinding(for: value))"
        }
        .joined(separator: ", ")
    let query: QueryFragment =
        """
        UPDATE \(qualifiedTable(descriptor.tableName))
        SET \(assignments)
        WHERE \(try primaryKeyValuesPredicate(change.primaryKeyValues))
        """
    try execute(query, in: workingDatabase)
}

private func execute(_ query: QueryFragment, in db: Database) throws {
    let prepared = query.prepare { _ in "?" }
    try db.execute(
        sql: prepared.sql,
        arguments: StatementArguments(
            try prepared.bindings.map { try databaseValue(for: $0) }
        )
    )
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
    _ tableName: String
) -> QueryFragment {
    return "\(quote: tableName)"
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
