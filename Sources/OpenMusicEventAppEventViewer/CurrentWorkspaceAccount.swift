import ATProto
import ATProtoOAuth
import Dependencies
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing

/// Captures the app's OAuth storage dependency when a feature state is created.
/// The closure reads the current selection each time an authoring control is evaluated.
struct CurrentWorkspaceAccount: Sendable {
    let selectedActorID: @Sendable () -> DID?

    init() {
        @Dependency(\.getOptionalDefaultSession) var getOptionalDefaultSession
        selectedActorID = {
            getOptionalDefaultSession().flatMap {
                DID($0.accountID.rawValue.description)
            }
        }
    }

    func validated(
        _ session: EventWorkspaceSession?,
        for eventID: Event.ID
    ) -> EventWorkspaceSession? {
        guard let session,
              session.authorizes(eventID: eventID, selectedActorID: selectedActorID())
        else { return nil }
        return session
    }
}
