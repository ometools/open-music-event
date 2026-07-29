import ComposableArchitecture2

public enum ScheduleDivisionRequested: FeatureEventKey {
    public typealias Value = ScheduleViewer.ScheduleDivision
}

public enum SchedulePerformanceDeleteRequested: FeatureEventKey {
    public typealias Value = OMERecord.ID<OMERecord.Performance>
}

public enum SchedulePerformanceDetailRequested: FeatureEventKey {
    public typealias Value = OMERecord.ID<OMERecord.Performance>
}

public enum SchedulePerformanceEditRequested: FeatureEventKey {
    public typealias Value = OMERecord.ID<OMERecord.Performance>
}

public struct SchedulePerformanceUserScheduleMembershipRequest: Equatable, Sendable {
    public init(
        performanceID: OMERecord.ID<OMERecord.Performance>,
        scheduleID: UserSchedule.ID
    ) {
        self.performanceID = performanceID
        self.scheduleID = scheduleID
    }

    public let performanceID: OMERecord.ID<OMERecord.Performance>
    public let scheduleID: UserSchedule.ID
}

public enum SchedulePerformanceUserScheduleMembershipRequested: FeatureEventKey {
    public typealias Value = SchedulePerformanceUserScheduleMembershipRequest
}

public enum SchedulePerformanceNewUserScheduleRequested: FeatureEventKey {
    public typealias Value = OMERecord.ID<OMERecord.Performance>
}
