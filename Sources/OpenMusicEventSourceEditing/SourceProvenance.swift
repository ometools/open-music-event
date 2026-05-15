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
