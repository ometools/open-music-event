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
    func contributorProfileUnhydratedDoesNotRequireActorCacheTables() async throws {
        let database = try makeCoreDatabase()
        let selectedEventID = canonicalRouteEventID
        let actor = try #require(DID("did:plc:alice123"))
        let contributorID = canonicalRouteRecordID(
            "events.openmusic.contributor", "3mrdbziccpcaj"
        )
        let createdAt = ATProto.DateTime(rawValue: "2026-08-01T12:00:00Z")
        let event = try Event(
            id: selectedEventID,
            name: "Event One",
            createdAt: createdAt,
            timeZone: .gmt
        )
        let contributor = try Contributor(
            id: contributorID,
            event: selectedEventID,
            name: "Alice",
            createdAt: createdAt,
            subject: actor
        )

        try await database.write { db in
            try Event.insert { event }.execute(db)
            try Contributor.insert { contributor }.execute(db)
        }

        let profiles = try await database.read { db in
            try ContributorProfile
                .all(eventID: selectedEventID, hydration: .none)
                .fetchAll(db)
        }

        let profile = try #require(profiles.first)
        #expect(profiles.count == 1)
        #expect(profile.id == contributorID)
        #expect(profile.name == "Alice")
        #expect(profile.contributorActor == actor)
        #expect(profile.handle == nil)
        #expect(profile.subtitle == nil)

        await #expect(throws: (any Error).self) {
            try await database.read { db in
                try ContributorProfile
                    .all(eventID: selectedEventID, hydration: .bskyActorProfile)
                    .fetchAll(db)
            }
        }
    }

    @Test
    func contributorStageContextAggregatesScheduledAndLineupStages() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = canonicalRouteEventID
        let otherEventID = canonicalRouteRecordID("events.openmusic.event", "3mrdbziccpcba")
        let contributorID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcaj")
        let otherContributorID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcbb")
        let mainID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcbc")
        let meadowID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcbd")
        let tentID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcbe")
        let otherPlaceID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcbf")
        let scheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcbg")
        let otherScheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcbh")
        let programID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcbi")
        let otherProgramID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcbj")
        let date = try #require(LocalDate("2026-08-07"))
        let zone = TimeZone.gmt

        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertCanonicalEvent(db, id: otherEventID, name: "Event Two")
            let contributor = try Contributor(
                id: contributorID, event: selectedEventID, name: "Artist",
                createdAt: "2026-09-01T12:00:00Z"
            )
            let otherContributor = try Contributor(
                id: otherContributorID, event: otherEventID, name: "Other Artist",
                createdAt: "2026-09-01T12:00:00Z"
            )
            try Contributor.insert { contributor }.execute(db)
            try Contributor.insert { otherContributor }.execute(db)
            try Self.insertCanonicalSchedule(db, id: scheduleID, eventID: selectedEventID, date: date)
            try Self.insertCanonicalSchedule(db, id: otherScheduleID, eventID: otherEventID, date: date)
            try Self.insertCanonicalStage(
                db, id: mainID, eventID: selectedEventID, name: "Main",
                lineup: [contributorID], sortIndex: 1
            )
            try Self.insertCanonicalStage(
                db, id: meadowID, eventID: selectedEventID, name: "Meadow", sortIndex: 2
            )
            try Self.insertCanonicalStage(
                db, id: tentID, eventID: selectedEventID, name: "Tent",
                lineup: [contributorID], sortIndex: 3
            )
            try Self.insertCanonicalStage(
                db, id: otherPlaceID, eventID: otherEventID, name: "Other",
                lineup: [otherContributorID], sortIndex: 0
            )
            try Self.insertCanonicalProgram(
                db, id: programID, eventID: selectedEventID,
                eventPlaces: [mainID, meadowID, tentID]
            )
            try Self.insertCanonicalProgram(
                db, id: otherProgramID, eventID: otherEventID, eventPlaces: [otherPlaceID]
            )
            try Self.insertCanonicalProgramItem(
                db, id: canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcbk"),
                eventID: selectedEventID, programID: programID,
                scheduleID: scheduleID, placeID: meadowID, title: "Meadow Set",
                startsAt: try #require(date.at(hour: 18, in: zone)),
                endsAt: try #require(date.at(hour: 19, in: zone)),
                credits: [ProgramItem.Credit(name: "Artist", contributor: contributorID)]
            )
            try Self.insertCanonicalProgramItem(
                db, id: canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcbl"),
                eventID: selectedEventID, programID: programID,
                scheduleID: scheduleID, placeID: tentID, title: "Tent Set",
                startsAt: try #require(date.at(hour: 20, in: zone)),
                endsAt: try #require(date.at(hour: 21, in: zone)),
                credits: [ProgramItem.Credit(name: "Artist", contributor: contributorID)]
            )
            try Self.insertCanonicalProgramItem(
                db, id: canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcbm"),
                eventID: otherEventID, programID: otherProgramID,
                scheduleID: otherScheduleID, placeID: otherPlaceID, title: "Other Set",
                startsAt: try #require(date.at(hour: 17, in: zone)),
                endsAt: try #require(date.at(hour: 18, in: zone)),
                credits: [ProgramItem.Credit(name: "Other Artist", contributor: otherContributorID)]
            )
        }

        let context = try await database.read { db in
            ContributorStageContext(
                contributorID: contributorID,
                performanceRows: try PerformanceRow.forContributor(
                    contributorID: contributorID,
                    eventID: selectedEventID
                )
                .fetchAll(db),
                lineupStages: try ContributorDetail.lineupStagesQuery(
                    contributorID: contributorID,
                    eventID: selectedEventID
                )
                    .fetchAll(db)
            )
        }

        #expect(context.scheduledItems.map(\.title) == ["Meadow Set", "Tent Set"])
        #expect(context.lineupOnlyStages.map(\.name) == ["Main"])
        #expect(context.stages.map(\.name) == ["Main", "Meadow", "Tent"])
        #expect(context.primaryStage?.name == "Main")
        let firstPerformance = try #require(context.scheduledItems.first)
        #expect(context.stage(for: firstPerformance)?.name == "Meadow")

        let rowContext = try withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            let state = ContributorList.State(eventID: selectedEventID)
            let row = try #require(state.contributorRows.first {
                $0.contributorID == contributorID
            })
            return row
        }

        #expect(rowContext.stages.map(\.name) == ["Main", "Meadow", "Tent"])
    }

    @Test
    func performanceRowScheduleQueryReturnsPerformanceAndStage() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = canonicalRouteEventID
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        let fridayID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcbd")
        let saturdayID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcbe")
        let programID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcbf")
        let openingID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcam")
        let nextDayID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcbn")
        let friday = try #require(LocalDate("2026-08-07"))
        let saturday = try #require(LocalDate("2026-08-08"))
        let zone = TimeZone.gmt

        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertCanonicalSchedule(db, id: fridayID, eventID: selectedEventID, date: friday)
            try Self.insertCanonicalSchedule(db, id: saturdayID, eventID: selectedEventID, date: saturday)
            try Self.insertCanonicalStage(db, id: stageID, eventID: selectedEventID, name: "Meadow")
            try Self.insertCanonicalProgram(
                db, id: programID, eventID: selectedEventID, eventPlaces: [stageID]
            )
            try Self.insertCanonicalProgramItem(
                db, id: openingID, eventID: selectedEventID,
                programID: programID, scheduleID: fridayID, placeID: stageID,
                title: "Opening",
                startsAt: try #require(friday.at(hour: 18, in: zone)),
                endsAt: try #require(friday.at(hour: 19, in: zone))
            )
            try Self.insertCanonicalProgramItem(
                db, id: nextDayID, eventID: selectedEventID,
                programID: programID, scheduleID: saturdayID, placeID: stageID,
                title: "Next Day",
                startsAt: try #require(saturday.at(hour: 20, in: zone)),
                endsAt: try #require(saturday.at(hour: 21, in: zone))
            )
        }

        let rows = try await database.read { db in
            try PerformanceRow
                .all(eventID: selectedEventID, scheduleID: fridayID)
                .fetchAll(db)
        }

        #expect(rows.map(\.performanceID) == [openingID])
        #expect(rows.map(\.title) == ["Opening"])
        #expect(rows.first?.stage?.name == "Meadow")
    }


}
