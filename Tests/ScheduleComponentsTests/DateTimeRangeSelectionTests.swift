import Foundation
import ScheduleComponents
import Testing

struct DateTimeRangeSelectionTests {
    @Test
    func defaultPolicyResolvesEarlyClockTimesToNextDay() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        var selection = DateTimeRangeSelection(
            start: try date(2026, 8, 7, 20, in: timeZone),
            end: try date(2026, 8, 7, 21, in: timeZone),
            timeZone: timeZone,
            anchorDate: try date(2026, 8, 7, 0, in: timeZone)
        )

        selection.startClockTimeSelection = try date(2026, 8, 7, 1, 30, in: timeZone)

        let expectedStart = try date(2026, 8, 8, 1, 30, in: timeZone)
        #expect(selection.start == expectedStart)
        #expect(selection.startDayOffset == 1)
    }

    @Test
    func endClockTimeResolvesAfterStart() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        var selection = DateTimeRangeSelection(
            start: try date(2026, 8, 7, 23, 30, in: timeZone),
            end: try date(2026, 8, 7, 23, 45, in: timeZone),
            timeZone: timeZone,
            anchorDate: try date(2026, 8, 7, 0, in: timeZone)
        )

        selection.endClockTimeSelection = try date(2026, 8, 7, 1, 15, in: timeZone)

        let expectedEnd = try date(2026, 8, 8, 1, 15, in: timeZone)
        #expect(selection.end == expectedEnd)
        #expect(selection.end > selection.start)
    }

    @Test
    func durationSelectionUpdatesEndFromStart() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        var selection = DateTimeRangeSelection(
            start: try date(2026, 8, 7, 23, 30, in: timeZone),
            end: try date(2026, 8, 8, 0, 30, in: timeZone),
            timeZone: timeZone,
            anchorDate: try date(2026, 8, 7, 0, in: timeZone)
        )

        selection.durationMinutesSelection = 105

        let expectedEnd = try date(2026, 8, 8, 1, 15, in: timeZone)
        #expect(selection.end == expectedEnd)
        #expect(selection.durationMinutesSelection == 105)
    }

    @Test
    func changingStartDayPreservesDuration() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        var selection = DateTimeRangeSelection(
            start: try date(2026, 8, 7, 20, in: timeZone),
            end: try date(2026, 8, 7, 22, in: timeZone),
            timeZone: timeZone,
            anchorDate: try date(2026, 8, 7, 0, in: timeZone)
        )

        selection.startDayOffset = 1

        let expectedStart = try date(2026, 8, 8, 20, in: timeZone)
        let expectedEnd = try date(2026, 8, 8, 22, in: timeZone)
        #expect(selection.start == expectedStart)
        #expect(selection.end == expectedEnd)
        #expect(selection.durationMinutesSelection == 120)
    }

    @Test
    func changingStartClockTimePreservesShortDuration() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        var selection = DateTimeRangeSelection(
            start: try date(2026, 8, 7, 20, in: timeZone),
            end: try date(2026, 8, 7, 20, 30, in: timeZone),
            timeZone: timeZone,
            anchorDate: try date(2026, 8, 7, 0, in: timeZone)
        )

        selection.startClockTimeSelection = try date(2026, 8, 7, 21, in: timeZone)

        let expectedStart = try date(2026, 8, 7, 21, in: timeZone)
        let expectedEnd = try date(2026, 8, 7, 21, 30, in: timeZone)
        #expect(selection.start == expectedStart)
        #expect(selection.end == expectedEnd)
        #expect(selection.durationMinutesSelection == 30)
    }

    @Test
    func explicitDayOffsetCanOverrideDefaultPolicy() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        var selection = DateTimeRangeSelection(
            start: try date(2026, 8, 7, 20, in: timeZone),
            end: try date(2026, 8, 7, 21, in: timeZone),
            timeZone: timeZone,
            anchorDate: try date(2026, 8, 7, 0, in: timeZone)
        )

        selection.startClockTimeSelection = try date(2026, 8, 7, 1, 30, in: timeZone)
        selection.startDayOffset = 0

        let expectedStart = try date(2026, 8, 7, 1, 30, in: timeZone)
        #expect(selection.start == expectedStart)
        #expect(selection.startDayOffset == 0)
    }

    @Test
    func preferredWindowResolvesMatchingClockTimeInsideWindow() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let window = DateInterval(
            start: try date(2026, 8, 7, 18, in: timeZone),
            end: try date(2026, 8, 8, 6, in: timeZone)
        )
        var selection = DateTimeRangeSelection(
            start: try date(2026, 8, 7, 20, in: timeZone),
            end: try date(2026, 8, 7, 21, in: timeZone),
            timeZone: timeZone,
            anchorDate: try date(2026, 8, 7, 0, in: timeZone),
            preferredWindow: window
        )

        selection.startClockTimeSelection = try date(2026, 8, 7, 1, 30, in: timeZone)

        let expectedStart = try date(2026, 8, 8, 1, 30, in: timeZone)
        #expect(selection.start == expectedStart)
    }

    @Test
    func ambiguousPreferredWindowExposesExplicitDaySelection() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let window = DateInterval(
            start: try date(2026, 8, 7, 18, in: timeZone),
            end: try date(2026, 8, 9, 6, in: timeZone)
        )
        var selection = DateTimeRangeSelection(
            start: try date(2026, 8, 7, 20, in: timeZone),
            end: try date(2026, 8, 7, 21, in: timeZone),
            timeZone: timeZone,
            anchorDate: try date(2026, 8, 7, 0, in: timeZone),
            preferredWindow: window
        )

        selection.startClockTimeSelection = try date(2026, 8, 7, 1, 30, in: timeZone)

        #expect(selection.shouldChooseStartDayExplicitly)
        #expect(selection.startDayOffsetOptions == [1, 2])
    }

    @Test
    func endClockTimeUsesFirstValidDateAfterStartInAmbiguousWindow() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let window = DateInterval(
            start: try date(2026, 8, 7, 18, in: timeZone),
            end: try date(2026, 8, 9, 6, in: timeZone)
        )
        var selection = DateTimeRangeSelection(
            start: try date(2026, 8, 7, 20, in: timeZone),
            end: try date(2026, 8, 7, 21, in: timeZone),
            timeZone: timeZone,
            anchorDate: try date(2026, 8, 7, 0, in: timeZone),
            preferredWindow: window
        )

        selection.endClockTimeSelection = try date(2026, 8, 7, 1, 15, in: timeZone)

        let expectedEnd = try date(2026, 8, 8, 1, 15, in: timeZone)
        #expect(selection.end == expectedEnd)
        #expect(selection.shouldChooseEndDayExplicitly)
    }

    @Test
    func customPolicyControlsRolloverHour() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        var selection = DateTimeRangeSelection(
            start: try date(2026, 8, 7, 20, in: timeZone),
            end: try date(2026, 8, 7, 21, in: timeZone),
            timeZone: timeZone,
            anchorDate: try date(2026, 8, 7, 0, in: timeZone),
            resolutionPolicy: DateTimeRangeResolutionPolicy(rolloverHour: 2)
        )

        selection.startClockTimeSelection = try date(2026, 8, 7, 1, 30, in: timeZone)
        let expectedOvernightStart = try date(2026, 8, 8, 1, 30, in: timeZone)
        #expect(selection.start == expectedOvernightStart)

        selection.startClockTimeSelection = try date(2026, 8, 7, 2, 30, in: timeZone)
        let expectedSameDayStart = try date(2026, 8, 7, 2, 30, in: timeZone)
        #expect(selection.start == expectedSameDayStart)
    }
}

private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int,
    _ minute: Int = 0,
    in timeZone: TimeZone
) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return try #require(
        calendar.date(
            from: DateComponents(
                timeZone: timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )
    )
}
