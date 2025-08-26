//
//  File.swift
//  
//
//  Created by Woodrow Melling on 6/5/24.
//

import Foundation

private let formatter = DateFormatter()

public struct ScheduleTime: Codable, Sendable {
    var hour: Int
    var minute: Int

    init?(hour: Int = 0, minute: Int = 0) {
        guard (0..<48).contains(hour),
              (0..<60).contains(minute)
        else { return nil }

        self.hour = hour
        self.minute = minute
    }

    init(from date: Date) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        self.hour = components.hour ?? 0
        self.minute = components.minute ?? 0
    }

    init?(from timeString: String, using formatter: DateFormatter) {
        // Ensure timezone is set before parsing
        formatter.timeZone = .init(secondsFromGMT: 0)!
        
        guard let date = formatter.date(from: timeString) else {
            return nil
        }
        
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .init(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        self.hour = components.hour ?? 0
        self.minute = components.minute ?? 0
    }


    public init(from decoder: any Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        self = try ScheduleTimeConversion().apply(string)
    }

    

    var dateComponents: DateComponents {
        return DateComponents(timeZone: .gmt, year: 1970, hour: hour, minute: minute)
    }

    func formattedString(dateFormat: String = "HH:mm:ss") -> String {
        formatter.dateFormat = dateFormat
        formatter.timeZone = .gmt

        guard let date = Calendar.current.date(from: dateComponents) else {
            return ""
        }
        return formatter.string(from: date)
    }

    static let dayMinutes = 24 * 60 // Total minutes in a day

    var minutesAfterMidnight: Int {
        (hour * 60) + minute
    }

    func isAfter(_ other: Self, maximumDistance: Int = 720) -> Bool {
        return if minutesAfterMidnight == other.minutesAfterMidnight {
            false
        } else if self.minutesAfterMidnight > other.minutesAfterMidnight {
            true
        } else {
            other.minutesAfterMidnight - self.minutesAfterMidnight > maximumDistance
        }
    }

    func isAtSameTimeOrAfter(_ other: Self, maximumDistance: Int = 720) -> Bool {
        guard minutesAfterMidnight != other.minutesAfterMidnight
        else { return true }

        return isAfter(other, maximumDistance: maximumDistance)
    }
}

extension ScheduleTime: CustomStringConvertible {
    public var description: String {

        "\(hour):\(minute == 0 ? "00" : String(minute))"
    }
}

extension ScheduleTime: Comparable {

    public static func < (lhs: ScheduleTime, rhs: ScheduleTime) -> Bool {
        if lhs.hour != rhs.hour {
            return lhs.hour < rhs.hour
        }
        return lhs.minute < rhs.minute
    }
}


import Dependencies
extension CalendarDate {
    public func resolveTime(_ time: ScheduleTime, timeZone: TimeZone) -> Date {
        @Dependency(\.calendar) var calendar
        
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = time.hour % 24
        components.minute = time.minute
        components.second = 0
        components.timeZone = timeZone

        var tzCalendar = calendar
        tzCalendar.timeZone = timeZone

        var date = tzCalendar.date(from: components)!

        if time.hour >= 24 {
            date.addTimeInterval(24 * 60 * 60)
        }

        return date
    }
}


