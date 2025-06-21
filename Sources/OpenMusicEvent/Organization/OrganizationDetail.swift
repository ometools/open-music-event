//
//  OrganizerDetails.swift
//  event-viewer
//
//  Created by Woodrow Melling on 3/25/25.
//

import Foundation
import Observation
import SwiftUI
import Dependencies
import Logging
import ImageCaching
import SharingGRDB
import CoreModels

public struct OrganizerDetailView: View {
    public init(url: Organizer.ID) {
        self.store = ViewModel(url: url)
    }

    public init(store: ViewModel) {
        self.store = store
    }
    
    @Observable
    @MainActor
    public class ViewModel {
        let logger = Logger(subsystem: "open-music-event.event-viewer", category: "OrganizerDetails")

        public init(url: Organizer.ID) {
            self.id = url

            _organizer = FetchOne(wrappedValue: nil, Organizer?.find(id))
            _events = FetchAll(
                MusicEvent
                    .where { $0.organizerURL == id }
                    .order { $0.startTime.desc(nulls: .last)  }
            )
        }

        public let id: Organizer.ID

        @ObservationIgnored
        @FetchOne
        public var organizer: Organizer?

        @ObservationIgnored
        @FetchAll
        var events: [MusicEvent]

        public var showingLoadingScreen: Bool = false

        public func didTapEvent(id: MusicEvent.ID) {
            logger.info("didTapEvent: \(id.rawValue)")
            NotificationCenter.default.post(
                name: .userSelectedToViewEvent,
                object: nil,
                userInfo: [
                    "eventID": id
                ]
            )
        }

        public func onPullToRefresh() async  {
            await withErrorReporting {
                try await downloadAndStoreOrganizer(from: .url(self.id))
            }
        }

        public func onAppear() async {
            try? await $organizer.load()
            if organizer == nil {
                await withErrorReporting {
                    self.showingLoadingScreen = true
                    try await downloadAndStoreOrganizer(from: .url(self.id))

                    try await withThrowingTaskGroup {
                        if let orgImageURL = organizer?.imageURL {
                            $0.addTask {
                                _ = try await ImagePipeline.images.image(for: orgImageURL)
                            }
                        }

                        for event in events {
                            if let imageURL = event.imageURL {
                                $0.addTask {
                                    _ = try await ImagePipeline.images.image(for: imageURL)
                                }
                            }
                        }

                        try await $0.waitForAll()
                    }

                    self.showingLoadingScreen = false
                }
            }
        }
    }

    @Bindable var store: ViewModel
    @Environment(\.loadingScreenImage) var loadingScreenImage

    public var body: some View {
        Group {
            ZStack {
                if let organizer = store.organizer, !store.showingLoadingScreen {
                    StretchyHeaderList(
                        title: Text(organizer.name),
                        stretchyContent: {
                            Organizer.ImageView(organizer: organizer)
                        },
                        listContent: {
                            EventsListView(events: store.events) { eventID in
                                store.didTapEvent(id: eventID)
                            }

                        }
                    )
                    .refreshable { await store.onPullToRefresh() }
                    .listStyle(.plain)
                }

                if store.showingLoadingScreen {
                    AnimatedMeshView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Material.ultraThin)
                        .ignoresSafeArea()
                }

                if let image = loadingScreenImage, store.showingLoadingScreen {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(80)
                        .transition(Twirl())
                }
            }
        }
        .task { await store.onAppear() }
        .animation(.default, value: store.organizer == nil)
        .animation(.default, value: store.showingLoadingScreen)
    }

    struct EventsListView: View {
        var events: [MusicEvent]
        var onTapEvent: (MusicEvent.ID) -> Void


        @Environment(\.date) var date

        var previousEvents: [MusicEvent] {
            events.filter { event in
                if let endTime = event.endTime {
                    endTime < date()
                } else {
                    true
                }
            }
        }

        var upcomingEvents: [MusicEvent] {
            events.filter { event in
                if let startTime = event.startTime {
                    startTime > date()
                } else {
                    true
                }
            }
        }

        var body: some View {
            if !upcomingEvents.isEmpty {
                Section("Upcoming Events") {
                    ForEach(upcomingEvents) { event in
                        NavigationLinkButton {
                            onTapEvent(event.id)
                        } label: {
                            EventRowView(event: event)
                        }
                    }
                }
            }

            if !previousEvents.isEmpty {
                Section("Previous Events") {
                    ForEach(previousEvents) { event in
                        NavigationLinkButton {
                            onTapEvent(event.id)
                        } label: {
                            EventRowView(event: event)
                        }
                    }
                }
            }
        }
    }

    struct EventRowView: View {
        var event: MusicEvent

        static let intervalFormatter = {
            let f = DateIntervalFormatter()
            f.dateStyle = .short
            f.timeStyle = .none
            return f
        }()

        var eventDateString: String? {
            if let startTime = event.startTime, let endTime = event.endTime {
                guard startTime <= endTime
                else {
                    reportIssue("Start time (\(String(describing: startTime))) is after end time (\(String(describing: endTime)))")
                    return nil
                }

                return Self.intervalFormatter.string(from: startTime, to: endTime)
            } else if let startTime = event.startTime {
                return startTime.formatted()
            } else {
                return nil
            }
        }

        @Environment(\.databaseDebugInformation) var databaseDebugInfo

        var body: some View {
            HStack(spacing: 10) {
                MusicEvent.IconImageView(event: event)
                    .frame(width: 60, height: 60)
//                    .foregroundColor(.label)
//                .invertForLightMode()

                VStack(alignment: .leading) {
                    Text(event.name)
                    if let eventDateString {
                        Text(eventDateString)
                            .lineLimit(1)
                        
                            .font(.caption2)
                    }
                    if databaseDebugInfo.isEnabled {
                        Text(String(event.id.rawValue))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
        }
    }
}

public extension EnvironmentValues {
    @Entry var databaseDebugInformation = DatabaseDebugStatus.disabled
    @Entry var loadingScreenImage: Image?
    @Entry var date: DateGenerator = .init { Date() }
}

public enum DatabaseDebugStatus {
    case enabled
    case disabled

    var isEnabled: Bool {
        self == .enabled
    }
}

import Sharing
extension SharedKey where Self == AppStorageKey<MusicEvent.ID?> {
    static var eventID: Self {
        .appStorage("OME-eventID")
    }
}

enum Current {
    static var musicEventID: AppStorageKey<MusicEvent.ID?> {
        .appStorage("OME-eventID")
    }


    static var musicEvent: Where<MusicEvent> {
        @Dependency(\.musicEventID) var musicEventID
        return MusicEvent.find(musicEventID)
    }

    static var organizer: SelectOf<Organizer> {
        @Dependency(\.musicEventID) var musicEventID

        return Organizer.all
            .where { $0.url == Current.musicEvent.select(\.organizerURL) }
            .limit(1)
    }

    static var artists: Where<Artist> {
        @Dependency(\.musicEventID) var eventID
        return Artist.where {
            eventID == $0.musicEventID
        }
    }

    static var stages: SelectOf<Stage> {
        Stage.where {
            @Dependency(\.musicEventID) var eventID
            eventID == $0.musicEventID
        }
        .order(by: \.sortIndex)
    }

    static var schedules: Where<Schedule> {
        Schedule.where {
            @Dependency(\.musicEventID) var eventID
            eventID == $0.musicEventID
        }
    }

}





extension ImagePipeline {
    static let images: ImagePipeline = {

        var configuration = ImagePipeline.Configuration()

        var dataCache = try? DataCache(name: "com.open-music-event.images")
        dataCache?.sizeLimit = 1024 * 1024 * 150

        configuration.dataCache = dataCache
        configuration.imageCache = ImageCache()

        return ImagePipeline(configuration: configuration)
    }()
}

let intervalFormatter = DateIntervalFormatter()



//#Preview {
//    prepareDependencies {
//        try! $0.defaultDatabase = appDatabase()
//    }
//
//    OrganizerDetailView(url: .init("")!)
//        .environment(\.loadingScreenImage, Image("WWVector", bundle: .module))
//}

struct Twirl: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase.isIdentity ? 1 : 0.5)
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity ? 0 : 10)
            .rotationEffect(
                .degrees(
                    phase == .willAppear ? 360 :
                        phase == .didDisappear ? -360 : .zero
                )
            )
            .brightness(phase == .willAppear ? 1 : 0)
    }
}
