import Foundation
#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

// SKIP INSERT: import skip.ui.*

struct TimeIndicatorView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scheduleHeight) var scheduleHeight
    @Environment(\.scheduleWidth) var scheduleWidth
    @Environment(\.scheduleTimelineOrientation) var scheduleTimelineOrientation
    @Environment(\.scheduleTimeRange) var scheduleTimeRange
    @Environment(\.shouldShowTimeIndicator) var shouldShowTimeIndicator

    let gradientHeight: ScheduleCGFloat = 30
    let textWidth: ScheduleCGFloat = 43
    let horizontalLabelHeight = HourLabelsHeightPreferenceKey.defaultValue
    let label: (Date) -> String

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
        #if os(Android) || SKIP_BRIDGE
        ZStack(alignment: .topLeading) {
            if scheduleWidth > 0, scheduleHeight > 0 {
                PeriodicTimelineView(every: 1) { currentDate in
                    if shouldShowTimeIndicator,
                       let scheduleTimeRange,
                       scheduleTimeRange.contains(currentDate)
                    {
                        switch scheduleTimelineOrientation {
                        case .verticalTime:
                            let indicatorWidth = scheduleWidth + textWidth
                            verticalTimeIndicator(at: currentDate)
                                .position(
                                    x: indicatorWidth / 2,
                                    y: currentDate.toY(
                                        containerHeight: scheduleHeight,
                                        in: scheduleTimeRange
                                    )
                                )
                                .id(ScheduleScrollTarget.currentTime)

                        case .horizontalTime:
                            let indicatorHeight = scheduleHeight + horizontalLabelHeight
                            horizontalTimeIndicator(
                                at: currentDate,
                                height: indicatorHeight
                            )
                            .position(
                                x: currentDate.toX(
                                    containerWidth: scheduleWidth,
                                    in: scheduleTimeRange
                                ),
                                y: indicatorHeight / 2
                            )
                            .id(ScheduleScrollTarget.currentTime)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #else
        PeriodicTimelineView(every: 1) { currentDate in
            GeometryReader { geometry in
                if shouldShowTimeIndicator,
                   let scheduleTimeRange,
                   scheduleTimeRange.contains(currentDate)
                {
                    switch scheduleTimelineOrientation {
                    case .verticalTime:
                        verticalTimeIndicator(at: currentDate)
                            .position(
                                x: (scheduleWidth > 0 ? scheduleWidth : geometry.size.width) / 2,
                                y: currentDate.toY(
                                    containerHeight: scheduleHeight,
                                    in: scheduleTimeRange
                                )
                            )
                            .id(ScheduleScrollTarget.currentTime)

                    case .horizontalTime:
                        horizontalTimeIndicator(at: currentDate, height: geometry.size.height)
                            .position(
                                x: currentDate.toX(
                                    containerWidth: scheduleWidth > 0 ? scheduleWidth : geometry.size.width,
                                    in: scheduleTimeRange
                                ),
                                y: geometry.size.height / 2
                            )
                            .id(ScheduleScrollTarget.currentTime)
                    }
                }
            }
        }
        #endif
    }

    func verticalTimeIndicator(at date: Date) -> some View {
        ZStack(alignment: .leading) {
            Text(label(date))
                .lineLimit(1)
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
        .accessibilityIdentifier("indicator.schedule-current-time")
    }

    func horizontalTimeIndicator(at date: Date, height: ScheduleCGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1, height: max(height - horizontalLabelHeight, 0))
                .offset(y: horizontalLabelHeight)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)
                .offset(y: horizontalLabelHeight - 2)

            Text(label(date))
                .lineLimit(1)
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
        .accessibilityIdentifier("indicator.schedule-current-time")
    }
}
