import SwiftUI
import SharingGRDB
import CoreModels

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

            do {
                @FetchOne(MusicEvent?.find(id))
                var musicEvent: MusicEvent? = nil

                try await $musicEvent.sharedReader.load()

                if let event = musicEvent {
                    try await withDependencies {
                        $0.musicEventID = self.id
                    } operation: { @MainActor in
                        @FetchAll(Current.artists) var artists
                        @FetchAll(Current.stages) var stages
                        @FetchAll(Current.schedules) var schedules

                        try await withThrowingTaskGroup {
                            $0.addTask { try await FetchAll(Current.stages).load() }
                            $0.addTask { try await FetchAll(Current.artists).load() }
                            $0.addTask { try await FetchAll(Current.schedules).load() }
                            $0.addTask { try await self.imagePrefetchClient.prefetchStageImages() }

                            try await $0.waitForAll()
                        }

                        // Unstructured Task so that we don't wait on artist images.
                        // A little bit of loading there is better than a lot of loading now.
                        Task {
                            try? await imagePrefetchClient.prefetchArtistImages()
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
        self.artists = ArtistsList()
        self.more = MoreTabFeature()

        self.shouldShowArtistImages = !artists.compactMap { $0.imageURL }.isEmpty

        if !schedules.isEmpty {
            self.schedule = ScheduleFeature()
        }

        if !event.contactNumbers.isEmpty {
            self.contactInfo = ContactInfoFeature()
        }

        if let location = event.location {
            self.location = LocationFeature(location: location)
        }

        self._event = FetchOne(wrappedValue: event, MusicEvent.find(event.id))
    }


    @ObservationIgnored
    @FetchOne
    var event: MusicEvent

//    public var orgLoader = OrganizerLoader()

//    @SharedReader(.appStorage("selectedFeature"))
    public var selectedFeature: Feature = .schedule

    public var schedule: ScheduleFeature?
    public var artists: ArtistsList
    public var location: LocationFeature?
    public var contactInfo: ContactInfoFeature?
    var more: MoreTabFeature

    var shouldShowArtistImages: Bool = true

    func onAppear() async {
        await withErrorReporting {
            try await $event.load()
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
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(MusicEventFeatures.Feature.schedule)
            }

            NavigationSplitView {
                ArtistsListView(store: store.artists)
            } detail: {
                Text("Select an Artist")
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
