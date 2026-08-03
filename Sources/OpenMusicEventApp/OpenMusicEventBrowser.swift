import ATProto
import ComposableArchitecture2
import ComposableCalendarEvents
import ComposableWorkspace
import Dependencies
import ErrorHandling
import Foundation
import IssueReporting
import OpenMusicEventAppEventViewer
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventSourceEditing
import OpenMusicEventAuthentication
import SourceEditing
import SQLiteData
import SwiftUI
import SwiftUITabFeatures
import Tagged

@Feature
public struct OpenMusicEventBrowser {
    public init() {}

    public enum Tab: String, TabFeatureValue {
        case browse
        case following
        case myEvents
        case search
        case settings

        public init?(_ description: String) {
            self.init(rawValue: description)
        }

        public var description: String {
            self.rawValue
        }
    }

    public struct State {
        public init() {}

        public var selectedTab: Tab = .browse
        public var browse = Spawn(Browse.State())
        public var following = Spawn(Following.State())
        public var search = Spawn(Browse.State())
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
            Browse()
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
    @State var tabLayout = TabFeatureLayout()

    public var body: some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            tabFeaturesView
        } else {
            legacyiOSTabView
        }
        #elseif os(macOS)
        if #available(macOS 15.0, *) {
            tabFeaturesView
        } else {
            defaultTabView
        }
        #else
        defaultTabView
        #endif
    }

    @available(iOS 18.0, macOS 15.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *)
    private var tabFeaturesView: some View {
        TabFeaturesView(
            selection: $store.selectedTab,
            layout: $tabLayout
        ) {
            TabFeature(
                .browse,
                title: "Browse",
                systemImage: "sparkles",
                navigation: .stack
            ) {
                BrowseView(store: store.spawn(\.browse))
            }

            TabFeature(
                .following,
                title: "Following",
                systemImage: "person.2.fill",
                navigation: .stack
            ) {
                FollowingView(store: store.spawn(\.following))
            }

            TabFeature(
                .myEvents,
                title: "My Events",
                systemImage: "star",
                navigation: .stack
            ) {
                MyEventsView(store: store.spawn(\.myEvents))
            }

            TabFeature(
                .settings,
                title: "Settings",
                systemImage: "gearshape",
                navigation: .stack
            ) {
                SettingsFeatureView(store: store.spawn(\.settings))
            }

            TabFeature(.search, role: .search) {
                NavigationStack {
                    BrowseView(store: store.spawn(\.search))
                }
            }
        }
    }

    #if os(iOS)
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

            NavigationStack {
                BrowseView(store: store.spawn(\.search))
            }
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
                BrowseView(store: store.spawn(\.search))
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
        public init(
            catalog: EventCatalog = .openMusicEvent,
            events: [CalendarEvent] = []
        ) {
            self.catalog = catalog
            self.events = events
        }

        public var catalog: EventCatalog
        public var errorMessage: String?
        public var eventDetail: EventBrowseDetail.State?
        public var events: [CalendarEvent]
        public var isLoading = false
        public var searchText = ""
        public var selectedDay: CalendarEvent.Day?
        public var selectedMode: CalendarEvent.Mode?
        public var sort = Sort.soonest

        public var days: [CalendarEvent.Day] {
            Array(Set(events.compactMap(\.localStartDay))).sorted()
        }

        public var visibleEvents: [CalendarEvent] {
            events
                .filter { event in
                    guard let selectedDay else { return true }
                    return event.localStartDay == selectedDay
                }
                .filter { event in
                    guard let selectedMode else { return true }
                    return event.mode == selectedMode
                }
                .filter { event in
                    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !query.isEmpty else { return true }
                    return event.name.localizedCaseInsensitiveContains(query)
                        || event.organizer.name.localizedCaseInsensitiveContains(query)
                        || (event.description?.localizedCaseInsensitiveContains(query) ?? false)
                }
                .sorted { lhs, rhs in
                    switch sort {
                    case .name:
                        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    case .soonest:
                        switch (lhs.startsAt, rhs.startsAt) {
                        case let (.some(lhsDate), .some(rhsDate)):
                            lhsDate == rhsDate
                                ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                                : lhsDate < rhsDate
                        case (.some, .none):
                            true
                        case (.none, .some):
                            false
                        case (.none, .none):
                            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                        }
                    }
                }
        }
    }

    public enum Action {
        case catalogSelected(EventCatalog)
        case browseEventButtonTapped(ATProto.URI)
        case daySelected(CalendarEvent.Day?)
        case didPullToRefresh
        case eventButtonTapped(OMERecord.Event.ID)
        case eventDetail(EventBrowseDetail.Action)
        case modeSelected(CalendarEvent.Mode?)
        case searchTextChanged(String)
        case sortSelected(Sort)
        case task
    }

    public enum Sort: Equatable, Sendable {
        case name
        case soonest
    }

    @Dependency(\.calendarEvents) var calendarEvents

    public var body: some Feature {
        Update { state, action in
            switch action {
            case let .catalogSelected(catalog):
                guard state.catalog != catalog else { return }
                state.catalog = catalog
                state.events = []
                state.selectedDay = nil
                state.selectedMode = nil
                fallthrough

            case .didPullToRefresh, .task:
                let catalog = state.catalog
                state.errorMessage = nil
                state.isLoading = true
                store.addTask {
                    do {
                        let page = try await calendarEvents.browse(
                            CalendarEvent.PageRequest(collection: catalog.collection)
                        )
                        try store.modify {
                            guard $0.catalog == catalog else { return }
                            $0.events = page.events
                            $0.isLoading = false
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        try store.modify {
                            guard $0.catalog == catalog else { return }
                            $0.errorMessage = "Unable to load \(catalog.title.lowercased())."
                            $0.isLoading = false
                        }
                    }
                }

            case let .browseEventButtonTapped(uri):
                guard let event = state.events.first(where: { $0.uri == uri }) else { return }
                state.eventDetail = EventBrowseDetail.State(
                    event: event,
                    organizerEvents: state.events.filter {
                        $0.organizer.id == event.organizer.id && $0.uri != event.uri
                    }
                )

            case let .daySelected(day):
                state.selectedDay = day

            case let .eventButtonTapped(eventID):
                store.addTask {
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(eventID, nil)
                    )
                }

            case .eventDetail:
                return

            case let .modeSelected(mode):
                state.selectedMode = mode

            case let .searchTextChanged(searchText):
                state.searchText = searchText

            case let .sortSelected(sort):
                state.sort = sort
            }
        }
        .ifLet(\.eventDetail, action: \.eventDetail) {
            EventBrowseDetail()
        }
    }
}

public enum EventCatalog: String, CaseIterable, Equatable, Identifiable, Sendable {
    case openMusicEvent
    case communityCalendar

    public var id: Self { self }

    public var collection: ATProto.NSID {
        switch self {
        case .openMusicEvent:
            OME.Event.nsid
        case .communityCalendar:
            "community.lexicon.calendar.event"
        }
    }

    public var title: String {
        switch self {
        case .openMusicEvent:
            "Open Music Events"
        case .communityCalendar:
            "Calendar Events"
        }
    }
}

public struct BrowseView: View {
    @Bindable var store: StoreOf<Browse>

    public init(store: StoreOf<Browse>) {
        self.store = store
    }

    public var body: some View {
        List {
            if !store.days.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        BrowseDayButton(
                            title: "All",
                            isSelected: store.selectedDay == nil
                        ) {
                            store.send(.daySelected(nil))
                        }
                        ForEach(store.days) { day in
                            BrowseDayButton(
                                title: "\(day.month)/\(day.day)",
                                isSelected: store.selectedDay == day
                            ) {
                                store.send(.daySelected(day))
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if let errorMessage = store.errorMessage {
                ContentUnavailableView(
                    "Events Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if store.isLoading && store.events.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Loading events")
                    Spacer()
                }
            } else if store.visibleEvents.isEmpty {
                EmptyBrowserState(
                    title: "No Events",
                    systemImage: "calendar",
                    message: "No events match the current browse selection."
                )
            } else {
                ForEach(store.visibleEvents) { event in
                    Button {
                        store.send(.browseEventButtonTapped(event.uri))
                    } label: {
                        BrowseCalendarEventRow(event: event)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Browse")
        .navigationDestination(
            item: $store.scope(\.eventDetail, action: \.eventDetail)
        ) { detailStore in
            EventBrowseDetailView(store: detailStore)
        }
        .searchable(
            text: Binding(
                get: { store.searchText },
                set: { store.send(.searchTextChanged($0)) }
            ),
            prompt: "Search events or organizers"
        )
        .refreshable {
            await store.send(.didPullToRefresh)?.value
        }
        .task {
            await store.send(.task)?.value
        }
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    ForEach(EventCatalog.allCases) { catalog in
                        Button {
                            store.send(.catalogSelected(catalog))
                        } label: {
                            if store.catalog == catalog {
                                Label(catalog.title, systemImage: "checkmark")
                            } else {
                                Text(catalog.title)
                            }
                        }
                    }
                } label: {
                    Label(store.catalog.title, systemImage: "calendar")
                }

                Menu {
                    Button("All formats") { store.send(.modeSelected(nil)) }
                    Button("In person") { store.send(.modeSelected(.inPerson)) }
                    Button("Virtual") { store.send(.modeSelected(.virtual)) }
                    Button("Hybrid") { store.send(.modeSelected(.hybrid)) }
                    Divider()
                    Button("Soonest first") { store.send(.sortSelected(.soonest)) }
                    Button("Name") { store.send(.sortSelected(.name)) }
                } label: {
                    Label("Filter and sort", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }
}

struct BrowseDayButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background {
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                }
        }
        .buttonStyle(.plain)
    }
}

struct BrowseCalendarEventRow: View {
    let event: CalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.name)
                .font(.headline)
            Text(event.organizer.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let startsAt = event.startsAt {
                Text(
                    startsAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.subheadline)
            }
            if let location = event.locations.first?.summary {
                Label(location, systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

@Feature
public struct EventBrowseDetail {
    public init() {}

    public struct State: Identifiable {
        public init(event: CalendarEvent, organizerEvents: [CalendarEvent] = []) {
            self.event = event
            self.organizerEvents = organizerEvents
        }

        public var errorMessage: String?
        public var event: CalendarEvent
        public var isEnteringEvent = false
        public var isSavingRSVP = false
        public var organizerDetail: CalendarEvent.Organizer?
        public var organizerEvents: [CalendarEvent]
        public var rsvpStatus: OME.RSVP.Status?

        public var id: ATProto.URI { event.uri }
    }

    public enum Action {
        case enterEventButtonTapped
        case organizerButtonTapped
        case rsvpButtonTapped(OME.RSVP.Status)
        case task
    }

    @Dependency(\.date.now) var now
    @Dependency(\.calendarEvents) var calendarEvents
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.getSelectedOAuthSessionID) var selectedAccountID
    @Dependency(\.omeEventInstallation) var eventInstallation

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .enterEventButtonTapped:
                let eventURI = state.event.uri
                state.errorMessage = nil
                state.isEnteringEvent = true
                store.addTask {
                    do {
                        let eventID = try await eventInstallation.ensureInstalled(eventURI)
                        try store.modify {
                            $0.isEnteringEvent = false
                        }
                        try store.post(
                            key: NavigationRequested.self,
                            value: .event(eventID, nil)
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to enter this event."
                            $0.isEnteringEvent = false
                        }
                    }
                }

            case .organizerButtonTapped:
                state.organizerDetail = state.event.organizer

            case let .rsvpButtonTapped(status):
                let event = state.event
                let consumer = EventRSVP.Consumer(
                    accountDID: selectedAccountID()?.rawValue
                )
                state.errorMessage = nil
                state.isSavingRSVP = true
                store.addTask {
                    do {
                        try database.write { db in
                            try EventRSVP.save(
                                eventURI: event.uri,
                                eventCID: event.cid,
                                consumer: consumer,
                                status: status,
                                createdAt: now,
                                in: db
                            )
                        }
                        try store.modify {
                            $0.isSavingRSVP = false
                            $0.rsvpStatus = status
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to save your RSVP."
                            $0.isSavingRSVP = false
                        }
                    }
                }

            case .task:
                let eventURI = state.event.uri
                let consumer = EventRSVP.Consumer(
                    accountDID: selectedAccountID()?.rawValue
                )
                store.addTask {
                    do {
                        let event = try await calendarEvents.event(eventURI)
                        let record = try await database.read { db in
                            try EventRSVP.forEvent(eventURI, consumer: consumer).fetchOne(db)
                        }
                        try store.modify {
                            $0.event = event
                            $0.rsvpStatus = record?.status
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to load all event details."
                        }
                    }
                }
            }
        }
    }
}

public struct EventBrowseDetailView: View {
    @Bindable var store: StoreOf<EventBrowseDetail>

    public init(store: StoreOf<EventBrowseDetail>) {
        self.store = store
    }

    public var body: some View {
        List {
            if let media = store.event.media.first {
                AsyncImage(url: media.url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
                .accessibilityLabel(media.alt ?? store.event.name)
            }

            Section {
                Button {
                    store.send(.organizerButtonTapped)
                } label: {
                    LabeledContent("Organizer", value: store.event.organizer.name)
                }

                if let startsAt = store.event.startsAt {
                    LabeledContent(
                        "Starts",
                        value: startsAt.formatted(date: .long, time: .shortened)
                    )
                }
                if let endsAt = store.event.endsAt {
                    LabeledContent(
                        "Ends",
                        value: endsAt.formatted(date: .long, time: .shortened)
                    )
                }
                if let location = store.event.locations.first?.summary {
                    LabeledContent("Location", value: location)
                }
            }

            if let description = store.event.description, !description.isEmpty {
                Section("About") {
                    Text(description)
                }
            }

            Section("RSVP") {
                RSVPStatusButton(
                    title: "Going",
                    status: .going,
                    selectedStatus: store.rsvpStatus,
                    disabled: store.isSavingRSVP
                ) {
                    store.send(.rsvpButtonTapped(.going))
                }
                RSVPStatusButton(
                    title: "Interested",
                    status: .interested,
                    selectedStatus: store.rsvpStatus,
                    disabled: store.isSavingRSVP
                ) {
                    store.send(.rsvpButtonTapped(.interested))
                }
                RSVPStatusButton(
                    title: "Not Going",
                    status: .notGoing,
                    selectedStatus: store.rsvpStatus,
                    disabled: store.isSavingRSVP
                ) {
                    store.send(.rsvpButtonTapped(.notGoing))
                }
                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if !store.event.links.isEmpty {
                Section("Links") {
                    ForEach(Array(store.event.links.enumerated()), id: \.offset) { _, link in
                        Link(link.name ?? link.uri.host() ?? "Event link", destination: link.uri)
                    }
                }
            }

            if store.event.source.collection == OME.Event.nsid {
                Section {
                    Button("Enter Event") {
                        store.send(.enterEventButtonTapped)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isEnteringEvent)
                }
            }
        }
        .navigationTitle(store.event.name)
        .navigationDestination(item: $store.organizerDetail) { organizer in
            BrowseOrganizerDetailView(
                organizer: organizer,
                events: store.organizerEvents
            )
        }
        .task {
            await store.send(.task)?.value
        }
    }
}

struct RSVPStatusButton: View {
    let title: String
    let status: OME.RSVP.Status
    let selectedStatus: OME.RSVP.Status?
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if selectedStatus == status {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .disabled(disabled)
    }
}

struct BrowseOrganizerDetailView: View {
    let organizer: CalendarEvent.Organizer
    let events: [CalendarEvent]

    var body: some View {
        List {
            Section {
                Text(organizer.name)
                    .font(.title2.weight(.semibold))
                if let handle = organizer.handle {
                    Text("@\(handle)")
                        .foregroundStyle(.secondary)
                }
                if let description = organizer.description, !description.isEmpty {
                    Text(description)
                }
            }

            if !events.isEmpty {
                Section("More Events") {
                    ForEach(events) { event in
                        BrowseCalendarEventRow(event: event)
                    }
                }
            }
        }
        .navigationTitle("Organizer")
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
        public enum ScheduleSection: Hashable, Sendable {
            case now
            case upcoming
            case previous
            case unavailable
        }

        public var currentRows: [CalendarDetail.EntryRow]
        public var upcomingRows: [CalendarDetail.EntryRow]
        public var previousRows: [CalendarDetail.EntryRow]
        public var unavailableRows: [CalendarDetail.EntryRow]

        public init(entryRows: CalendarDetail.EntryRows, now: Date) {
            let rows = entryRows.rows
            self.currentRows = Self.sortChronologically(
                rows.filter { Self.timing(for: $0, now: now) == .current }
            )
            self.upcomingRows = Self.sortChronologically(
                rows.filter { Self.timing(for: $0, now: now) == .upcoming }
            )
            self.previousRows = Self.sortReverseChronologically(
                rows.filter { Self.timing(for: $0, now: now) == .previous }
            )
            self.unavailableRows = rows.filter { Self.timing(for: $0, now: now) == .unavailable }
        }

        public var isEmpty: Bool {
            currentRows.isEmpty
            && upcomingRows.isEmpty
            && previousRows.isEmpty
            && unavailableRows.isEmpty
        }

        public var initialSection: ScheduleSection? {
            if !currentRows.isEmpty { return .now }
            if !upcomingRows.isEmpty { return .upcoming }
            if !previousRows.isEmpty { return .previous }
            if !unavailableRows.isEmpty { return .unavailable }
            return nil
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

        private static func sortChronologically(
            _ rows: [CalendarDetail.EntryRow]
        ) -> [CalendarDetail.EntryRow] {
            rows.sorted { lhs, rhs in
                Self.comesBefore(lhs: lhs, rhs: rhs, order: .ascending)
            }
        }

        private static func sortReverseChronologically(
            _ rows: [CalendarDetail.EntryRow]
        ) -> [CalendarDetail.EntryRow] {
            rows.sorted { lhs, rhs in
                Self.comesBefore(lhs: lhs, rhs: rhs, order: .descending)
            }
        }

        private enum ChronologicalOrder {
            case ascending
            case descending
        }

        private static func comesBefore(
            lhs: CalendarDetail.EntryRow,
            rhs: CalendarDetail.EntryRow,
            order: ChronologicalOrder
        ) -> Bool {
            switch (
                lhs.event.flatMap { $0.startDate ?? $0.endDate },
                rhs.event.flatMap { $0.startDate ?? $0.endDate }
            ) {
            case let (.some(lhsDate), .some(rhsDate)):
                let dateComparison = lhsDate.description.localizedStandardCompare(rhsDate.description)
                if dateComparison != .orderedSame {
                    switch order {
                    case .ascending:
                        return dateComparison == .orderedAscending
                    case .descending:
                        return dateComparison == .orderedDescending
                    }
                }

            case (.some, .none):
                return true

            case (.none, .some):
                return false

            case (.none, .none):
                break
            }

            let lhsName = lhs.event?.name ?? ""
            let rhsName = rhs.event?.name ?? ""
            let nameComparison = lhsName.localizedStandardCompare(rhsName)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            if lhs.entry.createdAt != rhs.entry.createdAt {
                return lhs.entry.createdAt < rhs.entry.createdAt
            }

            return lhs.entry.id.entryID.rawValue.rawValue.localizedStandardCompare(
                rhs.entry.id.entryID.rawValue.rawValue
            ) == .orderedAscending
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

    var initialScrollID: AnyHashable? {
        guard let initialSection = sections.initialSection else { return nil }
        return AnyHashable(initialSection)
    }

    public var body: some View {
        HeroImageList(
            title: Text(organizerTitle),
            initialScrollID: initialScrollID
        ) {
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
                Section("Now") {
                    calendarEntryRows(sections.currentRows)
                }
                .id(OrganizerDetail.CalendarEntrySections.ScheduleSection.now)
            }

            if !sections.upcomingRows.isEmpty {
                Section("Upcoming") {
                    calendarEntryRows(sections.upcomingRows)
                }
                .id(OrganizerDetail.CalendarEntrySections.ScheduleSection.upcoming)
            }

            if !sections.previousRows.isEmpty {
                Section("Previous") {
                    calendarEntryRows(sections.previousRows)
                }
                .id(OrganizerDetail.CalendarEntrySections.ScheduleSection.previous)
            }

            if !sections.unavailableRows.isEmpty {
                Section("Unavailable Events") {
                    calendarEntryRows(sections.unavailableRows)
                }
                .id(OrganizerDetail.CalendarEntrySections.ScheduleSection.unavailable)
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
            Button {
                store.send(.addEventButtonTapped)
            } label: {
                Label("Add Event", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
        }
        .whiteLabelRootToolbar(store: whiteLabelRootStore)
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

    public struct State: Identifiable, OpenMusicEventWorkspaceContentState {
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
        @Trigger<WorkspaceProposal> public var workspaceProposalRecorded
        @Trigger public var workspaceSourcePrepared

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
        case rolloverEventButtonTapped
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

    @Dependency(\.sourceDataRefresh) var sourceDataRefresh
    @FeatureEnvironment(WorkspaceContext<SourceWorkspaceDatabase, SourcePatch>.self)
    var workspace
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

            case .rolloverEventButtonTapped:
                guard let calendarID = state.editableCalendarID,
                      let sourceBaseline = state.sourceBaseline
                else { return }
                state.destination = .createEvent(
                    Spawn(
                        TeamWorkspaceCreateEvent.State(
                            sourceBaselineID: sourceBaseline.id,
                            calendarID: calendarID,
                            strategy: .rollover
                        )
                    )
                )

            case .destination:
                return

            case .didPullToRefresh:
                if workspace.source.wrappedValue != nil {
                    store.addTask(id: sourceDataRefreshTask) {
                        let reconciliation = try store.post(
                            key: WorkspaceReconciliationRequested.self,
                            value: ()
                        )
                        await reconciliation?.value
                    }
                    return
                }
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
                guard let calendarID = state.editableCalendarID,
                      let sourceBaseline = state.sourceBaseline,
                      let source = workspace.source.wrappedValue
                else { return }
                state.teamWorkspaceEditor = withDependencies {
                    $0.defaultDatabase = source.database
                } operation: {
                    SourceWorkspace.State(
                        target: .calendar(calendarID, sourceBaseline.id)
                    )
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
        }
        .onTrigger(store.workspaceProposalRecorded) { _, _ in }
    }
}

public struct TeamWorkspaceDetailView: View {
    @Bindable var store: StoreOf<TeamWorkspaceDetail>
    @Dependency(\.date.now) var now
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
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

    var initialScrollID: AnyHashable? {
        guard let initialSection = sections.initialSection else { return nil }
        return AnyHashable(initialSection)
    }

    public var body: some View {
        HeroImageList(
            title: Text(calendarTitle),
            initialScrollID: initialScrollID
        ) {
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

            if showsTechnicalDetails, let sourceBaseline = store.sourceBaseline {
                DisclosureGroup("Technical details", isExpanded: $sourceSectionExpanded) {
                    OpenMusicEventComponents.WorkspaceTechnicalValueView(
                        label: "Source address",
                        value: sourceBaseline.sourceReference
                    )
                    OpenMusicEventComponents.WorkspaceTechnicalValueView(
                        label: "Provider",
                        value: sourceBaseline.sourceKind.rawValue
                    )
                    OpenMusicEventComponents.WorkspaceTechnicalValueView(
                        label: "Version",
                        value: sourceBaseline.ref ?? "default version"
                    )
                    if let organizerID = store.organizer?.id.description {
                        OpenMusicEventComponents.WorkspaceTechnicalValueView(
                            label: "Owner actor ID",
                            value: organizerID
                        )
                    }
                    OpenMusicEventComponents.WorkspaceTechnicalValueView(
                        label: "Imported",
                        value: sourceBaseline.importedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
            }

            if !sections.currentRows.isEmpty {
                Section("Now") {
                    calendarEntryRows(sections.currentRows)
                }
                .id(OrganizerDetail.CalendarEntrySections.ScheduleSection.now)
            }

            if !sections.upcomingRows.isEmpty {
                Section("Upcoming") {
                    calendarEntryRows(sections.upcomingRows)
                }
                .id(OrganizerDetail.CalendarEntrySections.ScheduleSection.upcoming)
            }

            if !sections.previousRows.isEmpty {
                Section("Previous") {
                    calendarEntryRows(sections.previousRows)
                }
                .id(OrganizerDetail.CalendarEntrySections.ScheduleSection.previous)
            }

            if !sections.unavailableRows.isEmpty {
                Section("Unavailable Events") {
                    calendarEntryRows(sections.unavailableRows)
                }
                .id(OrganizerDetail.CalendarEntrySections.ScheduleSection.unavailable)
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
        .toolbar(content: toolbarContent)
    }

    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItemGroup {
            if showsAuthoringControls, store.canEditCalendar {
                Button {
                    store.send(.editButtonTapped)
                } label: {
                    Label("Edit Calendar", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                }
            }
            if showsAuthoringControls, store.canCreateEvent {
                Menu {
                    Button("Blank Event") {
                        store.send(.addEventButtonTapped)
                    }
                    Button("Start from Previous Event") {
                        store.send(.rolloverEventButtonTapped)
                    }
                } label: {
                    Label("Add Event", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
            }
            if showsAuthoringControls, store.canUploadToTangled {
                Button {
                    store.send(.uploadToTangledButtonTapped)
                } label: {
                    Label("Upload to Tangled", systemImage: "arrow.up.doc")
                        .labelStyle(.iconOnly)
                }
            }
            if showsAuthoringControls,
               isManageWorkspaceToolbarItemVisible,
               store.sourceBaseline != nil,
               store.editableCalendarID != nil
            {
                Button {
                    store.send(.manageSourceButtonTapped)
                } label: {
                    Label("Manage Team Workspace", systemImage: "tray.full")
                    .labelStyle(.iconOnly)
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
        ?? "Shared workspace"
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
