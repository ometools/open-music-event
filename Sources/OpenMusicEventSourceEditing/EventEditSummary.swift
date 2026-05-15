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
                descriptors: OME.sourceTableDescriptors,
                scope: eventScope
            )
        } else {
            @Dependency(\.defaultBaselineDatabase) var baselineDatabase
            sourceSummary = try SourceEditingComparer().summary(
                in: db,
                baselineDatabase: baselineDatabase,
                descriptors: OME.sourceTableDescriptors,
                scope: eventScope
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

    private var eventScope: SourceRecordScope {
        SourceRecordScope(
            filters: [
                SourceRecordScope.Filter(
                    columnName: "organizerID",
                    value: eventID.organizerID.queryBinding
                ),
                SourceRecordScope.Filter(
                    columnName: "eventID",
                    value: eventID.eventID.rawValue.rawValue.queryBinding
                ),
            ]
        )
    }
}
