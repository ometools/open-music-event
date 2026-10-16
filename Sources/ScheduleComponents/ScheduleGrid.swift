import Foundation
#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

// SKIP INSERT: import skip.ui.*

public struct ScheduleGrid<Content: View>: View {
    @Environment(\.scheduleTimelineOrientation) var scheduleTimelineOrientation

    let content: Content
    let currentTimeLabel: (Date) -> String
    let hourLabel: (Date) -> String

    public init(
        currentTimeLabel: @escaping (Date) -> String,
        hourLabel: @escaping (Date) -> String,
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) {
        self.content = content()
        self.currentTimeLabel = currentTimeLabel
        self.hourLabel = hourLabel
    }

    public var body: some View {
        switch scheduleTimelineOrientation {
        case .verticalTime:
            verticalTimeGrid

        case .horizontalTime:
            horizontalTimeGrid
        }
    }

    var verticalTimeGrid: some View {
        ZStack {
            HStack {
                ScheduleHourLabelsView(label: hourLabel)
                    .zIndex(0)

                ZStack {
                    ScheduleHourLines()
                        .zIndex(0)

                    content
                        .zIndex(10)
                        #if os(iOS)
                        .coordinateSpace(name: "Timeline")
                        #endif
                }
            }

            TimeIndicatorView(label: currentTimeLabel)
        }
        .ignoresSafeArea(edges: .trailing)
    }

    var horizontalTimeGrid: some View {
        ZStack {
            VStack(spacing: 0) {
                ScheduleHourLabelsView(label: hourLabel)
                    .zIndex(0)

                ZStack {
                    ScheduleHourLines()
                        .zIndex(0)

                    content
                        .zIndex(10)
                        #if os(iOS)
                        .coordinateSpace(name: "Timeline")
                        #endif
                }
            }

            TimeIndicatorView(label: currentTimeLabel)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
