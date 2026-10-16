import ComposableArchitecture2
import ComposableNotifications
import Dependencies
import Foundation
import OpenMusicEventAppEventViewer
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

        var sourceImport: ImportEventSource.State?
        var eventForm: EventForm.State?
        var errorMessage: String?
        @DebugSnapshotIgnored let currentAccount = CurrentWorkspaceAccount()
        var canCreateEvent: Bool { currentAccount.selectedActorID() != nil }
    }

    public enum Action {
        case createButtonTapped
        case eventForm(EventForm.Action)
        case eventButtonTapped(Event.ID)
        case importButtonTapped
        case sourceImport(ImportEventSource.Action)
    }

    static let query = Event
        .where { event in
            InstalledEvent
                .where { installedEvent in
                    installedEvent.id.eq(event.id)
                }
                .exists()
        }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .createButtonTapped:
                guard state.eventForm == nil, let owner = state.currentAccount.selectedActorID() else { return }
                state.errorMessage = nil
                do {
                    let previous = try database.read { db in
                        try Event.all.fetchAll(db).filter { $0.id.authority == .did(owner) }
                            .compactMap(\.id.rkey).max { $0.rawValue < $1.rawValue }
                    }
                    let id = try CanonicalRecordID.next(
                        collection: Event.lexiconID, in: .did(owner), at: now, after: previous
                    )
                    let event = try Event(id: id, name: "", createdAt: .init(now.ISO8601Format()), timeZone: .current)
                    state.eventForm = EventForm.State(event: event, mode: .create)
                } catch {
                    state.errorMessage = "Unable to create an event: \(error.localizedDescription)"
                }
            case .eventForm:
                break
            case .importButtonTapped:
                state.sourceImport = ImportEventSource.State()
            case .sourceImport:
                break
            case let .eventButtonTapped(eventID):
                store.addTask {
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(eventID, nil)
                    )
                }
            }
        }
        .ifLet(\.sourceImport) { ImportEventSource() }
        .ifLet(\.eventForm) { EventForm() }
    }
}
