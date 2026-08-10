import ComposableArchitecture2
import ComposableAuthoring
import ComposableAuthoringWorkspace
import ComposableWorkspace
import ComposableNotifications
import Dependencies
import ErrorHandling
import IssueReporting
import OpenMusicEventAppEventViewer
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
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
        public var errorNotifications = Spawn(ErrorNotifications.State())
        @Trigger<AppDelegateEvent> public var appDelegateEvent
        @Trigger<NotificationContent<AppRoute>> public var notificationContent
        @Trigger<NotificationSignal> public var notificationSignal
        @SharedReader(.devicePermissions) public var permissions: DevicePermissions
        var inAppBrowserPresentation: InAppBrowserPresentation?
        public var variant: OpenMusicEventAppVariant
        public var whiteLabelRoot: Spawn<WhiteLabelRoot>? = nil
        @DebugSnapshotIgnored var workspaceRestorationError: (any Error)?

        @FetchOne(AppState.find(1))
        public var appState: AppState?

        public var selectedEventID: OMERecord.Event.ID? {
            appState?.selectedEventID
        }
    }

    public enum Action {
        case appDelegateEvent(AppDelegateEvent)
        case browser(OpenMusicEventBrowser.Action)
        case destination(Destination.Action)
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
    @Dependency(\.eventImagePrefetch) var eventImagePrefetch
    @Dependency(\.omeEventInstallation) var eventInstallation
    public var body: some Feature {
//        let _ = Self._logChanges()

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

                case .handleNavigationRequest(let request):
                    switch request {
                    case let .event(eventID, target):
                        let eventURI = OMERecord.Event.reference(id: eventID).uri
                        let persistsSelectedEvent = state.persistsSelectedEvent
                        store.addTask {
                            let installedEventID = await store.withErrorHandling(
                                fallbackMessage: .eventInstallationFailed,
                                operation: .eventInstallation
                            ) {
                                try await eventInstallation.ensureInstalled(eventURI)
                            }
                            guard let installedEventID else { return }
                            let eventViewer = await store.withErrorHandling(
                                fallbackMessage: .eventWorkspaceRestoreFailed,
                                operation: .eventWorkspaceRestore
                            ) {
                                try Self.eventViewerState(
                                    eventID: installedEventID,
                                    target: target
                                )
                            }
                            guard let eventViewer else { return }
                            try store.modify { $0.destination = .eventViewer(eventViewer) }
                            if persistsSelectedEvent {
                                persistSelectedEvent(installedEventID, store.state)
                            }
                            do {
                                try await eventImagePrefetch.prefetchAssetsOnOpen(installedEventID)
                            } catch {
                            }
                        }

                    case let .externalURL(url):
                        state.openExternalURL(url)
                    }

                case .openRoute(let route):
                    switch route.navigationRequest {
                    case let .event(eventID, target):
                        let eventURI = OMERecord.Event.reference(id: eventID).uri
                        let persistsSelectedEvent = state.persistsSelectedEvent
                        store.addTask {
                            let installedEventID = await store.withErrorHandling(
                                fallbackMessage: .eventInstallationFailed,
                                operation: .eventInstallation
                            ) {
                                try await eventInstallation.ensureInstalled(eventURI)
                            }
                            guard let installedEventID else { return }
                            let eventViewer = await store.withErrorHandling(
                                fallbackMessage: .eventWorkspaceRestoreFailed,
                                operation: .eventWorkspaceRestore
                            ) {
                                try Self.eventViewerState(
                                    eventID: installedEventID,
                                    target: target
                                )
                            }
                            guard let eventViewer else { return }
                            try store.modify { $0.destination = .eventViewer(eventViewer) }
                            if persistsSelectedEvent {
                                persistSelectedEvent(installedEventID, store.state)
                            }
                            do {
                                try await eventImagePrefetch.prefetchAssetsOnOpen(installedEventID)
                            } catch {
                            }
                        }

                    case let .externalURL(url):
                        state.openExternalURL(url)
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
        .onEvent(NavigationRequested.self) { request, state in
            switch request {
            case let .event(eventID, target):
                let eventURI = OMERecord.Event.reference(id: eventID).uri
                let persistsSelectedEvent = state.persistsSelectedEvent
                store.addTask {
                    let installedEventID = await store.withErrorHandling(
                        fallbackMessage: .eventInstallationFailed,
                        operation: .eventInstallation
                    ) {
                        try await eventInstallation.ensureInstalled(eventURI)
                    }
                    guard let installedEventID else { return }
                    let eventViewer = await store.withErrorHandling(
                        fallbackMessage: .eventWorkspaceRestoreFailed,
                        operation: .eventWorkspaceRestore
                    ) {
                        try Self.eventViewerState(
                            eventID: installedEventID,
                            target: target
                        )
                    }
                    guard let eventViewer else { return }
                    try store.modify { $0.destination = .eventViewer(eventViewer) }
                    if persistsSelectedEvent {
                        persistSelectedEvent(installedEventID, store.state)
                    }
                    do {
                        try await eventImagePrefetch.prefetchAssetsOnOpen(installedEventID)
                    } catch {
                    }
                }

            case let .externalURL(url):
                state.openExternalURL(url)
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
            guard state.variant == .generic else { return }
            guard case .sourceAvailable = signal else { return }
            store.addTask {
                try await store.browser.browse.refresh()?.value
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
        .notifications(
            appDelegateEventTrigger: \.appDelegateEvent,
            contentTrigger: \.notificationContent,
            signalTrigger: \.notificationSignal
        )
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
