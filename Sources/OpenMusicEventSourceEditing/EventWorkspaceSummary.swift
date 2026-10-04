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

public struct CanonicalWorkspaceRecordChange: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case added
        case edited
        case deleted
    }

    public let collection: String
    public let id: Event.ID
    public let kind: Kind
}

public enum CanonicalWorkspaceRecordChanges {
    public static func hasChanges(
        eventID: Event.ID,
        in database: Database,
        referenceDatabase: SourceBaselineDatabase
    ) throws -> Bool {
        try !changes(
            eventID: eventID,
            in: database,
            referenceDatabase: referenceDatabase
        ).isEmpty
    }

    public static func changes(
        eventID: Event.ID,
        in database: Database,
        referenceDatabase: SourceBaselineDatabase
    ) throws -> [CanonicalWorkspaceRecordChange] {
        let current = try Snapshot(in: database, eventID: eventID)
        return try referenceDatabase.read { baseline in
            current.changes(from: try Snapshot(in: baseline, eventID: eventID))
        }
    }

    public static func reset(
        eventID: Event.ID,
        in database: any DatabaseWriter,
        referenceDatabase: SourceBaselineDatabase
    ) throws {
        let baseline = try referenceDatabase.read {
            try Snapshot(in: $0, eventID: eventID)
        }
        try database.write { db in
            let current = try Snapshot(in: db, eventID: eventID)
            try Snapshot.restore(current.events, from: baseline.events,
                delete: { _ = try Event.find($0).delete().execute(db) },
                upsert: { record in try Event.upsert { record }.execute(db) })
            try Snapshot.restore(current.programs, from: baseline.programs,
                delete: { _ = try Program.find($0).delete().execute(db) },
                upsert: { record in try Program.upsert { record }.execute(db) })
            try Snapshot.restore(current.schedules, from: baseline.schedules,
                delete: { _ = try Schedule.find($0).delete().execute(db) },
                upsert: { record in try Schedule.upsert { record }.execute(db) })
            try Snapshot.restore(current.places, from: baseline.places,
                delete: { _ = try EventPlace.find($0).delete().execute(db) },
                upsert: { record in try EventPlace.upsert { record }.execute(db) })
            try Snapshot.restore(current.stages, from: baseline.stages,
                delete: { _ = try Stage.find($0).delete().execute(db) },
                upsert: { record in try Stage.upsert { record }.execute(db) })
            try Snapshot.restore(current.contributors, from: baseline.contributors,
                delete: { _ = try Contributor.find($0).delete().execute(db) },
                upsert: { record in try Contributor.upsert { record }.execute(db) })
            try Snapshot.restore(current.items, from: baseline.items,
                delete: { _ = try ProgramItem.find($0).delete().execute(db) },
                upsert: { record in try ProgramItem.upsert { record }.execute(db) })
            try Snapshot.restore(current.categories, from: baseline.categories,
                delete: { _ = try Social.Category.find($0).delete().execute(db) },
                upsert: { record in try Social.Category.upsert { record }.execute(db) })
            try Snapshot.restore(current.posts, from: baseline.posts,
                delete: { _ = try Social.Post.find($0).delete().execute(db) },
                upsert: { record in try Social.Post.upsert { record }.execute(db) })
            try Snapshot.restore(current.relationships, from: baseline.relationships,
                delete: { id in
                    try OME.Relationship.where { $0.id.eq(id) }.delete().execute(db)
                },
                upsert: { record in try OME.Relationship.upsert { record }.execute(db) })
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
        var relationships: [Event.ID: OME.Relationship]

        init(in db: Database, eventID: Event.ID) throws {
            let organizer = eventID.authority
            events = try Event.all.fetchAll(db)
                .filter { $0.id.authority == organizer }
                .sorted { $0.id.description < $1.id.description }
            programs = try Program.all.fetchAll(db)
                .filter { $0.id.authority == organizer }
                .sorted { $0.id.description < $1.id.description }
            schedules = try Schedule.all.fetchAll(db)
                .filter { $0.id.authority == organizer }
                .sorted { $0.id.description < $1.id.description }
            places = try EventPlace.all.fetchAll(db)
                .filter { $0.id.authority == organizer }
                .sorted { $0.id.description < $1.id.description }
            stages = try Stage.all.fetchAll(db)
                .filter { $0.id.authority == organizer }
                .sorted { $0.id.description < $1.id.description }
            contributors = try Contributor.all.fetchAll(db)
                .filter { $0.id.authority == organizer }
                .sorted { $0.id.description < $1.id.description }
            items = try ProgramItem.all.fetchAll(db)
                .filter { $0.id.authority == organizer }
                .sorted { $0.id.description < $1.id.description }
            categories = try Social.Category.all.fetchAll(db)
                .filter { $0.id.authority == organizer }
                .sorted { $0.id.description < $1.id.description }
            posts = try Social.Post.all.fetchAll(db)
                .filter { $0.id.authority == organizer }
                .sorted { $0.id.description < $1.id.description }
            relationships = Dictionary(uniqueKeysWithValues: try OME.Relationship.all.fetchAll(db)
                .compactMap { relationship in
                    guard let id = relationship.id,
                          id.authority == organizer,
                          case let .some(.known(.record(object))) = relationship.object,
                          object.uri == eventID
                    else { return nil }
                    return (id, relationship)
                })
        }

        func changes(from baseline: Self) -> [CanonicalWorkspaceRecordChange] {
            Self.changes(Event.tableName, current: events, baseline: baseline.events)
                + Self.changes(Program.tableName, current: programs, baseline: baseline.programs)
                + Self.changes(Schedule.tableName, current: schedules, baseline: baseline.schedules)
                + Self.changes(EventPlace.tableName, current: places, baseline: baseline.places)
                + Self.changes(Stage.tableName, current: stages, baseline: baseline.stages)
                + Self.changes(Contributor.tableName, current: contributors, baseline: baseline.contributors)
                + Self.changes(ProgramItem.tableName, current: items, baseline: baseline.items)
                + Self.changes(Social.Category.tableName, current: categories, baseline: baseline.categories)
                + Self.changes(Social.Post.tableName, current: posts, baseline: baseline.posts)
                + Self.changes(OME.Relationship.tableName, current: relationships, baseline: baseline.relationships)
        }

        private static func changes<Record: Identifiable & Equatable>(
            _ collection: String,
            current: [Record],
            baseline: [Record]
        ) -> [CanonicalWorkspaceRecordChange] where Record.ID == Event.ID {
            let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
            let baselineByID = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
            return changes(collection, current: currentByID, baseline: baselineByID)
        }

        private static func changes<Record: Equatable>(
            _ collection: String,
            current currentByID: [Event.ID: Record],
            baseline baselineByID: [Event.ID: Record]
        ) -> [CanonicalWorkspaceRecordChange] {
            return Set(currentByID.keys).union(baselineByID.keys)
                .sorted { $0.description < $1.description }
                .compactMap { id in
                    let kind: CanonicalWorkspaceRecordChange.Kind
                    switch (currentByID[id], baselineByID[id]) {
                    case (.some, nil): kind = .added
                    case (nil, .some): kind = .deleted
                    case let (.some(current), .some(reference)) where current != reference:
                        kind = .edited
                    default: return nil
                    }
                    return CanonicalWorkspaceRecordChange(
                        collection: collection,
                        id: id,
                        kind: kind
                    )
                }
        }

        fileprivate static func restore<Record: Identifiable & Equatable>(
            _ current: [Record],
            from baseline: [Record],
            delete: (Event.ID) throws -> Void,
            upsert: (Record) throws -> Void
        ) throws where Record.ID == Event.ID {
            let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
            let baselineByID = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
            try restore(currentByID, from: baselineByID, delete: delete, upsert: upsert)
        }

        fileprivate static func restore<Record: Equatable>(
            _ currentByID: [Event.ID: Record],
            from baselineByID: [Event.ID: Record],
            delete: (Event.ID) throws -> Void,
            upsert: (Record) throws -> Void
        ) throws {
            for id in currentByID.keys where baselineByID[id] == nil {
                try delete(id)
            }
            for (id, record) in baselineByID where currentByID[id] != record {
                try upsert(record)
            }
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
