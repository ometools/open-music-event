#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if os(Android) || ROBOLECTRIC
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

import SwiftUITabFeatures

/// Mounts the same visible-tab plus More-overflow shape used by EventViewer.
@available(iOS 18, macOS 15, tvOS 18, visionOS 2, watchOS 11, *)
public struct MoreNavigationFixture: View {
    @State var selection = "schedule"
    @State var morePath: [String] = []
    @State var layout = TabFeatureLayout()

    public init() {
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text("selection: \(selection); overflow: \(morePath.first ?? "none")")
                .accessibilityIdentifier("more-navigation-state")

            TabFeaturesView(
                selection: $selection,
                layout: $layout,
                policy: TabFeaturePolicy(maxVisibleTabs: 1),
                morePath: $morePath
            ) {
                TabFeature(
                    "schedule",
                    title: "Schedule",
                    systemImage: "calendar"
                ) {
                    Text("Schedule root")
                        .accessibilityIdentifier("schedule-root")
                }

                TabFeature(
                    "stages",
                    title: "Stages",
                    systemImage: "list.bullet"
                ) {
                    Text("Stages destination")
                        .accessibilityIdentifier("stages-destination")
                        .navigationTitle("Stages")
                }
            }
        }
    }
}

/// Prepares the single-threaded Robolectric host for bridged main-actor calls.
public enum FuseUITestSupport {
    public static func prepareJVMHostedTesting() -> Bool {
        #if os(Android)
        return true
        #else
        #if canImport(Darwin)
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        #else
        let defaultHandle: UnsafeMutableRawPointer? = nil
        #endif
        guard let hook = dlsym(defaultHandle, "swift_task_checkIsolated_hook") else {
            return false
        }
        let noop: @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> Void = { _, _, _ in }
        hook.assumingMemoryBound(to: UnsafeRawPointer?.self).pointee = unsafeBitCast(
            noop,
            to: UnsafeRawPointer?.self
        )
        return true
        #endif
    }
}
