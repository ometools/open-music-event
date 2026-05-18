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
        public var eventViewer: Spawn<EventViewer>?
        public var latestError: HandledError?

        @FetchOne(AppState.find(1))
        public var appState: AppState?

        public var selectedEventID: OMERecord.Event.ID? {
            appState?.selectedEventID
        }
    }

    public enum Action {
        case eventViewerDismissed
        case handleNavigationRequest(NavigationRequest)
        case latestErrorNotificationTapped
        case openRoute(AppRoute)
        case openURL(URL)
        case task
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.eventImagePrefetch) var eventImagePrefetch

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

            case .latestErrorNotificationTapped:
                break

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
                break
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
            state.latestError = error
        }
        .spawn(\.browser) {
            OpenMusicEventBrowser()
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
        #if os(iOS)
        browserView
        #else
        browserView
            .globalNotificationOverlay(
                error: store.latestError,
                action: {
                    store.send(.latestErrorNotificationTapped)
                }
            )
        #endif
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

public struct OpenMusicEventGlobalErrorWindowView: View {
    public init(store: StoreOf<OpenMusicEventAppRoot>) {
        self.store = store
    }

    @Bindable var store: StoreOf<OpenMusicEventAppRoot>

    public var body: some View {
        VStack(spacing: 0) {
            if let latestError = store.latestError {
                GlobalNotificationView(error: latestError) {
                    store.send(.latestErrorNotificationTapped)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.snappy, value: store.latestError?.id)
        .allowsHitTesting(store.latestError != nil)
    }
}

struct GlobalNotificationView: View {
    let error: HandledError
    let action: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                        }

                    Text("OpenMusicEvent")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text("now")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(error.message.resource)
                    .font(.subheadline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.primary)
            .padding(12)
            .frame(maxWidth: 420, alignment: .leading)
            .background(
                notificationSurface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(notificationStroke, lineWidth: 1)
            }
            .shadow(color: notificationShadow, radius: 18, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var notificationSurface: Color {
        switch colorScheme {
        case .dark:
            Color(red: 0.18, green: 0.18, blue: 0.19).opacity(0.98)
        case .light:
            Color.white.opacity(0.98)
        @unknown default:
            Color.primary.opacity(0.92)
        }
    }

    private var notificationStroke: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.12)
        case .light:
            Color.black.opacity(0.08)
        @unknown default:
            Color.primary.opacity(0.08)
        }
    }

    private var notificationShadow: Color {
        switch colorScheme {
        case .dark:
            Color.black.opacity(0.35)
        case .light:
            Color.black.opacity(0.16)
        @unknown default:
            Color.black.opacity(0.20)
        }
    }
}

private extension View {
    func globalNotificationOverlay(
        error: HandledError?,
        action: @escaping () -> Void
    ) -> some View {
        overlay(alignment: .top) {
            if let error {
                GlobalNotificationView(error: error, action: action)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
        }
    }
}
