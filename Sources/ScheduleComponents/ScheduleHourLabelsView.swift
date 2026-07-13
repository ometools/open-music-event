import SwiftUI

public struct ScheduleHourTag: Hashable {
    public var hour: Int

    public init(hour: Int) {
        self.hour = hour
    }
}

public struct HourLabelsWidthPreferenceKey: PreferenceKey {
    public static let defaultValue: CGFloat = 43

    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

public struct HourLabelsHeightPreferenceKey: PreferenceKey {
    public static let defaultValue: CGFloat = 32

    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

public struct ScheduleHourLabelsView: View {
    @Environment(\.scheduleHeight) var scheduleHeight
    @Environment(\.scheduleTimelineOrientation) var scheduleTimelineOrientation
    @Environment(\.scheduleTimeRange) var scheduleTimeRange
    @ScaledMetric var hourLabelsHeight = HourLabelsHeightPreferenceKey.defaultValue
    @ScaledMetric var hourLabelsWidth = HourLabelsWidthPreferenceKey.defaultValue

    public init() {}

    var hourDates: [Date] {
        guard let range = scheduleTimeRange else { return [] }
        var result: [Date] = []
        var current = range.start.floor(precision: 3600)
        while current <= range.end {
            result.append(current)
            current = current.addingTimeInterval(3600)
        }
        return result
    }

    @ViewBuilder
    public var body: some View {
        switch scheduleTimelineOrientation {
        case .verticalTime:
            verticalTimeLabels

        case .horizontalTime:
            horizontalTimeLabels
        }
    }

    var verticalTimeLabels: some View {
        GeometryReader { _ in
            ForEach(hourDates, id: \.self) { date in
                if let range = scheduleTimeRange {
                    Text(timeString(for: date))
                        .id(ScheduleHourTag(hour: Calendar.current.component(.hour, from: date)))
                        .lineLimit(1)
                        .font(.caption)
                        #if os(iOS)
                        .monospacedDigit()
                        #endif
                        .foregroundStyle(.secondary)
                        .position(
                            x: hourLabelsWidth / 2,
                            y: date.toY(containerHeight: scheduleHeight, in: range)
                        )
                }
            }
        }
        .frame(width: hourLabelsWidth)
    }

    var horizontalTimeLabels: some View {
        GeometryReader { geometry in
            ForEach(hourDates, id: \.self) { date in
                if let range = scheduleTimeRange {
                    Text(timeString(for: date))
                        .id(ScheduleHourTag(hour: Calendar.current.component(.hour, from: date)))
                        .lineLimit(1)
                        .font(.caption)
                        #if os(iOS)
                        .monospacedDigit()
                        #endif
                        .foregroundStyle(.secondary)
                        .position(
                            x: date.toX(containerWidth: geometry.size.width, in: range),
                            y: hourLabelsHeight / 2
                        )
                }
            }
        }
        .frame(height: hourLabelsHeight)
    }

    func timeString(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 0:
            return "mdnt"
        case 12:
            return "noon"
        default:
            return date
                .formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
        }
    }
}
