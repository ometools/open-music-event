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
            self.scheduleViewerState = ScheduleViewerState(
                eventID: eventID,
                scheduleDivision: scheduleDivision
            )
            self._persistedScheduleViewerState = FetchOne(
                wrappedValue: nil,
                ScheduleViewerState.none
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
        public var scheduleViewerState: ScheduleViewerState
        @FetchOne var persistedScheduleViewerState: ScheduleViewerState?

        @FetchAll public var performanceRows: [PerformanceRow]
        @FetchAll public var schedules: [OMERecord.Schedule]
        @FetchAll public var stages: [OMERecord.Stage]

        public var scheduleOrientation: ScheduleViewerState.ScheduleKind.Orientation {
            if case let .allStagesAtOnce(orientation) = scheduleViewerState.scheduleKind {
                return orientation
            }
            return .vertical
        }

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
        case newUserScheduleButtonTapped(OMERecord.ID<OMERecord.Performance>)
        case performanceButtonTapped(OMERecord.ID<OMERecord.Performance>)
        case scheduleDivisionButtonTapped(ScheduleViewer.ScheduleDivision)
        case userScheduleMembershipButtonTapped(
            OMERecord.ID<OMERecord.Performance>,
            UserSchedule.ID
        )
    }

    @Dependency(\.defaultDatabase) var database

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

            case let .newUserScheduleButtonTapped(performanceID):
                store.addTask {
                    let task = try store.post(
                        key: SchedulePerformanceNewUserScheduleRequested.self,
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

            case let .scheduleDivisionButtonTapped(division):
                store.addTask {
                    let task = try store.post(
                        key: ScheduleDivisionRequested.self,
                        value: division
                    )
                    await task?.value
                }

            case let .userScheduleMembershipButtonTapped(performanceID, scheduleID):
                store.addTask {
                    let task = try store.post(
                        key: SchedulePerformanceUserScheduleMembershipRequested.self,
                        value: SchedulePerformanceUserScheduleMembershipRequest(
                            performanceID: performanceID,
                            scheduleID: scheduleID
                        )
                    )
                    await task?.value
                }
            }
        }
        .onChange(of: store.persistedScheduleViewerState) { _, persistedState, state in
            guard var persistedState else { return }
            persistedState.migrateLegacyScheduleKind()
            guard persistedState != state.scheduleViewerState else { return }
            state.scheduleViewerState = persistedState
        }
        .onMount { state in
            let eventID = state.eventID
            let scheduleDivision = state.scheduleDivision
            let initialState = state.scheduleViewerState
            let persistedState = state.$persistedScheduleViewerState
            store.addTask {
                let subscription = try await persistedState.load(
                    ScheduleViewerState.rows(
                        eventID: eventID,
                        scheduleDivision: scheduleDivision
                    )
                )
                if persistedState.wrappedValue == nil {
                    let defaultState = try await database.read { db in
                        try ScheduleViewerStateRequest(
                            eventID: eventID,
                            scheduleDivision: scheduleDivision
                        )
                        .fetch(db)
                    }
                    try store.modify {
                        guard $0.persistedScheduleViewerState == nil,
                              $0.scheduleViewerState == initialState
                        else { return }
                        $0.scheduleViewerState = defaultState
                    }
                }
                try await subscription.task
            }
        }
    }
}

public struct ScheduleManyStagesAtOnceView: View {
    @Bindable var store: StoreOf<ScheduleManyStagesAtOnce>
    @Binding var selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
    let userScheduleOverlay: UserScheduleOverlay
    let showsAuthoringControls: Bool

    let minimumStageLaneWidth: CGFloat = 132
    let compactVisibleStageLaneCount: CGFloat = 2.5
    let compactStageRevealMaxAvailableWidth: CGFloat = 500
    let minimumHorizontalStageLaneHeight: CGFloat = 84
    let minimumHorizontalPointsPerHour: CGFloat = 160

    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    @Environment(\.scheduleNowScrollRequest) var scheduleNowScrollRequest
    @Environment(\.schedulePointsPerHour) var schedulePointsPerHour
    @Environment(\.scheduleTimeBuffer) var scheduleTimeBuffer
    @Environment(\.showStageNameLabels) var showStageNameLabels

    public init(
        store: StoreOf<ScheduleManyStagesAtOnce>,
        selectedScheduleID: Binding<OMERecord.ID<OMERecord.Schedule>?>,
        userScheduleOverlay: UserScheduleOverlay,
        showsAuthoringControls: Bool
    ) {
        self.store = store
        self._selectedScheduleID = selectedScheduleID
        self.userScheduleOverlay = userScheduleOverlay
        self.showsAuthoringControls = showsAuthoringControls
    }

    public var body: some View {
        if visibleStages.isEmpty {
            emptyScheduleView
        } else {
            GeometryReader { geometry in
                scheduleBody(
                    availableWidth: geometry.size.width,
                    availableHeight: geometry.size.height,
                    timeRange: timeRange
                )
            }
        }
    }

    @ViewBuilder
    func scheduleBody(
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        timeRange: DateInterval?
    ) -> some View {
        switch store.scheduleOrientation {
        case .vertical:
            verticalScheduleBody(
                availableWidth: availableWidth,
                availableHeight: availableHeight,
                timeRange: timeRange
            )

        case .horizontal:
            horizontalScheduleBody(
                availableWidth: availableWidth,
                availableHeight: availableHeight,
                timeRange: timeRange
            )
        }
    }

    @ViewBuilder
    func verticalScheduleBody(
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        timeRange: DateInterval?
    ) -> some View {
        ScrollView(.horizontal) {
            verticalScheduleScroll(
                availableWidth: availableWidth,
                availableHeight: availableHeight,
                timeRange: timeRange
            )
            .frame(
                width: contentWidth(for: availableWidth),
                height: availableHeight
            )
        }
    }

    func horizontalScheduleBody(
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        timeRange: DateInterval?
    ) -> some View {
        let stageRailWidth = horizontalStageRailWidth
        let stageLaneHeight = horizontalStageLaneHeight(availableHeight: availableHeight)
        let availableTimelineWidth = max(availableWidth - stageRailWidth, 0)
        let timelineWidth = timeRange.map {
            horizontalTimelineWidth(for: $0, availableWidth: availableTimelineWidth)
        } ?? availableTimelineWidth
        let timelineHeight = horizontalTimelineHeight(stageLaneHeight: stageLaneHeight)
        let totalHeight = timelineHeight + hourLabelsHeight

        return ScrollView(.vertical) {
            horizontalTimelineScroll(
                stageRailWidth: stageRailWidth,
                stageLaneHeight: stageLaneHeight,
                timelineWidth: timelineWidth,
                timelineHeight: timelineHeight,
                totalHeight: totalHeight,
                timeRange: timeRange
            )
            .frame(
                minWidth: availableWidth,
                minHeight: max(availableHeight, totalHeight),
                alignment: .topLeading
            )
        }
    }

    @ViewBuilder
    func horizontalTimelineScroll(
        stageRailWidth: CGFloat,
        stageLaneHeight: CGFloat,
        timelineWidth: CGFloat,
        timelineHeight: CGFloat,
        totalHeight: CGFloat,
        timeRange: DateInterval?
    ) -> some View {
        #if os(iOS)
        horizontalTimelinePageScroll(
            timelineWidth: timelineWidth,
            timelineHeight: timelineHeight,
            totalHeight: totalHeight,
            timeRange: timeRange
        )
        .safeAreaInset(edge: .leading, alignment: .top, spacing: 0) {
            horizontalStageRail(
                width: stageRailWidth,
                laneHeight: stageLaneHeight
            )
        }
        #else
        horizontalInlineTimelineScroll(
            stageRailWidth: stageRailWidth,
            stageLaneHeight: stageLaneHeight,
            timelineWidth: timelineWidth,
            timelineHeight: timelineHeight,
            totalHeight: totalHeight,
            timeRange: timeRange
        )
        #endif
    }

    func horizontalInlineTimelineScroll(
        stageRailWidth: CGFloat,
        stageLaneHeight: CGFloat,
        timelineWidth: CGFloat,
        timelineHeight: CGFloat,
        totalHeight: CGFloat,
        timeRange: DateInterval?
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            horizontalStageRail(
                width: stageRailWidth,
                laneHeight: stageLaneHeight
            )

            horizontalTimelinePageScroll(
                timelineWidth: timelineWidth,
                timelineHeight: timelineHeight,
                totalHeight: totalHeight,
                timeRange: timeRange
            )
        }
    }

    func horizontalTimelinePageScroll(
        timelineWidth: CGFloat,
        timelineHeight: CGFloat,
        totalHeight: CGFloat,
        timeRange: DateInterval?
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                timelinePage
                    .frame(width: timelineWidth, height: totalHeight)
                    .environment(\.scheduleTimelineOrientation, .horizontalTime)
                    .environment(\.scheduleHeight, timelineHeight)
                    .environment(\.scheduleTimeRange, timeRange)
                    .environment(\.shouldShowTimeIndicator, true)
            }
            .onChange(of: scheduleNowScrollRequest) { _, request in
                guard let request else { return }
                scrollToCurrentTime(proxy: proxy, animated: request.animated)
            }
        }
    }

    func horizontalStageRail(
        width: CGFloat,
        laneHeight: CGFloat
    ) -> some View {
        ScheduleManyStagesStageRail(
            stages: visibleStages,
            unavailableStageIDs: unavailableStageIDs,
            width: width,
            laneHeight: laneHeight
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    func verticalScheduleScroll(
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        timeRange: DateInterval?
    ) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *), needsStageDisambiguation {
            scheduleScroll(
                availableWidth: availableWidth,
                availableHeight: availableHeight,
                timeRange: timeRange
            )
            .safeAreaBar(edge: .top) {
                laneHeader(availableWidth: availableWidth)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        } else if needsStageDisambiguation {
            scheduleScroll(
                availableWidth: availableWidth,
                availableHeight: availableHeight,
                timeRange: timeRange
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                laneHeader(availableWidth: availableWidth)
            }
        } else {
            scheduleScroll(
                availableWidth: availableWidth,
                availableHeight: availableHeight,
                timeRange: timeRange
            )
        }
        #else
        if needsStageDisambiguation {
            scheduleScroll(
                availableWidth: availableWidth,
                availableHeight: availableHeight,
                timeRange: timeRange
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                laneHeader(availableWidth: availableWidth)
            }
        } else {
            scheduleScroll(
                availableWidth: availableWidth,
                availableHeight: availableHeight,
                timeRange: timeRange
            )
        }
        #endif
    }

    func scheduleScroll(
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        timeRange: DateInterval?
    ) -> some View {
        let pageHeight = timeRange.map { scheduleHeight(for: $0) } ?? availableHeight
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                timelinePage
                .frame(
                    width: contentWidth(for: availableWidth),
                    height: pageHeight
                )
                .environment(\.scheduleHeight, pageHeight)
                .environment(\.scheduleTimeRange, timeRange)
                .environment(\.shouldShowTimeIndicator, true)
            }
            .onChange(of: scheduleNowScrollRequest) { _, request in
                guard let request else { return }
                scrollToCurrentTime(proxy: proxy, animated: request.animated)
            }
        }
    }

    func scrollToCurrentTime(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation {
                proxy.scrollTo(ScheduleScrollTarget.currentTime, anchor: .center)
            }
        } else {
            proxy.scrollTo(ScheduleScrollTarget.currentTime, anchor: .center)
        }
    }

    func laneHeader(availableWidth: CGFloat) -> some View {
        ScheduleManyStagesLaneHeader(
            stages: visibleStages,
            unavailableStageIDs: unavailableStageIDs,
            contentWidth: contentWidth(for: availableWidth),
            height: stageLaneHeaderHeight,
            minimumStageLaneWidth: minimumStageLaneWidth
        )
        .allowsHitTesting(false)
    }

    var timelinePage: some View {
        SchedulePageView(timelineCards, groups: timelineGroups) { card in
            ScheduleTimelineCardView(
                performance: card.performance,
                stage: card.stage,
                userScheduleOverlay: userScheduleOverlay,
                showsAuthoringControls: showsAuthoringControls,
                userScheduleMembershipAction: { scheduleID in
                    store.send(
                        .userScheduleMembershipButtonTapped(
                            card.id,
                            scheduleID
                        )
                    )
                },
                newUserScheduleAction: {
                    store.send(.newUserScheduleButtonTapped(card.id))
                },
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
    }

    var timelineGroups: [Int] {
        Self.timelineGroups(stageCount: visibleStages.count)
    }

    static func timelineGroups(stageCount: Int) -> [Int] {
        Array(0..<stageCount)
    }

    var stageLaneHeaderHeight: CGFloat {
        showStageNameLabels ? 116 : 84
    }

    var hourLabelsHeight: CGFloat {
        HourLabelsHeightPreferenceKey.defaultValue
    }

    var horizontalStageRailWidth: CGFloat {
        showStageNameLabels ? 116 : 84
    }

    var minimumResolvedHorizontalStageLaneHeight: CGFloat {
        showStageNameLabels ? 104 : minimumHorizontalStageLaneHeight
    }

    func horizontalStageLaneHeight(availableHeight: CGFloat) -> CGFloat {
        Self.horizontalStageLaneHeight(
            availableHeight: availableHeight,
            stageCount: visibleStages.count,
            hourLabelsHeight: hourLabelsHeight,
            minimumStageLaneHeight: minimumResolvedHorizontalStageLaneHeight
        )
    }

    static func horizontalStageLaneHeight(
        availableHeight: CGFloat,
        stageCount: Int,
        hourLabelsHeight: CGFloat = HourLabelsHeightPreferenceKey.defaultValue,
        minimumStageLaneHeight: CGFloat
    ) -> CGFloat {
        guard stageCount > 0 else { return minimumStageLaneHeight }

        let availableStageHeight = max(availableHeight - hourLabelsHeight, 0)
        return max(
            minimumStageLaneHeight,
            availableStageHeight / CGFloat(stageCount)
        )
    }

    func horizontalTimelineHeight(stageLaneHeight: CGFloat) -> CGFloat {
        CGFloat(visibleStages.count) * stageLaneHeight
    }

    var horizontalPointsPerHour: CGFloat {
        max(schedulePointsPerHour * 2, minimumHorizontalPointsPerHour)
    }

    func horizontalTimelineWidth(
        for timeRange: DateInterval,
        availableWidth: CGFloat
    ) -> CGFloat {
        max(
            availableWidth,
            CGFloat(timeRange.duration / 3600) * horizontalPointsPerHour
        )
    }

    var emptyPerformancesView: some View {
        ScheduleEmptyView(
            title: ScheduleViewer.emptyScheduleTitle(
                scheduleDivision: store.scheduleDivision,
                scheduleTitle: selectedScheduleTitle
            ),
            otherScheduleDivisions: otherScheduleDivisions,
            onScheduleDivisionTapped: { division in
                store.send(.scheduleDivisionButtonTapped(division))
            }
        )
    }

    var emptyScheduleView: some View {
        emptyPerformancesView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    var timelineCards: [ScheduleManyStagesTimelineCard] {
        Self.timelineCards(
            performanceRows: visiblePerformanceRows,
            stages: visibleStages
        )
    }

    var visiblePerformanceRows: [PerformanceRow] {
        store.state.visiblePerformanceRows(selectedScheduleID: selectedScheduleID)
    }

    var visiblePerformances: [OMERecord.Performance] {
        visiblePerformanceRows.map(\.performance)
    }

    var visibleStages: [OMERecord.Stage] {
        ScheduleViewer.orderedStages(
            store.visibleStages,
            performances: visiblePerformances
        )
    }

    var unavailableStageIDs: Set<OMERecord.ID<OMERecord.Stage>> {
        ScheduleViewer.unavailableStageIDs(
            stages: visibleStages,
            performances: visiblePerformances
        )
    }

    var otherScheduleDivisions: [ScheduleViewer.ScheduleDivision] {
        ScheduleViewer.scheduleDivisions(stages: store.stages)
            .filter { $0 != store.scheduleDivision }
    }

    var selectedScheduleTitle: String {
        guard let scheduleID = ScheduleViewer.resolvedSelectedScheduleID(
            selectedScheduleID,
            schedules: store.schedules
        ),
            let schedule = store.schedules.first(where: { $0.id.scheduleID == scheduleID })
        else { return "Select Schedule" }
        return ScheduleViewer.scheduleTitle(schedule)
    }

    var timeRange: DateInterval? {
        ScheduleStageTimelinePage.timeRange(
            for: timelineCards.map(\.performance),
            buffer: scheduleTimeBuffer
        )
    }

    func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        Self.contentWidth(
            availableWidth: availableWidth,
            stageCount: visibleStages.count,
            minimumStageLaneWidth: minimumStageLaneWidth,
            compactVisibleStageLaneCount: compactVisibleStageLaneCount,
            compactStageRevealMaxAvailableWidth: compactStageRevealMaxAvailableWidth
        )
    }

    static func contentWidth(
        availableWidth: CGFloat,
        stageCount: Int,
        minimumStageLaneWidth: CGFloat,
        hourLabelsWidth: CGFloat = HourLabelsWidthPreferenceKey.defaultValue,
        compactVisibleStageLaneCount: CGFloat = 2.5,
        compactStageRevealMaxAvailableWidth: CGFloat = 500
    ) -> CGFloat {
        let naturalContentWidth = hourLabelsWidth
            + CGFloat(stageCount) * minimumStageLaneWidth
        let compactRevealContentWidth = compactStageRevealContentWidth(
            availableWidth: availableWidth,
            stageCount: stageCount,
            minimumStageLaneWidth: minimumStageLaneWidth,
            hourLabelsWidth: hourLabelsWidth,
            compactVisibleStageLaneCount: compactVisibleStageLaneCount,
            compactStageRevealMaxAvailableWidth: compactStageRevealMaxAvailableWidth
        )

        return max(
            max(availableWidth, naturalContentWidth),
            compactRevealContentWidth
        )
    }

    static func compactStageRevealContentWidth(
        availableWidth: CGFloat,
        stageCount: Int,
        minimumStageLaneWidth: CGFloat,
        hourLabelsWidth: CGFloat = HourLabelsWidthPreferenceKey.defaultValue,
        compactVisibleStageLaneCount: CGFloat = 2.5,
        compactStageRevealMaxAvailableWidth: CGFloat = 500
    ) -> CGFloat {
        guard availableWidth > 0,
              CGFloat(stageCount) > compactVisibleStageLaneCount,
              compactVisibleStageLaneCount > 0,
              availableWidth <= compactStageRevealMaxAvailableWidth
        else { return 0 }

        let visibleStageArea = max(availableWidth - hourLabelsWidth, 0)
        let stageLaneWidth = max(
            minimumStageLaneWidth,
            visibleStageArea / compactVisibleStageLaneCount
        )

        return hourLabelsWidth + CGFloat(stageCount) * stageLaneWidth
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
    let unavailableStageIDs: Set<OMERecord.ID<OMERecord.Stage>>
    let contentWidth: CGFloat
    let height: CGFloat
    let minimumStageLaneWidth: CGFloat

    @Environment(\.showStageNameLabels) var showStageNameLabels

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear
                .frame(width: hourLabelsWidth)

            ForEach(stages) { stage in
                stageHeaderCell(for: stage)
                    .frame(width: stageSelectorCellWidth)
                    .frame(width: stageLaneWidth)
                    .opacity(unavailableStageIDs.contains(stage.id.stageID) ? 0.45 : 1)
            }
        }
        .padding(.vertical, 8)
        .frame(width: contentWidth, height: height, alignment: .topLeading)
    }

    func stageHeaderCell(for stage: OMERecord.Stage) -> some View {
        VStack(spacing: 6) {
            ScheduleStageIcon(stage: stage)
                .frame(width: stageIconSize, height: stageIconSize)
                .padding(stageIconPadding)
                .foregroundStyle(stage.color.swiftUIColor)
                .background {
                    Circle()
                        .fill(stage.color.swiftUIColor.opacity(stageIconFillOpacity))
                        .overlay {
                            Circle()
                                .stroke(
                                    stage.color.swiftUIColor.opacity(stageIconStrokeOpacity),
                                    lineWidth: 1
                                )
                        }
                }

            if showStageNameLabels {
                Text(stage.name)
                    .font(.caption2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var stageIconSize: CGFloat {
        44
    }

    var stageIconPadding: CGFloat {
        12
    }

    var hourLabelsWidth: CGFloat {
        HourLabelsWidthPreferenceKey.defaultValue
    }

    var stageSelectorCellWidth: CGFloat {
        showStageNameLabels ? 112 : 76
    }

    var stageIconFillOpacity: CGFloat {
        0.12
    }

    var stageIconStrokeOpacity: CGFloat {
        0.28
    }

    var stageLaneWidth: CGFloat {
        guard !stages.isEmpty else { return minimumStageLaneWidth }
        return max(
            minimumStageLaneWidth,
            (contentWidth - hourLabelsWidth) / CGFloat(stages.count)
        )
    }
}

struct ScheduleManyStagesStageRail: View {
    let stages: [OMERecord.Stage]
    let unavailableStageIDs: Set<OMERecord.ID<OMERecord.Stage>>
    let width: CGFloat
    let laneHeight: CGFloat

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.showStageNameLabels) var showStageNameLabels

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: hourLabelsHeight)

            ForEach(stages) { stage in
                stageRailCell(for: stage)
                    .frame(width: width, height: laneHeight)
                    .opacity(unavailableStageIDs.contains(stage.id.stageID) ? 0.45 : 1)
            }
        }
        .frame(width: width, alignment: .top)
        .background(alignment: .leading) {
            ZStack {
                LinearGradient(
                    colors: [
                        railBackgroundColor,
                        railBackgroundColor.opacity(0.64),
                        railBackgroundColor.opacity(0.0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask {
                        LinearGradient(
                            colors: [.white.opacity(0.42), .white.opacity(0.14), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
            }
        }
    }

    func stageRailCell(for stage: OMERecord.Stage) -> some View {
        VStack(spacing: 6) {
            ScheduleStageIcon(stage: stage)
                .frame(width: stageIconSize, height: stageIconSize)
                .padding(stageIconPadding)
                .foregroundStyle(stage.color.swiftUIColor)
                .background {
                    Circle()
                        .fill(stage.color.swiftUIColor.opacity(stageIconFillOpacity))
                        .overlay {
                            Circle()
                                .stroke(
                                    stage.color.swiftUIColor.opacity(stageIconStrokeOpacity),
                                    lineWidth: 1
                                )
                        }
                }

            if showStageNameLabels {
                Text(stage.name)
                    .font(.caption2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
    }

    var stageIconSize: CGFloat {
        44
    }

    var stageIconPadding: CGFloat {
        12
    }

    var hourLabelsHeight: CGFloat {
        HourLabelsHeightPreferenceKey.defaultValue
    }

    var stageIconFillOpacity: CGFloat {
        0.12
    }

    var stageIconStrokeOpacity: CGFloat {
        0.28
    }

    var railBackgroundColor: Color {
        switch colorScheme {
        case .dark:
            return .black
        case .light:
            return .white
        @unknown default:
            return .clear
        }
    }
}
