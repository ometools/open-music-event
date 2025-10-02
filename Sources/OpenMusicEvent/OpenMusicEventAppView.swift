

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

public enum OME {
    public static func prepareDependencies(enableFirebase: Bool = true) throws {
        try Dependencies.prepareDependencies {
            $0.defaultDatabase = try appDatabase()
            $0.omeLogger = LoggingLogger()
        }

        #if canImport(Nuke)
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
        #endif

        @Dependency(\.notificationManager) var notificationManager
        UNUserNotificationCenter.current().delegate = notificationManager

        if enableFirebase {
            FirebaseApp.configure()
            Messaging.messaging().delegate = notificationManager
        }

        IssueReporters.current += [InMemoryIssueReporter.shared, .breakpoint]
    }

    @MainActor
    public static func onLaunch() async throws {
        @Dependency(\.notificationManager) var notificationManager
        try await notificationManager.applicationDidLaunch()
    }

}

// MARK: - Shared Organization Model
@Observable
@MainActor
class OrganizationViewer {
    var musicEventViewer: MusicEventViewer.Model?

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

    func loadSavedEvent() {
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

// MARK: WhiteLabledEntryPoint
public struct OMEWhiteLabeledEntryPoint: View {
    public init(id: Organizer.ID, url: URL) {
        self.init(id: id, reference: .url(url))
    }

    public init(id: Organizer.ID, reference: OrganizationReference) {
        self.store = .init(id: id, organization: reference)
    }

    @State var store: Model

    @Observable
    @MainActor
    class Model {
        var organizationViewer = OrganizationViewer()
        var organizerDetailStore: OrganizerDetailView.Store
        let organizationReference: OrganizationReference
        var isLoadingOrganizer: Bool = false
        var organizerLoadError: String?

        init(id: Organizer.ID, organization: OrganizationReference) {
            self.organizerDetailStore = .init(id: id)
            self.organizationReference = organization
        }

        @ObservationIgnored
        @Dependency(\.defaultDatabase) var database

        func onAppear() async {
            organizationViewer.loadSavedEvent()

            self.isLoadingOrganizer = true
            self.organizerLoadError = nil

            await withTaskGroup {
                $0.addTask {
                    await withErrorReporting {
                        do {
                            try await downloadAndStoreOrganizer(from: self.organizationReference)
                        } catch {
                            let e = error
                        }

                        await MainActor.run {
                            self.isLoadingOrganizer = false
                        }
                    }
                }
            }
        }
    }

    public var body: some View {
        ZStack {
            NavigationStack {
                OrganizerDetailView(store: store.organizerDetailStore)
            }

            if let musicEventViewer = store.organizationViewer.musicEventViewer {
                MusicEventViewer(store: musicEventViewer)
            } else if store.isLoadingOrganizer {
                LoadingScreen()
            }
        }
        .onAppear { Task { await store.onAppear() } }
    }
}

// MARK: OMEAppEntryPoint


public struct OMEAppEntryPoint: View {
    public init() {}

    @State var store = Model()

    @Observable
    @MainActor
    class Model {
        var organizationViewer = OrganizationViewer()
        var organizerList = OrganizerListView.Model()

        func onAppear() async {
            organizationViewer.loadSavedEvent()
        }
    }

    public var body: some View {
        ZStack {
            NavigationStack {
                OrganizerListView(store: store.organizerList)
            }

            if let store = store.organizationViewer.musicEventViewer {
                MusicEventViewer(store: store)
            }
        }
        .onAppear { Task { await store.onAppear() } }
    }
}


// MARK: Bundled Entry Point
public struct OMEBundledEntryPoint: View {
    public init(folderURL: URL) {
        self.folderURL = folderURL
    }

    let folderURL: URL
    @State var store = Model()

    @Observable
    @MainActor
    class Model {
        var organizationViewer = OrganizationViewer()
        var isLoading: Bool = false
        var loadError: String?

        func onAppear(folderURL: URL) async {
            organizationViewer.loadSavedEvent()

            self.isLoading = true
            self.loadError = nil

            await withTaskGroup {
                $0.addTask {
                    await withErrorReporting {
                        do {
                            try await loadAndStoreLocalOrganizer(from: folderURL)
                        } catch {
                            await MainActor.run {
                                self.loadError = error.localizedDescription
                            }
                        }

                        await MainActor.run {
                            self.isLoading = false
                        }
                    }
                }
            }
        }
    }

    public var body: some View {
        ZStack {
            if let error = store.loadError {
                VStack {
                    Text("Error loading event")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } else if store.isLoading {
                LoadingScreen()
            } else if let musicEventViewer = store.organizationViewer.musicEventViewer {
                MusicEventViewer(store: musicEventViewer)
            }

            Text("Hello World!")
        }
        .onAppear { Task { await store.onAppear(folderURL: folderURL) } }
    }
}


// MARK: - Logging

public struct LoggingLogger: OMELogger {
    let logger = Logger(subsystem: "ome.OpenMusicEvent", category: "Parser")

    public func log(_ message: String, level: LogLevel, file: String, line: Int) {
        logger.log(level: .debug, "\(message)")
    }
}


@Observable
class InMemoryIssueReporter: IssueReporter, @unchecked Sendable {
    var issues: [Issue] = []

    struct Issue: Identifiable {
        var id = UUID()
        var message: String
    }
    static let shared = InMemoryIssueReporter()

    func reportIssue(
        _ message: @autoclosure () -> String?,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        if let message = message() {
            self.issues.append(.init(message: message))
        }
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
