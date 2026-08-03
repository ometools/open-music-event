import Foundation
import SkipFuse
import SwiftUI
import ATProtoOAuth
import BlueskyActorCache
import ComposableCalendarEvents
import Dependencies
import SQLiteData
import ComposableArchitecture2
import OpenMusicEventAppEventViewer
import OpenMusicEventAuthentication
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import SourceControlClient
#if !OME_ARCHIVE_SOURCE_ONLY && canImport(SourceControlClientGit)
import SourceControlClientGit
#endif
import SourceEditing
import TCATProtoAuthentication

/// A logger for the OpenMusicEventApp module.
let logger: Logger = Logger(subsystem: "fm.woody.openmusicevent", category: "OpenMusicEventApp")

public enum OpenMusicEventAppVariant: Equatable, Sendable {
    case generic
    case whiteLabel(WhiteLabelAppConfiguration)
}

extension OpenMusicEventAppVariant {
    var persistsSelectedEvent: Bool {
        switch self {
        case .generic:
            true
        case .whiteLabel:
            true
        }
    }
}

public enum OpenMusicEventAppDependencyProfile: Sendable {
    case generic
    case whiteLabel
}

extension OME {
    public static func prepareDependencies(_ dependencies: inout DependencyValues) throws {
        try dependencies.bootstrapDatabase()

        prepareDependencies(
            &dependencies,
            database: dependencies.defaultDatabase
        )
    }

    public static func prepareDependencies(
        _ dependencies: inout DependencyValues,
        database: any DatabaseWriter
    ) {
        dependencies.defaultDatabase = database
        dependencies.calendarEvents = .openMusicEventAndAtmo(database: database)
        OpenMusicEventOAuth.prepareDependencies(&dependencies)
        OpenMusicEventActorTypeahead.prepareDependencies(&dependencies)
        BlueskyActorCacheDependencies.prepareDependencies(&dependencies)
#if !OME_ARCHIVE_SOURCE_ONLY && canImport(SourceControlClientGit)
        dependencies.sourceControl = LibGit2SourceControlClient.live
#endif
        let resolveRevision: SourceWorkspaceRevisionResolver = { repository, ref in
            @Dependency(\.sourceControl) var sourceControl
            return try await sourceControl.resolveRevision(
                ResolveRevisionRequest(repository: repository, ref: ref)
            )
        }
        dependencies[SourceWorkspacePreparationClient.self] = .openMusicEvent(
            resolveRevision: resolveRevision
        )
        dependencies[WorkspaceReferenceUpdateClient.self] = .openMusicEvent(
            resolveRevision: resolveRevision
        )
        dependencies[SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self] = .openMusicEvent
        dependencies.sourceWorkspacePatchConversion = .live

        dependencies.tangledPullReviewListSource = .constellationBackfill
        dependencies.tangledPullReviewSourceSnapshot = .openMusicEvent
        dependencies.sourceWorkspaceStorage = .live
        dependencies.sourceWorkspaceReferenceMigrator = .openMusicEvent
        dependencies.tangledSourceArchiveExtractor = .live
        dependencies[OpenMusicEventSourceEditing.AuthoringPolicyClient.self] = .openMusicEvent
        dependencies[WorkspaceAuthoringActivationClient.self] = .live
    }

}

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// The default implementation merely loads the `ContentView` for the app and logs a message.
struct OpenMusicEventAuthorizationContext: FeatureEnvironmentKey {
    var broker: OAuth.AuthorizationBroker

    static let liveValue = Self(
        broker: OAuth.AuthorizationBroker { requirement in
            throw OAuth.AuthorizationRequired.signIn(requirement)
        }
    )
    static let testValue = liveValue
}

public struct OpenMusicEventApplication: FeatureProtocol {
    public typealias State = OAuthAuthorization<OpenMusicEventAppRoot>.State
    public typealias Action = OAuthAuthorization<OpenMusicEventAppRoot>.Action

    private let authorization: OpenMusicEventAuthorizationContext
    private let makeContent: @Sendable () -> OpenMusicEventAppRoot
    private let requestCenter: AuthorizationRequestCenter
    private let storage: OAuthSessionStorage

    public init(
        storage: OAuthSessionStorage,
        requestCenter: AuthorizationRequestCenter = AuthorizationRequestCenter(),
        makeContent: @escaping @Sendable () -> OpenMusicEventAppRoot
    ) {
        self.storage = storage
        self.requestCenter = requestCenter
        self.makeContent = makeContent
        self.authorization = OpenMusicEventAuthorizationContext(
            broker: OAuthAuthorizationRequests(center: requestCenter)
                .automaticallyUpgradingCurrentAccount(storage: storage)
                .broker()
        )
    }

    public var body: some FeatureProtocol<State, Action> {
        OAuthAuthorization(
            storage: storage,
            requestCenter: requestCenter,
            makeContent: makeContent
        )
        .environment(authorization)
    }
}

struct SelectedEventRestoration {
    var eventID: OMERecord.Event.ID?
    var error: (any Error)?

    init(
        eventID: OMERecord.Event.ID? = nil,
        error: (any Error)? = nil
    ) {
        self.eventID = eventID
        self.error = error
    }
}

/* SKIP @bridge */public struct OpenMusicEventApplicationRootView : View {
    @MainActor
    private static let genericStore = makeStore(variant: .generic)

    private let eventViewerPresentationLaunchAnimation: EventViewerPresentationLaunchAnimation
    let store: StoreOf<OpenMusicEventApplication>
    @AppStorage(TechnicalDetails.userDefaultsKey) var technicalDetailsUserPreference = false

    /* SKIP @bridge */public init() {
        let store = Self.genericStore
        self.eventViewerPresentationLaunchAnimation = Self.launchAnimation(for: store)
        self.store = store
    }

    @MainActor
    public init(store: StoreOf<OpenMusicEventApplication>) {
        self.eventViewerPresentationLaunchAnimation = Self.launchAnimation(for: store)
        self.store = store
    }

    @MainActor
    public init(variant: OpenMusicEventAppVariant) {
        let store = Self.makeStore(variant: variant)
        self.eventViewerPresentationLaunchAnimation = Self.launchAnimation(for: store)
        self.store = store
    }

    public var body: some View {
        OpenMusicEventAuthorizationView(store: store) { rootStore in
            OpenMusicEventAppRootView(store: rootStore)
        }
            .environment(
                \.eventViewerPresentationLaunchAnimation,
                eventViewerPresentationLaunchAnimation
            )
            .environment(
                \.showsTechnicalDetails,
                TechnicalDetails.isVisible(userPreference: technicalDetailsUserPreference)
            )
            .task {
                logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            }
    }

    @MainActor
    public static func makeStore(
        variant: OpenMusicEventAppVariant
    ) -> StoreOf<OpenMusicEventApplication> {
        let selectedEventRestoration = selectedEventRestoration(for: variant)
        return StoreOf<OpenMusicEventApplication>(
            initialState: .init(storage: OpenMusicEventOAuth.storage) {
                OpenMusicEventAppRoot.State(
                    variant: variant,
                    selectedEventIDAtLaunch: selectedEventRestoration.eventID,
                    workspaceRestorationErrorAtLaunch: selectedEventRestoration.error
                )
            }
        ) {
            OpenMusicEventApplication(storage: OpenMusicEventOAuth.storage) {
                OpenMusicEventAppRoot()
            }
            .presentAuthorizationFailures()
            .deliverAuthoringAuthorizationChanges()
        }
    }

    static func selectedEventRestoration(
        for variant: OpenMusicEventAppVariant
    ) -> SelectedEventRestoration {
        guard variant.persistsSelectedEvent else { return .init() }
        @Dependency(\.defaultDatabase) var database
        do {
            return SelectedEventRestoration(
                eventID: try database.read { db in
                    try AppState.find(1).fetchOne(db)?.selectedEventID
                }
            )
        } catch {
            return SelectedEventRestoration(error: error)
        }
    }

    @MainActor
    private static func launchAnimation(
        for store: StoreOf<OpenMusicEventApplication>
    ) -> EventViewerPresentationLaunchAnimation {
        store.content.eventViewer == nil ? .automatic : .disabled
    }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
/* SKIP @bridge */public final class OpenMusicEventAppDelegate : Sendable {
    /* SKIP @bridge */public static let shared = OpenMusicEventAppDelegate()

    private init() {
    }

    /* SKIP @bridge */public func onInit() {
//        OME.bootstrapIfNeeded()
        logger.debug("onInit")
    }

    /* SKIP @bridge */public func onLaunch() {
        logger.debug("onLaunch")
        enforceStoredAuthenticationFreshness()
    }

    /* SKIP @bridge */public func onResume() {
        logger.debug("onResume")
        enforceStoredAuthenticationFreshness()
    }

    /* SKIP @bridge */public func onPause() {
        logger.debug("onPause")
    }

    /* SKIP @bridge */public func onStop() {
        logger.debug("onStop")
    }

    /* SKIP @bridge */public func onDestroy() {
        logger.debug("onDestroy")
    }

    /* SKIP @bridge */public func onLowMemory() {
        logger.debug("onLowMemory")
    }

    private func enforceStoredAuthenticationFreshness() {
        @Dependency(\.openMusicEventAutomaticallyRefreshesStoredAuthentication)
        var automaticallyRefreshesStoredAuthentication

        guard automaticallyRefreshesStoredAuthentication else { return }
        Task {
            try? await OpenMusicEventOAuth.enforceStoredAuthenticationFreshness()
        }
    }
}
