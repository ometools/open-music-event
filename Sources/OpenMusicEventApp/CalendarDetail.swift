import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventImages
import SQLiteData
import SwiftUI

@Feature
public struct CalendarDetail {
    public init() {}

    public struct State: Identifiable {
        public init(calendarID: OMERecord.Calendar.ID) {
            self.calendarID = calendarID
            _calendar = FetchOne(CalendarDetail.calendarQuery(calendarID: calendarID))
            _entries = FetchAll(CalendarDetail.entriesQuery(calendarID: calendarID))
            _events = FetchAll(CalendarDetail.localEventsQuery)
        }

        var editCalendar: EditCalendar.State?

        @DebugSnapshotIgnored
        @FetchOne
        public var calendar: OMERecord.Calendar?

        @DebugSnapshotIgnored
        @FetchAll
        public var entries: [OMERecord.CalendarEntry]

        @DebugSnapshotIgnored
        @FetchAll
        public var events: [OMERecord.Event]

        public let calendarID: OMERecord.Calendar.ID

        public var id: OMERecord.Calendar.ID { calendarID }
    }

    public enum Action {
        case editButtonTapped
        case editCalendar(EditCalendar.Action)
        case eventButtonTapped(OMERecord.Event.ID)
        case task
    }

    static func calendarQuery(
        calendarID: OMERecord.Calendar.ID
    ) -> some SelectStatementOf<OMERecord.Calendar> {
        OMERecord.Calendar
            .where { $0.id.eq(calendarID) }
    }

    static func entriesQuery(
        calendarID: OMERecord.Calendar.ID
    ) -> some SelectStatementOf<OMERecord.CalendarEntry> {
        OMERecord.CalendarEntry
            .where { $0.id.calendarOwnerID.eq(calendarID.ownerID) }
            .where { $0.id.calendarID.eq(calendarID.calendarID) }
    }

    static let localEventsQuery = OMERecord.Event.all

    public struct EntryRows: Equatable, Sendable {
        public var rows: [EntryRow]

        public init(
            entries: [OMERecord.CalendarEntry],
            events: [OMERecord.Event]
        ) {
            let eventsByID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
            rows = entries
                .map { entry in
                    EntryRow(
                        entry: entry,
                        event: entry.event.localEventID.flatMap { eventsByID[$0] }
                    )
                }
                .sorted(by: Self.sort)
        }

        public var isEmpty: Bool {
            rows.isEmpty
        }

        private static func sort(
            lhs: EntryRow,
            rhs: EntryRow
        ) -> Bool {
            if lhs.entry.pinned != rhs.entry.pinned {
                return lhs.entry.pinned && !rhs.entry.pinned
            }

            switch (lhs.event?.calendarSortDate, rhs.event?.calendarSortDate) {
            case let (.some(lhsDate), .some(rhsDate)):
                if lhsDate != rhsDate { return lhsDate > rhsDate }

            case (.some, .none):
                return true

            case (.none, .some):
                return false

            case (.none, .none):
                break
            }

            if lhs.entry.createdAt != rhs.entry.createdAt {
                return lhs.entry.createdAt > rhs.entry.createdAt
            }

            return lhs.entry.id.entryID.rawValue.rawValue.localizedStandardCompare(
                rhs.entry.id.entryID.rawValue.rawValue
            ) == .orderedAscending
        }
    }

    public struct EntryRow: Equatable, Identifiable, Sendable {
        public var entry: OMERecord.CalendarEntry
        public var event: OMERecord.Event?

        public var id: OMERecord.CalendarEntry.ID {
            entry.id
        }

        public var eventID: OMERecord.Event.ID? {
            event?.id ?? entry.event.localEventID
        }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .editButtonTapped:
                state.editCalendar = EditCalendar.State(calendarID: state.calendarID)

            case .editCalendar:
                return

            case .eventButtonTapped(let eventID):
                store.addTask {
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(eventID, nil)
                    )
                }

            case .task:
                break
            }
        }
        .ifLet(\.editCalendar, action: \.editCalendar) {
            EditCalendar()
        }
    }
}

public struct CalendarDetailView: View {
    @Bindable var store: StoreOf<CalendarDetail>

    public init(store: StoreOf<CalendarDetail>) {
        self.store = store
    }

    public var body: some View {
        HeroImageList(title: Text(calendarTitle)) {
            HeroImage(
                title: Text(calendarTitle),
                sources: store.calendar?.heroImageSources ?? [],
                titleSources: store.calendar?.heroImageTitleSources ?? [.title]
            ) {
                Image(systemName: "calendar")
                    .font(.system(size: 82, weight: .semibold))
            }
        } content: {
            if let calendarDescription {
                Section("About") {
                    Text(calendarDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !entryRows.isEmpty {
                Section("Events") {
                    ForEach(entryRows.rows) { row in
                        CalendarEntryButton(row: row, store: store)
                    }
                }
            }

            if entryRows.isEmpty {
                EmptyBrowserState(
                    title: "No Events",
                    systemImage: "calendar.badge.exclamationmark",
                    message: "This calendar has no events."
                )
            }
        }
        .sheet(item: $store.scope(\.editCalendar, action: \.editCalendar)) { editStore in
            NavigationStack {
                EditCalendarView(store: editStore)
            }
        }
        .toolbar {
            Button("Edit Calendar", systemImage: "pencil") {
                store.send(.editButtonTapped)
            }
        }
    }

    private var calendarTitle: String {
        store.calendar?.name ?? store.calendarID.calendarID.rawValue.rawValue
    }

    private var calendarDescription: String? {
        guard let description = store.calendar?.description, !description.isEmpty else {
            return nil
        }
        return description
    }

    private var entryRows: CalendarDetail.EntryRows {
        CalendarDetail.EntryRows(entries: store.entries, events: store.events)
    }
}

struct CalendarEntryButton: View {
    let row: CalendarDetail.EntryRow
    let store: StoreOf<CalendarDetail>

    var body: some View {
        if let event = row.event {
            Button {
                store.send(.eventButtonTapped(event.id))
            } label: {
                CalendarEntryRowView(row: row)
            }
        } else {
            CalendarEntryRowView(row: row)
        }
    }
}

struct CalendarEntryRowView: View {
    let row: CalendarDetail.EntryRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let event = row.event {
                EventRowView(event: event)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Event unavailable")
                        Text(row.entry.event.uri.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
            }

            if let note = row.entry.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
    }
}

extension OMERecord.Event.Reference {
    var localEventID: OMERecord.Event.ID? {
        guard
            uri.collection == OMERecord.Event.nsid,
            let eventID = uri.rkey,
            case let .did(organizerID) = uri.authority
        else { return nil }

        return OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: OMERecord.ID<OMERecord.Event>(rawValue: eventID)
        )
    }
}

private extension OMERecord.Event {
    var calendarSortDate: LocalDate? {
        startDate ?? endDate
    }
}
