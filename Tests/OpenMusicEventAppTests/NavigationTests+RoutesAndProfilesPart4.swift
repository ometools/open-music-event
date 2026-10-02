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
    func contributorsViewerDeleteRemovesContributor() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let contributorID = canonicalRouteRecordID(
            "events.openmusic.contributor", "3mrdbziccpcae"
        )
        let stageID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcae"
        )
        let scheduleID = canonicalRouteRecordID(
            "events.openmusic.schedule", "3mrdbziccpcae"
        )
        let programID = canonicalRouteRecordID(
            "events.openmusic.program", "3mrdbziccpcae"
        )
        let itemID = canonicalRouteRecordID(
            "events.openmusic.programItem", "3mrdbziccpcae"
        )
        let date = try #require(LocalDate("2026-08-07"))

        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            let contributor = try Contributor(
                id: contributorID,
                event: eventID,
                name: "Amy",
                createdAt: "2026-09-01T12:00:00Z",
                subject: nil
            )
            try Contributor.insert { contributor }.execute(db)
            try Self.insertCanonicalStage(
                db, id: stageID, eventID: eventID, name: "Meadow",
                lineup: [contributorID]
            )
            try Self.insertCanonicalSchedule(
                db, id: scheduleID, eventID: eventID, date: date
            )
            try Self.insertCanonicalProgram(
                db, id: programID, eventID: eventID, eventPlaces: [stageID]
            )
            try Self.insertCanonicalProgramItem(
                db, id: itemID, eventID: eventID, programID: programID,
                scheduleID: scheduleID, placeID: stageID,
                title: "Opening",
                startsAt: Date(timeIntervalSince1970: 0),
                endsAt: Date(timeIntervalSince1970: 3_600),
                credits: [ProgramItem.Credit(name: "Amy", contributor: contributorID)]
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: ContributorList.State(eventID: eventID)) {
                ContributorList()
            }
        }

        await store.send(.deleteContributors([contributorID]))?.value

        #expect(store.state.errorMessage == nil)
        let records = try await database.read { db in
            (
                contributor: try Contributor.find(contributorID).fetchOne(db),
                item: try ProgramItem.find(itemID).fetchOne(db),
                stage: try EventPlace.find(stageID).fetchOne(db)
            )
        }
        #expect(records.contributor == nil)
        #expect(records.item?.credits?.first?.contributor == nil)
        guard case let .known(.stage(stageUse)) = records.stage?.kind else {
            Issue.record("Expected a canonical stage")
            return
        }
        #expect(stageUse.lineup == nil)
    }

}
