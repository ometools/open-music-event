import ComposableArchitecture2
import Foundation
import SwiftUI
import Tagged
import SQLiteData

@Feature
public struct OpenMusicEventBrowser {
    public init() {}

    public enum Tab: Hashable {
        case browse
        case following
        case myEvents
        case search
    }

    public struct State {
        public init() {}

        public var selectedTab: Tab = .myEvents
        public var browse = Spawn(Browse.State())
        public var eventPlaceholder: EventPlaceholder.State?
        public var following = Spawn(Following.State())
        public var search = Spawn(Search.State())
        public var myEvents = Spawn(MyEvents.State())
    }

    public enum Action {
        case browse(Browse.Action)
        case eventPlaceholder(EventPlaceholder.Action)
        case eventPlaceholderDismissed
        case following(Following.Action)
        case restoredSelectedEventID(OMERecord.Event.ID?)
        case search(Search.Action)
        case task
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .browse(.eventButtonTapped(let eventID)),
                 .following(.eventButtonTapped(let eventID)),
                 .following(.organizerDetail(.eventButtonTapped(let eventID))),
                 .search(.eventButtonTapped(let eventID)):
                state.eventPlaceholder = .init(eventID: eventID)

            case .eventPlaceholder(.closeButtonTapped), .eventPlaceholderDismissed:
                state.eventPlaceholder = nil

            case .restoredSelectedEventID(let eventID):
                state.eventPlaceholder = eventID.map(EventPlaceholder.State.init(eventID:))

            case .task:
                break

            case .browse, .eventPlaceholder, .following, .search:
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
        .spawn(\.myEvents) { MyEvents() }
        .ifLet(\.eventPlaceholder, action: \.eventPlaceholder) {
            EventPlaceholder()
        }
    }
}

public struct OpenMusicEventBrowserView: View {
    public init(store: StoreOf<OpenMusicEventBrowser>) {
        self.store = store
    }

    @Bindable var store: StoreOf<OpenMusicEventBrowser>

    public var body: some View {
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
                Label("my Events", systemImage: "star")
            }
            .tag(OpenMusicEventBrowser.Tab.myEvents)

            NavigationStack {
                SearchView(store: store.spawn(\.search))
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(OpenMusicEventBrowser.Tab.search)
        }
        .task {
            await store.send(.task)?.value
        }
        .fullScreenCover(
            item: $store.scope(state: \.eventPlaceholder, action: \.eventPlaceholder),
            onDismiss: {
                store.send(.eventPlaceholderDismissed)
            }
        ) { placeholderStore in
            NavigationStack {
                EventPlaceholderView(store: placeholderStore)
            }
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
        Update { _, _ in
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
                state.organizerDetail = .init(organizerID: organizerID)

            case .didPullToRefresh,
                 .eventButtonTapped,
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
        .navigationDestination(item: $store.scope(state: \.organizerDetail, action: \.organizerDetail)) { detailStore in
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
        }

        public let organizerID: OMERecord.Organizer.ID
        public var events: [BrowseEventRow] = []
        public var isFollowing = true
        public var isLoading = false

        public var id: OMERecord.Organizer.ID { organizerID }
    }

    public enum Action {
        case eventButtonTapped(OMERecord.Event.ID)
        case followStateResponse(Bool)
        case organizerDetailResponse([BrowseEventRow], Bool)
        case task
        case toggleFollowButtonTapped
    }

    public var body: some Feature {
        Update { _, _ in
        }
    }
}

public struct OrganizerDetailView: View {
    let store: StoreOf<OrganizerDetail>

    public init(store: StoreOf<OrganizerDetail>) {
        self.store = store
    }

    public var body: some View {
        List {
            EmptyBrowserState(
                title: "Organizer",
                systemImage: "person.crop.circle",
                message: "Organizer detail feature stub."
            )
        }
        .navigationTitle(store.organizerID.description)
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
            case .queryEdited(let query):
                state.query = query

            case .didPullToRefresh,
                 .eventButtonTapped,
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
        List {
            Section {
                TextField("Search events or organizers", text: $store.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            EmptyBrowserState(
                title: "Search",
                systemImage: "magnifyingglass",
                message: "Search feature stub."
            )
        }
        .navigationTitle("Search")
    }
}

@Feature
public struct EventPlaceholder {
    public init() {}

    public struct State: Identifiable {
        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
        }

        public let eventID: OMERecord.Event.ID
        public var event: EventPlaceholderRow?
        public var isLoading = false

        public var id: OMERecord.Event.ID { eventID }
    }

    public enum Action {
        case closeButtonTapped
        case eventResponse(EventPlaceholderRow?)
        case task
    }

    public var body: some Feature {
        Update { _, _ in
        }
    }
}

public struct EventPlaceholderView: View {
    let store: StoreOf<EventPlaceholder>

    public init(store: StoreOf<EventPlaceholder>) {
        self.store = store
    }

    public var body: some View {
        List {
            Section {
                Text(store.eventID.description)
                    .font(.headline)
            }

            Section {
                Text("Event placeholder feature stub.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Close") {
                    store.send(.closeButtonTapped)
                }
            }
        }
        .navigationTitle("Event")
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

public struct EventPlaceholderRow: Equatable, Identifiable, Sendable {
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
