#if os(Android) || SKIP_BRIDGE
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
        #if os(Android) || SKIP_BRIDGE
        ZStack(alignment: .topLeading) {
            if scheduleWidth > 0 {
                verticalTimeLines(width: scheduleWidth)
            }
        }
        .frame(maxWidth: .infinity)
        #else
        GeometryReader { proxy in
            verticalTimeLines(width: scheduleWidth > 0 ? scheduleWidth : proxy.size.width)
        }
        .frame(maxWidth: .infinity)
        #endif
    }

    var horizontalTimeLines: some View {
        #if os(Android) || SKIP_BRIDGE
        ZStack(alignment: .topLeading) {
            if scheduleWidth > 0 {
                horizontalTimeLines(width: scheduleWidth)
            }
        }
        .frame(maxHeight: .infinity)
        #else
        GeometryReader { proxy in
            horizontalTimeLines(width: scheduleWidth > 0 ? scheduleWidth : proxy.size.width)
        }
        .frame(maxHeight: .infinity)
        #endif
    }

    @ViewBuilder
    func verticalTimeLines(width: ScheduleCGFloat) -> some View {
        ForEach(lineHeights, id: \.self) { lineHeight in
            Path { path in
                path.move(to: ScheduleCGPoint(x: 0, y: lineHeight))
                path.addLine(to: ScheduleCGPoint(x: width, y: lineHeight))
            }
            .stroke(lineColor)
        }
    }

    @ViewBuilder
    func horizontalTimeLines(width: ScheduleCGFloat) -> some View {
        ForEach(hourDates, id: \.self) { date in
            if let range = scheduleTimeRange {
                let lineX = date.toX(containerWidth: width, in: range)
                Path { path in
                    path.move(to: ScheduleCGPoint(x: lineX, y: 0))
                    path.addLine(to: ScheduleCGPoint(x: lineX, y: scheduleHeight))
                }
                .stroke(lineColor)
            }
        }
    }
}
