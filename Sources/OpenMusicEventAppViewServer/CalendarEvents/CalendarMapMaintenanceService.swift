import Foundation
import ServiceLifecycle

struct CalendarMapMaintenanceService: Service {
    let store: OpenMusicEventAppViewStore
    var clock: any Clock<Duration> = ContinuousClock()
    var now: @Sendable () -> Date = { Date() }

    func run() async throws {
        do {
            try await cancelWhenGracefulShutdown {
                while !Task.isCancelled {
                    let expired = try store.expireMapEvents(now: now())
                    let rebuilt = try store.rebuildMapBatch(now: now())
                    try await clock.sleep(for: expired == 500 || !rebuilt ? .milliseconds(10) : .seconds(5))
                }
            }
        } catch is CancellationError {}
    }
}
