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
    func scheduleViewerStatePersistsModeAndStagePerDivision() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcae")
        let mainProgramID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcae")
        let mainDivision = ScheduleViewer.ScheduleDivision(
            programID: mainProgramID, title: "Schedule", eventPlaces: [stageID]
        )
        let workshopDivision = ScheduleViewer.ScheduleDivision(
            programID: canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcaq"),
            title: "Workshops"
        )
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: stageID, eventID: eventID, name: "Main")
            try Self.insertCanonicalProgram(
                db, id: mainProgramID, eventID: eventID,
                eventPlaces: [stageID], title: "Schedule"
            )
        }

        let firstVisit = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: ScheduleViewer.State(eventID: eventID, scheduleDivision: mainDivision)) {
                ScheduleViewer()
            }
        }

        await firstVisit.send(
            .scheduleKindButtonTapped(.allStagesAtOnce(.horizontal))
        )?.value
        await firstVisit.modify {
            $0.selectedStageID = stageID
        }?.value

        let storedState = try await database.read { db in
            try ScheduleViewerStateRequest(
                eventID: eventID,
                scheduleDivision: mainDivision
            )
            .fetch(db)
        }
        await firstVisit.dismount()

        let returnVisit = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: ScheduleViewer.State(eventID: eventID, scheduleDivision: mainDivision)) {
                ScheduleViewer()
            }
        }

        await waitForObservation {
            returnVisit.state.scheduleKind == .allStagesAtOnce(.horizontal)
                && returnVisit.state.selectedStageID == stageID
        }

        let workshopVisit = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: ScheduleViewer.State(
                    eventID: eventID,
                    scheduleDivision: workshopDivision
                )
            ) {
                ScheduleViewer()
            }
        }

        #expect(storedState.scheduleKind == .allStagesAtOnce(.horizontal))
        #expect(storedState.selectedStageID == stageID)
        #expect(returnVisit.state.scheduleKind == .allStagesAtOnce(.horizontal))
        #expect(returnVisit.state.selectedStageID == stageID)
        #expect(workshopVisit.state.scheduleKind == .singleStageAtOnce)
        #expect(workshopVisit.state.selectedStageID == nil)
        await workshopVisit.dismount()
    }

    @Test
    func scheduleViewerStatePersistenceMergesStaleFeatureChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcae")
        var storedState = ScheduleViewerState(
            eventID: eventID,
            scheduleDivision: .schedule
        )
        storedState.selectedStageID = stageID
        storedState.filteringFavorites = true
        storedState.scheduleKind = .allStagesAtOnce(.horizontal)
        storedState.syncScheduleKindStorage()
        let stateToStore = storedState
        try await database.write { db in
            try ScheduleViewerState.insert { stateToStore }.execute(db)
        }

        let staleState = ScheduleViewerState(
            eventID: eventID,
            scheduleDivision: .schedule
        )
        var changedState = staleState
        changedState.scheduleKind = .list
        let stateToPersist = changedState
        try await database.write { db in
            try ScheduleViewerState.persistChanges(
                from: staleState,
                to: stateToPersist,
                eventID: eventID,
                scheduleDivision: .schedule,
                in: db
            )
        }

        let mergedState = try await database.read { db in
            try ScheduleViewerStateRequest(
                eventID: eventID,
                scheduleDivision: .schedule
            )
            .fetch(db)
        }
        #expect(mergedState.selectedStageID == stageID)
        #expect(mergedState.filteringFavorites)
        #expect(mergedState.scheduleKind == .list)
    }

    @Test
    func scheduleViewerResolvedStageFallsBackToFirstOrderedStage() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let lateID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcae")
        let mainID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcaq")
        let missingID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcar")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: lateID, eventID: eventID, name: "Late", sortIndex: 2)
            try Self.insertCanonicalStage(db, id: mainID, eventID: eventID, name: "Main", sortIndex: 1)
        }

        let stages = try await database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }
        let orderedStages = ScheduleViewer.visibleStages(
            stages: stages,
            division: ScheduleViewer.ScheduleDivision(
                programID: canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcae"),
                title: "Schedule",
                eventPlaces: [mainID, lateID]
            )
        )

        #expect(
            ScheduleViewer.resolvedSelectedStageID(
                selectedStageID: nil,
                stages: orderedStages
            ) == mainID
        )
        #expect(
            ScheduleViewer.resolvedSelectedStageID(
                selectedStageID: missingID,
                stages: orderedStages
            ) == mainID
        )
        #expect(
            ScheduleViewer.resolvedSelectedStageID(
                selectedStageID: lateID,
                stages: orderedStages
            ) == lateID
        )
    }

    @Test
    func eventViewerNeedsStageDisambiguationOnlyWithMultipleStages() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let firstStageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcae")
        let secondStageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcaq")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(
                db, id: firstStageID, eventID: eventID, name: "Main", sortIndex: 1
            )
        }

        func state() -> EventViewer.State {
            withDependencies {
                $0.context = .test
                $0.defaultDatabase = database
            } operation: {
                EventViewer.State(eventID: eventID)
            }
        }

        #expect(state().needsStageDisambiguation == false)

        try await database.write { db in
            try Self.insertCanonicalStage(
                db, id: secondStageID, eventID: eventID, name: "Second", sortIndex: 2
            )
        }

        #expect(state().needsStageDisambiguation)
    }

    @Test
    func scheduleViewerBuildsDivisionsFromPrograms() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let mainID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcae")
        let workshopID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcaq")
        let secondWorkshopID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcar")
        let mainProgramID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcae")
        let workshopProgramID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcaq")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(
                db, id: mainID, eventID: eventID, name: "Main", sortIndex: 1
            )
            try Self.insertCanonicalStage(
                db, id: workshopID, eventID: eventID, name: "Workshop",
                sortIndex: 2
            )
            try Self.insertCanonicalStage(
                db, id: secondWorkshopID, eventID: eventID, name: "Second Workshop",
                sortIndex: 3
            )
            try Self.insertCanonicalProgram(
                db, id: mainProgramID, eventID: eventID,
                eventPlaces: [mainID], title: "Schedule"
            )
            try Self.insertCanonicalProgram(
                db, id: workshopProgramID, eventID: eventID,
                eventPlaces: [secondWorkshopID, workshopID], title: "Workshops"
            )
        }

        let records = try await database.read { db in
            (
                event: try Event.find(eventID).fetchOne(db),
                programs: try Program.where { $0.event.eq(eventID) }.fetchAll(db)
            )
        }
        let divisions = ScheduleViewer.scheduleDivisions(event: records.event, programs: records.programs)

        #expect(divisions.map(\.programID) == [mainProgramID, workshopProgramID])
        #expect(divisions.map(\.title) == ["Schedule", "Workshops"])
        #expect(divisions[1].eventPlaces == [secondWorkshopID, workshopID])
    }
}
