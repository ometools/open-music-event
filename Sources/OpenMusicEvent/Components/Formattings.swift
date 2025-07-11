//
//  Formattings.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/9/25.
//

import Foundation
import Dependencies

extension FormatStyle where Self == PerformanceTimeStyle {
    static var performanceTime: PerformanceTimeStyle {
        PerformanceTimeStyle()
    }
}
struct PerformanceTimeStyle: FormatStyle {
    typealias FormatInput = Range<Date>
    typealias FormatOutput = String

    func format(_ value: Range<Date>) -> String {

        var timeFormat = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute()
        timeFormat.timeZone = NSTimeZone.default

        return "\(value.lowerBound.formatted(timeFormat)) - \(value.upperBound.formatted(timeFormat))"
    }

}


extension FormatStyle where Self == DaySegmentStyle {
    static var daySegment: DaySegmentStyle {
        DaySegmentStyle()
    }
}

struct DaySegmentStyle: FormatStyle {
    typealias FormatInput = Date
    typealias FormatOutput = String

    func format(_ value: Date) -> String {
        @Dependency(\.calendar) var calendar

        var date = value
        let hour = calendar.component(.hour, from: date)

        let timeOfDay: String

        guard hour >= 0 && hour < 24 else { return "failed to format" }

        if hour < 6 {
            timeOfDay = "Night"

            // If we're in the early saturday AM, people feel like it's actually friday night still,
            // so show the date as the day before to reduce confusion (I think, this should probably be tested)
            date = calendar.date(byAdding: .day, value: -1, to: date)!
        } else if hour > 6 && hour < 12 {
            timeOfDay = "Morning"
        } else if hour > 12 &&  hour < 17 {
            timeOfDay = "Afternoon"
        } else if hour > 17 && hour < 20 {
            timeOfDay = "Evening"
        } else {
            timeOfDay = "Night"
        }

        return "\(value.formatted(.dateTime.weekday(.wide))) \(timeOfDay)"
    }
}
