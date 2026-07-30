#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

// SKIP INSERT: import skip.ui.*

public struct ScheduleHourLines: View {
    @Environment(\.scheduleHeight) var scheduleHeight
    @Environment(\.scheduleWidth) var scheduleWidth
    @Environment(\.scheduleTimelineOrientation) var scheduleTimelineOrientation
    @Environment(\.scheduleTimeRange) var scheduleTimeRange

    var lineColor = Color.secondary.opacity(0.5)

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

    var lineHeights: [ScheduleCGFloat] {
        guard let range = scheduleTimeRange else { return [] }
        return hourDates.map { $0.toY(containerHeight: scheduleHeight, in: range) }
    }

    @ViewBuilder
    public var body: some View {
        switch scheduleTimelineOrientation {
        case .verticalTime:
            verticalTimeLines

        case .horizontalTime:
            horizontalTimeLines
        }
    }

    var verticalTimeLines: some View {
        GeometryReader { proxy in
            ForEach(lineHeights, id: \.self) { lineHeight in
                Path { path in
                    path.move(to: ScheduleCGPoint(x: 0, y: lineHeight))
                    path.addLine(to: ScheduleCGPoint(
                        x: scheduleWidth > 0 ? scheduleWidth : proxy.size.width,
                        y: lineHeight
                    ))
                }
                .stroke(lineColor)
            }
        }
        .frame(maxWidth: .infinity)
    }

    var horizontalTimeLines: some View {
        GeometryReader { proxy in
            ForEach(hourDates, id: \.self) { date in
                if let range = scheduleTimeRange {
                    let lineX = date.toX(
                        containerWidth: scheduleWidth > 0 ? scheduleWidth : proxy.size.width,
                        in: range
                    )
                    Path { path in
                        path.move(to: ScheduleCGPoint(x: lineX, y: 0))
                        path.addLine(to: ScheduleCGPoint(x: lineX, y: scheduleHeight))
                    }
                    .stroke(lineColor)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}
