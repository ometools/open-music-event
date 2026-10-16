import ComposableArchitecture2
import OpenMusicEventLexicon

public enum ScheduleDivisionRequested: FeatureEventKey {
    public typealias Value = ScheduleList.ScheduleDivision
}

public enum SchedulePerformanceDeleteRequested: FeatureEventKey {
    public typealias Value = ProgramItem.ID
}

public enum SchedulePerformanceEditRequested: FeatureEventKey {
    public typealias Value = ProgramItem.ID
}

public struct SchedulePerformanceUserScheduleMembershipRequest: Equatable, Sendable {
    public init(
        performanceID: ProgramItem.ID,
        scheduleID: UserSchedule.ID
    ) {
        self.performanceID = performanceID
        self.scheduleID = scheduleID
    }

    public let performanceID: ProgramItem.ID
    public let scheduleID: UserSchedule.ID
}

public enum SchedulePerformanceUserScheduleMembershipRequested: FeatureEventKey {
    public typealias Value = SchedulePerformanceUserScheduleMembershipRequest
}

public enum SchedulePerformanceNewUserScheduleRequested: FeatureEventKey {
    public typealias Value = ProgramItem.ID
}
