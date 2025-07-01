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
//                NotificationCenter.default.addObserver(
//                    self,
//                    selector: #selector(handleSelectedEventIDNotification(_:)),
//                    name: .userSelectedToViewEvent,
//                    object: nil
//                )
//                NotificationCenter.default.addObserver(
//                    self,
//                    selector: #selector(handleExitEventNotification(_:)),
//                    name: .userRequestedToExitEvent,
//                    object: nil
//                )
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
//
//            @objc private func handleSelectedEventIDNotification(_ notification: Notification) {
//                guard let eventID = notification.userInfo?["eventID"] as? OmeID<MusicEvent> else {
//                    reportIssue("Posted notification: selectedEventID did not contain eventID")
//                    return
//                }
//                // TODO: Replace $eventID.withLock with proper state management
//                // self.$eventID.withLock { $0 = eventID }
//                self.eventID = eventID
//                self.musicEventViewer = .init(eventID: eventID)
//            }
//
//            @objc private func handleExitEventNotification(_ notification: Notification) {
//                // TODO: Replace $eventID.withLock with proper state management
//                // self.$eventID.withLock { $0 = nil }
//                self.eventID = nil
//                self.musicEventViewer = nil
//            }
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

