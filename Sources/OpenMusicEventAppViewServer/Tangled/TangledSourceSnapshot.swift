import ATProto
import OpenMusicEventLexicon
import OpenMusicEventSource

/// The notification identities and posts produced by one validated source revision.
/// The published source archive remains the authority for installation-only data.
struct TangledSourceSnapshot: Equatable, Sendable {
    let revision: String
    let eventIDs: [ATProto.URI]
    let posts: [OME.SourceDatabaseInsertion.CommunicationPost]

    init(
        revision: String,
        eventIDs: [ATProto.URI],
        posts: [OME.SourceDatabaseInsertion.CommunicationPost]
    ) {
        self.revision = revision
        self.eventIDs = eventIDs
        self.posts = posts
    }

    init(
        validated insertion: OME.SourceDatabaseInsertion,
        revision: String
    ) throws {
        self.revision = revision
        self.eventIDs = try insertion.events.map { draft in
            guard let eventID = draft.id else {
                throw TangledSourceSnapshotError.missingValidatedEventID(draft.name)
            }
            let uri = OME.Event.reference(id: eventID).uri
            guard let provenance = insertion.eventSourceProvenances.first(where: {
                $0.eventID == eventID
            }) else {
                throw TangledSourceSnapshotError.missingEventSourceProvenance(uri.description)
            }
            guard provenance.source.kind == .tangled else {
                throw TangledSourceSnapshotError.unsupportedEventSource(
                    provenance.source.reference
                )
            }
            guard provenance.source.ref == revision else {
                throw TangledSourceSnapshotError.eventSourceRevisionMismatch(
                    event: uri.description,
                    expected: revision,
                    actual: provenance.source.ref
                )
            }
            return uri
        }
        self.posts = insertion.communicationPosts
    }

    static func empty(revision: String) -> Self {
        Self(revision: revision, eventIDs: [], posts: [])
    }
}

enum TangledSourceSnapshotError: Error, Equatable {
    case eventSourceRevisionMismatch(event: String, expected: String, actual: String?)
    case missingValidatedEventID(String)
    case missingEventSourceProvenance(String)
    case unsupportedEventSource(String)
}
