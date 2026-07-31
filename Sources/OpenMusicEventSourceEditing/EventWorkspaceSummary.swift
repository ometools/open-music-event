import Dependencies
import GRDB
import OpenMusicEventLexicon
import SQLiteData
import SourceEditing

public struct EventWorkspaceSummary: Equatable, Sendable {
    public enum Availability: Equatable, Sendable {
        case available
        case workspaceNeedsPreparation
        case notInWorkspace
        case unavailable(SourceChangeSummary.UnavailableReason)
    }

    public var eventID: OME.Event.ID
    public var availability: Availability
    public var groups: [SourceChangeGroup]
    public var recordComparisons: SourceRecordComparisons

    public init(
        eventID: OME.Event.ID,
        availability: Availability,
        groups: [SourceChangeGroup],
        recordComparisons: SourceRecordComparisons = .empty
    ) {
        self.eventID = eventID
        self.availability = availability
        self.groups = groups
        self.recordComparisons = recordComparisons
    }

    public var totalCount: Int {
        groups.reduce(0) { $0 + $1.totalCount }
    }

    public var badgeCount: Int? {
        guard case .available = availability, totalCount > 0 else { return nil }
        return totalCount
    }
}

public extension EventWorkspaceSummary {
    static func query(
        eventID: OME.Event.ID,
        in db: Database
    ) throws -> Self {
        let eventWorkspace = try EventEditingWorkspaceRecord
            .where { $0.id.eq(eventID) }
            .fetchOne(db)
        guard let eventWorkspace else {
            return EventWorkspaceSummary(
                eventID: eventID,
                availability: .notInWorkspace,
                groups: []
            )
        }

        let workspace = try EditingWorkspaceRecord
            .where { $0.id.eq(eventWorkspace.workspaceID) }
            .fetchOne(db)
        guard let workspace else {
            return EventWorkspaceSummary(
                eventID: eventID,
                availability: .workspaceNeedsPreparation,
                groups: []
            )
        }

        guard let baselineSchemaName = try SourceEditingSession
            .attachedBaselineSchemaName(in: db)
        else {
            return EventWorkspaceSummary(
                eventID: eventID,
                availability: .workspaceNeedsPreparation,
                groups: []
            )
        }

        let sourceProvenance = try EventSourceProvenanceRecord
            .where { $0.id.eq(eventID) }
            .fetchOne(db)
        let sourceSummary: SourceChangeSummary
        if sourceProvenance?.sourceBaselineID != nil {
            sourceSummary = try openMusicEventSourceEditSummary(
                in: db,
                baselineSchemaName: baselineSchemaName
            )
        } else if workspace.kind == .local {
            sourceSummary = try openMusicEventSourceEditSummary(
                in: db,
                baselineSchemaName: baselineSchemaName
            )
        } else {
            return EventWorkspaceSummary(
                eventID: eventID,
                availability: .notInWorkspace,
                groups: []
            )
        }

        switch sourceSummary.availability {
        case .available:
            return EventWorkspaceSummary(
                eventID: eventID,
                availability: .available,
                groups: sourceSummary.groups,
                recordComparisons: sourceSummary.recordComparisons
            )

        case let .unavailable(reason):
            return EventWorkspaceSummary(
                eventID: eventID,
                availability: .unavailable(reason),
                groups: []
            )
        }
    }
}

public struct SourceEditSummary: Equatable, Sendable {
    public enum Availability: Equatable, Sendable {
        case available
        case missingBaseline
        case unavailable(SourceChangeSummary.UnavailableReason)
    }

    public var availability: Availability
    public var groups: [SourceChangeGroup]
    public var recordComparisons: SourceRecordComparisons
    public var sourceBaselineID: SourceBaselineRecord.ID

    public init(
        sourceBaselineID: SourceBaselineRecord.ID,
        availability: Availability,
        groups: [SourceChangeGroup],
        recordComparisons: SourceRecordComparisons = .empty
    ) {
        self.sourceBaselineID = sourceBaselineID
        self.availability = availability
        self.groups = groups
        self.recordComparisons = recordComparisons
    }

    public var totalCount: Int {
        groups.reduce(0) { $0 + $1.totalCount }
    }

    public var badgeCount: Int? {
        guard case .available = availability, totalCount > 0 else { return nil }
        return totalCount
    }
}

public extension SourceEditSummary {
    static func query(
        sourceBaselineID: SourceBaselineRecord.ID,
        in db: Database
    ) throws -> Self {
        let sourceBaselineExists = try SourceBaselineRecord
            .where { $0.id.eq(sourceBaselineID) }
            .fetchOne(db)
            .map { _ in true } ?? false

        guard sourceBaselineExists else {
            return SourceEditSummary(
                sourceBaselineID: sourceBaselineID,
                availability: .missingBaseline,
                groups: []
            )
        }

        guard let baselineSchemaName = try SourceEditingSession
            .attachedBaselineSchemaName(in: db)
        else {
            return SourceEditSummary(
                sourceBaselineID: sourceBaselineID,
                availability: .missingBaseline,
                groups: []
            )
        }
        let sourceSummary = try openMusicEventSourceEditSummary(
            in: db,
            baselineSchemaName: baselineSchemaName
        )

        switch sourceSummary.availability {
        case .available:
            return SourceEditSummary(
                sourceBaselineID: sourceBaselineID,
                availability: .available,
                groups: sourceSummary.groups,
                recordComparisons: sourceSummary.recordComparisons
            )

        case let .unavailable(reason):
            return SourceEditSummary(
                sourceBaselineID: sourceBaselineID,
                availability: .unavailable(reason),
                groups: []
            )
        }
    }
}

public func openMusicEventSourceEditSummary(
    in db: Database,
    baselineSchemaName: String
) throws -> SourceChangeSummary {
    try SourceEditingComparer().summary(
        in: db,
        baselineSchemaName: baselineSchemaName,
        recordTypes: OME.sourceDiffRecordTypes
    )
}

func openMusicEventSourceEventIDs(
    in db: Database,
    baselineSchemaName: String,
    sourceBaselineID: SourceBaselineRecord.ID,
    organizerID: OME.Organizer.ID
) throws -> [OME.Event.ID] {
    let workingEventIDs = try sourceEventIDs(
        in: db,
        sourceBaselineID: sourceBaselineID
    )
    let baselineEventIDs = try baselineSourceEventIDs(
        in: db,
        baselineSchemaName: baselineSchemaName,
        sourceBaselineID: sourceBaselineID
    )

    var seen: Set<OME.Event.ID> = []
    return (workingEventIDs + baselineEventIDs)
        .filter { $0.organizerID == organizerID }
        .sorted { lhs, rhs in
            lhs.eventID.rawValue.rawValue < rhs.eventID.rawValue.rawValue
        }
        .compactMap { eventID in
            guard seen.insert(eventID).inserted else { return nil }
            return eventID
        }
}

private func sourceEventIDs(
    in db: Database,
    sourceBaselineID: SourceBaselineRecord.ID
) throws -> [OME.Event.ID] {
    try EventSourceProvenanceRecord
        .where { $0.sourceBaselineID.eq(sourceBaselineID) }
        .fetchAll(db)
        .map(\.id)
}

private func baselineSourceEventIDs(
    in db: Database,
    baselineSchemaName: String,
    sourceBaselineID: SourceBaselineRecord.ID
) throws -> [OME.Event.ID] {
    let sql = """
        SELECT "organizerID", "eventID"
        FROM \(baselineSchemaName.quotedDatabaseIdentifier)."eventSourceProvenances"
        WHERE "sourceBaselineID" = ?
        """
    return try Row
        .fetchAll(
            db,
            sql: sql,
            arguments: [sourceBaselineID.rawValue]
        )
        .compactMap { row in
            let organizerIDString: String = row["organizerID"]
            let eventIDString: String = row["eventID"]
            guard let organizerID = OME.Organizer.ID(organizerIDString) else {
                return nil
            }
            return OME.Event.ID(
                organizerID: organizerID,
                eventID: OME.ID<OME.Event>(.init(eventIDString))
            )
        }
}

public extension SourceRecordScope {
    static func openMusicEventCalendar(calendarID: OME.Calendar.ID) -> Self {
        SourceRecordScope(
            filters: [
                SourceRecordScope.Filter(
                    columnName: "ownerID",
                    value: calendarID.ownerID.queryBinding
                ),
                SourceRecordScope.Filter(
                    columnName: "calendarID",
                    value: calendarID.calendarID.rawValue.rawValue.queryBinding
                ),
            ]
        )
    }

    static func openMusicEventWorkspace(_ workspaceID: EditingWorkspaceRecord.ID) -> Self {
        SourceRecordScope(
            filters: [
                SourceRecordScope.Filter(
                    columnName: "workspaceID",
                    value: workspaceID.rawValue.queryBinding
                ),
            ]
        )
    }
}
