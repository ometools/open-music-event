import Foundation
import SQLiteData

public struct LocalDate: Equatable, Hashable, Sendable, LosslessStringConvertible, RawRepresentable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard Self.isValid(year: year, month: month, day: day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(_ description: String) {
        guard description.count == 10 else { return nil }

        let parts = description.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }

        self.init(year: year, month: month, day: day)
    }

    public init?(rawValue: String) {
        self.init(rawValue)
    }

    public var rawValue: String { description }

    public var description: String {
        "\(year)-\(Self.twoDigits(month))-\(Self.twoDigits(day))"
    }

    public func atStartOfDay(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let date = calendar.date(
            from: DateComponents(
                timeZone: timeZone,
                year: year,
                month: month,
                day: day
            )
        )!

        return calendar.startOfDay(for: date)
    }

    public func at(
        hour: Int,
        minute: Int = 0,
        second: Int = 0,
        in timeZone: TimeZone
    ) -> Date? {
        guard (0..<24).contains(hour),
              (0..<60).contains(minute),
              (0..<60).contains(second)
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        return calendar.date(
            from: DateComponents(
                timeZone: timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second
            )
        )
    }

    private static func isValid(year: Int, month: Int, day: Int) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt

        let components = DateComponents(
            calendar: calendar,
            timeZone: .gmt,
            year: year,
            month: month,
            day: day
        )

        guard let date = calendar.date(from: components) else { return false }

        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == year && resolved.month == month && resolved.day == day
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

extension LocalDate: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)

        guard let localDate = Self(string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Not a valid local date: \"\(string)\""
            )
        }

        self = localDate
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension LocalDate: SQLiteType {
    public static var typeAffinity: SQLiteTypeAffinity { .text }
}

extension LocalDate: QueryRepresentable {}
extension LocalDate: QueryExpression {}
extension LocalDate: QueryBindable {
    public var queryBinding: QueryBinding { rawValue.queryBinding }
}

extension LocalDate: _OptionalPromotable {}
extension LocalDate: QueryDecodable {
    public init(decoder: inout some QueryDecoder) throws {
        let rawValue = try String(decoder: &decoder)
        guard let localDate = Self(rawValue: rawValue) else {
            throw InvalidLocalDateStringError(rawValue: rawValue)
        }
        self = localDate
    }
}

public struct InvalidLocalDateStringError: Error, Equatable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
