import Foundation
import SkipFuse
import SwiftUI
import Dependencies
import SQLiteData
import ComposableArchitecture2
import OpenMusicEventAppEventViewer
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import SourceControlClient
import SourceControlClientGit
import SourceEditing

/// A logger for the OpenMusicEventApp module.
let logger: Logger = Logger(subsystem: "fm.woody.openmusicevent", category: "OpenMusicEventApp")

extension OME {

    public static func prepareDependencies(_ dependencies: inout DependencyValues) throws {
        try dependencies.bootstrapDatabase()
        OpenMusicEventOAuth.prepareDependencies(&dependencies)
        dependencies.sourceControl = LibGit2SourceControlClient.live
        dependencies.tangledSourceCheckout = .git
        dependencies[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = .openMusicEvent
        dependencies[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] = .openMusicEventCalendar
        dependencies.sourcePatchPublisher = .openMusicEventTangled
        dependencies.sourceReferenceDatabaseMigrator = .openMusicEvent
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
/* SKIP @bridge */public struct OpenMusicEventApplicationRootView : View {
    /* SKIP @bridge */public init() {
    }

    static let store = StoreOf<OpenMusicEventAppRoot>(
        initialState: .init()) {
            OpenMusicEventAppRoot()
    }

    public var body: some View {
        OpenMusicEventAppRootView(store: Self.store)
            .task {
                logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            }
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
        Task {
            try? await OpenMusicEventOAuth.enforceStoredAuthenticationFreshness()
        }
    }
}
