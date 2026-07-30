import ComposableArchitecture2
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
            whiteLabelLoadedRootAtLaunch: WhiteLabelRoot.LoadedRoot? = nil
        ) {
            self.variant = variant
            if variant.persistsSelectedEvent, let selectedEventIDAtLaunch {
                self.destination = .eventViewer(
                    OpenMusicEventAppRoot.makeWorkspaceEventViewerState(
                        eventID: selectedEventIDAtLaunch,
                        target: nil,
                        pendingScheduleLaunchAction: .jumpToCurrentTime
                    )
                )
            }
            if case let .whiteLabel(configuration) = variant {
                self.whiteLabelRoot = Spawn(
                    WhiteLabelRoot.State(
                        configuration: configuration,
                        loadedRootAtLaunch: whiteLabelLoadedRootAtLaunch
                    )
                )
            }
        }

        public var browser = Spawn(OpenMusicEventBrowser.State())
        public var destination: Destination.State?
        public var errorNotifications = Spawn(ErrorNotifications.State())
        var inAppBrowserPresentation: InAppBrowserPresentation?
        public var variant: OpenMusicEventAppVariant
        public var whiteLabelRoot: Spawn<WhiteLabelRoot>? = nil

        @FetchOne(AppState.find(1))
        public var appState: AppState?

        public var selectedEventID: OMERecord.Event.ID? {
            appState?.selectedEventID
        }

        public var eventViewer: OpenMusicEventAuthoring<EventViewer>.State? {
            get {
                guard case let .eventViewer(eventViewer) = destination else { return nil }
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
    }

    public enum Action {
        case destination(Destination.Action)
        case handleNavigationRequest(NavigationRequest)
        case localEventDeletionRequested(OMERecord.Event.ID)
        case openRoute(AppRoute)
        case openURL(URL)
        case task
    }

    @Feature
    public enum Destination {
        case eventViewer(OpenMusicEventAuthoring<EventViewer>)
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.eventImagePrefetch) var eventImagePrefetch
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

        let openEventViewer:
            (OMERecord.Event.ID, EventTarget?, inout State) -> Void = { eventID, target, state in
            let workspaceID = Self.workspaceID(for: eventID)
            let mountedAuthoring = state.mountedAuthoring(for: workspaceID)
            state.eventViewer = Self.makeWorkspaceEventViewerState(
                eventID: eventID,
                target: target,
                mountedAuthoring: mountedAuthoring
            )
            prefetchAssetsOnOpen(eventID)
        }

        let handleNavigationRequest:
            (NavigationRequest, inout State) -> Void = { request, state in
            switch request {
            case let .event(eventID, target):
                openEventViewer(eventID, target, &state)

            case let .externalURL(url):
                state.openExternalURL(url)
            }
        }

        Features {
            Update { state, action in
                switch action {
                case .destination:
                    break

                case .handleNavigationRequest(let request):
                    handleNavigationRequest(request, &state)

                case let .localEventDeletionRequested(eventID):
                    store.addTask {
                        let didDelete: Void? = await store.withErrorHandling(
                            fallbackMessage: .eventDeletionFailed,
                            operation: .eventDeletion
                        ) {
                            try database.write { db in
                                try MyEventsDeletion.deleteCreatedLocalEvents([eventID], in: db)
                            }
                        }
                        guard didDelete != nil else { return }
                        try store.modify {
                            if $0.eventViewer?.id == eventID {
                                $0.eventViewer = nil
                            }
                        }
                    }

                case .openRoute(let route):
                    if case let .event(eventID, target) = route.navigationRequest {
                        openEventViewer(eventID, target, &state)
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
                    if let eventID = state.eventViewer?.id {
                        prefetchAssetsOnOpen(eventID)
                    }
                }
            }
        }
        .onChange(of: store.eventViewer?.id) { _, eventID, state in
            guard state.persistsSelectedEvent else { return }
            let organizerID = eventID?.organizerID
            let eventID = eventID?.eventID
            try? database.write { db in
                try AppState.update {
                    $0.organizerID = #bind(organizerID)
                    $0.eventID = #bind(eventID)
                }
                .execute(db)
            }
        }
        .onEvent(NavigationRequested.self) { request, state in
            handleNavigationRequest(request, &state)
        }
        .onEvent(OAuthAuthorizationInvalidated.self) { _, state in
            state.eventViewer?.content.invalidateAuthoring()
        }
        .onEvent(LocalEventDeletionRequested.self) { eventID, _ in
            store.addTask {
                await Task.yield()
                try store.send(.localEventDeletionRequested(eventID))
            }
        }
        .presentReportedErrors()
        .spawn(\.browser) {
            OpenMusicEventBrowser()
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
            item: $store.scope(\.destination, action: \.destination).eventViewer
        ) { authorizationStore in
            #if os(Android)
            let authoringStore = authorizationStore.scope(\.content, action: \.content)
            let eventViewerStore = authoringStore
                .scope(\.content, action: \.content)
            EventViewerView(
                store: eventViewerStore,
                authoringAdmission: authoringStore.admission
            )
            #else
            OpenMusicEventAuthorizationView(store: authorizationStore) { authoringStore in
                let eventViewerStore = authoringStore.scope(\.content, action: \.content)
                EventViewerView(
                    store: eventViewerStore,
                    authoringAdmission: authoringStore.admission
                )
            }
            #if os(iOS)
            .sheet(item: $store.inAppBrowserPresentation) { presentation in
                InAppSafariView(url: presentation.url)
                    .ignoresSafeArea()
            }
            #endif
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
                OpenMusicEventBrowserView(store: store.spawn(\.browser))

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
    struct MountedAuthoring {
        var grant: Shared<AuthoringGrant?>
    }

    static func makeWorkspaceEventViewerState(
        eventID: OMERecord.Event.ID,
        target: EventTarget?,
        mountedAuthoring: MountedAuthoring? = nil,
        pendingScheduleLaunchAction: EventViewer.ScheduleLaunchAction? = nil
    ) -> OpenMusicEventAuthoring<EventViewer>.State {
        if let mountedAuthoring {
            return OpenMusicEventAuthoring<EventViewer>.State(
                storage: OpenMusicEventOAuth.storage
            ) {
                OpenMusicEventSourceEditing.Authoring<EventViewer>.State(
                    workspaceID: workspaceID(for: eventID),
                    grant: mountedAuthoring.grant,
                    initiallyRequestsEntry: target?.eventFeature.isEditorFeature == true
                ) {
                    EventViewer.State.route(
                        eventID: eventID,
                        target: target,
                        pendingScheduleLaunchAction: pendingScheduleLaunchAction
                    )
                }
            }
        }
        return OpenMusicEventAuthoring<EventViewer>.State(
            storage: OpenMusicEventOAuth.storage
        ) {
            OpenMusicEventSourceEditing.Authoring<EventViewer>.State(
                workspaceID: workspaceID(for: eventID),
                initiallyRequestsEntry: target?.eventFeature.isEditorFeature == true
            ) {
                EventViewer.State.route(
                    eventID: eventID,
                    target: target,
                    pendingScheduleLaunchAction: pendingScheduleLaunchAction
                )
            }
        }
    }

    static func workspaceID(
        for eventID: OMERecord.Event.ID
    ) -> EditingWorkspaceRecord.ID {
        @Dependency(\.defaultDatabase) var database
        return (
            try? database.read { db in
                try EventEditingWorkspaceRecord
                    .where { $0.id.eq(eventID) }
                    .fetchOne(db)?
                    .workspaceID
            }
        ) ?? EditingWorkspaceRecord.ID(localEventID: eventID)
    }
}

private extension OpenMusicEventAppRoot.State {
    func mountedAuthoring(
        for workspaceID: EditingWorkspaceRecord.ID
    ) -> OpenMusicEventAppRoot.MountedAuthoring? {
        if let eventViewer,
           eventViewer.content.workspaceID == workspaceID {
            return .init(
                grant: eventViewer.content.$grant
            )
        }
        if let whiteLabelAuthoring = whiteLabelRoot?
            .state
            .teamWorkspaceDetail,
           whiteLabelAuthoring.state.content.workspaceID == workspaceID {
            return .init(
                grant: whiteLabelAuthoring.state.content.$grant
            )
        }
        if let myEventsAuthoring = browser
            .state
            .myEvents
            .state
            .teamWorkspaceDetail,
           myEventsAuthoring.content.workspaceID == workspaceID {
            return .init(
                grant: myEventsAuthoring.content.$grant
            )
        }
        return nil
    }

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
