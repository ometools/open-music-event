import Foundation
import ScheduleComponents
import SwiftUI

struct SchedulePerformanceTimelineCard: DateIntervalRepresentable, Equatable, Identifiable {
    let performance: OMERecord.Performance

    var id: OMERecord.ID<OMERecord.Performance> { performance.id.performanceID }
    var dateInterval: DateInterval {
        DateInterval(start: performance.startTime, end: performance.endTime)
    }
}

struct ScheduleSingleStageTimelineView: View {
    @Environment(\.schedulePointsPerHour) var schedulePointsPerHour
    @Environment(\.scheduleTimeBuffer) var scheduleTimeBuffer

    let stage: OMERecord.Stage
    let performances: [OMERecord.Performance]
    let onPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void

    var body: some View {
        Group {
            if let timeRange {
                ScrollView {
                    SchedulePageView(timelineCards) { card in
                        ScheduleTimelineCardView(
                            performance: card.item.performance,
                            stage: stage
                        ) {
                            onPerformanceTapped(card.item.id)
                        }
                    } emptyContent: {
                        EmptyView()
                    }
                    .frame(height: scheduleHeight(for: timeRange))
                    .environment(\.scheduleHeight, scheduleHeight(for: timeRange))
                    .environment(\.scheduleTimeRange, timeRange)
                    .padding(.trailing, 10)
                }
            } else {
                ContentUnavailableView(
                    stage.name,
                    systemImage: "calendar.day.timeline.leading",
                    description: Text("No performances have been added to this stage yet.")
                )
            }
        }
    }

    var timelineCards: [TimelineWrapper<SchedulePerformanceTimelineCard>] {
        performances.map(SchedulePerformanceTimelineCard.init).groupedToPreventOverlaps
    }

    var timeRange: DateInterval? {
        Self.timeRange(
            for: performances,
            buffer: scheduleTimeBuffer
        )
    }

    static func timeRange(
        for performances: [OMERecord.Performance],
        buffer: TimeInterval
    ) -> DateInterval? {
        guard
            let start = performances.map(\.startTime).min(),
            let end = performances.map(\.endTime).max()
        else { return nil }

        return DateInterval(
            start: start.addingTimeInterval(-buffer),
            end: end.addingTimeInterval(buffer)
        )
    }

    func scheduleHeight(for timeRange: DateInterval) -> CGFloat {
        max(
            CGFloat(timeRange.duration / 3600) * schedulePointsPerHour,
            420
        )
    }
}

struct ScheduleTimelineCardView: View {
    let performance: OMERecord.Performance
    let stage: OMERecord.Stage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(performance.title)
                        .font(.headline)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    if !performance.recordings.isEmpty {
                        Image(systemName: "play.circle.fill")
                            .font(.caption)
                            .accessibilityLabel("Has recordings")
                    }
                }

                HStack(spacing: 6) {
                    Text(performance.timeRangeText)

                    Text(stage.name)
                        .lineLimit(1)
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.86))

                if let description = performance.displayDescription {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
            .foregroundStyle(.white)
            .background {
                ScheduleTimelineCardBackground(stageColor: stage.color.swiftUIColor)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(performance.title)
        .accessibilityHint(performance.timeRangeText)
    }
}

struct ScheduleTimelineCardBackground: View {
    let stageColor: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(stageColor)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.36))
                    .frame(height: 1)
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.32))
                    .frame(width: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
    }
}
