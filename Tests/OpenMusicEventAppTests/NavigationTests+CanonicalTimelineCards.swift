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
    func scheduleTimelineCardsWrapCanonicalItemsAndBuildBufferedRange() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let placeID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbb"
        )
        let scheduleID = canonicalRouteRecordID(
            "events.openmusic.schedule", "3mrdbziccpcbc"
        )
        let programID = canonicalRouteRecordID(
            "events.openmusic.program", "3mrdbziccpcbd"
        )
        let openingID = canonicalRouteRecordID(
            "events.openmusic.programItem", "3mrdbziccpcbe"
        )
        let closingID = canonicalRouteRecordID(
            "events.openmusic.programItem", "3mrdbziccpcbf"
        )
        let date = try #require(LocalDate("2026-08-07"))
        let zone = TimeZone.gmt
        let openingStart = try #require(date.at(hour: 18, in: zone))
        let openingEnd = try #require(date.at(hour: 19, in: zone))
        let closingStart = try #require(date.at(hour: 20, in: zone))
        let closingEnd = try #require(date.at(hour: 21, in: zone))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: placeID, eventID: eventID, name: "Meadow")
            try Self.insertCanonicalSchedule(
                db, id: scheduleID, eventID: eventID, date: date
            )
            try Self.insertCanonicalProgram(
                db, id: programID, eventID: eventID, eventPlaces: [placeID]
            )
            try Self.insertCanonicalProgramItem(
                db, id: closingID, eventID: eventID, programID: programID,
                scheduleID: scheduleID, placeID: placeID, title: "Closing",
                startsAt: closingStart, endsAt: closingEnd
            )
            try Self.insertCanonicalProgramItem(
                db, id: openingID, eventID: eventID, programID: programID,
                scheduleID: scheduleID, placeID: placeID, title: "Opening",
                startsAt: openingStart, endsAt: openingEnd
            )
        }

        let rows = try await database.read { db in
            try PerformanceRow.all(eventID: eventID, scheduleID: scheduleID)
                .fetchAll(db)
        }
        let performances = rows.map { $0.performance }
        let cards = performances.compactMap(SchedulePerformanceTimelineCard.init)
        let range = try #require(
            ScheduleStageTimelinePage.timeRange(
                for: performances, buffer: 30 * 60
            )
        )
        expectNoDifference(cards.map { $0.id }, [openingID, closingID])
        expectNoDifference(cards.first?.dateInterval.start, openingStart)
        expectNoDifference(cards.first?.dateInterval.end, openingEnd)
        expectNoDifference(range.start, openingStart.addingTimeInterval(-30 * 60))
        expectNoDifference(range.end, closingEnd.addingTimeInterval(30 * 60))
    }

}
