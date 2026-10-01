import Foundation
import OpenMusicEventComponents
import OpenMusicEventLexicon
import ScheduleComponents
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

struct SchedulePerformanceTimelineCard: DateIntervalRepresentable, Equatable, Identifiable {
    let performance: ProgramItem
    let dateInterval: DateInterval

    init?(performance: ProgramItem) {
        guard let start = performance.startDate,
              let end = performance.endDate,
              end > start else { return nil }
        self.performance = performance
        self.dateInterval = DateInterval(start: start, end: end)
    }

    var id: ProgramItem.ID { performance.id }
}

struct ScheduleTimelineCardView: View {
    @Environment(\.performanceReactionMenuContext) var reactionMenuContext
    let performance: ProgramItem
    let stage: EventPlace
    let timeRangeText: String
    let userScheduleOverlay: UserScheduleOverlay
    let showsAuthoringControls: Bool
    let userScheduleMembershipAction: (UserSchedule.ID) -> Void
    let newUserScheduleAction: () -> Void
    let editAction: () -> Void
    let deleteAction: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            cardContent
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            "button.performance.\(performance.id.description)"
        )
        .accessibilityLabel(Text(accessibilityLabel))
        .portableAccessibilityHint(Text(timeRangeText))
        .contextMenu {
            PerformanceReactionMenuContent(
                performanceID: performance.id,
                context: reactionMenuContext
            )

            if let selectedSchedule = userScheduleOverlay.selectedSchedule {
                Button {
                    userScheduleMembershipAction(selectedSchedule.id)
                } label: {
                    Label(
                        quickActionTitle(selectedSchedule),
                        mappedSystemImage: userScheduleSystemImage
                    )
                }

                Divider()
            }

            ForEach(userScheduleOverlay.schedules) { schedule in
                Button {
                    userScheduleMembershipAction(schedule.id)
                } label: {
                    Label(
                        quickActionTitle(schedule),
                        mappedSystemImage: userScheduleSystemImage
                    )
                }
            }

            Button {
                newUserScheduleAction()
            } label: {
                Label("Add to a new schedule", systemImage: "plus")
            }

            if showsAuthoringControls {
                Divider()

                Button {
                    editAction()
                } label: {
                    Label("Edit Performance", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    deleteAction()
                } label: {
                    Label("Delete Performance", systemImage: "trash")
                }
            }
        }
    }

    var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(performance.title)
                    .font(.headline)
                    .lineLimit(2)

                Spacer(minLength: 0)

                if userScheduleOverlay.showsMembershipIndicator(
                    performanceID: performance.id
                ) {
                    MappedSystemImage(systemName: userScheduleSystemImage)
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }

                if !performance.recordingMedia.isEmpty {
                    Image(systemName: "play.circle.fill")
                        .font(.caption)
                        .accessibilityLabel("Has recordings")
                }
            }

            HStack(spacing: 6) {
                Text(timeRangeText)
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

            PerformanceReactionSummaryWhenFits(
                performanceID: performance.id,
                axes: [.horizontal, .vertical]
            )
            .foregroundStyle(.white.opacity(0.86))
            .portableLayoutPriority(-1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
        .foregroundStyle(.white)
        .background {
            ScheduleTimelineCardBackground(stageColor: stage.stageUIColor)
        }
        .overlay {
            if userScheduleOverlay.isDimmed(
                performanceID: performance.id
            ) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.62))
            }
        }
        .portableContentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    var accessibilityLabel: String {
        guard let selectedSchedule = userScheduleOverlay.selectedSchedule else {
            return userScheduleOverlay.showsMembershipIndicator(
                performanceID: performance.id
            )
                ? "\(performance.title), In a personal schedule"
                : performance.title
        }
        let membership = userScheduleOverlay.isMember(
            performanceID: performance.id
        ) ? "In" : "Not in"
        return "\(performance.title), \(membership) \(selectedSchedule.title)"
    }

    func quickActionTitle(_ schedule: UserSchedule) -> String {
        let prefix = userScheduleOverlay.contains(
            performanceID: performance.id,
            in: schedule.id
        ) ? "Remove from" : "Add to"
        return "\(prefix) \(schedule.title)"
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
