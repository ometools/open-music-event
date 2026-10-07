import OpenMusicEventLexicon
import Bluesky
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
    let calendar: Calendar
    let timeWithoutMeridiemStyle: Date.FormatStyle
    let timeStyle: Date.FormatStyle
    let hourStyle: Date.FormatStyle
    let weekdayStyle: Date.FormatStyle
    let shortTimeZoneStyle: Date.FormatStyle
    let longTimeZoneStyle: Date.FormatStyle

    init(timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let baseStyle = Date.FormatStyle(
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: calendar,
            timeZone: timeZone
        )

        self.timeZone = timeZone
        self.calendar = calendar
        self.timeWithoutMeridiemStyle = baseStyle
            .hour(.defaultDigits(amPM: .omitted))
            .minute(.twoDigits)
        self.timeStyle = baseStyle
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute(.twoDigits)
        self.hourStyle = baseStyle
            .hour(.defaultDigits(amPM: .abbreviated))
        self.weekdayStyle = baseStyle
            .weekday(.wide)
        self.shortTimeZoneStyle = baseStyle
            .timeZone(.specificName(.short))
        self.longTimeZoneStyle = baseStyle
            .timeZone(.specificName(.long))
    }

    func programItemRowTimeRange(
        for item: ProgramItem,
        disclosure: Disclosure = .never
    ) -> String {
        guard let start = item.startDate else { return "Time TBA" }
        guard let end = item.endDate else {
            return formattedTime(for: start, disclosure: disclosure)
        }
        return formattedTimeRange(start: start, end: end, disclosure: disclosure)
    }

    func formattedTimeRange(
        start: Date,
        end: Date,
        disclosure: Disclosure = .never
    ) -> String {
        let startMeridiem = calendar.component(.hour, from: start) < 12 ? "AM" : "PM"
        let endMeridiem = calendar.component(.hour, from: end) < 12 ? "AM" : "PM"

        let startStyle = startMeridiem == endMeridiem
            ? timeWithoutMeridiemStyle
            : timeStyle
        let timeRange = "\(normalizedTime(start, style: startStyle)) - \(normalizedTime(end, style: timeStyle))"
        return timeRange + timeZoneSuffix(for: start, disclosure: disclosure)
    }

    func formattedTime(
        for date: Date,
        disclosure: Disclosure = .never
    ) -> String {
        return normalizedTime(date, style: timeStyle)
            + timeZoneSuffix(for: date, disclosure: disclosure)
    }

    func hourLabel(for date: Date) -> String {
        switch calendar.component(.hour, from: date) {
        case 0:
            return "mdnt"
        case 12:
            return "noon"
        default:
            return normalizedTime(date, style: hourStyle)
                .replacingOccurrences(of: " ", with: "")
        }
    }

    func currentTimeLabel(
        for date: Date,
        disclosure: Disclosure = .never
    ) -> String {
        let time = normalizedTime(date, style: timeStyle)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "am", with: "a")
            .replacingOccurrences(of: "pm", with: "p")
        return time + timeZoneSuffix(for: date, disclosure: disclosure)
    }

    func daySegment(
        for date: Date,
        policy: DateTimeRangeResolutionPolicy = .default
    ) -> String {
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

        return "\(displayDate.formatted(weekdayStyle)) \(segment)"
    }

    func timeZoneSuffix(
        for date: Date,
        disclosure: Disclosure
    ) -> String {
        guard case let .whenDeviceClockDiffers(deviceTimeZone) = disclosure,
              timeZone.secondsFromGMT(for: date) != deviceTimeZone.secondsFromGMT(for: date),
              let abbreviation = timeZoneAbbreviation(for: date)
        else { return "" }
        return " (\(abbreviation))"
    }

    func timeZoneAbbreviation(for date: Date) -> String? {
        let shortName = date.formatted(shortTimeZoneStyle).uppercased()
        guard shortName.contains(where: { !$0.isLetter }) else {
            return shortName.isEmpty ? nil : shortName
        }

        let initials = date.formatted(longTimeZoneStyle)
            .split(whereSeparator: { !$0.isLetter })
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
        return initials.count > 1 ? initials : nil
    }

    func normalizedTime(_ date: Date, style: Date.FormatStyle) -> String {
        let time = date.formatted(style)
            .lowercased()
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        return time.hasPrefix("0") ? String(time.dropFirst()) : time
    }
}

enum EventTimePresentationEnvironmentKey: EnvironmentKey {
    static let defaultValue: EventTimePresentation? = nil
}

extension EnvironmentValues {
    var eventTimePresentation: EventTimePresentation? {
        get { self[EventTimePresentationEnvironmentKey.self] }
        set { self[EventTimePresentationEnvironmentKey.self] = newValue }
    }
}

extension Event {
    static func timeZoneQuery(
        eventID: Event.ID
    ) -> some PartialSelectStatement<TimeZone> {
        Event
            .where { $0.id.eq(eventID) }
            .select(\.timeZone)
    }
}

@Feature
public struct ScheduleList {
    public init() {}

    public typealias ScheduleDivision = OpenMusicEventViewers.ScheduleDivision
    public typealias ScheduleKind = ScheduleListState.ScheduleKind

    struct CurrentTimeDestination: Equatable, Sendable {
        let scheduleID: Schedule.ID
        let performanceID: ProgramItem.ID
    }

    public struct State {
        public init(
            eventID: Event.ID,
            scheduleDivision: ScheduleDivision = .schedule
        ) {
            self.eventID = eventID
            AttendeePerformance.mark("schedule-query-timeZone.begin", event: eventID.description)
            self._timeZone = FetchOne(
                Event.timeZoneQuery(eventID: eventID)
            )
            AttendeePerformance.mark("schedule-query-timeZone.end", event: eventID.description)
            self.scheduleDivision = scheduleDivision
            let scheduleViewerState = ScheduleListState(
                eventID: eventID,
                scheduleDivision: scheduleDivision
            )
            self.scheduleViewerState = scheduleViewerState
            self.scheduleViewerStateBaseline = scheduleViewerState
            AttendeePerformance.mark("schedule-query-persistedScheduleViewerState.begin", event: eventID.description)
            self._persistedScheduleViewerState = FetchOne(
                wrappedValue: nil,
                ScheduleListState.none
            )
            AttendeePerformance.mark("schedule-query-persistedScheduleViewerState.end", event: eventID.description)
            self.eventViewerState = EventDetailState(id: eventID)
            AttendeePerformance.mark("schedule-query-persistedEventViewerState.begin", event: eventID.description)
            self._persistedEventViewerState = FetchOne(
                wrappedValue: nil,
                EventDetailState.none
            )
            AttendeePerformance.mark("schedule-query-persistedEventViewerState.end", event: eventID.description)
            AttendeePerformance.mark("schedule-child-singleStageAtOnce.begin", event: eventID.description)
            self.singleStageAtOnce = Spawn(
                ScheduleSingleStageAtOnce.State(
                    eventID: eventID,
                    scheduleDivision: scheduleDivision
                )
            )
            AttendeePerformance.mark("schedule-child-singleStageAtOnce.end", event: eventID.description)
            AttendeePerformance.mark("schedule-child-manyStagesAtOnce.begin", event: eventID.description)
            self.manyStagesAtOnce = Spawn(
                ScheduleManyStagesAtOnce.State(
                    eventID: eventID,
                    scheduleDivision: scheduleDivision
                )
            )
            AttendeePerformance.mark("schedule-child-manyStagesAtOnce.end", event: eventID.description)
            AttendeePerformance.mark("schedule-child-performanceList.begin", event: eventID.description)
            self.performanceList = Spawn(
                SchedulePerformanceList.State(
                    eventID: eventID,
                    scheduleDivision: scheduleDivision
                )
            )
            AttendeePerformance.mark("schedule-child-performanceList.end", event: eventID.description)
            AttendeePerformance.mark("schedule-query-event.begin", event: eventID.description)
            _event = FetchOne(
                Event.where { $0.id.eq(eventID) }
            )
            AttendeePerformance.mark("schedule-query-event.end", event: eventID.description)
            AttendeePerformance.mark("schedule-query-performanceRows.begin", event: eventID.description)
            _performanceRows = FetchAll(
                PerformanceRow.all(eventID: eventID)
            )
            AttendeePerformance.mark("schedule-query-performanceRows.end", event: eventID.description)
            AttendeePerformance.mark("schedule-query-schedules.begin", event: eventID.description)
            _schedules = FetchAll(
                ScheduleList.schedulesQuery(eventID: eventID)
            )
            AttendeePerformance.mark("schedule-query-schedules.end", event: eventID.description)
            AttendeePerformance.mark("schedule-query-stages.begin", event: eventID.description)
            _stages = FetchAll(
                ScheduleList.stagesQuery(eventID: eventID)
            )
            AttendeePerformance.mark("schedule-query-stages.end", event: eventID.description)
            AttendeePerformance.mark("schedule-query-reactions.begin", event: eventID.description)
            _reactions = FetchAll(
                PerformanceReaction.forEvent(eventID: eventID)
            )
            AttendeePerformance.mark("schedule-query-reactions.end", event: eventID.description)
            AttendeePerformance.mark("schedule-query-reactionUsage.begin", event: eventID.description)
            _reactionUsage = FetchAll(
                PerformanceReactionEmojiUsage.ranked
            )
            AttendeePerformance.mark("schedule-query-reactionUsage.end", event: eventID.description)
            AttendeePerformance.mark("schedule-query-userSchedules.begin", event: eventID.description)
            _userSchedules = FetchAll(
                UserSchedule.all(eventID: eventID)
            )
            AttendeePerformance.mark("schedule-query-userSchedules.end", event: eventID.description)
            AttendeePerformance.mark("schedule-query-userSchedulePerformances.begin", event: eventID.description)
            _userSchedulePerformances = FetchAll(
                UserSchedule.Performance.all
            )
            AttendeePerformance.mark("schedule-query-userSchedulePerformances.end", event: eventID.description)
        }

        public let eventID: Event.ID
        @FetchOne public var timeZone: TimeZone?
        var eventTimePresentation: EventTimePresentation? {
            timeZone.map { EventTimePresentation(timeZone: $0) }
        }
        public let scheduleDivision: ScheduleDivision
        public var destination: Destination.State? = nil
        public var singleStageAtOnce: Spawn<ScheduleSingleStageAtOnce>
        public var manyStagesAtOnce: Spawn<ScheduleManyStagesAtOnce>
        public var performanceList: Spawn<SchedulePerformanceList>
        public var scheduleViewerState: ScheduleListState
        var scheduleViewerStateBaseline: ScheduleListState
        @FetchOne var persistedScheduleViewerState: ScheduleListState?
        public var eventViewerState: EventDetailState
        @FetchOne var persistedEventViewerState: EventDetailState?

        @FetchOne public var event: Event?
        public var scheduleKind: ScheduleKind {
            get { scheduleViewerState.scheduleKind }
            set {
                scheduleViewerState.scheduleKind = newValue
                scheduleViewerState.syncScheduleKindStorage()
            }
        }

        public var showStageNameLabels: Bool {
            let identifiers = visibleStages.map(\.stageVisualIdentifier)
            return Set(identifiers).count < identifiers.count
        }

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

        @FetchAll public var performanceRows: [PerformanceRow]
        @FetchAll public var schedules: [Schedule]
        public var orderedSchedules: [Schedule] {
            ScheduleList.orderedSchedules(event: event, schedules: schedules)
        }
        @FetchAll public var stages: [EventPlace]
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

        public var performances: [ProgramItem] {
            performanceRows.map(\.performance)
        }

        public func selectedSchedule(
            selectedScheduleID: Schedule.ID?
        ) -> Schedule? {
            guard let selectedScheduleID = resolvedSelectedScheduleID(selectedScheduleID) else {
                return nil
            }
            return schedules.first { $0.id == selectedScheduleID }
        }

        public func visiblePerformances(
            selectedScheduleID: Schedule.ID?
        ) -> [ProgramItem] {
            visiblePerformanceRows(selectedScheduleID: selectedScheduleID)
                .map(\.performance)
        }

        public func requiresListPresentation(selectedScheduleID: Schedule.ID?) -> Bool {
            if !unscheduledPerformanceRows.isEmpty { return true }
            let visibleStageIDs = Set(visibleStages.map(\.id))
            return visiblePerformances(selectedScheduleID: selectedScheduleID).contains { item in
                if item.startDate == nil || item.endDate == nil { return true }
                guard let eventPlace = item.eventPlace else { return true }
                return !visibleStageIDs.contains(eventPlace)
            }
        }

        public var unscheduledPerformanceRows: [PerformanceRow] {
            guard let programID = scheduleDivision.programID else { return [] }
            return performanceRows.filter {
                $0.performance.program == programID && $0.performance.schedule == nil
            }
        }

        func visiblePerformanceRows(
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
            guard let selectedStageID = resolvedSelectedStageID else { return [] }
            return visiblePerformances(selectedScheduleID: selectedScheduleID)
                .filter { $0.eventPlace == selectedStageID }
        }

        func currentTimeDestination(
            currentDate: Date?,
            selectedScheduleID: Schedule.ID?,
            buffer: TimeInterval
        ) -> CurrentTimeDestination? {
            ScheduleList.currentTimeDestination(
                currentDate: currentDate,
                selectedScheduleID: selectedScheduleID,
                schedules: orderedSchedules,
                performanceRows: performanceRows,
                division: scheduleDivision,
                buffer: buffer
            )
        }

        func resolvedSelectedScheduleID(
            _ selectedScheduleID: Schedule.ID?
        ) -> Schedule.ID? {
            if let selectedScheduleID,
               orderedSchedules.contains(where: { $0.id == selectedScheduleID }) {
                return selectedScheduleID
            }
            return orderedSchedules.first?.id
        }

        var resolvedSelectedStageID: EventPlace.ID? {
            ScheduleList.resolvedSelectedStageID(
                selectedStageID: scheduleViewerState.selectedStageID,
                stages: visibleStages
            )
        }

        func selectedScheduleTitle(
            selectedScheduleID: Schedule.ID?
        ) -> String {
            guard let schedule = selectedSchedule(selectedScheduleID: selectedScheduleID),
                  let timeZone
            else { return "Select Schedule" }
            return ScheduleList.scheduleTitle(schedule, in: timeZone)
        }

        var selectedStage: EventPlace? {
            guard let resolvedSelectedStageID else { return nil }
            return visibleStages.first { $0.id == resolvedSelectedStageID }
        }

        var stagesByID: [EventPlace.ID: EventPlace] {
            Dictionary(uniqueKeysWithValues: stages.map { ($0.id, $0) })
        }

        var visibleStages: [EventPlace] {
            ScheduleList.visibleStages(
                stages: stages,
                division: scheduleDivision
            )
        }
    }

    public enum Action {
        case addPerformanceButtonTapped(Schedule.ID?)
        case addScheduleButtonTapped
        case addStageButtonTapped
        case addToNewUserScheduleButtonTapped(ProgramItem.ID)
        case destination(Destination.Action)
        case editScheduleButtonTapped(Schedule.ID)
        case moveScheduleButtonTapped(Schedule.ID, Int)
        case otherReactionButtonTapped(ProgramItem.ID)
        case performanceButtonTapped(ProgramItem.ID)
        case programsButtonTapped
        case reactionButtonTapped(ProgramItem.ID, PerformanceReaction.Emoji)
        case scheduleKindButtonTapped(ScheduleKind)
        case schedulesButtonTapped
        case userScheduleButtonTapped(UserSchedule.ID?)
        case userScheduleMembershipButtonTapped(
            performanceID: ProgramItem.ID,
            scheduleID: UserSchedule.ID
        )
    }

    @Feature
    public enum Destination {
        case deletePerformanceConfirmation(DeletePerformanceConfirmation)
        case performanceDetail(Spawn<ProgramItemDetail>)
        case programs(Spawn<ProgramList>)
        case reactionEntry(PerformanceReactionEntry)
        case scheduleForm(ScheduleForm)
        case userScheduleForm(Spawn<UserScheduleForm>)
        case userScheduleList(Spawn<UserScheduleList>)
    }

    @Feature
    public struct DeletePerformanceConfirmation: Prompt {
        public struct State: Identifiable {
            public init(performanceID: ProgramItem.ID) {
                self.performanceID = performanceID
            }

            public var performanceID: ProgramItem.ID
            public var id: ProgramItem.ID { performanceID }
        }

        public enum Action {
            case deleteButtonTapped(ProgramItem.ID)
        }
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now
    @Dependency(\.getSelectedOAuthSessionID) var getSelectedOAuthSessionID
    @Dependency(\.uuid) var uuid

    static func eventPerformancesQuery(
        eventID: Event.ID
    ) -> some SelectStatementOf<ProgramItem> {
        ProgramItem
            .where { $0.event.eq(eventID) }
            .order { ($0.startsAt.asc(nulls: .last), $0.title.collate(.nocase)) }
    }

    static func performancesQuery(
        eventID: Event.ID,
        scheduleID: Schedule.ID
    ) -> some SelectStatementOf<ProgramItem> {
        ProgramItem
            .where { $0.event.eq(eventID) }
            .where { $0.schedule.eq(scheduleID) }
            .order { ($0.startsAt.asc(nulls: .last), $0.title.collate(.nocase)) }
    }

    static func schedulesQuery(
        eventID: Event.ID
    ) -> some SelectStatementOf<Schedule> {
        Schedule
            .where { $0.event.eq(eventID) }
            .order { ($0.date, $0.title.asc(nulls: .last)) }
    }

    static func orderedSchedules(event: Event?, schedules: [Schedule]) -> [Schedule] {
        guard let scheduleIDs = event?.schedules else { return schedules }
        let byID = Dictionary(uniqueKeysWithValues: schedules.map { ($0.id, $0) })
        return scheduleIDs.compactMap { byID[$0] }
    }

    static func stagesQuery(
        eventID: Event.ID
    ) -> some SelectStatementOf<EventPlace> {
        EventPlace.where { $0.event.eq(eventID) }
    }

    static func scheduleTitle(
        _ schedule: Schedule,
        in timeZone: TimeZone
    ) -> String {
        if let customTitle = schedule.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customTitle.isEmpty {
            return customTitle
        }
        return schedule.date.formattedWeekday(in: timeZone)
    }

    static func emptyStageTitle(
        scheduleDivision: ScheduleDivision,
        scheduleTitle: String,
        stage: EventPlace
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
        selectedStageID: EventPlace.ID?,
        stages: [EventPlace]
    ) -> EventPlace.ID? {
        if let selectedStageID,
           stages.contains(where: { $0.id == selectedStageID }) {
            return selectedStageID
        }
        return stages.first?.id
    }

    static func normalizedSelectedStageID(
        selectedStageID: EventPlace.ID?,
        stages: [EventPlace]
    ) -> EventPlace.ID? {
        guard !stages.isEmpty else { return selectedStageID }
        return resolvedSelectedStageID(
            selectedStageID: selectedStageID,
            stages: stages
        )
    }

    static func scheduleDivisions(event: Event?, programs: [Program]) -> [ScheduleDivision] {
        guard let event else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: programs.map { ($0.id, $0) })
        return (event.programs ?? []).compactMap { byID[$0].map(ScheduleDivision.init(program:)) }
    }

    static func visiblePerformances(
        performanceRows: [PerformanceRow],
        scheduleID: Schedule.ID?,
        division: ScheduleDivision
    ) -> [PerformanceRow] {
        guard let scheduleID, let programID = division.programID else { return [] }
        return performanceRows.filter {
            $0.performance.schedule == scheduleID
                && $0.performance.program == programID
        }
    }

    static func currentTimeDestination(
        currentDate: Date?,
        selectedScheduleID: Schedule.ID?,
        schedules: [Schedule],
        performanceRows: [PerformanceRow],
        division: ScheduleDivision,
        buffer: TimeInterval
    ) -> CurrentTimeDestination? {
        guard let currentDate else { return nil }

        let candidates = schedules.compactMap { schedule -> CurrentTimeDestination? in
            let rows = visiblePerformances(
                performanceRows: performanceRows,
                scheduleID: schedule.id,
                division: division
            )
            .filter { $0.performance.startDate != nil && $0.performance.endDate != nil }
            guard
                let firstStart = rows.compactMap(\.performance.startDate).min(),
                let lastEnd = rows.compactMap(\.performance.endDate).max()
            else { return nil }

            let renderedRange = DateInterval(
                start: firstStart.addingTimeInterval(-buffer),
                end: lastEnd.addingTimeInterval(buffer)
            )
            guard renderedRange.contains(currentDate) else { return nil }

            let row = rows.first { row in
                guard let start = row.performance.startDate,
                      let end = row.performance.endDate else { return false }
                return start <= currentDate && currentDate < end
            } ?? rows.first { row in
                guard let start = row.performance.startDate else { return false }
                return currentDate < start
            } ?? rows.last
            guard let row else { return nil }

            return CurrentTimeDestination(
                scheduleID: schedule.id,
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
        stages: [EventPlace],
        division: ScheduleDivision
    ) -> [EventPlace] {
        let byID = Dictionary(uniqueKeysWithValues: stages.map { ($0.id, $0) })
        return division.eventPlaces.compactMap { byID[$0] }
    }

    static func unavailableStageIDs(
        stages: [EventPlace],
        performances: [ProgramItem]
    ) -> Set<EventPlace.ID> {
        let stageIDsWithPerformances = Set(performances.compactMap(\.eventPlace))
        return Set(stages.map(\.id)).subtracting(stageIDsWithPerformances)
    }

    static func canAddPerformance(
        selectedScheduleID: Schedule.ID?,
        schedules: [Schedule],
        division: ScheduleDivision,
        event: Event?
    ) -> Bool {
        if event?.programs?.isEmpty == false && division.programID == nil { return false }
        if Self.resolvedSelectedScheduleID(
            selectedScheduleID,
            schedules: schedules
        ) != nil {
            return true
        }
        return schedules.isEmpty
    }

    static func resolvedSelectedScheduleID(
        _ selectedScheduleID: Schedule.ID?,
        schedules: [Schedule]
    ) -> Schedule.ID? {
        if let selectedScheduleID,
           schedules.contains(where: { $0.id == selectedScheduleID }) {
            return selectedScheduleID
        }
        return schedules.first?.id
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case let .addPerformanceButtonTapped(selectedScheduleID):
                guard Self.canAddPerformance(
                        selectedScheduleID: selectedScheduleID,
                        schedules: state.orderedSchedules,
                        division: state.scheduleDivision,
                        event: state.event
                      )
                else { return }
                let eventID = state.eventID
                let scheduleID = state.resolvedSelectedScheduleID(selectedScheduleID)
                let programID = state.scheduleDivision.programID
                let selectedStageID = state.resolvedSelectedStageID
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .addPerformance(
                            eventID: eventID,
                            scheduleID: scheduleID,
                            programID: programID,
                            stageID: selectedStageID
                        )
                    )
                    await task?.value
                }

            case .addStageButtonTapped:
                let eventID = state.eventID
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .createPlace(eventID)
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

            case let .editScheduleButtonTapped(scheduleID):
                guard let schedule = state.orderedSchedules.first(where: { $0.id == scheduleID }),
                      let timeZone = state.timeZone else { return }
                state.destination = .scheduleForm(
                    ScheduleForm.State(schedule: schedule, timeZone: timeZone)
                )

            case let .moveScheduleButtonTapped(scheduleID, offset):
                guard let index = state.orderedSchedules.firstIndex(where: { $0.id == scheduleID }),
                      state.orderedSchedules.indices.contains(index + offset) else { return }
                let eventID = state.eventID
                store.addTask {
                    do {
                        try await database.write { db in
                            guard var event = try Event.find(eventID).fetchOne(db) else { return }
                            let existingIDs: [Schedule.ID]
                            if let schedules = event.schedules {
                                existingIDs = schedules
                            } else {
                                existingIDs = try Self.schedulesQuery(eventID: eventID)
                                    .fetchAll(db).map(\.id)
                            }
                            var scheduleIDs = existingIDs
                            guard let index = scheduleIDs.firstIndex(of: scheduleID),
                                  scheduleIDs.indices.contains(index + offset) else { return }
                            scheduleIDs.swapAt(index, index + offset)
                            event.schedules = scheduleIDs
                            try event.validateReferences()
                            try Event.upsert { event }.execute(db)
                        }
                    } catch {
                        reportIssue(error)
                    }
                }

            case let .otherReactionButtonTapped(performanceID):
                state.destination = .reactionEntry(
                    PerformanceReactionEntry.State(performanceID: performanceID)
                )

            case let .performanceButtonTapped(performanceID):
                store.withDependencies {
                    state.destination = .performanceDetail(
                        Spawn(
                            ProgramItemDetail.State(
                                performanceID: performanceID,
                                eventID: state.eventID
                            )
                        )
                    )
                }

            case .programsButtonTapped:
                state.destination = .programs(Spawn(ProgramList.State(eventID: state.eventID)))

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
                state.destination = .userScheduleList(
                    Spawn(UserScheduleList.State(eventID: state.eventID))
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
        .ifLet(\.destination) {
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
        .onChange(of: store.persistedEventViewerState) {
            oldPersistedState, persistedState, state in
            guard let persistedState else { return }
            state.eventViewerState.mergePersistedChanges(
                from: oldPersistedState,
                to: persistedState
            )
        }
        .onChange(of: store.eventViewerState) { oldViewerState, viewerState, state in
            guard state.persistedEventViewerState != viewerState else { return }
            do {
                try database.write { db in
                    try EventDetailState.persistChanges(
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
            AttendeePerformance.mark("schedule-onMount.begin", event: state.eventID.description)
            defer { AttendeePerformance.mark("schedule-onMount.end", event: state.eventID.description) }
            let eventID = state.eventID
            let scheduleDivision = state.scheduleDivision
            let initialScheduleViewerState = state.scheduleViewerState
            let persistedScheduleViewerState = state.$persistedScheduleViewerState
            let persistedEventViewerState = state.$persistedEventViewerState
            store.addTask {
                let subscription = try await persistedScheduleViewerState.load(
                    ScheduleListState.rows(
                        eventID: eventID,
                        scheduleDivision: scheduleDivision
                    )
                )
                if persistedScheduleViewerState.wrappedValue == nil {
                    let defaultState = try await database.read { db in
                        try ScheduleListStateRequest(
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
                    EventDetailState.where { $0.id.eq(eventID) }
                )
                .task
            }

            guard !state.eventViewerState.didInitializeUserSchedules else { return }
            let scheduleID = uuid()
            let userDID = getSelectedOAuthSessionID()?.rawValue
            store.addTask {
                do {
                    try await database.write { db in
                        var viewerState = try EventDetailStateRequest(eventID: eventID).fetch(db)
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
                        try EventDetailState.upsert { viewerState }.execute(db)
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
        performanceID: ProgramItem.ID,
        eventID: Event.ID,
        database: any DatabaseWriter
    ) async throws {
        try await database.write { db in
            try ProgramItemRecordEditing.delete(performanceID, eventID: eventID, in: db)
        }
    }
}

extension ProgramItem {
    var displayDescription: String? {
        let description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return description?.isEmpty == false ? description : nil
    }

}

private extension LocalDate {
    func formattedWeekday(in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let weekdayStyle = Date.FormatStyle(
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: calendar,
            timeZone: timeZone
        )
        .weekday(.wide)
        return atStartOfDay(in: timeZone).formatted(weekdayStyle)
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
