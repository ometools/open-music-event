import ComposableArchitecture2
import Foundation
import ScheduleComponents
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
            self.eventID = eventID
            self._timeZone = FetchOne(
                OMERecord.Event.timeZoneQuery(eventID: eventID)
            )
            self.scheduleDivision = scheduleDivision
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
        @FetchOne public var timeZone: TimeZone?
        var eventTimePresentation: EventTimePresentation? {
            timeZone.map { EventTimePresentation(timeZone: $0) }
        }
        public let scheduleDivision: ScheduleViewer.ScheduleDivision

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
        case newUserScheduleButtonTapped(OMERecord.ID<OMERecord.Performance>)
        case scheduleDivisionButtonTapped(ScheduleViewer.ScheduleDivision)
        case userScheduleMembershipButtonTapped(
            OMERecord.ID<OMERecord.Performance>,
            UserSchedule.ID
        )
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

            case let .newUserScheduleButtonTapped(performanceID):
                store.addTask {
                    let task = try store.post(
                        key: SchedulePerformanceNewUserScheduleRequested.self,
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
    }
}

public struct ScheduleManyStagesAtOnceView: View {
    @Bindable var store: StoreOf<ScheduleManyStagesAtOnce>
    let orientation: ScheduleViewerState.ScheduleKind.Orientation
    @Binding var selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
    let userScheduleOverlay: UserScheduleOverlay
    let showsAuthoringControls: Bool
    let performanceButtonTapped: (OMERecord.ID<OMERecord.Performance>) -> Void

    let minimumStageLaneWidth: CGFloat = 132
    let compactVisibleStageLaneCount: CGFloat = 2.5
    let compactStageRevealMaxAvailableWidth: CGFloat = 500
    let minimumHorizontalStageLaneHeight: CGFloat = 84
    let minimumHorizontalPointsPerHour: CGFloat = 160

    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    @Environment(\.eventTimePresentation) var eventTimePresentation
    @Environment(\.scheduleNowScrollRequest) var scheduleNowScrollRequest
    @Environment(\.schedulePointsPerHour) var schedulePointsPerHour
    @Environment(\.scheduleTimeBuffer) var scheduleTimeBuffer
    @Environment(\.showStageNameLabels) var showStageNameLabels
    @Environment(\.timeZone) var deviceTimeZone

    public init(
        store: StoreOf<ScheduleManyStagesAtOnce>,
        orientation: ScheduleViewerState.ScheduleKind.Orientation,
        selectedScheduleID: Binding<OMERecord.ID<OMERecord.Schedule>?>,
        userScheduleOverlay: UserScheduleOverlay,
        showsAuthoringControls: Bool,
        performanceButtonTapped: @escaping (OMERecord.ID<OMERecord.Performance>) -> Void
    ) {
        self.store = store
        self.orientation = orientation
        self._selectedScheduleID = selectedScheduleID
        self.userScheduleOverlay = userScheduleOverlay
        self.showsAuthoringControls = showsAuthoringControls
        self.performanceButtonTapped = performanceButtonTapped
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
        switch orientation {
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
        #if os(Android)
        let availableTimelineWidth = availableWidth
        #else
        let availableTimelineWidth = max(availableWidth - stageRailWidth, 0)
        #endif
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
        #elseif os(Android)
        horizontalOverlayTimelineScroll(
            stageRailWidth: stageRailWidth,
            stageLaneHeight: stageLaneHeight,
            timelineWidth: timelineWidth,
            timelineHeight: timelineHeight,
            totalHeight: totalHeight,
            timeRange: timeRange
        )
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

    func horizontalOverlayTimelineScroll(
        stageRailWidth: CGFloat,
        stageLaneHeight: CGFloat,
        timelineWidth: CGFloat,
        timelineHeight: CGFloat,
        totalHeight: CGFloat,
        timeRange: DateInterval?
    ) -> some View {
        ZStack(alignment: .topLeading) {
            horizontalTimelinePageScroll(
                timelineWidth: timelineWidth,
                timelineHeight: timelineHeight,
                totalHeight: totalHeight,
                timeRange: timeRange
            )

            horizontalStageRail(
                width: stageRailWidth,
                laneHeight: stageLaneHeight
            )
        }
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
                    .environment(\.scheduleWidth, timelineWidth)
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
            .portableSafeAreaTopInset(spacing: 0) {
                laneHeader(availableWidth: availableWidth)
            }
        } else {
            scheduleScroll(
                availableWidth: availableWidth,
                availableHeight: availableHeight,
                timeRange: timeRange
            )
        }
        #elseif os(Android)
        if needsStageDisambiguation {
            let timelineHeight = max(availableHeight - stageLaneHeaderHeight, 0)
            VStack(spacing: 0) {
                laneHeader(availableWidth: availableWidth)
                scheduleScroll(
                    availableWidth: availableWidth,
                    availableHeight: timelineHeight,
                    timeRange: timeRange
                )
                .frame(height: timelineHeight)
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
            .portableSafeAreaTopInset(spacing: 0) {
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
                .environment(
                    \.scheduleWidth,
                    resolvedTimelineWidth(totalWidth: contentWidth(for: availableWidth))
                )
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
        Group {
            if let eventTimePresentation {
                SchedulePageView(
                    timelineCards,
                    groups: timelineGroups,
                    currentTimeLabel: {
                        eventTimePresentation.currentTimeLabel(
                            for: $0,
                            disclosure: .whenDeviceClockDiffers(deviceTimeZone)
                        )
                    },
                    hourLabel: {
                        eventTimePresentation.hourLabel(for: $0)
                    }
                ) { card in
                    ScheduleTimelineCardView(
                        performance: card.performance,
                        stage: card.stage,
                        timeRangeText: eventTimePresentation.performanceRowTimeRange(
                            for: card.performance
                        ),
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
                            performanceButtonTapped(card.id)
                        }
                    )
                } emptyContent: {
                    emptyPerformancesView
                }
            }
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
            let schedule = store.schedules.first(where: { $0.id.scheduleID == scheduleID }),
            let timeZone = store.timeZone
        else { return "Select Schedule" }
        return ScheduleViewer.scheduleTitle(schedule, in: timeZone)
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

    func timelineContentWidth(totalWidth: CGFloat) -> CGFloat {
        Self.timelineContentWidth(
            totalWidth: totalWidth,
            hourLabelsWidth: HourLabelsWidthPreferenceKey.defaultValue
        )
    }

    func resolvedTimelineWidth(totalWidth: CGFloat) -> CGFloat {
        Self.resolvedTimelineWidth(
            totalWidth: totalWidth,
            hourLabelsWidth: HourLabelsWidthPreferenceKey.defaultValue
        )
    }

    static func resolvedTimelineWidth(
        totalWidth: CGFloat,
        hourLabelsWidth: CGFloat
    ) -> CGFloat {
        timelineContentWidth(
            totalWidth: totalWidth,
            hourLabelsWidth: hourLabelsWidth
        )
    }

    static func timelineContentWidth(
        totalWidth: CGFloat,
        hourLabelsWidth: CGFloat
    ) -> CGFloat {
        max(totalWidth - hourLabelsWidth, 0)
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
            ScheduleManyStagesStageBubble(stage: stage)

            if showStageNameLabels {
                Text(stage.name)
                    .font(.caption2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
            }
        }
    }

    var hourLabelsWidth: CGFloat {
        HourLabelsWidthPreferenceKey.defaultValue
    }

    var stageSelectorCellWidth: CGFloat {
        showStageNameLabels ? 112 : 76
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
    }

    func stageRailCell(for stage: OMERecord.Stage) -> some View {
        VStack(spacing: 6) {
            ScheduleManyStagesStageBubble(stage: stage)

            if showStageNameLabels {
                Text(stage.name)
                    .font(.caption2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 6)
    }

    var hourLabelsHeight: CGFloat {
        HourLabelsHeightPreferenceKey.defaultValue
    }

}

struct ScheduleManyStagesStageBubble: View {
    let stage: OMERecord.Stage

    @ViewBuilder
    var body: some View {
        #if os(iOS) || os(macOS)
        if #available(iOS 26, macOS 26, *) {
            liquidGlassBubble
        } else {
            standardBubble
        }
        #else
        standardBubble
        #endif
    }

    #if os(iOS) || os(macOS)
    @available(iOS 26, macOS 26, *)
    var liquidGlassBubble: some View {
        ScheduleStageIcon(stage: stage)
            .padding(4)
            .frame(width: 70, height: 70)
            .foregroundStyle(.white)
            .glassEffect(.clear.tint(stage.color.swiftUIColor).interactive(), in: .capsule)
    }
    #endif

    var standardBubble: some View {
        ScheduleStageIcon(stage: stage)
            .frame(width: 44, height: 44)
            .padding(12)
            .foregroundStyle(.white)
            .background {
                Circle()
                    .fill(stage.color.swiftUIColor.opacity(0.85))
                    .overlay {
                        Circle()
                            .stroke(
                                stage.color.swiftUIColor.opacity(0.28),
                                lineWidth: 1
                            )
                    }
            }
    }
}
