import  SwiftUI; import SkipFuse
// import SharingGRDB
import GRDB
import CoreModels
import Dependencies
import IssueReporting


struct MusicEventViewer: View {
    @Observable
    @MainActor
    class Model {
        init(eventID: MusicEvent.ID) {
            self.id = eventID
        }

        var id: MusicEvent.ID
        var eventFeatures: MusicEventFeatures?
        var isLoading: Bool { eventFeatures == nil }

        @ObservationIgnored
        @Dependency(\.imagePrefetchClient) var imagePrefetchClient
        

        func onAppear() async {
            @Dependency(\.defaultDatabase) var database
            self.eventFeatures = nil

            let musicEventID = self.id
            do {
                // Load MusicEvent from database using GRDB
                let musicEvent = try await database.read { db in
                    try MusicEvent.fetchOne(db, id: musicEventID)
                }

                if let event = musicEvent {
                    try await withDependencies {
                        $0.musicEventID = musicEventID
                    } operation: { @MainActor in

                        let (artists, stages, schedules) = try await database.read { db in
                            let artists = try Current.artists.fetchAll(db)
                            let stages = try Current.stages.fetchAll(db)
                            let schedules = try Schedule
                                .filter(Column("musicEventID") == musicEventID)
                                .order(Column("startTime"))
                                .fetchAll(db)

                            return (artists, stages, schedules)
                        }

                        self.eventFeatures = MusicEventFeatures(
                            event,
                            artists: artists,
                            stages: stages,
                            schedules: schedules
                        )
                    }
                }
            } catch {
                reportIssue(error)
            }
        }
    }

    let store: Model
    public init(store: Model) {
        self.store = store
    }

    var body: some View {
        ZStack {
            AnimatedMeshView()
                .ignoresSafeArea()

            if let eventFeatures = store.eventFeatures {
                MusicEventFeaturesView(store: eventFeatures)
            }
        }
        .animation(.default, value: store.isLoading)
        .task(id: store.id) {
            await store.onAppear()
        }
    }
}



enum MusicEventIDDependencyKey: DependencyKey {
    static let liveValue: MusicEvent.ID = .init("-1")
}

extension DependencyValues {
    var musicEventID: MusicEvent.ID {
        get {
            self[MusicEventIDDependencyKey.self]
        }
        set { self[MusicEventIDDependencyKey.self] = newValue }
    }
}

@MainActor
@Observable
public class MusicEventFeatures: Identifiable {
    public enum Feature: String, Hashable, Codable, Sendable {
        case schedule, artists, contactInfo, communications, siteMap, location, explore, workshops, notifications, about, more
    }

    public init(
        _ event: MusicEvent,
        artists: [Artist],
        stages: [Stage],
        schedules: [Schedule]
    ) {
        @Dependency(\.musicEventID) var musicEventID

        self.artists = ArtistsList()
        self.communications = CommunicationsFeatureView.Store()
        self.notifications = NotificationPreferencesView.Store()

        self.shouldShowArtistImages = true

        if !schedules.isEmpty {
            self.schedule = ScheduleFeature()
        }

        if !event.contactNumbers.isEmpty {
            self.contactInfo = ContactInfoFeature()
        }

        if let location = event.location {
            self.location = LocationFeature(location: location)
        }


        self.event = event
    }


    var event: MusicEvent
    
    public var selectedFeature: Feature = .schedule

    public var schedule: ScheduleFeature?
    public var artists: ArtistsList
    public var location: LocationFeature?
    public var contactInfo: ContactInfoFeature?
    public var communications: CommunicationsFeatureView.Store?
    public var notifications: NotificationPreferencesView.Store?

    var shouldShowArtistImages: Bool = true
    var isLoadingOrganizer: Bool = false
    var errorMessage: String?

    func onAppear() async {
        NotificationCenter.default.addObserver(
            forName: .userSelectedToViewArtist,
            object: nil,
            queue: .main
        ) { notification in
            guard let artistID = notification.userInfo?["eventID"] as? Artist.ID else {
                reportIssue("Posted notification: selectedEventID did not contain eventID")
                return
            }
            MainActor.assumeIsolated {
                self.handleSelectedArtistIDNotification(artistID)
            }
        }
    }

    func didTapReloadOrganizer() async {
        guard let currentOrganizerID = event.organizerURL
        else { return }
        self.errorMessage = nil

        self.isLoadingOrganizer = true

        do {
            try await downloadAndStoreOrganizer(from: .url(currentOrganizerID))
            self.isLoadingOrganizer = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoadingOrganizer = true

        }
    }

    func didTapExitEvent() {
        NotificationCenter.default.post(name: .userRequestedToExitEvent, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func handleSelectedArtistIDNotification(_ artistID: Artist.ID) {
        self.selectedFeature = .artists
    }
}


// Step 1: Create a unique notification name
extension Notification.Name {
    static let userSelectedToViewArtist = Notification.Name("requestedToViewArtist")
}


public struct MusicEventFeaturesView: View {
    public init(store: MusicEventFeatures) {
        self.store = store
    }

    @Bindable var store: MusicEventFeatures

    public var body: some View {
        TabView(selection: $store.selectedFeature) {
            if let schedule = store.schedule {
                NavigationStack {
                    ScheduleView(store: schedule)
                }
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
                .tag(MusicEventFeatures.Feature.schedule)
            }

            NavigationStack {
                ArtistsListView(store: store.artists)
            }
            .tabItem {
                Label("Artists", systemImage: "person.3")
            }
            .tag(MusicEventFeatures.Feature.artists)

            if let communications = store.communications {
                NavigationStack {
                    CommunicationsFeatureView(store: communications)
                }
                .tabItem {
                    Label("Communication", systemImage: "megaphone")
                }
                .tag(MusicEventFeatures.Feature.communications)
            }

            if let location = store.location {
                NavigationStack {
                    LocationView(store: location)
                }
                .tabItem {
                    #if os(iOS)
                    Label("Location", systemImage: "mappin")
                    #elseif os(Android)
                    Label("Location", systemImage: "mappin.circle")
                    #endif
                }
                .tag(MusicEventFeatures.Feature.location)
            }

            NavigationStack {
                MoreView(store: store)
            }
            .tabItem { Label("More", systemImage: "ellipsis") }
            .tag(MusicEventFeatures.Feature.more)

//            if let workshops = store.workshops {
//                NavigationStack {
//                    Text("TODO: Workshops")
//                }
//                .tabItem { Label("Workshops", systemImage: "figure.mind.and.body") }
//                .tag(MusicEventFeatures.Feature.workshops)
//            }
//
//            if let siteMap = store.siteMap {
//                NavigationStack {
//                    Text("TODO: Site Map")
//                }
//                .tabItem { Label("Site Map", systemImage: "map") }
//                .tag(MusicEventFeatures.Feature.siteMap)
//            }

//
//            NavigationStack {
//                Text("TODO: Notifications")
//            }
//            .tabItem { Label("Notifications", systemImage: Icons.notifications) }
//            .tag(MusicEventFeatures.Feature.notifications)
        }
        .onAppear { Task { await store.onAppear() }}
        .environment(\.showArtistImages, store.shouldShowArtistImages)
    }
}

struct MoreView: View {
    let store: MusicEventFeatures

    var body: some View {
        List {
            if let notifications = store.notifications {
                Feature(.notifications) {
                    NotificationPreferencesView(store: notifications)
                } label: {
                    Label("Notifications", systemImage: "bell")
                }
            }
            
            if let contactInfo = store.contactInfo {
                Feature(.contactInfo) {
                    ContactInfoView(store: contactInfo)
                } label: {
                    Label("Contact Info", systemImage: "phone")
                }
            }

            Feature(.about) {
                AboutAppView(store: store)
            } label: {
                Label("About", systemImage: "info.circle")
            }

        }
        .navigationTitle("More")
        .environment(\.featureLocation, .more)
    }
}


enum FeatureLocation {
    case tabBar
    case more
}

enum FeatureLocationEnvironmentKey: EnvironmentKey {
    static let defaultValue: FeatureLocation = .tabBar
}

extension EnvironmentValues {
    var featureLocation: FeatureLocation {
        get {
            self[FeatureLocationEnvironmentKey.self]
        } set {
            self[FeatureLocationEnvironmentKey.self] = newValue
        }
    }
}

struct Feature<FeatureView: View, FeatureLabelView: View>: View {

    @Environment(\.featureLocation) var location: FeatureLocation

    var tag: MusicEventFeatures.Feature

    var label: FeatureLabelView
    var feature: FeatureView

    init(_ tag: MusicEventFeatures.Feature, @ViewBuilder feature: () -> FeatureView, @ViewBuilder label: () -> FeatureLabelView) {
        self.tag = tag
        self.label = label()
        self.feature = feature()
    }

    var body: some View {
        switch location {
        case .tabBar:
            NavigationStack {
                feature
            }
            .tabItem { label }
            .tag(tag)
        case .more:
            NavigationLink {
                feature
            } label: {
                label
            }
        }
    }
}



struct AboutAppView: View {
    let store: MusicEventFeatures
    var body: some View {
        List {
            Section(store.event.name) {
                Button {
                    Task {
                        await store.didTapReloadOrganizer()
                    }
                } label: {
                    VStack(alignment: .leading) {
                        HStack {
                            Label("Update to the newest schedule", systemImage: "arrow.clockwise")
                            Spacer()
                            if store.isLoadingOrganizer {
                                ProgressView()
                            }
                        }

                        if let errorMessage = store.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Button("Exit and see previous events", systemImage: "door.left.hand.open") {
                    store.didTapExitEvent()
                }
            }

            Section("Open Music Event") {
                Text("""
                OME (Open Music Event) is designed to help festival attendees effortlessly get access to information that they need during an event. The main goal of this project is to give concert and festival goers a simple, intuitive way to get information about events they are attending.
                
                The secondary goal is providing a free and open source way for event organizers to create, maintain and update information about their event.
                
                If you have any suggestions or discover any issues, please start a discussion and they will be addressed as soon as possible.
                """)

                Link(destination: URL(string: "https://github.com/woodymelling/open-music-event")!) {
                    Label("GitHub", systemImage: "link")
                }

                Link(destination: URL(string: "https://github.com/woodymelling/open-music-event/issues/new")!) {
                    Label("Report an Issue", systemImage: "exclamationmark.bubble")
                }

                Link(destination: URL(string: "https://github.com/woodymelling/open-music-event/issues/new")!) {
                    Label("Suggest a feature", systemImage: "plus.bubble")
                }
            }
        }
        .navigationTitle("About")
    }
}

//
//#Preview("About App") {
//
//    prepareDependencies {
//        $0.defaultDatabase = try! appDatabase()
//    }
//
//    return NavigationStack {
//        AboutAppView(store: .init())
//    }
//}
