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
        var isLoading: Bool = false

        @ObservationIgnored
        @Dependency(\.imagePrefetchClient) var imagePrefetchClient
        

        func onAppear() async {
            @Dependency(\.defaultDatabase) var database
            self.eventFeatures = nil
            self.isLoading = true
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
                        let (organizer, artists, stages, schedules) = try await database.read { db in
                            let organizer = try Organizer.fetchOne(db, id: event.organizerID)
                            let artists = try Current.artists.fetchAll(db)
                            let stages = try Current.stages.fetchAll(db)
                            let schedules = try Schedule
                                .filter(Column("musicEventID") == musicEventID)
                                .order(Column("startTime"))
                                .fetchAll(db)

                            return (organizer, artists, stages, schedules)
                        }

                        guard let organizer
                        else { reportIssue(); return }

                        self.eventFeatures = MusicEventFeatures(
                            event,
                            organizer,
                            artists: artists,
                            stages: stages,
                            schedules: schedules
                        )
                        self.isLoading = false
                    }
                }
            } catch {
                reportIssue(error)
            }
        }

        func didTapReload() async {
            await self.onAppear()
        }
    }

    let store: Model
    public init(store: Model) {
        self.store = store
    }

    var body: some View {
        ZStack {
            if let eventFeatures = store.eventFeatures {
                MusicEventFeaturesView(store: eventFeatures)
            }

            if store.isLoading {
                LoadingScreen()
                    .transition(.opacity)
            }
        }
        .animation(.easeIn(duration: 0.5), value: store.eventFeatures == nil)
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


    var event: MusicEvent
    var organizer: Organizer

    public var selectedFeature: Feature = .schedule

    public var schedule: ScheduleFeature?
    public var workshopsSchedule: ScheduleFeature?
    public var artists: ArtistsList
    public var location: LocationFeature?
    public var contactInfo: ContactInfoFeature?
    public var communications: CommunicationsFeatureView.Store?
    public var notifications: NotificationPreferencesView.Store?

    var shouldShowArtistImages: Bool = true
    var isLoadingOrganizer: Bool = false
    var errorMessage: String?

    @ObservationIgnored
    @Dependency(\.musicEventID) var musicEventID

    @ObservationIgnored
    @Dependency(\.defaultDatabase) var database


    @ObservationIgnored
    @Dependency(\.calendar) var calendar


    public init(
        _ event: MusicEvent,
        _ organizer: Organizer,
        artists: [Artist],
        stages: [Stage],
        schedules: [Schedule]
    ) {
        @Dependency(\.musicEventID) var musicEventID
        self.organizer = organizer

        self.artists = ArtistsList()
        self.communications = CommunicationsFeatureView.Store()
        self.notifications = NotificationPreferencesView.Store()

        self.shouldShowArtistImages = true

        if !schedules.isEmpty {
            self.schedule = ScheduleFeature(category: nil)
            self.workshopsSchedule = ScheduleFeature(category: "workshop")
        }

        if !event.contactNumbers.isEmpty {
            self.contactInfo = ContactInfoFeature()
        }

        if let location = event.location {
            self.location = LocationFeature(location: location)
        }


        self.event = event
    }

    func onAppear() async {
        NotificationCenter.default.addObserver(
            forName: .userSelectedToViewArtist,
            object: nil,
            queue: .main
        ) { notification in
            guard case .some(.viewArtist(let artistID)) = notification.info else {
                reportIssue("Posted notification: userSelectedToViewArtist did not contain valid artistID")
                return
            }
            MainActor.assumeIsolated {
                self.handleSelectedArtistIDNotification(artistID)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .userSelectedToViewPost,
            object: nil,
            queue: .main
        ) { notification in
            guard case .some(.viewPost(let channelID, let postID)) = notification.info else {
                reportIssue("Posted notification: userSelectedToViewPost did not contain valid channelID and postID")
                return
            }
            Task { @MainActor in
                await self.handleSelectedPostNotification(channelID: channelID, stub: postID)
            }
        }
    }

    func didTapReloadOrganizer() async {
        self.errorMessage = nil

        self.isLoadingOrganizer = true

        do {
            try await downloadAndStoreOrganizer(from: .url(organizer.url))
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
        self.artists.destination = .init(artistID: artistID)
    }

    private func handleSelectedPostNotification(channelID: CommunicationChannel.ID, stub: CommunicationChannel.Post.Stub) async {

        await withErrorReporting {
            let post = try await database.read { db in
                try CommunicationChannel.Post
                    .filter(Column("channelID") == channelID)
                    .filter(Column("stub") == stub)
                    .fetchOne(db)
            }

            await MainActor.run {
                self.selectedFeature = .communications

                self.communications?.destination = .init(channelID)

                self.communications?.destination?.destination = post
            }
        }
    }
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
                    Label("Schedule", image: Icons.calendar)
                }
                .tag(MusicEventFeatures.Feature.schedule)
            }

            if let workshopsSchedule = store.workshopsSchedule {
                NavigationStack {
                    ScheduleView(store: workshopsSchedule)
                        .environment(\.dayStartsAtNoon, false)
                }
                .tabItem {
                    Label {
                        Text("Workshops")
                    } icon: {
                        Icons.selfImprovement
                    }
                }
                .tag(MusicEventFeatures.Feature.workshops)
            }

            NavigationStack {
                ArtistsListView(store: store.artists)
            }
            .tabItem {
                Label {
                    Text("Artists")
                } icon: {
                    Icons.person3
                }
            }
            .tag(MusicEventFeatures.Feature.artists)

            if let communications = store.communications {
                NavigationStack {
                    CommunicationsFeatureView(store: communications)
                }
                .tabItem {
                    Label {
                        Text("Updates")
                    } icon: {
                        Icons.megaphone
                    }
                }
                .tag(MusicEventFeatures.Feature.communications)
            }

            NavigationStack {
                MoreView(store: store)
            }
            .tabItem { Label("More", image: Icons.ellipsis) }
            .tag(MusicEventFeatures.Feature.more)
//            if let workshops = store.workshops {
//                NavigationStack {
//                    Text("TODO: Workshops")
//                }
//                .tabItem { Label("Workshops", systemImage: "figure.mind.and.body") }
//                .tag(MusicEventFeatures.Feature.workshops)
//            }
//

//
//            NavigationStack {
//                Text("TODO: Notifications")
//            }
//            .tabItem { Label("Notifications", systemImage: Icons.notifications) }
//            .tag(MusicEventFeatures.Feature.notifications)
        }
        .task { await store.onAppear() }
        .environment(\.showArtistImages, store.shouldShowArtistImages)
        .environment(\.calendar, {
            var calendar = Calendar.current
            calendar.timeZone = store.event.timeZone
            return calendar
        }())
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
                    Label("Notifications", image: Icons.bell)
                }
            }

            Section {
                if let contactInfo = store.contactInfo {
                    Feature(.contactInfo) {
                        ContactInfoView(store: contactInfo)
                    } label: {
                        Label("Contact Info", image: Icons.phone)
                    }
                }

                if let location = store.location {
                    Feature(.location) {
                        LocationView(store: location)
                    } label: {
    #if os(iOS)
                        Label("Location", image: Icons.mappin)
    #elseif os(Android)
                        Label("Location", image: Icons.mappinCircle)
    #endif
                    }
                }

                if let siteMapURL = store.event.siteMapImageURL {
                    Feature(.siteMap) {
                        SiteMapImageView(siteMapURL: siteMapURL)
                    } label: {
                        Label("Site Map", image: Icons.map)
                    }
                }

            }

            Section {
                Feature(.about) {
                    AboutAppView(store: store)
                } label: {
                    Label("About", image: Icons.infoCircle)
                }
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



#if SKIP

#endif

struct SiteMapImageView: View {
    var siteMapURL: URL

    var body: some View {
        ZStack {
            #if os(Android)
            ComposeView { SiteMapComposer(siteMapURL: siteMapURL) }
                .background {
                    Color.black
                }
            #else
            CachedAsyncImage(url: siteMapURL, contentMode: .fit)
                ._zoomable()
                .background {
                    Color.black
                }
            #endif
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

}

#if SKIP
import me.saket.telephoto.zoomable.coil3.ZoomableAsyncImage
import coil3.request.ImageRequest
import coil3.request.CachePolicy
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.fillMaxSize

struct SiteMapComposer : ContentComposer {
    let siteMapURL: URL

    // SKIP @nobridge
    let logger = Logger(subsystem: "bundle.ome.OpenMusicEvent", category: "SiteMap")

    @Composable func Compose(context: ComposeContext) {
        let context = LocalContext.current
        let imageRequest = ImageRequest.Builder(context)
            .data(siteMapURL.absoluteString)
            .diskCachePolicy(CachePolicy.ENABLED)
            .memoryCachePolicy(CachePolicy.ENABLED)
            .listener(
                onStart = { _ in
                    logger.info("Loading site map image: \(siteMapURL.absoluteString)")
                },
                onSuccess = { _, _ in 
                    logger.info("Site map image loaded successfully")
                },
                onError = { _, error in
                    logger.error("Site map image load error: \(error.throwable.message ?? "Unknown error")")
                }
            )
            .build()
        
        ZoomableAsyncImage(
            model: imageRequest,
            contentDescription: "Site Map",
            modifier: Modifier.fillMaxSize()
        )
    }
}
#endif

enum FeatureLocationEnvironmentKey: EnvironmentKey {
    static let defaultValue: FeatureLocation = .tabBar
}

#if canImport(UIKit)

#endif
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
