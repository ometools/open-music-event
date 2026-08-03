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

    public var totalCount: Int { groups.reduce(0) { $0 + $1.totalCount } }
    public var badgeCount: Int? {
        guard case .available = availability, totalCount > 0 else { return nil }
        return totalCount
    }
}

public extension EventWorkspaceSummary {
    static func query(
        eventID: OME.Event.ID,
        using database: any DatabaseReader
    ) throws -> Self {
        try database.read { db in try query(eventID: eventID, in: db) }
    }

    static func query(eventID: OME.Event.ID, in db: Database) throws -> Self {
        guard try EventSourceProvenanceRecord.find(eventID).fetchOne(db)?.workspace != nil else {
            return Self(eventID: eventID, availability: .notInWorkspace, groups: [])
        }
        guard let baseline = try SourceEditingSession.attachedBaselineSchemaName(in: db) else {
            return Self(
                eventID: eventID,
                availability: .workspaceNeedsPreparation,
                groups: []
            )
        }

        let summary = try sourceSummary(
            projections: OME.sourceEventProjections,
            in: db,
            baselineSchemaName: baseline,
            scope: { _ in .openMusicEvent(eventID: eventID) }
        )
        switch summary.availability {
        case .available:
            return Self(
                eventID: eventID,
                availability: .available,
                groups: summary.groups,
                recordComparisons: summary.recordComparisons
            )
        case let .unavailable(reason):
            return Self(eventID: eventID, availability: .unavailable(reason), groups: [])
        }
    }
}

public struct SourceWorkspaceEditSummary: Equatable, Sendable {
    public enum Availability: Equatable, Sendable {
        case available
        case workspaceNeedsPreparation
        case unavailable(SourceChangeSummary.UnavailableReason)
    }

    public var workspaceID: SourceWorkspace.ID
    public var availability: Availability
    public var groups: [SourceChangeGroup]
    public var recordComparisons: SourceRecordComparisons

    public init(
        workspaceID: SourceWorkspace.ID,
        availability: Availability,
        groups: [SourceChangeGroup],
        recordComparisons: SourceRecordComparisons = .empty
    ) {
        self.workspaceID = workspaceID
        self.availability = availability
        self.groups = groups
        self.recordComparisons = recordComparisons
    }

    public var totalCount: Int { groups.reduce(0) { $0 + $1.totalCount } }
    public var badgeCount: Int? {
        guard case .available = availability, totalCount > 0 else { return nil }
        return totalCount
    }

    public static func query(workspace: SourceWorkspace, in db: Database) throws -> Self {
        guard let baseline = try SourceEditingSession.attachedBaselineSchemaName(in: db) else {
            return Self(
                workspaceID: workspace.id,
                availability: .workspaceNeedsPreparation,
                groups: []
            )
        }
        let summary = try openMusicEventSourceEditSummary(
            workspace: workspace,
            in: db,
            baselineSchemaName: baseline
        )
        switch summary.availability {
        case .available:
            return Self(
                workspaceID: workspace.id,
                availability: .available,
                groups: summary.groups,
                recordComparisons: summary.recordComparisons
            )
        case let .unavailable(reason):
            return Self(
                workspaceID: workspace.id,
                availability: .unavailable(reason),
                groups: []
            )
        }
    }
}

public func openMusicEventSourceEditSummary(
    workspace: SourceWorkspace,
    in db: Database,
    baselineSchemaName: String
) throws -> SourceChangeSummary {
    try sourceSummary(
        projections: OME.sourceProjections,
        in: db,
        baselineSchemaName: baselineSchemaName,
        scope: { sourceScope(for: $0, workspace: workspace) }
    )
}

private func sourceSummary(
    projections: [OpenMusicEventSourceProjection],
    in db: Database,
    baselineSchemaName: String,
    scope: (OpenMusicEventSourceProjection) -> SourceRecordScope
) throws -> SourceChangeSummary {
    var groups: [SourceChangeGroup] = []
    var comparisons: [AnySourceRecordComparison] = []
    for projection in projections {
        let summary = try SourceEditingComparer().summary(
            in: db,
            baselineSchemaName: baselineSchemaName,
            recordTypes: [projection.recordType],
            scope: scope(projection)
        )
        guard case .available = summary.availability else { return summary }
        groups.append(contentsOf: summary.groups)
        comparisons.append(contentsOf: summary.recordComparisons.values)
    }
    return SourceChangeSummary(
        availability: .available,
        groups: groups,
        recordComparisons: SourceRecordComparisons(comparisons)
    )
}

func sourceScope(
    for projection: OpenMusicEventSourceProjection,
    workspace: SourceWorkspace
) -> SourceRecordScope {
    switch projection.fileFamily {
    case .calendar:
        .openMusicEventCalendar(organizerID: workspace.organizerID)
    case .collaborator:
        .openMusicEventWorkspace(workspace.id)
    case .event, .stage, .contributor, .schedule, .channel, .poster:
        .openMusicEventOrganizer(workspace.organizerID)
    }
}

public extension SourceRecordScope {
    static func openMusicEvent(eventID: OME.Event.ID) -> Self {
        Self(filters: [
            .init(columnName: "organizerID", value: eventID.organizerID.queryBinding),
            .init(
                columnName: "eventID",
                value: eventID.eventID.rawValue.rawValue.queryBinding
            ),
        ])
    }

    static func openMusicEventOrganizer(_ organizerID: OME.Organizer.ID) -> Self {
        Self(filters: [.init(columnName: "organizerID", value: organizerID.queryBinding)])
    }

    static func openMusicEventCalendar(organizerID: OME.Organizer.ID) -> Self {
        Self(filters: [
            .init(columnName: "ownerID", value: organizerID.queryBinding),
            .init(
                columnName: "calendarID",
                value: OME.Calendar.defaultID.rawValue.rawValue.queryBinding
            ),
        ])
    }

    static func openMusicEventWorkspace(_ workspaceID: SourceWorkspace.ID) -> Self {
        Self(filters: [.init(columnName: "workspaceID", value: workspaceID.rawValue.queryBinding)])
    }
}
