import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
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
            self.eventID = eventID
            self._timeZone = FetchOne(
                OMERecord.Event.timeZoneQuery(eventID: eventID)
            )
            self.scheduleDivision = scheduleDivision
            let scheduleViewerState = ScheduleViewerState(
                eventID: eventID,
                scheduleDivision: scheduleDivision
            )
            self.scheduleViewerState = scheduleViewerState
            self.scheduleViewerStateBaseline = scheduleViewerState
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
        @FetchOne public var timeZone: TimeZone?
        var eventTimePresentation: EventTimePresentation? {
            timeZone.map { EventTimePresentation(timeZone: $0) }
        }
        public let scheduleDivision: ScheduleViewer.ScheduleDivision
        public var scheduleViewerState: ScheduleViewerState
        var scheduleViewerStateBaseline: ScheduleViewerState
        @FetchOne var persistedScheduleViewerState: ScheduleViewerState?

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
                scheduleViewerState.selectedStageID = selectedStageID
            }
        }

        mutating func normalizeSelectedStageID() {
            scheduleViewerState.selectedStageID = ScheduleViewer.normalizedSelectedStageID(
                selectedStageID: scheduleViewerState.selectedStageID,
                stages: visibleStages
            )
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
        case newUserScheduleButtonTapped(OMERecord.ID<OMERecord.Performance>)
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
            state.scheduleViewerStateBaseline = persistedState
            if persistedState != state.scheduleViewerState {
                state.scheduleViewerState = persistedState
            }
            state.normalizeSelectedStageID()
        }
        .onChange(of: store.scheduleViewerState) { oldViewerState, viewerState, state in
            guard state.scheduleViewerStateBaseline != viewerState else { return }
            do {
                try database.write { db in
                    try ScheduleViewerState.persistChanges(
                        from: oldViewerState,
                        to: viewerState,
                        eventID: state.eventID,
                        scheduleDivision: state.scheduleDivision,
                        in: db
                    )
                }
                state.scheduleViewerStateBaseline = viewerState
            } catch {
                reportIssue(error)
            }
        }
        .onChange(of: store.visibleStages) { _, _, state in
            state.normalizeSelectedStageID()
        }
        .onMount { state in
            state.normalizeSelectedStageID()
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
                        $0.scheduleViewerStateBaseline = defaultState
                        $0.scheduleViewerState = defaultState
                        $0.normalizeSelectedStageID()
                    }
                }
                try await subscription.task
            }
        }
    }
}

public struct ScheduleSingleStageAtOnceView: View {
    @Bindable var store: StoreOf<ScheduleSingleStageAtOnce>
    @Binding var selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
    let userScheduleOverlay: UserScheduleOverlay
    let showsAuthoringControls: Bool
    let performanceButtonTapped: (OMERecord.ID<OMERecord.Performance>) -> Void

    @Environment(\.schedulePointsPerHour) var schedulePointsPerHour
    @Environment(\.scheduleTimeBuffer) var scheduleTimeBuffer
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation

    public init(
        store: StoreOf<ScheduleSingleStageAtOnce>,
        selectedScheduleID: Binding<OMERecord.ID<OMERecord.Schedule>?>,
        userScheduleOverlay: UserScheduleOverlay,
        showsAuthoringControls: Bool,
        performanceButtonTapped: @escaping (OMERecord.ID<OMERecord.Performance>) -> Void
    ) {
        self.store = store
        self._selectedScheduleID = selectedScheduleID
        self.userScheduleOverlay = userScheduleOverlay
        self.showsAuthoringControls = showsAuthoringControls
        self.performanceButtonTapped = performanceButtonTapped
    }

    public var body: some View {
        content
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
                stages: visibleStages,
                unavailableStageIDs: unavailableStageIDs,
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
        if visibleStages.isEmpty {
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
        } else if let eventTimePresentation = store.state.eventTimePresentation {
            ScheduleStagePager(
                selectedStageID: $store.selectedStageID,
                stages: visibleStages,
                performances: visiblePerformances,
                timeRange: timeRange,
                eventTimePresentation: eventTimePresentation,
                pageHeight: timeRange.map { scheduleHeight(for: $0) },
                userScheduleOverlay: userScheduleOverlay,
                scheduleDivision: store.scheduleDivision,
                scheduleTitle: selectedScheduleTitle,
                otherScheduleDivisions: otherScheduleDivisions,
                showsAuthoringControls: showsAuthoringControls,
                onUserScheduleMembershipTapped: { performanceID, scheduleID in
                    store.send(
                        .userScheduleMembershipButtonTapped(
                            performanceID,
                            scheduleID
                        )
                    )
                },
                onNewUserScheduleTapped: { performanceID in
                    store.send(.newUserScheduleButtonTapped(performanceID))
                },
                onEditPerformanceTapped: { performanceID in
                    store.send(.editPerformanceButtonTapped(performanceID))
                },
                onDeletePerformanceTapped: { performanceID in
                    store.send(.deletePerformanceButtonTapped(performanceID))
                },
                onPerformanceTapped: { performanceID in
                    performanceButtonTapped(performanceID)
                },
                onScheduleDivisionTapped: { division in
                    store.send(.scheduleDivisionButtonTapped(division))
                }
            )
        }
    }

    var visiblePerformances: [OMERecord.Performance] {
        store.state.visiblePerformances(selectedScheduleID: selectedScheduleID)
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
        guard let scheduleID = store.state.resolvedSelectedScheduleID(selectedScheduleID),
              let schedule = store.schedules.first(where: { $0.id.scheduleID == scheduleID }),
              let timeZone = store.timeZone
        else { return "Select Schedule" }
        return ScheduleViewer.scheduleTitle(schedule, in: timeZone)
    }

    var timeRange: DateInterval? {
        ScheduleStageTimelinePage.timeRange(
            for: visiblePerformances,
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
        needsStageDisambiguation && !visibleStages.isEmpty
    }

}

struct ScheduleEmptyView: View {
    let title: String
    let otherScheduleDivisions: [ScheduleViewer.ScheduleDivision]
    let onScheduleDivisionTapped: (ScheduleViewer.ScheduleDivision) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ContentUnavailableView {
                Label(
                    title,
                    mappedSystemImage: "calendar.day.timeline.leading"
                )
            }
            .fixedSize(horizontal: false, vertical: true)

            if !otherScheduleDivisions.isEmpty {
                scheduleDivisionButtons
            }
        }
    }

    var scheduleDivisionButtons: some View {
        VStack(spacing: 8) {
            ForEach(otherScheduleDivisions) { division in
                Button {
                    onScheduleDivisionTapped(division)
                } label: {
                    Label(
                        division.title,
                        mappedSystemImage: division.systemImage
                    )
                }
            }
        }
    }
}

struct ScheduleStagePager: View {
    @Environment(\.scheduleNowScrollRequest) var scheduleNowScrollRequest
    @Binding var selectedStageID: OMERecord.ID<OMERecord.Stage>?

    let stages: [OMERecord.Stage]
    let performances: [OMERecord.Performance]
    let timeRange: DateInterval?
    let eventTimePresentation: EventTimePresentation
    let pageHeight: CGFloat?
    let userScheduleOverlay: UserScheduleOverlay
    let scheduleDivision: ScheduleViewer.ScheduleDivision
    let scheduleTitle: String
    let otherScheduleDivisions: [ScheduleViewer.ScheduleDivision]
    let showsAuthoringControls: Bool
    let onUserScheduleMembershipTapped: (
        OMERecord.ID<OMERecord.Performance>,
        UserSchedule.ID
    ) -> Void
    let onNewUserScheduleTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onEditPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onDeletePerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onScheduleDivisionTapped: (ScheduleViewer.ScheduleDivision) -> Void

    @ViewBuilder
    var body: some View {
        if let timeRange, let pageHeight {
            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    ScrollView {
                        HorizontalPageView(page: $selectedStageID) {
                            ForEach(stages) { stage in
                                stagePage(
                                    stage,
                                    width: geometry.size.width,
                                    timeRange: timeRange,
                                    pageHeight: pageHeight
                                )
                            }
                        }
                        .frame(height: pageHeight)
                    }
                }
                .onChange(of: scheduleNowScrollRequest) { _, request in
                    guard let request else { return }
                    scrollToCurrentTime(proxy: proxy, animated: request.animated)
                }
            }
        } else {
            GeometryReader { geometry in
                HorizontalPageView(page: $selectedStageID) {
                    ForEach(stages) { stage in
                        ScheduleEmptyView(
                            title: ScheduleViewer.emptyStageTitle(
                                scheduleDivision: scheduleDivision,
                                scheduleTitle: scheduleTitle,
                                stage: stage
                            ),
                            otherScheduleDivisions: otherScheduleDivisions,
                            onScheduleDivisionTapped: onScheduleDivisionTapped
                        )
                        .id(stage.id.stageID)
                        .tag(Optional(stage.id.stageID))
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                    }
                }
            }
        }
    }

    func stagePage(
        _ stage: OMERecord.Stage,
        width: CGFloat,
        timeRange: DateInterval,
        pageHeight: CGFloat
    ) -> some View {
        ScheduleFixedStageTimeline(
            stage: stage,
            performances: performances(for: stage),
            timeRange: timeRange,
            eventTimePresentation: eventTimePresentation,
            pageHeight: pageHeight,
            userScheduleOverlay: userScheduleOverlay,
            emptyTitle: ScheduleViewer.emptyStageTitle(
                scheduleDivision: scheduleDivision,
                scheduleTitle: scheduleTitle,
                stage: stage
            ),
            otherScheduleDivisions: otherScheduleDivisions,
            showsAuthoringControls: showsAuthoringControls,
            onUserScheduleMembershipTapped: onUserScheduleMembershipTapped,
            onNewUserScheduleTapped: onNewUserScheduleTapped,
            onEditPerformanceTapped: onEditPerformanceTapped,
            onDeletePerformanceTapped: onDeletePerformanceTapped,
            onPerformanceTapped: onPerformanceTapped,
            onScheduleDivisionTapped: onScheduleDivisionTapped
        )
        .id(stage.id.stageID)
        .tag(Optional(stage.id.stageID))
        .frame(width: width)
        #if os(Android)
        .environment(
            \.scheduleWidth,
            max(width - HourLabelsWidthPreferenceKey.defaultValue, 0)
        )
        #endif
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

    func performances(for stage: OMERecord.Stage) -> [OMERecord.Performance] {
        performances.filter { $0.stageID == stage.id.stageID }
    }
}

struct ScheduleFixedStageTimeline: View {
    let stage: OMERecord.Stage
    let performances: [OMERecord.Performance]
    let timeRange: DateInterval
    let eventTimePresentation: EventTimePresentation
    let pageHeight: CGFloat
    let userScheduleOverlay: UserScheduleOverlay
    let emptyTitle: String
    let otherScheduleDivisions: [ScheduleViewer.ScheduleDivision]
    let showsAuthoringControls: Bool
    let onUserScheduleMembershipTapped: (
        OMERecord.ID<OMERecord.Performance>,
        UserSchedule.ID
    ) -> Void
    let onNewUserScheduleTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onEditPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onDeletePerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onScheduleDivisionTapped: (ScheduleViewer.ScheduleDivision) -> Void

    init(
        stage: OMERecord.Stage,
        performances: [OMERecord.Performance],
        timeRange: DateInterval,
        eventTimePresentation: EventTimePresentation,
        pageHeight: CGFloat,
        userScheduleOverlay: UserScheduleOverlay,
        emptyTitle: String,
        otherScheduleDivisions: [ScheduleViewer.ScheduleDivision] = [],
        showsAuthoringControls: Bool,
        onUserScheduleMembershipTapped: @escaping (
            OMERecord.ID<OMERecord.Performance>,
            UserSchedule.ID
        ) -> Void,
        onNewUserScheduleTapped: @escaping (OMERecord.ID<OMERecord.Performance>) -> Void,
        onEditPerformanceTapped: @escaping (OMERecord.ID<OMERecord.Performance>) -> Void,
        onDeletePerformanceTapped: @escaping (OMERecord.ID<OMERecord.Performance>) -> Void,
        onPerformanceTapped: @escaping (OMERecord.ID<OMERecord.Performance>) -> Void,
        onScheduleDivisionTapped: @escaping (ScheduleViewer.ScheduleDivision) -> Void = { _ in }
    ) {
        self.stage = stage
        self.performances = performances
        self.timeRange = timeRange
        self.eventTimePresentation = eventTimePresentation
        self.pageHeight = pageHeight
        self.userScheduleOverlay = userScheduleOverlay
        self.emptyTitle = emptyTitle
        self.otherScheduleDivisions = otherScheduleDivisions
        self.showsAuthoringControls = showsAuthoringControls
        self.onUserScheduleMembershipTapped = onUserScheduleMembershipTapped
        self.onNewUserScheduleTapped = onNewUserScheduleTapped
        self.onEditPerformanceTapped = onEditPerformanceTapped
        self.onDeletePerformanceTapped = onDeletePerformanceTapped
        self.onPerformanceTapped = onPerformanceTapped
        self.onScheduleDivisionTapped = onScheduleDivisionTapped
    }

    var body: some View {
        ScheduleStageTimelinePage(
            stage: stage,
            performances: performances,
            timeRange: timeRange,
            eventTimePresentation: eventTimePresentation,
            userScheduleOverlay: userScheduleOverlay,
            emptyTitle: emptyTitle,
            otherScheduleDivisions: otherScheduleDivisions,
            showsAuthoringControls: showsAuthoringControls,
            onUserScheduleMembershipTapped: onUserScheduleMembershipTapped,
            onNewUserScheduleTapped: onNewUserScheduleTapped,
            onEditPerformanceTapped: onEditPerformanceTapped,
            onDeletePerformanceTapped: onDeletePerformanceTapped,
            onPerformanceTapped: onPerformanceTapped,
            onScheduleDivisionTapped: onScheduleDivisionTapped
        )
        .frame(height: pageHeight)
        .environment(\.scheduleHeight, pageHeight)
        .environment(\.scheduleTimeRange, timeRange)
        .environment(\.shouldShowTimeIndicator, true)
    }
}

struct ScheduleStageTimelinePage: View {
    @Environment(\.timeZone) var deviceTimeZone
    let stage: OMERecord.Stage
    let performances: [OMERecord.Performance]
    let timeRange: DateInterval
    let eventTimePresentation: EventTimePresentation
    let userScheduleOverlay: UserScheduleOverlay
    let emptyTitle: String
    let otherScheduleDivisions: [ScheduleViewer.ScheduleDivision]
    let showsAuthoringControls: Bool
    let onUserScheduleMembershipTapped: (
        OMERecord.ID<OMERecord.Performance>,
        UserSchedule.ID
    ) -> Void
    let onNewUserScheduleTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onEditPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onDeletePerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onPerformanceTapped: (OMERecord.ID<OMERecord.Performance>) -> Void
    let onScheduleDivisionTapped: (ScheduleViewer.ScheduleDivision) -> Void

    var body: some View {
        SchedulePageView(
            timelineCards,
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
                performance: card.item.performance,
                stage: stage,
                timeRangeText: eventTimePresentation.performanceRowTimeRange(
                    for: card.item.performance
                ),
                userScheduleOverlay: userScheduleOverlay,
                showsAuthoringControls: showsAuthoringControls,
                userScheduleMembershipAction: { scheduleID in
                    onUserScheduleMembershipTapped(card.item.id, scheduleID)
                },
                newUserScheduleAction: {
                    onNewUserScheduleTapped(card.item.id)
                },
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
            emptyContent
        }
    }

    @ViewBuilder
    var emptyContent: some View {
        ScheduleEmptyView(
            title: emptyTitle,
            otherScheduleDivisions: otherScheduleDivisions,
            onScheduleDivisionTapped: onScheduleDivisionTapped
        )
        .padding()
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
