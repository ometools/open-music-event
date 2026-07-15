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
        public init(
            variant: OpenMusicEventAppVariant = .generic,
            selectedEventIDAtLaunch: OMERecord.Event.ID? = nil
        ) {
            self.variant = variant
            if variant.persistsSelectedEvent, let selectedEventIDAtLaunch {
                self.eventViewer = OpenMusicEventAppRoot.withEventViewerWorkspaceDependencies(
                    eventID: selectedEventIDAtLaunch
                ) {
                    Spawn(.route(
                        eventID: selectedEventIDAtLaunch,
                        target: nil
                    ))
                }
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
        public var eventViewer: Spawn<EventViewer>?
        var inAppBrowserPresentation: InAppBrowserPresentation?
        public var variant: OpenMusicEventAppVariant
        public var whiteLabelRoot: Spawn<WhiteLabelRoot>? = nil

        @FetchOne(AppState.find(1))
        public var appState: AppState?

        public var selectedEventID: OMERecord.Event.ID? {
            appState?.selectedEventID
        }

        var currentAuthoringMode: Authoring.Mode? {
            guard let authoringMode = whiteLabelRoot?.state.authoringMode,
                  authoringMode.isAuthoring
            else { return nil }
            return authoringMode
        }
    }

    public enum Action {
        case authentication(AuthenticationCoordinator.Action)
        case authoringNavigationAuthorized(OMERecord.Event.ID, EventTarget?, Authoring.Scope)
        case handleNavigationRequest(NavigationRequest)
        case localEventDeletionRequested(OMERecord.Event.ID)
        case openRoute(AppRoute)
        case openURL(URL)
        case task
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.authoringPolicy) var authoringPolicy
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
            (OMERecord.Event.ID, EventTarget?, Authoring.Mode?, inout State) -> Void = { eventID, target, authoringMode, state in
            Self.withEventViewerWorkspaceDependencies(eventID: eventID) {
                state.eventViewer = Spawn(.route(
                    eventID: eventID,
                    target: target,
                    authoringMode: authoringMode
                ))
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

        let authorizeAuthoringNavigation:
            (OMERecord.Event.ID, EventTarget?) -> Void = { eventID, target in
            let authoringPolicy = authoringPolicy
            store.addTask {
                let result = await store.withErrorHandling(
                    fallbackMessage: .authoringAuthorizationFailed,
                    operation: .authoringAuthorization
                ) {
                    try await authoringPolicy.authorize(
                        Authoring.Request(
                            eventID: eventID,
                            editorTarget: target
                        )
                    )
                }
                guard let scope = result else { return }
                try store.send(.authoringNavigationAuthorized(eventID, target, scope))
            }
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

        let openEventViewerAfterAuthorization:
            (OMERecord.Event.ID, EventTarget?, inout State) -> Void = { eventID, target, state in
            if let authoringMode = state.currentAuthoringMode {
                openEventViewer(eventID, target, authoringMode, &state)
                return
            }

            guard target?.eventFeature.isEditorFeature == true else {
                openEventViewer(eventID, target, nil, &state)
                return
            }

            do {
                switch try authoringPolicy.mode(.event(eventID)) {
                case let .authoring(scope):
                    openEventViewer(eventID, target, .authoring(scope), &state)

                case .attendee:
                    authorizeAuthoringNavigation(eventID, target)
                }
            } catch {
                authorizeAuthoringNavigation(eventID, target)
            }
        }

        Features {
            Update { state, action in
                switch action {
                case .authentication:
                    break

                case let .authoringNavigationAuthorized(eventID, target, scope):
                    openEventViewer(eventID, target, .authoring(scope), &state)

                case .handleNavigationRequest(let request):
                    switch request {
                    case let .event(eventID, target):
                        openEventViewerAfterAuthorization(eventID, target, &state)

                    case let .externalURL(url):
                        state.openExternalURL(url)
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
                            if $0.eventViewer?.state.eventID == eventID {
                                $0.eventViewer = nil
                            }
                        }
                    }

                case .openRoute(let route):
                    if case let .event(eventID, target) = route.navigationRequest {
                        openEventViewerAfterAuthorization(eventID, target, &state)
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
                    if let eventID = state.eventViewer?.state.eventID {
                        prefetchAssetsOnOpen(eventID)
                    }
                }
            }

            Scope(\.authentication, action: \.authentication) {
                AuthenticationCoordinator()
            }
        }
        .onChange(of: store.eventViewer?.state.eventID) { oldValue, newValue, state in
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
        .onEvent(NavigationRequested.self) { request, _ in
            store.addTask {
                try store.send(.handleNavigationRequest(request))
            }
        }
        .onEvent(LocalEventDeletionRequested.self) { eventID, _ in
            store.addTask {
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
            EventViewer()
                .openMusicEventAuthenticatedSession()
                .transformDependency(\.self) { (dependencies: inout DependencyValues) in
                    guard dependencies.sourceEditingSession == nil else { return }
                    do {
                        guard let eventID = store.eventViewer?.eventID,
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
            isPresentationEnabled: store.eventViewer == nil
        ) {
            OpenMusicEventAppSurfaceView(store: store)
        }
        .openMusicEventViewerPresentation(item: eventViewerPresentation) { eventViewerStore in
            AuthenticationCoordinatorView(
                store: store.scope(\.authentication, action: \.authentication)
            ) {
                EventViewerView(store: eventViewerStore)
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

    private var eventViewerPresentation: Binding<StoreOf<EventViewer>?> {
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
    static func withEventViewerWorkspaceDependencies<Value>(
        eventID: OMERecord.Event.ID,
        operation: () -> Value
    ) -> Value {
        withDependencies {
            guard $0.sourceEditingSession == nil else { return }
            do {
                guard let sourceEditingSession = try $0.sourceWorkspaceDatabase
                    .event(eventID)?
                    .sourceEditingSession
                else { return }
                $0.sourceEditingSession = sourceEditingSession
            } catch {
                reportIssue(error)
            }
        } operation: {
            operation()
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

private extension Authoring.Request {
    init(eventID: OMERecord.Event.ID, editorTarget: EventTarget?) {
        switch editorTarget?.eventFeature {
        case .workspace:
            self.init(
                subject: .event(eventID),
                feature: .workspace,
                action: .manageWorkspace
            )

        case .settings:
            self.init(
                subject: .event(eventID),
                feature: .settings,
                action: .enterAuthoring
            )

        case .about,
             .communications,
             .contactInfo,
             .contributors,
             .location,
             .notifications,
             .posters,
             .schedule,
             .search,
             .siteMap,
             .stages,
             .none:
            self.init(
                subject: .event(eventID),
                feature: .event,
                action: .enterAuthoring
            )
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
