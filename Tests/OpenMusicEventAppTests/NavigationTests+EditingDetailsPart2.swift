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
                initialState: SocialCategoryForm.State(
                    eventID: eventID,
                    formValue: SocialCategoryForm.FormValue(
                        name: "  General Updates  ",
                        description: "  Important information for everyone.  ",
                        defaultNotificationState: .unsubscribed,
                        notificationsRequired: true
                    )
                )
            ) {
                SocialCategoryForm()
            }
        }

        await store.send(
            SocialCategoryForm.Action.formSubmitted(
                SocialCategoryForm.FormValue(
                    name: "  General Updates  ",
                    description: "  Important information for everyone.  ",
                    defaultNotificationState: .unsubscribed,
                    notificationsRequired: true
                )
            )
        )?.value

        let channel = try await database.read { db in
            try #require(
                try SocialCategoryList
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
                try SocialCategoryList
                    .channelsQuery(eventID: eventID)
                    .fetchAll(db)
                    .first
            )
        }
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: SocialCategoryForm.State(category: channel)) {
                SocialCategoryForm()
            }
        }

        await store.send(
            .formSubmitted(
                SocialCategoryForm.FormValue(
                    name: "  Camp Updates  ",
                    description: "  Messages for campers.  ",
                    defaultNotificationState: .subscribed,
                    notificationsRequired: false
                )
            )
        )?.value

        let savedChannel = try await database.read { db in
            try #require(
                try SocialCategoryList
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
    func categoryFormAddsAndReordersMediaOnTheCanonicalRecord() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let categoryID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: categoryID, eventID: eventID, name: "Updates")
        }
        let category = try await database.read { db in
            try #require(try Social.Category.find(categoryID).fetchOne(db))
        }
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.continuousClock = ContinuousClock()
        } operation: {
            TestStore(initialState: SocialCategoryForm.State(category: category)) {
                SocialCategoryForm()
            }
        }

        // The organizer adds two public media links and moves the second one to the top.
        for (title, url) in [
            ("Header", "https://example.com/header"),
            ("Icon", "https://example.com/icon"),
        ] {
            await store.send(.addExternalMediaButtonTapped)?.value
            await store.send(.mediaDraftURIChanged(url))?.value
            await store.send(.mediaDraftTitleChanged(title))?.value
            await store.send(.mediaDraftSaveButtonTapped)?.value
        }
        let iconID = store.state.mediaEntries[1].id
        await store.send(.mediaMoveButtonTapped(iconID, -1))?.value
        #expect(store.state.mediaEntries.map(\.title) == ["Icon", "Header"])

        let submittedValue = store.state.form.value
        let submission = store.send(.saveButtonTapped)
        let save = await store.receive(\.formSubmitted, .equals(submittedValue), timeout: .seconds(1))
        await save?.value
        await submission?.value

        let saved = try await database.read { db in
            try #require(try Social.Category.find(categoryID).fetchOne(db))
        }
        #expect(saved.description == nil)
        let media = (saved.media ?? []).compactMap { value -> OME.Media.External? in
            guard case let .known(.external(external)) = value else { return nil }
            return external
        }
        #expect(media.map(\.title) == ["Icon", "Header"])
        #expect(media.map(\.uri.absoluteString) == [
            "https://example.com/icon", "https://example.com/header",
        ])
    }

    @Test
    func categoryFormPreservesAnUnknownNotificationDefault() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let categoryID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(db, id: categoryID, eventID: eventID, name: "Updates")
            var category = try #require(try Social.Category.find(categoryID).fetchOne(db))
            category.defaultNotificationState = .unknown("digest")
            category.notificationsRequired = nil
            try Social.Category.upsert { category }.execute(db)
        }
        let category = try await database.read { db in
            try #require(try Social.Category.find(categoryID).fetchOne(db))
        }
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.continuousClock = ContinuousClock()
        } operation: {
            TestStore(initialState: SocialCategoryForm.State(category: category)) {
                SocialCategoryForm()
            }
        }

        #expect(store.state.form.value.defaultNotificationState == .unrecognized)
        store.modify { $0.form.value.name = "Event News" }
        let submittedValue = store.state.form.value
        let submission = store.send(.saveButtonTapped)
        let save = await store.receive(\.formSubmitted, .equals(submittedValue), timeout: .seconds(1))
        await save?.value
        await submission?.value

        let saved = try await database.read { db in
            try #require(try Social.Category.find(categoryID).fetchOne(db))
        }
        #expect(saved.name == "Event News")
        #expect(saved.description == nil)
        #expect(saved.defaultNotificationState == .unknown("digest"))
        #expect(saved.notificationsRequired == nil)
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
                try SocialCategoryList
                    .channelsQuery(eventID: eventID)
                    .fetchAll(db)
                    .first
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: SocialCategoryList.State(eventID: eventID)) {
                SocialCategoryList()
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
            try SocialCategoryList.channelsQuery(eventID: eventID).fetchAll(db)
        }
        #expect(channels.isEmpty)
    }

    @Test
    func communicationChannelDetailAuthoringActionsManagePinsAndOpenTheComposerEditor() async throws {
        let database = try makePreparedDatabase()
        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpdbb"
        ))
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
                try SocialCategoryList
                    .channelsQuery(eventID: eventID)
                    .fetchAll(db)
                .first
            )
        }
        let ownerID = try #require(DID("did:plc:organizer"))
        let baseline = try CanonicalWorkspaceBaseline.openOrCapture(
            at: FileManager.default.temporaryDirectory
                .appending(path: "OME-ChannelOwner-\(UUID()).sqlite").path,
            from: database
        )
        let session = EventWorkspaceSession(
            eventID: eventID, actorID: ownerID, baseline: baseline
        )
        let oauth = canonicalWorkspaceTestOAuthSession(actorID: ownerID)
        let selectedSession = TestMutex(Optional(oauth))

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.getOptionalDefaultSession = { selectedSession.withLock { $0 } }
        } operation: {
            Shared<EventWorkspaceSession?>(.defaultEventWorkspaceSession)
                .withLock { $0 = session }
            return TestStore(
                initialState: SocialCategoryDetail.State(
                    channelID: channelID,
                    eventID: eventID
                )
            ) {
                SocialCategoryDetail()
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

        store.send(.postButtonTapped(postID))
        await waitUntil { store.state.destination?.postDetail?.post != nil }
        store.send(.destination(.postDetail(.editButtonTapped)))
        #expect(store.state.destination?.postDetail?.destination?.composer?.editingPost?.id == postID)

        store.send(.editPostButtonTapped(postID))
        #expect(store.state.destination?.composer?.editingPost?.id == postID)

        store.send(.newPostButtonTapped)

        #expect(store.state.destination?.composer?.categoryID == channel.id)

        store.send(.editChannelButtonTapped(channel))

        #expect(store.state.destination?.channelForm?.categoryID == channelID)

        store.send(.deleteChannelButtonTapped)

        #expect(store.state.destination?.deleteChannelConfirmation?.channelID == channelID)

        selectedSession.withLock { $0 = nil }
        #expect(!store.state.canEditChannel)
    }


}
