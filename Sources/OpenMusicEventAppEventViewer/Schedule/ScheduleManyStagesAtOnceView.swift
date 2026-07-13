import ComposableArchitecture2
import Dependencies
import Foundation
import ScheduleComponents
import Sharing
import SQLiteData
import SwiftUI

@Feature
public struct ScheduleManyStagesAtOnce {
    public init() {}

    public struct State {
        public init(
            eventID: OMERecord.Event.ID,
            scheduleDivision: ScheduleViewer.ScheduleDivision
        ) {
            @Dependency(\.defaultEventTimeZone) var defaultEventTimeZone

            self.eventID = eventID
            self.timeZone = defaultEventTimeZone
            self.scheduleDivision = scheduleDivision
            self._scheduleViewerState = Shared(
                .scheduleViewerState(
                    eventID: eventID,
                    scheduleDivision: scheduleDivision
                )
            )
            _performanceRows = FetchAll(
                PerformanceRow.all(eventID: eventID)
            )
            _schedules = FetchAll(
                ScheduleViewer.schedulesQuery(eventID: eventID)
            )
            _stages = FetchAll(
                ScheduleViewer.stagesQuery(eventID: eventID)
            )
        }

        public let eventID: OMERecord.Event.ID
        @DebugSnapshotIgnored
        public var timeZone: TimeZone
        public let scheduleDivision: ScheduleViewer.ScheduleDivision
        @Shared public var scheduleViewerState: ScheduleViewerState

        @FetchAll public var performanceRows: [PerformanceRow]
        @FetchAll public var schedules: [OMERecord.Schedule]
        @FetchAll public var stages: [OMERecord.Stage]

        public func visiblePerformanceRows(
            selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> [PerformanceRow] {
            ScheduleViewer.visiblePerformances(
                performanceRows: performanceRows,
                scheduleID: ScheduleViewer.resolvedSelectedScheduleID(
                    selectedScheduleID,
                    schedules: schedules
                ),
                stages: visibleStages
            )
        }

        public var visibleStages: [OMERecord.Stage] {
            ScheduleViewer.visibleStages(
                stages: stages,
                division: scheduleDivision
            )
        }
    }

    public enum Action {
        case deletePerformanceButtonTapped(OMERecord.ID<OMERecord.Performance>)
        case editPerformanceButtonTapped(OMERecord.ID<OMERecord.Performance>)
        case performanceButtonTapped(OMERecord.ID<OMERecord.Performance>)
    }

    public var body: some Feature {
        Update { _, action in
            switch action {
            case let .deletePerformanceButtonTapped(performanceID):
                store.addTask {
                    let task = try store.post(
                        key: SchedulePerformanceDeleteRequested.self,
                        value: performanceID
                    )
                    await task?.value
                }

            case let .editPerformanceButtonTapped(performanceID):
                store.addTask {
                    let task = try store.post(
                        key: SchedulePerformanceEditRequested.self,
                        value: performanceID
                    )
                    await task?.value
                }

            case let .performanceButtonTapped(performanceID):
                store.addTask {
                    let task = try store.post(
                        key: SchedulePerformanceDetailRequested.self,
                        value: performanceID
                    )
                    await task?.value
                }
            }
        }
    }
}

public struct ScheduleManyStagesAtOnceView: View {
    @Bindable var store: StoreOf<ScheduleManyStagesAtOnce>
    @Shared var selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
    let showsAuthoringControls: Bool

    let minimumStageLaneWidth: CGFloat = 132

    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    @Environment(\.schedulePointsPerHour) var schedulePointsPerHour
    @Environment(\.scheduleTimeBuffer) var scheduleTimeBuffer

    public init(
        store: StoreOf<ScheduleManyStagesAtOnce>,
        selectedScheduleID: Shared<OMERecord.ID<OMERecord.Schedule>?>,
        showsAuthoringControls: Bool
    ) {
        self.store = store
        self._selectedScheduleID = selectedScheduleID
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        if store.visibleStages.isEmpty {
            emptyView(
                title: store.scheduleDivision.title,
                description: "No stages have been added to this schedule division yet."
            )
        } else if let timeRange {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 0) {
                        if needsStageDisambiguation {
                            ScheduleManyStagesLaneHeader(
                                stages: store.visibleStages,
                                contentWidth: contentWidth(for: geometry.size.width),
                                minimumStageLaneWidth: minimumStageLaneWidth
                            )
                        }

                        SchedulePageView(timelineCards) { card in
                            ScheduleTimelineCardView(
                                performance: card.performance,
                                stage: card.stage,
                                showsAuthoringControls: showsAuthoringControls,
                                editAction: {
                                    store.send(.editPerformanceButtonTapped(card.id))
                                },
                                deleteAction: {
                                    store.send(.deletePerformanceButtonTapped(card.id))
                                },
                                action: {
                                    store.send(.performanceButtonTapped(card.id))
                                }
                            )
                        } emptyContent: {
                            emptyPerformancesView
                        }
                        .frame(
                            width: contentWidth(for: geometry.size.width),
                            height: scheduleHeight(for: timeRange)
                        )
                        .environment(\.scheduleHeight, scheduleHeight(for: timeRange))
                        .environment(\.scheduleTimeRange, timeRange)
                    }
                }
            }
        } else {
            emptyPerformancesView
        }
    }

    var emptyPerformancesView: some View {
        emptyView(
            title: store.scheduleDivision.title,
            description: "No performances have been added to this schedule division yet."
        )
    }

    func emptyView(title: String, description: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    var timelineCards: [ScheduleManyStagesTimelineCard] {
        Self.timelineCards(
            performanceRows: store.state.visiblePerformanceRows(
                selectedScheduleID: selectedScheduleID
            ),
            stages: store.visibleStages
        )
    }

    var timeRange: DateInterval? {
        ScheduleStageTimelinePage.timeRange(
            for: timelineCards.map(\.performance),
            buffer: scheduleTimeBuffer
        )
    }

    func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        max(
            availableWidth,
            HourLabelsWidthPreferenceKey.defaultValue
                + CGFloat(store.visibleStages.count) * minimumStageLaneWidth
        )
    }

    func scheduleHeight(for timeRange: DateInterval) -> CGFloat {
        max(
            CGFloat(timeRange.duration / 3600) * schedulePointsPerHour,
            420
        )
    }

    static func timelineCards(
        performanceRows: [PerformanceRow],
        stages: [OMERecord.Stage]
    ) -> [ScheduleManyStagesTimelineCard] {
        let stagesByID = Dictionary(
            uniqueKeysWithValues: stages.map { stage in
                (stage.id.stageID, stage)
            }
        )
        let stageLaneIndices = Dictionary(
            uniqueKeysWithValues: stages.enumerated().map { index, stage in
                (stage.id.stageID, index)
            }
        )

        return performanceRows.compactMap { row in
            guard let stage = stagesByID[row.performance.stageID],
                  let laneIndex = stageLaneIndices[row.performance.stageID]
            else { return nil }

            return ScheduleManyStagesTimelineCard(
                performance: row.performance,
                stage: stage,
                laneIndex: laneIndex
            )
        }
    }
}

struct ScheduleManyStagesTimelineCard: TimelineCard {
    let performance: OMERecord.Performance
    let stage: OMERecord.Stage
    let laneIndex: Int

    var id: OMERecord.ID<OMERecord.Performance> {
        performance.id.performanceID
    }

    var dateInterval: DateInterval {
        DateInterval(start: performance.startTime, end: performance.endTime)
    }

    var groupWidth: Range<Int> {
        laneIndex..<laneIndex
    }
}

struct ScheduleManyStagesLaneHeader: View {
    let stages: [OMERecord.Stage]
    let contentWidth: CGFloat
    let minimumStageLaneWidth: CGFloat

    @Environment(\.showStageNameLabels) var showStageNameLabels

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear
                .frame(width: hourLabelsWidth)

            ForEach(stages) { stage in
                VStack(spacing: 4) {
                    ScheduleStageIcon(stage: stage)
                        .frame(width: 28, height: 28)
                        .foregroundStyle(stage.color.swiftUIColor)

                    if showStageNameLabels {
                        Text(stage.name)
                            .font(.caption2)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: stageLaneWidth)
                .padding(.vertical, 8)
            }
        }
        .frame(width: contentWidth, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
    }

    var hourLabelsWidth: CGFloat {
        HourLabelsWidthPreferenceKey.defaultValue
    }

    var stageLaneWidth: CGFloat {
        guard !stages.isEmpty else { return minimumStageLaneWidth }
        return max(
            minimumStageLaneWidth,
            (contentWidth - hourLabelsWidth) / CGFloat(stages.count)
        )
    }
}
