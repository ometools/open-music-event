//
//  OpenMusicEventAppView.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/6/25.
//

import  SwiftUI; import SkipFuse
// import Sharing
// import SharingGRDB
import GRDB
import CasePaths
import CoreModels
import Dependencies
import IssueReporting
#if canImport(Nuke)
import Nuke
#endif

// Step 1: Create a unique notification name
extension Notification.Name {
    static let userSelectedToViewEvent = Notification.Name("requestedToViewEvent")
    static let userRequestedToExitEvent = Notification.Name("requestedToExitEvent")
}


public enum OME {
    public static func prepareDependencies() throws {
        try Dependencies.prepareDependencies {
            $0.defaultDatabase = try appDatabase()
        }

        #if canImport(Nuke)
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
        #endif

        #if os(Android)
        prepareAndroidDependencies()
        #endif
    }


    public struct WhiteLabeledEntryPoint: View {
        public init(url: Organizer.ID) {
            self.url = url
        }

        @ObservationIgnored
        // TODO: Replace @Shared(.eventID) with proper state management
        // @Shared(.eventID) var eventID
        var eventID: MusicEvent.ID? = nil

        var url: Organizer.ID

        @State var musicEventViewer: MusicEventViewer.Model?

        public var body: some View {
            Group {
                if eventID == nil {
                    OrganizerDetailView(url: self.url)
                }

                if let musicEventViewer {
                    MusicEventViewer(store: musicEventViewer)
                        .transition(.slide)
                }
            }
            .animation(.default, value: eventID)
        }
    }

}

public struct OMEAppEntryPoint: View {

    public init() {}

    @State var store = Model()

    @Observable
    @MainActor
    class Model {
        var musicEventViewer: MusicEventViewer.Model?
        var organizerList = OrganizerListView.Model()

        @ObservationIgnored
        // TODO: Replace @Shared(.eventID) with proper state management
        // @Shared(.eventID) var eventID
        var eventID: MusicEvent.ID?

        init() {

            NotificationCenter.default.addObserver(
                forName: .userSelectedToViewEvent,
                object: nil,
                queue: .main
            ) { notification in
                guard let eventID = notification.userInfo?["eventID"] as? OmeID<MusicEvent> else {
                    reportIssue("Posted notification: selectedEventID did not contain eventID")
                    return
                }
                MainActor.assumeIsolated {
                    self.handleSelectedEventIDNotification(eventID)
                }
            }

            NotificationCenter.default.addObserver(
                forName: .userRequestedToExitEvent,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    self.handleExitEventNotification()
                }
            }
        }

        func onAppear() async {
            // TODO: Replace $eventID.load() with proper state loading
            // try? await $eventID.load()
            if let eventID {
                self.musicEventViewer = .init(eventID: eventID)
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        private func handleSelectedEventIDNotification(_ eventID: MusicEvent.ID) {
            // TODO: Replace $eventID.withLock with proper state management
            // self.$eventID.withLock { $0 = eventID }
            self.eventID = eventID
            self.musicEventViewer = .init(eventID: eventID)
        }

        private func handleExitEventNotification() {
            // TODO: Replace $eventID.withLock with proper state management
            // self.$eventID.withLock { $0 = nil }
            self.eventID = nil
            self.musicEventViewer = nil
        }
    }


    public var body: some View {
        //        Text("APP ENTRY POINT")
        ZStack {
            NavigationStack {
                OrganizerListView(store: store.organizerList)
            }

            if let store = store.musicEventViewer {
                MusicEventViewer(store: store)
            }
        }
        .onAppear { Task { await store.onAppear() } }
    }
}



#if os(iOS)
#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try appDatabase()
    }

    OMEAppEntryPoint()
}
#endif

#if SKIP
import androidx.emoji2.text.EmojiCompat

private func prepareAndroidDependencies() {
 
}
#endif
