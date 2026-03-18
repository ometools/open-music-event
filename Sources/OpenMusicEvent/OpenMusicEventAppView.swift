

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
    static let logger = Logger(subsystem: "live.openmusicevent.app", category: "OME")
    public static func prepareDependencies(enableFirebase: Bool = true) throws {
        logger.info("prepareDepedencies(enableFirebase: \(enableFirebase))")

        try Dependencies.prepareDependencies {
            $0.omeLogger = LoggingLogger()

            let userPrefrerencesDatabase = try OrganizationDatabaseManager.openUserPreferencesDatabase()
            $0.userPreferencesDatabase = userPrefrerencesDatabase
            $0.defaultDatabase = userPrefrerencesDatabase
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

        IssueReporters.current += [
            InMemoryIssueReporter.shared,
        ]

//        #if !os(Android)
//        IssueReporters.current += [
//            .breakpoint
//        ]
//        #endif
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
    var musicEventViewer: MusicEventViewer?

    struct OrganizationSelection: FetchableRecord {
        init(row: GRDB.Row) throws {
            self.organizationID = row["organizationID"]
            self.url = row["url"]
        }

        let organizationID: Organizer.ID
        let url: URL
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: WhiteLabledEntryPoint
public struct OMEWhiteLabeledEntryPoint: View {
    public init(id: Organizer.ID, url: URL)  {
         self.init(id: id, reference: .zipURL(url))
    }

    public init(id: Organizer.ID, reference: OrganizationReference) {

        self.store = withErrorReporting { try .init(id: id, organization: reference) }
    }

    @State var store: Model?

    @Observable
    @MainActor
    class Model {
        var organizationViewer = OrganizationViewer()
        var organizerDetailStore: OrganizationRoot
        let organizationReference: OrganizationReference
        var isLoadingOrganizer: Bool = false
        var organizerLoadError: String?

        init(id: Organizer.ID, organization: OrganizationReference) throws {
            self.organizationReference = organization
            self.organizerDetailStore = try .openExistingDatabase(for: id)

            Task {
                self.isLoadingOrganizer = true
                self.organizerLoadError = nil

                await withErrorReporting {
                    try await downloadAndStoreOrganizer(from: self.organizationReference)

                    await MainActor.run {
                        self.isLoadingOrganizer = false
                    }
                }
            }
        }

        @ObservationIgnored
        @Dependency(\.defaultDatabase) var database

    }

    public var body: some View {
        if let store {
            ZStack {
                NavigationStack {
                    OrganizationRootView(store: store.organizerDetailStore)
                }

                if let store = store.organizationViewer.musicEventViewer {
                    MusicEventView(store: store)
                } else if store.isLoadingOrganizer {
                    LoadingScreen()
                }
            }
        } else {
            LogsView()
        }

    }
}

// MARK: OMEAppEntryPoint


public struct OMEAppEntryPoint: View {
    public init() {}

    @State var store = Model()

    @Observable
    @MainActor
    class Model {
        var organizerList = OrganizerListView.Model()
        var organization: OrganizationRoot?

        @ObservationIgnored
        @Dependency(\.userPreferencesDatabase) var userPrefsDB

        func onFirstAppear() async {
            await withErrorReporting {
                let query = ValueObservation.tracking { db in
                     try AppState.fetchOne(db)
                }

                for try await appState in query.values(in: userPrefsDB) {
                    if let orgID = appState?.selectedOrganizationID,
                       organization?.id != orgID
                    {
                        self.organization = try OrganizationRoot.openExistingDatabase(for: orgID)
                    }
                }
            }
        }

        var logger = Logger(subsystem: "com.ometools.open-music-event", category: "AppEntryPoint")
        func navigate(to route: AppRoute) throws {
            logger.info("Navigating to \(String(describing: route))")
            switch route {
            case .organizationList:
                self.organization = nil
            case .organization(let id, _):
                if organization?.id != id {
                    self.organization = try OrganizationRoot.openExistingDatabase(for: id)
                }
            }
        }
    }

    public var body: some View {
        Group {
            OrganizerListView(store: store.organizerList)
        }
        .onFirstAppear {
            Task {
                await store.onFirstAppear()
            }
        }
    }
}

struct OnFirstAppearViewModifier: ViewModifier {
    let operation: () -> Void
    @State var hasAppeared: Bool = false
    func body(content: Content) -> some View {
        content.onAppear {
            if !hasAppeared {
                operation()
                hasAppeared = true
            }
        }

    }
}

extension View {
    func onFirstAppear(perform action: @escaping () -> Void) -> some View {
        modifier(OnFirstAppearViewModifier(operation: action))
    }
}




enum AppRoute: Hashable {
    case organizationList
    case organization(Organizer.ID, OrganizationRoute)
}


// MARK: Bundled Entry Point


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


//#if os(iOS)
//#Preview {
//    let _ = try! prepareDependencies {
//        $0.defaultDatabase = try appDatabase()
//    }
//
//    OMEAppEntryPoint()
//}
//#endif
