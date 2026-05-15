import Dependencies
import Foundation
import SQLiteData

public protocol SourceEditableTable: PrimaryKeyedTable {
    static var sourceIgnoredColumnNames: Set<String> { get }
    static var sourceDisplayName: String { get }
}

public extension SourceEditableTable {
    static var sourceIgnoredColumnNames: Set<String> { [] }

    static var sourceDisplayName: String {
        String(describing: Self.self)
    }

    static var sourceDescriptor: SourceTableDescriptor {
        let primaryKeyColumns = columns.primaryKey._names

        let excludedColumns = Set(primaryKeyColumns).union(sourceIgnoredColumnNames)
        let comparedColumns = TableColumns.writableColumns
            .flatMap(\._names)
            .filter { !excludedColumns.contains($0) }

        return SourceTableDescriptor(
            id: tableName,
            tableName: tableName,
            primaryKeyColumns: primaryKeyColumns,
            comparedColumns: comparedColumns,
            displayName: sourceDisplayName
        )
    }
}

public struct SourceTableDescriptor: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var tableName: String
    public var primaryKeyColumns: [String]
    public var comparedColumns: [String]
    public var displayName: String

    public init(
        id: String,
        tableName: String,
        primaryKeyColumns: [String],
        comparedColumns: [String],
        displayName: String
    ) {
        self.id = id
        self.tableName = tableName
        self.primaryKeyColumns = primaryKeyColumns
        self.comparedColumns = comparedColumns
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

public struct SourceChangeGroup: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var added: Int
    public var modified: Int
    public var deleted: Int

    public init(
        id: String,
        displayName: String,
        added: Int,
        modified: Int,
        deleted: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.added = added
        self.modified = modified
        self.deleted = deleted
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

    public init(
        availability: Availability,
        groups: [SourceChangeGroup]
    ) {
        self.availability = availability
        self.groups = groups
    }

    public var totalCount: Int {
        groups.reduce(0) { $0 + $1.totalCount }
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
        let added = try fetchCount(
            addedRowsQuery(
                descriptor: descriptor,
                baselineSchemaName: baselineSchemaName,
                scope: scope
            ),
            in: db
        )
        let deleted = try fetchCount(
            deletedRowsQuery(
                descriptor: descriptor,
                baselineSchemaName: baselineSchemaName,
                scope: scope
            ),
            in: db
        )
        let modified = try fetchCount(
            modifiedRowsQuery(
                descriptor: descriptor,
                baselineSchemaName: baselineSchemaName,
                scope: scope
            ),
            in: db
        )

        return SourceChangeGroup(
            id: descriptor.id,
            displayName: descriptor.displayName,
            added: added,
            modified: modified,
            deleted: deleted
        )
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

private func fetchCount(
    _ query: SQLQueryExpression<Int>,
    in db: Database
) throws -> Int {
    try query.fetchOne(db) ?? 0
}

private func addedRowsQuery(
    descriptor: SourceTableDescriptor,
    baselineSchemaName: String,
    scope: SourceRecordScope
) -> SQLQueryExpression<Int> {
    let workingAlias = "working"
    let baselineAlias = "baseline"

    return #sql(
        """
        SELECT count(*)
        FROM \(qualifiedTable(descriptor.tableName)) AS \(quote: workingAlias)
        WHERE \(scopePredicate(scope, alias: workingAlias))
        AND NOT EXISTS (
          SELECT 1
          FROM \(qualifiedTable(descriptor.tableName, schemaName: baselineSchemaName)) AS \(quote: baselineAlias)
          WHERE \(primaryKeyPredicate(descriptor.primaryKeyColumns, workingAlias: workingAlias, baselineAlias: baselineAlias))
          AND \(scopePredicate(scope, alias: baselineAlias))
        )
        """,
        as: Int.self
    )
}

private func deletedRowsQuery(
    descriptor: SourceTableDescriptor,
    baselineSchemaName: String,
    scope: SourceRecordScope
) -> SQLQueryExpression<Int> {
    let workingAlias = "working"
    let baselineAlias = "baseline"

    return #sql(
        """
        SELECT count(*)
        FROM \(qualifiedTable(descriptor.tableName, schemaName: baselineSchemaName)) AS \(quote: baselineAlias)
        WHERE \(scopePredicate(scope, alias: baselineAlias))
        AND NOT EXISTS (
          SELECT 1
          FROM \(qualifiedTable(descriptor.tableName)) AS \(quote: workingAlias)
          WHERE \(primaryKeyPredicate(descriptor.primaryKeyColumns, workingAlias: workingAlias, baselineAlias: baselineAlias))
          AND \(scopePredicate(scope, alias: workingAlias))
        )
        """,
        as: Int.self
    )
}

private func modifiedRowsQuery(
    descriptor: SourceTableDescriptor,
    baselineSchemaName: String,
    scope: SourceRecordScope
) -> SQLQueryExpression<Int> {
    guard !descriptor.comparedColumns.isEmpty else {
        return #sql("SELECT 0", as: Int.self)
    }

    let workingAlias = "working"
    let baselineAlias = "baseline"

    return #sql(
        """
        SELECT count(*)
        FROM \(qualifiedTable(descriptor.tableName)) AS \(quote: workingAlias)
        INNER JOIN \(qualifiedTable(descriptor.tableName, schemaName: baselineSchemaName)) AS \(quote: baselineAlias)
        ON \(primaryKeyPredicate(descriptor.primaryKeyColumns, workingAlias: workingAlias, baselineAlias: baselineAlias))
        WHERE \(scopePredicate(scope, alias: workingAlias))
        AND \(scopePredicate(scope, alias: baselineAlias))
        AND \(modifiedPredicate(descriptor.comparedColumns, workingAlias: workingAlias, baselineAlias: baselineAlias))
        """,
        as: Int.self
    )
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
