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
    public var fieldComparisons: SourceFieldComparisons
    public var recordComparisons: SourceRecordComparisons

    public init(
        eventID: OME.Event.ID,
        availability: Availability,
        groups: [SourceChangeGroup],
        fieldComparisons: SourceFieldComparisons = .empty,
        recordComparisons: SourceRecordComparisons = .empty
    ) {
        self.eventID = eventID
        self.availability = availability
        self.groups = groups
        self.fieldComparisons = fieldComparisons
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
        using database: any DatabaseReader,
        referenceDatabase: SourceBaselineDatabase? = nil
    ) throws -> Self {
        try database.read { db in
            try query(
                eventID: eventID,
                in: db,
                referenceDatabase: referenceDatabase
            )
        }
    }

    static func query(
        eventID: OME.Event.ID,
        in db: Database,
        referenceDatabase: SourceBaselineDatabase? = nil
    ) throws -> Self {
        guard try EventSourceProvenanceRecord.find(eventID).fetchOne(db)?.workspace != nil else {
            return Self(eventID: eventID, availability: .notInWorkspace, groups: [])
        }
        guard let referenceDatabase else {
            return Self(
                eventID: eventID,
                availability: .workspaceNeedsPreparation,
                groups: []
            )
        }

        let summary = try referenceDatabase.read { baselineDatabase in
            try sourceSummary(
                projections: OME.sourceEventProjections,
                workingDatabase: db,
                baselineDatabase: baselineDatabase,
                scope: { _ in .openMusicEvent(eventID: eventID) }
            )
        }
        switch summary.availability {
        case .available:
            return Self(
                eventID: eventID,
                availability: .available,
                groups: summary.groups,
                fieldComparisons: summary.fieldComparisons,
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
    public var fieldComparisons: SourceFieldComparisons
    public var recordComparisons: SourceRecordComparisons

    public init(
        workspaceID: SourceWorkspace.ID,
        availability: Availability,
        groups: [SourceChangeGroup],
        fieldComparisons: SourceFieldComparisons = .empty,
        recordComparisons: SourceRecordComparisons = .empty
    ) {
        self.workspaceID = workspaceID
        self.availability = availability
        self.groups = groups
        self.fieldComparisons = fieldComparisons
        self.recordComparisons = recordComparisons
    }

    public var totalCount: Int { groups.reduce(0) { $0 + $1.totalCount } }
    public var badgeCount: Int? {
        guard case .available = availability, totalCount > 0 else { return nil }
        return totalCount
    }

    public static func query(
        workspace: SourceWorkspace,
        in db: Database,
        referenceDatabase: SourceBaselineDatabase? = nil
    ) throws -> Self {
        guard let referenceDatabase else {
            return Self(
                workspaceID: workspace.id,
                availability: .workspaceNeedsPreparation,
                groups: []
            )
        }
        let summary = try referenceDatabase.read { baselineDatabase in
            try openMusicEventSourceEditSummary(
                workspace: workspace,
                workingDatabase: db,
                baselineDatabase: baselineDatabase
            )
        }
        switch summary.availability {
        case .available:
            return Self(
                workspaceID: workspace.id,
                availability: .available,
                groups: summary.groups,
                fieldComparisons: summary.fieldComparisons,
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
    workingDatabase: Database,
    baselineDatabase: Database
) throws -> SourceChangeSummary {
    try sourceSummary(
        projections: OME.sourceProjections,
        workingDatabase: workingDatabase,
        baselineDatabase: baselineDatabase,
        scope: { sourceScope(for: $0, workspace: workspace) }
    )
}

private func sourceSummary(
    projections: [OpenMusicEventSourceProjection],
    workingDatabase: Database,
    baselineDatabase: Database,
    scope: (OpenMusicEventSourceProjection) -> SourceRecordScope
) throws -> SourceChangeSummary {
    var groups: [SourceChangeGroup] = []
    var fieldComparisons = SourceFieldComparisons.empty
    var comparisons: [AnySourceRecordComparison] = []
    for projection in projections {
        let summary = try SourceEditingComparer().summary(
            workingDatabase: workingDatabase,
            baselineDatabase: baselineDatabase,
            recordTypes: [projection.recordType],
            scope: scope(projection)
        )
        guard case .available = summary.availability else { return summary }
        groups.append(contentsOf: summary.groups)
        fieldComparisons.append(contentsOf: summary.fieldComparisons)
        comparisons.append(contentsOf: summary.recordComparisons.values)
    }
    return SourceChangeSummary(
        availability: .available,
        groups: groups,
        fieldComparisons: fieldComparisons,
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
