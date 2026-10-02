import Bluesky
import ATProto
import Clocks
import ComposableArchitecture2
import ComposableNotifications
import CustomDump
import Dependencies
import DependenciesTestSupport
import DebugSnapshots
import Foundation
import IssueReporting
import Observation
import OpenMusicEventDatabase
import OpenMusicEventAuthentication
import OpenMusicEventImages
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import Sharing
import SQLiteData
import SourceEditing
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Testing
import ATProto

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventEditors

extension NavigationTests {
    @Test
    func addScheduleDefaultsToEventStartDate() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let eventStartDate = try #require(LocalDate("2026-08-07"))
        let today = try #require(LocalDate("2026-06-01"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(today.at(hour: 12, in: timeZone))
        try await database.write { db in
            var event = try Event(
                id: eventID,
                name: "Event One",
                createdAt: "2026-09-01T12:00:00Z",
                timeZone: timeZone
            )
            event.start = .known(.day(Event.Day(value: eventStartDate)))
            try Event.insert { event }.execute(db)
        }
        var state = withDependencies {
            $0.context = .test
            $0.date = .constant(now)
            $0.defaultDatabase = database
        } operation: {
            EventDetail.State(eventID: eventID)
        }
        state.selectedFeature = .contributors

        withDependencies {
            $0.context = .test
            $0.date = .constant(now)
            $0.defaultDatabase = database
        } operation: {
            state.handleEditingIntent(.addSchedule(eventID))
        }

        let editSchedule = try #require(state.destination?.scheduleForm)
        expectNoDifference(state.selectedFeature, .contributors)
        expectNoDifference(editSchedule.scheduleDate, eventStartDate)
        expectNoDifference(editSchedule.customTitle, "")
        expectNoDifference(editSchedule.inferredTitle, "Friday")
    }

    @Test
    func scheduleNowDestinationPrefersSelectedCurrentScheduleAndActivePerformance() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let firstScheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcae")
        let selectedScheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcaq")
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcae")
        let programID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcae")
        let firstID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcae")
        let selectedID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcaq")
        let date = try #require(LocalDate("2026-08-07"))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Schedule Now")
            try Self.insertCanonicalSchedule(db, id: firstScheduleID, eventID: eventID, date: date)
            try Self.insertCanonicalSchedule(db, id: selectedScheduleID, eventID: eventID, date: date)
            try Self.insertCanonicalStage(db, id: stageID, eventID: eventID, name: "Meadow")
            try Self.insertCanonicalProgram(db, id: programID, eventID: eventID, eventPlaces: [stageID])
            try Self.insertCanonicalProgramItem(
                db, id: firstID, eventID: eventID, programID: programID,
                scheduleID: firstScheduleID, placeID: stageID, title: "First Active",
                startsAt: Date(timeIntervalSince1970: 100),
                endsAt: Date(timeIntervalSince1970: 300)
            )
            try Self.insertCanonicalProgramItem(
                db, id: selectedID, eventID: eventID, programID: programID,
                scheduleID: selectedScheduleID, placeID: stageID, title: "Selected Active",
                startsAt: Date(timeIntervalSince1970: 120),
                endsAt: Date(timeIntervalSince1970: 320)
            )
        }

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            ScheduleList.State(
                eventID: eventID,
                scheduleDivision: .init(programID: programID, title: "Schedule", eventPlaces: [stageID])
            )
        }
        let destination = state.currentTimeDestination(
            currentDate: Date(timeIntervalSince1970: 200),
            selectedScheduleID: selectedScheduleID,
            buffer: 3_600
        )

        expectNoDifference(destination?.scheduleID, selectedScheduleID)
        expectNoDifference(destination?.performanceID, selectedID)
    }

    @Test
    func scheduleNowDestinationSwitchesSchedulesAndTargetsNextThenLastPerformance() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let pastScheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcae")
        let currentScheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcaq")
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcae")
        let programID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcae")
        let pastID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcae")
        let openingID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcaq")
        let closingID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcar")
        let date = try #require(LocalDate("2026-08-07"))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Schedule Now")
            try Self.insertCanonicalSchedule(db, id: pastScheduleID, eventID: eventID, date: date)
            try Self.insertCanonicalSchedule(db, id: currentScheduleID, eventID: eventID, date: date)
            try Self.insertCanonicalStage(db, id: stageID, eventID: eventID, name: "Meadow")
            try Self.insertCanonicalProgram(db, id: programID, eventID: eventID, eventPlaces: [stageID])
            try Self.insertCanonicalProgramItem(
                db, id: pastID, eventID: eventID, programID: programID,
                scheduleID: pastScheduleID, placeID: stageID, title: "Past Set",
                startsAt: Date(timeIntervalSince1970: 0),
                endsAt: Date(timeIntervalSince1970: 3_600)
            )
            try Self.insertCanonicalProgramItem(
                db, id: openingID, eventID: eventID, programID: programID,
                scheduleID: currentScheduleID, placeID: stageID, title: "Opening",
                startsAt: Date(timeIntervalSince1970: 10_000),
                endsAt: Date(timeIntervalSince1970: 11_000)
            )
            try Self.insertCanonicalProgramItem(
                db, id: closingID, eventID: eventID, programID: programID,
                scheduleID: currentScheduleID, placeID: stageID, title: "Closing",
                startsAt: Date(timeIntervalSince1970: 12_000),
                endsAt: Date(timeIntervalSince1970: 13_000)
            )
        }

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            ScheduleList.State(
                eventID: eventID,
                scheduleDivision: .init(programID: programID, title: "Schedule", eventPlaces: [stageID])
            )
        }
        let nextDestination = state.currentTimeDestination(
            currentDate: Date(timeIntervalSince1970: 9_000),
            selectedScheduleID: pastScheduleID,
            buffer: 3_600
        )
        let lastDestination = state.currentTimeDestination(
            currentDate: Date(timeIntervalSince1970: 15_500),
            selectedScheduleID: pastScheduleID,
            buffer: 3_600
        )

        expectNoDifference(nextDestination?.scheduleID, currentScheduleID)
        expectNoDifference(nextDestination?.performanceID, openingID)
        expectNoDifference(lastDestination?.scheduleID, currentScheduleID)
        expectNoDifference(lastDestination?.performanceID, closingID)
    }

    @Test
    func scheduleNowDestinationHandlesOvernightRangesAndHidesOutsideRenderedTime() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let scheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcae")
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcae")
        let programID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcae")
        let itemID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcae")
        let date = try #require(LocalDate("2026-08-07"))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Schedule Now")
            try Self.insertCanonicalSchedule(db, id: scheduleID, eventID: eventID, date: date)
            try Self.insertCanonicalStage(db, id: stageID, eventID: eventID, name: "Meadow")
            try Self.insertCanonicalProgram(db, id: programID, eventID: eventID, eventPlaces: [stageID])
            try Self.insertCanonicalProgramItem(
                db, id: itemID, eventID: eventID, programID: programID,
                scheduleID: scheduleID, placeID: stageID, title: "Late Set",
                startsAt: Date(timeIntervalSince1970: 86_000),
                endsAt: Date(timeIntervalSince1970: 90_000)
            )
        }

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            ScheduleList.State(
                eventID: eventID,
                scheduleDivision: .init(programID: programID, title: "Schedule", eventPlaces: [stageID])
            )
        }
        let overnightDestination = state.currentTimeDestination(
            currentDate: Date(timeIntervalSince1970: 88_000),
            selectedScheduleID: nil,
            buffer: 3_600
        )
        let outsideDestination = state.currentTimeDestination(
            currentDate: Date(timeIntervalSince1970: 94_000),
            selectedScheduleID: nil,
            buffer: 3_600
        )
        let unavailableDestination = state.currentTimeDestination(
            currentDate: nil,
            selectedScheduleID: nil,
            buffer: 3_600
        )

        expectNoDifference(overnightDestination?.performanceID, itemID)
        #expect(outsideDestination == nil)
        #expect(unavailableDestination == nil)
    }
}
