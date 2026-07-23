import ComposableArchitecture2
import Dependencies
import Foundation
import ScheduleComponents
import Sharing
import SQLiteData
import SwiftUI

@Feature
public struct ScheduleSingleStageAtOnce {
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

        public var selectedStageID: OMERecord.ID<OMERecord.Stage>? {
            get {
                ScheduleViewer.normalizedSelectedStageID(
                    selectedStageID: scheduleViewerState.selectedStageID,
                    stages: visibleStages
                )
            }
            set {
                let selectedStageID = ScheduleViewer.normalizedSelectedStageID(
                    selectedStageID: newValue,
                    stages: visibleStages
                )
                $scheduleViewerState.withLock {
                    $0.selectedStageID = selectedStageID
                }
            }
        }

        public func visiblePerformances(
            selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> [OMERecord.Performance] {
            visiblePerformanceRows(selectedScheduleID: selectedScheduleID)
                .map(\.performance)
        }

        public func visiblePerformanceRows(
            selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> [PerformanceRow] {
            ScheduleViewer.visiblePerformances(
                performanceRows: performanceRows,
                scheduleID: resolvedSelectedScheduleID(selectedScheduleID),
                stages: visibleStages
            )
        }

        public func visiblePerformancesForSelectedStage(
            selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> [OMERecord.Performance] {
            guard let resolvedSelectedStageID else { return [] }
            return visiblePerformances(selectedScheduleID: selectedScheduleID)
                .filter { $0.stageID == resolvedSelectedStageID }
        }

        public func resolvedSelectedScheduleID(
            _ selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> OMERecord.ID<OMERecord.Schedule>? {
            ScheduleViewer.resolvedSelectedScheduleID(
                selectedScheduleID,
                schedules: schedules
            )
        }

        public var resolvedSelectedStageID: OMERecord.ID<OMERecord.Stage>? {
            ScheduleViewer.resolvedSelectedStageID(
                selectedStageID: scheduleViewerState.selectedStageID,
                stages: visibleStages
            )
        }

        public var selectedStage: OMERecord.Stage? {
            guard let resolvedSelectedStageID else { return nil }
            return visibleStages.first { $0.id.stageID == resolvedSelectedStageID }
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

public struct ScheduleSingleStageAtOnceView: View {
    @Bindable var store: StoreOf<ScheduleSingleStageAtOnce>
    @Shared var selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
    let showsAuthoringControls: Bool

    @Environment(\.schedulePointsPerHour) var schedulePointsPerHour
    @Environment(\.scheduleTimeBuffer) var scheduleTimeBuffer
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation

    public init(
        store: StoreOf<ScheduleSingleStageAtOnce>,
        selectedScheduleID: Shared<OMERecord.ID<OMERecord.Schedule>?>,
        showsAuthoringControls: Bool
    ) {
        self.store = store
        self._selectedScheduleID = selectedScheduleID
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
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
                stages: store.visibleStages,
                selectedStageID: $store.selectedStageID
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
        if store.visibleStages.isEmpty {
            ContentUnavailableView(
                store.scheduleDivision.title,
                systemImage: "music.note.list",
                description: Text("No stages have been added to this schedule division yet.")
            )
        } else if let timeRange {
            ScheduleStageTimelinePager(
                selectedStageID: $store.selectedStageID,
                stages: store.visibleStages,
                performances: store.state.visiblePerformances(
                    selectedScheduleID: selectedScheduleID
                ),
                timeRange: timeRange,
                pageHeight: scheduleHeight(for: timeRange),
                showsAuthoringControls: showsAuthoringControls,
                onEditPerformanceTapped: { performanceID in
                    store.send(.editPerformanceButtonTapped(performanceID))
                },
                onDeletePerformanceTapped: { performanceID in
                    store.send(.deletePerformanceButtonTapped(performanceID))
                },
                onPerformanceTapped: { performanceID in
                    store.send(.performanceButtonTapped(performanceID))
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
            for: store.state.visiblePerformances(selectedScheduleID: selectedScheduleID),
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
        needsStageDisambiguation && !store.visibleStages.isEmpty
    }

    var resolvedSelectedStageID: OMERecord.ID<OMERecord.Stage>? {
        store.resolvedSelectedStageID
    }

    func resolveSelectedStage() {
        guard !store.visibleStages.isEmpty else { return }
        guard store.state.scheduleViewerState.selectedStageID != resolvedSelectedStageID else { return }
        $store.selectedStageID.wrappedValue = resolvedSelectedStageID
    }

    var emptyStageTitle: String {
        needsStageDisambiguation
            ? store.selectedStage?.name ?? store.scheduleDivision.title
            : store.scheduleDivision.title
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
                        ScheduleFixedStageTimeline(
                            stage: stage,
                            performances: performances(for: stage),
                            timeRange: timeRange,
                            pageHeight: pageHeight,
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
            }
        }
    }

    func performances(for stage: OMERecord.Stage) -> [OMERecord.Performance] {
        performances.filter { $0.stageID == stage.id.stageID }
    }
}

struct ScheduleFixedStageTimeline: View {
    let stage: OMERecord.Stage
    let performances: [OMERecord.Performance]
    let timeRange: DateInterval
    let pageHeight: CGFloat
    let showsAuthoringControls: Bool
    let onEditPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onDeletePerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void

    var body: some View {
        ScheduleStageTimelinePage(
            stage: stage,
            performances: performances,
            timeRange: timeRange,
            showsAuthoringControls: showsAuthoringControls,
            onEditPerformanceTapped: onEditPerformanceTapped,
            onDeletePerformanceTapped: onDeletePerformanceTapped,
            onPerformanceTapped: onPerformanceTapped
        )
        .frame(height: pageHeight)
        .environment(\.scheduleHeight, pageHeight)
        .environment(\.scheduleTimeRange, timeRange)
        .environment(\.shouldShowTimeIndicator, true)
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
