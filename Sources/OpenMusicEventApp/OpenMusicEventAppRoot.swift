import ComposableArchitecture2
import ComposableAuthoring
import ComposableAuthoringWorkspace
import ComposableWorkspace
import Dependencies
import ErrorHandling
import IssueReporting
import OpenMusicEventAppEventViewer
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventSourceEditing
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
            whiteLabelLoadedRootAtLaunch: WhiteLabelRoot.LoadedRoot? = nil,
            workspaceRestorationErrorAtLaunch: (any Error)? = nil
        ) {
            self.variant = variant
            self.workspaceRestorationError = workspaceRestorationErrorAtLaunch
            if workspaceRestorationErrorAtLaunch == nil,
               variant.persistsSelectedEvent,
               let selectedEventIDAtLaunch {
                do {
                    let workspaceID = try OpenMusicEventAppRoot.workspaceID(
                        for: selectedEventIDAtLaunch
                    )
                    self.destination = .eventViewer(
                        OpenMusicEventAppRoot.makeWorkspaceEventViewerState(
                            workspaceID: workspaceID,
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
        @DebugSnapshotIgnored var workspaceRestorationError: (any Error)?

        @FetchOne(AppState.find(1))
        public var appState: AppState?

        public var selectedEventID: OMERecord.Event.ID? {
            appState?.selectedEventID
        }

        public var eventViewer: OpenMusicEventEventAuthoring.State? {
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
        case eventViewer(OpenMusicEventEventAuthoring)
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
            (OMERecord.Event.ID, EventTarget?, inout State) throws -> Void = { eventID, target, state in
            let workspaceID = try Self.workspaceID(for: eventID)
            state.eventViewer = Self.makeWorkspaceEventViewerState(
                workspaceID: workspaceID,
                eventID: eventID,
                target: target
            )
            prefetchAssetsOnOpen(eventID)
        }

        let handleNavigationRequest:
            (NavigationRequest, inout State) throws -> Void = { request, state in
            switch request {
            case let .event(eventID, target):
                try openEventViewer(eventID, target, &state)

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
                    do {
                        try handleNavigationRequest(request, &state)
                    } catch {
                        store.addTask {
                            await store.reportError(
                                error,
                                fallbackMessage: .eventWorkspaceRestoreFailed,
                                operation: .eventWorkspaceRestore
                            )
                        }
                    }

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
                            if $0.eventViewer?
                                .content
                                .authoring
                                .content
                                .content
                                .id == eventID {
                                $0.eventViewer = nil
                            }
                        }
                    }

                case .openRoute(let route):
                    do {
                        try handleNavigationRequest(route.navigationRequest, &state)
                    } catch {
                        store.addTask {
                            await store.reportError(
                                error,
                                fallbackMessage: .eventWorkspaceRestoreFailed,
                                operation: .eventWorkspaceRestore
                            )
                        }
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
                    if let eventID = state.eventViewer?
                        .content
                        .authoring
                        .content
                        .content
                        .id {
                        prefetchAssetsOnOpen(eventID)
                    }
                }
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
        .onChange(
            of: store.eventViewer?
                .content
                .authoring
                .content
                .content
                .id
        ) { _, eventID, state in
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
            do {
                try handleNavigationRequest(request, &state)
            } catch {
                store.addTask {
                    await store.reportError(
                        error,
                        fallbackMessage: .eventWorkspaceRestoreFailed,
                        operation: .eventWorkspaceRestore
                    )
                }
            }
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
            let authoringWorkspaceStore = authorizationStore.scope(\.content, action: \.content)
            let authoringStore = authoringWorkspaceStore
                .scope(\.authoring, action: \.authoring)
            let workspaceStore = authoringStore.scope(\.content, action: \.content)
            let eventViewerStore = workspaceStore.scope(\.content, action: \.content)
            EventViewerView(
                store: eventViewerStore,
                authoringAdmission: authoringStore.admission
            )
            .openMusicEventWorkspacePhase(workspaceStore.phase)
            #else
            OpenMusicEventAuthorizationView(store: authorizationStore) {
                authoringWorkspaceStore in
                let authoringStore = authoringWorkspaceStore
                    .scope(\.authoring, action: \.authoring)
                let workspaceStore = authoringStore.scope(\.content, action: \.content)
                let eventViewerStore = workspaceStore.scope(\.content, action: \.content)
                EventViewerView(
                    store: eventViewerStore,
                    authoringAdmission: authoringStore.admission
                )
                .openMusicEventWorkspacePhase(workspaceStore.phase)
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
    static func makeWorkspaceEventViewerState(
        workspaceID: EditingWorkspaceRecord.ID,
        eventID: OMERecord.Event.ID,
        target: EventTarget?,
        pendingScheduleLaunchAction: EventViewer.ScheduleLaunchAction? = nil
    ) -> OpenMusicEventEventAuthoring.State {
        OpenMusicEventEventAuthoring.State(
            storage: OpenMusicEventOAuth.storage
        ) {
            OpenMusicEventAuthoringWorkspace<EventViewer>.state(
                workspaceID: workspaceID
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
    ) throws -> EditingWorkspaceRecord.ID {
        @Dependency(\.defaultDatabase) var database
        return try database.read { db in
            if let workspaceID = try (EventEditingWorkspaceRecord
                    .where { $0.id.eq(eventID) }
                    .fetchOne(db)?
                    .workspaceID) {
                return workspaceID
            }

            if let sourceBaselineID = try (EventSourceProvenanceRecord
                .where { $0.id.eq(eventID) }
                .fetchOne(db)?
                .sourceBaselineID) {
                return EditingWorkspaceRecord.ID(
                    sourceBaselineID: sourceBaselineID
                )
            }

            return EditingWorkspaceRecord.ID(localEventID: eventID)
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
