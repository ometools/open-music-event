import ComposableArchitecture2
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventViewers
import SQLiteData

/// The installed-event library.
///
/// Browsing installs an event into the writable application database. Opening it composes the
/// event viewer with its source workspace; this feature never creates, imports, or owns source.
@Feature
public struct MyEvents {
    public struct State {
        @DebugSnapshotIgnored
        @FetchAll(MyEvents.query)
        var events
    }

    public enum Action {
        case eventButtonTapped(OME.Event.ID)
    }

    static let query = OME.Event
        .where { event in
            InstalledEventRecord
                .where { installedEvent in
                    installedEvent.id.organizerID.eq(event.id.organizerID)
                        .and(installedEvent.id.eventID.eq(event.id.eventID))
                }
                .exists()
        }
        .order { ($0.startDate.asc(), $0.name) }

    public var body: some Feature {
        Update { _, action in
            switch action {
            case let .eventButtonTapped(eventID):
                store.addTask {
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(eventID, nil)
                    )
                }
            }
        }
    }
}
