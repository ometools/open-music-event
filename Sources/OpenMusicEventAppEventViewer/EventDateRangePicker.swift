#if os(iOS)
import DateRangePicker
#endif
import Foundation
import OpenMusicEventLexicon
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

public struct EventDateRangeSelection: Equatable {
    public var hasStartDate: Bool
    public var startDateSelection: Date
    public var hasEndDate: Bool
    public var endDateSelection: Date
    public let timeZone: TimeZone

    public init(
        hasStartDate: Bool,
        startDateSelection: Date,
        hasEndDate: Bool,
        endDateSelection: Date,
        timeZone: TimeZone
    ) {
        self.hasStartDate = hasStartDate
        self.startDateSelection = startDateSelection
        self.hasEndDate = hasEndDate
        self.endDateSelection = endDateSelection
        self.timeZone = timeZone
    }

    public var startDate: Date? {
        get {
            hasStartDate ? pickerDate(for: startDateSelection) : nil
        }
        set {
            guard let newValue else {
                hasStartDate = false
                hasEndDate = false
                return
            }

            hasStartDate = true
            startDateSelection = eventDate(for: newValue)

            if hasEndDate,
               LocalDate(endDateSelection, in: timeZone) < LocalDate(startDateSelection, in: timeZone)
            {
                hasEndDate = false
            }
        }
    }

    public var endDate: Date? {
        get {
            hasEndDate ? pickerDate(for: endDateSelection) : nil
        }
        set {
            guard let newValue else {
                hasEndDate = false
                return
            }

            hasEndDate = true
            endDateSelection = eventDate(for: newValue)

            if !hasStartDate {
                hasStartDate = true
                startDateSelection = endDateSelection
            }
        }
    }

    public mutating func clear() {
        hasStartDate = false
        hasEndDate = false
    }

    var hasDates: Bool {
        hasStartDate || hasEndDate
    }

    var pickerBounds: Range<Date> {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let lowerBound = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1))!
        let upperBound = calendar.date(from: DateComponents(year: 2101, month: 1, day: 1))!
        return lowerBound..<upperBound
    }

    private func pickerDate(for eventDate: Date) -> Date {
        LocalDate(eventDate, in: timeZone).atStartOfDay(in: .current)
    }

    private func eventDate(for pickerDate: Date) -> Date {
        LocalDate(pickerDate, in: .current).atStartOfDay(in: timeZone)
    }
}

public struct EventDateRangePicker: View {
    @Binding var selection: EventDateRangeSelection

    public init(selection: Binding<EventDateRangeSelection>) {
        self._selection = selection
    }

    public var body: some View {
        #if os(iOS)
        DateRangePicker(
            startDate: $selection.startDate,
            endDate: $selection.endDate,
            bounds: selection.pickerBounds
        )

        if selection.hasDates {
            Button("Clear Dates") {
                selection.clear()
            }
        }
        #else
        Toggle("Start Date", isOn: $selection.hasStartDate.portableAnimation())
        if selection.hasStartDate {
            DatePicker(
                "Start Date",
                selection: $selection.startDateSelection,
                displayedComponents: .date
            )
            .labelsHidden()
            .environment(\.timeZone, selection.timeZone)
        }

        Toggle("Add End Date", isOn: $selection.hasEndDate.portableAnimation())
        if selection.hasEndDate {
            DatePicker(
                "End Date",
                selection: $selection.endDateSelection,
                displayedComponents: .date
            )
            .labelsHidden()
            .environment(\.timeZone, selection.timeZone)
        }
        #endif
    }
}
