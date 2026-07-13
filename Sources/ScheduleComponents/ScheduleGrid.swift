import SwiftUI

public struct ScheduleGrid<Content: View>: View {
    @Environment(\.scheduleTimelineOrientation) var scheduleTimelineOrientation

    let content: Content

    public init(@ViewBuilder content: () -> Content = { EmptyView() }) {
        self.content = content()
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
                ScheduleHourLabelsView()
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

            TimeIndicatorView()
        }
        .ignoresSafeArea(edges: .trailing)
    }

    var horizontalTimeGrid: some View {
        ZStack {
            VStack(spacing: 0) {
                ScheduleHourLabelsView()
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

            TimeIndicatorView()
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
