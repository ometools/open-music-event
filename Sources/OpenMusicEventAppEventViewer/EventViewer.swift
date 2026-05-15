import ComposableArchitecture2
import Dependencies
import Sharing
import OpenMusicEventDatabase
import SQLiteData
import SwiftUI
import SwiftUITabFeatures
import Tagged

private enum DefaultEventIDKey: DependencyKey {
    static let liveValue: OMERecord.Event.ID =
        unimplemented(
            "DependencyValues.defaultEventID",
            placeholder: .init(
                organizerID: OMERecord.Organizer.ID("did:web:example.com")!,
                eventID: .init("-1")
            )
        )
}

extension DependencyValues {
    var defaultEventID: OMERecord.Event.ID {
        get { self[DefaultEventIDKey.self] }
        set { self[DefaultEventIDKey.self] = newValue }
    }
}

extension OMERecord.Event {
  static var defaultEvent: some SelectStatementOf<OMERecord.Event> {
    @Dependency(\.defaultEventID) var defaultEventID
    return Self.where { $0.id.eq(defaultEventID) }
  }
}

@Feature
public struct EventViewer {
    public init() {}

    public enum EventFeature: Hashable, Sendable, LosslessStringConvertible, TabFeatureValue {
        case schedule(ScheduleViewer.ScheduleDivision)
        case people
        case stages
        case communications
        case contactInfo
        case location
        case siteMap
        case posters
        case notifications
        case search
        case about

        public static let defaultFeatures: [Self] = [
            .schedule(.schedule),
            .people,
            .stages,
            .communications,
            .contactInfo,
            .location,
            .siteMap,
            .posters,
            .notifications,
            .search,
            .about,
        ]

        public init?(_ description: String) {
            switch description {
            case "schedule":
                self = .schedule(.schedule)
            case let value where value.hasPrefix("schedule:"):
                let rawCategory = String(value.dropFirst("schedule:".count))
                guard !rawCategory.isEmpty else { return nil }
                self = .schedule(
                    ScheduleViewer.ScheduleDivision(
                        category: OMERecord.Stage.Category(rawCategory)
                    )
                )
            case "people":
                self = .people
            case "stages":
                self = .stages
            case "communications":
                self = .communications
            case "contactInfo":
                self = .contactInfo
            case "location":
                self = .location
            case "siteMap":
                self = .siteMap
            case "posters":
                self = .posters
            case "notifications":
                self = .notifications
            case "search":
                self = .search
            case "about":
                self = .about
            default:
                return nil
            }
        }

        public var description: String {
            switch self {
            case let .schedule(division):
                if let category = division.category {
                    return "schedule:\(category.rawValue)"
                }
                return "schedule"
            case .people:
                return "people"
            case .stages:
                return "stages"
            case .communications:
                return "communications"
            case .contactInfo:
                return "contactInfo"
            case .location:
                return "location"
            case .siteMap:
                return "siteMap"
            case .posters:
                return "posters"
            case .notifications:
                return "notifications"
            case .search:
                return "search"
            case .about:
                return "about"
            }
        }

        var title: String {
            switch self {
            case let .schedule(division): division.title
            case .people: "People"
            case .stages: "Stages"
            case .communications: "Comms"
            case .contactInfo: "Contact"
            case .location: "Location"
            case .siteMap: "Site Map"
            case .posters: "Posters"
            case .notifications: "Alerts"
            case .search: "Search"
            case .about: "About"
            }
        }

        var systemImage: String {
            switch self {
            case let .schedule(division): division.systemImage
            case .people: "person.3"
            case .stages: "square.grid.2x2"
            case .communications: "megaphone"
            case .contactInfo: "phone"
            case .location: "mappin.and.ellipse"
            case .siteMap: "map"
            case .posters: "photo.on.rectangle"
            case .notifications: "bell"
            case .search: "magnifyingglass"
            case .about: "info.circle"
            }
        }

        var labelTint: Color? {
            switch self {
            case .schedule: .green
            case .people: .pink
            case .stages: .indigo
            case .communications: .orange
            case .contactInfo: .green
            case .location: .blue
            case .siteMap: .teal
            case .posters: .purple
            case .notifications: .red
            case .search: nil
            case .about: .gray
            }
        }

        var customizationID: TabFeatureID {
            switch self {
            case let .schedule(division):
                if division.category == nil {
                    return "openMusicEvent.eventViewer.schedule"
                }
                return "openMusicEvent.eventViewer.schedule.\(division.id)"
            case .people: return "openMusicEvent.eventViewer.people"
            case .stages: return "openMusicEvent.eventViewer.stages"
            case .communications: return "openMusicEvent.eventViewer.communications"
            case .contactInfo: return "openMusicEvent.eventViewer.contactInfo"
            case .location: return "openMusicEvent.eventViewer.location"
            case .siteMap: return "openMusicEvent.eventViewer.siteMap"
            case .posters: return "openMusicEvent.eventViewer.posters"
            case .notifications: return "openMusicEvent.eventViewer.notifications"
            case .search: return "openMusicEvent.eventViewer.search"
            case .about: return "openMusicEvent.eventViewer.about"
            }
        }

        var scheduleDivision: ScheduleViewer.ScheduleDivision? {
            guard case let .schedule(division) = self else { return nil }
            return division
        }

        static func features(eventID: OMERecord.Event.ID) -> [Self] {
            @Dependency(\.defaultDatabase) var database
            let stages = (try? database.read { db in
                try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
            }) ?? []
            return features(scheduleDivisions: ScheduleViewer.scheduleDivisions(stages: stages))
        }

        static func features(
            scheduleDivisions: [ScheduleViewer.ScheduleDivision]
        ) -> [Self] {
            let divisions = scheduleDivisions.isEmpty ? [.schedule] : scheduleDivisions
            return divisions.map(Self.schedule) + defaultFeatures.filter {
                $0.scheduleDivision == nil
            }
        }
    }

    public struct State: Identifiable {
        public init(eventID: OMERecord.Event.ID) {
            self.init(
                eventID: eventID,
                features: EventFeature.features(eventID: eventID)
            )
        }

        public init(
            eventID: OMERecord.Event.ID,
            features: [EventFeature]
        ) {

            self.eventID = eventID
            self._eventViewerState = Shared(.eventViewerState(eventID))
            self._editSummary = Fetch(
                wrappedValue: EventEditSummary(
                    eventID: eventID,
                    availability: .notSourceBacked,
                    groups: []
                ),
                EventEditSummaryRequest(eventID: eventID)
            )
            self.installedFeatures = features
            self.selectedFeature = features.first ?? .schedule(.schedule)

            withDependencies {
                $0.defaultEventID = eventID
            } operation: {

                for feature in features {
                    switch feature {
                    case let .schedule(division):
                        self.scheduleViewers.append(
                            Spawn(
                                ScheduleViewer.State(
                                    eventID: eventID,
                                    scheduleDivision: division
                                )
                            )
                        )
                    case .people:
                        self.peopleViewer = Spawn(PeopleViewer.State(eventID: eventID))
                    case .stages:
                        self.stagesViewer = Spawn(StagesViewer.State(eventID: eventID))
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
                        self.eventInfoViewer = Spawn(EventInfoViewer.State())
                    }
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
        @Shared public var eventViewerState: EventViewerState
        @DebugSnapshotIgnored
        @Fetch public var editSummary: EventEditSummary
        public var installedFeatures: [EventFeature]
        public var selectedFeature: EventFeature

        public var scheduleViewers: [Spawn<ScheduleViewer>] = []
        public var peopleViewer: Spawn<PeopleViewer>?
        public var stagesViewer: Spawn<StagesViewer>?
        public var communicationsViewer: Spawn<CommunicationsViewer>?
        public var contactInfoViewer: Spawn<ContactInfoViewer>?
        public var locationViewer: Spawn<LocationViewer>?
        public var siteMapViewer: Spawn<SiteMapViewer>?
        public var postersViewer: Spawn<PostersViewer>?
        public var notificationsViewer: Spawn<NotificationsViewer>?
        public var eventSearch = Spawn(EventSearch.State())
        public var eventInfoViewer: Spawn<EventInfoViewer>?

        public var id: OMERecord.Event.ID { eventID }

        mutating func navigate(to target: EventTarget?) {
            guard let target else {
                self.eventSearch.state = EventSearch.State()
                self.peopleViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
                self.eventInfoViewer?.state.destination = nil
                return
            }

            self.selectedFeature = target.eventFeature

            switch target {
            case let .participant(participantID):
                let eventID = self.eventID
                self.eventSearch.state = EventSearch.State()
                if self.peopleViewer == nil {
                    self.peopleViewer = Spawn(PeopleViewer.State(eventID: eventID))
                }
                self.peopleViewer?.state.destination = .participantDetail(
                    Spawn(
                        ParticipantDetail.State(
                            participantID: participantID,
                            eventID: eventID
                        )
                    )
                )
                self.stagesViewer?.state.destination = nil
                self.eventInfoViewer?.state.destination = nil
            case .people:
                self.eventSearch.state = EventSearch.State()
                self.peopleViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
                self.eventInfoViewer?.state.destination = nil
            case let .stage(stageID):
                let eventID = self.eventID
                self.eventSearch.state = EventSearch.State()
                self.peopleViewer?.state.destination = nil
                if self.stagesViewer == nil {
                    self.stagesViewer = Spawn(StagesViewer.State(eventID: eventID))
                }
                self.stagesViewer?.state.destination = .stageDetail(
                    Spawn(
                        StageDetail.State(
                            stageID: stageID,
                            eventID: eventID
                        )
                    )
                )
                self.eventInfoViewer?.state.destination = nil
            case .stages:
                self.eventSearch.state = EventSearch.State()
                self.peopleViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
                self.eventInfoViewer?.state.destination = nil
            case .search:
                self.eventSearch.state = EventSearch.State.route(target: target)
                self.peopleViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
                self.eventInfoViewer?.state.destination = nil
            case .edit:
                self.eventSearch.state = EventSearch.State()
                self.peopleViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
                if self.eventInfoViewer == nil {
                    self.eventInfoViewer = Spawn(EventInfoViewer.State())
                }
                self.eventInfoViewer?.state.destination = .editEventInfo(Spawn(EditEventInfo.State()))
            default:
                self.eventSearch.state = EventSearch.State()
                self.peopleViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
                self.eventInfoViewer?.state.destination = nil
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
        .forEach(\.scheduleViewers) {
            ScheduleViewer()
        }
        .ifLet(\.peopleViewer) {
            PeopleViewer()
        }
        .ifLet(\.stagesViewer) {
            StagesViewer()
        }
        .spawn(\.eventSearch) {
            EventSearch()
        }
        .ifLet(\.communicationsViewer) {
            CommunicationsViewer()
        }
        .ifLet(\.contactInfoViewer) {
            ContactInfoViewer()
        }
        .ifLet(\.locationViewer) {
            LocationViewer()
        }
        .ifLet(\.siteMapViewer) {
            SiteMapViewer()
        }
        .ifLet(\.postersViewer) {
            PostersViewer()
        }
        .ifLet(\.notificationsViewer) {
            NotificationsViewer()
        }
        .ifLet(\.eventInfoViewer) {
            EventInfoViewer()
        }
        .dependency(\.defaultEventID, store.eventID)
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
        @State var tabLayout = TabFeatureLayout(preferredIDs: [EventViewer.EventFeature.about.customizationID])

        var body: some View {
            TabFeaturesView(
                selection: $store.selectedFeature,
                layout: $tabLayout
            ) {
                if store.installedFeatures.contains(.search) {
                    TabFeature(.search, role: .search) {
                        EventSearchView(store: store.spawn(\.eventSearch))
                    }
                }

                for featureStore in store.spawn(\.scheduleViewers) {
                    let feature = EventViewer.EventFeature.schedule(featureStore.scheduleDivision)
                    TabFeature(
                        feature,
                        title: feature.title,
                        systemImage: feature.systemImage,
                        labelTint: feature.labelTint,
                        navigation: .stack
                    ) {
                        ScheduleViewerView(
                            store: featureStore,
                            selectedScheduleID: store.state.$eventViewerState.selectedScheduleID
                        )
                    }
                }

                if let featureStore = store.spawn(\.peopleViewer) {
                    TabFeature(
                        .people,
                        title: EventViewer.EventFeature.people.title,
                        systemImage: EventViewer.EventFeature.people.systemImage,
                        labelTint: EventViewer.EventFeature.people.labelTint,
                        navigation: .stack
                    ) {
                        PeopleViewerView(store: featureStore)
                    }
                }

                if let featureStore = store.spawn(\.stagesViewer) {
                    TabFeature(
                        .stages,
                        title: EventViewer.EventFeature.stages.title,
                        systemImage: EventViewer.EventFeature.stages.systemImage,
                        labelTint: EventViewer.EventFeature.stages.labelTint,
                        navigation: .stack
                    ) {
                        StagesViewerView(store: featureStore)
                    }
                }

                if let featureStore = store.spawn(\.communicationsViewer) {
                    TabFeature(
                        .communications,
                        title: EventViewer.EventFeature.communications.title,
                        systemImage: EventViewer.EventFeature.communications.systemImage,
                        labelTint: EventViewer.EventFeature.communications.labelTint,
                        navigation: .stack
                    ) {
                        CommunicationsViewerView(store: featureStore)
                    }
                }

                if let featureStore = store.spawn(\.contactInfoViewer) {
                    TabFeature(
                        .contactInfo,
                        title: EventViewer.EventFeature.contactInfo.title,
                        systemImage: EventViewer.EventFeature.contactInfo.systemImage,
                        labelTint: EventViewer.EventFeature.contactInfo.labelTint,
                        navigation: .stack
                    ) {
                        ContactInfoViewerView(store: featureStore)
                    }
                }

                if let featureStore = store.spawn(\.locationViewer) {
                    TabFeature(
                        .location,
                        title: EventViewer.EventFeature.location.title,
                        systemImage: EventViewer.EventFeature.location.systemImage,
                        labelTint: EventViewer.EventFeature.location.labelTint,
                        navigation: .stack
                    ) {
                        LocationViewerView(store: featureStore)
                    }
                }

                if let featureStore = store.spawn(\.siteMapViewer) {
                    TabFeature(
                        .siteMap,
                        title: EventViewer.EventFeature.siteMap.title,
                        systemImage: EventViewer.EventFeature.siteMap.systemImage,
                        labelTint: EventViewer.EventFeature.siteMap.labelTint,
                        navigation: .stack
                    ) {
                        SiteMapViewerView(store: featureStore)
                    }
                }

                if let featureStore = store.spawn(\.postersViewer) {
                    TabFeature(
                        .posters,
                        title: EventViewer.EventFeature.posters.title,
                        systemImage: EventViewer.EventFeature.posters.systemImage,
                        labelTint: EventViewer.EventFeature.posters.labelTint,
                        navigation: .stack
                    ) {
                        PostersViewerView(store: featureStore)
                    }
                }

                if let featureStore = store.spawn(\.notificationsViewer) {
                    TabFeature(
                        .notifications,
                        title: EventViewer.EventFeature.notifications.title,
                        systemImage: EventViewer.EventFeature.notifications.systemImage,
                        labelTint: EventViewer.EventFeature.notifications.labelTint,
                        navigation: .stack
                    ) {
                        NotificationsViewerView(store: featureStore)
                    }
                }

                if let featureStore = store.spawn(\.eventInfoViewer) {
                    TabFeature(
                        .about,
                        title: EventViewer.EventFeature.about.title,
                        systemImage: EventViewer.EventFeature.about.systemImage,
                        labelTint: EventViewer.EventFeature.about.labelTint,
                        navigation: .stack
                    ) {
                        EventInfoViewerView(store: featureStore)
                            .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") {
                                    store.send(.closeButtonTapped)
                                }
                            }
                        }
                    }
                }

            }
        }
    }
    #endif

    #if os(iOS)
    private var legacyiOSTabView: some View {
        TabView(selection: $store.selectedFeature) {
            ForEach(store.spawn(\.scheduleViewers)) { featureStore in
                let feature = EventViewer.EventFeature.schedule(featureStore.scheduleDivision)
                viewerTab(feature) {
                    ScheduleViewerView(
                        store: featureStore,
                        selectedScheduleID: store.state.$eventViewerState.selectedScheduleID
                    )
                }
                .tag(feature)
            }

            if let featureStore = store.spawn(\.peopleViewer) {
                viewerTab(.people) {
                    PeopleViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.people)
            }

            if let featureStore = store.spawn(\.stagesViewer) {
                viewerTab(.stages) {
                    StagesViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.stages)
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

            if let featureStore = store.spawn(\.eventInfoViewer) {
                viewerTab(.about) {
                    EventInfoViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.about)
            }

        }
    }
    #endif

    private var defaultTabView: some View {
        TabView(selection: $store.selectedFeature) {
            ForEach(store.spawn(\.scheduleViewers)) { featureStore in
                let feature = EventViewer.EventFeature.schedule(featureStore.scheduleDivision)
                viewerTab(feature) {
                    ScheduleViewerView(
                        store: featureStore,
                        selectedScheduleID: store.state.$eventViewerState.selectedScheduleID
                    )
                }
                .tag(feature)
            }

            if let featureStore = store.spawn(\.peopleViewer) {
                viewerTab(.people) {
                    PeopleViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.people)
            }

            if let featureStore = store.spawn(\.stagesViewer) {
                viewerTab(.stages) {
                    StagesViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.stages)
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

            if let featureStore = store.spawn(\.eventInfoViewer) {
                viewerTab(.about) {
                    EventInfoViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.about)
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
            initialState: EventViewer.State(
                eventID: .init(
                    organizerID: OMERecord.Organizer.ID("did:web:example.com")!,
                    eventID: .init("preview")
                )
            )
        ) {
            EventViewer()
        }
    )
}
