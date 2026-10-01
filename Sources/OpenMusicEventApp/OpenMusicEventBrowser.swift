import HeroImageList
import ATProto
import ATProtoTypes
import Bluesky
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
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import OpenMusicEventAuthentication
import SourceEditing
import SQLiteData
import SwiftUI
import SwiftUITabFeatures
import Tagged

#if SKIP
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.DateRange
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
#endif

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

        public var account = Spawn(Account.State())
        public var selectedTab: Tab = .browse
        public var browse = Spawn(Browse.State())
        public var following = Spawn(Following.State())
        public var search = Spawn(Browse.State())
        public var settings = Settings.State()
        public var myEvents = Spawn(MyEvents.State())

        public var myEventsNotificationIndicatorCount: Int {
            myEvents.notificationIndicatorCount
        }
    }

    public enum Action {
        case settings(Settings.Action)
        case task
    }

    public var body: some Feature {
//        let _ = Self._logChanges()

        Features {
            Update { _, action in
                switch action {
                case .settings:
                    break

                case .task:
                    break
                }
            }
            Scope(\.settings) {
                Settings()
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
        .spawn(\.myEvents) { MyEvents() }
        .spawn(\.account) { Account() }
    }
}

public struct OpenMusicEventBrowserView: View {
    public init(
        store: StoreOf<OpenMusicEventBrowser>,
        serviceEnvironment: OpenMusicEventServiceEnvironment,
        isServiceEnvironmentSelectionEnabled: Bool,
        isServiceEnvironmentSwitching: Bool,
        serviceEnvironmentSelected: @escaping (OpenMusicEventServiceEnvironment) -> Void
    ) {
        self.store = store
        self.accountStore = store.spawn(\.account)
        self.serviceEnvironment = serviceEnvironment
        self.isServiceEnvironmentSelectionEnabled = isServiceEnvironmentSelectionEnabled
        self.isServiceEnvironmentSwitching = isServiceEnvironmentSwitching
        self.serviceEnvironmentSelected = serviceEnvironmentSelected
    }

    @Bindable var store: StoreOf<OpenMusicEventBrowser>
    @Bindable var accountStore: StoreOf<Account>
    @State var tabLayout = TabFeatureLayout()
    let serviceEnvironment: OpenMusicEventServiceEnvironment
    let isServiceEnvironmentSelectionEnabled: Bool
    let isServiceEnvironmentSwitching: Bool
    let serviceEnvironmentSelected: (OpenMusicEventServiceEnvironment) -> Void

    public var body: some View {
        Group {
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
        .sheet(
            item: $accountStore.presentation,
            onDismiss: { accountStore.send(.accountPresentationDismissed) }
        ) { _ in
            AccountPresentationView(store: accountStore)
        }
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
                BrowseView(store: store.spawn(\.browse), accountStore: accountStore)
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
                badgeValue: store.myEventsNotificationIndicatorCount,
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
                SettingsFeatureView(
                    store: store.scope(\.settings),
                    serviceEnvironment: serviceEnvironment,
                    isServiceEnvironmentSelectionEnabled: isServiceEnvironmentSelectionEnabled,
                    isServiceEnvironmentSwitching: isServiceEnvironmentSwitching,
                    serviceEnvironmentSelected: serviceEnvironmentSelected
                )
            }

            TabFeature(.search, role: .search) {
                NavigationStack {
                    BrowseView(store: store.spawn(\.search), accountStore: accountStore)
                }
            }
        }
    }

    #if os(iOS)
    private var legacyiOSTabView: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack {
                BrowseView(store: store.spawn(\.browse), accountStore: accountStore)
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
            .badge(store.myEventsNotificationIndicatorCount)

            NavigationStack {
                SettingsFeatureView(
                    store: store.scope(\.settings),
                    serviceEnvironment: serviceEnvironment,
                    isServiceEnvironmentSelectionEnabled: isServiceEnvironmentSelectionEnabled,
                    isServiceEnvironmentSwitching: isServiceEnvironmentSwitching,
                    serviceEnvironmentSelected: serviceEnvironmentSelected
                )
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(OpenMusicEventBrowser.Tab.settings)

            NavigationStack {
                BrowseView(store: store.spawn(\.search), accountStore: accountStore)
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
                BrowseView(store: store.spawn(\.browse), accountStore: accountStore)
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
            .badge(store.myEventsNotificationIndicatorCount)

            NavigationStack {
                SettingsFeatureView(
                    store: store.scope(\.settings),
                    serviceEnvironment: serviceEnvironment,
                    isServiceEnvironmentSelectionEnabled: isServiceEnvironmentSelectionEnabled,
                    isServiceEnvironmentSwitching: isServiceEnvironmentSwitching,
                    serviceEnvironmentSelected: serviceEnvironmentSelected
                )
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(OpenMusicEventBrowser.Tab.settings)

            NavigationStack {
                BrowseView(store: store.spawn(\.search), accountStore: accountStore)
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
            events: [CalendarEvent] = [],
            referenceDate: Date = .distantPast
        ) {
            self.catalog = catalog
            self.events = events
            self.referenceDate = referenceDate
        }

        public var catalog: EventCatalog
        public var errorMessage: String?
        public var eventDetail: EventBrowseDetail.State?
        public var events: [CalendarEvent]
        public var isLoading = false
        @Trigger public var refresh
        public var referenceDate: Date
        public var searchText = ""
        public var selectedDay: CalendarEvent.Day?
        public var selectedMode: CalendarEvent.Mode?
        public var sort = Sort.soonest

        public var visibleEvents: [CalendarEvent] {
            let filteredEvents = events
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

            switch sort {
            case .name:
                return filteredEvents.sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            case .soonest:
                return filteredEvents.sorted(by: CalendarEvent.isSooner)
            }
        }

        public var happeningNowEvents: [CalendarEvent] {
            visibleEvents.filter { event in
                guard let startsAt = event.startsAt,
                      let endsAt = event.endsAt
                else { return false }
                return startsAt <= referenceDate && referenceDate <= endsAt
            }
        }

        public var upcomingEvents: [CalendarEvent] {
            visibleEvents.filter { event in
                guard let startsAt = event.startsAt else { return false }
                return startsAt > referenceDate
            }
        }

        public var pastEvents: [CalendarEvent] {
            visibleEvents.filter { event in
                guard let startsAt = event.startsAt else { return false }
                let lastInstant = event.endsAt ?? startsAt
                return lastInstant < referenceDate
            }
        }

        public var undatedEvents: [CalendarEvent] {
            visibleEvents.filter { $0.startsAt == nil }
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
    @Dependency(\.date.now) var now

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
                state.referenceDate = now
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
                state.eventDetail = EventBrowseDetail.State(event: event)

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
        .onTrigger(store.refresh) { _ in
            store.addTask {
                try await store.send(.didPullToRefresh)?.value
            }
        }
        .ifLet(\.eventDetail) {
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
    let accountStore: StoreOf<Account>
    @State var isDatePickerPresented = false

    public init(store: StoreOf<Browse>, accountStore: StoreOf<Account>) {
        self.store = store
        self.accountStore = accountStore
    }

    public var body: some View {
        List {
            if let errorMessage = store.errorMessage {
                PortableContentUnavailableView(
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
            } else if let selectedDay = store.selectedDay {
                Section(selectedDay.formatted(in: .current)) {
                    browseEventRows(store.visibleEvents)
                }
            } else {
                Section("Happening Now") {
                    if store.happeningNowEvents.isEmpty {
                        Text("Nothing is happening right now.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        browseEventRows(store.happeningNowEvents)
                    }
                }

                if !store.upcomingEvents.isEmpty {
                    Section("Upcoming") {
                        browseEventRows(store.upcomingEvents)
                    }
                }

                if !store.undatedEvents.isEmpty {
                    Section("More Events") {
                        browseEventRows(store.undatedEvents)
                    }
                }

                if !store.pastEvents.isEmpty {
                    Section("Past Events") {
                        browseEventRows(store.pastEvents)
                    }
                }
            }
        }
        .navigationTitle("Browse")
        .navigationDestination(
            item: $store.scope(\.eventDetail)
        ) { detailStore in
            EventBrowseDetailView(store: detailStore)
        }
        .searchable(text: $store.searchText, prompt: "Search events or organizers")
        .refreshable {
            await store.send(.didPullToRefresh)?.value
        }
        .task {
            await store.send(.task)?.value
        }
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .automatic) {
                AccountPicker(store: accountStore)
            }
            #else
            ToolbarItem(placement: .topBarLeading) {
                AccountPicker(store: accountStore)
            }
            #endif
            ToolbarItemGroup {
                #if os(Android)
                AndroidBrowseDatePickerButton(
                    selectedDay: store.selectedDay,
                    daySelected: { store.send(.daySelected($0)) }
                )
                #else
                Button {
                    isDatePickerPresented = true
                } label: {
                    Label("Choose a date", systemImage: "calendar")
                }
                .popover(isPresented: $isDatePickerPresented) {
                    BrowseDatePicker(
                        selectedDay: store.selectedDay,
                        daySelected: { store.send(.daySelected($0)) }
                    )
                }
                #endif

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
                    Divider()
                    browseModeButton("All formats", mode: nil)
                    browseModeButton("In person", mode: .inPerson)
                    browseModeButton("Virtual", mode: .virtual)
                    browseModeButton("Hybrid", mode: .hybrid)
                    Divider()
                    browseSortButton("Soonest first", sort: .soonest)
                    browseSortButton("Name", sort: .name)
                } label: {
                    Label("Filter and sort", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    @ViewBuilder
    func browseEventRows(_ events: [CalendarEvent]) -> some View {
        ForEach(events) { event in
            Button {
                store.send(.browseEventButtonTapped(event.uri))
            } label: {
                BrowseCalendarEventRow(
                    event: event,
                    artworkSources: event.artworkSources
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(
                "button.browse-event.\(event.uri.rkey?.rawValue ?? "unknown")"
            )
        }
    }

    @ViewBuilder
    func browseModeButton(_ title: String, mode: CalendarEvent.Mode?) -> some View {
        Button {
            store.send(.modeSelected(mode))
        } label: {
            if store.selectedMode == mode {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    @ViewBuilder
    func browseSortButton(_ title: String, sort: Browse.Sort) -> some View {
        Button {
            store.send(.sortSelected(sort))
        } label: {
            if store.sort == sort {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

struct ActorCacheRequestingRow<Content: View>: View {
    let actorID: DID
    @Fetch var cachedActorIdentities: CachedActorIdentities
    @Dependency(\.blueskyActorProfileCache) var actorProfileCache
    @ViewBuilder var content: (ActorIdentity?) -> Content

    init(
        actorID: DID,
        @ViewBuilder content: @escaping (ActorIdentity?) -> Content
    ) {
        self.actorID = actorID
        self.content = content
        _cachedActorIdentities = Fetch(
            wrappedValue: CachedActorIdentities(),
            CachedActorIdentitiesRequest()
        )
    }

    var body: some View {
        content(cachedActorIdentities[actorID.description])
            .task(id: actorID) {
                do {
                    _ = try await actorProfileCache.refreshProfileIfNeeded(
                        actorID.description,
                        24 * 60 * 60,
                        15 * 60
                    )
                } catch is CancellationError {
                } catch {
                    reportIssue(error)
                }
            }
    }
}

struct OrganizerActorPresentation: Equatable {
    let avatarURL: URL?
    let title: String

    init(
        organizer: CalendarEvent.Organizer,
        cachedIdentity: ActorIdentity?
    ) {
        self.avatarURL = organizer.avatarURL ?? cachedIdentity?.avatar
        self.title = Self.attendeeFacing(organizer.displayName)
            ?? Self.attendeeFacing(cachedIdentity?.displayName)
            ?? Self.attendeeFacing(organizer.handle)
            ?? Self.attendeeFacing(cachedIdentity?.handle?.rawValue)
            ?? "Organizer"
    }

    static func attendeeFacing(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        let lowercaseValue = value.lowercased()
        guard !lowercaseValue.hasPrefix("did:"),
              !lowercaseValue.hasPrefix("@did:")
        else { return nil }
        return value
    }
}

struct BrowseCalendarEventRow: View {
    let event: CalendarEvent
    let artworkSources: [HeroImageSource]

    var body: some View {
        ActorCacheRequestingRow(actorID: event.organizer.id) { cachedIdentity in
            let organizer = OrganizerActorPresentation(
                organizer: event.organizer,
                cachedIdentity: cachedIdentity
            )
            HStack(alignment: .top, spacing: 12) {
                BrowseEventArtwork(
                    event: event,
                    artworkSources: artworkSources,
                    size: 60
                )

                VStack(alignment: .leading, spacing: 4) {
                    if let dateText {
                        Text(dateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(event.name)
                        .font(.headline)
                    Text(organizer.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        }
    }

    var dateText: String? {
        guard let startsAt = event.startsAt else { return nil }
        if event.source.collection == OME.Event.nsid {
            let formatter = DateIntervalFormatter()
            formatter.timeZone = event.eventTimeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            if let endsAt = event.endsAt,
               event.localStartDay != CalendarEvent.Day(
                   endsAt,
                   timeZone: event.eventTimeZone
               ) {
                return formatter.string(from: startsAt, to: endsAt)
            }
            return formatter.string(from: startsAt, to: startsAt)
        } else {
            let formatter = DateFormatter()
            formatter.timeZone = event.eventTimeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: startsAt)
        }
    }
}

struct BrowseEventArtwork: View {
    let event: CalendarEvent
    let artworkSources: [HeroImageSource]
    let size: ImageFocusCGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(0.12))

            BrowseEventArtworkSourceChain<BrowseEventArtworkPlaceholder>(
                sources: artworkSources[...],
                renderedImageSize: ImageFocusCGSize(width: size, height: size)
            ) {
                BrowseEventArtworkPlaceholder()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(Text(event.name))
    }
}

struct BrowseEventArtworkPlaceholder: View {
    var body: some View {
        MappedSystemImage(systemName: "music.note")
            .frame(width: 18, height: 18)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

struct BrowseEventArtworkSourceChain<Placeholder: View>: View {
    let sources: ArraySlice<HeroImageSource>
    let renderedImageSize: ImageFocusCGSize
    @ViewBuilder var placeholder: () -> Placeholder

    @ViewBuilder
    var body: some View {
        if let source = sources.first {
            switch source.kind {
            case .primaryImage:
                ImageAssetAsyncImage(
                    image: source.image,
                    contentMode: .fill,
                    renderedImageSize: renderedImageSize
                ) { reason in
                    fallback(for: reason)
                }

            case .logo:
                ImageAssetAsyncImage(
                    image: source.image,
                    contentMode: .fit,
                    renderedImageSize: renderedImageSize
                ) { reason in
                    fallback(for: reason)
                }
                .padding(10)
            }
        } else {
            placeholder()
        }
    }

    @ViewBuilder
    private func fallback(for reason: ImageAssetPlaceholderReason) -> some View {
        switch reason {
        case .loading:
            Color.clear
        case .failure, .unavailable:
            BrowseEventArtworkSourceChain(
                sources: sources.dropFirst(),
                renderedImageSize: renderedImageSize,
                placeholder: placeholder
            )
        }
    }
}

extension CalendarEvent {
    var artworkSources: [HeroImageSource] {
        artworkSources(orderedMedia: semanticallyOrderedMedia)
    }

    var organizationArtworkSources: [HeroImageSource] {
        artworkSources(orderedMedia: organizationOrderedMedia)
    }

    func artworkSources(orderedMedia: [Media]) -> [HeroImageSource] {
        var seenURLs = Set<URL>()
        var sources = orderedMedia.compactMap { media -> HeroImageSource? in
            guard seenURLs.insert(media.url).inserted else { return nil }
            return media.artworkSource
        }
        if let avatarURL = organizer.avatarURL,
           seenURLs.insert(avatarURL).inserted {
            sources.append(
                .logo(
                    DisplayImageAsset(
                        asset: OME.ImageAsset(
                            source: .url(avatarURL),
                            role: .logo,
                            renderKind: .transparent,
                            materializationPolicy: .lazy
                        )
                    )
                )
            )
        }
        return sources
    }

    var semanticallyOrderedMedia: [Media] {
        media.enumerated()
            .filter { $0.element.normalizedRole != "sitemap" }
            .sorted { lhs, rhs in
                let lhsPriority = lhs.element.artworkPriority
                let rhsPriority = rhs.element.artworkPriority
                return lhsPriority == rhsPriority
                    ? lhs.offset < rhs.offset
                    : lhsPriority < rhsPriority
            }
            .map(\.element)
    }

    var organizationOrderedMedia: [Media] {
        media.enumerated()
            .filter { $0.element.normalizedRole != "sitemap" }
            .sorted { lhs, rhs in
                let lhsPriority = lhs.element.organizationArtworkPriority
                let rhsPriority = rhs.element.organizationArtworkPriority
                return lhsPriority == rhsPriority
                    ? lhs.offset < rhs.offset
                    : lhsPriority < rhsPriority
            }
            .map(\.element)
    }
}

private extension CalendarEvent.Media {
    var normalizedRole: String? {
        guard let role else { return nil }
        return role
            .split(separator: "#")
            .last
            .map(String.init)?
            .lowercased()
    }

    var artworkPriority: Int {
        switch normalizedRole {
        case "poster": 0
        case "hero": 1
        case "photo": 2
        case nil: 3
        case "icon": 4
        case "logo": 5
        default: 3
        }
    }

    var organizationArtworkPriority: Int {
        switch normalizedRole {
        case "icon", "logo": 0
        case "poster": 1
        case "hero": 2
        case "photo": 3
        default: 4
        }
    }

    var artworkSource: HeroImageSource {
        let role: OME.ImageAsset.Role
        let renderKind: OME.ImageAsset.RenderKind
        let kind: HeroImageSource.Kind
        switch normalizedRole {
        case "poster":
            role = .poster
            renderKind = .fullImage
            kind = .primaryImage
        case "hero":
            role = .hero
            renderKind = .fullImage
            kind = .primaryImage
        case "icon":
            role = .icon
            renderKind = .transparent
            kind = .logo
        case "logo":
            role = .logo
            renderKind = .transparent
            kind = .logo
        default:
            role = .photo
            renderKind = .fullImage
            kind = .primaryImage
        }
        return HeroImageSource(
            kind,
            image: DisplayImageAsset(
                asset: OME.ImageAsset(
                    source: .url(url),
                    role: role,
                    renderKind: renderKind,
                    materializationPolicy: .lazy
                )
            )
        )
    }
}

#if os(Android)
struct AndroidBrowseDatePickerButton: View {
    @Dependency(\.date.now) var now
    let selectedDay: CalendarEvent.Day?
    let daySelected: (CalendarEvent.Day?) -> Void

    var body: some View {
        ComposeView {
            AndroidBrowseDatePickerComposer(
                selectedDate: selectedDay?.date(in: .current) ?? now,
                dateSelected: { date in
                    daySelected(CalendarEvent.Day(date, timeZone: .current))
                },
                allDatesSelected: {
                    daySelected(nil)
                }
            )
        }
    }
}
#endif

#if SKIP
struct AndroidBrowseDatePickerComposer: ContentComposer {
    let selectedDate: Date
    let dateSelected: (Date) -> Void
    let allDatesSelected: () -> Void

    init(
        selectedDate: Date,
        dateSelected: @escaping (Date) -> Void,
        allDatesSelected: @escaping () -> Void
    ) {
        self.selectedDate = selectedDate
        self.dateSelected = dateSelected
        self.allDatesSelected = allDatesSelected
    }

    // SKIP INSERT: @OptIn(ExperimentalMaterial3Api::class)
    @Composable func Compose(context: ComposeContext) {
        let isPresented = remember { mutableStateOf(false) }

        androidx.compose.material3.IconButton(
            onClick: { isPresented.value = true },
            modifier: context.modifier
        ) {
            androidx.compose.material3.Icon(
                imageVector: Icons.Outlined.DateRange,
                contentDescription: "Choose a date"
            )
        }

        guard isPresented.value else { return }

        let timeZone = TimeZone.current
        let pickerState = androidx.compose.material3.rememberDatePickerState(
            initialSelectedDateMillis: datePickerMillis(
                from: selectedDate,
                timeZone: timeZone
            )
        )
        androidx.compose.material3.DatePickerDialog(
            onDismissRequest: { isPresented.value = false },
            confirmButton: {
                androidx.compose.material3.TextButton(
                    onClick: {
                        if let millis = pickerState.selectedDateMillis {
                            dateSelected(
                                date(
                                    fromDatePickerMillis: millis,
                                    timeZone: timeZone
                                )
                            )
                        }
                        isPresented.value = false
                    }
                ) {
                    androidx.compose.material3.Text("Done")
                }
            },
            dismissButton: {
                androidx.compose.material3.TextButton(
                    onClick: {
                        allDatesSelected()
                        isPresented.value = false
                    }
                ) {
                    androidx.compose.material3.Text("All Dates")
                }
            }
        ) {
            androidx.compose.material3.DatePicker(state: pickerState)
        }
    }

    private func datePickerMillis(from date: Date, timeZone: TimeZone) -> Long {
        let timeZoneOffset = Double(timeZone.secondsFromGMT(for: date))
        return Long((date.timeIntervalSince1970 + timeZoneOffset) * 1_000)
    }

    private func date(fromDatePickerMillis millis: Long, timeZone: TimeZone) -> Date {
        let utcDate = Date(timeIntervalSince1970: Double(millis) / 1_000)
        let timeZoneOffset = Double(timeZone.secondsFromGMT(for: utcDate))
        return Date(
            timeIntervalSince1970: utcDate.timeIntervalSince1970 - timeZoneOffset
        )
    }
}
#endif

enum BrowseDatePickerConversion {
    static func datePickerMilliseconds(
        from date: Date,
        timeZone: TimeZone
    ) -> Double {
        let timeZoneOffset = Double(timeZone.secondsFromGMT(for: date))
        return (date.timeIntervalSince1970 + timeZoneOffset) * 1_000
    }

    static func date(
        fromDatePickerMilliseconds milliseconds: Double,
        timeZone: TimeZone
    ) -> Date {
        let utcDate = Date(timeIntervalSince1970: milliseconds / 1_000)
        let timeZoneOffset = Double(timeZone.secondsFromGMT(for: utcDate))
        return Date(
            timeIntervalSince1970: utcDate.timeIntervalSince1970 - timeZoneOffset
        )
    }
}

struct BrowseDatePicker: View {
    @Environment(\.dismiss) var dismiss
    @State var selection: Date
    let daySelected: (CalendarEvent.Day?) -> Void

    init(
        selectedDay: CalendarEvent.Day?,
        daySelected: @escaping (CalendarEvent.Day?) -> Void
    ) {
        @Dependency(\.date.now) var now
        _selection = State(
            initialValue: selectedDay?.date(in: .current) ?? now
        )
        self.daySelected = daySelected
    }

    var body: some View {
        VStack(spacing: 12) {
            #if os(Android)
            DatePicker("Date", selection: $selection, displayedComponents: .date)
            #else
            DatePicker("Date", selection: $selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
            #endif
            HStack {
                Button("All Dates") {
                    daySelected(nil)
                    dismiss()
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 320)
        .onChange(of: selection) { _, selection in
            daySelected(CalendarEvent.Day(selection, timeZone: .current))
        }
    }
}

extension CalendarEvent.Day {
    func date(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(
            from: DateComponents(
                timeZone: timeZone,
                year: year,
                month: month,
                day: day
            )
        )!
    }

    func formatted(in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date(in: timeZone))
    }
}

@Feature
public struct EventBrowseDetail {
    public init() {}

    public struct State: Identifiable {
        public init(event: CalendarEvent) {
            self.event = event
            _record = FetchOne(Event.find(event.uri))
        }

        @FetchOne public var record: Event?
        public var eventInfoForm: EditEventInfo.State?
        public var title: String { record?.name ?? event.name }
        public var eventDescription: String? {
            if let record { return record.description }
            return event.description
        }

        public var locationText: String? {
            if let record { return record.locations?.first?.name }
            return event.locations.first?.summary
        }

        public var links: [CalendarEvent.Link] {
            if let record {
                return (record.links ?? []).map {
                    CalendarEvent.Link(name: $0.title, uri: $0.url)
                }
            }
            return event.links
        }

        public var artworkSources: [HeroImageSource] {
            record?.heroImageSources ?? event.artworkSources
        }

        public var artworkTitleSources: [HeroImageTitleSource] {
            record?.heroImageTitleSources ?? [.title]
        }

        public var dateText: String? {
            guard let record else { return event.detailDateText }
            let formatter = DateFormatter()
            formatter.timeZone = record.timeZone
            formatter.dateStyle = .long
            func text(_ boundary: Open<Event.Time>?) -> String? {
                guard let boundary, let date = boundary.date(in: record.timeZone) else { return nil }
                if case .known(.time) = boundary {
                    formatter.timeStyle = .short
                } else {
                    formatter.timeStyle = .none
                }
                return formatter.string(from: date)
            }
            return [text(record.start), text(record.end)].compactMap { $0 }.joined(separator: " – ")
        }

        public var errorMessage: String?
        public var event: CalendarEvent
        public var isEnteringEvent = false
        public var isSavingRSVP = false
        public var organizationDetail: OrganizationDetail.State?
        public var rsvpStatus: OME.RSVP.Status?

        public var id: ATProto.URI { event.uri }
    }

    public enum Action {
        case enterEventButtonTapped
        case editButtonTapped
        case eventInfoForm(EditEventInfo.Action)
        case organizationDetail(OrganizationDetail.Action)
        case organizerButtonTapped
        case rsvpButtonTapped(OME.RSVP.Status)
        case task
    }

    @Dependency(\.date.now) var now
    @Dependency(\.calendarEvents) var calendarEvents
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.getSelectedOAuthSessionID) var selectedAccountID
    @Dependency(\.omeEventInstallation) var eventInstallation
    @Dependency(\.eventRecords) var eventRecords

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .editButtonTapped:
                guard let record = state.record else { return }
                state.eventInfoForm = EditEventInfo.State(event: record)

            case .eventInfoForm:
                break

            case .enterEventButtonTapped:
                let eventURI = state.event.uri
                state.errorMessage = nil
                state.isEnteringEvent = true
                store.addTask {
                    let _: Void? = await store.withErrorHandling(
                        fallbackMessage: .eventInstallationFailed,
                        operation: .eventInstallation
                    ) {
                        let eventID = try await eventInstallation.ensureInstalled(eventURI)
                        try store.modify {
                            $0.isEnteringEvent = false
                        }
                        try store.post(
                            key: NavigationRequested.self,
                            value: .event(eventID, nil)
                        )
                    } cleanup: {
                        $0.isEnteringEvent = false
                    }
                }

            case .organizerButtonTapped:
                state.organizationDetail = OrganizationDetail.State(
                    organizerID: state.event.organizer.id,
                    collection: state.event.source.collection
                )

            case .organizationDetail:
                return

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
                state.errorMessage = nil
                let eventURI = state.event.uri
                let consumer = EventRSVP.Consumer(
                    accountDID: selectedAccountID()?.rawValue
                )
                store.addTask {
                    do {
                        if eventURI.collection == ATProto.NSID(Event.lexiconID.rawValue) {
                            let exists = try await database.read { db in
                                try Event.find(eventURI).fetchOne(db) != nil
                            }
                            if !exists {
                                let graph = try await eventRecords.load(eventURI)
                                guard graph.event.id == eventURI else {
                                    throw ValidationError("The downloaded event has a different record ID")
                                }
                                try Task.checkCancellation()
                                try await database.write { db in
                                    guard try Event.find(eventURI).fetchOne(db) == nil else { return }
                                    try graph.upsert(in: db)
                                }
                            }
                        } else {
                            let event = try await calendarEvents.event(eventURI)
                            try store.modify { $0.event = event }
                        }
                        let record = try await database.read { db in
                            try EventRSVP.forEvent(eventURI, consumer: consumer).fetchOne(db)
                        }
                        try store.modify {
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
        .ifLet(\.eventInfoForm) {
            EditEventInfo()
        }
        .ifLet(\.organizationDetail) {
            OrganizationDetail()
        }
    }
}

public struct EventBrowseDetailView: View {
    @Bindable var store: StoreOf<EventBrowseDetail>

    public init(store: StoreOf<EventBrowseDetail>) {
        self.store = store
    }

    public var body: some View {
        HeroImageList(
            title: Text(store.title)
        ) {
            HeroImage(
                title: Text(store.title),
                sources: store.artworkSources,
                titleSources: store.artworkTitleSources
            ) {
                MappedSystemImage(systemName: "music.note")
                    .frame(width: 56, height: 56)
            } chromeTrailingContent: {
                if store.event.source.collection == OME.Event.nsid {
                    Button {
                        store.send(.enterEventButtonTapped)
                    } label: {
                        HStack(spacing: 8) {
                            if store.isEnteringEvent {
                                ProgressView()
                            }
                            Text(store.isEnteringEvent ? "Entering…" : "Enter Event")
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isEnteringEvent)
                    .accessibilityIdentifier(
                        "button.enter-event.\(store.event.uri.rkey?.rawValue ?? "unknown")"
                    )
                }
            }
        } content: {
            Section {
                Button {
                    store.send(.organizerButtonTapped)
                } label: {
                    EventOrganizerRow(organizer: store.event.organizer)
                }
                .navigationLinkListRowStyle()

                if let dateText = store.dateText, !dateText.isEmpty {
                    LabeledContent("Date") {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(dateText)

                            if store.record == nil, let timeText = store.event.detailTimeText {
                                Text(timeText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let location = store.locationText {
                    LabeledContent("Location", value: location)
                }
//
//                HStack(spacing: 12) {
//                    VStack(alignment: .leading, spacing: 3) {
//                        Text("RSVP")
//
//                        if let status = store.rsvpStatus {
//                            Text(status.eventBrowseTitle)
//                                .font(.caption)
//                                .foregroundStyle(.secondary)
//                        }
//                    }
//
//                    Spacer()
//
//                    Menu {
//                        RSVPStatusButton(
//                            title: "Going",
//                            status: .going,
//                            selectedStatus: store.rsvpStatus,
//                            disabled: store.isSavingRSVP
//                        ) {
//                            store.send(.rsvpButtonTapped(.going))
//                        }
//                        RSVPStatusButton(
//                            title: "Interested",
//                            status: .interested,
//                            selectedStatus: store.rsvpStatus,
//                            disabled: store.isSavingRSVP
//                        ) {
//                            store.send(.rsvpButtonTapped(.interested))
//                        }
//                        RSVPStatusButton(
//                            title: "Not Going",
//                            status: .notGoing,
//                            selectedStatus: store.rsvpStatus,
//                            disabled: store.isSavingRSVP
//                        ) {
//                            store.send(.rsvpButtonTapped(.notGoing))
//                        }
//                    } label: {
//                        HStack(spacing: 6) {
//                            if store.isSavingRSVP {
//                                ProgressView()
//                            }
//                            Text("RSVP")
//                            MappedSystemImage(systemName: "ellipsis")
//                                .frame(width: 20, height: 20)
//                        }
//                    }
//                    .buttonStyle(.bordered)
//                    .disabled(store.isSavingRSVP)
//                }

                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if let description = store.eventDescription, !description.isEmpty {
                Section("About") {
                    Text(description)
                }
            }

            if !store.links.isEmpty {
                Section("Links") {
                    ForEach(Array(store.links.enumerated()), id: \.offset) { _, link in
                        Link(link.name ?? link.uri.host() ?? "Event link", destination: link.uri)
                    }
                }
            }
        }
        .toolbar {
            if store.record != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.editButtonTapped)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("button.edit-event")
                }
            }
        }
        .sheet(item: $store.scope(\.eventInfoForm)) { formStore in
            NavigationStack {
                EditEventInfoView(store: formStore)
            }
        }
        .navigationDestination(
            item: $store.scope(\.organizationDetail)
        ) { organizationStore in
            OrganizationDetailView(store: organizationStore)
        }
        .task {
            await store.send(.task)?.value
        }
        .accessibilityIdentifier(
            "view.event-browse-detail.\(store.event.uri.rkey?.rawValue ?? "unknown")"
        )
    }
}

private extension CalendarEvent {
    var detailDateText: String? {
        switch (startsAt, endsAt) {
        case let (.some(startsAt), .some(endsAt)):
            let formatter = DateIntervalFormatter()
            formatter.timeZone = eventTimeZone
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            return formatter.string(from: startsAt, to: endsAt)

        case let (.some(startsAt), .none):
            return detailDateFormatter.string(from: startsAt)

        case let (.none, .some(endsAt)):
            return detailDateFormatter.string(from: endsAt)

        case (.none, .none):
            return nil
        }
    }

    var detailTimeText: String? {
        guard !detailRangeCoversWholeDays else { return nil }

        switch (startsAt, endsAt) {
        case let (.some(startsAt), .some(endsAt)):
            let formatter = DateIntervalFormatter()
            formatter.timeZone = eventTimeZone
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: startsAt, to: endsAt)

        case let (.some(startsAt), .none):
            return detailTimeFormatter.string(from: startsAt)

        case let (.none, .some(endsAt)):
            return detailTimeFormatter.string(from: endsAt)

        case (.none, .none):
            return nil
        }
    }

    var detailRangeCoversWholeDays: Bool {
        guard let startsAt, let endsAt else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eventTimeZone
        let start = calendar.dateComponents([.hour, .minute, .second], from: startsAt)
        let end = calendar.dateComponents([.hour, .minute, .second], from: endsAt)
        return start.hour == 0
            && start.minute == 0
            && start.second == 0
            && end.hour == 23
            && end.minute == 59
            && end.second == 59
    }

    var detailDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = eventTimeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }

    var detailTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = eventTimeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
}

private extension OME.RSVP.Status {
    var eventBrowseTitle: String {
        switch self {
        case .going:
            "Going"
        case .interested:
            "Interested"
        case .notGoing:
            "Not Going"
        }
    }
}

struct EventOrganizerRow: View {
    let organizer: CalendarEvent.Organizer

    var body: some View {
        ActorCacheRequestingRow(actorID: organizer.id) { cachedIdentity in
            let presentation = OrganizerActorPresentation(
                organizer: organizer,
                cachedIdentity: cachedIdentity
            )
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.secondary.opacity(0.12))

                    CachedRemoteImage(
                        url: presentation.avatarURL,
                        targetSize: CGSize(width: 60, height: 60)
                    ) { phase in
                        switch phase {
                        case let .success(image, _):
                            image
                                .resizable()
                                .scaledToFill()

                        case .empty, .failure, .unavailable:
                            MappedSystemImage(systemName: "person")
                                .foregroundStyle(.secondary)
                                .padding(16)
                        }
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                        .lineLimit(1)

                    Text("Organizer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
        .ifLet(\.organizerDetail) {
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
        .navigationDestination(item: $store.scope(\.organizerDetail)) { detailStore in
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
        case calendarButtonTapped(OMERecord.Calendar.ID)
        case calendarDetail(CalendarDetail.Action)
        case eventButtonTapped(OMERecord.Event.ID)
        case task
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
            case .calendarButtonTapped(let calendarID):
                store.withDependencies {
                    state.calendarDetail = .init(calendarID: calendarID)
                }

            case .calendarDetail:
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
        .ifLet(\.calendarDetail) {
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
        .navigationDestination(item: $store.scope(\.calendarDetail)) { detailStore in
            CalendarDetailView(store: detailStore)
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

struct PortableContentUnavailableView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: Text

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        description: Text
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        #if os(Android)
        VStack(alignment: .center, spacing: 12) {
            MappedSystemImage(systemName: systemImage)
                .frame(width: 32, height: 32)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            description
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowBackground(Color.clear)
        #else
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: description
        )
        #endif
    }
}
