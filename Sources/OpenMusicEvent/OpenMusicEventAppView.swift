//
//  OpenMusicEventAppView.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/6/25.
//

import SwiftUI
import Sharing
import SharingGRDB
import ImageCaching
import CasePaths
import CoreModels

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

    public struct AppEntryPoint: View {

        public init() {}

        @State var store = Model()

        @Observable
        @MainActor
        class Model {
            var musicEventViewer: MusicEventViewer.Model?
            var organizerList = OrganizerListView.Model()

            @ObservationIgnored
            @Shared(.eventID) var eventID

            init() {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleSelectedEventIDNotification(_:)),
                    name: .userSelectedToViewEvent,
                    object: nil
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleExitEventNotification(_:)),
                    name: .userRequestedToExitEvent,
                    object: nil
                )
            }

            func onAppear() async {
                try? await $eventID.load()
                if let eventID {
                    self.musicEventViewer = .init(eventID: eventID)
                }
            }

            deinit {
                NotificationCenter.default.removeObserver(self)
            }

            @objc private func handleSelectedEventIDNotification(_ notification: Notification) {
                guard let eventID = notification.userInfo?["eventID"] as? OmeID<MusicEvent> else {
                    reportIssue("Posted notification: selectedEventID did not contain eventID")
                    return
                }
                self.$eventID.withLock { $0 = eventID }
                self.musicEventViewer = .init(eventID: eventID)
            }

            @objc private func handleExitEventNotification(_ notification: Notification) {
                self.$eventID.withLock { $0 = nil }
                self.musicEventViewer = nil
            }
        }


        public var body: some View {
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

    public struct WhiteLabeledEntryPoint: View {
        public init(url: Organizer.ID) {
            self.url = url
        }

        @ObservationIgnored
        @Shared(.eventID) var eventID

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




#Preview {
    let _ = try! prepareDependencies {
      $0.defaultDatabase = try appDatabase()
    }

    OME.AppEntryPoint()
}
