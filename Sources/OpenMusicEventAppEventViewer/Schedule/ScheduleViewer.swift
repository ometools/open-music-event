import BlueskyActorCache
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventEditors
import OpenMusicEventImages
import OpenMusicEventViewers
import ScheduleComponents
import Sharing
import SQLiteData
import SwiftUITabFeatures
import SwiftUI
import Tagged

struct EventTimePresentation: Equatable, Sendable {
    enum Disclosure: Equatable, Sendable {
        case never
        case whenDeviceClockDiffers(TimeZone)
    }

    let timeZone: TimeZone

    func performanceRowTimeRange(
        for performance: OMERecord.Performance,
        disclosure: Disclosure = .never
    ) -> String {
        formattedTimeRange(
            start: performance.startTime,
            end: performance.endTime,
            disclosure: disclosure
        )
    }

    func formattedTimeRange(
        start: Date,
        end: Date,
        disclosure: Disclosure = .never
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startMeridiem = calendar.component(.hour, from: start) < 12 ? "AM" : "PM"
        let endMeridiem = calendar.component(.hour, from: end) < 12 ? "AM" : "PM"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = startMeridiem == endMeridiem ? "h:mm" : "h:mm a"

        let endFormatter = DateFormatter()
        endFormatter.locale = Locale(identifier: "en_US_POSIX")
        endFormatter.timeZone = timeZone
        endFormatter.dateFormat = "h:mm a"

        let timeRange = "\(timeFormatter.string(from: start)) - \(endFormatter.string(from: end))"
            .lowercased()
        return timeRange + timeZoneSuffix(for: start, disclosure: disclosure)
    }

    func formattedTime(
        for date: Date,
        disclosure: Disclosure = .never
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date).lowercased()
            + timeZoneSuffix(for: date, disclosure: disclosure)
    }

    func hourLabel(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        switch calendar.component(.hour, from: date) {
        case 0:
            return "mdnt"
        case 12:
            return "noon"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "ha"
            return formatter.string(from: date)
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
        }
    }

    func currentTimeLabel(
        for date: Date,
        disclosure: Disclosure = .never
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mma"
        let time = formatter.string(from: date)
            .lowercased()
            .replacingOccurrences(of: "am", with: "a")
            .replacingOccurrences(of: "pm", with: "p")
        return time + timeZoneSuffix(for: date, disclosure: disclosure)
    }

    func daySegment(
        for date: Date,
        policy: DateTimeRangeResolutionPolicy = .default
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var displayDate = date
        let hour = calendar.component(.hour, from: date)
        let segment: String

        if hour < policy.rolloverHour {
            segment = "Night"
            displayDate = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        } else if hour < 12 {
            segment = "Morning"
        } else if hour < 17 {
            segment = "Afternoon"
        } else if hour < 20 {
            segment = "Evening"
        } else {
            segment = "Night"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE"
        return "\(formatter.string(from: displayDate)) \(segment)"
    }

    func timeZoneSuffix(
        for date: Date,
        disclosure: Disclosure
    ) -> String {
        guard case let .whenDeviceClockDiffers(deviceTimeZone) = disclosure,
              timeZone.secondsFromGMT(for: date) != deviceTimeZone.secondsFromGMT(for: date),
              let abbreviation = timeZone.abbreviation(for: date)
        else { return "" }
        return " (\(abbreviation.uppercased()))"
    }
}

extension OMERecord.Event {
    static func timeZoneQuery(
        eventID: OMERecord.Event.ID
    ) -> some PartialSelectStatement<TimeZone> {
        OMERecord.Event
            .where { $0.id.eq(eventID) }
            .select(\.timeZone)
    }
}

@Feature
public struct ScheduleViewer {
    public init() {}

    public typealias ScheduleDivision = OpenMusicEventViewers.ScheduleDivision
    public typealias ScheduleKind = ScheduleViewerState.ScheduleKind

    struct CurrentTimeDestination: Equatable, Sendable {
        let scheduleID: OMERecord.ID<OMERecord.Schedule>
        let performanceID: OMERecord.ID<OMERecord.Performance>
    }

    public struct State {
        public init(
            eventID: OMERecord.Event.ID,
            scheduleDivision: ScheduleDivision = .schedule
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
            self.eventViewerState = EventViewerState(id: eventID)
            self._persistedEventViewerState = FetchOne(
                wrappedValue: nil,
                EventViewerState.none
            )
            self.singleStageAtOnce = Spawn(
                ScheduleSingleStageAtOnce.State(
                    eventID: eventID,
                    scheduleDivision: scheduleDivision
                )
            )
            self.manyStagesAtOnce = Spawn(
                ScheduleManyStagesAtOnce.State(
                    eventID: eventID,
                    scheduleDivision: scheduleDivision
                )
            )
            self.performanceList = Spawn(
                SchedulePerformanceList.State(
                    eventID: eventID,
                    scheduleDivision: scheduleDivision
                )
            )
            _event = FetchOne(
                OMERecord.Event.where { $0.id.eq(eventID) }
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
            _reactions = FetchAll(
                PerformanceReaction.forEvent(eventID: eventID)
            )
            _reactionUsage = FetchAll(
                PerformanceReactionEmojiUsage.ranked
            )
            _userSchedules = FetchAll(
                UserSchedule.all(eventID: eventID)
            )
            _userSchedulePerformances = FetchAll(
                UserSchedule.Performance.all
            )
        }

        public let eventID: OMERecord.Event.ID
        @FetchOne public var timeZone: TimeZone?
        var eventTimePresentation: EventTimePresentation? {
            timeZone.map { EventTimePresentation(timeZone: $0) }
        }
        public let scheduleDivision: ScheduleDivision
        public var destination: Destination.State? = nil
        public var singleStageAtOnce: Spawn<ScheduleSingleStageAtOnce>
        public var manyStagesAtOnce: Spawn<ScheduleManyStagesAtOnce>
        public var performanceList: Spawn<SchedulePerformanceList>
        public var scheduleViewerState: ScheduleViewerState
        var scheduleViewerStateBaseline: ScheduleViewerState
        @FetchOne var persistedScheduleViewerState: ScheduleViewerState?
        public var eventViewerState: EventViewerState
        @FetchOne var persistedEventViewerState: EventViewerState?

        @FetchOne public var event: OMERecord.Event?
        public var scheduleKind: ScheduleKind {
            get { scheduleViewerState.scheduleKind }
            set {
                scheduleViewerState.scheduleKind = newValue
                scheduleViewerState.syncScheduleKindStorage()
            }
        }

        public var showStageNameLabels: Bool {
            get { scheduleViewerState.showStageNameLabels }
            set {
                scheduleViewerState.showStageNameLabels = newValue
            }
        }

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

        @FetchAll public var performanceRows: [PerformanceRow]
        @FetchAll public var schedules: [OMERecord.Schedule]
        @FetchAll public var stages: [OMERecord.Stage]
        @FetchAll public var reactions: [PerformanceReaction]
        @FetchAll public var reactionUsage: [PerformanceReactionEmojiUsage]
        @FetchAll public var userSchedules: [UserSchedule]
        @FetchAll public var userSchedulePerformances: [UserSchedule.Performance]

        public var userScheduleOverlay: UserScheduleOverlay {
            UserScheduleOverlay(
                schedules: userSchedules,
                memberships: userSchedulePerformances,
                selectedScheduleID: eventViewerState.selectedUserScheduleID
            )
        }

        public var performances: [OMERecord.Performance] {
            performanceRows.map(\.performance)
        }

        var usesSingletonSchedule: Bool {
            schedules.count == 1
                && schedules.first?.id.scheduleID == OMERecord.Schedule.singletonID
        }

        public func selectedSchedule(
            selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> OMERecord.Schedule? {
            guard let selectedScheduleID = resolvedSelectedScheduleID(selectedScheduleID) else {
                return nil
            }
            return schedules.first { $0.id.scheduleID == selectedScheduleID }
        }

        public func visiblePerformances(
            selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> [OMERecord.Performance] {
            visiblePerformanceRows(selectedScheduleID: selectedScheduleID)
                .map(\.performance)
        }

        func visiblePerformanceRows(
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
            guard let selectedStageID = resolvedSelectedStageID else { return [] }
            return visiblePerformances(selectedScheduleID: selectedScheduleID)
                .filter { $0.stageID == selectedStageID }
        }

        func currentTimeDestination(
            currentDate: Date?,
            selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?,
            buffer: TimeInterval
        ) -> CurrentTimeDestination? {
            ScheduleViewer.currentTimeDestination(
                currentDate: currentDate,
                selectedScheduleID: selectedScheduleID,
                schedules: schedules,
                performanceRows: performanceRows,
                stages: visibleStages,
                buffer: buffer
            )
        }

        func resolvedSelectedScheduleID(
            _ selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> OMERecord.ID<OMERecord.Schedule>? {
            if let selectedScheduleID,
               schedules.contains(where: { $0.id.scheduleID == selectedScheduleID }) {
                return selectedScheduleID
            }
            return schedules.first?.id.scheduleID
        }

        var resolvedSelectedStageID: OMERecord.ID<OMERecord.Stage>? {
            ScheduleViewer.resolvedSelectedStageID(
                selectedStageID: scheduleViewerState.selectedStageID,
                stages: visibleStages
            )
        }

        func selectedScheduleTitle(
            selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?
        ) -> String {
            guard let schedule = selectedSchedule(selectedScheduleID: selectedScheduleID),
                  let timeZone
            else { return "Select Schedule" }
            return ScheduleViewer.scheduleTitle(schedule, in: timeZone)
        }

        var selectedStage: OMERecord.Stage? {
            guard let resolvedSelectedStageID else { return nil }
            return visibleStages.first { $0.id.stageID == resolvedSelectedStageID }
        }

        var stagesByID: [OMERecord.ID<OMERecord.Stage>: OMERecord.Stage] {
            Dictionary(uniqueKeysWithValues: stages.map { ($0.id.stageID, $0) })
        }

        var visibleStages: [OMERecord.Stage] {
            ScheduleViewer.visibleStages(
                stages: stages,
                division: scheduleDivision
            )
        }
    }

    public enum Action {
        case addPerformanceButtonTapped(OMERecord.ID<OMERecord.Schedule>?)
        case addScheduleButtonTapped
        case addToNewUserScheduleButtonTapped(OMERecord.ID<OMERecord.Performance>)
        case destination(Destination.Action)
        case otherReactionButtonTapped(OMERecord.Performance.ID)
        case performanceButtonTapped(OMERecord.ID<OMERecord.Performance>)
        case reactionButtonTapped(OMERecord.Performance.ID, PerformanceReaction.Emoji)
        case scheduleKindButtonTapped(ScheduleKind)
        case schedulesButtonTapped
        case userScheduleButtonTapped(UserSchedule.ID?)
        case userScheduleMembershipButtonTapped(
            performanceID: OMERecord.ID<OMERecord.Performance>,
            scheduleID: UserSchedule.ID
        )
    }

    @Feature
    public enum Destination {
        case deletePerformanceConfirmation(DeletePerformanceConfirmation)
        case performanceDetail(Spawn<PerformanceDetail>)
        case reactionEntry(PerformanceReactionEntry)
        case userScheduleForm(Spawn<UserScheduleForm>)
        case userSchedulesList(Spawn<UserSchedulesList>)
    }

    @Feature
    public struct DeletePerformanceConfirmation: Prompt {
        public struct State: Identifiable {
            public init(performanceID: OMERecord.ID<OMERecord.Performance>) {
                self.performanceID = performanceID
            }

            public var performanceID: OMERecord.ID<OMERecord.Performance>
            public var id: OMERecord.ID<OMERecord.Performance> { performanceID }
        }

        public enum Action {
            case deleteButtonTapped(OMERecord.ID<OMERecord.Performance>)
        }
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now
    @Dependency(\.getSelectedOAuthSessionID) var getSelectedOAuthSessionID
    @Dependency(\.uuid) var uuid

    static func eventPerformancesQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Performance> {
        OMERecord.Performance
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { ($0.startTime, $0.title.collate(.nocase)) }
    }

    static func performancesQuery(
        eventID: OMERecord.Event.ID,
        scheduleID: OMERecord.ID<OMERecord.Schedule>
    ) -> some SelectStatementOf<OMERecord.Performance> {
        OMERecord.Performance
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.scheduleID.eq(scheduleID) }
            .order { ($0.startTime, $0.title.collate(.nocase)) }
    }

    static func schedulesQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Schedule> {
        OMERecord.Schedule
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { ($0.date, $0.startsAt.asc(nulls: .last), $0.customTitle.asc(nulls: .last)) }
    }

    static func stagesQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Stage> {
        OMERecord.Stage
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { ($0.sortIndex.asc(nulls: .last), $0.name.collate(.nocase)) }
    }

    static func scheduleTitle(
        _ schedule: OMERecord.Schedule,
        in timeZone: TimeZone
    ) -> String {
        if let customTitle = schedule.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customTitle.isEmpty {
            return customTitle
        }
        return schedule.date.formatted(dateFormat: "EEEE", in: timeZone)
    }

    static func emptyStageTitle(
        scheduleDivision: ScheduleDivision,
        scheduleTitle: String,
        stage: OMERecord.Stage
    ) -> String {
        "\(emptyScheduleTitle(scheduleDivision: scheduleDivision, scheduleTitle: scheduleTitle)) at \(stage.name)"
    }

    static func emptyScheduleTitle(
        scheduleDivision: ScheduleDivision,
        scheduleTitle: String
    ) -> String {
        "No \(scheduleDivision.title) on \(scheduleTitle)"
    }

    static func resolvedSelectedStageID(
        selectedStageID: OMERecord.ID<OMERecord.Stage>?,
        stages: [OMERecord.Stage]
    ) -> OMERecord.ID<OMERecord.Stage>? {
        if let selectedStageID,
           stages.contains(where: { $0.id.stageID == selectedStageID }) {
            return selectedStageID
        }
        return stages.first?.id.stageID
    }

    static func normalizedSelectedStageID(
        selectedStageID: OMERecord.ID<OMERecord.Stage>?,
        stages: [OMERecord.Stage]
    ) -> OMERecord.ID<OMERecord.Stage>? {
        guard !stages.isEmpty else { return selectedStageID }
        return resolvedSelectedStageID(
            selectedStageID: selectedStageID,
            stages: stages
        )
    }

    static func scheduleDivisions(stages: [OMERecord.Stage]) -> [ScheduleDivision] {
        guard !stages.isEmpty else { return [] }

        var divisions: [ScheduleDivision] = [.schedule]
        var seenCategories = Set<OMERecord.Stage.Category>()
        for stage in stages {
            guard let category = stage.category, seenCategories.insert(category).inserted else {
                continue
            }
            divisions.append(ScheduleDivision(category: category))
        }
        return divisions
    }

    static func visiblePerformances(
        performanceRows: [PerformanceRow],
        scheduleID: OMERecord.ID<OMERecord.Schedule>?,
        stages: [OMERecord.Stage]
    ) -> [PerformanceRow] {
        guard let scheduleID else { return [] }
        let visibleStageIDs = Set(stages.map(\.id.stageID))
        return performanceRows.filter {
            $0.performance.scheduleID == scheduleID
                && visibleStageIDs.contains($0.performance.stageID)
        }
    }

    static func currentTimeDestination(
        currentDate: Date?,
        selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?,
        schedules: [OMERecord.Schedule],
        performanceRows: [PerformanceRow],
        stages: [OMERecord.Stage],
        buffer: TimeInterval
    ) -> CurrentTimeDestination? {
        guard let currentDate else { return nil }

        let candidates = schedules.compactMap { schedule -> CurrentTimeDestination? in
            let rows = visiblePerformances(
                performanceRows: performanceRows,
                scheduleID: schedule.id.scheduleID,
                stages: stages
            )
            guard
                let firstStart = rows.map(\.performance.startTime).min(),
                let lastEnd = rows.map(\.performance.endTime).max()
            else { return nil }

            let renderedRange = DateInterval(
                start: firstStart.addingTimeInterval(-buffer),
                end: lastEnd.addingTimeInterval(buffer)
            )
            guard renderedRange.contains(currentDate) else { return nil }

            let row = rows.first {
                $0.performance.startTime <= currentDate
                    && currentDate < $0.performance.endTime
            } ?? rows.first {
                currentDate < $0.performance.startTime
            } ?? rows.last
            guard let row else { return nil }

            return CurrentTimeDestination(
                scheduleID: schedule.id.scheduleID,
                performanceID: row.performanceID
            )
        }

        if let selectedScheduleID,
           let selectedDestination = candidates.first(where: {
               $0.scheduleID == selectedScheduleID
           }) {
            return selectedDestination
        }
        return candidates.first
    }

    static func visibleStages(
        stages: [OMERecord.Stage],
        division: ScheduleDivision
    ) -> [OMERecord.Stage] {
        stages.filter { $0.category == division.category }
    }

    static func orderedStages(
        _ stages: [OMERecord.Stage],
        performances: [OMERecord.Performance]
    ) -> [OMERecord.Stage] {
        let stageIDsWithPerformances = Set(performances.map(\.stageID))
        return stages.filter { stageIDsWithPerformances.contains($0.id.stageID) }
            + stages.filter { !stageIDsWithPerformances.contains($0.id.stageID) }
    }

    static func unavailableStageIDs(
        stages: [OMERecord.Stage],
        performances: [OMERecord.Performance]
    ) -> Set<OMERecord.ID<OMERecord.Stage>> {
        let stageIDsWithPerformances = Set(performances.map(\.stageID))
        return Set(stages.map(\.id.stageID)).subtracting(stageIDsWithPerformances)
    }

    static func canAddPerformance(
        selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?,
        schedules: [OMERecord.Schedule],
        stages: [OMERecord.Stage],
        event: OMERecord.Event?
    ) -> Bool {
        guard !stages.isEmpty else { return false }
        if Self.resolvedSelectedScheduleID(
            selectedScheduleID,
            schedules: schedules
        ) != nil {
            return true
        }
        return schedules.isEmpty && (event == nil || event?.startDate != nil)
    }

    static func resolvedSelectedScheduleID(
        _ selectedScheduleID: OMERecord.ID<OMERecord.Schedule>?,
        schedules: [OMERecord.Schedule]
    ) -> OMERecord.ID<OMERecord.Schedule>? {
        if let selectedScheduleID,
           schedules.contains(where: { $0.id.scheduleID == selectedScheduleID }) {
            return selectedScheduleID
        }
        return schedules.first?.id.scheduleID
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case let .addPerformanceButtonTapped(selectedScheduleID):
                guard let selectedStageID = state.resolvedSelectedStageID,
                      Self.canAddPerformance(
                        selectedScheduleID: selectedScheduleID,
                        schedules: state.schedules,
                        stages: state.stages,
                        event: state.event
                      )
                else { return }
                let eventID = state.eventID
                let scheduleID = state.resolvedSelectedScheduleID(selectedScheduleID)
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .addPerformance(
                            eventID: eventID,
                            scheduleID: scheduleID,
                            stageID: selectedStageID
                        )
                    )
                    await task?.value
                }

            case .addScheduleButtonTapped:
                let eventID = state.eventID
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .addSchedule(eventID)
                    )
                    await task?.value
                }

            case let .addToNewUserScheduleButtonTapped(performanceID):
                guard state.performanceRows.contains(where: { $0.performanceID == performanceID }) else {
                    return
                }
                state.destination = .userScheduleForm(
                    Spawn(
                        UserScheduleForm.State(
                            eventID: state.eventID,
                            performanceID: performanceID
                        )
                    )
                )

            case let .destination(.deletePerformanceConfirmation(.deleteButtonTapped(performanceID))):
                let eventID = state.eventID
                store.addTask {
                    do {
                        try await Self.deletePerformance(
                            performanceID: performanceID,
                            eventID: eventID,
                            database: database
                        )
                    } catch {
                        reportIssue(error)
                    }
                }

            case .destination:
                break

            case let .otherReactionButtonTapped(performanceID):
                state.destination = .reactionEntry(
                    PerformanceReactionEntry.State(performanceID: performanceID)
                )

            case let .performanceButtonTapped(performanceID):
                store.withDependencies {
                    state.destination = .performanceDetail(
                        Spawn(
                            PerformanceDetail.State(
                                performanceID: performanceID,
                                eventID: state.eventID
                            )
                        )
                    )
                }

            case let .reactionButtonTapped(performanceID, emoji):
                let id = uuid()
                let date = now
                let userDID = getSelectedOAuthSessionID()?.rawValue
                store.addTask {
                    do {
                        try await database.write { db in
                            try PerformanceReaction.toggle(
                                performanceID: performanceID,
                                emoji: emoji,
                                id: id,
                                date: date,
                                userDID: userDID,
                                in: db
                            )
                        }
                    } catch {
                        reportIssue(error)
                    }
                }

            case let .scheduleKindButtonTapped(scheduleKind):
                state.scheduleKind = scheduleKind

            case .schedulesButtonTapped:
                state.destination = .userSchedulesList(
                    Spawn(UserSchedulesList.State(eventID: state.eventID))
                )

            case let .userScheduleButtonTapped(scheduleID):
                guard scheduleID == nil
                    || state.userSchedules.contains(where: { $0.id == scheduleID })
                else { return }
                state.eventViewerState.selectedUserScheduleID = scheduleID

            case let .userScheduleMembershipButtonTapped(performanceID, scheduleID):
                guard state.performanceRows.contains(where: { $0.performanceID == performanceID }),
                      state.userSchedules.contains(where: { $0.id == scheduleID })
                else { return }
                let membership = UserSchedule.Performance(
                    scheduleID: scheduleID,
                    performanceID: performanceID
                )
                let isMember = state.userSchedulePerformances.contains { $0.id == membership.id }
                store.addTask {
                    do {
                        try await database.write { db in
                            if isMember {
                                try UserSchedule.Performance
                                    .find(membership.id)
                                    .delete()
                                    .execute(db)
                            } else {
                                try UserSchedule.Performance.insert { membership }.execute(db)
                            }
                        }
                    } catch {
                        reportIssue(error)
                    }
                }
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .spawn(\.singleStageAtOnce) {
            ScheduleSingleStageAtOnce()
        }
        .spawn(\.manyStagesAtOnce) {
            ScheduleManyStagesAtOnce()
        }
        .spawn(\.performanceList) {
            SchedulePerformanceList()
        }
        .onEvent(SchedulePerformanceDeleteRequested.self) { performanceID, state in
            state.destination = .deletePerformanceConfirmation(
                DeletePerformanceConfirmation.State(performanceID: performanceID)
            )
        }
        .onEvent(SchedulePerformanceEditRequested.self) { performanceID, state in
            guard state.performanceRows.contains(where: { $0.performanceID == performanceID }) else {
                return
            }
            let eventID = state.eventID
            store.addTask {
                let task = try store.post(
                    key: EventEditingRequested.self,
                    value: .editPerformance(
                        eventID: eventID,
                        performanceID: performanceID
                    )
                )
                await task?.value
            }
        }
        .onEvent(SchedulePerformanceUserScheduleMembershipRequested.self) { request, state in
            guard state.performanceRows.contains(where: { $0.performanceID == request.performanceID }),
                  state.userSchedules.contains(where: { $0.id == request.scheduleID })
            else { return }
            let membership = UserSchedule.Performance(
                scheduleID: request.scheduleID,
                performanceID: request.performanceID
            )
            let isMember = state.userSchedulePerformances.contains { $0.id == membership.id }
            store.addTask {
                do {
                    try await database.write { db in
                        if isMember {
                            try UserSchedule.Performance.find(membership.id).delete().execute(db)
                        } else {
                            try UserSchedule.Performance.insert { membership }.execute(db)
                        }
                    }
                } catch {
                    reportIssue(error)
                }
            }
        }
        .onEvent(SchedulePerformanceNewUserScheduleRequested.self) { performanceID, state in
            let performanceIDs = state.performanceRows.map(\.performanceID)
            guard performanceIDs.contains(performanceID) else {
                return
            }
            state.destination = .userScheduleForm(
                Spawn(
                    UserScheduleForm.State(
                        eventID: state.eventID,
                        performanceID: performanceID
                    )
                )
            )
        }
        .onChange(of: store.persistedScheduleViewerState) { _, persistedState, state in
            guard var persistedState else { return }
            persistedState.migrateLegacyScheduleKind()
            state.scheduleViewerStateBaseline = persistedState
            guard persistedState != state.scheduleViewerState else { return }
            state.scheduleViewerState = persistedState
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
        .onChange(of: store.persistedEventViewerState) { _, persistedState, state in
            guard let persistedState else { return }
            guard persistedState != state.eventViewerState else { return }
            state.eventViewerState = persistedState
        }
        .onChange(of: store.eventViewerState) { oldViewerState, viewerState, state in
            guard state.persistedEventViewerState != viewerState else { return }
            do {
                try database.write { db in
                    try EventViewerState.persistChanges(
                        from: oldViewerState,
                        to: viewerState,
                        in: db
                    )
                }
            } catch {
                reportIssue(error)
            }
        }
        .onChange(of: store.userSchedules, initial: true) { _, schedules, state in
            guard let selectedScheduleID = state.eventViewerState.selectedUserScheduleID,
                  !schedules.contains(where: { $0.id == selectedScheduleID })
            else { return }
            state.eventViewerState.selectedUserScheduleID = nil
        }
        .onMount { state in
            let eventID = state.eventID
            let scheduleDivision = state.scheduleDivision
            let initialScheduleViewerState = state.scheduleViewerState
            let persistedScheduleViewerState = state.$persistedScheduleViewerState
            let persistedEventViewerState = state.$persistedEventViewerState
            store.addTask {
                let subscription = try await persistedScheduleViewerState.load(
                    ScheduleViewerState.rows(
                        eventID: eventID,
                        scheduleDivision: scheduleDivision
                    )
                )
                if persistedScheduleViewerState.wrappedValue == nil {
                    let defaultState = try await database.read { db in
                        try ScheduleViewerStateRequest(
                            eventID: eventID,
                            scheduleDivision: scheduleDivision
                        )
                        .fetch(db)
                    }
                    try store.modify {
                        guard $0.persistedScheduleViewerState == nil,
                              $0.scheduleViewerState == initialScheduleViewerState
                        else { return }
                        $0.scheduleViewerStateBaseline = defaultState
                        $0.scheduleViewerState = defaultState
                    }
                }
                try await subscription.task
            }
            store.addTask {
                try await persistedEventViewerState.load(
                    EventViewerState.where { $0.id.eq(eventID) }
                )
                .task
            }

            guard !state.eventViewerState.didInitializeUserSchedules else { return }
            let scheduleID = uuid()
            let userDID = getSelectedOAuthSessionID()?.rawValue
            store.addTask {
                do {
                    try await database.write { db in
                        var viewerState = try EventViewerStateRequest(eventID: eventID).fetch(db)
                        guard !viewerState.didInitializeUserSchedules else { return }

                        try UserSchedule.insert {
                            UserSchedule(
                                id: scheduleID,
                                eventID: eventID,
                                title: "My Schedule",
                                userDID: userDID
                            )
                        }
                        .execute(db)
                        viewerState.didInitializeUserSchedules = true
                        try EventViewerState.upsert { viewerState }.execute(db)
                    }
                    try store.modify {
                        $0.eventViewerState.didInitializeUserSchedules = true
                    }
                } catch is CancellationError {
                    return
                } catch {
                    reportIssue(error)
                }
            }
        }
    }


    private static func deletePerformance(
        performanceID: OMERecord.ID<OMERecord.Performance>,
        eventID: OMERecord.Event.ID,
        database: any DatabaseWriter
    ) async throws {
        try await database.write { db in
            let id = OMERecord.Performance.ID(
                organizerID: eventID.organizerID,
                eventID: eventID.eventID,
                performanceID: performanceID
            )
            guard try OMERecord.Performance.find(id).fetchOne(db) != nil else {
                throw DeletePerformanceError()
            }
            try OMERecord.Performance
                .find(id)
                .delete()
                .execute(db)
        }
    }
}

private struct DeletePerformanceError: Error {}

extension OMERecord.Performance {
    var displayDescription: String? {
        let description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return description?.isEmpty == false ? description : nil
    }

}

private extension LocalDate {
    func formatted(dateFormat: String, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        formatter.timeZone = timeZone
        return formatter.string(from: atStartOfDay(in: timeZone))
    }
}

extension OMEColor {
    var swiftUIColor: Color {
        Color(
            red: Double((rawValue >> 16) & 0xFF) / 255.0,
            green: Double((rawValue >> 8) & 0xFF) / 255.0,
            blue: Double(rawValue & 0xFF) / 255.0
        )
    }
}

private extension String {
    var scheduleDivisionTitle: String {
        split { $0 == "-" || $0 == "_" || $0 == " " }
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
