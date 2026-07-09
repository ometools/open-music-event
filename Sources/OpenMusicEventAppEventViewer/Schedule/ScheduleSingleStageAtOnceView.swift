import Foundation
import ScheduleComponents
import SwiftUI

struct ScheduleSingleStageAtOnceView: View {
    let scheduleDivisionTitle: String
    let selectedStage: OMERecord.Stage?
    let stages: [OMERecord.Stage]
    let performances: [OMERecord.Performance]
    @Binding var selectedStageID: OMERecord.ID<OMERecord.Stage>?
    let showsAuthoringControls: Bool
    let onEditPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onDeletePerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void

    @Environment(\.schedulePointsPerHour) var schedulePointsPerHour
    @Environment(\.scheduleTimeBuffer) var scheduleTimeBuffer
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation

    var body: some View {
        content
            .onAppear {
                resolveSelectedStage()
            }
            .onChange(of: resolvedSelectedStageID) { _, _ in
                resolveSelectedStage()
            }
    }

    @ViewBuilder
    var content: some View {
        #if os(iOS)
        if #available(iOS 26.0, *), shouldShowStageSelector {
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
        if shouldShowStageSelector {
            OMEScheduleStageSelector(
                stages: stages,
                selectedStageID: $selectedStageID
            )
        }
    }

    @ViewBuilder
    var inlineStageSelector: some View {
        if shouldShowStageSelector {
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
                pageHeight: scheduleHeight(for: timeRange),
                showsAuthoringControls: showsAuthoringControls,
                onEditPerformanceTapped: { performanceID in
                    onEditPerformanceTapped(performanceID)
                },
                onDeletePerformanceTapped: { performanceID in
                    onDeletePerformanceTapped(performanceID)
                },
                onPerformanceTapped: { performanceID in
                    onPerformanceTapped(performanceID)
                }
            )
        } else {
            ContentUnavailableView(
                emptyStageTitle,
                systemImage: "calendar.day.timeline.leading",
                description: Text(emptyStageDescription)
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

    var shouldShowStageSelector: Bool {
        needsStageDisambiguation && !stages.isEmpty
    }

    var resolvedSelectedStageID: OMERecord.ID<OMERecord.Stage>? {
        if let selectedStageID,
           stages.contains(where: { $0.id.stageID == selectedStageID }) {
            return selectedStageID
        }
        return stages.first?.id.stageID
    }

    func resolveSelectedStage() {
        guard selectedStageID != resolvedSelectedStageID else { return }
        selectedStageID = resolvedSelectedStageID
    }

    var emptyStageTitle: String {
        needsStageDisambiguation
            ? selectedStage?.name ?? scheduleDivisionTitle
            : scheduleDivisionTitle
    }

    var emptyStageDescription: String {
        needsStageDisambiguation
            ? "No performances have been added to this stage yet."
            : "No performances have been added yet."
    }
}

struct ScheduleStageTimelinePager: View {
    @Binding var selectedStageID: OMERecord.ID<OMERecord.Stage>?

    let stages: [OMERecord.Stage]
    let performances: [OMERecord.Performance]
    let timeRange: DateInterval
    let pageHeight: CGFloat
    let showsAuthoringControls: Bool
    let onEditPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onDeletePerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                HorizontalPageView(page: $selectedStageID) {
                    ForEach(stages) { stage in
                        ScheduleStageTimelinePage(
                            stage: stage,
                            performances: performances(for: stage),
                            timeRange: timeRange,
                            showsAuthoringControls: showsAuthoringControls,
                            onEditPerformanceTapped: { performanceID in
                                onEditPerformanceTapped(performanceID)
                            },
                            onDeletePerformanceTapped: { performanceID in
                                onDeletePerformanceTapped(performanceID)
                            },
                            onPerformanceTapped: { performanceID in
                                onPerformanceTapped(performanceID)
                            }
                        )
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
    let showsAuthoringControls: Bool
    let onEditPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onDeletePerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void

    var body: some View {
        SchedulePageView(timelineCards) { card in
            ScheduleTimelineCardView(
                performance: card.item.performance,
                stage: stage,
                showsAuthoringControls: showsAuthoringControls,
                editAction: {
                    onEditPerformanceTapped(card.item.id)
                },
                deleteAction: {
                    onDeletePerformanceTapped(card.item.id)
                },
                action: {
                    onPerformanceTapped(card.item.id)
                }
            )
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
