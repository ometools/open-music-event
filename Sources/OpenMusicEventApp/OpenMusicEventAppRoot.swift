import ComposableArchitecture2
import Dependencies
import ErrorHandling
import OpenMusicEventAppEventViewer
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
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
                self.whiteLabelBootstrap = Spawn(
                    WhiteLabelBootstrap.State(configuration: configuration)
                )
            }
        }

        public var authentication = AuthenticationCoordinator.State()
        public var browser = Spawn(OpenMusicEventBrowser.State())
        public var errorNotifications = Spawn(ErrorNotifications.State())
        public var eventViewer: Spawn<EventViewer>?
        public var hasRestoredSelectedEventAtLaunch = false
        var inAppBrowserPresentation: InAppBrowserPresentation?
        public var launchEventViewer: Spawn<EventViewer>?
        public var variant: OpenMusicEventAppVariant
        public var whiteLabelBootstrap: Spawn<WhiteLabelBootstrap>? = nil

        @FetchOne(AppState.find(1))
        public var appState: AppState?

        public var selectedEventID: OMERecord.Event.ID? {
            appState?.selectedEventID
        }
    }

    public enum Action {
        case authentication(AuthenticationCoordinator.Action)
        case eventViewerDismissed
        case handleNavigationRequest(NavigationRequest)
        case openRoute(AppRoute)
        case openURL(URL)
        case task
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

        let openEventViewer: (OMERecord.Event.ID, EventTarget?, inout State) -> Void = { eventID, target, state in
            store.withDependencies {
                if state.launchEventViewer != nil {
                    state.launchEventViewer = Spawn(.route(eventID: eventID, target: target))
                } else {
                    state.eventViewer = Spawn(.route(eventID: eventID, target: target))
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

                case .eventViewerDismissed:
                    state.eventViewer = nil
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

            store.withDependencies {
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
        .ifLet(\.whiteLabelBootstrap) {
            WhiteLabelBootstrap()
        }
        .ifLet(\.eventViewer) {
            EventViewer()
                .openMusicEventAuthenticatedSession()
        }
        .ifLet(\.launchEventViewer) {
            EventViewer()
                .openMusicEventAuthenticatedSession()
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
        content
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

    @ViewBuilder
    private var content: some View {
        if let launchEventViewerStore = store.spawn(\.launchEventViewer) {
            AuthenticationCoordinatorView(store: authenticationStore) {
                EventViewerView(store: launchEventViewerStore)
            }
        } else {
            AuthenticationCoordinatorView(
                store: authenticationStore,
                isPresentationEnabled: rootAuthenticationPresentationEnabled
            ) {
                surfaceView
            }
        }
    }

    private var authenticationStore: StoreOf<AuthenticationCoordinator> {
        store.scope(\.authentication, action: \.authentication)
    }

    @ViewBuilder
    private var surfaceView: some View {
        mainContent
            .openMusicEventFullScreenCover(
                item: eventViewerStore,
                onDismiss: {
                    store.send(.eventViewerDismissed)
                }
            ) { eventViewerStore in
                AuthenticationCoordinatorView(store: authenticationStore) {
                    EventViewerView(store: eventViewerStore)
                }
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch store.variant {
        case .generic:
            OpenMusicEventBrowserView(store: store.spawn(\.browser))

        case .whiteLabel:
            if let whiteLabelStore = store.spawn(\.whiteLabelBootstrap) {
                WhiteLabelBootstrapView(store: whiteLabelStore)
            }
        }
    }

    private var eventViewerStore: Binding<StoreOf<EventViewer>?> {
        Binding(
            get: { store.spawn(\.eventViewer) },
            set: { eventViewerStore in
                if eventViewerStore == nil {
                    store.send(.eventViewerDismissed)
                }
            }
        )
    }

    private var rootAuthenticationPresentationEnabled: Bool {
        store.eventViewer == nil
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
