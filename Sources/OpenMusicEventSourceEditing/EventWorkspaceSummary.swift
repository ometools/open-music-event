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
    public var presentation: OME.WorkspaceProposal.Presentation

    public init(
        workspaceID: SourceWorkspace.ID,
        availability: Availability,
        groups: [SourceChangeGroup],
        fieldComparisons: SourceFieldComparisons = .empty,
        recordComparisons: SourceRecordComparisons = .empty,
        presentation: OME.WorkspaceProposal.Presentation = .empty
    ) {
        self.workspaceID = workspaceID
        self.availability = availability
        self.groups = groups
        self.fieldComparisons = fieldComparisons
        self.recordComparisons = recordComparisons
        self.presentation = presentation
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
                recordComparisons: summary.recordComparisons,
                presentation: try SourceChangePresentationRenderer().render(summary)
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

public enum CanonicalWorkspaceRecordChanges {
    public static func hasChanges(
        workspace: SourceWorkspace,
        in database: Database,
        referenceDatabase: SourceBaselineDatabase
    ) throws -> Bool {
        let current = try Snapshot(in: database, organizerID: workspace.organizerID)
        return try referenceDatabase.read { baseline in
            current != (try Snapshot(in: baseline, organizerID: workspace.organizerID))
        }
    }

    private struct Snapshot: Equatable {
        var events: [Event]
        var programs: [Program]
        var schedules: [Schedule]
        var places: [EventPlace]
        var stages: [Stage]
        var contributors: [Contributor]
        var items: [ProgramItem]
        var categories: [Social.Category]
        var posts: [Social.Post]

        init(in db: Database, organizerID: OME.Organizer.ID) throws {
            events = try Event.all.fetchAll(db)
                .filter { $0.id.authority == .did(organizerID) }
                .sorted { $0.id.description < $1.id.description }
            programs = try Program.all.fetchAll(db)
                .filter { $0.id.authority == .did(organizerID) }
                .sorted { $0.id.description < $1.id.description }
            schedules = try Schedule.all.fetchAll(db)
                .filter { $0.id.authority == .did(organizerID) }
                .sorted { $0.id.description < $1.id.description }
            places = try EventPlace.all.fetchAll(db)
                .filter { $0.id.authority == .did(organizerID) }
                .sorted { $0.id.description < $1.id.description }
            stages = try Stage.all.fetchAll(db)
                .filter { $0.id.authority == .did(organizerID) }
                .sorted { $0.id.description < $1.id.description }
            contributors = try Contributor.all.fetchAll(db)
                .filter { $0.id.authority == .did(organizerID) }
                .sorted { $0.id.description < $1.id.description }
            items = try ProgramItem.all.fetchAll(db)
                .filter { $0.id.authority == .did(organizerID) }
                .sorted { $0.id.description < $1.id.description }
            categories = try Social.Category.all.fetchAll(db)
                .filter { $0.id.authority == .did(organizerID) }
                .sorted { $0.id.description < $1.id.description }
            posts = try Social.Post.all.fetchAll(db)
                .filter { $0.id.authority == .did(organizerID) }
                .sorted { $0.id.description < $1.id.description }
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

package func sourceScope(
    for projection: OpenMusicEventSourceProjection,
    workspace: SourceWorkspace
) -> SourceRecordScope {
    switch projection.fileFamily {
    case .calendar:
        .openMusicEventCalendar(organizerID: workspace.organizerID)
    case .collaborator:
        .openMusicEventWorkspace(workspace.id)
    case .event, .stage, .contributor, .schedule, .channel, .communicationPost, .poster:
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
