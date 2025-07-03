//
//  OrganizerDetails.swift
//  event-viewer
//
//  Created by Woodrow Melling on 3/25/25.
//

import Foundation
import Observation
import  SwiftUI; import SkipFuse
import Dependencies
// import SharingGRDB
import GRDB
import CoreModels
import IssueReporting

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

            // TODO: Replace @FetchOne/@FetchAll with GRDB queries
            // _organizer = FetchOne(wrappedValue: nil, Organizer?.find(id))
            // _events = FetchAll(
            //     MusicEvent
            //         .where { $0.organizerURL == id }
            //         .order { $0.startTime.desc(nulls: .last)  }
            // )
        }

        public let id: Organizer.ID

        // TODO: Replace @FetchOne with GRDB query
        public var organizer: Organizer?

        // TODO: Replace @FetchAll with GRDB query
        var events: [MusicEvent] = []

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


        struct OrganizerEvents {
            let info: Organizer
            let events: [MusicEvent]
        }
        public func onAppear() async {
            @Dependency(\.defaultDatabase) var database

            let query = ValueObservation.tracking { db in
                let org = try Organizer.fetchOne(db, id: self.id)
                let events = try MusicEvent
                    .filter(Column("organizerURL") == self.id)
                    .order(Column("startTime").desc)
                    .fetchAll(db)

                return (org, events)
            }

            
            do {
                for try await (organizer, events) in query.values(in: database) {
                    self.organizer = organizer
                    self.events = events
                }
            } catch {
                reportIssue(error)
            }
//
//
//
//            // TODO: Replace $organizer.load() with GRDB query
//            // try? await $organizer.load()
//            if organizer == nil {
//                await withErrorReporting {
//                    self.showingLoadingScreen = true
//                    try await downloadAndStoreOrganizer(from: .url(self.id))
//
//                    try await withThrowingTaskGroup {
//                        if let orgImageURL = organizer?.imageURL {
//                            $0.addTask {
//                                _ = try await ImagePipeline.images.image(for: orgImageURL)
//                            }
//                        }
//
//                        for event in events {
//                            if let imageURL = event.imageURL {
//                                $0.addTask {
//                                    _ = try await ImagePipeline.images.image(for: imageURL)
//                                }
//                            }
//                        }
//
//                        try await $0.waitForAll()
//                    }
//
//                    self.showingLoadingScreen = false
//                }
//            }
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
//                        .background(Material.ultraThin)
                        .ignoresSafeArea()
                }

                if let image = loadingScreenImage, store.showingLoadingScreen {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(80)
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
//                        NavigationLinkButton {
//                            onTapEvent(event.id)
//                        } label: {
//                            EventRowView(event: event)
//                        }
                    }
                }
            }

            if !previousEvents.isEmpty {
                Section("Previous Events") {
                    ForEach(previousEvents) { event in
//                        NavigationLinkButton {
//                            onTapEvent(event.id)
//                        } label: {
//                            EventRowView(event: event)
//                        }
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
//                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
        }
    }
}

private struct DatabaseDebugInformationKey: EnvironmentKey {
    static let defaultValue = DatabaseDebugStatus.disabled
}

private struct LoadingScreenImageKey: EnvironmentKey {
    static let defaultValue: Image? = nil
}

private struct DateKey: EnvironmentKey {
    static let defaultValue: DateGenerator = .init { Date() }
}

public extension EnvironmentValues {
    var databaseDebugInformation: DatabaseDebugStatus {
        get { self[DatabaseDebugInformationKey.self] }
        set { self[DatabaseDebugInformationKey.self] = newValue }
    }
    
    var loadingScreenImage: Image? {
        get { self[LoadingScreenImageKey.self] }
        set { self[LoadingScreenImageKey.self] = newValue }
    }
    
    var date: DateGenerator {
        get { self[DateKey.self] }
        set { self[DateKey.self] = newValue }
    }
}

public enum DatabaseDebugStatus: Sendable {
    case enabled
    case disabled

    var isEnabled: Bool {
        self == .enabled
    }
}

// import Sharing
// TODO: Replace SharedKey extension with proper state management
// extension SharedKey where Self == AppStorageKey<MusicEvent.ID?> {
//     static var eventID: Self {
//         .appStorage("OME-eventID")
//     }
// }

enum Current {
//    static var musicEventID: AppStorageKey<MusicEvent.ID?> {
//        .appStorage("OME-eventID")
//    }


    // TODO: Replace with GRDB query
    // static var musicEvent: Where<MusicEvent> {
    //     @Dependency(\.musicEventID) var musicEventID
    //     return MusicEvent.find(musicEventID)
    // }

    // TODO: Replace with GRDB query
    // static var organizer: SelectOf<Organizer> {
    //     @Dependency(\.musicEventID) var musicEventID
    //
    //     return Organizer.all
    //         .where { $0.url == Current.musicEvent.select(\.organizerURL) }
    //         .limit(1)
    // }

    // TODO: Replace with GRDB query
    // static var artists: Where<Artist> {
    //     @Dependency(\.musicEventID) var eventID
    //     return Artist.where {
    //         eventID == $0.musicEventID
    //     }
    // }

    // TODO: Replace with GRDB query
    // static var stages: SelectOf<Stage> {
    //     Stage.where {
    //         @Dependency(\.musicEventID) var eventID
    //         eventID == $0.musicEventID
    //     }
    //     .order(by: \.sortIndex)
    // }

    // TODO: Replace with GRDB query
    // static var schedules: Where<Schedule> {
    //     Schedule.where {
    //         @Dependency(\.musicEventID) var eventID
    //         eventID == $0.musicEventID
    //     }
    // }

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



extension Organizer {
    static let placeholder = Organizer.omeTools
}
