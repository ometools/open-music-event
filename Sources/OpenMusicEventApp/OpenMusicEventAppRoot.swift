import ComposableArchitecture2
import Dependencies
import ErrorHandling
import IssueReporting
import OpenMusicEventAppEventViewer
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventSourceEditing
import SourceEditing
import SQLiteData
import SwiftUI
#if os(iOS)
import SafariServices
#endif

@Feature
public struct OpenMusicEventAppRoot {
    public init() {}

    public struct State {
        public init(variant: OpenMusicEventAppVariant = .generic) {
            self.variant = variant
            if case let .whiteLabel(configuration) = variant {
                self.whiteLabelRoot = Spawn(
                    WhiteLabelRoot.State(configuration: configuration)
                )
            }
        }

        public var authentication = AuthenticationCoordinator.State()
        public var browser = Spawn(OpenMusicEventBrowser.State())
        public var destination: Destination.State?
        public var errorNotifications = Spawn(ErrorNotifications.State())
        public var eventViewer: Spawn<EventViewer>? {
            get {
                guard case let .some(.eventViewer(eventViewer)) = destination else { return nil }
                return eventViewer
            }
            set {
                if let newValue {
                    destination = .eventViewer(newValue)
                } else {
                    destination = nil
                }
            }
        }
        public var hasRestoredSelectedEventAtLaunch = false
        var inAppBrowserPresentation: InAppBrowserPresentation?
        public var launchEventViewer: Spawn<EventViewer>?
        public var variant: OpenMusicEventAppVariant
        public var whiteLabelRoot: Spawn<WhiteLabelRoot>? = nil

        @FetchOne(AppState.find(1))
        public var appState: AppState?

        public var selectedEventID: OMERecord.Event.ID? {
            appState?.selectedEventID
        }
    }

    public enum Action {
        case authentication(AuthenticationCoordinator.Action)
        case destination(Destination.Action)
        case eventViewerDismissed
        case handleNavigationRequest(NavigationRequest)
        case openRoute(AppRoute)
        case openURL(URL)
        case task
    }

    @Feature
    public enum Destination {
        case eventViewer(Spawn<EventViewer>)
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.eventImagePrefetch) var eventImagePrefetch
    public var body: some Feature {
        let _ = Self._logChanges()

        let clearSelectedEvent: () -> Void = {
            try? database.write { db in
                try AppState.update {
                    $0.organizerID = #bind(nil as OMERecord.Organizer.ID?)
                    $0.eventID = #bind(nil as OMERecord.ID<OMERecord.Event>?)
                }
                .execute(db)
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

        let withEventViewerWorkspaceDependencies:
            (OMERecord.Event.ID, () -> Void) -> Void = { eventID, operation in
            withDependencies {
                guard $0.sourceEditingSession == nil else { return }
                do {
                    guard let sourceEditingSession = try $0.sourceWorkspaceDatabase
                        .event(eventID)?
                        .sourceEditingSession
                    else {
                        return
                    }
                    $0.sourceEditingSession = sourceEditingSession
                } catch {
                    reportIssue(error)
                }
            } operation: {
                operation()
            }
        }

        let openEventViewer: (OMERecord.Event.ID, EventTarget?, inout State) -> Void = { eventID, target, state in
            withEventViewerWorkspaceDependencies(eventID) {
                if state.launchEventViewer != nil {
                    state.launchEventViewer = Spawn(.route(eventID: eventID, target: target))
                } else {
                    state.destination = .eventViewer(Spawn(.route(eventID: eventID, target: target)))
                }
            }
            if state.persistsSelectedEvent, state.selectedEventID != eventID {
                try? database.write { db in
                    try AppState.update {
                        $0.organizerID = #bind(eventID.organizerID)
                        $0.eventID = #bind(eventID.eventID)
                    }
                    .execute(db)
                }
            }
            prefetchAssetsOnOpen(eventID)
        }

        Features {
            Update { state, action in
                switch action {
                case .authentication:
                    break

                case .destination:
                    break

                case .eventViewerDismissed:
                    state.destination = nil
                    if state.persistsSelectedEvent {
                        clearSelectedEvent()
                    }

                case .handleNavigationRequest(let request):
                    switch request {
                    case let .event(eventID, target):
                        openEventViewer(eventID, target, &state)

                    case let .externalURL(url):
                        state.openExternalURL(url)
                    }

                case .openRoute(let route):
                    if case let .event(eventID, target) = route.navigationRequest {
                        openEventViewer(eventID, target, &state)
                    }

                case .openURL(let url):
                    if OpenMusicEventOAuth.isCallbackURL(url) {
                        store.addTask {
                            try store.send(.authentication(.handleOpenURL(.init(url))))
                        }
                        return
                    }

                    if let route = AppRoute(url: url) {
                        store.addTask {
                            try store.send(.openRoute(route))
                        }
                    } else {
                        state.openExternalURL(url)
                    }

                case .task:
                    break
                }
            }

            Scope(\.authentication, action: \.authentication) {
                AuthenticationCoordinator()
            }
        }
        .onChange(of: store.selectedEventID, initial: true) { _, newValue, state in
            guard state.persistsSelectedEvent else { return }
            guard !state.hasRestoredSelectedEventAtLaunch else {
                if newValue == nil {
                    state.launchEventViewer = nil
                }
                return
            }

            state.hasRestoredSelectedEventAtLaunch = true
            guard let newValue else { return }

            withEventViewerWorkspaceDependencies(newValue) {
                state.launchEventViewer = Spawn(.route(eventID: newValue, target: nil))
            }
            prefetchAssetsOnOpen(newValue)
        }
        .onChange(of: store.launchEventViewer?.state.eventID) { oldValue, newValue, state in
            if state.persistsSelectedEvent, oldValue != nil, newValue == nil {
                clearSelectedEvent()
            }
        }
        .onEvent(NavigationRequested.self) { request, _ in
            store.addTask {
                try store.send(.handleNavigationRequest(request))
            }
        }
        .presentReportedErrors()
        .spawn(\.browser) {
            OpenMusicEventBrowser()
        }
        .spawn(\.errorNotifications) {
            ErrorNotifications()
        }
        .ifLet(\.whiteLabelRoot) {
            WhiteLabelRoot()
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
                .openMusicEventAuthenticatedSession()
                .transformDependency(\.self) { (dependencies: inout DependencyValues) in
                    guard dependencies.sourceEditingSession == nil else { return }
                    do {
                        guard let eventID = store.destination?.eventViewer?.eventID,
                              let sourceEditingSession = try dependencies.sourceWorkspaceDatabase
                                .event(eventID)?
                                .sourceEditingSession
                        else { return }
                        dependencies.sourceEditingSession = sourceEditingSession
                    } catch {
                        reportIssue(error)
                    }
                }
        }
        .ifLet(\.launchEventViewer) {
            EventViewer()
                .openMusicEventAuthenticatedSession()
                .transformDependency(\.self) { (dependencies: inout DependencyValues) in
                    guard dependencies.sourceEditingSession == nil else { return }
                    do {
                        guard let eventID = store.launchEventViewer?.eventID,
                              let sourceEditingSession = try dependencies.sourceWorkspaceDatabase
                                .event(eventID)?
                                .sourceEditingSession
                        else { return }
                        dependencies.sourceEditingSession = sourceEditingSession
                    } catch {
                        reportIssue(error)
                    }
                }
        }
    }
}

extension OpenMusicEventAppRoot.State: ErrorNotificationRootState {}

public struct OpenMusicEventAppRootView: View {
    public init(store: StoreOf<OpenMusicEventAppRoot>) {
        self.store = store
    }

    @Bindable var store: StoreOf<OpenMusicEventAppRoot>

    public var body: some View {
        AuthenticationCoordinatorView(
            store: store.scope(\.authentication, action: \.authentication),
            isPresentationEnabled: store.destination?.eventViewer == nil
        ) {
            if let launchEventViewerStore = store.spawn(\.launchEventViewer) {
                EventViewerView(store: launchEventViewerStore)
            } else {
                OpenMusicEventAppSurfaceView(store: store)
            }
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
        .sheet(item: $store.inAppBrowserPresentation) { presentation in
            InAppSafariView(url: presentation.url)
                .ignoresSafeArea()
        }
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
                OpenMusicEventBrowserView(store: store.spawn(\.browser))

            case .whiteLabel:
                if let whiteLabelStore = store.spawn(\.whiteLabelRoot) {
                    WhiteLabelRootView(store: whiteLabelStore)
                } else {
                    EmptyView()
                }
            }
        }
        .openMusicEventFullScreenCover(
            item: $store.scope(\.destination, action: \.destination).eventViewer,
            onDismiss: {
                store.send(.eventViewerDismissed)
            }
        ) { eventViewerStore in
            AuthenticationCoordinatorView(
                store: store.scope(\.authentication, action: \.authentication)
            ) {
                EventViewerView(store: eventViewerStore)
            }
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
        switch variant {
        case .generic:
            true
        case .whiteLabel:
            false
        }
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
