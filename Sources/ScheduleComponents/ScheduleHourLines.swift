import SwiftUI

public struct ScheduleHourLines: View {
    @Environment(\.scheduleHeight) var scheduleHeight
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

    var lineHeights: [CGFloat] {
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
                    path.move(to: CGPoint(x: 0, y: lineHeight))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: lineHeight))
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
                    let lineX = date.toX(containerWidth: proxy.size.width, in: range)
                    Path { path in
                        path.move(to: CGPoint(x: lineX, y: 0))
                        path.addLine(to: CGPoint(x: lineX, y: proxy.size.height))
                    }
                    .stroke(lineColor)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}
