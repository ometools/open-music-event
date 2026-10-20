import HeroImageList
import ATProto
import ATProtoTypes
import Bluesky
import ComposableArchitecture2
import ComposableCalendarEvents
import Dependencies
import ErrorHandling
import Foundation
import IssueReporting
import OpenMusicEventAppEventViewer
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventLexicon
import OpenMusicEventAuthentication
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
        public init() {}

        public var catalogs = EventCatalog.allCases
        public var dateScope = DateScope.current
        public var errorMessage: String?
        public var eventDetail: EventBrowseDetail.State?
        public var events: [OME.CalendarEvent.Summary] = []
        public var cursor: String?
        public var evaluatedAt: Date?
        public var isLoading = false
        public var isLoadingMore = false
        public var hasLoaded = false
        public var moreError: String?
        public var publisherSelection: EventBrowseClient.PublisherSelection?
        public var requestGeneration = 0
        @Trigger public var refresh
        public var searchText = ""
    }

    public enum DateScope: String, CaseIterable, Identifiable, Sendable {
        case current, all
        public var id: Self { self }
        public var title: String {
            switch self {
            case .current: "Current and upcoming"
            case .all: "All dates"
            }
        }
    }

    public enum Action {
        case catalogToggled(EventCatalog)
        case browseEventButtonTapped(String)
        case dateScopeSelected(DateScope)
        case didPullToRefresh
        case eventDetail(EventBrowseDetail.Action)
        case loadMoreButtonTapped
        case searchTextChanged(String)
        case task
    }

    @Dependency(\.eventBrowse) var eventBrowse
    @Dependency(\.continuousClock) var clock
    @StoreTaskID var browseRequest

    public var body: some Feature {
        Update { state, action in
            let loadMore: Bool
            let debounce: Bool
            switch action {
            case let .browseEventButtonTapped(uri):
                guard let summary = state.events.first(where: { $0.uri == uri }) else { return }
                do {
                    state.eventDetail = try EventBrowseDetail.State(event: summary.browsePreview())
                } catch {
                    state.errorMessage = "Unable to open this event. Please refresh and try again."
                }
                return

            case .eventDetail:
                return

            case let .catalogToggled(catalog):
                if state.catalogs.contains(catalog) {
                    state.catalogs.removeAll { $0 == catalog }
                } else {
                    state.catalogs.append(catalog)
                }
                loadMore = false
                debounce = false

            case let .dateScopeSelected(scope):
                guard state.dateScope != scope else { return }
                state.dateScope = scope
                loadMore = false
                debounce = false

            case let .searchTextChanged(text):
                let text = String(text.prefix(256))
                guard state.searchText != text else { return }
                state.searchText = text
                loadMore = false
                debounce = !text.isEmpty

            case .loadMoreButtonTapped:
                guard !state.isLoading, !state.isLoadingMore, state.cursor != nil else { return }
                loadMore = true
                debounce = false

            case .task:
                guard !state.hasLoaded, !state.isLoading else { return }
                loadMore = false
                debounce = false

            case .didPullToRefresh:
                loadMore = false
                debounce = false
            }

            state.errorMessage = nil
            state.moreError = nil
            if loadMore {
                state.isLoadingMore = true
            } else {
                state.requestGeneration += 1
                state.events = []
                state.cursor = nil
                state.evaluatedAt = nil
                state.isLoading = !state.catalogs.isEmpty
                state.isLoadingMore = false
                state.hasLoaded = false
            }
            guard !state.catalogs.isEmpty else { return }
            let generation = state.requestGeneration
            let selection = state.publisherSelection
            let query = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let parameters = OME.CalendarEvent.BrowseSummaries.Parameters(
                catalogs: state.catalogs.map(\.collection), query: query.isEmpty ? nil : query,
                cursor: state.cursor, limit: 50, dates: state.dateScope.rawValue
            )
            store.addTask(id: browseRequest) {
                do {
                    if debounce { try await clock.sleep(for: .milliseconds(300)) }
                    guard store.requestGeneration == generation else { return }
                    let publishers: EventBrowseClient.PublisherSelection
                    if let selection {
                        publishers = selection
                    } else {
                        publishers = try await eventBrowse.defaults()
                    }
                    guard store.requestGeneration == generation else { return }
                    var request = parameters
                    request.publisherMode = publishers.mode
                    request.publishers = publishers.publishers
                    let page = try await eventBrowse.browse(request)
                    try store.modify {
                        guard $0.requestGeneration == generation else { return }
                        $0.publisherSelection = publishers
                        // Retries and adjacent pages may overlap; preserve the AppView's order.
                        var seen = Set($0.events.map(\.uri))
                        $0.events.append(contentsOf: page.events.filter { seen.insert($0.uri).inserted })
                        $0.cursor = page.hasMore ? page.cursor : nil
                        $0.evaluatedAt = page.evaluatedAt
                        $0.isLoading = false
                        $0.isLoadingMore = false
                        $0.hasLoaded = true
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try store.modify {
                        guard $0.requestGeneration == generation else { return }
                        if loadMore {
                            $0.moreError = "Unable to load more events. Try again."
                        } else {
                            $0.errorMessage = "Unable to load events. Pull to refresh and try again."
                        }
                        $0.isLoading = false
                        $0.isLoadingMore = false
                    }
                }
            }
        }
        .onTrigger(store.refresh) { _ in
            store.addTask { try await store.send(.didPullToRefresh)?.value }
        }
        .ifLet(\.eventDetail) { EventBrowseDetail() }
    }
}

public enum EventCatalog: String, CaseIterable, Equatable, Identifiable, Sendable {
    case openMusicEvent
    case communityCalendar

    public var id: Self { self }

    public var collection: ATProto.NSID {
        switch self {
        case .openMusicEvent:
            ATProto.NSID(Event.lexiconID.rawValue)
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

    public init(store: StoreOf<Browse>, accountStore: StoreOf<Account>) {
        self.store = store
        self.accountStore = accountStore
    }

    public var body: some View {
        List {
            if let errorMessage = store.errorMessage {
                PortableContentUnavailableView(
                    "Events Unavailable", systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if store.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading events")
                    Spacer()
                }
            } else if store.events.isEmpty {
                EmptyBrowserState(
                    title: "No Events", systemImage: "calendar",
                    message: store.catalogs.isEmpty
                        ? "Choose a catalog in Filters to browse events."
                        : "No events match the current browse selection."
                )
            } else {
                ForEach(store.events) { event in
                    Button {
                        store.send(.browseEventButtonTapped(event.uri))
                    } label: {
                        BrowseSummaryRow(event: event)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("button.browse-event.\(event.uri.split(separator: "/").last ?? "unknown")")
                }
                if let moreError = store.moreError {
                    Text(moreError).foregroundStyle(.secondary)
                }
                if store.cursor != nil {
                    Button {
                        store.send(.loadMoreButtonTapped)
                    } label: {
                        HStack {
                            Text("Load more")
                            if store.isLoadingMore { ProgressView() }
                        }
                    }
                    .disabled(store.isLoadingMore)
                    .accessibilityIdentifier("button.browse-load-more")
                }
            }
        }
        .navigationTitle("Browse")
        .navigationDestination(item: $store.scope(\.eventDetail)) { detailStore in
            EventBrowseDetailView(store: detailStore)
        }
        .searchable(text: Binding(
            get: { store.searchText },
            set: { store.send(.searchTextChanged($0)) }
        ), prompt: "Events, artists, places")
        .refreshable { await store.send(.didPullToRefresh)?.value }
        .task { await store.send(.task)?.value }
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .automatic) { AccountPicker(store: accountStore) }
            #else
            ToolbarItem(placement: .topBarLeading) { AccountPicker(store: accountStore) }
            #endif
            ToolbarItem {
                Menu {
                    ForEach(EventCatalog.allCases) { catalog in
                        Button {
                            store.send(.catalogToggled(catalog))
                        } label: {
                            if store.catalogs.contains(catalog) {
                                Label(catalog.title, systemImage: "checkmark")
                            } else {
                                Text(catalog.title)
                            }
                        }
                        .accessibilityIdentifier("button.browse-catalog.\(catalog.rawValue)")
                    }
                    Divider()
                    ForEach(Browse.DateScope.allCases) { scope in
                        Button {
                            store.send(.dateScopeSelected(scope))
                        } label: {
                            if store.dateScope == scope {
                                Label(scope.title, systemImage: "checkmark")
                            } else {
                                Text(scope.title)
                            }
                        }
                        .accessibilityIdentifier("button.browse-dates.\(scope.rawValue)")
                    }
                } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("button.browse-filters")
            }
        }
    }
}

struct BrowseSummaryRow: View {
    let event: OME.CalendarEvent.Summary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CachedRemoteImage(url: event.markerMedia?.url, targetSize: .init(width: 60, height: 60)) { phase in
                if case let .success(image, _) = phase {
                    image.resizable()
                        .aspectRatio(contentMode: event.markerMedia?.renderKind == .transparent ? .fit : .fill)
                } else {
                    Image(systemName: "calendar").frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 60, height: 60)
            .clipped()
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.name).font(.headline)
                if let dateText { Text(dateText).font(.subheadline).foregroundStyle(.secondary) }
                if let location = event.locationSummary {
                    Text(location).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                if let publisher = event.publisherName {
                    HStack(spacing: 5) {
                        if let avatar = event.publisherAvatarURL.flatMap(URL.init(string:)) {
                            CachedRemoteImage(url: avatar, targetSize: .init(width: 16, height: 16)) { phase in
                                if case let .success(image, _) = phase { image.resizable().scaledToFill() }
                            }
                            .frame(width: 16, height: 16).clipShape(Circle()).accessibilityHidden(true)
                        }
                        Text(publisher).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    var dateText: String? {
        guard let startsAt = event.startsAt else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = event.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .gmt
        formatter.dateStyle = .medium
        formatter.timeStyle = event.dateOnly ? .none : .short
        let text = formatter.string(from: startsAt)
        return event.timeZoneIdentifier == nil && !event.dateOnly ? text + " UTC" : text
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
        if event.source.collection == ATProto.NSID(Event.lexiconID.rawValue) {
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
           seenURLs.insert(avatarURL).inserted,
           let image = OME.Image(
               source: .known(.url(avatarURL)),
               role: .known(.logo),
               renderingMode: .known(.template)
           ).displayImageAsset() {
            sources.append(
                .logo(image)
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

    var artworkSource: HeroImageSource? {
        let role: OME.Image.Role
        let renderingMode: OME.Image.RenderingMode
        let kind: HeroImageSource.Kind
        switch normalizedRole {
        case "poster":
            role = .poster
            renderingMode = .original
            kind = .primaryImage
        case "hero":
            role = .hero
            renderingMode = .original
            kind = .primaryImage
        case "icon":
            role = .icon(.init())
            renderingMode = .template
            kind = .logo
        case "logo":
            role = .logo
            renderingMode = .template
            kind = .logo
        default:
            role = .photo
            renderingMode = .original
            kind = .primaryImage
        }
        return OME.Image(
            source: .known(.url(url)),
            role: .known(role),
            renderingMode: .known(renderingMode)
        ).displayImageAsset().map { HeroImageSource(kind, image: $0) }
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
        public var eventInfoForm: EventForm.State?
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
            if let timeZone = record.timeZone,
               case let .known(.day(startDay)) = record.start,
               case let .known(.day(endDay)) = record.end {
                let formatter = DateIntervalFormatter()
                formatter.timeZone = timeZone
                formatter.dateStyle = .long
                formatter.timeStyle = .none
                return formatter.string(
                    from: startDay.value.atStartOfDay(in: timeZone),
                    to: endDay.value.atStartOfDay(in: timeZone)
                )
            }
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
        public var isSavingRSVP = false
        public var organizationDetail: OrganizationDetail.State?
        public var rsvpStatus: EventRSVP.Status?

        public var id: ATProto.URI { event.uri }
    }

    public enum Action {
        case enterEventButtonTapped
        case editButtonTapped
        case eventInfoForm(EventForm.Action)
        case organizationDetail(OrganizationDetail.Action)
        case organizerButtonTapped
        case rsvpButtonTapped(EventRSVP.Status)
        case task
    }

    @Dependency(\.date.now) var now
    @Dependency(\.eventBrowse) var eventBrowse
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.getSelectedOAuthSessionID) var selectedAccountID
    @Dependency(\.eventRecords) var eventRecords

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .editButtonTapped:
                guard let record = state.record else { return }
                state.eventInfoForm = EventForm.State(event: record)

            case .eventInfoForm:
                break

            case .enterEventButtonTapped:
                let eventURI = state.event.uri
                AttendeePerformance.mark("enter.begin", event: eventURI.description)
                state.errorMessage = nil
                store.addTask {
                    AttendeePerformance.mark("navigation.begin", event: eventURI.description)
                    try store.post(key: NavigationRequested.self, value: .event(eventURI, nil))
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
                let advertisedCID = state.event.cid
                let consumer = EventRSVP.Consumer(
                    accountDID: selectedAccountID()?.rawValue
                )
                store.addTask {
                    do {
                        if eventURI.collection == ATProto.NSID(Event.lexiconID.rawValue) {
                            let cached = try await database.read { db in
                                try Event.find(eventURI).fetchOne(db)
                            }
                            if let cached, advertisedCID == nil || cached.cid != advertisedCID,
                               consumer.accountDID == nil {
                                let locallyAuthored = try await database.read { db in
                                    try CanonicalSourceEventIdentity.find(eventURI).fetchOne(db) != nil
                                        || LocallyCreatedEvent.find(eventURI).fetchOne(db) != nil
                                }
                                if !locallyAuthored {
                                    let latest = try await eventRecords.latestEvent(eventURI)
                                    try latest.validateReferences()
                                    guard latest.id == eventURI else {
                                        throw ValidationError("The AppView returned a different Event")
                                    }
                                    try Task.checkCancellation()
                                    try await database.write { db in
                                        // A form save or source import during the request owns its local changes.
                                        guard try CanonicalSourceEventIdentity.find(eventURI).fetchOne(db) == nil,
                                              try LocallyCreatedEvent.find(eventURI).fetchOne(db) == nil,
                                              try Event.find(eventURI).fetchOne(db) == cached else { return }
                                        try Event.upsert { latest }.execute(db)
                                    }
                                }
                            } else if cached == nil {
                                let event = try await eventRecords.latestEvent(eventURI)
                                guard event.id == eventURI else {
                                    throw ValidationError("The downloaded event has a different record ID")
                                }
                                try Task.checkCancellation()
                                try await database.write { db in
                                    guard try Event.find(eventURI).fetchOne(db) == nil else { return }
                                    try Event.upsert { event }.execute(db)
                                }
                            }
                        } else {
                            let event = try await eventBrowse.event(eventURI)
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
            EventForm()
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
                if store.event.source.collection == ATProto.NSID(Event.lexiconID.rawValue) {
                    Button {
                        store.send(.enterEventButtonTapped)
                    } label: {
                        HStack(spacing: 8) {
                            Text("Enter Event")
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.borderedProminent)
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
                EventFormView(store: formStore)
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

private extension EventRSVP.Status {
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
    let status: EventRSVP.Status
    let selectedStatus: EventRSVP.Status?
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
        public var organizationDetail: OrganizationDetail.State?

    }

    public enum Action {
        case didPullToRefresh
        case followedOrganizersResponse([FollowedOrganizerRow])
        case organizationDetail(OrganizationDetail.Action)
        case organizerRowTapped(DID)
        case task
        case toggleFollowButtonTapped(DID)
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .organizerRowTapped(let organizerID):
                store.withDependencies {
                    state.organizationDetail = .init(organizerID: organizerID)
                }

            case .didPullToRefresh,
                 .followedOrganizersResponse,
                 .organizationDetail,
                 .task,
                 .toggleFollowButtonTapped:
                break
            }
        }
        .ifLet(\.organizationDetail) {
            OrganizationDetail()
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
        .navigationDestination(item: $store.scope(\.organizationDetail)) { detailStore in
            OrganizationDetailView(store: detailStore)
        }
    }
}

public struct FollowedOrganizerRow: Equatable, Identifiable, Sendable {
    public let organizerID: DID
    public let eventCount: Int

    public init(organizerID: DID, eventCount: Int) {
        self.organizerID = organizerID
        self.eventCount = eventCount
    }

    public var id: DID { organizerID }
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
