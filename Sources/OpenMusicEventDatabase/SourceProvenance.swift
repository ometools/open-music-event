import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData

extension OME.SourceDatabaseInsertion.EventIDOrigin: SQLiteType {
    public static var typeAffinity: SQLiteTypeAffinity { .text }
}

extension OME.SourceDatabaseInsertion.SourceKind: SQLiteType {
    public static var typeAffinity: SQLiteTypeAffinity { .text }
}

@Table("eventSourceProvenances")
public struct EventSourceProvenanceRecord: Equatable, Sendable, Identifiable {
    public var id: OME.Event.ID
    public var sourceKind: OME.SourceDatabaseInsertion.SourceKind
    public var sourceReference: String
    public var ref: String?
    public var eventIDOrigin: OME.SourceDatabaseInsertion.EventIDOrigin
    public var sourceEventDirectory: String

    public init(
        id: OME.Event.ID,
        sourceKind: OME.SourceDatabaseInsertion.SourceKind,
        sourceReference: String,
        ref: String?,
        eventIDOrigin: OME.SourceDatabaseInsertion.EventIDOrigin,
        sourceEventDirectory: String
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.sourceReference = sourceReference
        self.ref = ref
        self.eventIDOrigin = eventIDOrigin
        self.sourceEventDirectory = sourceEventDirectory
    }

    public init(_ provenance: OME.SourceDatabaseInsertion.EventSourceProvenance) {
        self.init(
            id: provenance.eventID,
            sourceKind: provenance.source.kind,
            sourceReference: provenance.source.reference,
            ref: provenance.source.ref,
            eventIDOrigin: provenance.eventIDOrigin,
            sourceEventDirectory: provenance.sourceEventDirectory
        )
    }
}
