//
//  File.swift
//
//
//  Created by Woody on 2/20/22.
//

import Foundation
import SkipFuse
import Dependencies

public extension Date {
    func startOfDay(dayStartsAtNoon: Bool) -> Date {

        let calendar = Calendar.current


        if dayStartsAtNoon {
            // Subtract 12 hours to get the correct day if the day starts at noon
            let noonAdjustedDate = calendar.date(byAdding: .hour, value: -12, to: self)!
            // Get the start of the day for the adjusted date, then add 12 hours back
            let startOfDay = calendar.startOfDay(for: noonAdjustedDate)
            return calendar.date(byAdding: .hour, value: 12, to: startOfDay)!
        } else {
            // Simply return the start of the day
            return calendar.startOfDay(for: self)
        }
    }

    static func - (lhs: Date, rhs: Date) -> TimeInterval {
        return lhs.timeIntervalSinceReferenceDate - rhs.timeIntervalSinceReferenceDate
    }

    func round(precision: TimeInterval) -> Date {
        return round(precision: precision, rule: .toNearestOrAwayFromZero)
    }

    func ceil(precision: TimeInterval) -> Date {
        return round(precision: precision, rule: .up)
    }

    func floor(precision: TimeInterval) -> Date {
        return round(precision: precision, rule: .down)
    }

    func round(precision: TimeInterval, rule: FloatingPointRoundingRule) -> Date {
        let seconds = (self.timeIntervalSinceReferenceDate / precision).rounded(rule) *  precision;
        return Date(timeIntervalSinceReferenceDate: seconds)
    }
}

public extension Date {
    func toY(containerHeight: CGFloat, dayStartsAtNoon: Bool) -> CGFloat {

        @Dependency(\.calendar) var calendar
        var hoursIntoTheDay = calendar.component(.hour, from: self)
        let minutesIntoTheHour = calendar.component(.minute, from: self)

        if dayStartsAtNoon {
            // Shift the hour start by 12 hours, we're doing nights, not days
            hoursIntoTheDay = (hoursIntoTheDay + 12) % 24
        }

        let hourInSeconds = hoursIntoTheDay * 60 * 60
        let minuteInSeconds = minutesIntoTheHour * 60

        return secondsToY(hourInSeconds + minuteInSeconds, containerHeight: containerHeight)
    }
}

public extension Date {

    /// Create a date from specified parameters
    ///
    /// - Parameters:
    ///   - year: The desired year
    ///   - month: The desired month
    ///   - day: The desired day
    /// - Returns: A `Date` object
    init?(year: Int = 1970, month: Int = 0, day: Int = 0, hour: Int = 0, minute: Int = 0) {
        let calendar = Calendar.current
        var dateComponents = DateComponents()

        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = hour
        dateComponents.minute = minute

        if let date = calendar.date(from: dateComponents) {
            self = date
        } else {
            return nil
        }
    }
}


/// Get the y placement for a specific numbers of seconds
public func secondsToY(_ seconds: Int, containerHeight: CGFloat) -> CGFloat {
    let dayInSeconds: CGFloat = 86400
    let progress = CGFloat(seconds) / dayInSeconds
    return containerHeight * progress
}
