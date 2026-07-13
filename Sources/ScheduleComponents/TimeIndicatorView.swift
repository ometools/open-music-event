import Dependencies
import SwiftUI

struct TimeIndicatorView: View {
    @Dependency(\.date) var date

    @Environment(\.calendar) var calendar
    @Environment(\.colorScheme) var colorScheme
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
        CrossPlatformTimelineView(.periodic(by: 1)) { currentDate in
            GeometryReader { geometry in
                if shouldShowTimeIndicator {
                    switch scheduleTimelineOrientation {
                    case .verticalTime:
                        verticalTimeIndicator(at: currentDate)
                            .position(
                                x: geometry.size.width / 2,
                                y: scheduleTimeRange.map {
                                    currentDate.toY(containerHeight: scheduleHeight, in: $0)
                                } ?? -100
                            )

                    case .horizontalTime:
                        horizontalTimeIndicator(
                            at: currentDate,
                            height: geometry.size.height
                        )
                        .position(
                            x: scheduleTimeRange.map {
                                currentDate.toX(containerWidth: geometry.size.width, in: $0)
                            } ?? -100,
                            y: geometry.size.height / 2
                        )
                    }
                }
            }
        }
    }

    private func verticalTimeIndicator(at currentDate: Date) -> some View {
        ZStack(alignment: .leading) {
            Text(currentDate.formatted(timeFormat).lowercased().replacingOccurrences(of: " ", with: ""))
                .foregroundStyle(Color.accentColor)
                .font(.caption)
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

    private func horizontalTimeIndicator(at currentDate: Date, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1, height: max(height - horizontalLabelHeight, 0))
                .offset(y: horizontalLabelHeight)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)
                .offset(y: horizontalLabelHeight - 2)

            Text(currentDate.formatted(timeFormat).lowercased().replacingOccurrences(of: " ", with: ""))
                .foregroundStyle(Color.accentColor)
                .font(.caption)
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

    var timeFormat: Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .narrow)).minute()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        return format
    }
}

struct CrossPlatformTimelineView<Content: View>: View {
    struct PeriodicTimelineSchedule {
        var interval: TimeInterval

        static func periodic(by interval: TimeInterval) -> PeriodicTimelineSchedule {
            PeriodicTimelineSchedule(interval: interval)
        }
    }

    @Dependency(\.date) var date
    @State var currentDate = Date.now

    let content: (Date) -> Content
    let schedule: PeriodicTimelineSchedule

    init(_ schedule: PeriodicTimelineSchedule, @ViewBuilder content: @escaping (Date) -> Content) {
        self.content = content
        self.schedule = schedule
    }

    var body: some View {
        content(currentDate)
            .task {
                while !Task.isCancelled {
                    currentDate = date()
                    try? await Task.sleep(for: .seconds(schedule.interval))
                }
            }
    }
}
