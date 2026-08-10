import Foundation
import SwiftUI
import OpenMusicEventApp
import Dependencies

#if canImport(UIKit)
import OSLog
import UIKit

private let notificationLogger = Logger(
    subsystem: "app.openmusicevent",
    category: "notifications"
)
#endif

private typealias AppRootView = OpenMusicEventApplicationRootView
private typealias AppDelegate = OpenMusicEventAppDelegate

/// The entry point to the app simply loads the App implementation from SPM module.
@main struct AppMain: App {
    @AppDelegateAdaptor(AppMainDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        try! prepareDependencies {
            try OME.prepareDependencies(&$0)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                AppDelegate.shared.onResume()
            case .inactive:
                AppDelegate.shared.onPause()
            case .background:
                AppDelegate.shared.onStop()
            @unknown default:
                print("unknown app phase: \(newPhase)")
            }
        }
    }
}

#if canImport(UIKit)
typealias AppDelegateAdaptor = UIApplicationDelegateAdaptor
typealias AppMainDelegateBase = UIApplicationDelegate
typealias AppType = UIApplication
#elseif canImport(AppKit)
typealias AppDelegateAdaptor = NSApplicationDelegateAdaptor
typealias AppMainDelegateBase = NSApplicationDelegate
typealias AppType = NSApplication
#endif

@MainActor final class AppMainDelegate: NSObject, AppMainDelegateBase {
    let application = AppType.shared

    #if canImport(UIKit)
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        AppDelegate.shared.onInit()
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        AppDelegate.shared.onLaunch()
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        AppDelegate.shared.onDestroy()
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        AppDelegate.shared.onLowMemory()
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        AppDelegate.shared.onRegisteredForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        AppDelegate.shared.onRemoteNotificationRegistrationFailed(
            errorDescription: String(describing: error)
        )
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        do {
            let data = try JSONSerialization.data(withJSONObject: userInfo)
            AppDelegate.shared.onRemoteNotification(
                json: String(decoding: data, as: UTF8.self)
            )
            completionHandler(.newData)
        } catch {
            notificationLogger.error(
                "Could not preserve delivered notification JSON: \(String(describing: error), privacy: .public)"
            )
            completionHandler(.failed)
        }
    }
    #elseif canImport(AppKit)
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppDelegate.shared.onInit()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared.onLaunch()
    }

    func applicationWillTerminate(_ application: Notification) {
        AppDelegate.shared.onDestroy()
    }
    #endif

}
