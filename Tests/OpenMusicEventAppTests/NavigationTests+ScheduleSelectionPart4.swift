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
    func eventViewerStatePersistenceMergesStaleFeatureChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let scheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcae")
        let userScheduleID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-00000000e001")
        )
        var storedState = EventViewerState(id: eventID)
        storedState.selectedScheduleID = scheduleID
        storedState.didInitializeUserSchedules = true
        let stateToStore = storedState
        try await database.write { db in
            try UserSchedule.insert {
                UserSchedule(
                    id: userScheduleID,
                    eventID: eventID,
                    title: "Favorites"
                )
            }
            .execute(db)
            try EventViewerState.insert { stateToStore }.execute(db)
        }

        let staleState = EventViewerState(id: eventID)
        var changedState = staleState
        changedState.selectedUserScheduleID = userScheduleID
        let stateToPersist = changedState
        try await database.write { db in
            try EventViewerState.persistChanges(
                from: staleState,
                to: stateToPersist,
                in: db
            )
        }

        let mergedState = try await database.read { db in
            try EventViewerStateRequest(eventID: eventID).fetch(db)
        }
        #expect(mergedState.selectedScheduleID == scheduleID)
        #expect(mergedState.selectedUserScheduleID == userScheduleID)
        #expect(mergedState.didInitializeUserSchedules)
    }

    @Test
    func eventViewerStateObservationPreservesNewerLocalChanges() throws {
        let eventID = canonicalRouteEventID
        let scheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcae")
        let userScheduleID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-00000000e001")
        )
        var localState = EventViewerState(
            id: eventID,
            selectedUserScheduleID: userScheduleID,
            didInitializeUserSchedules: true
        )
        let stalePersistedState = EventViewerState(
            id: eventID,
            selectedScheduleID: scheduleID,
            didInitializeUserSchedules: true
        )

        localState.mergePersistedChanges(
            from: nil,
            to: stalePersistedState
        )

        #expect(localState.selectedScheduleID == scheduleID)
        #expect(localState.selectedUserScheduleID == userScheduleID)
        #expect(localState.didInitializeUserSchedules)
    }

}
