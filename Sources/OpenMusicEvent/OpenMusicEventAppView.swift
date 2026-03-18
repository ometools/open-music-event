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


#if !APPCLIP
#if os(Android)
import SkipFirebaseCore
import SkipFirebaseMessaging
#else
import FirebaseCore
import FirebaseMessaging
#endif
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

        #if APPCLIP
        logger.info("prepareDependencies: APPCLIP")
        #endif


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

                @Dependency(\.downloadAndStoreOrganization) var downloadAndStoreOrganization
                await withErrorReporting {
                    try await downloadAndStoreOrganization(self.organizationReference)

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

import Dependencies

public struct OMEAppEntryPoint: View {
    public init(store: Model) {
        self.store = store
    }

    let store: Model

    @Observable
    @MainActor
    public class Model {
        public init() {
            _ = Task {
                await self.task()
            }
        }


        var organizerList = OrganizerListView.Model()
        var organizationRoot: OrganizationRoot?

        @ObservationIgnored
        @Dependency(\.userPreferencesDatabase) var userPrefsDB
        

        func task() async {
            await withErrorReporting {
                let query = ValueObservation.tracking { db in
                    try AppState
                        .select(Column("selectedOrganizationID"))
                        .asRequest(of: Organizer.ID.self)
                        .fetchOne(db)
                }

                for try await selectedOrganizationID in query.values(in: userPrefsDB) {
                    if let orgID = selectedOrganizationID, organizationRoot?.id != orgID {
                        try withDependencies(from: self) {
                            self.organizationRoot = try OrganizationRoot.openExistingDatabase(for: orgID)
                        }
                    }
                }
            }
        }

        public func didReceiveURL(url: URL) {
            logger.info("OMEAPPEntryPoint.didReceiveURL(\(url.absoluteString)")

            withErrorReporting {
                let route = try appRouter.match(url: url)
                logger.info("Parsed AppRoute: \(String(describing: route))")

                try self.navigate(to: route)
            }
        }


        var logger = Logger(subsystem: "com.ometools.open-music-event", category: "AppEntryPoint")
        public func navigate(to route: AppRoute) throws {
            logger.info("Navigating to \(String(describing: route))")
            switch route {
            case .home, .organizationList:
                self.organizationRoot = nil

            case .organization(let id, _):
                // 1) Persist selection and ensure minimal organizer row exists in user prefs DB
                try userPrefsDB.write { db in
                    // Ensure AppState row exists and set selection
                    var appState = try AppState.fetchOne(db, key: 1) ?? AppState()
                    appState.selectedOrganizationID = id
                    try appState.save(db)
                }

            }
        }
    }

    public var body: some View {
        let _ = Self._printChanges()

        Group {
            if let organizationRoot = store.organizationRoot {
                OrganizationRootView(store: organizationRoot)

            } else {
                OrganizerListView(store: store.organizerList)
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



import DependenciesMacros
@DependencyClient
public struct OrgIdentifierResolutionClient: Sendable {
    public var perform: @Sendable (Organizer.ID) async throws -> OrganizationReference
    public func callAsFunction(id: Organizer.ID) async throws -> OrganizationReference {
        try await self.perform(id)
    }
}

extension OrgIdentifierResolutionClient: TestDependencyKey {
    public static let testValue: OrgIdentifierResolutionClient = Self()
}

extension DependencyValues {
    public var resolveOrgID: OrgIdentifierResolutionClient {
        get { self[OrgIdentifierResolutionClient.self] }
        set { self[OrgIdentifierResolutionClient.self] = newValue }
    }
}

public enum AppRoute: Hashable, Sendable {
    case home
    case organizationList
    case organization(Organizer.ID, OrganizationRoute)
}

@preconcurrency import URLRouting
public let appRouter = OneOf {

    Route(.case(AppRoute.home))
    Route(.case(AppRoute.organizationList)) { Path { "orgs" } }
    Route(.case(AppRoute.organization)) {
        Path { "orgs" }
        Path { Parse(.string.representing(Organizer.ID.self)) }
        organizationRouter
    }
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

