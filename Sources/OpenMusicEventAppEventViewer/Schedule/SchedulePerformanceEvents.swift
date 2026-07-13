import ComposableArchitecture2

public enum SchedulePerformanceDeleteRequested: FeatureEventKey {
    public typealias Value = OMERecord.ID<OMERecord.Performance>
}

public enum SchedulePerformanceDetailRequested: FeatureEventKey {
    public typealias Value = OMERecord.ID<OMERecord.Performance>
}

public enum SchedulePerformanceEditRequested: FeatureEventKey {
    public typealias Value = OMERecord.ID<OMERecord.Performance>
}
