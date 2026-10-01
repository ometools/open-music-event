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
    func performanceRowContributorQueryReturnsContributorPerformancesAndStages() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = canonicalRouteEventID
        let contributorID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcaj")
        let meadowID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        let tentID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcap")
        let scheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcbd")
        let programID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcbf")
        let meadowSetID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcam")
        let tentSetID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcbn")
        let date = try #require(LocalDate("2026-08-07"))
        let zone = TimeZone.gmt

        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: selectedEventID, name: "Event One")
            let contributor = try Contributor(
                id: contributorID, event: selectedEventID, name: "Artist",
                createdAt: "2026-09-01T12:00:00Z"
            )
            try Contributor.insert { contributor }.execute(db)
            try Self.insertCanonicalSchedule(db, id: scheduleID, eventID: selectedEventID, date: date)
            try Self.insertCanonicalStage(db, id: meadowID, eventID: selectedEventID, name: "Meadow")
            try Self.insertCanonicalStage(db, id: tentID, eventID: selectedEventID, name: "Tent")
            try Self.insertCanonicalProgram(
                db, id: programID, eventID: selectedEventID, eventPlaces: [meadowID, tentID]
            )
            try Self.insertCanonicalProgramItem(
                db, id: meadowSetID, eventID: selectedEventID,
                programID: programID, scheduleID: scheduleID, placeID: meadowID,
                title: "Meadow Set",
                startsAt: try #require(date.at(hour: 18, in: zone)),
                endsAt: try #require(date.at(hour: 19, in: zone)),
                credits: [ProgramItem.Credit(name: "Artist", contributor: contributorID)]
            )
            try Self.insertCanonicalProgramItem(
                db, id: tentSetID, eventID: selectedEventID,
                programID: programID, scheduleID: scheduleID, placeID: tentID,
                title: "Tent Set",
                startsAt: try #require(date.at(hour: 20, in: zone)),
                endsAt: try #require(date.at(hour: 21, in: zone))
            )
        }

        let rows = try await database.read { db in
            try PerformanceRow
                .forContributor(contributorID: contributorID, eventID: selectedEventID)
                .fetchAll(db)
        }

        #expect(rows.map(\.performanceID) == [meadowSetID])
        #expect(rows.map(\.title) == ["Meadow Set"])
        #expect(rows.first?.stage?.name == "Meadow")
    }

    @Test
    func performanceRowTimeLabelsUseEventTimeZoneAndAssignedFestivalDay() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let friday = try #require(LocalDate("2026-08-07"))
        let saturday = try #require(LocalDate("2026-08-08"))
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        let scheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcbd")
        let programID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcbf")
        let eveningID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcam")
        let lateNightID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcbn")

        try await database.write { db in
            let event = try Event(
                id: eventID, name: "Event One",
                createdAt: "2026-09-01T12:00:00Z", timeZone: timeZone
            )
            try Event.insert { event }.execute(db)
            try Self.insertCanonicalSchedule(db, id: scheduleID, eventID: eventID, date: friday)
            try Self.insertCanonicalStage(db, id: stageID, eventID: eventID, name: "Meadow")
            try Self.insertCanonicalProgram(db, id: programID, eventID: eventID, eventPlaces: [stageID])
            try Self.insertCanonicalProgramItem(
                db, id: eveningID, eventID: eventID,
                programID: programID, scheduleID: scheduleID, placeID: stageID,
                title: "Evening Set",
                startsAt: try #require(friday.at(hour: 18, in: timeZone)),
                endsAt: try #require(friday.at(hour: 19, in: timeZone))
            )
            try Self.insertCanonicalProgramItem(
                db, id: lateNightID, eventID: eventID,
                programID: programID, scheduleID: scheduleID, placeID: stageID,
                title: "Late Night",
                startsAt: try #require(saturday.at(hour: 1, minute: 30, in: timeZone)),
                endsAt: try #require(saturday.at(hour: 2, minute: 30, in: timeZone))
            )
        }

        let rows = try await database.read { db in
            try PerformanceRow
                .all(eventID: eventID, scheduleID: scheduleID)
                .fetchAll(db)
        }
        let eveningPerformance = try #require(rows.first?.performance)
        let afterMidnightPerformance = try #require(rows.dropFirst().first?.performance)
        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            ScheduleViewer.State(eventID: eventID)
        }
        let eventTimePresentation = try #require(state.eventTimePresentation)

        expectNoDifference(
            eventTimePresentation.programItemRowTimeRange(for: eveningPerformance),
            "6:00 - 7:00 pm"
        )
        expectNoDifference(
            eventTimePresentation.daySegment(for: try #require(eveningPerformance.startDate)),
            "Friday Evening"
        )
        expectNoDifference(
            eventTimePresentation.programItemRowTimeRange(for: afterMidnightPerformance),
            "1:30 - 2:30 am"
        )
        expectNoDifference(
            eventTimePresentation.daySegment(for: try #require(afterMidnightPerformance.startDate)),
            "Friday Night"
        )
        #expect(
            eventTimePresentation.formattedTimeRange(
                start: try #require(friday.at(hour: 23, minute: 30, in: timeZone)),
                end: try #require(saturday.at(hour: 1, minute: 15, in: timeZone))
            ) == "11:30 pm - 1:15 am"
        )
    }

    @Test
    func eventTimeZoneDisclosureUsesTheEffectiveOffsetAndSeasonalAbbreviation() throws {
        let eventTimeZone = try #require(TimeZone(identifier: "America/Denver"))
        let matchingDeviceTimeZone = try #require(TimeZone(identifier: "America/Edmonton"))
        let differentDeviceTimeZone = try #require(TimeZone(identifier: "America/Vancouver"))
        let summer = try #require(LocalDate("2026-09-04"))
        let winter = try #require(LocalDate("2026-01-02"))
        let summerStart = try #require(summer.at(hour: 18, in: eventTimeZone))
        let summerEnd = try #require(summer.at(hour: 19, in: eventTimeZone))
        let winterStart = try #require(winter.at(hour: 18, in: eventTimeZone))
        let winterEnd = try #require(winter.at(hour: 19, in: eventTimeZone))
        let eventTimePresentation = EventTimePresentation(timeZone: eventTimeZone)

        // A visitor whose device clock disagrees sees the event's current abbreviation.
        expectNoDifference(
            eventTimePresentation.formattedTimeRange(
                start: summerStart,
                end: summerEnd,
                disclosure: .whenDeviceClockDiffers(differentDeviceTimeZone)
            ),
            "6:00 - 7:00 pm (MDT)"
        )

        // Different zone identifiers do not add noise when both clocks agree.
        expectNoDifference(
            eventTimePresentation.formattedTimeRange(
                start: summerStart,
                end: summerEnd,
                disclosure: .whenDeviceClockDiffers(matchingDeviceTimeZone)
            ),
            "6:00 - 7:00 pm"
        )

        // The event abbreviation follows daylight-saving rules at the performance date.
        expectNoDifference(
            eventTimePresentation.formattedTimeRange(
                start: winterStart,
                end: winterEnd,
                disclosure: .whenDeviceClockDiffers(differentDeviceTimeZone)
            ),
            "6:00 - 7:00 pm (MST)"
        )

        // Dense schedule surfaces still render the event clock without repeating a suffix.
        expectNoDifference(
            eventTimePresentation.formattedTimeRange(
                start: summerStart,
                end: summerEnd,
                disclosure: .never
            ),
            "6:00 - 7:00 pm"
        )

        // The feature supplies event-clock labels to the reusable timeline components.
        expectNoDifference(
            eventTimePresentation.hourLabel(for: summerStart),
            "6pm"
        )
        expectNoDifference(
            eventTimePresentation.currentTimeLabel(
                for: summerStart,
                disclosure: .whenDeviceClockDiffers(differentDeviceTimeZone)
            ),
            "6:00p (MDT)"
        )
        expectNoDifference(
            eventTimePresentation.formattedTime(
                for: summerStart,
                disclosure: .whenDeviceClockDiffers(differentDeviceTimeZone)
            ),
            "6:00 pm (MDT)"
        )
    }


}
