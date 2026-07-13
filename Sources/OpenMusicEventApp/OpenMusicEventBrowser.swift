import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
import IssueReporting
import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventSourceEditing
import OpenMusicEventAuthentication
import SourceEditing
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
//        let _ = Self._logChanges()

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
        var deleteEventIDs: [OMERecord.Event.ID] = []
        var errorMessage: String?
        var isDeleteEventsConfirmationPresented = false

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
        case deleteEventsButtonTapped([OMERecord.Event.ID])
        case deleteEventsConfirmationDeleteButtonTapped
        case deleteEventsConfirmationPresentedChanged(Bool)
        case destination(Destination.Action)
        case eventButtonTapped(OMERecord.Event.ID)
        case task
    }

    @Feature
    public enum Destination {
        case createEvent(Spawn<CreateEvent>)
    }

    @Dependency(\.defaultDatabase) var database

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

            case let .deleteEventsButtonTapped(eventIDs):
                guard !eventIDs.isEmpty else { return }
                state.deleteEventIDs = eventIDs.uniqued()
                state.isDeleteEventsConfirmationPresented = true

            case .deleteEventsConfirmationDeleteButtonTapped:
                let eventIDs = state.deleteEventIDs
                store.addTask {
                    do {
                        try database.write { db in
                            try MyEventsDeletion.deleteCreatedLocalEvents(eventIDs, in: db)
                        }
                        try store.modify {
                            $0.deleteEventIDs = []
                            $0.errorMessage = nil
                            $0.isDeleteEventsConfirmationPresented = false
                        }
                    } catch {
                        try store.modify {
                            $0.isDeleteEventsConfirmationPresented = false
                            $0.errorMessage = "Unable to delete event."
                        }
                    }
                }

            case let .deleteEventsConfirmationPresentedChanged(isPresented):
                state.isDeleteEventsConfirmationPresented = isPresented
                if !isPresented {
                    state.deleteEventIDs = []
                }

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
    let whiteLabelRootStore: StoreOf<WhiteLabelRoot>?

    public init(
        store: StoreOf<OrganizerDetail>,
        whiteLabelRootStore: StoreOf<WhiteLabelRoot>? = nil
    ) {
        self.store = store
        self.whiteLabelRootStore = whiteLabelRootStore
    }

    public var body: some View {
        HeroImageList(title: Text(organizerTitle)) {
            HeroImage(
                title: Text(organizerTitle),
                sources: [],
                titleSources: [.title]
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

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
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
            CalendarDetailView(
                store: detailStore,
                whiteLabelRootStore: whiteLabelRootStore
            )
        }
        .confirmationDialog(
            "Delete Event?",
            isPresented: deleteEventsConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Event", role: .destructive) {
                store.send(.deleteEventsConfirmationDeleteButtonTapped)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the selected event data from this device. Created events are not cached off device.")
        }
        .toolbar {
            Button("Add Event", systemImage: "plus") {
                store.send(.addEventButtonTapped)
            }
        }
        .whiteLabelRootActionsToolbar(store: whiteLabelRootStore)
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

    private var deleteEventsConfirmationPresented: Binding<Bool> {
        Binding(
            get: { store.isDeleteEventsConfirmationPresented },
            set: { store.send(.deleteEventsConfirmationPresentedChanged($0)) }
        )
    }

    private var showsAuthoringControls: Bool {
        whiteLabelRootStore?.showsAuthoringControls ?? false
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
        .onDelete { offsets in
            guard showsAuthoringControls else { return }
            let eventIDs = offsets.compactMap { offset in
                rows.indices.contains(offset)
                    ? rows[offset].eventID
                    : nil
            }
            store.send(.deleteEventsButtonTapped(eventIDs))
        }
        .deleteDisabled(!showsAuthoringControls)
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
public struct TeamWorkspaceDetail {
    public init() {}

    public struct State: Identifiable {
        public init(sourceBaselineID: SourceBaselineRecord.ID) {
            self.sourceBaselineID = sourceBaselineID
            _calendar = FetchOne(
                TeamWorkspaceDetail.calendarQuery(sourceBaselineID: sourceBaselineID)
            )
            _calendarEntries = FetchAll(
                TeamWorkspaceDetail.calendarEntriesQuery(sourceBaselineID: sourceBaselineID)
            )
            _sourceBaseline = FetchOne(
                TeamWorkspaceDetail.sourceBaselineQuery(sourceBaselineID: sourceBaselineID)
            )
            _organizer = FetchOne(
                TeamWorkspaceDetail.organizerQuery(sourceBaselineID: sourceBaselineID)
            )
            _events = FetchAll(
                TeamWorkspaceDetail.eventsQuery(sourceBaselineID: sourceBaselineID)
            )
        }

        var destination: Destination.State?
        var editCalendar: EditCalendar.State?
        var teamWorkspaceEditor: SourceWorkspace.State?
        var isPreparingTeamWorkspaceEditor = false

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

        var fetchLoadFailures: [FetchLoadFailure] {
            [
                FetchLoadFailure(
                    label: "TeamWorkspaceDetail.calendar",
                    error: $calendar.loadError
                ),
                FetchLoadFailure(
                    label: "TeamWorkspaceDetail.calendarEntries",
                    error: $calendarEntries.loadError
                ),
                FetchLoadFailure(label: "TeamWorkspaceDetail.events", error: $events.loadError),
                FetchLoadFailure(
                    label: "TeamWorkspaceDetail.organizer",
                    error: $organizer.loadError
                ),
                FetchLoadFailure(
                    label: "TeamWorkspaceDetail.sourceBaseline",
                    error: $sourceBaseline.loadError
                ),
            ]
            .compactMap { $0 }
        }

        var canManageSource: Bool {
            sourceBaseline != nil && editableCalendarID != nil
        }

        var canUploadToTangled: Bool {
            sourceBaseline?.sourceKind == .local
        }

        var canCreateEvent: Bool {
            sourceBaseline != nil && editableCalendarID != nil
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
        case didPullToRefresh
        case editButtonTapped
        case editCalendar(EditCalendar.Action)
        case eventButtonTapped(OMERecord.Event.ID)
        case manageSourceButtonTapped
        case teamWorkspaceEditor(SourceWorkspace.Action)
        case task
        case uploadToTangledButtonTapped
    }

    @Feature
    public enum Destination {
        case createEvent(Spawn<TeamWorkspaceCreateEvent>)
        case uploadToTangled(Spawn<TangledWorkspaceUpload>)
    }

    @Dependency(\.sourceEditModePreparation) var sourceEditModePreparation
    @Dependency(\.sourceDataRefresh) var sourceDataRefresh
    @Dependency(\.sourceWorkspaceDatabase) var sourceWorkspaceDatabase
    @StoreTaskID var sourceDataRefreshTask

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
        let eventIDs = Set(events.map(\.id))
        var displayEntries = calendarEntries.filter { entry in
            entry.event.localEventID.map(eventIDs.contains) ?? false
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

    static func defaultTangledRepositoryName(
        for sourceBaseline: SourceBaselineRecord
    ) -> String {
        let lastPathComponent = URL(
            fileURLWithPath: sourceBaseline.sourceReference
        )
        .lastPathComponent
        guard !lastPathComponent.isEmpty else {
            return "open-music-event"
        }
        return lastPathComponent
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addEventButtonTapped:
                guard let calendarID = state.editableCalendarID,
                      let sourceBaseline = state.sourceBaseline
                else { return }
                state.destination = .createEvent(
                    Spawn(
                        TeamWorkspaceCreateEvent.State(
                            sourceBaselineID: sourceBaseline.id,
                            calendarID: calendarID
                        )
                    )
                )

            case .destination:
                return

            case .didPullToRefresh:
                let sourceBaselineID = state.sourceBaselineID
                store.addTask(id: sourceDataRefreshTask) {
                    let _: Void? = await store.withErrorHandling(
                        fallbackMessage: .sourceDataRefreshFailed,
                        operation: .sourceDataRefresh
                    ) {
                        try await sourceDataRefresh.refresh(sourceBaselineID)
                    } parseError: {
                        SourceImportError.parser
                    }
                }

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

            case .manageSourceButtonTapped:
                guard !state.isPreparingTeamWorkspaceEditor else { return }
                guard let calendarID = state.editableCalendarID,
                      let sourceBaseline = state.sourceBaseline
                else { return }
                let sourceBaselineID = sourceBaseline.id
                let sourceEditModePreparation = sourceEditModePreparation
                let sourceWorkspaceDatabase = sourceWorkspaceDatabase
                state.isPreparingTeamWorkspaceEditor = true
                store.addTask {
                    let teamWorkspaceEditor = await store.withErrorHandling(
                        fallbackMessage: .sourceEditPreparationFailed,
                        operation: .sourceEditPreparation
                    ) {
                        try await sourceEditModePreparation.prepare(sourceBaselineID)
                        let workspaceDatabase = try sourceWorkspaceDatabase
                            .sourceBaseline(sourceBaselineID)
                        return withDependencies {
                            $0.defaultDatabase = workspaceDatabase.database
                            $0.sourceEditingSession = workspaceDatabase.sourceEditingSession
                        } operation: {
                            SourceWorkspace.State(
                                target: .calendar(calendarID, sourceBaselineID)
                            )
                        }
                    } cleanup: {
                        $0.isPreparingTeamWorkspaceEditor = false
                    } parseError: {
                        SourceImportError.parser
                    }

                    guard let teamWorkspaceEditor else { return }
                    try store.modify {
                        $0.isPreparingTeamWorkspaceEditor = false
                        $0.teamWorkspaceEditor = teamWorkspaceEditor
                    }
                }

            case let .teamWorkspaceEditor(
                .delegate(
                    .createEventRequested(sourceBaselineID: sourceBaselineID, calendarID: calendarID)
                )
            ):
                state.destination = .createEvent(
                    Spawn(
                        TeamWorkspaceCreateEvent.State(
                            sourceBaselineID: sourceBaselineID,
                            calendarID: calendarID
                        )
                    )
                )

            case .teamWorkspaceEditor:
                return

            case .task:
                break

            case .uploadToTangledButtonTapped:
                guard let sourceBaseline = state.sourceBaseline,
                      sourceBaseline.sourceKind == .local
                else { return }
                state.destination = .uploadToTangled(
                    Spawn(
                        TangledWorkspaceUpload.State(
                            sourceBaselineID: sourceBaseline.id,
                            repositoryName: Self.defaultTangledRepositoryName(
                                for: sourceBaseline
                            )
                        )
                    )
                )
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .ifLet(\.editCalendar, action: \.editCalendar) {
            EditCalendar()
        }
        .ifLet(\.teamWorkspaceEditor, action: \.teamWorkspaceEditor) {
            SourceWorkspace()
                .transformDependency(\.self) { (dependencies: inout DependencyValues) in
                    guard case let .calendar(_, sourceBaselineID) = store.teamWorkspaceEditor!.target else {
                        return
                    }
                    do {
                        let workspaceDatabase = try dependencies.sourceWorkspaceDatabase
                            .sourceBaseline(sourceBaselineID)
                        dependencies.sourceEditingSession = workspaceDatabase.sourceEditingSession
                    } catch {
                        reportIssue(error)
                    }
                }
        }
    }
}

public struct TeamWorkspaceDetailView: View {
    @Bindable var store: StoreOf<TeamWorkspaceDetail>
    @Dependency(\.date.now) var now
    let isManageWorkspaceToolbarItemVisible: Bool
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<TeamWorkspaceDetail>,
        isManageWorkspaceToolbarItemVisible: Bool = true,
        showsAuthoringControls: Bool = true
    ) {
        self.store = store
        self.isManageWorkspaceToolbarItemVisible = isManageWorkspaceToolbarItemVisible
        self.showsAuthoringControls = showsAuthoringControls
    }

    @State var sourceSectionExpanded = false


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
            if !store.fetchLoadFailures.isEmpty {
                FetchLoadErrorSection(failures: store.fetchLoadFailures)
            }

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
        .refreshable {
            await store.send(.didPullToRefresh)?.value
        }
        .sheet(item: $store.scope(\.editCalendar, action: \.editCalendar)) { editStore in
            NavigationStack {
                EditCalendarView(store: editStore)
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).createEvent) { createEventStore in
            NavigationStack {
                TeamWorkspaceCreateEventView(store: createEventStore)
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).uploadToTangled) { uploadStore in
            NavigationStack {
                TangledWorkspaceUploadView(store: uploadStore)
            }
        }
        .sheet(item: $store.scope(\.teamWorkspaceEditor, action: \.teamWorkspaceEditor)) { teamWorkspaceEditorStore in
            NavigationStack {
                SourceWorkspaceView(store: teamWorkspaceEditorStore)
            }
        }
        .toolbar {
            if showsAuthoringControls, store.canEditCalendar {
                Button("Edit Calendar", systemImage: "pencil") {
                    store.send(.editButtonTapped)
                }
            }
            if showsAuthoringControls, store.canCreateEvent {
                Button("Add Event", systemImage: "plus") {
                    store.send(.addEventButtonTapped)
                }
            }
            if showsAuthoringControls, store.canUploadToTangled {
                Button("Upload to Tangled") {
                    store.send(.uploadToTangledButtonTapped)
                }
            }
            if showsAuthoringControls, isManageWorkspaceToolbarItemVisible && store.canManageSource {
                Button(
                    store.isPreparingTeamWorkspaceEditor
                        ? "Preparing Team Workspace"
                        : "Manage Team Workspace",
                    systemImage: "person.3"
                ) {
                    store.send(.manageSourceButtonTapped)
                }
                .disabled(store.isPreparingTeamWorkspaceEditor)
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

    private var entryRows: CalendarDetail.EntryRows {
        return CalendarDetail.EntryRows(
            entries: TeamWorkspaceDetail.displayEntries(
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
