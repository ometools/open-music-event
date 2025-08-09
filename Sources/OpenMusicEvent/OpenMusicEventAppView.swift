

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


#if os(Android)
import SkipFirebaseCore
import SkipFirebaseMessaging
#else
import FirebaseCore
import FirebaseMessaging
#endif



import OpenMusicEventParser

public struct LoggingLogger: OMELogger {
    let logger = Logger(subsystem: "ome.OpenMusicEvent", category: "Parser")

    public func log(_ message: String, level: LogLevel, file: String, line: Int) {
        logger.log(level: .debug, "\(message)")
    }
}

public enum OME {
    public static func prepareDependencies() throws {
        try Dependencies.prepareDependencies {
            $0.defaultDatabase = try appDatabase()
            $0.omeLogger = LoggingLogger()
        }

        #if canImport(Nuke)
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
        #endif

        @Dependency(\.notificationManager) var notificationManager

        FirebaseApp.configure()
        Messaging.messaging().delegate = notificationManager
        UNUserNotificationCenter.current().delegate = notificationManager
//
    }

    public static func onLaunch() async throws {
        @Dependency(\.notificationManager) var notificationManager
        try await notificationManager.applicationDidLaunch()
    }

}

public struct OMEWhiteLabeledEntryPoint: View {
    public init(url: Organizer.ID) {
        self.url = url
        self.store = Model(organizerID: url)
    }

    var url: Organizer.ID
    
    @State var store: Model

    @Observable
    @MainActor
    class Model {
        var musicEventViewer: MusicEventViewer.Model?
        var organizerDetailStore: OrganizerDetailView.ViewModel
        let organizerURL: Organizer.ID
        var isLoadingOrganizer: Bool = false

        init(organizerID: Organizer.ID) {
            self.organizerURL = organizerID
            self.organizerDetailStore = OrganizerDetailView.ViewModel(url: organizerID)
            
            self.observeNotifications()
        }

        func observeNotifications() {
            NotificationCenter.default.addObserver(
                forName: .userSelectedToViewEvent,
                object: nil,
                queue: .main
            ) { notification in
                guard case .some(.viewEvent(let eventID)) = notification.info else {
                    reportIssue("Posted notification: userSelectedToViewEvent did not contain valid eventID")
                    return
                }
                Task { @MainActor in
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


        @ObservationIgnored
        @Dependency(\.defaultDatabase) var database

        func onAppear() async {
            let eventIDString: String? = UserDefaults.standard.string(forKey: "selectedMusicEventID")

            if let eventIDString {
                self.musicEventViewer = .init(eventID: .init(eventIDString))
            }

            // Just download on launch if possible
            // May not want to even report errors here, failure is expected if no service
            await withErrorReporting {
                try await downloadAndStoreOrganizer(from: .url(self.organizerURL))
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        private func handleSelectedEventIDNotification(_ eventID: MusicEvent.ID) {
            let eventString = String(eventID.rawValue)
            UserDefaults.standard.set(eventString, forKey: "selectedMusicEventID")
            self.musicEventViewer = .init(eventID: eventID)
        }

        private func handleExitEventNotification() {
            UserDefaults.standard.set(nil, forKey: "selectedMusicEventID")
            self.musicEventViewer = nil
        }
    }

    public var body: some View {
        ZStack {
            NavigationStack {
                OrganizerDetailView(store: store.organizerDetailStore)

            }

            if let musicEventViewer = store.musicEventViewer {
                MusicEventViewer(store: musicEventViewer)
            }

        }
        .onAppear { Task { await store.onAppear() } }
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


        init() {

            NotificationCenter.default.addObserver(
                forName: .userSelectedToViewEvent,
                object: nil,
                queue: .main
            ) { notification in
                guard case .some(.viewEvent(let eventID)) = notification.info else {
                    reportIssue("Posted notification: userSelectedToViewEvent did not contain valid eventID")
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
            let eventIDString: String? = UserDefaults.standard.string(forKey: "selectedMusicEventID")

            if let eventIDString {
                self.musicEventViewer = .init(eventID: .init(eventIDString))
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        private func handleSelectedEventIDNotification(_ eventID: MusicEvent.ID) {
            let eventString = String(eventID.rawValue)
            UserDefaults.standard.set(eventString, forKey: "selectedMusicEventID")
            self.musicEventViewer = .init(eventID: eventID)
        }

        private func handleExitEventNotification() {
            UserDefaults.standard.set(nil, forKey: "selectedMusicEventID")
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
