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
    func channelFormAddsCanonicalCategoryWithRequiredNotifications() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let existingID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: existingID, eventID: eventID, name: "Existing")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: ChannelForm.State(
                    eventID: eventID,
                    formValue: ChannelForm.FormValue(
                        name: "  General Updates  ",
                        description: "  Important information for everyone.  ",
                        defaultNotificationState: .unsubscribed,
                        notificationsRequired: true
                    )
                )
            ) {
                ChannelForm()
            }
        }

        await store.send(
            ChannelForm.Action.formSubmitted(
                ChannelForm.FormValue(
                    name: "  General Updates  ",
                    description: "  Important information for everyone.  ",
                    defaultNotificationState: .unsubscribed,
                    notificationsRequired: true
                )
            )
        )?.value

        let channel = try await database.read { db in
            try #require(
                try CommunicationsViewer
                    .channelsQuery(eventID: eventID)
                    .fetchAll(db)
                    .first(where: { $0.id != existingID })
            )
        }

        expectNoDifference(channel.name, "General Updates")
        expectNoDifference(channel.description, "Important information for everyone.")
        #expect(channel.id.authority == eventID.authority)
        expectNoDifference(channel.defaultNotificationState, .known(.subscribed))
        #expect(channel.notificationsRequired == true)
        #expect(store.isPresented == false)
    }

    @Test
    func channelFormEditsTheExistingChannelWithoutChangingItsIDOrOrder() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(
                db, id: channelID, eventID: eventID, name: "General",
                description: "Original updates.", defaultNotificationState: .unsubscribed
            )
        }

        let channel = try await database.read { db in
            try #require(
                try CommunicationsViewer
                    .channelsQuery(eventID: eventID)
                    .fetchAll(db)
                    .first
            )
        }
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: ChannelForm.State(category: channel)) {
                ChannelForm()
            }
        }

        await store.send(
            .formSubmitted(
                ChannelForm.FormValue(
                    name: "  Camp Updates  ",
                    description: "  Messages for campers.  ",
                    defaultNotificationState: .subscribed,
                    notificationsRequired: false
                )
            )
        )?.value

        let savedChannel = try await database.read { db in
            try #require(
                try CommunicationsViewer
                    .channelsQuery(eventID: eventID)
                    .fetchAll(db)
                    .first
            )
        }

        expectNoDifference(savedChannel.id, channelID)
        expectNoDifference(savedChannel.name, "Camp Updates")
        expectNoDifference(savedChannel.description, "Messages for campers.")
        expectNoDifference(savedChannel.defaultNotificationState, .known(.subscribed))
        #expect(savedChannel.notificationsRequired == false)
        #expect(store.isPresented == false)
    }

    @Test
    func communicationsViewerChannelActionsEditAndDeleteTheSelectedChannel() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: channelID, eventID: eventID, name: "General")
        }
        let channel = try await database.read { db in
            try #require(
                try CommunicationsViewer
                    .channelsQuery(eventID: eventID)
                    .fetchAll(db)
                    .first
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: CommunicationsViewer.State(eventID: eventID)) {
                CommunicationsViewer()
            }
        }

        store.send(.editChannelButtonTapped(channel))

        #expect(store.state.destination?.channelForm?.categoryID == channelID)

        store.send(.deleteChannelButtonTapped(channelID))

        #expect(store.state.destination?.deleteChannelConfirmation?.channelID == channelID)

        await store.send(
            .destination(
                .deleteChannelConfirmation(
                    .deleteButtonTapped(channelID)
                )
            )
        )?.value

        let channels = try await database.read { db in
            try CommunicationsViewer.channelsQuery(eventID: eventID).fetchAll(db)
        }
        #expect(channels.isEmpty)
    }

    @Test
    func communicationChannelDetailAuthoringActionsManagePinsAndOpenTheComposerEditor() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        let postID = canonicalRouteRecordID("social.ome.post", "3mrdbziccpcap")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: channelID, eventID: eventID, name: "General")
            try Self.insertCanonicalPost(
                db, id: postID, eventID: eventID, categoryID: channelID,
                title: "Welcome", text: "Welcome to the event."
            )
        }
        let channel = try await database.read { db in
            try #require(
                try CommunicationsViewer
                    .channelsQuery(eventID: eventID)
                    .fetchAll(db)
                .first
            )
        }
        let workspace = SourceWorkspace(
            organizerID: testOrganizerID,
            repository: "tangled.org/example/events",
            branch: "main"
        )
        let grant = AuthoringGrant(
            principal: AuthoringPrincipal(
                actorID: try #require(DID("did:plc:organizer"))
            ),
            role: .owner,
            workspaceID: workspace.id
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            let authoringGrant = Shared<AuthoringGrant?>(.defaultAuthoringGrant)
            authoringGrant.withLock { $0 = grant }
            return TestStore(
                initialState: CommunicationChannelDetail.State(
                    channelID: channelID,
                    eventID: eventID
                )
            ) {
                CommunicationChannelDetail()
            }
        }

        #expect(store.state.canEditChannel)
        await waitUntil {
            store.state.channel != nil && store.state.posts.contains { $0.id == postID }
        }

        await store.send(.pinPostButtonTapped(postID))?.value
        #expect(try await database.read {
            try Social.Category.find(channelID).fetchOne($0)?.pinnedPosts
        } == [postID])
        await waitUntil { store.state.channel?.pinnedPosts == [postID] }
        await store.send(.unpinPostButtonTapped(postID))?.value
        #expect(try await database.read {
            try Social.Category.find(channelID).fetchOne($0)?.pinnedPosts
        } == nil)

        store.send(.newPostButtonTapped)

        #expect(store.state.destination?.composer?.categoryID == channel.id)

        store.send(.editChannelButtonTapped(channel))

        #expect(store.state.destination?.channelForm?.categoryID == channelID)

        store.send(.deleteChannelButtonTapped)

        #expect(store.state.destination?.deleteChannelConfirmation?.channelID == channelID)
    }


}
