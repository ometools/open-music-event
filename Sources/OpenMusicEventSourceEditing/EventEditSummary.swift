import Dependencies
import OpenMusicEventLexicon
import SQLiteData
import SourceEditing

public struct EventEditSummary: Equatable, Sendable {
    public enum Availability: Equatable, Sendable {
        case available
        case missingBaseline
        case notSourceBacked
        case unavailable(SourceChangeSummary.UnavailableReason)
    }

    public var eventID: OME.Event.ID
    public var availability: Availability
    public var groups: [SourceChangeGroup]

    public init(
        eventID: OME.Event.ID,
        availability: Availability,
        groups: [SourceChangeGroup]
    ) {
        self.eventID = eventID
        self.availability = availability
        self.groups = groups
    }

    public var totalCount: Int {
        groups.reduce(0) { $0 + $1.totalCount }
    }

    public var badgeCount: Int? {
        guard case .available = availability, totalCount > 0 else { return nil }
        return totalCount
    }
}

public struct EventEditSummaryRequest: FetchKeyRequest {
    public var eventID: OME.Event.ID

    public init(eventID: OME.Event.ID) {
        self.eventID = eventID
    }

    public func fetch(_ db: Database) throws -> EventEditSummary {
        let provenance = try EventSourceProvenanceRecord
            .where { $0.id.eq(eventID) }
            .fetchOne(db)
        guard let provenance else {
            return EventEditSummary(
                eventID: eventID,
                availability: .notSourceBacked,
                groups: []
            )
        }

        guard let sourceBaselineID = provenance.sourceBaselineID,
              try (SourceBaselineRecord
                .where { $0.id.eq(sourceBaselineID) }
                .fetchOne(db)) != nil
        else {
            return EventEditSummary(
                eventID: eventID,
                availability: .missingBaseline,
                groups: []
            )
        }

        @Dependency(\.sourceReferenceDatabase) var sourceReferenceDatabase
        guard let baselineDatabase = try sourceReferenceDatabase.existing(
            provenance.sourceProvenance
        ) else {
            return EventEditSummary(
                eventID: eventID,
                availability: .missingBaseline,
                groups: []
            )
        }
        let sourceSummary = try SourceEditingComparer().summary(
            in: db,
            baselineDatabase: baselineDatabase,
            recordTypes: OME.sourceRecordTypes,
            scope: .openMusicEvent(eventID: eventID)
        )

        switch sourceSummary.availability {
        case .available:
            return EventEditSummary(
                eventID: eventID,
                availability: .available,
                groups: sourceSummary.groups
            )

        case let .unavailable(reason):
            return EventEditSummary(
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
    public var sourceBaselineID: SourceBaselineRecord.ID

    public init(
        sourceBaselineID: SourceBaselineRecord.ID,
        availability: Availability,
        groups: [SourceChangeGroup]
    ) {
        self.sourceBaselineID = sourceBaselineID
        self.availability = availability
        self.groups = groups
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
        let sourceBaseline = try SourceBaselineRecord
            .where { $0.id.eq(sourceBaselineID) }
            .fetchOne(db)

        guard let sourceBaseline else {
            return SourceEditSummary(
                sourceBaselineID: sourceBaselineID,
                availability: .missingBaseline,
                groups: []
            )
        }

        @Dependency(\.sourceReferenceDatabase) var sourceReferenceDatabase
        guard let baselineDatabase = try sourceReferenceDatabase.existing(
            sourceBaseline.sourceProvenance
        ) else {
            return SourceEditSummary(
                sourceBaselineID: sourceBaselineID,
                availability: .missingBaseline,
                groups: []
            )
        }

        let sourceSummary = try sourceEditSummary(
            in: db,
            baselineDatabase: baselineDatabase,
            sourceBaselineID: sourceBaselineID,
            calendarID: calendarID
        )

        switch sourceSummary.availability {
        case .available:
            return SourceEditSummary(
                sourceBaselineID: sourceBaselineID,
                availability: .available,
                groups: sourceSummary.groups
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
    baselineDatabase: SourceBaselineDatabase,
    sourceBaselineID: SourceBaselineRecord.ID,
    calendarID: OME.Calendar.ID
) throws -> SourceChangeSummary {
    let comparer = SourceEditingComparer()
    let calendarSummary = try comparer.summary(
        in: db,
        baselineDatabase: baselineDatabase,
        recordTypes: OME.sourceMetadataRecordTypes,
        scope: .openMusicEventCalendar(calendarID: calendarID)
    )
    guard case .available = calendarSummary.availability else {
        return calendarSummary
    }

    var summaries = [calendarSummary]
    for eventID in try sourceEventIDs(
        in: db,
        baselineDatabase: baselineDatabase,
        sourceBaselineID: sourceBaselineID,
        organizerID: calendarID.ownerID
    ) {
        let eventSummary = try comparer.summary(
            in: db,
            baselineDatabase: baselineDatabase,
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
        groups: mergedSourceChangeGroups(summaries.flatMap(\.groups))
    )
}

private func sourceEventIDs(
    in db: Database,
    baselineDatabase: SourceBaselineDatabase,
    sourceBaselineID: SourceBaselineRecord.ID,
    organizerID: OME.Organizer.ID
) throws -> [OME.Event.ID] {
    let workingEventIDs = try sourceEventIDs(
        in: db,
        sourceBaselineID: sourceBaselineID
    )
    let baselineEventIDs = try baselineDatabase.read { db in
        try sourceEventIDs(
            in: db,
            sourceBaselineID: sourceBaselineID
        )
    }

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
