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
    func scheduleViewerStageFallbackIsScopedToDivision() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let mainID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        let workshopID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcap")
        let workshopDivision = ScheduleList.ScheduleDivision(
            programID: canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcap"),
            title: "Workshops",
            eventPlaces: [workshopID]
        )
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: mainID, eventID: eventID, name: "Main", sortIndex: 1)
            try Self.insertCanonicalStage(db, id: workshopID, eventID: eventID, name: "Workshop", sortIndex: 2)
        }

        var state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = ScheduleList.State(
                eventID: eventID,
                scheduleDivision: workshopDivision
            )
            state.selectedStageID = mainID
            return state
        }

        #expect(state.visibleStages.map(\.id) == [workshopID])
        #expect(state.resolvedSelectedStageID == workshopID)
        #expect(state.selectedStageID == workshopID)

        state.selectedStageID = mainID

        #expect(state.scheduleViewerState.selectedStageID == workshopID)
    }

    @Test
    func singleStageScheduleSelectionBindingNormalizesToVisibleStage() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let mainID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        let workshopID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcap")
        let workshopDivision = ScheduleList.ScheduleDivision(
            programID: canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcap"),
            title: "Workshops",
            eventPlaces: [workshopID]
        )
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: mainID, eventID: eventID, name: "Main", sortIndex: 1)
            try Self.insertCanonicalStage(db, id: workshopID, eventID: eventID, name: "Workshop", sortIndex: 2)
        }

        var state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = ScheduleSingleStageAtOnce.State(
                eventID: eventID,
                scheduleDivision: workshopDivision
            )
            state.scheduleViewerState.selectedStageID = mainID
            return state
        }

        #expect(state.visibleStages.map(\.id) == [workshopID])
        #expect(state.selectedStageID == workshopID)
        #expect(state.resolvedSelectedStageID == workshopID)
        #expect(state.scheduleViewerState.selectedStageID == mainID)

        state.selectedStageID = state.selectedStageID

        #expect(state.scheduleViewerState.selectedStageID == workshopID)
    }

    @MainActor
    @Test
    func singleStageMountNormalizesSelectionBeforeViewObservation() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let mainID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        let workshopID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcap")
        let workshopDivision = ScheduleList.ScheduleDivision(
            programID: canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcap"),
            title: "Workshops",
            eventPlaces: [workshopID]
        )
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: mainID, eventID: eventID, name: "Main", sortIndex: 1)
            try Self.insertCanonicalStage(db, id: workshopID, eventID: eventID, name: "Workshop", sortIndex: 2)
        }

        // The persisted selection points outside the visible workshop division.
        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = ScheduleSingleStageAtOnce.State(
                eventID: eventID,
                scheduleDivision: workshopDivision
            )
            state.scheduleViewerState.selectedStageID = mainID
            return state
        }

        // Feature mounting must repair query-loaded selection before SwiftUI observes the store.
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: state) {
                ScheduleSingleStageAtOnce()
            } changes: {
                $0.scheduleViewerState.selectedStageID = workshopID
            }
        }

        #expect(store.state.scheduleViewerState.selectedStageID == workshopID)
    }

    @Test
    func scheduleViewerPerformanceTapPresentsDetail() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let performanceID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcam")
        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            let store = Store(initialState: ScheduleList.State(eventID: eventID)) {
                ScheduleList()
            }
            await store.send(.performanceButtonTapped(performanceID))?.value

            #expect(store.destination?.performanceDetail?.performanceID == performanceID)
            expectNoDifference(
                store.destination?.performanceDetail?.eventID,
                eventID
            )
        }
    }

    @Test
    func performanceDetailQueriesCoreFields() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        let scheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcbd")
        let programID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcbf")
        let performanceID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcam")
        let amyID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcaj")
        let zaraID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcas")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: stageID, eventID: eventID, name: "Meadow")
            try Self.insertCanonicalSchedule(db, id: scheduleID, eventID: eventID, date: date)
            try Self.insertCanonicalProgram(db, id: programID, eventID: eventID, eventPlaces: [stageID])
            let amy = try Contributor(
                id: amyID, event: eventID, name: "Amy", createdAt: "2026-09-01T12:00:00Z"
            )
            let zara = try Contributor(
                id: zaraID, event: eventID, name: "Zara", createdAt: "2026-09-01T12:00:00Z"
            )
            try Contributor.insert { amy }.execute(db)
            try Contributor.insert { zara }.execute(db)
            try Self.insertCanonicalProgramItem(
                db, id: performanceID, eventID: eventID,
                programID: programID, scheduleID: scheduleID, placeID: stageID,
                title: "Opening",
                startsAt: try #require(date.at(hour: 18, in: timeZone)),
                endsAt: try #require(date.at(hour: 19, in: timeZone))
            )
            var item = try #require(try ProgramItem.find(performanceID).fetchOne(db))
            item.description = "First set"
            item.credits = [
                ProgramItem.Credit(name: "Amy", contributor: amyID),
                ProgramItem.Credit(name: "Zara", contributor: zaraID),
            ]
            try ProgramItem.upsert { item }.execute(db)
        }

        let detail = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            ProgramItemDetail.State(performanceID: performanceID, eventID: eventID)
        }

        #expect(detail.performance?.title == "Opening")
        #expect(detail.performance?.description == "First set")
        #expect(detail.schedule?.id == scheduleID)
        #expect(detail.stage?.name == "Meadow")
        expectNoDifference(detail.displayedContributorCredits.map { $0.credit.name }, ["Amy", "Zara"])
        expectNoDifference(detail.displayedContributors.map(\.name), ["Amy", "Zara"])
    }


}
