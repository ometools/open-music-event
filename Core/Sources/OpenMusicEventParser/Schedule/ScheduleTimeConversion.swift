//
//  ScheduleTimeConversion.swift
//  OpenFestival
//
//  Created by Woodrow Melling on 10/28/24.
//

import FileTree
import Foundation

extension ScheduleTime: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = try! ScheduleTimeConversion().apply(value)
    }
}

struct ScheduleTimeConversion: Conversion {
    typealias Input = String
    typealias Output = ScheduleTime

    private let formats = ["h:mm a", "HH:mm", "h a", "h:mm", "h"]

    func apply(_ input: Input) throws(ScheduleTimeDecodingError) -> Output {

        let formatter = DateFormatter()

        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX") // Ensures consistent AM/PM parsing

        for format in formats {
            formatter.dateFormat = format
            if let time = ScheduleTime(from: input, using: formatter) {
                return time
            }
        }

        throw ScheduleTimeDecodingError.invalidDateString(input)
    }

    func unapply(_ output: ScheduleTime) throws  -> String {
        output.formattedString(dateFormat: formats.first!)
    }
}


struct ScheduleTimeDecodingError: LocalizedError, Equatable, Sendable {
    let rawText: String
    let errorDescription: String
    let failureReason: String
    let recoverySuggestion: String

    private init(
        raw: String,
        description: String,
        reason: String,
        suggestion: String
    ) {
        self.rawText = raw
        self.errorDescription = description
        self.failureReason = reason
        self.recoverySuggestion = suggestion
    }

    static let hourExceeds24Hours = { @Sendable (raw: String) in
        ScheduleTimeDecodingError(
            raw: raw,
            description: "Invalid 24-hour time format",
            reason: "The provided hour value exceeds 24 hours",
            suggestion: "Please provide a time between 00:00 and 23:59"
        )
    }

    static let hourExceeds12HourTimeFormat = { @Sendable (raw: String) in
        ScheduleTimeDecodingError(
            raw: raw,
            description: "Invalid 12-hour time format",
            reason: "The provided hour value exceeds 12 hours in 12-hour format",
            suggestion: "Please provide a time between 1:00 and 12:59, followed by AM/PM"
        )
    }

    static let minutesExceeds60Minutes = { @Sendable (raw: String) in
        ScheduleTimeDecodingError(
            raw: raw,
            description: "Invalid minutes value",
            reason: "The provided minutes value exceeds 60 minutes",
            suggestion: "Please provide a minutes value between 0 and 59"
        )
    }

    static let invalidDateString = { @Sendable (raw: String) in
        ScheduleTimeDecodingError(
            raw: raw,
            description: "Invalid time string format",
            reason: "The provided time string could not be parsed",
            suggestion: """
            Please provide time in one of the following formats:
            • HH:mm (24-hour format, e.g. "14:30")
            • h:mm a (12-hour format, e.g. "2:30 PM")
            • h a (12-hour format, e.g. "2 PM")
            • h:mm (hour and minutes, e.g. "2:30")
            • h (hour only, e.g. "2")
            """
        )
    }

    // Helper method to provide debug description
    var debugDescription: String {
        """
        ScheduleTimeDecodingError:
        Description: \(errorDescription)
        Reason: \(failureReason)
        Suggestion: \(recoverySuggestion)
        """
    }
}

// Extension to provide additional error context if needed
extension ScheduleTimeDecodingError {
    // Helper to create custom instances with the same structure
    static func custom(
        raw: String,
        description: String,
        reason: String,
        suggestion: String
    ) -> ScheduleTimeDecodingError {
        ScheduleTimeDecodingError(
            raw: raw,
            description: description,
            reason: reason,
            suggestion: suggestion
        )
    }
}
