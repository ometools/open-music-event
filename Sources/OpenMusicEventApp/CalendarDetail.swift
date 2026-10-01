import HeroImageList
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventAppEventViewer
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventLexicon
import SQLiteData
import SwiftUITabFeatures
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

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

        @DebugSnapshotIgnored
        @FetchOne
        public var calendar: OMERecord.Calendar?

        @DebugSnapshotIgnored
        @FetchAll
        public var entries: [OMERecord.CalendarEntry]

        @DebugSnapshotIgnored
        @FetchAll
        public var events: [Event]

        public let calendarID: OMERecord.Calendar.ID

        public var id: OMERecord.Calendar.ID { calendarID }
    }

    public enum Action {
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

    static let localEventsQuery = Event.all

    public struct EntryRows: Equatable, Sendable {
        public var rows: [EntryRow]

        public init(
            entries: [OMERecord.CalendarEntry],
            events: [Event]
        ) {
            let eventsByID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
            rows = entries
                .map { entry in
                    EntryRow(
                        entry: entry,
                        event: eventsByID[entry.event.uri]
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
        public var event: Event?

        public var id: OMERecord.CalendarEntry.ID {
            entry.id
        }

        public var eventID: Event.ID? {
            event?.id
        }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .task:
                break
            }
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
                    calendarEntryRows(entryRows.rows)
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

    @ViewBuilder
    private func calendarEntryRows(_ rows: [CalendarDetail.EntryRow]) -> some View {
        ForEach(rows) { row in
            CalendarEntryRowView(row: row)
        }
    }
}

struct CalendarEntryRowView: View {
    let row: CalendarDetail.EntryRow
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let event = row.event {
                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .frame(width: 60, height: 60)
                    Text(event.name)
                    Spacer()
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Event unavailable")
                        if showsTechnicalDetails {
                            Text(row.entry.event.uri.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
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

extension Event {
    var calendarStartDay: LocalDate? {
        start?.date(in: timeZone).map { LocalDate($0, in: timeZone) }
    }

    var calendarEndDay: LocalDate? {
        end?.date(in: timeZone).map { LocalDate($0, in: timeZone) }
    }

    var calendarSortDate: LocalDate? {
        calendarStartDay ?? calendarEndDay
    }
}
