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
            serviceEnvironment: OpenMusicEventServiceEnvironment = .production,
            selectedEventIDAtLaunch: Event.ID? = nil,
            workspaceRestorationErrorAtLaunch: (any Error)? = nil
        ) {
            _installedEvents = FetchAll(InstalledEvent.all)
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
                self.destination = .eventViewer(
                    OpenMusicEventAppRoot.makeEventViewerState(
                        eventID: selectedEventIDAtLaunch,
                        target: nil,
                        pendingScheduleLaunchAction: .jumpToCurrentTime
                    )
                )
            }
            if let configuration = variant
                .whiteLabelConfiguration(for: serviceEnvironment) {
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
        @Trigger<Push.Destination> public var notificationDestination
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

        @FetchAll public var installedEvents: [InstalledEvent]
        @Fetch public var notificationIndicatorSummary: ApplicationNotificationIndicatorSummary
        @Fetch public var notificationSubscriptions: Set<NotificationSubscription>

        public var selectedEventID: Event.ID? {
            appState?.selectedEventID
        }
    }

    public enum Action {
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
        case eventViewer(EventViewer)
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.applicationIconBadgeClient) var applicationIconBadgeClient
    @Dependency(\.brandedEventRouteClaims) var brandedEventRouteClaims
    @Dependency(\.notificationsClient) var notificationsClient
    @Dependency(\.eventRecords) var eventRecords
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

        let persistSelectedEvent: (Event.ID?, State) -> Void = { eventID, state in
            guard state.persistsSelectedEvent else { return }
            do {
                try database.write { db in
                    try AppState.update {
                        $0.selectedEventURI = #bind(eventID)
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
                case .browser:
                    break

                case .destination:
                    break

                case let .handleNavigationRequest(request):
                    switch request {
                    case let .event(eventID, target):
                        store.addTask {
                            let task = try store.send(.openRoute(.event(eventID, target)))
                            await task?.value
                        }

                    case let .externalURL(url):
                        state.openExternalURL(url)
                    }

                case let .openRoute(route):
                    switch route.navigationRequest {
                    case let .event(eventID, target):
                        let persistsSelectedEvent = state.persistsSelectedEvent
                        let routeRequestID = uuid()
                        state.activeRouteRequestID = routeRequestID
                        state.eventEntry = EventEntryState(
                            id: routeRequestID,
                            route: route
                        )
                        store.addTask {
                            do {
                                let installedEventID = try await eventRecords.install(eventID)
                                var routeIsActive = false
                                let activeRouteCheck = try store.modify {
                                    routeIsActive = $0.activeRouteRequestID == routeRequestID
                                }
                                await activeRouteCheck?.value
                                guard routeIsActive else { return }

                                let eventViewer = Self.makeEventViewerState(
                                    eventID: installedEventID,
                                    target: target
                                )
                                let mount = try store.modify { state in
                                    guard state.eventEntry?.id == routeRequestID else { return }
                                    state.destination = .eventViewer(eventViewer)
                                    state.eventEntry = nil
                                    if persistsSelectedEvent {
                                        persistSelectedEvent(installedEventID, state)
                                    }
                                }
                                await mount?.value
                            } catch {
                                var routeIsActive = false
                                let activeRouteCheck = try store.modify {
                                    routeIsActive = $0.activeRouteRequestID == routeRequestID
                                }
                                await activeRouteCheck?.value
                                guard routeIsActive else {
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
                        let task = try store.send(.openRoute(route))
                        await task?.value
                    }

                case .openURL(let url):
                    if let route = AppRoute(
                        url: url,
                        brandedClaims: brandedEventRouteClaims
                    ) {
                        store.addTask {
                            await Task.yield()
                            let task = try store.send(.openRoute(route))
                            await task?.value
                        }
                    } else {
                        state.openExternalURL(url)
                    }

                case .task:
                    break
                }
            }
            Scope(\.browser) {
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
                let task = try store.send(.handleNavigationRequest(request))
                await task?.value
            }
        }
        .onEvent(NotificationSubscriptionsRefreshRequested.self) { _, _ in
            store.addTask {
                let subscriptions = try await database.read {
                    try ApplicationNotificationSubscriptionsRequest().fetch($0)
                }
                try await notificationsClient.replaceSubscriptions(subscriptions)
            }
        }
        .onEvent(EventViewerDismissalRequested.self) { eventID, state in
            guard state.destination?.eventViewer?.id == eventID else {
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
        .onTrigger(store.appDelegateEvent) { event, state in
            switch event {
            case .launched, .resumed:
                let permissions = state.$permissions
                store.addTask {
                    try await permissions.load()
                }
            default:
                break
            }
        }
        .spawn(\.errorNotifications) {
            ErrorNotifications()
        }
        .ifLet(\.destination) {
            Destination.body
        }
        .ifLet(\.whiteLabelRoot) {
            WhiteLabelRoot()
        }
        .notificationSubscriptions(\.notificationSubscriptions)
        .notifications(
            appDelegateEventTrigger: \.appDelegateEvent,
            contentTrigger: \.notificationContent,
            destinationTrigger: \.notificationDestination,
            notificationEventTrigger: \.notificationEvent,
            signalTrigger: \.notificationSignal
        )
    }
}

extension OpenMusicEventAppRoot.State: ErrorNotificationRootState {}

public struct OpenMusicEventAppRootView: View {
    public init(
        store: StoreOf<OpenMusicEventAppRoot>,
        serviceEnvironment: OpenMusicEventServiceEnvironment,
        isServiceEnvironmentSelectionEnabled: Bool,
        isServiceEnvironmentSwitching: Bool,
        serviceEnvironmentSelected: @escaping (OpenMusicEventServiceEnvironment) -> Void
    ) {
        self.store = store
        self.serviceEnvironment = serviceEnvironment
        self.isServiceEnvironmentSelectionEnabled = isServiceEnvironmentSelectionEnabled
        self.isServiceEnvironmentSwitching = isServiceEnvironmentSwitching
        self.serviceEnvironmentSelected = serviceEnvironmentSelected
    }

    @Bindable var store: StoreOf<OpenMusicEventAppRoot>
    let serviceEnvironment: OpenMusicEventServiceEnvironment
    let isServiceEnvironmentSelectionEnabled: Bool
    let isServiceEnvironmentSwitching: Bool
    let serviceEnvironmentSelected: (OpenMusicEventServiceEnvironment) -> Void

    public var body: some View {
        OpenMusicEventAppSurfaceView(
            store: store,
            serviceEnvironment: serviceEnvironment,
            isServiceEnvironmentSelectionEnabled: isServiceEnvironmentSelectionEnabled,
            isServiceEnvironmentSwitching: isServiceEnvironmentSwitching,
            serviceEnvironmentSelected: serviceEnvironmentSelected
        )
        .accessibilityIdentifier("app.root")
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
                .scope(\.destination)
                .eventViewer
        ) { eventViewerStore in
            EventViewerView(store: eventViewerStore)
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
    init(
        store: StoreOf<OpenMusicEventAppRoot>,
        serviceEnvironment: OpenMusicEventServiceEnvironment,
        isServiceEnvironmentSelectionEnabled: Bool,
        isServiceEnvironmentSwitching: Bool,
        serviceEnvironmentSelected: @escaping (OpenMusicEventServiceEnvironment) -> Void
    ) {
        self.store = store
        self.serviceEnvironment = serviceEnvironment
        self.isServiceEnvironmentSelectionEnabled = isServiceEnvironmentSelectionEnabled
        self.isServiceEnvironmentSwitching = isServiceEnvironmentSwitching
        self.serviceEnvironmentSelected = serviceEnvironmentSelected
    }

    @Bindable var store: StoreOf<OpenMusicEventAppRoot>
    let serviceEnvironment: OpenMusicEventServiceEnvironment
    let isServiceEnvironmentSelectionEnabled: Bool
    let isServiceEnvironmentSwitching: Bool
    let serviceEnvironmentSelected: (OpenMusicEventServiceEnvironment) -> Void

    var body: some View {
        Group {
            switch store.variant {
            case .generic:
                OpenMusicEventBrowserView(
                    store: store.scope(\.browser),
                    serviceEnvironment: serviceEnvironment,
                    isServiceEnvironmentSelectionEnabled: isServiceEnvironmentSelectionEnabled,
                    isServiceEnvironmentSwitching: isServiceEnvironmentSwitching,
                    serviceEnvironmentSelected: serviceEnvironmentSelected
                )

            case .whiteLabel, .whiteLabelEnvironments:
                if let whiteLabelStore = store.spawn(\.whiteLabelRoot) {
                    WhiteLabelRootView(
                        store: whiteLabelStore,
                        serviceEnvironment: serviceEnvironment,
                        isServiceEnvironmentSelectionEnabled: isServiceEnvironmentSelectionEnabled,
                        isServiceEnvironmentSwitching: isServiceEnvironmentSwitching,
                        serviceEnvironmentSelected: serviceEnvironmentSelected
                    )
                } else {
                    EmptyView()
                }
            }
        }
    }
}

private extension OpenMusicEventAppRoot {
    static func makeEventViewerState(
        eventID: Event.ID,
        target: EventTarget?,
        pendingScheduleLaunchAction: EventViewer.ScheduleLaunchAction? = nil
    ) -> EventViewer.State {
        withDependencies {
            $0.defaultEventID = eventID
        } operation: {
            EventViewer.State.route(
                eventID: eventID,
                target: target,
                pendingScheduleLaunchAction: pendingScheduleLaunchAction
            )
        }
    }
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
