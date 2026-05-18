import ComposableArchitecture2
import Dependencies
import ErrorHandling
import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import SQLiteData
import SwiftUI

@Feature
public struct OpenMusicEventAppRoot {
    public init() {}

    public struct State {
        public init() {}

        public var browser = Spawn(OpenMusicEventBrowser.State())
        public var errorNotifications = Spawn(ErrorNotifications.State())
        public var eventViewer: Spawn<EventViewer>?

        @FetchOne(AppState.find(1))
        public var appState: AppState?

        public var selectedEventID: OMERecord.Event.ID? {
            appState?.selectedEventID
        }
    }

    public enum Action {
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

        Update { state, action in
            switch action {
            case .eventViewerDismissed:
                state.eventViewer = nil
                try? database.write { db in
                    try AppState.update {
                        $0.organizerID = #bind(nil as OMERecord.Organizer.ID?)
                        $0.eventID = #bind(nil as OMERecord.ID<OMERecord.Event>?)
                    }
                    .execute(db)
                }

            case .handleNavigationRequest(let request):
                switch request {
                case let .event(eventID, target):
                    state.eventViewer = Spawn(.route(eventID: eventID, target: target))
                    if state.selectedEventID != eventID {
                        try? database.write { db in
                            try AppState.update {
                                $0.organizerID = #bind(eventID.organizerID)
                                $0.eventID = #bind(eventID.eventID)
                            }
                            .execute(db)
                        }
                    }
                    store.addTask {
                        do {
                            try await eventImagePrefetch.prefetchAssetsOnOpen(eventID)
                        } catch {
                        }
                    }

                case .externalURL:
                    break
                }

            case .openRoute(let route):
                if case let .event(eventID, target) = route.navigationRequest {
                    state.eventViewer = Spawn(.route(eventID: eventID, target: target))
                    try? database.write { db in
                        try AppState.update {
                            $0.organizerID = #bind(eventID.organizerID)
                            $0.eventID = #bind(eventID.eventID)
                        }
                            .execute(db)
                    }
                    store.addTask {
                        do {
                            try await eventImagePrefetch.prefetchAssetsOnOpen(eventID)
                        } catch {
                        }
                    }
                }

            case .openURL(let url):
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
        .onChange(of: store.selectedEventID, initial: true) { _, newValue, state in
            if let newValue {
                if state.eventViewer?.state.eventID != newValue {
                    state.eventViewer = Spawn(.route(eventID: newValue, target: nil))
                }
                store.addTask {
                    do {
                        try await eventImagePrefetch.prefetchAssetsOnOpen(newValue)
                    } catch {
                    }
                }
            } else {
                state.eventViewer = nil
            }
        }
        .onEvent(NavigationRequested.self) { request, _ in
            store.addTask {
                try store.send(.handleNavigationRequest(request))
            }
        }
        .onEvent(ErrorReported.self) { error, state in
            state.errorNotifications.state.report(error)
            store.addTask {
                await errorNotificationPresentation.show(error)
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
        browserView
    }

    @ViewBuilder
    private var browserView: some View {
        #if os(iOS)
        OpenMusicEventBrowserView(store: store.spawn(\.browser))
            .fullScreenCover(
                isPresented: eventViewerIsPresented,
                onDismiss: {
                    store.send(.eventViewerDismissed)
                }
            ) {
                if let eventViewerStore = store.spawn(\.eventViewer) {
                    EventViewerView(store: eventViewerStore)
                }
            }
        #else
        OpenMusicEventBrowserView(store: store.spawn(\.browser))
            .sheet(
                isPresented: eventViewerIsPresented,
                onDismiss: {
                    store.send(.eventViewerDismissed)
                }
            ) {
                if let eventViewerStore = store.spawn(\.eventViewer) {
                    EventViewerView(store: eventViewerStore)
                }
            }
        #endif
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
