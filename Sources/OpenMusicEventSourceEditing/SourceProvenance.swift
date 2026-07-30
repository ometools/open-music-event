import ATProto
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData

@Table("sourceBaselines")
public struct SourceBaselineRecord: Equatable, Sendable, Identifiable {
    public struct ID: RawRepresentable, Codable, Hashable, Sendable, SQLiteType {
        public static var typeAffinity: SQLiteTypeAffinity { .text }

        public var rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public var id: ID
    public var sourceKind: OME.SourceDatabaseInsertion.SourceKind
    public var sourceReference: String
    public var ref: String?
    public var databaseFileName: String
    public var importedAt: Date

    public init(
        id: ID,
        sourceKind: OME.SourceDatabaseInsertion.SourceKind,
        sourceReference: String,
        ref: String?,
        databaseFileName: String,
        importedAt: Date
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.sourceReference = sourceReference
        self.ref = ref
        self.databaseFileName = databaseFileName
        self.importedAt = importedAt
    }

    public init(
        source: OME.SourceDatabaseInsertion.SourceProvenance,
        databaseFileName: String,
        importedAt: Date
    ) {
        self.init(
            id: .init(source: source),
            sourceKind: source.kind,
            sourceReference: source.reference,
            ref: source.ref,
            databaseFileName: databaseFileName,
            importedAt: importedAt
        )
    }
}

public extension SourceBaselineRecord.ID {
    init(source: OME.SourceDatabaseInsertion.SourceProvenance) {
        let components = [
            source.kind.rawValue,
            source.reference,
            source.ref.map { "some:\($0)" } ?? "none",
        ]
        self.init(
            rawValue: components
                .map { Data($0.utf8).base64EncodedString() }
                .joined(separator: ".")
        )
    }
}

@Table("editingWorkspaces")
public struct EditingWorkspaceRecord: Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Equatable, Hashable, Sendable, SQLiteType {
        public static var typeAffinity: SQLiteTypeAffinity { .text }

        case local
        case team
    }

    public struct ID: RawRepresentable, Codable, Hashable, Sendable, SQLiteType {
        public static var typeAffinity: SQLiteTypeAffinity { .text }

        public var rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public var id: ID
    public var kind: Kind
    public var databaseFileName: String
    public var createdAt: Date
    public var updatedAt: Date
    public var sourceBaselineID: SourceBaselineRecord.ID?
    @Column(as: OME.Relationship.RecordReference.JSONRepresentation?.self)
    public var publicRecord: OME.Relationship.RecordReference?

    public init(
        id: ID,
        kind: Kind,
        databaseFileName: String,
        createdAt: Date,
        updatedAt: Date,
        sourceBaselineID: SourceBaselineRecord.ID? = nil,
        publicRecord: OME.Relationship.RecordReference? = nil
    ) {
        self.id = id
        self.kind = kind
        self.databaseFileName = databaseFileName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceBaselineID = sourceBaselineID
        self.publicRecord = publicRecord
    }
}

public extension EditingWorkspaceRecord {
    init(localEventID eventID: OME.Event.ID, createdAt: Date) {
        let workspaceID = EditingWorkspaceRecord.ID(localEventID: eventID)
        self.init(
            id: workspaceID,
            kind: .local,
            databaseFileName: "\(workspaceID.rawValue).sqlite",
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    init(
        teamSourceBaseline sourceBaseline: SourceBaselineRecord,
        organizerID: OME.Organizer.ID? = nil
    ) {
        self.init(
            id: .init(sourceBaselineID: sourceBaseline.id),
            kind: .team,
            databaseFileName: sourceBaseline.databaseFileName,
            createdAt: sourceBaseline.importedAt,
            updatedAt: sourceBaseline.importedAt,
            sourceBaselineID: sourceBaseline.id,
            publicRecord: sourceBaseline.sourceKind == .tangled
                ? organizerID.map(OME.Relationship.RecordReference.init(sourceOrganizerID:))
                : nil
        )
    }
}

public enum WorkspaceIdentity: Equatable, Hashable, Sendable {
    case local(EditingWorkspaceRecord.ID)
    case published(
        localID: EditingWorkspaceRecord.ID,
        record: OME.Relationship.RecordReference
    )

    public var localID: EditingWorkspaceRecord.ID {
        switch self {
        case let .local(id), let .published(id, _):
            id
        }
    }

    public var publicRecord: OME.Relationship.RecordReference? {
        guard case let .published(_, record) = self else { return nil }
        return record
    }
}

public extension EditingWorkspaceRecord {
    var identity: WorkspaceIdentity {
        publicRecord.map { .published(localID: id, record: $0) } ?? .local(id)
    }
}

public extension OME.Relationship.RecordReference {
    init(sourceOrganizerID: OME.Organizer.ID) {
        self.init(
            author: sourceOrganizerID,
            collection: OME.SourceRecord.nsid,
            rkey: ATProto.Record.Key(rawValue: OME.SourceRecord.canonicalRecordKey)
        )
    }
}

@Table("workspaceRelationships")
public struct WorkspaceRelationshipRecord: Equatable, Sendable, Identifiable {
    @Selection public struct ID: Codable, Hashable, Sendable {
        public init(
            workspaceID: EditingWorkspaceRecord.ID,
            actorID: DID
        ) {
            self.workspaceID = workspaceID
            self.actorID = actorID
        }

        public var workspaceID: EditingWorkspaceRecord.ID
        public var actorID: DID
    }

    public init(
        id: ID,
        recordKey: String,
        relationship: OME.Relationship
    ) {
        self.id = id
        self.recordKey = recordKey
        self.relationship = relationship
    }

    public var id: ID
    public var recordKey: String
    @Column(as: OME.Relationship.JSONRepresentation.self)
    public var relationship: OME.Relationship

    public static func recordKey(for actorID: DID) -> String {
        Data(actorID.description.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public extension EditingWorkspaceRecord.ID {
    init(localEventID eventID: OME.Event.ID) {
        self.init(rawValue: "local.\(eventID.eventID.rawValue.rawValue)")
    }

    init(sourceBaselineID: SourceBaselineRecord.ID) {
        self.init(rawValue: "team.\(sourceBaselineID.rawValue)")
    }
}

@Table("eventEditingWorkspaces")
public struct EventEditingWorkspaceRecord: Equatable, Sendable, Identifiable {
    public var id: OME.Event.ID
    public var workspaceID: EditingWorkspaceRecord.ID

    public init(
        id: OME.Event.ID,
        workspaceID: EditingWorkspaceRecord.ID
    ) {
        self.id = id
        self.workspaceID = workspaceID
    }
}

extension OME.SourceDatabaseInsertion.EventIDOrigin: SQLiteType {
    public static var typeAffinity: SQLiteTypeAffinity { .text }
}

extension OME.SourceDatabaseInsertion.SourceKind: SQLiteType {
    public static var typeAffinity: SQLiteTypeAffinity { .text }
}

@Table("eventSourceProvenances")
public struct EventSourceProvenanceRecord: Equatable, Sendable, Identifiable {
    public var id: OME.Event.ID
    public var sourceBaselineID: SourceBaselineRecord.ID?
    public var sourceKind: OME.SourceDatabaseInsertion.SourceKind
    public var sourceReference: String
    public var ref: String?
    public var eventIDOrigin: OME.SourceDatabaseInsertion.EventIDOrigin
    public var sourceEventDirectory: String

    public init(
        id: OME.Event.ID,
        sourceBaselineID: SourceBaselineRecord.ID? = nil,
        sourceKind: OME.SourceDatabaseInsertion.SourceKind,
        sourceReference: String,
        ref: String?,
        eventIDOrigin: OME.SourceDatabaseInsertion.EventIDOrigin,
        sourceEventDirectory: String
    ) {
        self.id = id
        self.sourceBaselineID = sourceBaselineID
        self.sourceKind = sourceKind
        self.sourceReference = sourceReference
        self.ref = ref
        self.eventIDOrigin = eventIDOrigin
        self.sourceEventDirectory = sourceEventDirectory
    }

    public init(
        _ provenance: OME.SourceDatabaseInsertion.EventSourceProvenance,
        sourceBaselineID: SourceBaselineRecord.ID? = nil
    ) {
        self.init(
            id: provenance.eventID,
            sourceBaselineID: sourceBaselineID,
            sourceKind: provenance.source.kind,
            sourceReference: provenance.source.reference,
            ref: provenance.source.ref,
            eventIDOrigin: provenance.eventIDOrigin,
            sourceEventDirectory: provenance.sourceEventDirectory
        )
    }
}
