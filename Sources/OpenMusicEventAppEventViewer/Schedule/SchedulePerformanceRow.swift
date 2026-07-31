import Foundation
import OpenMusicEventComponents
import SwiftUI

public struct SchedulePerformanceRow: View {
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    let row: PerformanceRow
    let timeRangeText: String
    let daySegmentText: String
    let userScheduleOverlay: UserScheduleOverlay
    var now: Date?

    public init(
        row: PerformanceRow,
        timeRangeText: String,
        daySegmentText: String,
        userScheduleOverlay: UserScheduleOverlay = UserScheduleOverlay(
            schedules: [],
            memberships: [],
            selectedScheduleID: nil
        ),
        now: Date? = nil
    ) {
        self.row = row
        self.timeRangeText = timeRangeText
        self.daySegmentText = daySegmentText
        self.userScheduleOverlay = userScheduleOverlay
        self.now = now
    }

    public var body: some View {
        HStack(spacing: 10) {
            if needsStageDisambiguation {
                RoundedRectangle(cornerRadius: 2)
                    .fill(row.stage?.color.swiftUIColor ?? .secondary.opacity(0.35))
                    .frame(width: 5)

                stageIcon
                    .frame(width: 60, height: 60)
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(timeRangeText)
                        .lineLimit(1)
                        .portableLayoutPriority(1)

                    Text(daySegmentText)
                        .lineLimit(1)

                    if let timingStatus {
                        PerformanceTimingChip(status: timingStatus)
                            .portableLayoutPriority(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            if userScheduleOverlay.isMember(performanceID: row.performanceID) {
                Image(systemName: "checkmark-circle")
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 60)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .foregroundStyle(.primary)
        .opacity(userScheduleOverlay.isDimmed(performanceID: row.performanceID) ? 0.38 : 1)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    @ViewBuilder
    var stageIcon: some View {
        if let stage = row.stage {
            ScheduleStageIcon(stage: stage)
        } else {
            Image(
                system: "music.note",
                material: "Icons.Outlined.MusicNote"
            )
                .resizable()
                .scaledToFit()
                .padding(14)
                .foregroundStyle(.secondary)
        }
    }

    var timingStatus: PerformanceTimingStatus? {
        guard let now else { return nil }
        return PerformanceTimingStatus(
            startTime: row.performance.startTime,
            endTime: row.performance.endTime,
            now: now
        )
    }

    var accessibilityLabel: String {
        guard let selectedSchedule = userScheduleOverlay.selectedSchedule else {
            return "\(row.title), \(timeRangeText), \(daySegmentText)"
        }
        let membership = userScheduleOverlay.isMember(performanceID: row.performanceID)
            ? "In"
            : "Not in"
        return "\(row.title), \(membership) \(selectedSchedule.title), \(timeRangeText), \(daySegmentText)"
    }
}
