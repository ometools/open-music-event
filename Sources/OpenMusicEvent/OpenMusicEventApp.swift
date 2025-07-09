import Foundation
import  SwiftUI; import SkipFuse
// import SharingGRDB
import GRDB
import Dependencies
/// A logger for the OpenMusicEvent module.
private let logger: Logger = Logger(subsystem: "bundle.ome.OpenMusicEvent", category: "OpenMusicEvent")

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// The default implementation merely loads the `ContentView` for the app and logs a message.
/* SKIP @bridge */public struct OpenMusicEventRootView : View {

    @Dependency(\.context) var context
    // SKIP @bridge
    public init() {
        if context == .live {
            try! OME.prepareDependencies()

        }
    }

    public var body: some View {
        if context == .live {
            OMEAppEntryPoint()
                .task {
                    logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
                }
        } else {
            Text("OpenMusicEventRootView: context is \(String(describing: _context.wrappedValue))")
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

    /* SKIP @bridge */public func onStart() {
        logger.debug("onStart")
    }

    /* SKIP @bridge */public func onResume() {
        logger.debug("onResume")
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
}

