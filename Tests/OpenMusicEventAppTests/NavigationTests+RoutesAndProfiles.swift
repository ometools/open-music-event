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
    func performanceDeepLinkPreservesIDWhenPerformanceIsUnavailable() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let performanceID = canonicalRouteRecordID("events.openmusic.programItem", "3mrdbziccpcae")
        let graph = try canonicalNavigationGraph(id: eventID)
        let store = makeCanonicalRootHarnessStore(
            database: database,
            client: EventRecordClient { _ in graph }
        )
        let route = AppRoute.event(eventID, .performance(performanceID))
        let url = try #require(URL(string: "https://openmusicevent.app" + route.path))

        await store.send(.root(.openURL(url)))?.value
        await waitUntil {
            store.state.root.destination?.eventViewer?.scheduleViewers
                .contains { $0.state.destination?.performanceDetail?.performanceID == performanceID }
                == true
        }

        let scheduleViewer = try #require(
            store.state.root.destination?.eventViewer?.scheduleViewers.first {
                $0.state.scheduleDivision == .schedule
            }
        )
        let performanceDetail = try #require(scheduleViewer.state.destination?.performanceDetail)
        #expect(performanceDetail.performanceID == performanceID)
        #expect(performanceDetail.performance == nil)
    }

    @Test
    func channelDeepLinkPresentsChannelDetail() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcae")
        let graph = try canonicalNavigationGraph(id: eventID)
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(
                db, id: channelID, eventID: eventID, name: "General"
            )
        }

        let store = makeCanonicalRootHarnessStore(
            database: database,
            client: EventRecordClient { _ in graph }
        )
        let route = AppRoute.event(eventID, .channel(channelID))
        let url = try #require(URL(string: "https://openmusicevent.app" + route.path))
        await store.send(.root(.openURL(url)))?.value
        await waitUntil {
            store.state.root.destination?.eventViewer?
                .communicationsViewer?.destination?.channelDetail?.channelID == channelID
        }

        let eventViewer = try #require(store.state.root.destination?.eventViewer)
        #expect(eventViewer.selectedFeature == .communications)
        #expect(eventViewer.communicationsViewer?.destination?.channelDetail?.channelID == channelID)
        #expect(eventViewer.communicationsViewer?.destination?.channelDetail?.channel?.name == "General")
    }

    @Test
    func postDeepLinkPresentsPostDetailByStableID() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcae")
        let postID = canonicalRouteRecordID("social.ome.post", "3mrdbziccpcae")
        let graph = try canonicalNavigationGraph(id: eventID)
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(
                db, id: channelID, eventID: eventID, name: "General"
            )
            try Self.insertCanonicalPost(
                db, id: postID, eventID: eventID, categoryID: channelID,
                title: "Welcome", text: "Welcome to the event."
            )
        }

        let store = makeCanonicalRootHarnessStore(
            database: database,
            client: EventRecordClient { _ in graph }
        )
        let route = AppRoute.event(
            eventID,
            .post(channelID: channelID, postID: postID)
        )
        let url = try #require(URL(string: "https://openmusicevent.app" + route.path))
        await store.send(.root(.openURL(url)))?.value
        await waitUntil {
            store.state.root.destination?.eventViewer?
                .communicationsViewer?.destination?.channelDetail?
                .destination?.postDetail?.postID == postID
        }

        let eventViewer = try #require(store.state.root.destination?.eventViewer)
        let channel = try #require(
            eventViewer.communicationsViewer?.destination?.channelDetail
        )
        #expect(eventViewer.selectedFeature == .communications)
        #expect(channel.destination?.postDetail?.postID == postID)
        #expect(channel.destination?.postDetail?.post?.title == "Welcome")
    }

    @Test
    func eventViewerConsumesContributorNavigationFromSearchDescendant() async throws {
        let contributorID = canonicalRouteRecordID(
            "events.openmusic.contributor", "3mrdbziccpcae"
        )
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
        }
        let store = try makeEventViewerHarnessStore(
            eventID: eventID, database: database
        )

        await withDependencies {
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            await store.send(
                to: \.eventViewer.eventSearch,
                EventSearch.Action.openTarget(.contributor(contributorID))
            )?.value

            #expect(
                store.state.eventViewer.eventSearch.state.destination?.contributorDetail?.state
                    .contributorID == contributorID
            )
            #expect(store.state.lastRequest == nil)
        }
    }

    @Test
    func eventViewerSearchUsesMountedEventIDForContributorNavigation() async throws {
        let selectedEventID = canonicalRouteEventID
        let otherEventID = canonicalRouteRecordID(
            "events.openmusic.event", "3mrdbziccpcae"
        )
        let contributorID = canonicalRouteRecordID(
            "events.openmusic.contributor", "3mrdbziccpcae"
        )
        let database = try makePreparedDatabase()
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: selectedEventID, name: "Selected")
            try Self.insertCanonicalEvent(db, id: otherEventID, name: "Other")
        }
        let store = try makeEventViewerHarnessStore(
            eventID: selectedEventID, database: database
        )

        await withDependencies {
            $0.defaultDatabase = database
            $0.defaultEventID = selectedEventID
        } operation: {
            await store.send(
                to: \.eventViewer.eventSearch,
                EventSearch.Action.openTarget(.contributor(contributorID))
            )?.value

            #expect(
                store.state.eventViewer.eventSearch.state.destination?.contributorDetail?.state
                    .eventID == selectedEventID
            )
        }
    }

    @Test
    func eventViewerConsumesStageNavigationFromSearchDescendant() async throws {
        let stageID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcae"
        )
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
        }
        let store = try makeEventViewerHarnessStore(
            eventID: eventID, database: database
        )

        await withDependencies {
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            await store.send(
                to: \.eventViewer.eventSearch,
                EventSearch.Action.openTarget(.stage(stageID))
            )?.value

            #expect(
                store.state.eventViewer.eventSearch.state.destination?.stageDetail?.state.stageID
                    == stageID
            )
            #expect(store.state.lastRequest == nil)
        }
    }

    @Test
    func myEventsPostsNavigationRequest() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Test Event")
            try InstalledEvent.insert { InstalledEvent(id: eventID) }.execute(db)
        }
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: MyEventsEventHarness.State()) {
                MyEventsEventHarness()
            }
        }

        store.send(.myEvents(.eventButtonTapped(eventID))) {
            $0.lastRequest = .event(eventID, nil)
        }
        #expect(store.state.lastRequest == .event(eventID, nil))
    }


}
