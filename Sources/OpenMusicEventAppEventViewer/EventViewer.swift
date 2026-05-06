import ComposableArchitecture2
import Dependencies
import SwiftUI
import Tagged

private enum ViewerEventIDKey: DependencyKey {
    static let liveValue: OMERecord.Event.ID = .init("-1")
}

extension DependencyValues {
    var viewerEventID: OMERecord.Event.ID {
        get { self[ViewerEventIDKey.self] }
        set { self[ViewerEventIDKey.self] = newValue }
    }
}

@Feature
public struct EventViewer {
    public init() {}

    public enum EventFeature: String, CaseIterable, Hashable, Sendable {
        case schedule
        case communications
        case contactInfo
        case location
        case siteMap
        case posters
        case notifications
        case search
        case about
        case edit

        var title: String {
            switch self {
            case .schedule: "Schedule"
            case .communications: "Comms"
            case .contactInfo: "Contact"
            case .location: "Location"
            case .siteMap: "Site Map"
            case .posters: "Posters"
            case .notifications: "Alerts"
            case .search: "Search"
            case .about: "About"
            case .edit: "Edit"
            }
        }

        var systemImage: String {
            switch self {
            case .schedule: "calendar"
            case .communications: "megaphone"
            case .contactInfo: "phone"
            case .location: "mappin.and.ellipse"
            case .siteMap: "map"
            case .posters: "photo.on.rectangle"
            case .notifications: "bell"
            case .search: "magnifyingglass"
            case .about: "info.circle"
            case .edit: "pencil"
            }
        }

        var customizationID: String {
            switch self {
            case .schedule: "openMusicEvent.eventViewer.schedule"
            case .communications: "openMusicEvent.eventViewer.communications"
            case .contactInfo: "openMusicEvent.eventViewer.contactInfo"
            case .location: "openMusicEvent.eventViewer.location"
            case .siteMap: "openMusicEvent.eventViewer.siteMap"
            case .posters: "openMusicEvent.eventViewer.posters"
            case .notifications: "openMusicEvent.eventViewer.notifications"
            case .search: "openMusicEvent.eventViewer.search"
            case .about: "openMusicEvent.eventViewer.about"
            case .edit: "openMusicEvent.eventViewer.edit"
            }
        }
    }

    public struct State: Identifiable {
        public init(eventID: OMERecord.Event.ID) {
            self.init(eventID: eventID, features: EventFeature.allCases)
        }

        public init(eventID: OMERecord.Event.ID, features: [EventFeature]) {
            self.eventID = eventID
            self.installedFeatures = features
            self.selectedFeature = features.first ?? .schedule

            for feature in features {
                switch feature {
                case .schedule:
                    self.scheduleViewer = Spawn(ScheduleViewer.State())
                case .communications:
                    self.communicationsViewer = Spawn(CommunicationsViewer.State())
                case .contactInfo:
                    self.contactInfoViewer = Spawn(ContactInfoViewer.State())
                case .location:
                    self.locationViewer = Spawn(LocationViewer.State())
                case .siteMap:
                    self.siteMapViewer = Spawn(SiteMapViewer.State())
                case .posters:
                    self.postersViewer = Spawn(PostersViewer.State())
                case .notifications:
                    self.notificationsViewer = Spawn(NotificationsViewer.State())
                case .search:
                    self.eventSearch = Spawn(EventSearch.State())
                case .about:
                    self.aboutViewer = Spawn(AboutViewer.State())
                case .edit:
                    self.edit = Spawn(Edit.State())
                }
            }
        }

        public static func route(
            eventID: OMERecord.Event.ID,
            target: EventTarget?
        ) -> Self {
            var state = Self(eventID: eventID)
            state.navigate(to: target)
            return state
        }

        public let eventID: OMERecord.Event.ID
        public var installedFeatures: [EventFeature]
        public var selectedFeature: EventFeature

        public var scheduleViewer: Spawn<ScheduleViewer>?
        public var communicationsViewer: Spawn<CommunicationsViewer>?
        public var contactInfoViewer: Spawn<ContactInfoViewer>?
        public var locationViewer: Spawn<LocationViewer>?
        public var siteMapViewer: Spawn<SiteMapViewer>?
        public var postersViewer: Spawn<PostersViewer>?
        public var notificationsViewer: Spawn<NotificationsViewer>?
        public var eventSearch = Spawn(EventSearch.State())
        public var aboutViewer: Spawn<AboutViewer>?
        public var edit: Spawn<Edit>?

        public var id: OMERecord.Event.ID { eventID }

        mutating func navigate(to target: EventTarget?) {
            guard let target else {
                self.eventSearch.state = EventSearch.State()
                return
            }

            self.selectedFeature = target.eventFeature

            switch target {
            case .participant, .stage, .search:
                self.eventSearch.state = EventSearch.State.route(target: target)
            default:
                self.eventSearch.state = EventSearch.State()
            }
        }
    }

    public enum Action {
        case closeButtonTapped
        case eventSearch(EventSearch.Action)
    }

    public var body: some Feature {
        Update { _, action in
            switch action {
            case .closeButtonTapped, .eventSearch:
                break
            }
        }
        .onEvent(NavigationRequested.self, consume: true) { request, state in
            guard case let .event(eventID, target) = request, eventID == state.eventID else { return }
            state.navigate(to: target)
        }
        .ifLet(\.scheduleViewer) {
            ScheduleViewer()
                .dependency(\.viewerEventID, store.eventID)
        }
        .spawn(\.eventSearch) {
            EventSearch()
                .dependency(\.viewerEventID, store.eventID)
        }
        .ifLet(\.communicationsViewer) {
            CommunicationsViewer()
                .dependency(\.viewerEventID, store.eventID)
        }
        .ifLet(\.contactInfoViewer) {
            ContactInfoViewer()
                .dependency(\.viewerEventID, store.eventID)
        }
        .ifLet(\.locationViewer) {
            LocationViewer()
                .dependency(\.viewerEventID, store.eventID)
        }
        .ifLet(\.siteMapViewer) {
            SiteMapViewer()
                .dependency(\.viewerEventID, store.eventID)
        }
        .ifLet(\.postersViewer) {
            PostersViewer()
                .dependency(\.viewerEventID, store.eventID)
        }
        .ifLet(\.notificationsViewer) {
            NotificationsViewer()
                .dependency(\.viewerEventID, store.eventID)
        }
        .ifLet(\.aboutViewer) {
            AboutViewer()
                .dependency(\.viewerEventID, store.eventID)
        }
        .ifLet(\.edit) {
            Edit()
                .dependency(\.viewerEventID, store.eventID)
        }
    }
}

public struct EventViewerView: View {
    public init(store: StoreOf<EventViewer>) {
        self.store = store
    }

    @Bindable var store: StoreOf<EventViewer>

    public var body: some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            iOS18TabView(store: store)
        } else {
            legacyiOSTabView
        }
        #else
        defaultTabView
        #endif
    }

    #if os(iOS)

    @available(iOS 18.0, *)
    struct iOS18TabView: View {
        @Bindable var store: StoreOf<EventViewer>

        init(store: StoreOf<EventViewer>) {
            self.store = store
        }

        @AppStorage("eventViewerTabCustomization")
        var customization: TabViewCustomization = .init()

        var body: some View {
            TabView(selection: $store.selectedFeature) {

                if store.installedFeatures.contains(.search) {
                    Tab(value: EventViewer.EventFeature.search, role: .search) {
                        EventSearchView(store: store.spawn(\.eventSearch))
                    }
                    .customizationID(EventViewer.EventFeature.search.customizationID)
                    .customizationBehavior(.disabled, for: .sidebar, .tabBar)
                }
                
                if let featureStore = store.spawn(\.scheduleViewer) {
                    Tab("Schedule", systemImage: "calendar", value: EventViewer.EventFeature.schedule) {
                        NavigationStack {
                            ScheduleViewerView(store: featureStore)
                        }
                    }
                    .customizationID(EventViewer.EventFeature.schedule.customizationID)
                }

                if let featureStore = store.spawn(\.communicationsViewer) {
                    Tab("Comms", systemImage: "megaphone", value: EventViewer.EventFeature.communications) {
                        NavigationStack {
                            CommunicationsViewerView(store: featureStore)
                        }
                    }
                    .customizationID(EventViewer.EventFeature.communications.customizationID)
                }

                if let featureStore = store.spawn(\.contactInfoViewer) {
                    Tab("Contact", systemImage: "phone", value: EventViewer.EventFeature.contactInfo) {
                        NavigationStack {
                            ContactInfoViewerView(store: featureStore)
                        }
                    }
                    .customizationID(EventViewer.EventFeature.contactInfo.customizationID)
                }


                if let featureStore = store.spawn(\.locationViewer) {
                    Tab("Location", systemImage: "mappin.and.ellipse", value: EventViewer.EventFeature.location) {
                        NavigationStack {
                            LocationViewerView(store: featureStore)
                        }
                    }
                    .customizationID(EventViewer.EventFeature.location.customizationID)
                }

                if let featureStore = store.spawn(\.siteMapViewer) {
                    Tab("Site Map", systemImage: "map", value: EventViewer.EventFeature.siteMap) {
                        NavigationStack {
                            SiteMapViewerView(store: featureStore)
                        }
                    }
                    .customizationID(EventViewer.EventFeature.siteMap.customizationID)
                }

                if let featureStore = store.spawn(\.postersViewer) {
                    Tab("Posters", systemImage: "photo.on.rectangle", value: EventViewer.EventFeature.posters) {
                        NavigationStack {
                            PostersViewerView(store: featureStore)
                        }
                    }
                    .customizationID(EventViewer.EventFeature.posters.customizationID)
                }

                if let featureStore = store.spawn(\.notificationsViewer) {
                    Tab("Alerts", systemImage: "bell", value: EventViewer.EventFeature.notifications) {
                        NavigationStack {
                            NotificationsViewerView(store: featureStore)
                        }
                    }
                    .customizationID(EventViewer.EventFeature.notifications.customizationID)
                }

                if let featureStore = store.spawn(\.aboutViewer) {
                    Tab("About", systemImage: "info.circle", value: EventViewer.EventFeature.about) {
                        NavigationStack {
                            AboutViewerView(store: featureStore)
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") {
                                    store.send(.closeButtonTapped)
                                }
                            }
                        }
                    }
                    .customizationID(EventViewer.EventFeature.about.customizationID)
                }

                if let featureStore = store.spawn(\.edit) {
                    Tab("Edit", systemImage: "pencil", value: EventViewer.EventFeature.edit) {
                        NavigationStack {
                            EditView(store: featureStore)
                        }
                    }
                    .customizationID(EventViewer.EventFeature.edit.customizationID)
                }

            }
            .tabViewStyle(.sidebarAdaptable)
            .tabViewCustomization($customization)
        }
    }
    #endif

    #if os(iOS)
    private var legacyiOSTabView: some View {
        TabView(selection: $store.selectedFeature) {
            if let featureStore = store.spawn(\.scheduleViewer) {
                viewerTab(.schedule) {
                    ScheduleViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.schedule)
            }

            if let featureStore = store.spawn(\.communicationsViewer) {
                viewerTab(.communications) {
                    CommunicationsViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.communications)
            }

            if let featureStore = store.spawn(\.contactInfoViewer) {
                viewerTab(.contactInfo) {
                    ContactInfoViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.contactInfo)
            }

            if let featureStore = store.spawn(\.locationViewer) {
                viewerTab(.location) {
                    LocationViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.location)
            }

            if store.installedFeatures.contains(.search) {
                viewerTab(.search) {
                    EventSearchView(store: store.spawn(\.eventSearch))
                }
                .tag(EventViewer.EventFeature.search)
            }

            if let featureStore = store.spawn(\.siteMapViewer) {
                viewerTab(.siteMap) {
                    SiteMapViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.siteMap)
            }

            if let featureStore = store.spawn(\.postersViewer) {
                viewerTab(.posters) {
                    PostersViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.posters)
            }

            if let featureStore = store.spawn(\.notificationsViewer) {
                viewerTab(.notifications) {
                    NotificationsViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.notifications)
            }

            if let featureStore = store.spawn(\.aboutViewer) {
                viewerTab(.about) {
                    AboutViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.about)
            }

            if let featureStore = store.spawn(\.edit) {
                viewerTab(.edit) {
                    EditView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.edit)
            }


        }
    }
    #endif

    private var defaultTabView: some View {
        TabView(selection: $store.selectedFeature) {
            if let featureStore = store.spawn(\.scheduleViewer) {
                viewerTab(.schedule) {
                    ScheduleViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.schedule)
            }

            if let featureStore = store.spawn(\.communicationsViewer) {
                viewerTab(.communications) {
                    CommunicationsViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.communications)
            }

            if let featureStore = store.spawn(\.contactInfoViewer) {
                viewerTab(.contactInfo) {
                    ContactInfoViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.contactInfo)
            }

            if let featureStore = store.spawn(\.locationViewer) {
                viewerTab(.location) {
                    LocationViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.location)
            }

            if let featureStore = store.spawn(\.siteMapViewer) {
                viewerTab(.siteMap) {
                    SiteMapViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.siteMap)
            }

            if let featureStore = store.spawn(\.postersViewer) {
                viewerTab(.posters) {
                    PostersViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.posters)
            }

            if let featureStore = store.spawn(\.notificationsViewer) {
                viewerTab(.notifications) {
                    NotificationsViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.notifications)
            }

            if let featureStore = store.spawn(\.aboutViewer) {
                viewerTab(.about) {
                    AboutViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.about)
            }

            if let featureStore = store.spawn(\.edit) {
                viewerTab(.edit) {
                    EditView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.edit)
            }

            if store.installedFeatures.contains(.search) {
                viewerTab(.search) {
                    EventSearchView(store: store.spawn(\.eventSearch))
                }
                .tag(EventViewer.EventFeature.search)
            }
        }
    }

    private func viewerTab<Content: View>(
        _ feature: EventViewer.EventFeature,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    if feature == .about {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                store.send(.closeButtonTapped)
                            }
                        }
                    }
                }
        }
            .tabItem {
                Label(feature.title, systemImage: feature.systemImage)
            }
    }
}

struct ViewerPlaceholderView: View {
    let title: String
    let systemImage: String
    let description: LocalizedStringKey

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .navigationTitle(title)
    }
}

#Preview {
    EventViewerView(
        store: Store(
            initialState: EventViewer.State(eventID: .init("preview"))
        ) {
            EventViewer()
        }
    )
}
