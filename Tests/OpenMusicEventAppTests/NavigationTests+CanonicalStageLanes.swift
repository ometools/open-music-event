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
    func manyStagesTimelineUsesCanonicalEventPlaceOrderForLanes() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let lateID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbb"
        )
        let mainID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbc"
        )
        let scheduleID = canonicalRouteRecordID(
            "events.openmusic.schedule", "3mrdbziccpcbd"
        )
        let programID = canonicalRouteRecordID(
            "events.openmusic.program", "3mrdbziccpcbe"
        )
        let lateItemID = canonicalRouteRecordID(
            "events.openmusic.programItem", "3mrdbziccpcbf"
        )
        let mainItemID = canonicalRouteRecordID(
            "events.openmusic.programItem", "3mrdbziccpcbg"
        )
        let date = try #require(LocalDate("2026-08-07"))
        let zone = TimeZone.gmt
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(
                db, id: lateID, eventID: eventID, name: "Late", sortIndex: 2
            )
            try Self.insertCanonicalStage(
                db, id: mainID, eventID: eventID, name: "Main", sortIndex: 1
            )
            try Self.insertCanonicalSchedule(
                db, id: scheduleID, eventID: eventID, date: date
            )
            try Self.insertCanonicalProgram(
                db, id: programID, eventID: eventID,
                eventPlaces: [mainID, lateID]
            )
            try Self.insertCanonicalProgramItem(
                db, id: lateItemID, eventID: eventID, programID: programID,
                scheduleID: scheduleID, placeID: lateID, title: "Late Set",
                startsAt: try #require(date.at(hour: 18, in: zone)),
                endsAt: try #require(date.at(hour: 19, in: zone))
            )
            try Self.insertCanonicalProgramItem(
                db, id: mainItemID, eventID: eventID, programID: programID,
                scheduleID: scheduleID, placeID: mainID, title: "Main Set",
                startsAt: try #require(date.at(hour: 20, in: zone)),
                endsAt: try #require(date.at(hour: 21, in: zone))
            )
        }

        let stages = try await database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }
        let visibleStages = ScheduleViewer.visibleStages(
            stages: stages, division: .schedule
        )
        let rows = try await database.read { db in
            try PerformanceRow.all(eventID: eventID, scheduleID: scheduleID)
                .fetchAll(db)
        }
        let cards = ScheduleManyStagesAtOnceView.timelineCards(
            performanceRows: rows, stages: visibleStages
        )
        let laneByItemID = Dictionary(
            uniqueKeysWithValues: cards.map { ($0.id, $0.groupWidth.lowerBound) }
        )
        expectNoDifference(visibleStages.map { $0.id }, [mainID, lateID])
        expectNoDifference(laneByItemID[mainItemID], 0)
        expectNoDifference(laneByItemID[lateItemID], 1)
        expectNoDifference(Set(cards.map { $0.groupWidth.upperBound }), Set([0, 1]))
    }

}
