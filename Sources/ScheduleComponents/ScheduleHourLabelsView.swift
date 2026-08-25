#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

// SKIP INSERT: import skip.ui.*

public struct ScheduleHourTag: Hashable {
    public var hour: Int

    public init(hour: Int) {
        self.hour = hour
    }
}

public struct HourLabelsWidthPreferenceKey: PreferenceKey {
    public static let defaultValue: ScheduleCGFloat = 43

    public static func reduce(value: inout ScheduleCGFloat, nextValue: () -> ScheduleCGFloat) {
        value = nextValue()
    }
}

public struct HourLabelsHeightPreferenceKey: PreferenceKey {
    public static let defaultValue: ScheduleCGFloat = 32

    public static func reduce(value: inout ScheduleCGFloat, nextValue: () -> ScheduleCGFloat) {
        value = nextValue()
    }
}

public struct ScheduleHourLabelsView: View {
    @Environment(\.scheduleHeight) var scheduleHeight
    @Environment(\.scheduleWidth) var scheduleWidth
    @Environment(\.scheduleTimelineOrientation) var scheduleTimelineOrientation
    @Environment(\.scheduleTimeRange) var scheduleTimeRange
    @ScaledMetric var hourLabelsHeight = HourLabelsHeightPreferenceKey.defaultValue
    @ScaledMetric var hourLabelsWidth = HourLabelsWidthPreferenceKey.defaultValue
    let label: (Date) -> String

    public init(label: @escaping (Date) -> String) {
        self.label = label
    }

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
        #if os(Android) || SKIP_BRIDGE
        ZStack(alignment: .topLeading) {
            ForEach(hourDates, id: \.self) { date in
                if let range = scheduleTimeRange {
                    Text(label(date))
                        .id(date)
                        .lineLimit(1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: hourLabelsWidth, height: hourLabelsHeight)
                        .offset(
                            y: date.toY(containerHeight: scheduleHeight, in: range)
                                - hourLabelsHeight / 2
                        )
                }
            }
        }
        .frame(width: hourLabelsWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        #else
        GeometryReader { _ in
            ForEach(hourDates, id: \.self) { date in
                if let range = scheduleTimeRange {
                    Text(label(date))
                        .id(date)
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
        #endif
    }

    var horizontalTimeLabels: some View {
        #if os(Android) || SKIP_BRIDGE
        ZStack(alignment: .topLeading) {
            if scheduleWidth > 0 {
                ForEach(hourDates, id: \.self) { date in
                    if let range = scheduleTimeRange {
                        Text(label(date))
                            .id(date)
                            .lineLimit(1)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: hourLabelsWidth, height: hourLabelsHeight)
                            .offset(
                                x: date.toX(containerWidth: scheduleWidth, in: range)
                                    - hourLabelsWidth / 2
                            )
                    }
                }
            }
        }
        .frame(height: hourLabelsHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        #else
        GeometryReader { geometry in
            ForEach(hourDates, id: \.self) { date in
                if let range = scheduleTimeRange {
                    Text(label(date))
                        .id(date)
                        .lineLimit(1)
                        .font(.caption)
                        #if os(iOS)
                        .monospacedDigit()
                        #endif
                        .foregroundStyle(.secondary)
                        .position(
                            x: date.toX(
                                containerWidth: scheduleWidth > 0 ? scheduleWidth : geometry.size.width,
                                in: range
                            ),
                            y: hourLabelsHeight / 2
                        )
                }
            }
        }
        .frame(height: hourLabelsHeight)
        #endif
    }
}
