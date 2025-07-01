//
//  ScheduleTimeConversionTests.swift
//  OpenFestival
//
//  Created by Woodrow Melling on 10/28/24.
//


import Testing

@testable import OpenMusicEventParser

struct ScheduleTimeConversionTests {
    var conversion = ScheduleTimeConversion()
    
    // MARK: - Apply Tests
    
    @Test("Standard time parsing")
    func standardTimeParsing() throws {
        let time1 = try conversion.apply("9:30 AM")
        #expect(time1.hour == 9)
        #expect(time1.minute == 30)
        
        let time2 = try conversion.apply("2:45 PM")
        #expect(time2.hour == 14)
        #expect(time2.minute == 45)
    }
    
    @Test("24-hour time parsing")
    func militaryTimeParsing() throws {
        let time1 = try conversion.apply("14:30")
        #expect(time1.hour == 14)
        #expect(time1.minute == 30)
        
        let time2 = try conversion.apply("08:15")
        #expect(time2.hour == 8)
        #expect(time2.minute == 15)
    }
    
    @Test("Hour only parsing")
    func hourOnlyParsing() throws {
        let time = try conversion.apply("3")
        #expect(time.hour == 3)
        #expect(time.minute == 0)
    }
    
    @Test("Hour with period parsing")
    func hourWithPeriodParsing() throws {
        let time1 = try conversion.apply("3 PM")
        #expect(time1.hour == 15)
        #expect(time1.minute == 0)
        
        let time2 = try conversion.apply("11 AM")
        #expect(time2.hour == 11)
        #expect(time2.minute == 0)
    }
    
    @Test("Hour and minute parsing")
    func hourAndMinuteParsing() throws {
        let time = try conversion.apply("3:30")
        #expect(time.hour == 3)
        #expect(time.minute == 30)
    }
    
    @Test("Invalid time handling")
    func invalidTimeHandling() throws {
        #expect(throws: ScheduleTimeDecodingError.self) {
            _ = try conversion.apply("25:00")
        }
        
        #expect(throws: ScheduleTimeDecodingError.self) {
            _ = try conversion.apply("9:60 AM")
        }
        
        #expect(throws: ScheduleTimeDecodingError.self) {
            _ = try conversion.apply("invalid")
        }
        
        #expect(throws: ScheduleTimeDecodingError.self) {
            _ = try conversion.apply("13 PM")
        }
    }
    
    // MARK: - Unapply Tests
    
    @Test("Time to string conversion")
    func timeToStringConversion() throws {
        let morning = ScheduleTime(hour: 9, minute: 30)!
        let afternoon = ScheduleTime(hour: 14, minute: 45)!

        let morningString = try conversion.unapply(morning)
        let afternoonString = try conversion.unapply(afternoon)

        #expect(morningString == "9:30 AM")
        #expect(afternoonString == "2:45 PM")
    }
    
    @Test("Zero minute formatting")
    func zeroMinuteFormatting() throws {
        let time = ScheduleTime(hour: 15, minute: 0)!
        let result = try conversion.unapply(time)
        #expect(result == "3:00 PM")
    }
}
