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

        let baseline: SourceBaselineRecord?
        if let sourceBaselineID = provenance.sourceBaselineID {
            baseline = try SourceBaselineRecord
                .where { $0.id.eq(sourceBaselineID) }
                .fetchOne(db)
        } else {
            baseline = nil
        }
        guard baseline != nil else {
            return EventEditSummary(
                eventID: eventID,
                availability: .missingBaseline,
                groups: []
            )
        }

        @Dependency(\.sourceEditingSession) var sourceEditingSession
        let sourceSummary: SourceChangeSummary
        if let sourceEditingSession {
            sourceSummary = try SourceEditingComparer().summary(
                in: db,
                baselineSchemaName: sourceEditingSession.baselineSchemaName,
                recordTypes: OME.sourceRecordTypes,
                scope: .openMusicEvent(eventID: eventID)
            )
        } else {
            @Dependency(\.sourceReferenceDatabase) var sourceReferenceDatabase
            guard let baselineDatabase = try sourceReferenceDatabase.existing(provenance.sourceProvenance) else {
                return EventEditSummary(
                    eventID: eventID,
                    availability: .missingBaseline,
                    groups: []
                )
            }
            sourceSummary = try SourceEditingComparer().summary(
                in: db,
                baselineDatabase: baselineDatabase,
                recordTypes: OME.sourceRecordTypes,
                scope: .openMusicEvent(eventID: eventID)
            )
        }

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

public struct SourceMetadataEditSummary: Equatable, Sendable {
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

public struct SourceMetadataEditSummaryRequest: FetchKeyRequest {
    public var calendarID: OME.Calendar.ID
    public var sourceBaselineID: SourceBaselineRecord.ID

    public init(
        sourceBaselineID: SourceBaselineRecord.ID,
        calendarID: OME.Calendar.ID
    ) {
        self.sourceBaselineID = sourceBaselineID
        self.calendarID = calendarID
    }

    public func fetch(_ db: Database) throws -> SourceMetadataEditSummary {
        let sourceBaseline = try SourceBaselineRecord
            .where { $0.id.eq(sourceBaselineID) }
            .fetchOne(db)

        guard let sourceBaseline else {
            return SourceMetadataEditSummary(
                sourceBaselineID: sourceBaselineID,
                availability: .missingBaseline,
                groups: []
            )
        }

        @Dependency(\.sourceReferenceDatabase) var sourceReferenceDatabase
        guard let baselineDatabase = try sourceReferenceDatabase.existing(
            sourceBaseline.sourceProvenance
        ) else {
            return SourceMetadataEditSummary(
                sourceBaselineID: sourceBaselineID,
                availability: .missingBaseline,
                groups: []
            )
        }

        let sourceSummary = try SourceEditingComparer().summary(
            in: db,
            baselineDatabase: baselineDatabase,
            recordTypes: OME.sourceMetadataRecordTypes,
            scope: .openMusicEventCalendar(calendarID: calendarID)
        )

        switch sourceSummary.availability {
        case .available:
            return SourceMetadataEditSummary(
                sourceBaselineID: sourceBaselineID,
                availability: .available,
                groups: sourceSummary.groups
            )

        case let .unavailable(reason):
            return SourceMetadataEditSummary(
                sourceBaselineID: sourceBaselineID,
                availability: .unavailable(reason),
                groups: []
            )
        }
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
}
