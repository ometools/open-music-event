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
    func eventTimeZoneRefreshUpdatesEveryMountedScheduleSurface() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = canonicalRouteEventID
        let contributorID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcaj")
        let performanceID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcam")
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        let scheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcbd")
        let programID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcbf")
        let denver = try #require(TimeZone(identifier: "America/Denver"))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let friday = try #require(LocalDate("2026-08-07"))
        let startTime = try #require(friday.at(hour: 20, in: denver))
        let endTime = try #require(friday.at(hour: 21, in: denver))

        try await database.write { db in
            let event = try Event(
                id: selectedEventID, name: "Event Time Zone Refresh",
                createdAt: "2026-09-01T12:00:00Z", timeZone: denver
            )
            try Event.insert { event }.execute(db)
            try Self.insertCanonicalSchedule(db, id: scheduleID, eventID: selectedEventID, date: friday)
            try Self.insertCanonicalStage(db, id: stageID, eventID: selectedEventID, name: "Meadow")
            let contributor = try Contributor(
                id: contributorID, event: selectedEventID, name: "Artist",
                createdAt: "2026-09-01T12:00:00Z"
            )
            try Contributor.insert { contributor }.execute(db)
            try Self.insertCanonicalProgram(
                db, id: programID, eventID: selectedEventID, eventPlaces: [stageID]
            )
            try Self.insertCanonicalProgramItem(
                db, id: performanceID, eventID: selectedEventID,
                programID: programID, scheduleID: scheduleID, placeID: stageID,
                title: "Evening Set", startsAt: startTime, endsAt: endTime,
                credits: [ProgramItem.Credit(name: "Artist", contributor: contributorID)]
            )
        }

        try await withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
        } operation: {
            let store = Store(
                initialState: EventDetail.State(
                    eventID: selectedEventID,
                    features: [.schedule(.schedule), .contributors]
                )
            ) {
                EventDetail()
            }
            let scheduleStore = try #require(store.spawn(\.scheduleViewers).first)
            let contributorsStore = try #require(store.spawn(\.contributorsViewer))

            // The attendee opens a performance and contributor while the event uses Denver time.
            await scheduleStore.send(.performanceButtonTapped(performanceID))?.value
            let performanceDetail = try #require(
                scheduleStore.destination?.performanceDetail
            )
            await contributorsStore.send(.contributorButtonTapped(contributorID))?.value
            let contributorDetail = try #require(
                contributorsStore.destination?.contributorDetail
            )
            expectNoDifference(
                [
                    scheduleStore.timeZone?.identifier,
                    performanceDetail.timeZone?.identifier,
                    contributorDetail.timeZone?.identifier,
                ],
                Array(repeating: denver.identifier, count: 3)
            )

            // A source refresh changes the event's published time zone while those features remain mounted.
            try await database.write { db in
                try Event
                    .find(selectedEventID)
                    .update { $0.timeZone = losAngeles }
                    .execute(db)
            }
            await waitUntil {
                scheduleStore.timeZone == losAngeles
                    && performanceDetail.timeZone == losAngeles
                    && contributorDetail.timeZone == losAngeles
            }

            // Every attendee-facing renderer follows the refreshed event record together.
            expectNoDifference(
                [
                    scheduleStore.timeZone?.identifier,
                    performanceDetail.timeZone?.identifier,
                    contributorDetail.timeZone?.identifier,
                ],
                [
                    losAngeles.identifier,
                    losAngeles.identifier,
                    losAngeles.identifier,
                ]
            )
        }
    }

    @Test
    func coldLaunchHydrationKeepsDeviceTimeZoneOutOfNewPerformanceDetail() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = canonicalRouteEventID
        let contributorID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcaj")
        let performanceID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcam")
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        let scheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcbd")
        let programID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcbf")
        let eventTimeZone = try #require(TimeZone(identifier: "America/Denver"))
        let deviceTimeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let friday = try #require(LocalDate("2026-08-07"))
        let startTime = try #require(friday.at(hour: 15, in: eventTimeZone))
        let endTime = try #require(friday.at(hour: 16, in: eventTimeZone))

        try await withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
        } operation: {
            let store = Store(
                initialState: EventDetail.State(
                    eventID: selectedEventID,
                    features: [.schedule(.schedule), .contributors, .stages]
                )
            ) {
                EventDetail()
            }
            let scheduleStore = try #require(store.spawn(\.scheduleViewers).first)
            let singleStageStore: StoreOf<ScheduleSingleStageAtOnce> =
                scheduleStore.spawn(\.singleStageAtOnce)
            let manyStagesStore: StoreOf<ScheduleManyStagesAtOnce> =
                scheduleStore.spawn(\.manyStagesAtOnce)
            let performanceListStore: StoreOf<SchedulePerformanceList> =
                scheduleStore.spawn(\.performanceList)
            let eventSearchStore: StoreOf<EventSearch> = store.spawn(\.eventSearch)

            // An unavailable event row never turns the device zone into an event-time fallback.
            expectNoDifference(
                [
                    scheduleStore.timeZone?.identifier,
                    singleStageStore.timeZone?.identifier,
                    manyStagesStore.timeZone?.identifier,
                    performanceListStore.timeZone?.identifier,
                    eventSearchStore.timeZone?.identifier,
                ],
                Array<String?>(repeating: nil, count: 5)
            )

            // A restored shell can mount before its observed event row has hydrated.
            try await database.write { db in
                let event = try Event(
                    id: selectedEventID, name: "Cold Launch Time Zone",
                    createdAt: "2026-09-01T12:00:00Z", timeZone: eventTimeZone
                )
                try Event.insert { event }.execute(db)
                try Self.insertCanonicalSchedule(
                    db, id: scheduleID, eventID: selectedEventID, date: friday
                )
                try Self.insertCanonicalStage(
                    db, id: stageID, eventID: selectedEventID, name: "The Hallow"
                )
                let contributor = try Contributor(
                    id: contributorID, event: selectedEventID, name: "Woofax",
                    createdAt: "2026-09-01T12:00:00Z"
                )
                try Contributor.insert { contributor }.execute(db)
                try Self.insertCanonicalProgram(
                    db, id: programID, eventID: selectedEventID, eventPlaces: [stageID]
                )
                try Self.insertCanonicalProgramItem(
                    db, id: performanceID, eventID: selectedEventID,
                    programID: programID, scheduleID: scheduleID, placeID: stageID,
                    title: "Woofax", startsAt: startTime, endsAt: endTime,
                    credits: [ProgramItem.Credit(name: "Woofax", contributor: contributorID)]
                )
            }
            try await store.state.$event.load()

            expectNoDifference(
                [
                    scheduleStore.timeZone?.identifier,
                    singleStageStore.timeZone?.identifier,
                    manyStagesStore.timeZone?.identifier,
                    performanceListStore.timeZone?.identifier,
                    eventSearchStore.timeZone?.identifier,
                ],
                Array(repeating: eventTimeZone.identifier, count: 5)
            )
            let schedule = try #require(scheduleStore.schedules.first)
            expectNoDifference(
                ScheduleList.scheduleTitle(schedule, in: eventTimeZone),
                "Friday"
            )

            let contributorsStore = try #require(store.spawn(\.contributorsViewer))
            await contributorsStore.send(.contributorButtonTapped(contributorID))?.value
            let contributorDetail = try #require(
                contributorsStore.destination?.contributorDetail
            )
            expectNoDifference(
                contributorDetail.timeZone?.identifier,
                eventTimeZone.identifier
            )

            let stagesStore = try #require(store.spawn(\.eventPlaceList))
            await stagesStore.send(.stageButtonTapped(stageID))?.value
            let stageDetail = try #require(stagesStore.destination?.stageDetail)
            expectNoDifference(
                stageDetail.timeZone?.identifier,
                eventTimeZone.identifier
            )

            // Exercise the mounted reducer path used by a real schedule-row tap. The device zone
            // may determine whether an MDT suffix is shown, but it can never become the clock.
            await waitForObservation {
                store.spawn(\.scheduleViewers).contains { $0.scheduleDivision.programID == programID }
            }
            let programScheduleStore = try #require(
                store.spawn(\.scheduleViewers).first { $0.scheduleDivision.programID == programID }
            )
            await programScheduleStore.send(.performanceButtonTapped(performanceID))?.value

            let performanceDetail = try #require(
                programScheduleStore.destination?.performanceDetail
            )
            expectNoDifference(
                performanceDetail.timeZone?.identifier,
                eventTimeZone.identifier
            )
            let eventTimePresentation = try #require(
                performanceDetail.eventTimePresentation
            )
            let performance = try #require(performanceDetail.performance)
            expectNoDifference(
                eventTimePresentation.programItemRowTimeRange(
                    for: performance,
                    disclosure: .whenDeviceClockDiffers(deviceTimeZone)
                ),
                "3:00 - 4:00 pm (MDT)"
            )
        }
    }


}
