import SwiftUI
import OpenMusicEvent
import Dependencies

#if canImport(UIKit)
import UIKit
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
            #if canImport(UIKit)
            AppRootView()
                .background {
                    GlobalErrorWindowPresenter {
                        AppRootView.globalErrorWindowContent()
                    }
                }
            #else
            AppRootView()
            #endif
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

    // support for SkipNotify.fetchNotificationToken()

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: NSNotification.Name("didRegisterForRemoteNotificationsWithDeviceToken"), object: application, userInfo: ["deviceToken": deviceToken])
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        NotificationCenter.default.post(name: NSNotification.Name("didFailToRegisterForRemoteNotificationsWithError"), object: application, userInfo: ["error": error])
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

#if canImport(UIKit)
private struct GlobalErrorWindowPresenter<Content: View>: UIViewControllerRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> GlobalErrorWindowPresenterController<Content> {
        GlobalErrorWindowPresenterController(content: content)
    }

    func updateUIViewController(
        _ viewController: GlobalErrorWindowPresenterController<Content>,
        context: Context
    ) {
        viewController.update(content: content)
    }
}

@MainActor
private final class GlobalErrorWindowPresenterController<Content: View>: UIViewController {
    private var content: Content
    private var hostingController: UIHostingController<Content>?
    private var window: PassthroughWindow?

    init(content: Content) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        window?.isHidden = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installWindowIfPossible()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        installWindowIfPossible()
    }

    func update(content: Content) {
        self.content = content
        hostingController?.rootView = content
        installWindowIfPossible()
    }

    private func installWindowIfPossible() {
        guard let windowScene = view.window?.windowScene else { return }

        if let window, window.windowScene === windowScene {
            return
        }

        window?.isHidden = true

        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear

        let window = PassthroughWindow(windowScene: windowScene)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.rootViewController = hostingController
        window.windowLevel = .alert + 1
        window.isHidden = false

        self.hostingController = hostingController
        self.window = window
    }
}

private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event) else { return nil }

        if let rootView = rootViewController?.view, hitView === rootView {
            return nil
        }

        return hitView
    }
}
#endif
