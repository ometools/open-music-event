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
    func scheduledCanonicalPlacesLeadWhileEmptyPlacesRemainVisible() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let meadowID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbb"
        )
        let ampID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbc"
        )
        let groveID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbd"
        )
        let lakeID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbe"
        )
        let scheduleID = canonicalRouteRecordID(
            "events.openmusic.schedule", "3mrdbziccpcbf"
        )
        let programID = canonicalRouteRecordID(
            "events.openmusic.program", "3mrdbziccpcbg"
        )
        let date = try #require(LocalDate("2026-08-07"))
        let zone = TimeZone.gmt
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Sparse Friday")
            try Self.insertCanonicalStage(
                db, id: meadowID, eventID: eventID, name: "Meadow", sortIndex: 1
            )
            try Self.insertCanonicalStage(
                db, id: ampID, eventID: eventID, name: "Amp", sortIndex: 2
            )
            try Self.insertCanonicalStage(
                db, id: groveID, eventID: eventID, name: "Grove", sortIndex: 3
            )
            try Self.insertCanonicalStage(
                db, id: lakeID, eventID: eventID, name: "Lake", sortIndex: 4
            )
            try Self.insertCanonicalSchedule(
                db, id: scheduleID, eventID: eventID, date: date
            )
            try Self.insertCanonicalProgram(
                db, id: programID, eventID: eventID,
                eventPlaces: [meadowID, ampID, groveID, lakeID]
            )
            try Self.insertCanonicalProgramItem(
                db,
                id: canonicalRouteRecordID(
                    "events.openmusic.programItem", "3mrdbziccpcbh"
                ),
                eventID: eventID, programID: programID,
                scheduleID: scheduleID, placeID: ampID, title: "Amp Opening",
                startsAt: try #require(date.at(hour: 18, in: zone)),
                endsAt: try #require(date.at(hour: 19, in: zone))
            )
            try Self.insertCanonicalProgramItem(
                db,
                id: canonicalRouteRecordID(
                    "events.openmusic.programItem", "3mrdbziccpcbi"
                ),
                eventID: eventID, programID: programID,
                scheduleID: scheduleID, placeID: lakeID, title: "Lake Opening",
                startsAt: try #require(date.at(hour: 19, in: zone)),
                endsAt: try #require(date.at(hour: 20, in: zone))
            )
        }

        let places = try await database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }
        let visible = ScheduleViewer.visibleStages(
            stages: places,
            division: ScheduleViewer.ScheduleDivision(
                programID: programID,
                title: "Main Schedule",
                eventPlaces: [meadowID, ampID, groveID, lakeID]
            )
        )
        let performances = try await database.read { db in
            try PerformanceRow.all(eventID: eventID, scheduleID: scheduleID)
                .fetchAll(db).map { $0.performance }
        }
        expectNoDifference(
            visible.map { $0.id }, [meadowID, ampID, groveID, lakeID]
        )
        expectNoDifference(
            ScheduleViewer.unavailableStageIDs(
                stages: visible, performances: performances
            ),
            Set([meadowID, groveID])
        )
        let meadow = try #require(places.first { $0.id == meadowID })
        expectNoDifference(
            ScheduleViewer.emptyStageTitle(
                scheduleDivision: .schedule,
                scheduleTitle: "Friday",
                stage: meadow
            ),
            "No Schedule on Friday at Meadow"
        )
    }

}
