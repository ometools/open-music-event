import Foundation
import SkipFuse
import SwiftUI
import BlueskyActorCache
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
import SourceControlClientGit
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

        OpenMusicEventOAuth.prepareDependencies(&dependencies)
        OpenMusicEventActorTypeahead.prepareDependencies(&dependencies)
        BlueskyActorCacheDependencies.prepareDependencies(&dependencies)

        dependencies.sourceControl = LibGit2SourceControlClient.live
        dependencies.tangledSourceCheckout = .git

        dependencies[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        dependencies[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] = .openMusicEventCalendar

        dependencies.sourcePatchPublisher = .openMusicEventTangled

        dependencies.tangledPullReviewListSource = .constellationBackfill
        dependencies.sourceReferenceDatabaseMigrator = .openMusicEvent
        dependencies[OpenMusicEventSourceEditing.AuthoringPolicyClient.self] = .openMusicEvent

        let baseDatabase = dependencies.defaultDatabase

        dependencies.sourceDataRefresh = SourceDataRefreshClient { sourceBaselineID in
            try await withDependencies {
                $0.defaultDatabase = baseDatabase
                $0.sourceEditingSession = nil
            } operation: {
                @Dependency(\.defaultDatabase) var database
                @Dependency(\.tangledSourceImport) var tangledSourceImport
                let sourceBaseline = try await database.read { db in
                    try SourceBaselineRecord
                        .where { $0.id.eq(sourceBaselineID) }
                        .fetchOne(db)
                }
                guard let sourceBaseline else {
                    throw SourceDataRefreshError.sourceBaselineNotFound(sourceBaselineID)
                }
                _ = try await tangledSourceImport.importSource(
                    OpenMusicEventSourceValidationRequest(
                        source: sourceBaseline.sourceReference,
                        ref: sourceBaseline.ref ?? "HEAD"
                    )
                )
            }
        }
    }

}

private enum SourceDataRefreshError: Error, Equatable, Sendable {
    case sourceBaselineNotFound(SourceBaselineRecord.ID)
}

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// The default implementation merely loads the `ContentView` for the app and logs a message.
public typealias OpenMusicEventApplication = OAuthAuthorization<OpenMusicEventAppRoot>

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
        StoreOf<OpenMusicEventApplication>(
            initialState: .init(storage: OpenMusicEventOAuth.storage) {
                OpenMusicEventAppRoot.State(
                    variant: variant,
                    selectedEventIDAtLaunch: selectedEventIDAtLaunch(for: variant),
                    whiteLabelLoadedRootAtLaunch: whiteLabelLoadedRootAtLaunch(for: variant)
                )
            }
        ) {
            OpenMusicEventApplication(storage: OpenMusicEventOAuth.storage) {
                OpenMusicEventAppRoot()
            }
            .presentAuthorizationFailures()
        }
    }

    private static func selectedEventIDAtLaunch(
        for variant: OpenMusicEventAppVariant
    ) -> OMERecord.Event.ID? {
        guard variant.persistsSelectedEvent else { return nil }
        @Dependency(\.defaultDatabase) var database
        do {
            return try database.read { db in
                try AppState.find(1).fetchOne(db)?.selectedEventID
            }
        } catch {
            logger.error("Failed to restore selected event at launch: \(String(describing: error))")
            return nil
        }
    }

    private static func whiteLabelLoadedRootAtLaunch(
        for variant: OpenMusicEventAppVariant
    ) -> WhiteLabelRoot.LoadedRoot? {
        guard case let .whiteLabel(configuration) = variant else { return nil }
        @Dependency(\.defaultDatabase) var database
        do {
            return try WhiteLabelRoot.loadedRootAtLaunch(
                for: configuration,
                database: database
            )
        } catch {
            logger.error("Failed to restore white-label event at launch: \(String(describing: error))")
            return nil
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
