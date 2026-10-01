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
    func scheduleViewerFiltersStagesAndPerformancesToDivision() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let mainID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcae")
        let workshopID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcaq")
        let scheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcae")
        let programID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcae")
        let concertID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcae")
        let workshopItemID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcaq")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let workshopDivision = ScheduleViewer.ScheduleDivision(
            category: "workshop"
        )
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: mainID, eventID: eventID, name: "Main", sortIndex: 1)
            try Self.insertCanonicalStage(
                db, id: workshopID, eventID: eventID, name: "Workshop",
                category: "workshop", sortIndex: 2
            )
            try Self.insertCanonicalSchedule(db, id: scheduleID, eventID: eventID, date: date)
            try Self.insertCanonicalProgram(db, id: programID, eventID: eventID, eventPlaces: [mainID, workshopID])
            try Self.insertCanonicalProgramItem(
                db, id: concertID, eventID: eventID, programID: programID,
                scheduleID: scheduleID, placeID: mainID, title: "Concert",
                startsAt: try #require(date.at(hour: 18, in: timeZone)),
                endsAt: try #require(date.at(hour: 19, in: timeZone))
            )
            try Self.insertCanonicalProgramItem(
                db, id: workshopItemID, eventID: eventID, programID: programID,
                scheduleID: scheduleID, placeID: workshopID, title: "Workshop",
                startsAt: try #require(date.at(hour: 20, in: timeZone)),
                endsAt: try #require(date.at(hour: 21, in: timeZone))
            )
        }

        let stages = try await database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }
        let performanceRows = try await database.read { db in
            try PerformanceRow.all(
                eventID: eventID,
                scheduleID: scheduleID
            )
            .fetchAll(db)
        }
        let visibleStages = ScheduleViewer.visibleStages(
            stages: stages,
            division: workshopDivision
        )
        let visiblePerformances = ScheduleViewer.visiblePerformances(
            performanceRows: performanceRows,
            scheduleID: scheduleID,
            stages: visibleStages
        )
        let timelineCards = ScheduleManyStagesAtOnceView.timelineCards(
            performanceRows: visiblePerformances,
            stages: visibleStages
        )

        #expect(visibleStages.map(\.id) == [workshopID])
        #expect(visiblePerformances.map(\.title) == ["Workshop"])
        #expect(timelineCards.map(\.performance.title) == ["Workshop"])
        #expect(timelineCards.map(\.stage.id) == [workshopID])
    }

    @Test
    func eventViewerBuildsScheduleDivisionTabsFromStageCategories() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let mainID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcae")
        let workshopID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcaq")
        let workshopDivision = ScheduleViewer.ScheduleDivision(category: "workshop")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: mainID, eventID: eventID, name: "Main", sortIndex: 1)
            try Self.insertCanonicalStage(
                db, id: workshopID, eventID: eventID, name: "Workshop",
                category: workshopDivision.category, sortIndex: 2
            )
        }
        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            EventViewer.State(eventID: eventID)
        }

        #expect(Array(state.installedFeatures.prefix(2).map(\.description)) == [
            "schedule",
            "schedule:workshop",
        ])
        #expect(state.scheduleViewers.map { $0.state.scheduleDivision.id } == ["schedule", "workshop"])
        #expect(state.installedFeatures.contains(.workspace) == false)
        #expect(state.eventWorkspace == nil)
    }

    @Test
    func `empty stage links open another schedule category`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let mainID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcae")
        let workshopID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcaq")
        let workshopDivision = ScheduleViewer.ScheduleDivision(category: "workshop")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Category Links")
            try Self.insertCanonicalStage(db, id: mainID, eventID: eventID, name: "Main", sortIndex: 1)
            try Self.insertCanonicalStage(
                db, id: workshopID, eventID: eventID, name: "Workshop",
                category: workshopDivision.category, sortIndex: 2
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EventViewer.State(eventID: eventID)) {
                EventViewer()
            }
        }
        let scheduleStore = try #require(
            store.spawn(\.scheduleViewers).first {
                $0.scheduleDivision == .schedule
            }
        )
        let singleStageStore = scheduleStore.spawn(\.singleStageAtOnce)

        await singleStageStore.send(
            .scheduleDivisionButtonTapped(workshopDivision)
        )?.value

        expectNoDifference(store.selectedFeature, .schedule(workshopDivision))

        await scheduleStore.spawn(\.manyStagesAtOnce).send(
            .scheduleDivisionButtonTapped(.schedule)
        )?.value

        expectNoDifference(store.selectedFeature, .schedule(.schedule))

        await scheduleStore.spawn(\.performanceList).send(
            .scheduleDivisionButtonTapped(workshopDivision)
        )?.value

        expectNoDifference(store.selectedFeature, .schedule(workshopDivision))
    }

    @Test
    func eventViewerStartsInAttendeeModeWhenAuthoringIsNotAllowed() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Attendee Mode Event")
        }

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            EventViewer.State(eventID: eventID)
        }

        #expect(state.authoringAccess == .attendee)
        #expect(!state.installedFeatures.contains(.workspace))
        #expect(state.installedFeatures.contains(.settings))
        #expect(state.eventWorkspace == nil)
        #expect(state.eventSettings?.eventID == eventID)
    }

    @Test
    func `signed out event settings unlocks canonical editing without a source workspace`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Editable Event")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.getSelectedOAuthSessionID = { nil }
        } operation: {
            Store(initialState: EventViewer.State(eventID: eventID)) {
                EventViewer()
            }
        }
        let settings = try #require(store.spawn(\.eventSettings))

        #expect(!store.showsAuthoringControls)
        #expect(store.authoringGrant == nil)
        #expect(store.eventWorkspace == nil)

        await settings.send(.enterEditingButtonTapped)?.value
        await waitForObservation { store.showsAuthoringControls }
        await settings.send(.exitEditingButtonTapped)?.value
        await waitForObservation { !store.showsAuthoringControls }

        await settings.send(.enterEditingButtonTapped)?.value
        await waitForObservation { store.showsAuthoringControls }
        let contactInfo = try #require(store.spawn(\.contactInfoViewer))
        await contactInfo.send(.editButtonTapped)?.value
        await waitForObservation { store.destination?.contactInfoForm != nil }

        #expect(store.destination?.contactInfoForm != nil)
        #expect(store.authoringGrant == nil)
        #expect(store.eventWorkspace == nil)
    }

    @Test
    func eventViewerStatePersistsSelectedSchedulePerEvent() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let scheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcae")
        let workshopDivision = ScheduleViewer.ScheduleDivision(category: "workshop")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalSchedule(
                db, id: scheduleID, eventID: eventID,
                date: try #require(LocalDate("2026-08-07"))
            )
        }

        let firstVisit = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: EventViewer.State(
                    eventID: eventID,
                    features: [
                        .schedule(.schedule),
                        .schedule(workshopDivision),
                    ]
                )
            ) {
                EventViewer()
            }
        }

        await firstVisit.modify {
            $0.eventViewerState.selectedScheduleID = scheduleID
        }?.value

        let storedState = try await database.read { db in
            try EventViewerStateRequest(eventID: eventID).fetch(db)
        }
        await firstVisit.dismount()

        let returnVisit = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(
                initialState: EventViewer.State(
                    eventID: eventID,
                    features: [
                        .schedule(.schedule),
                        .schedule(workshopDivision),
                    ]
                )
            ) {
                EventViewer()
            }
        }

        await waitForObservation {
            returnVisit.state.eventViewerState.selectedScheduleID == scheduleID
        }

        #expect(storedState.selectedScheduleID == scheduleID)
        #expect(returnVisit.state.eventViewerState.selectedScheduleID == scheduleID)
    }


}
