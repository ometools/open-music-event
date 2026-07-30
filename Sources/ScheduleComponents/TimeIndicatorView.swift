import Foundation
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

// SKIP INSERT: import skip.ui.*

#if os(Android) && SKIP_BRIDGE
struct PeriodicTimelineSchedule {
    static func periodic(from startDate: Date, by interval: TimeInterval) -> Self {
        Self()
    }
}

struct TimelineView: View {
    struct Context {
        let date: Date
    }

    let content: (Context) -> AnyView

    init<Content: View>(
        _ schedule: PeriodicTimelineSchedule,
        @ViewBuilder content: @escaping (Context) -> Content
    ) {
        self.content = { context in AnyView(content(context)) }
    }

    var body: some View {
        content(Context(date: .now))
    }
}
#endif

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
        TimelineView(.periodic(from: Date.now, by: 1)) { context in
            GeometryReader { geometry in
                if shouldShowTimeIndicator,
                   let scheduleTimeRange,
                   scheduleTimeRange.contains(context.date)
                {
                    switch scheduleTimelineOrientation {
                    case .verticalTime:
                        verticalTimeIndicator(at: context.date)
                            .position(
                                x: (scheduleWidth > 0 ? scheduleWidth : geometry.size.width) / 2,
                                y: context.date.toY(
                                    containerHeight: scheduleHeight,
                                    in: scheduleTimeRange
                                )
                            )
                            .id(ScheduleScrollTarget.currentTime)

                    case .horizontalTime:
                        horizontalTimeIndicator(at: context.date, height: geometry.size.height)
                            .position(
                                x: context.date.toX(
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
    }
}
