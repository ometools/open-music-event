import Foundation
import SwiftUI

struct TimeIndicatorView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.calendar) var calendar
    @Environment(\.scheduleHeight) var scheduleHeight
    @Environment(\.scheduleTimelineOrientation) var scheduleTimelineOrientation
    @Environment(\.scheduleTimeRange) var scheduleTimeRange
    @Environment(\.shouldShowTimeIndicator) var shouldShowTimeIndicator

    let gradientHeight: CGFloat = 30
    let textWidth: CGFloat = 43
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
                        verticalTimeIndicator(at: context.date)
                            .position(
                                x: geometry.size.width / 2,
                                y: context.date.toY(
                                    containerHeight: scheduleHeight,
                                    in: scheduleTimeRange
                                )
                            )

                    case .horizontalTime:
                        horizontalTimeIndicator(at: context.date, height: geometry.size.height)
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

    func verticalTimeIndicator(at date: Date) -> some View {
        ZStack(alignment: .leading) {
            Text(currentTime(at: date))
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

    func horizontalTimeIndicator(at date: Date, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1, height: max(height - horizontalLabelHeight, 0))
                .offset(y: horizontalLabelHeight)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)
                .offset(y: horizontalLabelHeight - 2)

            Text(currentTime(at: date))
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

    func currentTime(at date: Date) -> String {
        Date.FormatStyle.dateTime
            .hour(.defaultDigits(amPM: .narrow))
            .minute()
            .format(date)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }
}
