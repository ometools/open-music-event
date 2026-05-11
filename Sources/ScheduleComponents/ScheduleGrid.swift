import SwiftUI

public struct ScheduleGrid<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content = { EmptyView() }) {
        self.content = content()
    }

    public var body: some View {
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
}
