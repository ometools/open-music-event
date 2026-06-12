import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventSourceEditing
import SQLiteData
import SwiftUI
import Tagged

@Feature
public struct OpenMusicEventBrowser {
    public init() {}

    public enum Tab: Hashable {
        case browse
        case following
        case myEvents
        case search
        case settings
    }

    public struct State {
        public init() {}

        public var selectedTab: Tab = .myEvents
        public var browse = Spawn(Browse.State())
        public var following = Spawn(Following.State())
        public var search = Spawn(Search.State())
        public var settings = Spawn(Settings.State())
        public var myEvents = Spawn(MyEvents.State())
    }

    public enum Action {
        case task
    }

    public var body: some Feature {
        let _ = Self._logChanges()

        Update { _, action in
            switch action {
            case .task:
                break
            }
        }
        .spawn(\.browse) {
            Browse()
        }
        .spawn(\.following) {
            Following()
        }
        .spawn(\.search) {
            Search()
        }
        .spawn(\.settings) {
            Settings()
        }
        .spawn(\.myEvents) { MyEvents() }
    }
}

public struct OpenMusicEventBrowserView: View {
    public init(store: StoreOf<OpenMusicEventBrowser>) {
        self.store = store
    }

    @Bindable var store: StoreOf<OpenMusicEventBrowser>

    public var body: some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            iosTabView
        } else {
            legacyiOSTabView
        }
        #else
        defaultTabView
        #endif
    }

    #if os(iOS)
    @available(iOS 18.0, *)
    private var iosTabView: some View {
        TabView(selection: $store.selectedTab) {
            Tab("Browse", systemImage: "sparkles", value: OpenMusicEventBrowser.Tab.browse) {
                NavigationStack {
                    BrowseView(store: store.spawn(\.browse))
                }
            }

            Tab("Following", systemImage: "person.2.fill", value: OpenMusicEventBrowser.Tab.following) {
                NavigationStack {
                    FollowingView(store: store.spawn(\.following))
                }
            }

            Tab("My Events", systemImage: "star", value: OpenMusicEventBrowser.Tab.myEvents) {
                NavigationStack {
                    MyEventsView(store: store.spawn(\.myEvents))
                }
            }

            Tab("Settings", systemImage: "gearshape", value: OpenMusicEventBrowser.Tab.settings) {
                NavigationStack {
                    SettingsFeatureView(store: store.spawn(\.settings))
                }
            }

            Tab(value: OpenMusicEventBrowser.Tab.search, role: .search) {
                SearchView(store: store.spawn(\.search))
            }
        }
    }

    private var legacyiOSTabView: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack {
                BrowseView(store: store.spawn(\.browse))
            }
            .tabItem {
                Label("Browse", systemImage: "sparkles")
            }
            .tag(OpenMusicEventBrowser.Tab.browse)

            NavigationStack {
                FollowingView(store: store.spawn(\.following))
            }
            .tabItem {
                Label("Following", systemImage: "person.2.fill")
            }
            .tag(OpenMusicEventBrowser.Tab.following)
//
            NavigationStack {
                MyEventsView(store: store.spawn(\.myEvents))
            }
            .tabItem {
                Label("My Events", systemImage: "star")
            }
            .tag(OpenMusicEventBrowser.Tab.myEvents)

            NavigationStack {
                SettingsFeatureView(store: store.spawn(\.settings))
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(OpenMusicEventBrowser.Tab.settings)

            SearchView(store: store.spawn(\.search))
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(OpenMusicEventBrowser.Tab.search)
        }
    }
    #endif

    private var defaultTabView: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack {
                BrowseView(store: store.spawn(\.browse))
            }
            .tabItem {
                Label("Browse", systemImage: "sparkles")
            }
            .tag(OpenMusicEventBrowser.Tab.browse)

            NavigationStack {
                FollowingView(store: store.spawn(\.following))
            }
            .tabItem {
                Label("Following", systemImage: "person.2.fill")
            }
            .tag(OpenMusicEventBrowser.Tab.following)

            NavigationStack {
                MyEventsView(store: store.spawn(\.myEvents))
            }
            .tabItem {
                Label("My Events", systemImage: "star")
            }
            .tag(OpenMusicEventBrowser.Tab.myEvents)

            NavigationStack {
                SettingsFeatureView(store: store.spawn(\.settings))
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(OpenMusicEventBrowser.Tab.settings)

            NavigationStack {
                SearchView(store: store.spawn(\.search))
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(OpenMusicEventBrowser.Tab.search)
        }
    }
}

@Feature
public struct Browse {
    public init() {}

    public struct State {
        public init() {}

        public var events: [BrowseEventRow] = []
        public var isLoading = false
    }

    public enum Action {
        case browseResponse([BrowseEventRow])
        case didPullToRefresh
        case eventButtonTapped(OMERecord.Event.ID)
        case task
    }

    public var body: some Feature {
        Update { _, action in
            switch action {
            case .eventButtonTapped(let eventID):
                store.addTask {
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(eventID, nil)
                    )
                }

            case .browseResponse, .didPullToRefresh, .task:
                break
            }
        }
    }
}

public struct BrowseView: View {
    let store: StoreOf<Browse>

    public init(store: StoreOf<Browse>) {
        self.store = store
    }

    public var body: some View {
        List {
            EmptyBrowserState(
                title: "Browse",
                systemImage: "sparkles",
                message: "Browse feature stub."
            )
        }
        .navigationTitle("Browse")
    }
}

@Feature
public struct Following {
    public init() {}

    public struct State {
        public init() {}

        public var followedOrganizers: [FollowedOrganizerRow] = []
        public var isLoading = false
        public var organizerDetail: OrganizerDetail.State?

    }

//    static let followersQuery = OrganizerPreferences
//        .select { $0.isFollowing }
//        .leftJoin(OMERecord.Organizer.all, on: {
//            $0.0.organizerID.is($0.1.id)
//        })


    public enum Action {
        case didPullToRefresh
        case eventButtonTapped(OMERecord.Event.ID)
        case followedOrganizersResponse([FollowedOrganizerRow])
        case organizerDetail(OrganizerDetail.Action)
        case organizerRowTapped(OMERecord.Organizer.ID)
        case task
        case toggleFollowButtonTapped(OMERecord.Organizer.ID)
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .organizerRowTapped(let organizerID):
                store.withDependencies {
                    state.organizerDetail = .init(organizerID: organizerID)
                }

            case .eventButtonTapped(let eventID):
                store.addTask {
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(eventID, nil)
                    )
                }

            case .didPullToRefresh,
                 .followedOrganizersResponse,
                 .organizerDetail,
                 .task,
                 .toggleFollowButtonTapped:
                break
            }
        }
        .ifLet(\.organizerDetail, action: \.organizerDetail) {
            OrganizerDetail()
        }
    }
}

public struct FollowingView: View {
    @Bindable var store: StoreOf<Following>

    public init(store: StoreOf<Following>) {
        self.store = store
    }

    public var body: some View {
        List {
            EmptyBrowserState(
                title: "Following",
                systemImage: "person.2.fill",
                message: "Following feature stub."
            )
        }
        .navigationTitle("Following")
        .navigationDestination(item: $store.scope(\.organizerDetail, action: \.organizerDetail)) { detailStore in
            OrganizerDetailView(store: detailStore)
        }
    }
}

@Feature
public struct OrganizerDetail {
    public init() {}

    public struct State: Identifiable {
        public init(organizerID: OMERecord.Organizer.ID) {
            self.organizerID = organizerID
            _calendars = FetchAll(OrganizerDetail.calendarsQuery(organizerID: organizerID))
            _calendarEvents = FetchAll(CalendarDetail.localEventsQuery)
            _defaultCalendarEntries = FetchAll(
                OrganizerDetail.defaultCalendarEntriesQuery(organizerID: organizerID)
            )
            _organizer = FetchOne(OrganizerDetail.organizerQuery(organizerID: organizerID))
        }

        var calendarDetail: CalendarDetail.State?
        var destination: Destination.State?

        @DebugSnapshotIgnored
        @FetchAll
        public var calendars: [OMERecord.Calendar]

        @DebugSnapshotIgnored
        @FetchAll
        public var calendarEvents: [OMERecord.Event]

        @DebugSnapshotIgnored
        @FetchAll
        public var defaultCalendarEntries: [OMERecord.CalendarEntry]

        @DebugSnapshotIgnored
        @FetchOne
        public var organizer: OMERecord.Organizer?

        public let organizerID: OMERecord.Organizer.ID

        public var id: OMERecord.Organizer.ID { organizerID }
    }

    public enum Action {
        case addEventButtonTapped
        case calendarButtonTapped(OMERecord.Calendar.ID)
        case calendarDetail(CalendarDetail.Action)
        case destination(Destination.Action)
        case eventButtonTapped(OMERecord.Event.ID)
        case task
    }

    @Feature
    public enum Destination {
        case createEvent(Spawn<CreateEvent>)
    }

    static func organizerQuery(
        organizerID: OMERecord.Organizer.ID
    ) -> some SelectStatementOf<OMERecord.Organizer> {
        OMERecord.Organizer.where { $0.id.eq(organizerID) }
    }

    static func calendarsQuery(
        organizerID: OMERecord.Organizer.ID
    ) -> some SelectStatementOf<OMERecord.Calendar> {
        OMERecord.Calendar
            .where { $0.id.ownerID.eq(organizerID) }
            .order { $0.name.collate(.nocase) }
    }

    static func defaultCalendarID(
        organizerID: OMERecord.Organizer.ID
    ) -> OMERecord.Calendar.ID {
        OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
    }

    static func defaultCalendarEntriesQuery(
        organizerID: OMERecord.Organizer.ID
    ) -> some SelectStatementOf<OMERecord.CalendarEntry> {
        CalendarDetail.entriesQuery(
            calendarID: defaultCalendarID(organizerID: organizerID)
        )
    }

    static func eventsQuery(
        organizerID: OMERecord.Organizer.ID
    ) -> some SelectStatementOf<OMERecord.Event> {
        OMERecord.Event.where { event in
            OMERecord.EventOrganizer
                .where { $0.id.organizerID.eq(event.id.organizerID) }
                .where { $0.id.eventID.eq(event.id.eventID) }
                .where { $0.id.eventOrganizerID.eq(organizerID) }
                .exists()
        }
    }

    public struct EventSections: Equatable, Sendable {
        public var currentEvents: [OMERecord.Event]
        public var previousEvents: [OMERecord.Event]
        public var upcomingEvents: [OMERecord.Event]

        public init(events: [OMERecord.Event], now: Date) {
            let sortedEvents = events.sorted(by: Self.sort)
            self.currentEvents = sortedEvents.filter { Self.timing(for: $0, now: now) == .current }
            self.previousEvents = sortedEvents.filter { Self.timing(for: $0, now: now) == .previous }
            self.upcomingEvents = sortedEvents.filter { Self.timing(for: $0, now: now) == .upcoming }
        }

        public var isEmpty: Bool {
            currentEvents.isEmpty && previousEvents.isEmpty && upcomingEvents.isEmpty
        }

        private enum Timing {
            case current
            case previous
            case upcoming
        }

        private static func sort(lhs: OMERecord.Event, rhs: OMERecord.Event) -> Bool {
            switch (lhs.sortDate, rhs.sortDate) {
            case let (.some(lhsDate), .some(rhsDate)):
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending

            case (.some, .none):
                return true

            case (.none, .some):
                return false

            case (.none, .none):
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }

        private static func timing(for event: OMERecord.Event, now: Date) -> Timing {
            let today = LocalDate(now, in: event.timeZone)

            switch (event.startDate, event.endDate) {
            case let (.some(startDate), .some(endDate)):
                if startDate <= today && today <= endDate { return .current }
                if endDate < today { return .previous }
                return .upcoming

            case let (.some(startDate), .none):
                if startDate > today { return .upcoming }
                if startDate == today { return .current }
                return .previous

            case let (.none, .some(endDate)):
                return endDate >= today ? .current : .previous

            case (.none, .none):
                return .previous
            }
        }
    }

    public struct CalendarEntrySections: Equatable, Sendable {
        public var currentRows: [CalendarDetail.EntryRow]
        public var previousRows: [CalendarDetail.EntryRow]
        public var unavailableRows: [CalendarDetail.EntryRow]
        public var upcomingRows: [CalendarDetail.EntryRow]

        public init(entryRows: CalendarDetail.EntryRows, now: Date) {
            let rows = entryRows.rows
            self.currentRows = rows.filter { Self.timing(for: $0, now: now) == .current }
            self.previousRows = rows.filter { Self.timing(for: $0, now: now) == .previous }
            self.unavailableRows = rows.filter { Self.timing(for: $0, now: now) == .unavailable }
            self.upcomingRows = rows.filter { Self.timing(for: $0, now: now) == .upcoming }
        }

        public var isEmpty: Bool {
            currentRows.isEmpty
            && previousRows.isEmpty
            && unavailableRows.isEmpty
            && upcomingRows.isEmpty
        }

        private enum Timing {
            case current
            case previous
            case unavailable
            case upcoming
        }

        private static func timing(for row: CalendarDetail.EntryRow, now: Date) -> Timing {
            guard let event = row.event else { return .unavailable }
            let today = LocalDate(now, in: event.timeZone)

            switch (event.startDate, event.endDate) {
            case let (.some(startDate), .some(endDate)):
                if startDate <= today && today <= endDate { return .current }
                if endDate < today { return .previous }
                return .upcoming

            case let (.some(startDate), .none):
                if startDate > today { return .upcoming }
                if startDate == today { return .current }
                return .previous

            case let (.none, .some(endDate)):
                return endDate >= today ? .current : .previous

            case (.none, .none):
                return .previous
            }
        }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addEventButtonTapped:
                state.destination = .createEvent(
                    Spawn(
                        CreateEvent.State(
                            organizerID: state.organizerID,
                            eventOrganizerID: state.organizerID
                        )
                    )
                )

            case .calendarButtonTapped(let calendarID):
                store.withDependencies {
                    state.calendarDetail = .init(calendarID: calendarID)
                }

            case .calendarDetail:
                return

            case .destination:
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
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .ifLet(\.calendarDetail, action: \.calendarDetail) {
            CalendarDetail()
        }
    }
}

public struct OrganizerDetailView: View {
    @Bindable var store: StoreOf<OrganizerDetail>
    @Dependency(\.date.now) var now

    public init(store: StoreOf<OrganizerDetail>) {
        self.store = store
    }

    public var body: some View {
        HeroImageList(title: Text(organizerTitle)) {
            HeroImage(
                title: Text(organizerTitle),
                asset: nil,
                cacheContext: nil
            ) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 82, weight: .semibold))
            }
        } content: {
            if !store.calendars.isEmpty {
                Section("Calendars") {
                    calendarRows(store.calendars)
                }
            }

            if !sections.currentRows.isEmpty {
                Section("Happening Now") {
                    calendarEntryRows(sections.currentRows)
                }
            }

            if !sections.upcomingRows.isEmpty {
                Section("Upcoming Events") {
                    calendarEntryRows(sections.upcomingRows)
                }
            }

            if !sections.previousRows.isEmpty {
                Section("Previous Events") {
                    calendarEntryRows(sections.previousRows)
                }
            }

            if !sections.unavailableRows.isEmpty {
                Section("Unavailable Events") {
                    calendarEntryRows(sections.unavailableRows)
                }
            }

            if sections.isEmpty {
                EmptyBrowserState(
                    title: "No Events",
                    systemImage: "calendar.badge.exclamationmark",
                    message: "This organizer has no events."
                )
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).createEvent) { createEventStore in
            NavigationStack {
                CreateEventView(store: createEventStore)
            }
        }
        .navigationDestination(item: $store.scope(\.calendarDetail, action: \.calendarDetail)) { detailStore in
            CalendarDetailView(store: detailStore)
        }
        .toolbar {
            Button("Add Event", systemImage: "plus") {
                store.send(.addEventButtonTapped)
            }
        }
    }

    private var defaultCalendarEntryRows: CalendarDetail.EntryRows {
        CalendarDetail.EntryRows(
            entries: store.defaultCalendarEntries,
            events: store.calendarEvents
        )
    }

    private var sections: OrganizerDetail.CalendarEntrySections {
        OrganizerDetail.CalendarEntrySections(
            entryRows: defaultCalendarEntryRows,
            now: now
        )
    }

    private var organizerTitle: String {
        (store.organizer?.id ?? store.organizerID).description
    }

    @ViewBuilder
    private func calendarRows(_ calendars: [OMERecord.Calendar]) -> some View {
        ForEach(calendars) { calendar in
            Button {
                store.send(.calendarButtonTapped(calendar.id))
            } label: {
                CalendarRowView(calendar: calendar)
            }
        }
    }

    @ViewBuilder
    private func calendarEntryRows(_ rows: [CalendarDetail.EntryRow]) -> some View {
        ForEach(rows) { row in
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
}

struct CalendarRowView: View {
    let calendar: OMERecord.Calendar

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(calendar.name)
                    .lineLimit(1)

                if let description = calendar.description, !description.isEmpty {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .foregroundStyle(.primary)
    }
}

@Feature
public struct SourceDetail {
    public init() {}

    public struct State: Identifiable {
        public init(sourceBaselineID: SourceBaselineRecord.ID) {
            self.sourceBaselineID = sourceBaselineID
            _calendar = FetchOne(
                SourceDetail.calendarQuery(sourceBaselineID: sourceBaselineID)
            )
            _calendarEntries = FetchAll(
                SourceDetail.calendarEntriesQuery(sourceBaselineID: sourceBaselineID)
            )
            _sourceBaseline = FetchOne(
                SourceDetail.sourceBaselineQuery(sourceBaselineID: sourceBaselineID)
            )
            _organizer = FetchOne(
                SourceDetail.organizerQuery(sourceBaselineID: sourceBaselineID)
            )
            _events = FetchAll(
                SourceDetail.eventsQuery(sourceBaselineID: sourceBaselineID)
            )
        }

        var editCalendar: EditCalendar.State?
        var destination: Destination.State?

        @DebugSnapshotIgnored
        @FetchOne
        public var calendar: OMERecord.Calendar?

        @DebugSnapshotIgnored
        @FetchAll
        public var calendarEntries: [OMERecord.CalendarEntry]

        @DebugSnapshotIgnored
        @FetchAll
        public var events: [OMERecord.Event]

        @DebugSnapshotIgnored
        @FetchOne
        public var organizer: OMERecord.Organizer?

        @DebugSnapshotIgnored
        @FetchOne
        public var sourceBaseline: SourceBaselineRecord?

        public let sourceBaselineID: SourceBaselineRecord.ID

        public var id: SourceBaselineRecord.ID { sourceBaselineID }

        var canEditCalendar: Bool {
            editableCalendarID != nil
        }

        var canAddEvent: Bool {
            sourceBaseline != nil && editableCalendarID != nil && organizer != nil
        }

        var editableCalendarID: OMERecord.Calendar.ID? {
            if let calendar {
                return calendar.id
            }
            if let organizer {
                return OrganizerDetail.defaultCalendarID(organizerID: organizer.id)
            }
            return nil
        }
    }

    public enum Action {
        case addEventButtonTapped
        case destination(Destination.Action)
        case editButtonTapped
        case editCalendar(EditCalendar.Action)
        case eventButtonTapped(OMERecord.Event.ID)
        case task
    }

    @Feature
    public enum Destination {
        case createEvent(Spawn<CreateEvent>)
    }

    static func sourceBaselineQuery(
        sourceBaselineID: SourceBaselineRecord.ID
    ) -> some SelectStatementOf<SourceBaselineRecord> {
        SourceBaselineRecord.where { $0.id.eq(sourceBaselineID) }
    }

    static func calendarQuery(
        sourceBaselineID: SourceBaselineRecord.ID
    ) -> some SelectStatementOf<OMERecord.Calendar> {
        OMERecord.Calendar
            .where { $0.id.calendarID.eq(OMERecord.Calendar.defaultID) }
            .where { calendar in
                EventSourceProvenanceRecord
                    .where { $0.sourceBaselineID.eq(sourceBaselineID) }
                    .where { $0.id.organizerID.eq(calendar.id.ownerID) }
                    .exists()
            }
    }

    static func calendarEntriesQuery(
        sourceBaselineID: SourceBaselineRecord.ID
    ) -> some SelectStatementOf<OMERecord.CalendarEntry> {
        OMERecord.CalendarEntry
            .where { $0.id.calendarID.eq(OMERecord.Calendar.defaultID) }
            .where { entry in
                EventSourceProvenanceRecord
                    .where { $0.sourceBaselineID.eq(sourceBaselineID) }
                    .where { $0.id.organizerID.eq(entry.id.calendarOwnerID) }
                    .exists()
            }
    }

    static func organizerQuery(
        sourceBaselineID: SourceBaselineRecord.ID
    ) -> some SelectStatementOf<OMERecord.Organizer> {
        OMERecord.Organizer.where { organizer in
            EventSourceProvenanceRecord
                .where { $0.sourceBaselineID.eq(sourceBaselineID) }
                .where { $0.id.organizerID.eq(organizer.id) }
                .exists()
        }
    }

    static func eventsQuery(
        sourceBaselineID: SourceBaselineRecord.ID
    ) -> some SelectStatementOf<OMERecord.Event> {
        OMERecord.Event.where { event in
            EventSourceProvenanceRecord
                .where { $0.sourceBaselineID.eq(sourceBaselineID) }
                .where { $0.id.organizerID.eq(event.id.organizerID) }
                .where { $0.id.eventID.eq(event.id.eventID) }
                .exists()
        }
    }

    static func displayEntries(
        calendarEntries: [OMERecord.CalendarEntry],
        events: [OMERecord.Event],
        sourceBaseline: SourceBaselineRecord?
    ) -> [OMERecord.CalendarEntry] {
        let sourceEventIDs = Set(events.map(\.id))
        var displayEntries = calendarEntries.filter { entry in
            entry.event.localEventID.map(sourceEventIDs.contains) ?? false
        }

        guard let sourceBaseline else {
            return displayEntries
        }

        let existingEventIDs = Set(displayEntries.compactMap(\.event.localEventID))
        displayEntries.append(
            contentsOf: events
                .filter { !existingEventIDs.contains($0.id) }
                .map { event in
                    synthesizedEntry(
                        event: event,
                        importedAt: sourceBaseline.importedAt
                    )
                }
        )
        return displayEntries
    }

    static func synthesizedEntry(
        event: OMERecord.Event,
        importedAt: Date
    ) -> OMERecord.CalendarEntry {
        OMERecord.CalendarEntry(
            id: .init(
                calendarOwnerID: event.id.organizerID,
                calendarID: OMERecord.Calendar.defaultID,
                entryID: OMERecord.ID<OMERecord.CalendarEntry>(
                    rawValue: event.id.eventID.rawValue
                )
            ),
            event: OMERecord.Event.reference(id: event.id),
            createdAt: importedAt,
            note: nil,
            pinned: false
        )
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addEventButtonTapped:
                guard let calendarID = state.editableCalendarID,
                      let organizer = state.organizer,
                      let sourceBaseline = state.sourceBaseline
                else { return }
                state.destination = .createEvent(
                    Spawn(
                        CreateEvent.State(
                            organizerID: organizer.id,
                            eventOrganizerID: organizer.id,
                            sourceContext: CreateEvent.State.SourceContext(
                                sourceBaseline: sourceBaseline,
                                calendarID: calendarID
                            )
                        )
                    )
                )

            case .destination:
                return

            case .editButtonTapped:
                guard let calendarID = state.editableCalendarID else {
                    return
                }
                state.editCalendar = EditCalendar.State(calendarID: calendarID)

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
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .ifLet(\.editCalendar, action: \.editCalendar) {
            EditCalendar()
        }
    }
}

public struct SourceDetailView: View {
    @Bindable var store: StoreOf<SourceDetail>
    @Dependency(\.date.now) var now

    public init(store: StoreOf<SourceDetail>) {
        self.store = store
    }

    @State var sourceSectionExpanded = false


    public var body: some View {
        HeroImageList(title: Text(calendarTitle)) {
            HeroImage(
                title: Text(calendarTitle),
                asset: store.calendar?.images?.imageAsset(role: .hero),
                cacheContext: calendarImageCacheContext,
                logoAsset: store.calendar?.images?.imageAsset(role: .logo)
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

            if let sourceBaseline = store.sourceBaseline {
                DisclosureGroup("Source", isExpanded: $sourceSectionExpanded) {
                    LabeledContent("Reference", value: sourceBaseline.sourceReference)
                    LabeledContent("Ref", value: sourceBaseline.ref ?? "default ref")
                    LabeledContent(
                        "Imported",
                        value: sourceBaseline.importedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
            }

            if !sections.currentRows.isEmpty {
                Section("Happening Now") {
                    calendarEntryRows(sections.currentRows)
                }
            }

            if !sections.upcomingRows.isEmpty {
                Section("Upcoming Events") {
                    calendarEntryRows(sections.upcomingRows)
                }
            }

            if !sections.previousRows.isEmpty {
                Section("Previous Events") {
                    calendarEntryRows(sections.previousRows)
                }
            }

            if !sections.unavailableRows.isEmpty {
                Section("Unavailable Events") {
                    calendarEntryRows(sections.unavailableRows)
                }
            }

            if sections.isEmpty {
                EmptyBrowserState(
                    title: "No Events",
                    systemImage: "calendar.badge.exclamationmark",
                    message: "This source has no events."
                )
            }
        }
        .sheet(item: $store.scope(\.editCalendar, action: \.editCalendar)) { editStore in
            NavigationStack {
                EditCalendarView(store: editStore)
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).createEvent) { createEventStore in
            NavigationStack {
                CreateEventView(store: createEventStore)
            }
        }
        .toolbar {
            if store.canAddEvent {
                Button("Add Event", systemImage: "plus") {
                    store.send(.addEventButtonTapped)
                }
            }
            if store.canEditCalendar {
                Button("Edit Calendar", systemImage: "pencil") {
                    store.send(.editButtonTapped)
                }
            }
        }
    }

    private var calendarDescription: String? {
        guard let description = store.calendar?.description,
              !description.isEmpty
        else { return nil }
        return description
    }

    private var calendarTitle: String {
        store.calendar?.name
        ?? store.sourceBaseline?.sourceReference
        ?? store.organizer?.id.description
        ?? store.sourceBaselineID.rawValue
    }

    private var calendarImageCacheContext: LocalImageCacheContext? {
        store.editableCalendarID.map(LocalImageCacheContext.init(calendarID:))
    }

    private var entryRows: CalendarDetail.EntryRows {
        return CalendarDetail.EntryRows(
            entries: SourceDetail.displayEntries(
                calendarEntries: store.calendarEntries,
                events: store.events,
                sourceBaseline: store.sourceBaseline
            ),
            events: store.events
        )
    }

    private var sections: OrganizerDetail.CalendarEntrySections {
        OrganizerDetail.CalendarEntrySections(entryRows: entryRows, now: now)
    }

    @ViewBuilder
    private func calendarEntryRows(_ rows: [CalendarDetail.EntryRow]) -> some View {
        ForEach(rows) { row in
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
}

private extension OMERecord.Event {
    var sortDate: LocalDate? {
        startDate ?? endDate
    }
}

@Feature
public struct Search {
    public init() {}

    public struct State {
        public init() {}

        public var isSearching = false
        public var query = ""
        public var results: [BrowseEventRow] = []
    }

    public enum Action {
        case didPullToRefresh
        case eventButtonTapped(OMERecord.Event.ID)
        case queryEdited(String)
        case searchResponse([BrowseEventRow])
        case task
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .eventButtonTapped(let eventID):
                store.addTask {
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(eventID, nil)
                    )
                }

            case .queryEdited(let query):
                state.query = query

            case .didPullToRefresh,
                 .searchResponse,
                 .task:
                break
            }
        }
    }
}

public struct SearchView: View {
    @Bindable var store: StoreOf<Search>

    public init(store: StoreOf<Search>) {
        self.store = store
    }

    public var body: some View {
        content
    }

    private var content: some View {
        NavigationStack {
            List {
                EmptyBrowserState(
                    title: "Search",
                    systemImage: "magnifyingglass",
                    message: "Search feature stub."
                )
            }
            .navigationTitle("Search")
        }
        .searchable(
            text: $store.query,
            prompt: "Search events or organizers"
        )
    }

    @ViewBuilder
    private var searchField: some View {
        #if os(iOS)
        TextField("Search events or organizers", text: $store.query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        TextField("Search events or organizers", text: $store.query)
        #endif
    }
}

public struct BrowseEventRow: Equatable, Identifiable, Sendable {
    public let eventID: OMERecord.Event.ID
    public let eventName: String
    public let startsAt: Date?
    public let endsAt: Date?
    public let organizerIDs: [OMERecord.Organizer.ID]

    public init(
        eventID: OMERecord.Event.ID,
        eventName: String,
        startsAt: Date?,
        endsAt: Date?,
        organizerIDs: [OMERecord.Organizer.ID]
    ) {
        self.eventID = eventID
        self.eventName = eventName
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.organizerIDs = organizerIDs
    }

    public var id: OMERecord.Event.ID { eventID }
}

public struct FollowedOrganizerRow: Equatable, Identifiable, Sendable {
    public let organizerID: OMERecord.Organizer.ID
    public let eventCount: Int

    public init(organizerID: OMERecord.Organizer.ID, eventCount: Int) {
        self.organizerID = organizerID
        self.eventCount = eventCount
    }

    public var id: OMERecord.Organizer.ID { organizerID }
}

struct EmptyBrowserState: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: LocalizedStringKey

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowBackground(Color.clear)
    }
}
