import OpenMusicEventLexicon
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
            eventID: Event.ID,
            scheduleDivision: ScheduleList.ScheduleDivision
        ) {
            self.eventID = eventID
            self._timeZone = FetchOne(
                Event.timeZoneQuery(eventID: eventID)
            )
            self.scheduleDivision = scheduleDivision
            let scheduleViewerState = ScheduleListState(
                eventID: eventID,
                scheduleDivision: scheduleDivision
            )
            self.scheduleViewerState = scheduleViewerState
            self.scheduleViewerStateBaseline = scheduleViewerState
            self._persistedScheduleViewerState = FetchOne(
                wrappedValue: nil,
                ScheduleListState.none
            )
            _performanceRows = FetchAll(
                PerformanceRow.all(eventID: eventID)
            )
            _schedules = FetchAll(
                ScheduleList.schedulesQuery(eventID: eventID)
            )
            _stages = FetchAll(
                ScheduleList.stagesQuery(eventID: eventID)
            )
            _event = FetchOne(Event.where { $0.id.eq(eventID) })
            _programs = FetchAll(Program.where { $0.event.eq(eventID) })
        }

        public let eventID: Event.ID
        @FetchOne public var timeZone: TimeZone?
        var eventTimePresentation: EventTimePresentation? {
            timeZone.map { EventTimePresentation(timeZone: $0) }
        }
        public let scheduleDivision: ScheduleList.ScheduleDivision
        public var scheduleViewerState: ScheduleListState
        var scheduleViewerStateBaseline: ScheduleListState
        @FetchOne var persistedScheduleViewerState: ScheduleListState?

        @FetchAll public var performanceRows: [PerformanceRow]
        @FetchAll public var schedules: [Schedule]
        @FetchAll public var stages: [EventPlace]
        @FetchOne public var event: Event?
        @FetchAll public var programs: [Program]

        public var selectedStageID: EventPlace.ID? {
            get {
                ScheduleList.normalizedSelectedStageID(
                    selectedStageID: scheduleViewerState.selectedStageID,
                    stages: visibleStages
                )
            }
            set {
                let selectedStageID = ScheduleList.normalizedSelectedStageID(
                    selectedStageID: newValue,
                    stages: visibleStages
                )
                scheduleViewerState.selectedStageID = selectedStageID
            }
        }

        mutating func normalizeSelectedStageID() {
            scheduleViewerState.selectedStageID = ScheduleList.normalizedSelectedStageID(
                selectedStageID: scheduleViewerState.selectedStageID,
                stages: visibleStages
            )
        }

        public func visiblePerformances(
            selectedScheduleID: Schedule.ID?
        ) -> [ProgramItem] {
            visiblePerformanceRows(selectedScheduleID: selectedScheduleID)
                .map(\.performance)
        }

        public func visiblePerformanceRows(
            selectedScheduleID: Schedule.ID?
        ) -> [PerformanceRow] {
            ScheduleList.visiblePerformances(
                performanceRows: performanceRows,
                scheduleID: resolvedSelectedScheduleID(selectedScheduleID),
                division: scheduleDivision
            )
        }

        public func visiblePerformancesForSelectedStage(
            selectedScheduleID: Schedule.ID?
        ) -> [ProgramItem] {
            guard let resolvedSelectedStageID else { return [] }
            return visiblePerformances(selectedScheduleID: selectedScheduleID)
                .filter { $0.eventPlace == resolvedSelectedStageID }
        }

        public func resolvedSelectedScheduleID(
            _ selectedScheduleID: Schedule.ID?
        ) -> Schedule.ID? {
            ScheduleList.resolvedSelectedScheduleID(
                selectedScheduleID,
                schedules: ScheduleList.orderedSchedules(event: event, schedules: schedules)
            )
        }

        public var resolvedSelectedStageID: EventPlace.ID? {
            ScheduleList.resolvedSelectedStageID(
                selectedStageID: scheduleViewerState.selectedStageID,
                stages: visibleStages
            )
        }

        public var selectedStage: EventPlace? {
            guard let resolvedSelectedStageID else { return nil }
            return visibleStages.first { $0.id == resolvedSelectedStageID }
        }

        public var visibleStages: [EventPlace] {
            ScheduleList.visibleStages(
                stages: stages,
                division: scheduleDivision
            )
        }
    }

    public enum Action {
        case deletePerformanceButtonTapped(ProgramItem.ID)
        case editPerformanceButtonTapped(ProgramItem.ID)
        case newUserScheduleButtonTapped(ProgramItem.ID)
        case scheduleDivisionButtonTapped(ScheduleList.ScheduleDivision)
        case userScheduleMembershipButtonTapped(
            ProgramItem.ID,
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
                    try ScheduleListState.persistChanges(
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
                    ScheduleListState.rows(
                        eventID: eventID,
                        scheduleDivision: scheduleDivision
                    )
                )
                if persistedState.wrappedValue == nil {
                    let defaultState = try await database.read { db in
                        try ScheduleListStateRequest(
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
    @Binding var selectedScheduleID: Schedule.ID?
    let userScheduleOverlay: UserScheduleOverlay
    let showsAuthoringControls: Bool
    let performanceButtonTapped: (ProgramItem.ID) -> Void

    @Environment(\.schedulePointsPerHour) var schedulePointsPerHour
    @Environment(\.scheduleTimeBuffer) var scheduleTimeBuffer
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    @Environment(\.eventTimePresentation) var eventTimePresentation

    public init(
        store: StoreOf<ScheduleSingleStageAtOnce>,
        selectedScheduleID: Binding<Schedule.ID?>,
        userScheduleOverlay: UserScheduleOverlay,
        showsAuthoringControls: Bool,
        performanceButtonTapped: @escaping (ProgramItem.ID) -> Void
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
                title: ScheduleList.emptyScheduleTitle(
                    scheduleDivision: store.scheduleDivision,
                    scheduleTitle: selectedScheduleTitle
                ),
                otherScheduleDivisions: otherScheduleDivisions,
                onScheduleDivisionTapped: { division in
                    store.send(.scheduleDivisionButtonTapped(division))
                }
            )
        } else if eventTimePresentation != nil {
            ScheduleStagePager(
                selectedStageID: $store.selectedStageID,
                stages: visibleStages,
                performances: visiblePerformances,
                timeRange: timeRange,
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

    var visiblePerformances: [ProgramItem] {
        store.state.visiblePerformances(selectedScheduleID: selectedScheduleID)
    }

    var visibleStages: [EventPlace] {
        store.visibleStages
    }

    var unavailableStageIDs: Set<EventPlace.ID> {
        ScheduleList.unavailableStageIDs(
            stages: visibleStages,
            performances: visiblePerformances
        )
    }

    var otherScheduleDivisions: [ScheduleList.ScheduleDivision] {
        ScheduleList.scheduleDivisions(event: store.event, programs: store.programs)
            .filter { $0 != store.scheduleDivision }
    }

    var selectedScheduleTitle: String {
        guard let scheduleID = store.state.resolvedSelectedScheduleID(selectedScheduleID),
              let schedule = store.schedules.first(where: { $0.id == scheduleID }),
              let timeZone = store.timeZone
        else { return "Select Schedule" }
        return ScheduleList.scheduleTitle(schedule, in: timeZone)
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

struct ScheduleEmptyActions: Sendable {
    var addStage: (@MainActor @Sendable () -> Void)?
    var addPerformance: (@MainActor @Sendable () -> Void)?
    var addSchedule: (@MainActor @Sendable () -> Void)?
}

enum ScheduleEmptyActionsKey: EnvironmentKey {
    static let defaultValue: ScheduleEmptyActions? = nil
}

extension EnvironmentValues {
    var scheduleEmptyActions: ScheduleEmptyActions? {
        get { self[ScheduleEmptyActionsKey.self] }
        set { self[ScheduleEmptyActionsKey.self] = newValue }
    }
}

struct ScheduleEmptyView: View {
    @Environment(\.scheduleEmptyActions) var authoringActions
    let title: String
    let otherScheduleDivisions: [ScheduleList.ScheduleDivision]
    let onScheduleDivisionTapped: (ScheduleList.ScheduleDivision) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ContentUnavailableView {
                Label(
                    title,
                    mappedSystemImage: "calendar.day.timeline.leading"
                )
            } description: {
                if let authoringActions {
                    if authoringActions.addStage != nil {
                        Text("Build your schedule by adding stages and performances. Add a schedule to organize them by day.")
                    } else {
                        Text("Add a performance to this stage, or add a schedule to organize performances by day.")
                    }
                    if authoringActions.addPerformance == nil {
                        Text("Choose a program below to add a performance.")
                    }
                }
            } actions: {
                if let authoringActions {
                    VStack(spacing: 12) {
                        if let addStage = authoringActions.addStage {
                            Button("Add Stage", action: addStage)
                                .accessibilityIdentifier("schedule.empty.add-stage")
                        }
                        if let addPerformance = authoringActions.addPerformance {
                            Button("Add Performance", action: addPerformance)
                                .accessibilityIdentifier("schedule.empty.add-performance")
                        }
                        if let addSchedule = authoringActions.addSchedule {
                            Button("Add Schedule", action: addSchedule)
                                .accessibilityIdentifier("schedule.empty.add-schedule")
                        }
                    }
                    .buttonStyle(.bordered)
                }
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
    @Binding var selectedStageID: EventPlace.ID?

    let stages: [EventPlace]
    let performances: [ProgramItem]
    let timeRange: DateInterval?
    let pageHeight: CGFloat?
    let userScheduleOverlay: UserScheduleOverlay
    let scheduleDivision: ScheduleList.ScheduleDivision
    let scheduleTitle: String
    let otherScheduleDivisions: [ScheduleList.ScheduleDivision]
    let showsAuthoringControls: Bool
    let onUserScheduleMembershipTapped: (
        ProgramItem.ID,
        UserSchedule.ID
    ) -> Void
    let onNewUserScheduleTapped: (ProgramItem.ID) -> Void
    let onEditPerformanceTapped: (ProgramItem.ID) -> Void
    let onDeletePerformanceTapped: (ProgramItem.ID) -> Void
    let onPerformanceTapped: (ProgramItem.ID) -> Void
    let onScheduleDivisionTapped: (ScheduleList.ScheduleDivision) -> Void

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
                            title: ScheduleList.emptyStageTitle(
                                scheduleDivision: scheduleDivision,
                                scheduleTitle: scheduleTitle,
                                stage: stage
                            ),
                            otherScheduleDivisions: otherScheduleDivisions,
                            onScheduleDivisionTapped: onScheduleDivisionTapped
                        )
                        .id(stage.id)
                        .tag(Optional(stage.id))
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
        _ stage: EventPlace,
        width: CGFloat,
        timeRange: DateInterval,
        pageHeight: CGFloat
    ) -> some View {
        ScheduleFixedStageTimeline(
            stage: stage,
            performances: performances(for: stage),
            timeRange: timeRange,
            pageHeight: pageHeight,
            userScheduleOverlay: userScheduleOverlay,
            emptyTitle: ScheduleList.emptyStageTitle(
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
        .id(stage.id)
        .tag(Optional(stage.id))
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

    func performances(for stage: EventPlace) -> [ProgramItem] {
        performances.filter { $0.eventPlace == stage.id }
    }
}

struct ScheduleFixedStageTimeline: View {
    let stage: EventPlace
    let performances: [ProgramItem]
    let timeRange: DateInterval
    let pageHeight: CGFloat
    let userScheduleOverlay: UserScheduleOverlay
    let emptyTitle: String
    let otherScheduleDivisions: [ScheduleList.ScheduleDivision]
    let showsAuthoringControls: Bool
    let onUserScheduleMembershipTapped: (
        ProgramItem.ID,
        UserSchedule.ID
    ) -> Void
    let onNewUserScheduleTapped: (ProgramItem.ID) -> Void
    let onEditPerformanceTapped: (ProgramItem.ID) -> Void
    let onDeletePerformanceTapped: (ProgramItem.ID) -> Void
    let onPerformanceTapped: (ProgramItem.ID) -> Void
    let onScheduleDivisionTapped: (ScheduleList.ScheduleDivision) -> Void

    init(
        stage: EventPlace,
        performances: [ProgramItem],
        timeRange: DateInterval,
        pageHeight: CGFloat,
        userScheduleOverlay: UserScheduleOverlay,
        emptyTitle: String,
        otherScheduleDivisions: [ScheduleList.ScheduleDivision] = [],
        showsAuthoringControls: Bool,
        onUserScheduleMembershipTapped: @escaping (
            ProgramItem.ID,
            UserSchedule.ID
        ) -> Void,
        onNewUserScheduleTapped: @escaping (ProgramItem.ID) -> Void,
        onEditPerformanceTapped: @escaping (ProgramItem.ID) -> Void,
        onDeletePerformanceTapped: @escaping (ProgramItem.ID) -> Void,
        onPerformanceTapped: @escaping (ProgramItem.ID) -> Void,
        onScheduleDivisionTapped: @escaping (ScheduleList.ScheduleDivision) -> Void = { _ in }
    ) {
        self.stage = stage
        self.performances = performances
        self.timeRange = timeRange
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
    @Environment(\.eventTimePresentation) var eventTimePresentation
    @Environment(\.timeZone) var deviceTimeZone
    let stage: EventPlace
    let performances: [ProgramItem]
    let timeRange: DateInterval
    let userScheduleOverlay: UserScheduleOverlay
    let emptyTitle: String
    let otherScheduleDivisions: [ScheduleList.ScheduleDivision]
    let showsAuthoringControls: Bool
    let onUserScheduleMembershipTapped: (
        ProgramItem.ID,
        UserSchedule.ID
    ) -> Void
    let onNewUserScheduleTapped: (ProgramItem.ID) -> Void
    let onEditPerformanceTapped: (ProgramItem.ID) -> Void
    let onDeletePerformanceTapped: (ProgramItem.ID) -> Void
    let onPerformanceTapped: (ProgramItem.ID) -> Void
    let onScheduleDivisionTapped: (ScheduleList.ScheduleDivision) -> Void

    var body: some View {
        if let eventTimePresentation {
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
                    timeRangeText: eventTimePresentation.programItemRowTimeRange(
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
        performances.compactMap(SchedulePerformanceTimelineCard.init).groupedToPreventOverlaps
    }

    static func timeRange(
        for performances: [ProgramItem],
        buffer: TimeInterval
    ) -> DateInterval? {
        guard
            let start = performances.compactMap(\.startDate).min(),
            let end = performances.compactMap(\.endDate).max()
        else { return nil }

        return DateInterval(
            start: start.addingTimeInterval(-buffer),
            end: end.addingTimeInterval(buffer)
        )
    }
}
