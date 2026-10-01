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
    func communicationsChannelDetailNotifyMeWritesPreference() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(
                db, id: channelID, eventID: eventID, name: "General",
                defaultNotificationState: .unsubscribed
            )
        }

        let refreshCount = TestMutex(0)
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: CommunicationChannelDetail.State(
                    channelID: channelID,
                    eventID: eventID
                )
            ) {
                CommunicationChannelDetail()
                    .onEvent(NotificationSubscriptionsRefreshRequested.self) { _, _ in
                        refreshCount.withLock { $0 += 1 }
                    }
            }
        }

        let notifyTask = store.send(.notificationStateButtonTapped(.subscribed))
        await notifyTask?.value
        expectNoDifference(refreshCount.withLock { $0 }, 1)

        let preference = try await database.read { db in
            try ChannelPreferences
                .where { $0.id.eq(channelID) }
                .fetchOne(db)
        }

        #expect(preference?.notificationState == .subscribed)
    }

    @Test
    func communicationsChannelDetailStopNotifyingMeWritesPreference() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(
                db, id: channelID, eventID: eventID, name: "General",
                defaultNotificationState: .subscribed
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: CommunicationChannelDetail.State(
                    channelID: channelID,
                    eventID: eventID
                )
            ) {
                CommunicationChannelDetail()
            }
        }

        let notifyTask = store.send(.notificationStateButtonTapped(.unsubscribed))
        await notifyTask?.value

        let preference = try await database.read { db in
            try ChannelPreferences
                .where { $0.id.eq(channelID) }
                .fetchOne(db)
        }

        #expect(preference?.notificationState == .unsubscribed)
    }

    @Test
    func communicationsChannelDetailRequiredChannelDoesNotWriteUnsubscribePreference() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(
                db, id: channelID, eventID: eventID, name: "General",
                defaultNotificationState: .subscribed, notificationsRequired: true
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: CommunicationChannelDetail.State(
                    channelID: channelID,
                    eventID: eventID
                )
            ) {
                CommunicationChannelDetail()
            }
        }

        store.send(.notificationStateButtonTapped(.unsubscribed))

        let preference = try await database.read { db in
            try ChannelPreferences
                .where { $0.id.eq(channelID) }
                .fetchOne(db)
        }

        #expect(preference == nil)
    }

    @Test
    func communicationsChannelDetailFetchesSelectedChannelPosts() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        let safetyID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcao")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: channelID, eventID: eventID, name: "General")
            try Self.insertCanonicalCategory(db, id: safetyID, eventID: eventID, name: "Safety")
            try Self.insertCanonicalPost(
                db, id: canonicalRouteRecordID("social.ome.post", "3mrdbziccpcap"),
                eventID: eventID, categoryID: channelID, title: "Arrival Info",
                text: "Use the north gate."
            )
            try Self.insertCanonicalPost(
                db, id: canonicalRouteRecordID("social.ome.post", "3mrdbziccpcaq"),
                eventID: eventID, categoryID: channelID, title: "Welcome",
                text: "Welcome to the event.", pinned: true
            )
            try Self.insertCanonicalPost(
                db, id: canonicalRouteRecordID("social.ome.post", "3mrdbziccpcar"),
                eventID: eventID, categoryID: safetyID, title: "Weather",
                text: "Bring layers."
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(
                initialState: CommunicationChannelDetail.State(
                    channelID: channelID,
                    eventID: eventID
                )
            ) {
                CommunicationChannelDetail()
            }
        }

        expectNoDifference(store.state.pinnedPosts.map(\.title), ["Welcome"])
        expectNoDifference(store.state.recentPosts.map(\.title), ["Arrival Info"])
        #expect(store.state.shouldShowEmptyPostsFooter == false)
    }

    @Test
    func communicationsChannelDetailShowsEmptyPostsFooterWhenNoPosts() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: channelID, eventID: eventID, name: "General")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(
                initialState: CommunicationChannelDetail.State(
                    channelID: channelID,
                    eventID: eventID
                )
            ) {
                CommunicationChannelDetail()
            }
        }

        #expect(store.state.shouldShowEmptyPostsFooter == true)
        expectNoDifference(store.state.pinnedPosts, [])
        expectNoDifference(store.state.recentPosts, [])
    }

    @Test
    func communicationsChannelDetailPostTapPresentsPostDetail() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        let postID = canonicalRouteRecordID("social.ome.post", "3mrdbziccpcap")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: channelID, eventID: eventID, name: "General")
            try Self.insertCanonicalPost(
                db, id: postID, eventID: eventID, categoryID: channelID,
                title: "Welcome", text: "Welcome to the event.", pinned: true
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: CommunicationChannelDetail.State(
                    channelID: channelID,
                    eventID: eventID
                )
            ) {
                CommunicationChannelDetail()
            }
        }

        store.send(.postButtonTapped(postID))

        #expect(store.state.destination?.postDetail?.postID == postID)
        #expect(store.state.destination?.postDetail?.post?.title == "Welcome")
    }


}
