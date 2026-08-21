import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
import SwiftUI
import Tagged

@Feature
public struct CommunicationChannelDetail {
    public init() {}

    public struct State: Identifiable {
        public init(
            channelID: OMERecord.ID<OMERecord.Channel>,
            eventID: OMERecord.Event.ID,
            destination: Destination.State? = nil
        ) {
            self.channelID = channelID
            self.eventID = eventID
            self.destination = destination
            _channel = FetchOne(
                CommunicationChannelDetail.channelQuery(
                    channelID: channelID,
                    eventID: eventID
                )
            )
            _preference = FetchOne(
                CommunicationChannelDetail.preferenceQuery(
                    channelID: channelID,
                    eventID: eventID
                )
            )
            _posts = FetchAll(
                CommunicationChannelDetail.postsQuery(
                    channelID: channelID,
                    eventID: eventID
                )
            )
            _postReads = FetchAll(
                CommunicationChannelDetail.postReadsQuery(
                    channelID: channelID,
                    eventID: eventID
                )
            )
        }

        public let channelID: OMERecord.ID<OMERecord.Channel>
        public let eventID: OMERecord.Event.ID
        @SharedReader(.defaultAuthoringGrant)
        public var authoringGrant: AuthoringGrant?
        public var destination: Destination.State?
        public var errorMessage: String?

        @FetchOne public var channel: OMERecord.Channel?
        @FetchOne public var preference: ChannelPreferences?
        @FetchAll public var posts: [CommsPost]
        @FetchAll public var postReads: [CommsPostRead]

        public var id: OMERecord.ID<OMERecord.Channel> { channelID }

        var channelRecordID: OMERecord.Channel.ID {
            OMERecord.Channel.ID(
                organizerID: eventID.organizerID,
                eventID: eventID.eventID,
                channelID: channelID
            )
        }

        var canChangeNotificationState: Bool {
            channel?.notificationsRequired == false
        }

        public var canEditChannel: Bool {
            authoringGrant?.access.canEditContent == true
        }

        var effectiveNotificationState: OMERecord.Channel.NotificationState? {
            if channel?.notificationsRequired == true {
                return .subscribed
            }
            return preference?.notificationState ?? channel?.defaultNotificationState
        }

        var pinnedPosts: [CommsPost] {
            posts.filter(\.isPinned)
        }

        var recentPosts: [CommsPost] {
            posts.filter { !$0.isPinned }
        }

        var shouldShowEmptyPostsFooter: Bool {
            posts.isEmpty
        }

        var readPostIDs: Set<CommsPost.ID> {
            Set(postReads.map(\.id))
        }
    }

    public enum Action {
        case deleteChannelButtonTapped
        case editChannelButtonTapped(OMERecord.Channel)
        case markPostReadButtonTapped(CommsPost.ID)
        case markPostUnreadButtonTapped(CommsPost.ID)
        case newPostButtonTapped
        case notificationStateButtonTapped(OMERecord.Channel.NotificationState)
        case postButtonTapped(CommsPost.ID)
        case destination(Destination.Action)
    }

    @Feature
    public enum Destination {
        case channelForm(ChannelForm)
        case composer(CommsPostComposer)
        case deleteChannelConfirmation(ChannelDeleteConfirmation)
        case postDetail(CommsPostDetail)
    }

    @Dependency(\.defaultDatabase) var database

    static func channelQuery(
        channelID: OMERecord.ID<OMERecord.Channel>,
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Channel> {
        OMERecord.Channel
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.id.channelID.eq(channelID) }
    }

    static func preferenceQuery(
        channelID: OMERecord.ID<OMERecord.Channel>,
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<ChannelPreferences> {
        ChannelPreferences
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.id.channelID.eq(channelID) }
    }

    static func postsQuery(
        channelID: OMERecord.ID<OMERecord.Channel>,
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<CommsPost> {
        CommsPost
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.id.channelID.eq(channelID) }
            .order { ($0.timestamp.desc(), $0.sortIndex, $0.title.collate(.nocase)) }
    }

    static func postReadsQuery(
        channelID: OMERecord.ID<OMERecord.Channel>,
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<CommsPostRead> {
        CommsPostRead
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .where { $0.id.channelID.eq(channelID) }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .deleteChannelButtonTapped:
                state.destination = .deleteChannelConfirmation(
                    ChannelDeleteConfirmation.State(channelID: state.channelID)
                )

            case let .editChannelButtonTapped(channel):
                state.destination = .channelForm(ChannelForm.State(channel: channel))

            case let .markPostReadButtonTapped(postID):
                updateReadState(true, postID: postID)

            case let .markPostUnreadButtonTapped(postID):
                updateReadState(false, postID: postID)

            case .newPostButtonTapped:
                guard state.canEditChannel else { return }
                state.destination = .composer(
                    CommsPostComposer.State(
                        channelID: state.channelRecordID
                    )
                )

            case let .notificationStateButtonTapped(notificationState):
                guard
                    notificationState != .unsubscribed
                        || state.canChangeNotificationState
                else { return }
                updateNotificationState(notificationState, state: state)

            case let .postButtonTapped(postID):
                state.destination = .postDetail(CommsPostDetail.State(postID: postID))

            case let .destination(.deleteChannelConfirmation(.deleteButtonTapped(channelID))):
                guard channelID == state.channelID else { return }
                let recordID = state.channelRecordID
                state.destination = nil
                store.addTask {
                    do {
                        try await database.write { db in
                            try OMERecord.Channel.find(recordID).delete().execute(db)
                        }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to delete this channel."
                        }
                    }
                }

            case .destination:
                break
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }

    private func updateNotificationState(
        _ notificationState: OMERecord.Channel.NotificationState,
        state: CommunicationChannelDetail.State
    ) {
        guard state.channel != nil else { return }

        let channelPreference = ChannelPreferences(
            id: state.channelRecordID,
            notificationState: notificationState
        )
        store.addTask {
            do {
                try await database.write { db in
                    try ChannelPreferences.upsert { channelPreference }.execute(db)
                }
                let refreshTask = try store.post(
                    NotificationSubscriptionsRefreshRequested()
                )
                await refreshTask?.value
                try store.modify {
                    $0.errorMessage = nil
                }
            } catch {
                try store.modify {
                    $0.errorMessage = "Unable to update notification preference."
                }
            }
        }
    }

    func updateReadState(_ isRead: Bool, postID: CommsPost.ID) {
        store.addTask {
            do {
                try await database.write { database in
                    try CommsPostRead.setRead(isRead, postID: postID, in: database)
                }
                try store.modify {
                    $0.errorMessage = nil
                }
            } catch {
                try store.modify {
                    $0.errorMessage = isRead
                        ? "Unable to mark this post as read."
                        : "Unable to mark this post as unread."
                }
            }
        }
    }
}
