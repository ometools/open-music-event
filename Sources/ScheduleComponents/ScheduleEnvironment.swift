import SwiftUI

private enum ScheduleHeightEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1500
}

private enum SchedulePointsPerHourKey: EnvironmentKey {
    static let defaultValue: CGFloat = 80
}

private enum ScheduleTimeBufferKey: EnvironmentKey {
    static let defaultValue: TimeInterval = 60 * 60
}

private enum ScheduleTimeRangeKey: EnvironmentKey {
    static let defaultValue: DateInterval? = nil
}

private enum ShowTimeIndicatorEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var scheduleHeight: CGFloat {
        get { self[ScheduleHeightEnvironmentKey.self] }
        set { self[ScheduleHeightEnvironmentKey.self] = newValue }
    }

    var schedulePointsPerHour: CGFloat {
        get { self[SchedulePointsPerHourKey.self] }
        set { self[SchedulePointsPerHourKey.self] = newValue }
    }

    var scheduleTimeBuffer: TimeInterval {
        get { self[ScheduleTimeBufferKey.self] }
        set { self[ScheduleTimeBufferKey.self] = newValue }
    }

    var scheduleTimeRange: DateInterval? {
        get { self[ScheduleTimeRangeKey.self] }
        set { self[ScheduleTimeRangeKey.self] = newValue }
    }

    var shouldShowTimeIndicator: Bool {
        get { self[ShowTimeIndicatorEnvironmentKey.self] }
        set { self[ShowTimeIndicatorEnvironmentKey.self] = newValue }
    }
}
