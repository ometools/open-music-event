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
                            let schedules = try Current.schedules.fetchAll(db)

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
    static let liveValue: MusicEvent.ID = .init(-1)
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
        case schedule, artists, contactInfo, siteMap, location, explore, workshops, notifications, more
    }

    public init(
        _ event: MusicEvent,
        artists: [Artist],
        stages: [Stage],
        schedules: [Schedule]
    ) {
        @Dependency(\.musicEventID) var musicEventID


        self.artists = ArtistsList()
        self.more = MoreTabFeature()

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
    var more: MoreTabFeature

    var shouldShowArtistImages: Bool = true

    func onAppear() async {
        // Event is already loaded in MusicEventViewer.Model.onAppear()
        // No additional loading needed here
    }
}

public struct MusicEventFeaturesView: View {
    public init(store: MusicEventFeatures) {
        self.store = store
    }

    @Bindable var store: MusicEventFeatures

    public var body: some View {
        TabView(selection: $store.selectedFeature) {
//            if let schedule = store.schedule {
//                NavigationStack {
//                    ScheduleView(store: schedule)
//                }
//                .tabItem { Label("Schedule", systemImage: "calendar") }
//                .tag(MusicEventFeatures.Feature.schedule)
//            }
//
            NavigationStack {
                ArtistsListView(store: store.artists)
            }
            .tabItem { Label("Artists", systemImage: "person.3") }
            .tag(MusicEventFeatures.Feature.artists)

            if let contactInfo = store.contactInfo {
                NavigationStack {
                    ContactInfoView(store: contactInfo)
                }
                .tabItem { Label("Contact Info", systemImage: "phone") }
                .tag(MusicEventFeatures.Feature.contactInfo)
            }

            if let location = store.location {
                NavigationStack {
                    LocationView(store: location)
                }
                #if os(iOS)
                .tabItem { Label("Location", systemImage: "mappin") }
                #elseif os(Android)
                .tabItem { Label("Location", systemImage: "mappin.circle")}
                #endif
                .tag(MusicEventFeatures.Feature.location)
            }

            NavigationStack {
                MoreView(store: store.more)
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
