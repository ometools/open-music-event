import Dependencies
import Foundation
#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

public struct PeriodicTimelineView<Content: View>: View {
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date) var date

    @State var currentDate: Date?

    let interval: TimeInterval
    let content: (Date) -> Content

    public init(
        every interval: TimeInterval,
        @ViewBuilder content: @escaping (Date) -> Content
    ) {
        precondition(interval.isFinite && interval > 0)
        self.interval = interval
        self.content = content
    }

    public var body: some View {
#if os(Android) || SKIP_BRIDGE
        content(currentDate ?? date.now)
            .task {
                currentDate = date.now

                do {
                    while !Task.isCancelled {
                        try await clock.sleep(for: .seconds(interval))
                        currentDate = date.now
                    }
                } catch is CancellationError {
                    return
                } catch {
                    assertionFailure("Periodic timeline clock failed: \(error)")
                }
            }
#else
        TimelineView(.periodic(from: date.now, by: interval)) { _ in
            // TimelineView schedules redraws, while the dependency remains the
            // semantic clock for production, previews, tests, and UI automation.
            content(date.now)
        }
#endif
    }
}
