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
    func scheduleViewerFetchesCanonicalFestivalDaysInOrder() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = canonicalRouteEventID
        let otherEventID = canonicalRouteRecordID(
            "events.openmusic.event", "3mrdbziccpcba"
        )
        let friday = try #require(LocalDate("2026-08-07"))
        let saturday = try #require(LocalDate("2026-08-08"))
        let earlyID = canonicalRouteRecordID(
            "events.openmusic.schedule", "3mrdbziccpcbb"
        )
        let lateID = canonicalRouteRecordID(
            "events.openmusic.schedule", "3mrdbziccpcbc"
        )
        let saturdayID = canonicalRouteRecordID(
            "events.openmusic.schedule", "3mrdbziccpcbd"
        )
        let otherID = canonicalRouteRecordID(
            "events.openmusic.schedule", "3mrdbziccpcbe"
        )
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertCanonicalEvent(db, id: otherEventID, name: "Event Two")
            try Self.insertCanonicalSchedule(
                db, id: lateID, eventID: selectedEventID, date: friday,
                title: "Friday Late"
            )
            try Self.insertCanonicalSchedule(
                db, id: saturdayID, eventID: selectedEventID, date: saturday,
                title: "Saturday"
            )
            try Self.insertCanonicalSchedule(
                db, id: earlyID, eventID: selectedEventID, date: friday,
                title: "Friday Early"
            )
            try Self.insertCanonicalSchedule(
                db, id: otherID, eventID: otherEventID, date: friday,
                title: "Other"
            )
        }

        let schedules = try await database.read { db in
            try ScheduleList.schedulesQuery(eventID: selectedEventID).fetchAll(db)
        }
        expectNoDifference(schedules.map { $0.id }, [earlyID, lateID, saturdayID])
    }

}
