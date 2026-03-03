import  SwiftUI; import SkipFuse
// import SharingGRDB
import GRDB
import CoreModels
import Dependencies
import IssueReporting

@MainActor
@Observable
class MusicEventViewer: Identifiable {
    init(eventID: MusicEvent.ID) {
        self.id = eventID
    }

    let id: MusicEvent.ID

    var isLoading = false
    var eventFeatures: MusicEventFeatures?

    @ObservationIgnored
    @Dependency(\.imagePrefetchClient) var imagePrefetchClient

    @ObservationIgnored
    @Dependency(\.defaultDatabase) var database


    @ObservationIgnored
    @Dependency(\.musicEventID) var musicEventID

    func task() async {
        self.isLoading = true
        await self.loadData()
        self.isLoading = false
    }

    func loadData() async {
        self.eventFeatures = withDependencies(from: self) {
            $0.musicEventID = musicEventID
        } operation: { @MainActor in
            return MusicEventFeatures(
                features: [
                    .posters,
                    .schedule,
                    .artists,
                    .communications,
                    .contactInfo,
                    .location,
                    .siteMap,
                    .notifications
                ]
            )
        }
    }

    func didTapReload() async {
//        await self.onAppear()
    }
}


struct MusicEventView: View {

    let store: MusicEventViewer

    public init(store: MusicEventViewer) {
        self.store = store
    }

    var body: some View {
        Group {
            if !store.isLoading, let eventFeatures = store.eventFeatures {
                MusicEventFeaturesView(store: eventFeatures)
            } else {
                LoadingScreen("Music Event Viewer")
            }
        }
        .environment(\.defaultDatabase, {
            print(store.database)
            return store.database
        }())
        .animation(.easeIn(duration: 0.5), value: store.eventFeatures == nil)
        .task {
            await store.task()
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

enum OrganizerIDDependencyKey: DependencyKey {
    static let liveValue: Organizer.ID = .init("-1")
}

extension DependencyValues {
    var organizerID: Organizer.ID {
        get {
            self[OrganizerIDDependencyKey.self]
        }
        set { self[OrganizerIDDependencyKey.self] = newValue }
    }
}

@MainActor
@Observable
public class MusicEventFeatures: Identifiable {
    public enum Feature: String, Hashable, Codable, Sendable {
        case schedule, artists, contactInfo, communications, siteMap, location, explore, workshops, notifications, about, more, edit, posters
    }

    var event: MusicEvent?
    public var selectedFeature: Feature = .communications

    public var schedule: ScheduleFeature?
    public var workshopsSchedule: ScheduleFeature?
    public var artists: ArtistsList?
    public var location: LocationFeature?
    public var contactInfo: ContactInfoFeature?
    public var communications: CommunicationsFeatureView.Store?
    public var notifications: NotificationPreferencesView.Store?
    public var edits: EditsFeature?
    public var siteMap: SiteMapFeature?
    public var posters: PostersFeature?

    var shouldShowArtistImages: Bool = true
    var isLoadingOrganizer: Bool = false
    var errorMessage: String?

    @ObservationIgnored
    @Dependency(\.musicEventID) var musicEventID

    @ObservationIgnored
    @Dependency(\.defaultDatabase) var database


    @ObservationIgnored
    @Dependency(\.calendar) var calendar

    init(features: [Feature]) {
        let musicEventID = musicEventID

        for feature in features {
            switch feature {
            case .schedule:
                self.schedule = ScheduleFeature(category: nil)

            case .workshops:
                self.workshopsSchedule = ScheduleFeature(category: "workshop")

            case .artists:
                self.artists = ArtistsList()

            case .contactInfo:
                self.contactInfo = ContactInfoFeature()

            case .communications:
                self.communications = CommunicationsFeatureView.Store()

            case .siteMap:
                self.siteMap = SiteMapFeature()

            case .location:
                self.location = LocationFeature()

            case .explore:
                break

            case .notifications:
                self.notifications = NotificationPreferencesView.Store()

            case .about:
                break

            case .more:
                break

            case .edit:
                self.edits = EditsFeature()

            case .posters:
                self.posters = PostersFeature()
            }
        }
    }


    func onAppear() async {
//        NotificationCenter.default.addObserver(
//            forName: .userSelectedToViewArtist,
//            object: nil,
//            queue: .main
//        ) { notification in
//            guard case .some(.viewArtist(let artistID)) = notification.info else {
//                reportIssue("Posted notification: userSelectedToViewArtist did not contain valid artistID")
//                return
//            }
//            MainActor.assumeIsolated {
//                self.handleSelectedArtistIDNotification(artistID)
//            }
//        }
//
//        NotificationCenter.default.addObserver(
//            forName: .userSelectedToViewPost,
//            object: nil,
//            queue: .main
//        ) { notification in
//            guard case .some(.viewPost(let channelID, let postID)) = notification.info else {
//                reportIssue("Posted notification: userSelectedToViewPost did not contain valid channelID and postID")
//                return
//            }
//            Task { @MainActor in
//                await self.handleSelectedPostNotification(channelID: channelID, stub: postID)
//            }
//        }
    }

    func didTapReloadOrganizer() {
        unimplemented()
    }

    func didTapExitEvent() {
        @Dependency(\.userPreferencesDatabase) var userPrefsDatabase

        withAnimation {
            withErrorReporting {
                try userPrefsDatabase.write { db in

                    try db.execute(
                        sql: """
                            UPDATE \(AppState.databaseTableName)
                            SET selectedEventID = NULL;
                        """,
                        arguments: []
                    )
                }
            }
        }

    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func handleSelectedArtistIDNotification(_ artistID: Artist.ID) {
        self.selectedFeature = .artists
        self.artists?.destination = .init(artistID: artistID)
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

                let channelFeature = CommunicationChannelView.Store(channelID)
                channelFeature.destination = post.map { .post($0) }

                self.communications?.destination = .channel(channelFeature)

            }
        }
    }

    var showingEdit: Bool {
        true
    }
}



// MARK: View
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

            if let artists = store.artists {
                NavigationStack {
                    ArtistsListView(store: artists)
                }
                .tabItem {
                    Label {
                        Text("Artists")
                    } icon: {
                        Icons.person3
                    }
                }
                .tag(MusicEventFeatures.Feature.artists)
            }

            if let communications = store.communications {
                NavigationStack {
                    CommunicationsFeatureView(store: communications)
                }
                .tabItem {
                    Label {
                        Text("Comms")
                    } icon: {
                        Icons.megaphone
                    }
                }
                .tag(MusicEventFeatures.Feature.communications)
            }


            if let edits = store.edits {
                NavigationStack {
                    EditsView(store: edits)
                }
            }

            NavigationStack {
                MoreView(store: store)
            }
            .tabItem { Label("More", image: Icons.ellipsis) }
            .tag(MusicEventFeatures.Feature.more)
        }
        .task { await store.onAppear() }
        .environment(\.showArtistImages, store.shouldShowArtistImages)
        .environment(\.calendar, {
            var calendar = Calendar.current
            if let event = store.event {
                calendar.timeZone = event.timeZone
            }
            return calendar
        }())
    }
}

#if os(Android)
extension EnvironmentValues {
    enum CalendarEnvironmentKey: EnvironmentKey {
        static let defaultValue = Calendar.autoupdatingCurrent
    }

    /// The current calendar that views should use when handling dates.
    public var calendar: Calendar {
        get { self[CalendarEnvironmentKey.self] }
        set { self[CalendarEnvironmentKey.self] = newValue }
    }
}
#endif

// MARK: MORE
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
                if let store = store.posters {
                    Feature(.posters) {
                        PostersFeatureView(store: store)
                    } label: {
                        Label("Posters", image: Icons.posters)
                    }
                }

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

                if let siteMapFeature = store.siteMap {
                    Feature(.siteMap) {
                        SiteMapView(store: siteMapFeature)
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


//            if store.showingEdit {
//                Feature(.edit) {
//                    EditsView()
//                } label: {
//                    Label("Edit", image: Icons.infoCircle)
//                }
//            }


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


@Observable
@MainActor
public class SiteMapFeature {

    @ObservationIgnored
    @Dependency(\.defaultDatabase) var defaultDatabase

    @ObservationIgnored
    @Dependency(\.musicEventID) var musicEventID

    public var siteMapImageURL: URL?

    public func task() async {
        let musicEventID = self.musicEventID
        let query = ValueObservation.tracking { db in
            try MusicEvent
                .fetchOne(db, id: musicEventID)?
                .siteMapImageURL
        }

        await withErrorReporting {
            for try await imageURL in query.values(in: defaultDatabase) {
                self.siteMapImageURL = imageURL
            }
        }
    }
}


struct SiteMapView: View {

    let store: SiteMapFeature

    var body: some View {
        Group {
            if let siteMapURL = store.siteMapImageURL {
                SiteMapImageView(siteMapURL: siteMapURL)
            } else {
                ProgressView()
            }
        }
        .task { await store.task() }
    }
}

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
        #if !os(macOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
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

