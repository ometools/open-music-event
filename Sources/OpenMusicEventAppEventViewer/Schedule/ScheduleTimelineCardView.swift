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
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
