#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

public enum ScheduleTimelineOrientation: Hashable, Sendable {
    case verticalTime
    case horizontalTime
}

public enum ScheduleScrollTarget: Hashable, Sendable {
    case currentTime
}

private enum ScheduleHeightEnvironmentKey: EnvironmentKey {
    static let defaultValue: ScheduleCGFloat = 1500
}

private enum ScheduleWidthEnvironmentKey: EnvironmentKey {
    static let defaultValue: ScheduleCGFloat = 0
}

private enum ScheduleTimelineOrientationEnvironmentKey: EnvironmentKey {
    static let defaultValue = ScheduleTimelineOrientation.verticalTime
}

private enum SchedulePointsPerHourKey: EnvironmentKey {
    static let defaultValue: ScheduleCGFloat = 80
}

private enum ScheduleTimeBufferKey: EnvironmentKey {
    static let defaultValue: TimeInterval = 60 * 60
}

private enum ScheduleTimeRangeKey: EnvironmentKey {
    static let defaultValue: DateInterval? = nil
}

private enum DateTimeRangeResolutionPolicyKey: EnvironmentKey {
    static let defaultValue = DateTimeRangeResolutionPolicy.default
}

private enum ShowTimeIndicatorEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var dateTimeRangeResolutionPolicy: DateTimeRangeResolutionPolicy {
        get { self[DateTimeRangeResolutionPolicyKey.self] }
        set { self[DateTimeRangeResolutionPolicyKey.self] = newValue }
    }

    var scheduleHeight: ScheduleCGFloat {
        get { self[ScheduleHeightEnvironmentKey.self] }
        set { self[ScheduleHeightEnvironmentKey.self] = newValue }
    }

    var scheduleWidth: ScheduleCGFloat {
        get { self[ScheduleWidthEnvironmentKey.self] }
        set { self[ScheduleWidthEnvironmentKey.self] = newValue }
    }

    var scheduleTimelineOrientation: ScheduleTimelineOrientation {
        get { self[ScheduleTimelineOrientationEnvironmentKey.self] }
        set { self[ScheduleTimelineOrientationEnvironmentKey.self] = newValue }
    }

    var schedulePointsPerHour: ScheduleCGFloat {
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
