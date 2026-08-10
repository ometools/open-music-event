import Foundation
import SkipFuse
import SwiftUI
import ATProtoOAuth
import BlueskyActorCache
import ComposableCalendarEvents
import ComposableNotifications
import ComposableNotificationsHTTP
import Dependencies
import ErrorHandling
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
#if canImport(UIKit)
import UIKit
#endif

/// A logger for the OpenMusicEventApp module.
let logger: Logger = Logger(subsystem: "fm.woody.openmusicevent", category: "OpenMusicEventApp")

public enum OpenMusicEventAppVariant: Equatable, Sendable {
    case generic
    case whiteLabel(WhiteLabelAppConfiguration)
}

extension OpenMusicEventAppVariant {
    var appConfiguration: OpenMusicEventAppConfiguration {
        switch self {
        case .generic:
            .openMusicEvent
        case let .whiteLabel(configuration) where configuration.handle == WickedWoodsWhiteLabel.handle:
            .wickedWoods
        case .whiteLabel:
            .openMusicEvent
        }
    }

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
        dependencies.notificationTokenClient = NotificationTokenClient(
            tokens: { OpenMusicEventAppDelegate.shared.notificationTokens() }
        )
        dependencies.notificationsClient = .http(
            baseURL: OpenMusicEventNotificationAuthorization.serverURL
        )
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

        dependencies.tangledPullReviewListSource = .tangledXRPC
        dependencies.tangledPullReviewSourceSnapshot = .openMusicEvent
        dependencies.sourceWorkspaceStorage = .live
        dependencies.sourceWorkspaceReferenceMigrator = .openMusicEvent
        dependencies.tangledSourceArchiveExtractor = .live
        dependencies[WorkspaceAuthoringActivationClient.self] = .live
    }

}

public typealias OpenMusicEventApplicationContent = OpenMusicEventAppRoot

/// The application's single authentication boundary. Its entire root receives the authenticated
/// OAuth session, authorization requests, and authorization broker from `OAuthAuthorization`.
public typealias OpenMusicEventApplication = OAuthAuthorization<OpenMusicEventApplicationContent>

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
    let store: StoreOf<OpenMusicEventApplication>
    @AppStorage(TechnicalDetails.userDefaultsKey) var technicalDetailsUserPreference = false
    @Environment(\.sourceRecordComparisonStyle) var sourceRecordComparisonStyle

    /* SKIP @bridge */public init() {
        self.store = OpenMusicEventAppDelegate.store
    }

    @MainActor
    public init(store: StoreOf<OpenMusicEventApplication>) {
        self.store = store
    }

    @MainActor
    public init(variant: OpenMusicEventAppVariant) {
        self.store = Self.makeStore(variant: variant)
    }

    public var body: some View {
#if os(Android)
        @Bindable var authenticationStore = store.scope(
            \.authentication,
            action: \.authentication
        )
        let applicationContentStore = store.scope(
            \.content,
            action: \.content
        )

        OpenMusicEventAppRootView(
            store: applicationContentStore
        )
            .sheet(
                item: $authenticationStore.scope(
                    \.authorization,
                    action: \.authorization
                )
            ) { authorizationStore in
                OpenMusicEventAuthorizationFlowSheetView(store: authorizationStore)
            }
            .onOpenURL { url in
                store.send(.authentication(.handleOpenURL(.init(url))))
            }
            .environment(
                \.showsTechnicalDetails,
                TechnicalDetails.isVisible(userPreference: technicalDetailsUserPreference)
            )
            .environment(
                \.sourceRecordComparisonStyle,
                SourceRecordComparisonStyle.openMusicEvent.overlaying(
                    sourceRecordComparisonStyle
                )
            )
            .task {
                logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            }
#else
        OpenMusicEventAuthorizationView(store: store) { rootStore in
            OpenMusicEventAppRootView(
                store: rootStore
            )
        }
            .environment(
                \.showsTechnicalDetails,
                TechnicalDetails.isVisible(userPreference: technicalDetailsUserPreference)
            )
            .environment(
                \.sourceRecordComparisonStyle,
                SourceRecordComparisonStyle.openMusicEvent.overlaying(
                    sourceRecordComparisonStyle
                )
            )
            .task {
                logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            }
#endif
    }

    @MainActor
    public static func makeStore(
        variant: OpenMusicEventAppVariant
    ) -> StoreOf<OpenMusicEventApplication> {
        let selectedEventRestoration = selectedEventRestoration(for: variant)
        return withDependencies {
            $0.openMusicEventAppConfiguration = variant.appConfiguration
        } operation: {
            StoreOf<OpenMusicEventApplication>(
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
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
/* SKIP @bridge */public final class OpenMusicEventAppDelegate : Sendable {
    /* SKIP @bridge */public static let shared = OpenMusicEventAppDelegate()

    @MainActor
    static let store = OpenMusicEventApplicationRootView.makeStore(variant: .generic)

    private let notificationTokenContinuation: AsyncStream<Push.Destination>.Continuation
    private let notificationTokenStream: AsyncStream<Push.Destination>

    private init() {
        let (tokenStream, tokenContinuation) = AsyncStream<Push.Destination>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.notificationTokenContinuation = tokenContinuation
        self.notificationTokenStream = tokenStream
    }

    public func notificationTokens() -> AsyncStream<Push.Destination> {
        notificationTokenStream
    }

    /* SKIP @bridge */public func onInit() {
//        OME.bootstrapIfNeeded()
        send(.initialized)
        logger.debug("onInit")
    }

    /* SKIP @bridge */public func onLaunch() {
        send(.launched)
        logger.debug("onLaunch")
#if canImport(UIKit)
        Task { @MainActor in
            let wasRegistered = UIApplication.shared.isRegisteredForRemoteNotifications
            logger.info(
                "Requesting remote notification registration; already registered: \(wasRegistered, privacy: .public)"
            )
            UIApplication.shared.registerForRemoteNotifications()
            let isRegisteredAfterRequest = UIApplication.shared.isRegisteredForRemoteNotifications
            logger.info(
                "Submitted remote notification registration request; registered after submission: \(isRegisteredAfterRequest, privacy: .public)"
            )
        }
#endif
        enforceStoredAuthenticationFreshness()
    }

    /* SKIP @bridge */public func onRegisteredForRemoteNotifications(deviceToken: Data) {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            logger.error("Remote notification registration has no application bundle identifier")
            return
        }
#if SKIP
        logger.info("Remote notification destination available for \(bundleIdentifier)")
#else
        logger.info(
            "Remote notification destination available for \(bundleIdentifier, privacy: .public)"
        )
#endif
        let value = deviceToken.map { String(format: "%02x", $0) }.joined()
        notificationTokenContinuation.yield(
            .apns(
                Push.APNS(
                    applicationID: .init(rawValue: bundleIdentifier),
                    deviceToken: .init(rawValue: value)
                )
            )
        )
    }

    /* SKIP @bridge */public func onRemoteNotificationRegistrationFailed(
        errorDescription: String
    ) {
#if SKIP
        logger.error("Remote notification registration failed: \(errorDescription)")
#else
        logger.error(
            "Remote notification registration failed: \(errorDescription, privacy: .public)"
        )
#endif
    }

    /// Preserves provider JSON until the notifications feature transforms it into an app signal.
    /* SKIP @bridge */public func onRemoteNotification(json: String) {
        sendNotification(
            NotificationEvent(json: json, delivery: .contentAvailable)
        )
    }

    /// Preserves a notification delivered while the application is in the foreground.
    /* SKIP @bridge */public func onForegroundNotification(json: String) {
        sendNotification(
            NotificationEvent(json: json, delivery: .foreground)
        )
    }

    /// Preserves the notification and action that brought the user into the application.
    /* SKIP @bridge */public func onNotificationInteraction(
        json: String,
        actionIdentifier: String?
    ) {
        sendNotification(
            NotificationEvent(
                json: json,
                delivery: .userInteraction(actionIdentifier: actionIdentifier)
            )
        )
    }

    /* SKIP @bridge */public func onResume() {
        send(.resumed)
        logger.debug("onResume")
        enforceStoredAuthenticationFreshness()
    }

    /* SKIP @bridge */public func onPause() {
        send(.paused)
        logger.debug("onPause")
    }

    /* SKIP @bridge */public func onStop() {
        send(.stopped)
        logger.debug("onStop")
    }

    /* SKIP @bridge */public func onDestroy() {
        send(.destroyed)
        logger.debug("onDestroy")
    }

    /* SKIP @bridge */public func onLowMemory() {
        send(.lowMemory)
        logger.debug("onLowMemory")
    }

    private func send(_ event: AppDelegateEvent) {
        Task { @MainActor in
            Self.store.send(.content(.appDelegateEvent(event)))
        }
    }

    private func sendNotification(_ event: NotificationEvent) {
        Task { @MainActor in
            Self.store.send(.content(.notificationEvent(event)))
        }
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
