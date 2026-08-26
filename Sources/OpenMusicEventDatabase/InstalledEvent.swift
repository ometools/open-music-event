import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import SQLiteData

/// An attendee's explicit decision to keep an event in their local library.
///
/// Source-workspace preparation may temporarily materialize every event in an organizer's
/// repository. This record is deliberately independent of those source rows so authoring cannot
/// silently redefine which events the attendee installed.
@Table("installedEvents")
public struct InstalledEventRecord: Equatable, Sendable, Identifiable {
    public var id: OME.Event.ID
    public var sourceKind: OME.SourceDatabaseInsertion.SourceKind?
    public var sourceReference: String?
    public var ref: String?

    public init(
        id: OME.Event.ID,
        sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance? = nil
    ) {
        self.id = id
        self.sourceKind = sourceProvenance?.kind
        self.sourceReference = sourceProvenance?.reference
        self.ref = sourceProvenance?.ref
    }

    public var workspace: SourceWorkspace? {
        guard sourceKind == .tangled, let sourceReference else { return nil }
        return SourceWorkspace(
            organizerID: id.organizerID,
            repository: sourceReference,
            branch: "main"
        )
    }
}
