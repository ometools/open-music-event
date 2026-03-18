//
//  OpenURLWhenActiveSceneModifier.swift
//  open-music-event
//
//  Created by Woodrow Melling on 3/21/26.
//



#if canImport(SwiftUI)
import SwiftUI

public struct OpenURLWhenActiveSceneModifier: ViewModifier {
    var action: (URL) -> Void
    @Environment(\.scenePhase) var scenePhase
    @State var pendingURL: URL?

    public func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                processURLWhenSceneActive(url: url, scenePhase: scenePhase)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb, perform: {
                processURLWhenSceneActive(url: $0.webpageURL, scenePhase: scenePhase)
            })
            .onChange(of: scenePhase) { newValue in
                processURLWhenSceneActive(url: pendingURL, scenePhase: newValue)
            }
    }

    private func processURLWhenSceneActive(url: URL?, scenePhase: ScenePhase) {
        pendingURL = url
        switch scenePhase {
        case .active:
            if let url {
                action(url)
            }
            pendingURL = nil
        case .background, .inactive: break
        @unknown default: break
        }
    }
}

public extension View {
    /**
    Adds a modifier that handles URLs opened when the app becomes active.

    This modifier defers URL processing until the app's scene becomes active,
    ensuring that URLs are handled only when the app is in the foreground.

    - Parameter action: A closure that takes a URL and performs an action.
    - Returns: A view that handles URL opens when the app becomes active.
     */
    public func onOpenURLWhenSceneActive(perform action: @escaping (URL) -> Void) -> some View {
        self.modifier(OpenURLWhenActiveSceneModifier(action: action))
    }
}
#endif
