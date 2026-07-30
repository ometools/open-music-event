import Foundation
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

// SKIP INSERT: import skip.ui.*

public struct DateTimeRangeResolutionPolicy: Equatable, Sendable {
    public init(rolloverHour: Int = 6) {
        self.rolloverHour = rolloverHour
    }

    public var rolloverHour: Int

    public static let `default` = Self()
}

public struct DateTimeRangeSelection: Equatable, Sendable {
    public init(
        start: Date,
        end: Date,
        timeZone: TimeZone,
        anchorDate: Date,
        preferredWindow: DateInterval? = nil,
        resolutionPolicy: DateTimeRangeResolutionPolicy = .default
    ) {
        self.anchorDate = anchorDate
        self.end = end
        self.preferredWindow = preferredWindow
        self.resolutionPolicy = resolutionPolicy
        self.start = start
        self.timeZone = timeZone
    }

    public var anchorDate: Date
    public var end: Date
    public var preferredWindow: DateInterval?
    public var resolutionPolicy: DateTimeRangeResolutionPolicy
    public var start: Date
    public var timeZone: TimeZone

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    public var durationMinutesSelection: Int {
        get { max(5, Int((duration / 60).rounded())) }
        set { setDuration(minutes: newValue) }
    }

    public var durationMinuteRange: ClosedRange<Int> {
        5...max(24 * 60, durationMinutesSelection)
    }

    public var durationLabel: String {
        Self.durationLabel(minutes: durationMinutesSelection)
    }

    public var endDayOffset: Int {
        get { dayOffset(for: end) }
        set { setEndDayOffset(newValue) }
    }

    public var endDayOffsetOptions: [Int] {
        dayOffsetOptions(matchingClockTimeOf: end)
    }

    public var startDayOffset: Int {
        get { dayOffset(for: start) }
        set { setStartDayOffset(newValue) }
    }

    public var startDayOffsetOptions: [Int] {
        dayOffsetOptions(matchingClockTimeOf: start)
    }

    public var shouldChooseEndDayExplicitly: Bool {
        shouldChooseDayExplicitly(matchingClockTimeOf: end)
    }

    public var shouldChooseStartDayExplicitly: Bool {
        shouldChooseDayExplicitly(matchingClockTimeOf: start)
    }

    public var endClockTimeSelection: Date {
        get { end }
        set { resolveEndClockTime(from: newValue, policy: resolutionPolicy) }
    }

    public var startClockTimeSelection: Date {
        get { start }
        set { resolveStartClockTime(from: newValue, policy: resolutionPolicy) }
    }

    public mutating func resolveStartClockTime(
        from date: Date,
        preservingDuration duration: TimeInterval? = nil,
        policy: DateTimeRangeResolutionPolicy
    ) {
        let oldDuration = max(duration ?? self.duration, Self.minimumDuration)
        start = resolvedDate(
            matchingClockTimeOf: date,
            after: nil,
            policy: policy
        )
        end = start.addingTimeInterval(oldDuration)
    }

    public mutating func resolveEndClockTime(
        from date: Date,
        policy: DateTimeRangeResolutionPolicy
    ) {
        end = resolvedDate(
            matchingClockTimeOf: date,
            after: start,
            policy: policy
        )
    }

    public mutating func setStartDayOffset(_ dayOffset: Int) {
        let duration = validDuration
        start = moving(start, toDayOffset: dayOffset)
        end = start.addingTimeInterval(duration)
    }

    public mutating func setEndDayOffset(_ dayOffset: Int) {
        end = moving(end, toDayOffset: dayOffset)
    }

    public mutating func setDuration(minutes: Int) {
        let minutes = max(5, minutes)
        end = start.addingTimeInterval(TimeInterval(minutes * 60))
    }

    public func dayLabel(for date: Date) -> String {
        let offset = dayOffset(for: date)
        if offset == 0 { return "Same day" }
        if offset == 1 { return "Next day" }
        if offset == -1 { return "Previous day" }
        if offset > 1 { return "+\(offset) days" }
        return "\(offset) days"
    }

    public static func durationLabel(minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        switch (hours, remainingMinutes) {
        case (0, let minutes):
            return "\(minutes) min"
        case (let hours, 0):
            return hours == 1 ? "1 hr" : "\(hours) hr"
        case (1, let minutes):
            return "1 hr \(minutes) min"
        case (let hours, let minutes):
            return "\(hours) hr \(minutes) min"
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func dayOffset(for date: Date) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: anchorDate),
            to: calendar.startOfDay(for: date)
        )
        .day ?? 0
    }

    private func moving(_ date: Date, toDayOffset dayOffset: Int) -> Date {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let targetDay = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: calendar.startOfDay(for: anchorDate)
        ) ?? anchorDate
        return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: targetDay
        ) ?? date
    }

    private func resolvedDate(
        matchingClockTimeOf date: Date,
        after lowerBound: Date?,
        policy: DateTimeRangeResolutionPolicy
    ) -> Date {
        let candidates = candidateDates(matchingClockTimeOf: date, policy: policy)
        if let lowerBound {
            let afterLowerBound = candidates.filter { $0 > lowerBound }
            if let preferredWindow,
               let firstInWindow = afterLowerBound
                .filter({ preferredWindow.contains($0) })
                .min() {
                return firstInWindow
            }
            return afterLowerBound.min()
                ?? dateMatchingClockTime(of: date, dayOffset: dayOffset(for: lowerBound) + 1)
        }
        return candidates.first
            ?? dateMatchingClockTime(of: date, dayOffset: 0)
    }

    private func candidateDates(
        matchingClockTimeOf date: Date,
        policy: DateTimeRangeResolutionPolicy
    ) -> [Date] {
        let offsets = candidateDayOffsets(matchingClockTimeOf: date, policy: policy)
        return offsets.map { self.dateMatchingClockTime(of: date, dayOffset: $0) }
    }

    private func candidateDayOffsets(
        matchingClockTimeOf date: Date,
        policy: DateTimeRangeResolutionPolicy
    ) -> [Int] {
        let policyDayOffset = dayOffset(matchingClockTimeOf: date, policy: policy)
        if preferredWindow != nil {
            let windowDayOffsets = windowDayOffsets(matchingClockTimeOf: date)
            if windowDayOffsets.count == 1 {
                return uniqueDayOffsets(windowDayOffsets + [policyDayOffset, 0, 1, -1, 2])
            } else if windowDayOffsets.count > 1 {
                let currentDayOffset = dayOffset(for: date)
                let currentDayOffsets = windowDayOffsets.contains(currentDayOffset)
                    ? [currentDayOffset]
                    : []
                return uniqueDayOffsets(currentDayOffsets + windowDayOffsets + [policyDayOffset, 0, 1, -1, 2])
            }
        }
        return uniqueDayOffsets([policyDayOffset, 0, 1, -1, 2])
    }

    private func dayOffsetOptions(matchingClockTimeOf date: Date) -> [Int] {
        let offsets: [Int]
        if preferredWindow == nil {
            offsets = defaultDayOffsets
        } else {
            let windowDayOffsets = windowDayOffsets(matchingClockTimeOf: date)
            offsets = windowDayOffsets.isEmpty ? defaultDayOffsets : windowDayOffsets
        }
        let currentDayOffset = dayOffset(for: date)
        return uniqueDayOffsets([currentDayOffset] + offsets)
    }

    private func shouldChooseDayExplicitly(matchingClockTimeOf date: Date) -> Bool {
        guard preferredWindow != nil else { return true }
        return windowDayOffsets(matchingClockTimeOf: date).count != 1
    }

    private func windowDayOffsets(matchingClockTimeOf date: Date) -> [Int] {
        guard let preferredWindow else { return [] }
        return defaultDayOffsets.filter { offset in
            preferredWindow.contains(dateMatchingClockTime(of: date, dayOffset: offset))
        }
    }

    private var defaultDayOffsets: [Int] {
        [-1, 0, 1, 2]
    }

    private var validDuration: TimeInterval {
        max(duration, Self.minimumDuration)
    }

    private static let minimumDuration: TimeInterval = 5 * 60

    private func uniqueDayOffsets(_ offsets: [Int]) -> [Int] {
        var seen = Set<Int>()
        return offsets.compactMap { offset in
            guard seen.insert(offset).inserted else { return nil }
            return offset
        }
    }

    private func dayOffset(
        matchingClockTimeOf date: Date,
        policy: DateTimeRangeResolutionPolicy
    ) -> Int {
        guard preferredWindow == nil else { return 0 }
        let hour = calendar.component(.hour, from: date)
        return hour < policy.rolloverHour ? 1 : 0
    }

    private func dateMatchingClockTime(of date: Date, dayOffset: Int) -> Date {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let targetDay = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: calendar.startOfDay(for: anchorDate)
        ) ?? anchorDate
        return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: targetDay
        ) ?? date
    }
}

public struct DateTimeRangePicker: View {
    @Environment(\.dateTimeRangeResolutionPolicy) var policy
    @Binding var selection: DateTimeRangeSelection
    let endLabel: LocalizedStringKey
    let startLabel: LocalizedStringKey

    public init(
        startLabel: LocalizedStringKey = "Starts",
        endLabel: LocalizedStringKey = "Ends",
        selection: Binding<DateTimeRangeSelection>
    ) {
        self.endLabel = endLabel
        self.startLabel = startLabel
        self._selection = selection
    }

    public var body: some View {
        Group {
            DatePicker(
                startLabel,
                selection: $selection.startClockTimeSelection,
                displayedComponents: .hourAndMinute
            )
            .environment(\.timeZone, selection.timeZone)

            if selection.shouldChooseStartDayExplicitly {
                Picker("Start Day", selection: $selection.startDayOffset) {
                    ForEach(selection.startDayOffsetOptions, id: \.self) { offset in
                        Text(dayOffsetLabel(offset)).tag(offset)
                    }
                }
            } else if selection.startDayOffset != 0 {
                LabeledContent("Start Day", value: selection.dayLabel(for: selection.start))
            }

            Stepper(
                value: $selection.durationMinutesSelection,
                in: selection.durationMinuteRange,
                step: 5
            ) {
                LabeledContent("Duration", value: selection.durationLabel)
            }

            LabeledContent(endLabel) {
                Text(endSummaryLabel)
            }
        }
        .onAppear { updateResolutionPolicy() }
        .onChange(of: policy) { _, _ in updateResolutionPolicy() }
    }

    private func dayOffsetLabel(_ offset: Int) -> String {
        if offset == 0 { return "Same day" }
        if offset == 1 { return "Next day" }
        if offset == -1 { return "Previous day" }
        if offset > 1 { return "+\(offset) days" }
        return "\(offset) days"
    }

    private var endSummaryLabel: String {
        let clockTime = clockTimeLabel(for: selection.end)
        if selection.endDayOffset == selection.startDayOffset {
            return clockTime
        }
        return "\(clockTime), \(selection.dayLabel(for: selection.end))"
    }

    private func clockTimeLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = selection.timeZone
        return formatter.string(from: date)
    }

    private func updateResolutionPolicy() {
        selection.resolutionPolicy = policy
    }
}
