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

public struct EventWorkspaceSummaryRequest: FetchKeyRequest {
    public var eventID: OME.Event.ID

    public init(eventID: OME.Event.ID) {
        self.eventID = eventID
    }

    public func fetch(_ db: Database) throws -> EventWorkspaceSummary {
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

        let workspaceExists = try EditingWorkspaceRecord
            .where { $0.id.eq(eventWorkspace.workspaceID) }
            .fetchOne(db)
            .map { _ in true } ?? false
        guard workspaceExists else {
            return EventWorkspaceSummary(
                eventID: eventID,
                availability: .workspaceNeedsPreparation,
                groups: []
            )
        }

        @Dependency(\.sourceEditingSession) var sourceEditingSession
        guard let sourceEditingSession else {
            return EventWorkspaceSummary(
                eventID: eventID,
                availability: .workspaceNeedsPreparation,
                groups: []
            )
        }
        let sourceSummary = try sourceEditingSession.withAttachedBaseline(to: db) { baselineSchemaName in
            try SourceEditingComparer().summary(
                in: db,
                baselineSchemaName: baselineSchemaName,
                recordTypes: OME.sourceRecordTypes,
                scope: .openMusicEvent(eventID: eventID)
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

public struct SourceEditSummaryRequest: FetchKeyRequest {
    public var calendarID: OME.Calendar.ID
    public var sourceBaselineID: SourceBaselineRecord.ID

    public init(
        sourceBaselineID: SourceBaselineRecord.ID,
        calendarID: OME.Calendar.ID
    ) {
        self.sourceBaselineID = sourceBaselineID
        self.calendarID = calendarID
    }

    public func fetch(_ db: Database) throws -> SourceEditSummary {
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

        @Dependency(\.sourceEditingSession) var sourceEditingSession
        guard let sourceEditingSession else {
            return SourceEditSummary(
                sourceBaselineID: sourceBaselineID,
                availability: .missingBaseline,
                groups: []
            )
        }
        let sourceSummary = try sourceEditingSession.withAttachedBaseline(to: db) { baselineSchemaName in
            try sourceEditSummary(
                in: db,
                baselineSchemaName: baselineSchemaName,
                sourceBaselineID: sourceBaselineID,
                calendarID: calendarID
            )
        }

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

private func sourceEditSummary(
    in db: Database,
    baselineSchemaName: String,
    sourceBaselineID: SourceBaselineRecord.ID,
    calendarID: OME.Calendar.ID
) throws -> SourceChangeSummary {
    let comparer = SourceEditingComparer()
    let calendarSummary = try comparer.summary(
        in: db,
        baselineSchemaName: baselineSchemaName,
        recordTypes: OME.sourceMetadataRecordTypes,
        scope: .openMusicEventCalendar(calendarID: calendarID)
    )
    guard case .available = calendarSummary.availability else {
        return calendarSummary
    }

    var summaries = [calendarSummary]
    for eventID in try sourceEventIDs(
        in: db,
        baselineSchemaName: baselineSchemaName,
        sourceBaselineID: sourceBaselineID,
        organizerID: calendarID.ownerID
    ) {
        let eventSummary = try comparer.summary(
            in: db,
            baselineSchemaName: baselineSchemaName,
            recordTypes: OME.sourceRecordTypes,
            scope: .openMusicEvent(eventID: eventID)
        )
        guard case .available = eventSummary.availability else {
            return eventSummary
        }
        summaries.append(eventSummary)
    }

    return SourceChangeSummary(
        availability: .available,
        groups: mergedSourceChangeGroups(summaries.flatMap(\.groups)),
        recordComparisons: mergedSourceRecordComparisons(summaries)
    )
}

private func sourceEventIDs(
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

private func mergedSourceChangeGroups(
    _ groups: [SourceChangeGroup]
) -> [SourceChangeGroup] {
    var orderedIDs: [SourceChangeGroup.ID] = []
    var groupsByID: [SourceChangeGroup.ID: SourceChangeGroup] = [:]

    for group in groups {
        if groupsByID[group.id] == nil {
            orderedIDs.append(group.id)
            groupsByID[group.id] = group
        } else {
            groupsByID[group.id]?.added += group.added
            groupsByID[group.id]?.modified += group.modified
            groupsByID[group.id]?.deleted += group.deleted
            groupsByID[group.id]?.records.append(contentsOf: group.records)
        }
    }

    return orderedIDs.compactMap { groupsByID[$0] }
}

private func mergedSourceRecordComparisons(
    _ summaries: [SourceChangeSummary]
) -> SourceRecordComparisons {
    SourceRecordComparisons(summaries.flatMap(\.recordComparisons.values))
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
}
