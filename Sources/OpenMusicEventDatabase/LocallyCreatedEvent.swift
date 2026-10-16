import ATProtoSQLite
import OpenMusicEventLexicon
import SQLiteData

/// Local authorship, not source-import provenance or proof of publication.
@Table("locallyCreatedEvents")
public struct LocallyCreatedEvent: Equatable, Sendable, Identifiable {
    @Column(primaryKey: true)
    public let id: Event.ID

    public init(id: Event.ID) { self.id = id }
}
