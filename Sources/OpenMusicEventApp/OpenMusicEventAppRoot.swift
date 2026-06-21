import ComposableArchitecture2
import Dependencies
import ErrorHandling
import OpenMusicEventAppEventViewer
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import SQLiteData
import SwiftUI

@Feature
public struct OpenMusicEventAppRoot {
    public init() {}

    public struct State {
        public init() {}

        public var authentication = AuthenticationCoordinator.State()
        public var browser = Spawn(OpenMusicEventBrowser.State())
        public var errorNotifications = Spawn(ErrorNotifications.State())
        public var eventViewer: Spawn<EventViewer>?
        public var hasRestoredSelectedEventAtLaunch = false
        public var launchEventViewer: Spawn<EventViewer>?

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
    @Dependency(\.continuousClock) var clock
    @Dependency(\.errorNotificationPresentation) var errorNotificationPresentation

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
            if state.selectedEventID != eventID {
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
                    clearSelectedEvent()

                case .handleNavigationRequest(let request):
                    switch request {
                    case let .event(eventID, target):
                        openEventViewer(eventID, target, &state)

                    case .externalURL:
                        break
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

                    guard let route = AppRoute(url: url) else { return }
                    store.addTask {
                        try store.send(.openRoute(route))
                    }

                case .task:
                    store.addTask {
                        let selections = await errorNotificationPresentation.selections()
                        for await error in selections {
                            try store.post(
                                key: ErrorNotificationSelected.self,
                                value: error
                            )
                        }
                    }
                }
            }

            Scope(\.authentication, action: \.authentication) {
                AuthenticationCoordinator()
            }
        }
        .onChange(of: store.selectedEventID, initial: true) { _, newValue, state in
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
        .onChange(of: store.launchEventViewer?.state.eventID) { oldValue, newValue, _ in
            if oldValue != nil, newValue == nil {
                clearSelectedEvent()
            }
        }
        .onEvent(NavigationRequested.self) { request, _ in
            store.addTask {
                try store.send(.handleNavigationRequest(request))
            }
        }
        .onEvent(OpenMusicEventAuthorizationPresentationRequested.self) { request, _ in
            store.addTask {
                try store.send(.authentication(.authorizationPresentationRequested(request)))
            }
        }
        .onEvent(ErrorReported.self) { error, state in
            state.errorNotifications.state.report(error)
            store.addTask {
                await errorNotificationPresentation.show(.error(error))
            }
            store.addTask {
                try await clock.sleep(for: ErrorNotifications.automaticDismissDelay)
                try store.modify {
                    $0.errorNotifications.state.dismiss(id: error.id)
                }
            }
        }
        .spawn(\.browser) {
            OpenMusicEventBrowser()
        }
        .spawn(\.errorNotifications) {
            ErrorNotifications()
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
    }

    @ViewBuilder
    private var content: some View {
        AuthenticationCoordinatorView(
            store: store.scope(\.authentication, action: \.authentication)
        ) {
            if let launchEventViewerStore = store.spawn(\.launchEventViewer) {
                EventViewerView(store: launchEventViewerStore)
            } else {
                browserView
            }
        }
    }

    @ViewBuilder
    private var browserView: some View {
        OpenMusicEventBrowserView(store: store.spawn(\.browser))
            .openMusicEventFullScreenCover(
                isPresented: eventViewerIsPresented,
                onDismiss: {
                    store.send(.eventViewerDismissed)
                }
            ) {
                if let eventViewerStore = store.spawn(\.eventViewer) {
                    EventViewerView(store: eventViewerStore)
                }
            }
    }

    private var eventViewerIsPresented: Binding<Bool> {
        Binding(
            get: { store.eventViewer != nil },
            set: { isPresented in
                if !isPresented {
                    store.send(.eventViewerDismissed)
                }
            }
        )
    }
}
