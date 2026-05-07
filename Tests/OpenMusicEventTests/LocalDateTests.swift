import Foundation
import OpenMusicEventLexicon
import Testing

struct LocalDateTests {
    @Test
    func decodesAndEncodesISODateString() throws {
        let date = try #require(LocalDate("2025-08-29"))

        #expect(date.year == 2025)
        #expect(date.month == 8)
        #expect(date.day == 29)
        #expect(date.description == "2025-08-29")
        #expect(try JSONEncoder().encode(date) == Data(#""2025-08-29""#.utf8))
    }

    @Test
    func rejectsInvalidStrings() {
        #expect(LocalDate("2025-2-9") == nil)
        #expect(LocalDate("2025-13-01") == nil)
        #expect(LocalDate("2025-02-30") == nil)
        #expect(LocalDate("not-a-date") == nil)
    }

    @Test
    func resolvesStartOfDayInTimeZone() throws {
        let localDate = try #require(LocalDate("2025-08-29"))
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))

        let date = localDate.atStartOfDay(in: timeZone)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        #expect(components.year == 2025)
        #expect(components.month == 8)
        #expect(components.day == 29)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }

    @Test
    func resolvesExplicitLocalTimeInTimeZone() throws {
        let localDate = try #require(LocalDate("2025-08-29"))
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))

        let date = try #require(localDate.at(hour: 15, minute: 45, second: 30, in: timeZone))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        #expect(components.year == 2025)
        #expect(components.month == 8)
        #expect(components.day == 29)
        #expect(components.hour == 15)
        #expect(components.minute == 45)
        #expect(components.second == 30)
    }
}
