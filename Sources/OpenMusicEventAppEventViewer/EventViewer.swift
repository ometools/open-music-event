import ComposableArchitecture2
import Dependencies
import Sharing
import OpenMusicEventDatabase
import OpenMusicEventSourceEditing
import SQLiteData
import SourceEditing
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

    @Dependency(\.defaultDatabase) var database

    public enum EventFeature: Hashable, Sendable, LosslessStringConvertible, TabFeatureValue {
        case schedule(ScheduleViewer.ScheduleDivision)
        case contributors
        case stages
        case communications
        case contactInfo
        case location
        case siteMap
        case posters
        case notifications
        case settings
        case edit
        case search
        case about

        public static let defaultFeatures: [Self] = [
            .schedule(.schedule),
            .contributors,
            .stages,
            .communications,
            .contactInfo,
            .location,
            .siteMap,
            .posters,
            .notifications,
            .settings,
            .edit,
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
            case "contributors":
                self = .contributors
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
            case "settings":
                self = .settings
            case "edit":
                self = .edit
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
            case .contributors:
                return "contributors"
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
            case .settings:
                return "settings"
            case .edit:
                return "edit"
            case .search:
                return "search"
            case .about:
                return "about"
            }
        }

        var title: String {
            switch self {
            case let .schedule(division): division.title
            case .contributors: "Contributors"
            case .stages: "Stages"
            case .communications: "Comms"
            case .contactInfo: "Contact"
            case .location: "Location"
            case .siteMap: "Site Map"
            case .posters: "Posters"
            case .notifications: "Alerts"
            case .settings: "Settings"
            case .edit: "Edit"
            case .search: "Search"
            case .about: "About"
            }
        }

        var systemImage: String {
            switch self {
            case let .schedule(division): division.systemImage
            case .contributors: "person.3"
            case .stages: "square.grid.2x2"
            case .communications: "megaphone"
            case .contactInfo: "phone"
            case .location: "mappin.and.ellipse"
            case .siteMap: "map"
            case .posters: "photo.on.rectangle"
            case .notifications: "bell"
            case .settings: "gearshape"
            case .edit: "pencil"
            case .search: "magnifyingglass"
            case .about: "info.circle"
            }
        }

        var labelTint: Color? {
            switch self {
            case .schedule: .green
            case .contributors: .pink
            case .stages: .indigo
            case .communications: .orange
            case .contactInfo: .green
            case .location: .blue
            case .siteMap: .teal
            case .posters: .purple
            case .notifications: .red
            case .settings: .gray
            case .edit: .yellow
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
            case .contributors: return "openMusicEvent.eventViewer.contributors"
            case .stages: return "openMusicEvent.eventViewer.stages"
            case .communications: return "openMusicEvent.eventViewer.communications"
            case .contactInfo: return "openMusicEvent.eventViewer.contactInfo"
            case .location: return "openMusicEvent.eventViewer.location"
            case .siteMap: return "openMusicEvent.eventViewer.siteMap"
            case .posters: return "openMusicEvent.eventViewer.posters"
            case .notifications: return "openMusicEvent.eventViewer.notifications"
            case .settings: return "openMusicEvent.eventViewer.settings"
            case .edit: return "openMusicEvent.eventViewer.edit"
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
            let sourceEditingSession = try? SourceEditingSession.openMusicEvent(eventID: eventID)

            self.eventID = eventID
            self.sourceEditingSession = sourceEditingSession
            self._eventViewerState = Shared(.eventViewerState(eventID))
            self.installedFeatures = features
            self.selectedFeature = features.first ?? .schedule(.schedule)
            self.eventSearch = Spawn(EventSearch.State(eventID: eventID))

            withDependencies {
                $0.defaultEventID = eventID
                if let sourceEditingSession {
                    $0.defaultDatabase = sourceEditingSession.database
                    $0.sourceEditingSession = sourceEditingSession
                }
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
                    case .contributors:
                        self.contributorsViewer = Spawn(ContributorsViewer.State(eventID: eventID))
                    case .stages:
                        self.stagesViewer = Spawn(StagesViewer.State(eventID: eventID))
                    case .communications:
                        self.communicationsViewer = Spawn(CommunicationsViewer.State(eventID: eventID))
                    case .contactInfo:
                        self.contactInfoViewer = Spawn(ContactInfoViewer.State(eventID: eventID))
                    case .location:
                        self.locationViewer = Spawn(LocationViewer.State(eventID: eventID))
                    case .siteMap:
                        self.siteMapViewer = Spawn(SiteMapViewer.State(eventID: eventID))
                    case .posters:
                        self.postersViewer = Spawn(PostersViewer.State(eventID: eventID))
                    case .notifications:
                        self.notificationsViewer = Spawn(NotificationsViewer.State(eventID: eventID))
                    case .settings:
                        self.eventSettings = Spawn(EventSettings.State(eventID: eventID))
                    case .edit:
                        self.editEvent = Spawn(EditEvent.State(eventID: eventID))
                    case .search:
                        self.eventSearch = Spawn(EventSearch.State(eventID: eventID))
                    case .about:
                        self.eventInfoViewer = Spawn(EventInfoViewer.State(eventID: eventID))
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
        @DebugSnapshotIgnored
        public var sourceEditingSession: SourceEditingSession?
        @Shared public var eventViewerState: EventViewerState
        public var installedFeatures: [EventFeature]
        public var selectedFeature: EventFeature

        public var scheduleViewers: [Spawn<ScheduleViewer>] = []
        public var contributorsViewer: Spawn<ContributorsViewer>?
        public var stagesViewer: Spawn<StagesViewer>?
        public var communicationsViewer: Spawn<CommunicationsViewer>?
        public var contactInfoViewer: Spawn<ContactInfoViewer>?
        public var locationViewer: Spawn<LocationViewer>?
        public var siteMapViewer: Spawn<SiteMapViewer>?
        public var postersViewer: Spawn<PostersViewer>?
        public var notificationsViewer: Spawn<NotificationsViewer>?
        public var eventSettings: Spawn<EventSettings>?
        public var editEvent: Spawn<EditEvent>?
        public var eventSearch: Spawn<EventSearch>
        public var eventInfoViewer: Spawn<EventInfoViewer>?

        public var id: OMERecord.Event.ID { eventID }

        mutating func navigate(to target: EventTarget?) {
            guard let target else {
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
                self.eventInfoViewer?.state.destination = nil
                return
            }

            self.selectedFeature = target.eventFeature

            switch target {
            case let .contributor(contributorID):
                let eventID = self.eventID
                self.eventSearch.state = withEventDependencies {
                    EventSearch.State(eventID: eventID)
                }
                if self.contributorsViewer == nil {
                    self.contributorsViewer = withEventDependencies {
                        Spawn(ContributorsViewer.State(eventID: eventID))
                    }
                }
                let destination = withEventDependencies {
                    ContributorsViewer.Destination.State.contributorDetail(
                        Spawn(
                            ContributorDetail.State(
                                contributorID: contributorID,
                                eventID: eventID
                            )
                        )
                    )
                }
                self.contributorsViewer?.state.destination = destination
                self.stagesViewer?.state.destination = nil
                self.eventInfoViewer?.state.destination = nil
            case .contributors:
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
                self.eventInfoViewer?.state.destination = nil
            case let .stage(stageID):
                let eventID = self.eventID
                self.eventSearch.state = withEventDependencies {
                    EventSearch.State(eventID: eventID)
                }
                self.contributorsViewer?.state.destination = nil
                if self.stagesViewer == nil {
                    self.stagesViewer = withEventDependencies {
                        Spawn(StagesViewer.State(eventID: eventID))
                    }
                }
                let destination = withEventDependencies {
                    StagesViewer.Destination.State.stageDetail(
                        Spawn(
                            StageDetail.State(
                                stageID: stageID,
                                eventID: eventID
                            )
                        )
                    )
                }
                self.stagesViewer?.state.destination = destination
                self.eventInfoViewer?.state.destination = nil
            case .stages:
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
                self.eventInfoViewer?.state.destination = nil
            case .search:
                self.eventSearch.state = EventSearch.State.route(eventID: eventID, target: target)
                self.contributorsViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
                self.eventInfoViewer?.state.destination = nil
            case .edit:
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
                self.eventInfoViewer?.state.destination = nil
                if self.editEvent == nil {
                    self.editEvent = Spawn(EditEvent.State(eventID: self.eventID))
                }
            default:
                self.eventSearch.state = EventSearch.State(eventID: eventID)
                self.contributorsViewer?.state.destination = nil
                self.stagesViewer?.state.destination = nil
                self.eventInfoViewer?.state.destination = nil
            }
        }

        private func withEventDependencies<Value>(_ operation: () -> Value) -> Value {
            let eventID = self.eventID
            let sourceEditingSession = self.sourceEditingSession
            return withDependencies {
                $0.defaultEventID = eventID
                if let sourceEditingSession {
                    $0.defaultDatabase = sourceEditingSession.database
                    $0.sourceEditingSession = sourceEditingSession
                }
            } operation: {
                operation()
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
            case .closeButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .eventSearch:
                break
            }
        }
        .onEvent(NavigationRequested.self) { request, state in
            guard case let .event(eventID, target) = request, eventID == state.eventID else { return }
            state.navigate(to: target)
        }
        .forEach(\.scheduleViewers) {
            ScheduleViewer()
        }
        .ifLet(\.contributorsViewer) {
            ContributorsViewer()
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
        .ifLet(\.eventSettings) {
            EventSettings()
        }
        .ifLet(\.editEvent) {
            EditEvent()
        }
        .ifLet(\.eventInfoViewer) {
            EventInfoViewer()
        }
        .dependency(\.defaultEventID, store.eventID)
        .dependency(\.sourceEditingSession, store.sourceEditingSession)
        .dependency(\.defaultDatabase, store.sourceEditingSession?.database ?? database)
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

                if let featureStore = store.spawn(\.contributorsViewer) {
                    TabFeature(
                        .contributors,
                        title: EventViewer.EventFeature.contributors.title,
                        systemImage: EventViewer.EventFeature.contributors.systemImage,
                        labelTint: EventViewer.EventFeature.contributors.labelTint,
                        navigation: .stack
                    ) {
                        ContributorsViewerView(store: featureStore)
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

                if let featureStore = store.spawn(\.eventSettings) {
                    TabFeature(
                        .settings,
                        title: EventViewer.EventFeature.settings.title,
                        systemImage: EventViewer.EventFeature.settings.systemImage,
                        labelTint: EventViewer.EventFeature.settings.labelTint,
                        navigation: .stack
                    ) {
                        EventSettingsView(store: featureStore)
                    }
                }

                if let featureStore = store.spawn(\.editEvent) {
                    TabFeature(
                        .edit,
                        title: EventViewer.EventFeature.edit.title,
                        systemImage: EventViewer.EventFeature.edit.systemImage,
                        labelTint: EventViewer.EventFeature.edit.labelTint,
                        badgeValue: featureStore.changeCount,
                        navigation: .stack
                    ) {
                        EditEventView(store: featureStore)
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

            if let featureStore = store.spawn(\.contributorsViewer) {
                viewerTab(.contributors) {
                    ContributorsViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.contributors)
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

            if let featureStore = store.spawn(\.eventSettings) {
                viewerTab(.settings) {
                    EventSettingsView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.settings)
            }

            if let featureStore = store.spawn(\.editEvent) {
                viewerTab(.edit, badgeValue: featureStore.changeCount) {
                    EditEventView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.edit)
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

            if let featureStore = store.spawn(\.contributorsViewer) {
                viewerTab(.contributors) {
                    ContributorsViewerView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.contributors)
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

            if let featureStore = store.spawn(\.eventSettings) {
                viewerTab(.settings) {
                    EventSettingsView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.settings)
            }

            if let featureStore = store.spawn(\.editEvent) {
                viewerTab(.edit, badgeValue: featureStore.changeCount) {
                    EditEventView(store: featureStore)
                }
                .tag(EventViewer.EventFeature.edit)
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
        badgeValue: Int? = nil,
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
            .badge(badgeValue ?? 0)
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
