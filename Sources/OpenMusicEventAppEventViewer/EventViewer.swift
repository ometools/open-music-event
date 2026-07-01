import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Sharing
import OpenMusicEventDatabase
import OpenMusicEventEditors
import OpenMusicEventSourceEditing
import OpenMusicEventViewers
import SQLiteData
import SourceEditing
import SwiftUI
import SwiftUITabFeatures
import Tagged

private enum DefaultEventIDKey: DependencyKey {
    static var liveValue: OMERecord.Event.ID {
        unimplemented(
            "DependencyValues.defaultEventID",
            placeholder: .init(
                organizerID: OMERecord.Organizer.ID("did:web:example.com")!,
                eventID: .init("-1")
            )
        )
    }
}

private enum DefaultEventTimeZoneKey: DependencyKey {
    static var liveValue: TimeZone {
        .current
    }

    static let testValue = TimeZone(secondsFromGMT: 0)!
}

extension DependencyValues {
    var defaultEventID: OMERecord.Event.ID {
        get { self[DefaultEventIDKey.self] }
        set { self[DefaultEventIDKey.self] = newValue }
    }

    var defaultEventTimeZone: TimeZone {
        get { self[DefaultEventTimeZoneKey.self] }
        set { self[DefaultEventTimeZoneKey.self] = newValue }
    }
}

extension OMERecord.Event {
  static var defaultEvent: some SelectStatementOf<OMERecord.Event> {
    @Dependency(\.defaultEventID) var defaultEventID
    return Self.where { $0.id.eq(defaultEventID) }
  }
}

extension OpenMusicEventViewers.EventFeature {
    static var defaultFeatures: [Self] {
        defaultReadOnlyFeatures.filter { $0 != .search && $0 != .about }
            + editorFeatures
            + [.search, .about]
    }

    static func features(eventID: OMERecord.Event.ID) -> [Self] {
        @Dependency(\.defaultDatabase) var database
        let stages = (try? database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }) ?? []
        return features(scheduleDivisions: ScheduleViewer.scheduleDivisions(stages: stages))
    }

    static func features(
        scheduleDivisions: [ScheduleDivision]
    ) -> [Self] {
        let divisions = scheduleDivisions.isEmpty ? [.schedule] : scheduleDivisions
        return divisions.map(Self.schedule) + defaultFeatures.filter {
            $0.scheduleDivision == nil
        }
    }
}

@Feature
public struct EventViewer {
    public init() {}

    public typealias EventFeature = OpenMusicEventViewers.EventFeature

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.sourceDataRefresh) var sourceDataRefresh
    @StoreTaskID var sourceDataRefreshTask

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
            let eventTimeZone = Self.eventTimeZone(
                eventID: eventID,
                sourceEditingSession: sourceEditingSession
            )

            self.eventID = eventID
            self.eventTimeZone = eventTimeZone
            self.sourceEditingSession = sourceEditingSession
            self._eventViewerState = Shared(.eventViewerState(eventID))
            self.installedFeatures = features
            self.selectedFeature = features.first ?? .schedule(.schedule)
            self.eventSearch = Spawn(EventSearch.State(eventID: eventID))
            self.installFeatureStores(features)
        }

        private mutating func installFeatureStores(_ features: [EventFeature]) {
            self.scheduleViewers = []
            self.contributorsViewer = nil
            self.stagesViewer = nil
            self.communicationsViewer = nil
            self.contactInfoViewer = nil
            self.locationViewer = nil
            self.siteMapViewer = nil
            self.postersViewer = nil
            self.notificationsViewer = nil
            self.eventSettings = nil
            self.editEvent = nil
            self.eventSearch = Spawn(EventSearch.State(eventID: eventID))
            self.eventInfoViewer = nil

            withEventDependencies {
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

        mutating func reloadAfterSourceDataRefresh() {
            let selectedFeature = self.selectedFeature
            self.sourceEditingSession = try? SourceEditingSession.openMusicEvent(eventID: eventID)
            self.eventTimeZone = Self.eventTimeZone(
                eventID: eventID,
                sourceEditingSession: sourceEditingSession
            )
            let features = withEventDependencies {
                EventFeature.features(eventID: eventID)
            }
            self.installedFeatures = features
            self.selectedFeature = features.contains(selectedFeature)
                ? selectedFeature
                : features.first ?? .schedule(.schedule)
            self.installFeatureStores(features)
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
        public var eventTimeZone: TimeZone
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

        mutating func handleEditingIntent(_ intent: EventEditingIntent) {
            switch intent {
            case let .addPerformance(eventID, _),
                 let .deletePerformance(eventID, _),
                 let .editPerformance(eventID, _):
                guard eventID == self.eventID else { return }
                self.selectedFeature = .schedule(.schedule)

            case let .addPosters(eventID):
                guard eventID == self.eventID else { return }
                self.selectedFeature = .posters

            case let .deletePoster(posterID),
                 let .editPoster(posterID):
                guard posterID.eventID == self.eventID.eventID,
                      posterID.organizerID == self.eventID.organizerID
                else { return }
                self.selectedFeature = .posters

            case let .editEvent(eventID):
                guard eventID == self.eventID else { return }
                self.selectedFeature = .edit
                if self.editEvent == nil {
                    self.editEvent = Spawn(EditEvent.State(eventID: eventID))
                }

            case let .editEventInfo(eventID):
                guard eventID == self.eventID else { return }
                self.selectedFeature = .about
                if self.eventInfoViewer == nil {
                    self.eventInfoViewer = Spawn(EventInfoViewer.State(eventID: eventID))
                }
                self.eventInfoViewer?.state.destination = .editEventInfo(
                    Spawn(EditEventInfo.State(eventID: eventID))
                )

            case let .eventSettings(eventID):
                guard eventID == self.eventID else { return }
                self.selectedFeature = .settings
                if self.eventSettings == nil {
                    self.eventSettings = Spawn(EventSettings.State(eventID: eventID))
                }
            }
        }

        private func withEventDependencies<Value>(_ operation: () -> Value) -> Value {
            let eventID = self.eventID
            let eventTimeZone = self.eventTimeZone
            let sourceEditingSession = self.sourceEditingSession
            return withDependencies {
                $0.defaultEventID = eventID
                $0.defaultEventTimeZone = eventTimeZone
                if let sourceEditingSession {
                    $0.defaultDatabase = sourceEditingSession.database
                    $0.sourceEditingSession = sourceEditingSession
                }
            } operation: {
                operation()
            }
        }

        private static func eventTimeZone(
            eventID: OMERecord.Event.ID,
            sourceEditingSession: SourceEditingSession?
        ) -> TimeZone {
            @Dependency(\.defaultDatabase) var database
            let activeDatabase = sourceEditingSession?.database ?? database
            return (
                try? activeDatabase.read { db in
                    try OMERecord.Event
                        .where { $0.id.eq(eventID) }
                        .fetchOne(db)?
                        .timeZone
                }
            ) ?? .current
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
        .onEvent(EventEditingRequested.self) { intent, state in
            state.handleEditingIntent(intent)
        }
        .onEvent(SourceDataRefreshRequested.self) { request, state in
            guard request.eventID == state.eventID else { return }
            store.addTask(id: sourceDataRefreshTask) {
                let result: Void? = await store.withErrorHandling(
                    fallbackMessage: .sourceDataRefreshFailed,
                    operation: .sourceDataRefresh
                ) {
                    try await sourceDataRefresh.refresh(request.sourceBaselineID)
                }
                guard result != nil else { return }
                try store.modify {
                    $0.reloadAfterSourceDataRefresh()
                }
            }
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
        .dependency(\.defaultEventTimeZone, store.eventTimeZone)
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
        @State var tabLayout = TabFeatureLayout()

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
