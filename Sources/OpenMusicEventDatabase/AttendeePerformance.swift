import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Monotonic diagnostic markers for UI automation; never uses the fixture's frozen date.
public enum AttendeePerformance {
    public static func mark(_ phase: String, event: String = "") {
        #if DEBUG && canImport(OSLog)
        guard Bundle.main.object(forInfoDictionaryKey: "OMEUIAutomation") as? String == "YES"
        else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        Logger(subsystem: "app.openmusicevent", category: "performance")
            .notice("OME_PERF \(uptime, privacy: .public) \(phase, privacy: .public) \(event, privacy: .public)")
        #endif
    }
}
