import OpenMusicEventLexicon
import SQLiteData

public struct EventEditSummary: Equatable, Sendable {
    public enum Availability: Equatable, Sendable {
        case available
        case missingBaseline
        case notSourceBacked
    }

    public var eventID: OME.Event.ID
    public var availability: Availability
    public var groups: [AnyRecordChangeGroup]

    public init(
        eventID: OME.Event.ID,
        availability: Availability,
        groups: [AnyRecordChangeGroup]
    ) {
        self.eventID = eventID
        self.availability = availability
        self.groups = groups
    }

    public var totalCount: Int {
        groups.reduce(0) { $0 + $1.totalCount }
    }
}

public struct RecordChangeGroup<Record: OME.SourceRecord>: Equatable, Sendable {
    public var added: Int
    public var modified: Int
    public var deleted: Int

    public init(
        added: Int = 0,
        modified: Int = 0,
        deleted: Int = 0
    ) {
        self.added = added
        self.modified = modified
        self.deleted = deleted
    }

    public var recordName: String {
        String(describing: Record.self)
    }

    public var totalCount: Int {
        added + modified + deleted
    }
}

public struct AnyRecordChangeGroup: Equatable, Sendable, Identifiable {
    public var id: String
    public var recordName: String
    public var added: Int
    public var modified: Int
    public var deleted: Int

    public init<Record: OME.SourceRecord>(_ group: RecordChangeGroup<Record>) {
        self.init(
            id: String(reflecting: Record.self),
            recordName: String(describing: Record.self),
            added: group.added,
            modified: group.modified,
            deleted: group.deleted
        )
    }

    public init(
        id: String,
        recordName: String,
        added: Int,
        modified: Int,
        deleted: Int
    ) {
        self.id = id
        self.recordName = recordName
        self.added = added
        self.modified = modified
        self.deleted = deleted
    }

    public var totalCount: Int {
        added + modified + deleted
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

        return EventEditSummary(
            eventID: eventID,
            availability: .available,
            groups: []
        )
    }
}
