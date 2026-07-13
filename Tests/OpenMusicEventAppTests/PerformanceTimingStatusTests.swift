import Foundation
import Testing

@testable import OpenMusicEventAppEventViewer

struct PerformanceTimingStatusTests {
    @Test
    func statusTracksFutureActiveAndEndedPerformances() {
        let startTime = Date(timeIntervalSince1970: 1_800_000_000)
        let endTime = startTime.addingTimeInterval(60 * 60)

        #expect(
            PerformanceTimingStatus(
                startTime: startTime,
                endTime: endTime,
                now: startTime.addingTimeInterval(-15 * 60)
            ) == .startsIn(15 * 60)
        )
        #expect(
            PerformanceTimingStatus(
                startTime: startTime,
                endTime: endTime,
                now: startTime
            ) == .nowPlaying
        )
        #expect(
            PerformanceTimingStatus(
                startTime: startTime,
                endTime: endTime,
                now: endTime.addingTimeInterval(-1)
            ) == .nowPlaying
        )
        #expect(
            PerformanceTimingStatus(
                startTime: startTime,
                endTime: endTime,
                now: endTime
            ) == nil
        )
    }

    @Test
    func startsInTitleUsesCompactRemainingTime() {
        #expect(PerformanceTimingStatus.startsIn(30).title == "Starts In <1m")
        #expect(PerformanceTimingStatus.startsIn(15 * 60).title == "Starts In 15m")
        #expect(PerformanceTimingStatus.startsIn((2 * 60 + 10) * 60).title == "Starts In 2h 10m")
        #expect(PerformanceTimingStatus.startsIn((24 + 3) * 60 * 60).title == "Starts In 1d 3h")
    }
}
