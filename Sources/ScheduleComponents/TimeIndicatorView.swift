import Foundation
import SwiftUI

struct TimeIndicatorView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scheduleHeight) var scheduleHeight
    @Environment(\.scheduleTimelineOrientation) var scheduleTimelineOrientation
    @Environment(\.scheduleTimeRange) var scheduleTimeRange
    @Environment(\.shouldShowTimeIndicator) var shouldShowTimeIndicator

    let gradientHeight: CGFloat = 30
    let textWidth: CGFloat = 62
    let horizontalLabelHeight = HourLabelsHeightPreferenceKey.defaultValue

    var backgroundColor: Color {
        switch colorScheme {
        case .dark:
            return .black
        case .light:
            return .white
        @unknown default:
            return .clear
        }
    }

    var body: some View {
        TimelineView(.periodic(from: Date.now, by: 1)) { context in
            GeometryReader { geometry in
                if shouldShowTimeIndicator,
                   let scheduleTimeRange,
                   scheduleTimeRange.contains(context.date)
                {
                    switch scheduleTimelineOrientation {
                    case .verticalTime:
                        verticalTimeIndicator()
                            .position(
                                x: geometry.size.width / 2,
                                y: context.date.toY(
                                    containerHeight: scheduleHeight,
                                    in: scheduleTimeRange
                                )
                            )

                    case .horizontalTime:
                        horizontalTimeIndicator(height: geometry.size.height)
                            .position(
                                x: context.date.toX(
                                    containerWidth: geometry.size.width,
                                    in: scheduleTimeRange
                                ),
                                y: geometry.size.height / 2
                            )
                    }
                }
            }
        }
    }

    func verticalTimeIndicator() -> some View {
        ZStack(alignment: .leading) {
            Text("Right Now")
                .foregroundStyle(Color.accentColor)
                .font(.caption)
                .fontWeight(.semibold)
                .background {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, backgroundColor, backgroundColor, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: gradientHeight)
                }

            Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)
                .offset(x: textWidth)

            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 1)
                .offset(x: textWidth)
        }
    }

    func horizontalTimeIndicator(height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1, height: max(height - horizontalLabelHeight, 0))
                .offset(y: horizontalLabelHeight)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)
                .offset(y: horizontalLabelHeight - 2)

            Text("Right Now")
                .foregroundStyle(Color.accentColor)
                .font(.caption)
                .fontWeight(.semibold)
                .background {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, backgroundColor, backgroundColor, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: textWidth + 16)
                }
        }
        .frame(width: textWidth + 16, height: height, alignment: .top)
    }
}
