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
import SwiftUI
#if os(iOS)
import SafariServices
#endif

@Feature
public struct OpenMusicEventAppRoot {
    public init() {}

    public typealias WorkspaceEventViewer = OpenMusicEventSourceEditing.Authoring<EventViewer>

    public struct State {
        public init(
            variant: OpenMusicEventAppVariant = .generic,
            selectedEventIDAtLaunch: OMERecord.Event.ID? = nil
        ) {
            self.variant = variant
            if variant.persistsSelectedEvent, let selectedEventIDAtLaunch {
                self.eventViewer = Spawn(
                    OpenMusicEventAppRoot.makeWorkspaceEventViewerState(
                        eventID: selectedEventIDAtLaunch,
                        target: nil,
                        pendingScheduleLaunchAction: .jumpToCurrentTime
                    )
                )
            }
            if case let .whiteLabel(configuration) = variant {
                self.whiteLabelRoot = Spawn(
                    WhiteLabelRoot.State(configuration: configuration)
                )
            }
        }

        public var authentication = AuthenticationCoordinator.State()
        public var browser = Spawn(OpenMusicEventBrowser.State())
        public var errorNotifications = Spawn(ErrorNotifications.State())
        public var eventViewer: Spawn<WorkspaceEventViewer>?
        var inAppBrowserPresentation: InAppBrowserPresentation?
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
        case handleNavigationRequest(NavigationRequest)
        case localEventDeletionRequested(OMERecord.Event.ID)
        case openRoute(AppRoute)
        case openURL(URL)
        case task
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.eventImagePrefetch) var eventImagePrefetch
    public var body: some Feature {
//        let _ = Self._logChanges()

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

        let openEventViewer:
            (OMERecord.Event.ID, EventTarget?, inout State) -> Void = { eventID, target, state in
            let workspaceID = Self.workspaceID(for: eventID)
            let mountedAuthoring = state.mountedAuthoring(for: workspaceID)
            state.eventViewer = Spawn(
                Self.makeWorkspaceEventViewerState(
                    eventID: eventID,
                    target: target,
                    mountedAuthoring: mountedAuthoring
                )
            )
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

        let reportAuthenticationError: ((any Error)?) -> Void = { error in
            guard let error else { return }
            store.addTask {
                await store.reportError(
                    error,
                    fallbackMessage: .authenticationAuthorizationFailed,
                    operation: .authenticationAuthorization
                )
            }
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
                case .authentication:
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
                            if $0.eventViewer?.state.content.eventID == eventID {
                                $0.eventViewer = nil
                            }
                        }
                    }

                case .openRoute(let route):
                    if case let .event(eventID, target) = route.navigationRequest {
                        openEventViewer(eventID, target, &state)
                    }

                case .openURL(let url):
                    if OpenMusicEventOAuth.isCallbackURL(url) {
                        store.addTask {
                            await Task.yield()
                            try store.send(.authentication(.handleOpenURL(.init(url))))
                        }
                        return
                    }

                    if let route = AppRoute(url: url) {
                        store.addTask {
                            await Task.yield()
                            try store.send(.openRoute(route))
                        }
                    } else {
                        state.openExternalURL(url)
                    }

                case .task:
                    if let eventID = state.eventViewer?.state.content.eventID {
                        prefetchAssetsOnOpen(eventID)
                    }
                }
            }

            Scope(\.authentication, action: \.authentication) {
                AuthenticationCoordinator()
            }
        }
        .onChange(of: store.eventViewer?.state.content.eventID) { oldValue, newValue, state in
            if state.persistsSelectedEvent, oldValue != nil, newValue == nil {
                clearSelectedEvent()
            }
        }
        .onChange(of: store.authentication.authorization?.error) { _, error, _ in
            reportAuthenticationError(error?.originalError)
        }
        .onChange(of: store.authentication.directAuthorization?.error) { _, error, _ in
            reportAuthenticationError(error?.originalError)
        }
        .onEvent(NavigationRequested.self) { request, state in
            handleNavigationRequest(request, &state)
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
        .ifLet(\.whiteLabelRoot) {
            WhiteLabelRoot()
        }
        .ifLet(\.eventViewer) {
            WorkspaceEventViewer {
                EventViewer()
            }
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
        AuthenticationCoordinatorView(
            store: store.scope(\.authentication, action: \.authentication),
            isPresentationEnabled: store.eventViewer == nil
        ) {
            OpenMusicEventAppSurfaceView(store: store)
        }
        .openMusicEventViewerPresentation(item: eventViewerPresentation) { authoringStore in
            let eventViewerStore = authoringStore.scope(\.content, action: \.content)
            AuthenticationCoordinatorView(
                store: store.scope(\.authentication, action: \.authentication)
            ) {
                EventViewerView(store: eventViewerStore)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if authoringStore.entry.isRunning {
                    ProgressView("Preparing workspace")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.bar)
                } else if let entryFailure = authoringStore.entryFailure {
                    Text(entryFailure.message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.bar)
                }
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

    private var eventViewerPresentation: Binding<StoreOf<OpenMusicEventAppRoot.WorkspaceEventViewer>?> {
        Binding {
            store.spawn(\.eventViewer)
        } set: { eventViewerStore in
            if eventViewerStore == nil {
                $store.eventViewer.wrappedValue = nil
            }
        }
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
    ) -> WorkspaceEventViewer.State {
        if let mountedAuthoring {
            return WorkspaceEventViewer.State(
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
        return WorkspaceEventViewer.State(
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
           eventViewer.state.workspaceID == workspaceID {
            return .init(
                grant: eventViewer.state.$grant
            )
        }
        if let whiteLabelAuthoring = whiteLabelRoot?
            .state
            .teamWorkspaceDetail,
           whiteLabelAuthoring.state.workspaceID == workspaceID {
            return .init(
                grant: whiteLabelAuthoring.state.$grant
            )
        }
        if let myEventsAuthoring = browser
            .state
            .myEvents
            .state
            .teamWorkspaceDetail,
           myEventsAuthoring.workspaceID == workspaceID {
            return .init(
                grant: myEventsAuthoring.$grant
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
