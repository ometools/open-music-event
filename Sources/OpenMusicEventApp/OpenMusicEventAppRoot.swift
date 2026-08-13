import ComposableArchitecture2
import ComposableAuthoring
import ComposableAuthoringWorkspace
import ComposableWorkspace
import ComposableNotifications
import Dependencies
import ErrorHandling
import Foundation
import IssueReporting
import OpenMusicEventAppEventViewer
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventEntry
import OpenMusicEventSourceEditing
import Sharing
import SourceEditing
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
#if os(iOS)
import SafariServices
#endif

@Feature
public struct OpenMusicEventAppRoot {
    public init() {}

    public struct State {
        public init(
            variant: OpenMusicEventAppVariant = .generic,
            selectedEventIDAtLaunch: OMERecord.Event.ID? = nil,
            workspaceRestorationErrorAtLaunch: (any Error)? = nil
        ) {
            _installedEvents = FetchAll(InstalledEventRecord.all)
            _notificationIndicatorSummary = Fetch(
                wrappedValue: ApplicationNotificationIndicatorSummary(),
                ApplicationNotificationIndicatorSummaryRequest()
            )
            _notificationSubscriptions = Fetch(
                wrappedValue: [],
                ApplicationNotificationSubscriptionsRequest()
            )
            self.variant = variant
            self.workspaceRestorationError = workspaceRestorationErrorAtLaunch
            if workspaceRestorationErrorAtLaunch == nil,
               variant.persistsSelectedEvent,
               let selectedEventIDAtLaunch {
                do {
                    let workspace = try OpenMusicEventAppRoot.workspace(
                        for: selectedEventIDAtLaunch
                    )
                    self.destination = .eventViewer(
                        OpenMusicEventAppRoot.makeWorkspaceEventViewerState(
                            workspace: workspace,
                            eventID: selectedEventIDAtLaunch,
                            target: nil,
                            pendingScheduleLaunchAction: .jumpToCurrentTime
                        )
                    )
                } catch {
                    self.workspaceRestorationError = error
                }
            }
            if case let .whiteLabel(configuration) = variant {
                self.whiteLabelRoot = Spawn(
                    WhiteLabelRoot.State(configuration: configuration)
                )
            }
        }

        public var browser = OpenMusicEventBrowser.State()
        public var destination: Destination.State?
        public var eventEntry: EventEntryState?
        public var errorNotifications = Spawn(ErrorNotifications.State())
        @Trigger<AppDelegateEvent> public var appDelegateEvent
        @Trigger<NotificationContent<AppRoute>> public var notificationContent
        @Trigger<NotificationEvent> public var notificationEvent
        @Trigger<NotificationSignal> public var notificationSignal
        @SharedReader(.devicePermissions) public var permissions: DevicePermissions
        var inAppBrowserPresentation: InAppBrowserPresentation?
        public var variant: OpenMusicEventAppVariant
        public var whiteLabelRoot: Spawn<WhiteLabelRoot>? = nil
        @DebugSnapshotIgnored var activeRouteRequestID: UUID?
        @DebugSnapshotIgnored var workspaceRestorationError: (any Error)?

        @FetchOne(AppState.find(1))
        public var appState: AppState?

        @FetchAll public var installedEvents: [InstalledEventRecord]
        @Fetch public var notificationIndicatorSummary: ApplicationNotificationIndicatorSummary
        @Fetch public var notificationSubscriptions: Set<NotificationSubscription>

        public var selectedEventID: OMERecord.Event.ID? {
            appState?.selectedEventID
        }
    }

    public enum Action {
        case appDelegateEvent(AppDelegateEvent)
        case browser(OpenMusicEventBrowser.Action)
        case destination(Destination.Action)
        case eventEntryDismissed
        case eventEntryRetryTapped
        case handleNavigationRequest(NavigationRequest)
        case openRoute(AppRoute)
        case openURL(URL)
        case task
    }

    @Feature
    public enum Destination {
        case eventViewer(OpenMusicEventWorkspace)
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.applicationIconBadgeClient) var applicationIconBadgeClient
    @Dependency(\.eventImagePrefetch) var eventImagePrefetch
    @Dependency(\.omeEventInstallation) var eventInstallation
    @Dependency(\.uuid) var uuid
    public var body: some Feature {
//        let _ = Self._logChanges()

        let setApplicationIconBadge: (Int) -> Void = { count in
            store.addTask {
                do {
                    try await applicationIconBadgeClient.setCount(count)
                } catch {
                    reportIssue(error)
                }
            }
        }

        let prefetchAssetsOnOpen: (OMERecord.Event.ID) -> Void = { eventID in
            store.addTask {
                do {
                    try await eventImagePrefetch.prefetchAssetsOnOpen(eventID)
                } catch {
                }
            }
        }

        let persistSelectedEvent: (OMERecord.Event.ID?, State) -> Void = { eventID, state in
            guard state.persistsSelectedEvent else { return }
            let organizerID = eventID?.organizerID
            let eventID = eventID?.eventID
            do {
                try database.write { db in
                    try AppState.update {
                        $0.organizerID = #bind(organizerID)
                        $0.eventID = #bind(eventID)
                    }
                    .execute(db)
                }
            } catch {
                store.addTask {
                    await store.reportError(
                        error,
                        fallbackMessage: .selectedEventPersistenceFailed,
                        operation: .selectedEventPersistence
                    )
                }
            }
        }

        Features {
            Update { state, action in
                switch action {
                case let .appDelegateEvent(event):
                    store.addTask {
                        try await store.appDelegateEvent(event)?.value
                    }

                case .browser:
                    break

                case .destination:
                    break

                case let .handleNavigationRequest(request):
                    switch request {
                    case let .event(eventID, target):
                        store.addTask {
                            try store.send(.openRoute(.event(eventID, target)))
                        }

                    case let .externalURL(url):
                        state.openExternalURL(url)
                    }

                case let .openRoute(route):
                    switch route.navigationRequest {
                    case let .event(eventID, target):
                        let eventURI = OMERecord.Event.reference(id: eventID).uri
                        let persistsSelectedEvent = state.persistsSelectedEvent
                        let routeRequestID = uuid()
                        state.activeRouteRequestID = routeRequestID
                        state.eventEntry = EventEntryState(
                            id: routeRequestID,
                            route: route
                        )
                        store.addTask {
                            do {
                                for try await progress in eventInstallation.install(eventURI) {
                                    guard store.state.activeRouteRequestID == routeRequestID else {
                                        return
                                    }
                                    switch progress {
                                    case let .preview(preview):
                                        try store.modify {
                                            guard $0.eventEntry?.id == routeRequestID else { return }
                                            $0.eventEntry?.title = preview.title
                                            $0.eventEntry?.logoURL = preview.logoURL
                                        }
                                    case let .installed(installedEventID):
                                        let eventViewer: OpenMusicEventWorkspace.State
                                        do {
                                            eventViewer = try Self.eventViewerState(
                                                eventID: installedEventID,
                                                target: target
                                            )
                                        } catch {
                                            guard store.state.activeRouteRequestID == routeRequestID else {
                                                return
                                            }
                                            await store.reportError(
                                                error,
                                                fallbackMessage: .eventWorkspaceRestoreFailed,
                                                operation: .eventWorkspaceRestore
                                            )
                                            try store.modify {
                                                guard $0.eventEntry?.id == routeRequestID else { return }
                                                $0.eventEntry?.phase = .failed(
                                                    "This event could not be opened."
                                                )
                                            }
                                            return
                                        }
                                        let mount = try store.modify {
                                            guard $0.eventEntry?.id == routeRequestID else { return }
                                            $0.destination = .eventViewer(eventViewer)
                                            $0.eventEntry = nil
                                        }
                                        await mount?.value
                                        guard store.state.activeRouteRequestID == routeRequestID else {
                                            return
                                        }
                                        if persistsSelectedEvent {
                                            persistSelectedEvent(installedEventID, store.state)
                                        }
                                        do {
                                            try await eventImagePrefetch.prefetchAssetsOnOpen(installedEventID)
                                        } catch {
                                        }
                                    }
                                }
                            } catch {
                                guard store.state.activeRouteRequestID == routeRequestID else {
                                    return
                                }
                                await store.reportError(
                                    error,
                                    fallbackMessage: .eventInstallationFailed,
                                    operation: .eventInstallation
                                )
                                try store.modify {
                                    guard $0.eventEntry?.id == routeRequestID else { return }
                                    $0.eventEntry?.phase = .failed(
                                        "This event could not be loaded."
                                    )
                                }
                            }
                        }

                    case let .externalURL(url):
                        state.openExternalURL(url)
                    }

                case .eventEntryDismissed:
                    state.activeRouteRequestID = nil
                    state.eventEntry = nil

                case .eventEntryRetryTapped:
                    guard let route = state.eventEntry?.route else { return }
                    store.addTask {
                        try store.send(.openRoute(route))
                    }

                case .openURL(let url):
                    if let route = AppRoute(url: url) {
                        store.addTask {
                            await Task.yield()
                            try store.send(.openRoute(route))
                        }
                    } else {
                        state.openExternalURL(url)
                    }

                case .task:
                    if let eventID = state.destination?.eventViewer?
                        .authoring
                        .content
                        .content
                        .id {
                        prefetchAssetsOnOpen(eventID)
                    }
                }
            }
            Scope(\.browser, action: \.browser) {
                OpenMusicEventBrowser()
            }
        }
        .onMount { state in
            setApplicationIconBadge(state.notificationIndicatorSummary.totalCount)
            guard let error = state.workspaceRestorationError else { return }
            state.workspaceRestorationError = nil
            store.addTask {
                await store.reportError(
                    error,
                    fallbackMessage: .eventWorkspaceRestoreFailed,
                    operation: .eventWorkspaceRestore
                )
            }
        }
        .onChange(of: store.notificationIndicatorSummary.totalCount) {
            _, count, _ in
            setApplicationIconBadge(count)
        }
        .onEvent(NavigationRequested.self) { request, state in
            store.addTask {
                try store.send(.handleNavigationRequest(request))
            }
        }
        .onEvent(EventViewerDismissalRequested.self) { eventID, state in
            guard state.destination?.eventViewer?.authoring.content.content.id == eventID else {
                return
            }
            persistSelectedEvent(nil, state)
        }
        .presentReportedErrors()
        .onTrigger(store.notificationContent) { content, _ in
            store.addTask {
                let routeTask = try store.send(.openRoute(content.route))
                await routeTask?.value
            }
        }
        .onTrigger(store.notificationSignal) {
            (signal: NotificationSignal, state: inout State) in
            guard case let .sourceAvailable(source) = signal else { return }
            let installedEventIDs = Set(state.installedEvents.map(\.id))
            let routedEventID: OMERecord.Event.ID?
            if let route = AppRoute(notificationRoute: source.id.rawValue),
               case let .event(eventID, _) = route,
               installedEventIDs.contains(eventID) {
                routedEventID = eventID
            } else {
                routedEventID = nil
            }
            let refreshesInstalledEvents = routedEventID.map { [$0] }
                ?? state.installedEvents.compactMap { installedEvent in
                    source.id.rawValue == OMERecord.Event.reference(id: installedEvent.id)
                        .uri
                        .description
                        ? installedEvent.id
                        : nil
                }
            let refreshesBrowse = state.variant == .generic
            guard refreshesBrowse || !refreshesInstalledEvents.isEmpty else {
                NotificationRefreshDiagnostics.debug("""
                Ignoring source-available notification with no relevant installed content
                source: \(source.id.rawValue)
                version: \(source.version.rawValue)
                """)
                return
            }
            store.addTask {
                NotificationRefreshDiagnostics.notice("""
                Source-available notification refresh started
                source: \(source.id.rawValue)
                version: \(source.version.rawValue)
                events: \(refreshesInstalledEvents.map { OMERecord.Event.reference(id: $0).uri.description }.joined(separator: ", "))
                browse: \(refreshesBrowse)
                """)
                do {
                    for eventID in refreshesInstalledEvents {
                        try await eventInstallation.synchronizeInstalledEvent(eventID)
                    }
                    if refreshesBrowse {
                        try await store.browser.browse.refresh()?.value
                    }
                    let summary = try await database.read { database in
                        try ApplicationNotificationIndicatorSummaryRequest().fetch(database)
                    }
                    try await applicationIconBadgeClient.setCount(summary.totalCount)
                    NotificationRefreshDiagnostics.notice("""
                    Source-available notification refresh completed
                    source: \(source.id.rawValue)
                    version: \(source.version.rawValue)
                    """)
                } catch {
                    NotificationRefreshDiagnostics.failure("""
                    Source-available notification refresh failed
                    source: \(source.id.rawValue)
                    version: \(source.version.rawValue)
                    error: \(String(describing: error))
                    """)
                    throw error
                }
            }
        }
        .onTrigger(store.appDelegateEvent) { event, _ in
            switch event {
            case .launched, .resumed:
                store.addTask {
                    try await store.state.$permissions.load()
                }
            default:
                break
            }
        }
        .spawn(\.errorNotifications) {
            ErrorNotifications()
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .ifLet(\.whiteLabelRoot) {
            WhiteLabelRoot()
        }
        .notificationSubscriptions(\.notificationSubscriptions)
        .notifications(
            appDelegateEventTrigger: \.appDelegateEvent,
            contentTrigger: \.notificationContent,
            notificationEventTrigger: \.notificationEvent,
            signalTrigger: \.notificationSignal
        )
        .appDelegate(eventTrigger: \.appDelegateEvent)
    }
}

extension OpenMusicEventAppRoot.State: ErrorNotificationRootState {}

public struct OpenMusicEventAppRootView: View {
    public init(store: StoreOf<OpenMusicEventAppRoot>) {
        self.store = store
    }

    @Bindable var store: StoreOf<OpenMusicEventAppRoot>

    public var body: some View {
        OpenMusicEventAppSurfaceView(store: store)
        .overlay {
            if let eventEntry = store.eventEntry {
                EventEntryView(
                    state: eventEntry,
                    retry: { store.send(.eventEntryRetryTapped) },
                    dismiss: { store.send(.eventEntryDismissed) }
                )
            }
        }
        .openMusicEventViewerPresentation(
            item: $store
                .scope(\.destination, action: \.destination)
                .eventViewer
        ) { authoringWorkspaceStore in
            let authoringStore = authoringWorkspaceStore
                .scope(\.authoring, action: \.authoring)
            let workspaceStore = authoringStore.scope(\.content, action: \.content)
            let eventViewerStore = workspaceStore.scope(\.content, action: \.content)
            EventViewerView(store: eventViewerStore)
            .openMusicEventAuthoringPhase(authoringStore.phase)
            #if os(iOS)
            .sheet(item: $store.inAppBrowserPresentation) { presentation in
                InAppSafariView(url: presentation.url)
                    .ignoresSafeArea()
            }
            #endif
        }
        .task {
            await store.send(.task)?.value
        }
        .onOpenURL { url in
            store.send(.openURL(url))
        }
        #if os(iOS)
        .environment(
            \.openURL,
            OpenURLAction { url in
                guard url.isOpenMusicEventHandledURL else {
                    return .systemAction
                }
                store.send(.openURL(url))
                return .handled
            }
        )
        #endif
    }
}

struct OpenMusicEventAppSurfaceView: View {
    init(store: StoreOf<OpenMusicEventAppRoot>) {
        self.store = store
    }

    @Bindable var store: StoreOf<OpenMusicEventAppRoot>

    var body: some View {
        Group {
            switch store.variant {
            case .generic:
                OpenMusicEventBrowserView(
                    store: store.scope(\.browser, action: \.browser)
                )

            case .whiteLabel:
                if let whiteLabelStore = store.spawn(\.whiteLabelRoot) {
                    WhiteLabelRootView(store: whiteLabelStore)
                } else {
                    EmptyView()
                }
            }
        }
    }
}

private extension OpenMusicEventAppRoot {
    static func eventViewerState(
        eventID: OMERecord.Event.ID,
        target: EventTarget?
    ) throws -> OpenMusicEventWorkspace.State {
        try makeWorkspaceEventViewerState(
            workspace: workspace(for: eventID),
            eventID: eventID,
            target: target
        )
    }

    static func makeWorkspaceEventViewerState(
        workspace: SourceWorkspace,
        eventID: OMERecord.Event.ID,
        target: EventTarget?,
        pendingScheduleLaunchAction: EventViewer.ScheduleLaunchAction? = nil
    ) -> OpenMusicEventWorkspace.State {
        withDependencies {
            $0.defaultEventID = eventID
        } operation: {
            let authoringGrant = Shared<AuthoringGrant?>(.defaultAuthoringGrant)
            return OpenMusicEventAuthoringWorkspace<EventViewer>.state(
                workspace: workspace,
                grant: authoringGrant
            ) {
                EventViewer.State.route(
                    eventID: eventID,
                    target: target,
                    pendingScheduleLaunchAction: pendingScheduleLaunchAction
                )
            }
        }
    }

    static func workspace(
        for eventID: OMERecord.Event.ID
    ) throws -> SourceWorkspace {
        @Dependency(\.defaultDatabase) var database
        return try database.read { db in
            guard let workspace = try (EventSourceProvenanceRecord
                .where { $0.id.eq(eventID) }
                .fetchOne(db)?
                .workspace)
            else { throw OpenMusicEventAppRootError.eventHasNoSource(eventID) }
            return workspace
        }
    }
}

private enum OpenMusicEventAppRootError: Error {
    case eventHasNoSource(OMERecord.Event.ID)
}

private extension OpenMusicEventAppRoot.State {
    mutating func openExternalURL(_ url: URL) {
        #if os(iOS)
        guard url.isInAppBrowserURL else { return }
        inAppBrowserPresentation = InAppBrowserPresentation(url: url)
        #endif
    }

    var persistsSelectedEvent: Bool {
        variant.persistsSelectedEvent
    }
}

public struct InAppBrowserPresentation: Identifiable, Equatable, Sendable {
    let url: URL

    public var id: String {
        url.absoluteString
    }
}

private extension URL {
    var isInAppBrowserURL: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    var isOpenMusicEventHandledURL: Bool {
        OpenMusicEventOAuth.isCallbackURL(self)
            || AppRoute(url: self) != nil
            || isInAppBrowserURL
    }
}

#if os(iOS)
struct InAppSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(
        _ uiViewController: SFSafariViewController,
        context: Context
    ) {
    }
}
#endif
