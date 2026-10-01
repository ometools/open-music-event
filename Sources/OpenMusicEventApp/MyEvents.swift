import ComposableArchitecture2
import ComposableNotifications
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventViewers
import SQLiteData

/// The installed-event library.
///
/// Browsing installs an event into the writable application database.
@Feature
public struct MyEvents {
    public struct State {
        public init() {
            _notificationIndicatorSummary = Fetch(
                wrappedValue: ApplicationNotificationIndicatorSummary(),
                ApplicationNotificationIndicatorSummaryRequest()
            )
        }

        @DebugSnapshotIgnored
        @FetchAll(MyEvents.query)
        var events

        var sortedEvents: [Event] {
            events.sorted { lhs, rhs in
                let lhsStart = lhs.start?.date(in: lhs.timeZone)
                let rhsStart = rhs.start?.date(in: rhs.timeZone)
                switch (lhsStart, rhsStart) {
                case let (.some(lhsStart), .some(rhsStart)) where lhsStart != rhsStart:
                    return lhsStart < rhsStart
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
        }

        @DebugSnapshotIgnored
        @Fetch var notificationIndicatorSummary: ApplicationNotificationIndicatorSummary

        var notificationIndicatorCount: Int {
            notificationIndicatorSummary.totalCount
        }

        var notificationIndicatorCountsByEventID: [Event.ID: Int] {
            Dictionary(
                uniqueKeysWithValues: events.map { event in
                    (event.id, notificationIndicatorSummary.count(for: event.id))
                }
            )
        }
    }

    public enum Action {
        case eventButtonTapped(Event.ID)
    }

    static let query = Event
        .where { event in
            InstalledEvent
                .where { installedEvent in
                    installedEvent.id.eq(event.id)
                }
                .exists()
        }

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
