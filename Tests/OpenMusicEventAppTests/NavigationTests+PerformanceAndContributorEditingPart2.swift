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
    func performanceDetailDisplaysPrimaryContributorsAtStageAndSupportBelow() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        let scheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcbd")
        let programID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcbf")
        let performanceID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcam")
        let stylustID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcaj")
        let oodraID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcas")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: stageID, eventID: eventID, name: "Meadow")
            try Self.insertCanonicalSchedule(db, id: scheduleID, eventID: eventID, date: date)
            try Self.insertCanonicalProgram(db, id: programID, eventID: eventID, eventPlaces: [stageID])
            let stylust = try Contributor(
                id: stylustID, event: eventID, name: "STYLUST", createdAt: "2026-09-01T12:00:00Z"
            )
            let oodra = try Contributor(
                id: oodraID, event: eventID, name: "Oodra Movement", createdAt: "2026-09-01T12:00:00Z"
            )
            try Contributor.insert { stylust }.execute(db)
            try Contributor.insert { oodra }.execute(db)
            try Self.insertCanonicalProgramItem(
                db, id: performanceID, eventID: eventID,
                programID: programID, scheduleID: scheduleID, placeID: stageID,
                title: "STYLUST",
                startsAt: try #require(date.at(hour: 18, in: timeZone)),
                endsAt: try #require(date.at(hour: 19, in: timeZone))
            )
            var item = try #require(try ProgramItem.find(performanceID).fetchOne(db))
            item.credits = [
                ProgramItem.Credit(name: "STYLUST", contributor: stylustID, billing: .known(.primary), role: "DJ"),
                ProgramItem.Credit(name: "Oodra Movement", contributor: oodraID, billing: .known(.supporting), role: "Dancer"),
            ]
            try ProgramItem.upsert { item }.execute(db)
        }

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            PerformanceDetail.State(
                performanceID: performanceID,
                eventID: eventID
            )
        }

        expectNoDifference(state.headlineContributors.map(\.name), ["STYLUST"])
        expectNoDifference(
            state.displayedContributors.map(\.name),
            ["STYLUST", "Oodra Movement"]
        )
        expectNoDifference(
            state.displayedContributorCredits.compactMap(\.roleTitle),
            ["DJ", "Dancer"]
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: PerformanceDetail.State(
                    performanceID: performanceID,
                    eventID: eventID
                )
            ) {
                PerformanceDetail()
            }
        }
        store.send(.contributorButtonTapped(stylustID))
        #expect(
            store.state.destination?.contributorDetail?.contributorID
                == stylustID
        )
        expectNoDifference(store.state.destination?.contributorDetail?.eventID, eventID)
    }

    @Test
    func contributorDetailPerformanceTapPresentsPerformanceDetail() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let stageID = canonicalRouteRecordID("events.openmusic.eventPlace", "3mrdbziccpcak")
        let scheduleID = canonicalRouteRecordID("events.openmusic.schedule", "3mrdbziccpcbd")
        let programID = canonicalRouteRecordID("events.openmusic.program", "3mrdbziccpcbf")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let contributorID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcaj")
        let performanceID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcam")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: stageID, eventID: eventID, name: "Meadow")
            try Self.insertCanonicalSchedule(db, id: scheduleID, eventID: eventID, date: date)
            try Self.insertCanonicalProgram(db, id: programID, eventID: eventID, eventPlaces: [stageID])
            let contributor = try Contributor(
                id: contributorID, event: eventID, name: "Amy", createdAt: "2026-09-01T12:00:00Z"
            )
            try Contributor.insert { contributor }.execute(db)
            try Self.insertCanonicalProgramItem(
                db, id: performanceID, eventID: eventID,
                programID: programID, scheduleID: scheduleID, placeID: stageID,
                title: "Opening",
                startsAt: try #require(date.at(hour: 18, in: timeZone)),
                endsAt: try #require(date.at(hour: 19, in: timeZone))
            )
            var item = try #require(try ProgramItem.find(performanceID).fetchOne(db))
            item.credits = [ProgramItem.Credit(name: "Amy", contributor: contributorID)]
            try ProgramItem.upsert { item }.execute(db)
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: ContributorDetail.State(
                    contributorID: contributorID,
                    eventID: eventID
                )
            ) {
                ContributorDetail()
            }
        }

        store.send(.performanceButtonTapped(performanceID))

        #expect(store.state.destination?.performanceDetail?.performanceID == performanceID)
        expectNoDifference(store.state.destination?.performanceDetail?.eventID, eventID)
    }

    @Test
    func contributorDetailFallsBackToFestivalHeroAndLogo() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let contributorID = canonicalRouteRecordID("events.openmusic.contributor", "3mrdbziccpcaj")
        let festivalHeroURL = try #require(URL(string: "https://example.com/festival-hero.jpg"))
        let festivalLogoURL = try #require(URL(string: "https://example.com/festival-logo.png"))

        try await database.write { db in
            var event = try Event(
                id: eventID, name: "Festival",
                createdAt: "2026-09-01T12:00:00Z", timeZone: .gmt
            )
            event.media = [
                .known(.image(OME.Image(source: .known(.url(festivalHeroURL)), role: .known(.hero)))),
                .known(.image(OME.Image(source: .known(.url(festivalLogoURL)), role: .known(.logo)))),
            ]
            try Event.insert { event }.execute(db)
            let contributor = try Contributor(
                id: contributorID, event: eventID, name: "Artist",
                createdAt: "2026-09-01T12:00:00Z"
            )
            try Contributor.insert { contributor }.execute(db)
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: ContributorDetail.State(
                    contributorID: contributorID,
                    eventID: eventID
                )
            ) {
                ContributorDetail()
            }
        }

        expectNoDifference(store.state.heroImageSources.map(\.kind), [.primaryImage, .logo])
        expectNoDifference(
            store.state.heroImageSources.map { $0.image.asset.url },
            [festivalHeroURL, festivalLogoURL]
        )
        expectNoDifference(store.state.heroImageSources.map { $0.image.recordID }, [eventID, eventID])
    }


}
