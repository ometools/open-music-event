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
        let workshopProgramID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcaq")
        let concertID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcae")
        let workshopItemID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcaq")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let workshopDivision = ScheduleList.ScheduleDivision(
            programID: workshopProgramID,
            title: "Workshops",
            eventPlaces: [workshopID]
        )
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: mainID, eventID: eventID, name: "Main", sortIndex: 1)
            try Self.insertCanonicalStage(
                db, id: workshopID, eventID: eventID, name: "Workshop",
                category: "workshop", sortIndex: 2
            )
            try Self.insertCanonicalSchedule(db, id: scheduleID, eventID: eventID, date: date)
            try Self.insertCanonicalProgram(db, id: programID, eventID: eventID, eventPlaces: [mainID])
            try Self.insertCanonicalProgram(
                db, id: workshopProgramID, eventID: eventID,
                eventPlaces: [workshopID], title: "Workshops"
            )
            try Self.insertCanonicalProgramItem(
                db, id: concertID, eventID: eventID, programID: programID,
                scheduleID: scheduleID, placeID: mainID, title: "Concert",
                startsAt: try #require(date.at(hour: 18, in: timeZone)),
                endsAt: try #require(date.at(hour: 19, in: timeZone))
            )
            try Self.insertCanonicalProgramItem(
                db, id: workshopItemID, eventID: eventID, programID: workshopProgramID,
                scheduleID: scheduleID, placeID: workshopID, title: "Workshop",
                startsAt: try #require(date.at(hour: 20, in: timeZone)),
                endsAt: try #require(date.at(hour: 21, in: timeZone))
            )
        }

        let stages = try await database.read { db in
            try ScheduleList.stagesQuery(eventID: eventID).fetchAll(db)
        }
        let performanceRows = try await database.read { db in
            try PerformanceRow.all(
                eventID: eventID,
                scheduleID: scheduleID
            )
            .fetchAll(db)
        }
        let visibleStages = ScheduleList.visibleStages(
            stages: stages,
            division: workshopDivision
        )
        let visiblePerformances = ScheduleList.visiblePerformances(
            performanceRows: performanceRows,
            scheduleID: scheduleID,
            division: workshopDivision
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
    func eventViewerBuildsScheduleDivisionTabsFromPrograms() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let mainID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcae")
        let workshopID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcaq")
        let mainProgramID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcae")
        let workshopProgramID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcaq")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: mainID, eventID: eventID, name: "Main", sortIndex: 1)
            try Self.insertCanonicalStage(
                db, id: workshopID, eventID: eventID, name: "Workshop",
                category: "other", sortIndex: 2
            )
            try Self.insertCanonicalProgram(
                db, id: mainProgramID, eventID: eventID,
                eventPlaces: [mainID], title: "Schedule"
            )
            try Self.insertCanonicalProgram(
                db, id: workshopProgramID, eventID: eventID,
                eventPlaces: [workshopID], title: "Workshops"
            )
        }
        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            EventDetail.State(eventID: eventID)
        }

        #expect(Array(state.installedFeatures.prefix(2).map(\.description)) == [
            "schedule:\(mainProgramID)",
            "schedule:\(workshopProgramID)",
        ])
        #expect(state.scheduleViewers.map { $0.state.scheduleDivision.programID } == [mainProgramID, workshopProgramID])
        #expect(state.installedFeatures.contains(.workspace) == false)
        #expect(state.canonicalWorkspace == nil)
    }

    @Test
    func `empty stage links open another program`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let mainID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcae")
        let workshopID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcaq")
        let mainProgramID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcae")
        let workshopProgramID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcaq")
        let mainDivision = ScheduleList.ScheduleDivision(
            programID: mainProgramID, title: "Schedule", eventPlaces: [mainID]
        )
        let workshopDivision = ScheduleList.ScheduleDivision(
            programID: workshopProgramID, title: "Workshops", eventPlaces: [workshopID]
        )
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Category Links")
            try Self.insertCanonicalStage(db, id: mainID, eventID: eventID, name: "Main", sortIndex: 1)
            try Self.insertCanonicalStage(
                db, id: workshopID, eventID: eventID, name: "Workshop",
                category: "other", sortIndex: 2
            )
            try Self.insertCanonicalProgram(
                db, id: mainProgramID, eventID: eventID,
                eventPlaces: [mainID], title: "Schedule"
            )
            try Self.insertCanonicalProgram(
                db, id: workshopProgramID, eventID: eventID,
                eventPlaces: [workshopID], title: "Workshops"
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EventDetail.State(eventID: eventID)) {
                EventDetail()
            }
        }
        let scheduleStore = try #require(
            store.spawn(\.scheduleViewers).first {
                $0.scheduleDivision == mainDivision
            }
        )
        let singleStageStore = scheduleStore.spawn(\.singleStageAtOnce)

        await singleStageStore.send(
            .scheduleDivisionButtonTapped(workshopDivision)
        )?.value

        expectNoDifference(store.selectedFeature, .schedule(workshopDivision))

        await scheduleStore.spawn(\.manyStagesAtOnce).send(
            .scheduleDivisionButtonTapped(mainDivision)
        )?.value

        expectNoDifference(store.selectedFeature, .schedule(mainDivision))

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
            EventDetail.State(eventID: eventID)
        }

        #expect(state.authoringAccess == .attendee)
        #expect(!state.installedFeatures.contains(.workspace))
        #expect(state.installedFeatures.contains(.settings))
        #expect(state.canonicalWorkspace == nil)
        #expect(state.eventSettings?.eventID == eventID)
    }

    @Test
    func `owner event settings unlocks canonical editing without a source workspace`() async throws {
        let database = try makePreparedDatabase()
        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpdbc"
        ))
        let ownerID = try #require(DID("did:plc:organizer"))
        let oauth = canonicalWorkspaceTestOAuthSession(actorID: ownerID)
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Editable Event")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.getSelectedOAuthSessionID = { oauth.accountID }
            $0.getOptionalDefaultSession = { oauth }
            $0.canonicalWorkspaceStorage = .fileBacked(
                rootURL: FileManager.default.temporaryDirectory
                    .appending(path: "OME-OwnerEditing-\(UUID())", directoryHint: .isDirectory)
            )
        } operation: {
            Store(initialState: EventDetail.State(eventID: eventID)) {
                EventDetail()
            }
        }
        let settings = try #require(store.spawn(\.eventSettings))

        #expect(!store.showsAuthoringControls)
        #expect(store.workspaceSession == nil)
        #expect(store.canonicalWorkspace == nil)

        await settings.send(.enterAuthoringButtonTapped)?.value
        await waitForObservation { store.showsAuthoringControls }
        await settings.send(.exitAuthoringButtonTapped)?.value
        await waitForObservation { !store.showsAuthoringControls }

        await settings.send(.enterAuthoringButtonTapped)?.value
        await waitForObservation { store.showsAuthoringControls }
        let contactInfo = try #require(store.spawn(\.contactInfoViewer))
        await contactInfo.send(.editButtonTapped)?.value
        await waitForObservation { store.destination?.contactInfoForm != nil }

        #expect(store.destination?.contactInfoForm != nil)
        #expect(store.workspaceSession != nil)
        #expect(store.canonicalWorkspace != nil)
    }

    @Test
    func eventViewerStatePersistsSelectedSchedulePerEvent() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let scheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcae")
        let workshopDivision = ScheduleList.ScheduleDivision(
            programID: canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcaq"),
            title: "Workshops"
        )
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
                initialState: EventDetail.State(
                    eventID: eventID,
                    features: [
                        .schedule(.schedule),
                        .schedule(workshopDivision),
                    ]
                )
            ) {
                EventDetail()
            }
        }

        await firstVisit.modify {
            $0.eventViewerState.selectedScheduleID = scheduleID
        }?.value

        let storedState = try await database.read { db in
            try EventDetailStateRequest(eventID: eventID).fetch(db)
        }
        await firstVisit.dismount()

        let returnVisit = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(
                initialState: EventDetail.State(
                    eventID: eventID,
                    features: [
                        .schedule(.schedule),
                        .schedule(workshopDivision),
                    ]
                )
            ) {
                EventDetail()
            }
        }

        await waitForObservation {
            returnVisit.state.eventViewerState.selectedScheduleID == scheduleID
        }

        #expect(storedState.selectedScheduleID == scheduleID)
        #expect(returnVisit.state.eventViewerState.selectedScheduleID == scheduleID)
    }


}
