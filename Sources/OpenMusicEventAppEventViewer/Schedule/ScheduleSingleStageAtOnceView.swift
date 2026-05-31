import Foundation
import ScheduleComponents
import SwiftUI

struct ScheduleSingleStageAtOnceView: View {
    let scheduleDivisionTitle: String
    let selectedStage: OMERecord.Stage?
    let stages: [OMERecord.Stage]
    let performances: [OMERecord.Performance]
    @Binding var selectedStageID: OMERecord.ID<OMERecord.Stage>?
    let onPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void

    @Environment(\.schedulePointsPerHour) var schedulePointsPerHour
    @Environment(\.scheduleTimeBuffer) var scheduleTimeBuffer

    var body: some View {
        #if os(iOS)
        if #available(iOS 26.0, *), !stages.isEmpty {
            timeline
                .safeAreaBar(edge: .top) {
                    stageSelector
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            inlineBody
        }
        #else
        inlineBody
        #endif
    }

    var inlineBody: some View {
        VStack(spacing: 0) {
            inlineStageSelector
            timeline
        }
    }

    @ViewBuilder
    var stageSelector: some View {
        if !stages.isEmpty {
            OMEScheduleStageSelector(
                stages: stages,
                selectedStageID: $selectedStageID
            )
        }
    }

    @ViewBuilder
    var inlineStageSelector: some View {
        if !stages.isEmpty {
            stageSelector
            Divider()
        }
    }

    @ViewBuilder
    var timeline: some View {
        if stages.isEmpty {
            ContentUnavailableView(
                scheduleDivisionTitle,
                systemImage: "music.note.list",
                description: Text("No stages have been added to this schedule division yet.")
            )
        } else if let timeRange {
            ScheduleStageTimelinePager(
                selectedStageID: $selectedStageID,
                stages: stages,
                performances: performances,
                timeRange: timeRange,
                pageHeight: scheduleHeight(for: timeRange)
            ) { performanceID in
                onPerformanceTapped(performanceID)
            }
        } else {
            ContentUnavailableView(
                selectedStage?.name ?? scheduleDivisionTitle,
                systemImage: "calendar.day.timeline.leading",
                description: Text("No performances have been added to this stage yet.")
            )
        }
    }

    var timeRange: DateInterval? {
        ScheduleStageTimelinePage.timeRange(
            for: performances,
            buffer: scheduleTimeBuffer
        )
    }

    func scheduleHeight(for timeRange: DateInterval) -> CGFloat {
        max(
            CGFloat(timeRange.duration / 3600) * schedulePointsPerHour,
            420
        )
    }
}

struct ScheduleStageTimelinePager: View {
    @Binding var selectedStageID: OMERecord.ID<OMERecord.Stage>?

    let stages: [OMERecord.Stage]
    let performances: [OMERecord.Performance]
    let timeRange: DateInterval
    let pageHeight: CGFloat
    let onPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                HorizontalPageView(page: $selectedStageID) {
                    ForEach(stages) { stage in
                        ScheduleStageTimelinePage(
                            stage: stage,
                            performances: performances(for: stage),
                            timeRange: timeRange
                        ) { performanceID in
                            onPerformanceTapped(performanceID)
                        }
                        .id(stage.id.stageID)
                        .tag(Optional(stage.id.stageID))
                        .frame(width: geometry.size.width)
                    }
                }
                .frame(height: pageHeight)
                .environment(\.scheduleHeight, pageHeight)
                .environment(\.scheduleTimeRange, timeRange)
            }
        }
    }

    func performances(for stage: OMERecord.Stage) -> [OMERecord.Performance] {
        performances.filter { $0.stageID == stage.id.stageID }
    }
}

struct ScheduleStageTimelinePage: View {
    let stage: OMERecord.Stage
    let performances: [OMERecord.Performance]
    let timeRange: DateInterval
    let onPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void

    var body: some View {
        SchedulePageView(timelineCards) { card in
            ScheduleTimelineCardView(
                performance: card.item.performance,
                stage: stage
            ) {
                onPerformanceTapped(card.item.id)
            }
        } emptyContent: {
            ContentUnavailableView(
                stage.name,
                systemImage: "calendar.day.timeline.leading",
                description: Text("No performances have been added to this stage yet.")
            )
            .padding()
        }
    }

    var timelineCards: [TimelineWrapper<SchedulePerformanceTimelineCard>] {
        performances.map(SchedulePerformanceTimelineCard.init).groupedToPreventOverlaps
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
}
