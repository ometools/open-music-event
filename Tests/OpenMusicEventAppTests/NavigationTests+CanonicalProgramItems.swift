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
    func scheduleViewerFetchesCanonicalProgramItemsForSelectedDayInOrder() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = canonicalRouteEventID
        let otherEventID = canonicalRouteRecordID(
            "events.openmusic.event", "3mrdbziccpcba"
        )
        let meadowID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbb"
        )
        let otherPlaceID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbc"
        )
        let fridayID = canonicalRouteRecordID(
            "events.openmusic.schedule", "3mrdbziccpcbd"
        )
        let saturdayID = canonicalRouteRecordID(
            "events.openmusic.schedule", "3mrdbziccpcbe"
        )
        let otherScheduleID = canonicalRouteRecordID(
            "events.openmusic.schedule", "3mrdbziccpcbf"
        )
        let programID = canonicalRouteRecordID(
            "events.openmusic.program", "3mrdbziccpcbg"
        )
        let otherProgramID = canonicalRouteRecordID(
            "events.openmusic.program", "3mrdbziccpcbh"
        )
        let friday = try #require(LocalDate("2026-08-07"))
        let saturday = try #require(LocalDate("2026-08-08"))
        let zone = TimeZone.gmt
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertCanonicalEvent(db, id: otherEventID, name: "Event Two")
            try Self.insertCanonicalStage(
                db, id: meadowID, eventID: selectedEventID, name: "Meadow"
            )
            try Self.insertCanonicalStage(
                db, id: otherPlaceID, eventID: otherEventID, name: "Other"
            )
            try Self.insertCanonicalSchedule(
                db, id: fridayID, eventID: selectedEventID, date: friday
            )
            try Self.insertCanonicalSchedule(
                db, id: saturdayID, eventID: selectedEventID, date: saturday
            )
            try Self.insertCanonicalSchedule(
                db, id: otherScheduleID, eventID: otherEventID, date: friday
            )
            try Self.insertCanonicalProgram(
                db, id: programID, eventID: selectedEventID,
                eventPlaces: [meadowID]
            )
            try Self.insertCanonicalProgram(
                db, id: otherProgramID, eventID: otherEventID,
                eventPlaces: [otherPlaceID]
            )
            try Self.insertCanonicalProgramItem(
                db,
                id: canonicalRouteRecordID(
                    "events.openmusic.programItem", "3mrdbziccpcbi"
                ),
                eventID: selectedEventID, programID: programID,
                scheduleID: fridayID, placeID: meadowID, title: "Closing",
                startsAt: try #require(friday.at(hour: 22, in: zone)),
                endsAt: try #require(friday.at(hour: 23, in: zone))
            )
            try Self.insertCanonicalProgramItem(
                db,
                id: canonicalRouteRecordID(
                    "events.openmusic.programItem", "3mrdbziccpcbj"
                ),
                eventID: selectedEventID, programID: programID,
                scheduleID: fridayID, placeID: meadowID, title: "Opening",
                startsAt: try #require(friday.at(hour: 18, in: zone)),
                endsAt: try #require(friday.at(hour: 19, in: zone))
            )
            try Self.insertCanonicalProgramItem(
                db,
                id: canonicalRouteRecordID(
                    "events.openmusic.programItem", "3mrdbziccpcbk"
                ),
                eventID: selectedEventID, programID: programID,
                scheduleID: saturdayID, placeID: meadowID, title: "Other Day",
                startsAt: try #require(saturday.at(hour: 17, in: zone)),
                endsAt: try #require(saturday.at(hour: 18, in: zone))
            )
            try Self.insertCanonicalProgramItem(
                db,
                id: canonicalRouteRecordID(
                    "events.openmusic.programItem", "3mrdbziccpcbl"
                ),
                eventID: otherEventID, programID: otherProgramID,
                scheduleID: otherScheduleID, placeID: otherPlaceID,
                title: "Other Event",
                startsAt: try #require(friday.at(hour: 16, in: zone)),
                endsAt: try #require(friday.at(hour: 17, in: zone))
            )
        }

        let items = try await database.read { db in
            try ScheduleViewer.performancesQuery(
                eventID: selectedEventID,
                scheduleID: fridayID
            ).fetchAll(db)
        }
        expectNoDifference(items.map { $0.title }, ["Opening", "Closing"])
    }

}
