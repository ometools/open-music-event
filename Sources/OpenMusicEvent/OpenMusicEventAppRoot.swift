import ComposableArchitecture2
import Dependencies
import OpenMusicEventAppEventViewer
import SQLiteData
import SwiftUI

@Feature
public struct OpenMusicEventAppRoot {
    public init() {}

    public struct State {
        public init() {}

        public var browser = Spawn(OpenMusicEventBrowser.State())
        public var eventViewer: EventViewer.State?

        @FetchOne(AppState.select { $0.selectedEventID })
        public var selectedEventID: OMERecord.Event.ID?
    }

    public enum Action {
        case eventViewer(EventViewer.Action)
        case eventViewerDismissed
        case handleNavigationRequest(NavigationRequest)
        case openRoute(AppRoute)
        case openURL(URL)
        case task
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        let _ = Self._logChanges()

        Update { state, action in
            switch action {
            case .eventViewer(.closeButtonTapped), .eventViewerDismissed:
                state.eventViewer = nil
                try? database.write { db in
                    try AppState.update {
                        $0.selectedEventID = #bind(nil)
                    }
                    .execute(db)
                }

            case .eventViewer:
                break

            case .handleNavigationRequest(let request):
                switch request {
                case let .event(eventID, target):
                    state.eventViewer = .route(eventID: eventID, target: target)
                    if state.selectedEventID != eventID {
                        try? database.write { db in
                            try AppState.update {
                                $0.selectedEventID = #bind(eventID)
                            }
                            .execute(db)
                        }
                    }

                case .externalURL:
                    break
                }

            case .openRoute(let route):
                if case let .event(eventID, target) = route.navigationRequest {
                    state.eventViewer = .route(eventID: eventID, target: target)
                    try? database.write { db in
                        try AppState.update {
                            $0.selectedEventID = #bind(eventID)
                        }
                        .execute(db)
                    }
                }

            case .openURL(let url):
                guard let route = AppRoute(url: url) else { return }
                store.addTask {
                    try store.send(.openRoute(route))
                }

            case .task:
                break
            }
        }
        .onChange(of: store.selectedEventID, initial: true) { _, newValue, state in
            if let newValue {
                if state.eventViewer?.eventID != newValue {
                    state.eventViewer = .route(eventID: newValue, target: nil)
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
        .spawn(\.browser) {
            OpenMusicEventBrowser()
        }
        .ifLet(\.eventViewer, action: \.eventViewer) {
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
        browserView
            .task {
                await store.send(.task)?.value
            }
            .onOpenURL { url in
                store.send(.openURL(url))
            }
    }

    @ViewBuilder
    private var browserView: some View {
        #if os(iOS)
        OpenMusicEventBrowserView(store: store.spawn(\.browser))
            .fullScreenCover(
                item: $store.scope(state: \.eventViewer, action: \.eventViewer),
                onDismiss: {
                    store.send(.eventViewerDismissed)
                }
            ) { eventViewerStore in
                EventViewerView(store: eventViewerStore)
            }
        #else
        OpenMusicEventBrowserView(store: store.spawn(\.browser))
            .sheet(
                item: $store.scope(state: \.eventViewer, action: \.eventViewer),
                onDismiss: {
                    store.send(.eventViewerDismissed)
                }
            ) { eventViewerStore in
                EventViewerView(store: eventViewerStore)
            }
        #endif
    }
}
