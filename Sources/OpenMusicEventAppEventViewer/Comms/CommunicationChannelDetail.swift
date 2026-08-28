import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventLexicon
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
        case deletePostButtonTapped(CommsPost.ID)
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
        case postDeleteConfirmation(PostDeleteConfirmation)
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

            case let .deletePostButtonTapped(postID):
                guard state.canEditChannel else { return }
                state.destination = .postDeleteConfirmation(
                    PostDeleteConfirmation.State(postID: postID)
                )

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

            case .destination(.postDetail(.deleteButtonTapped)):
                guard case let .postDetail(detail) = state.destination,
                      state.canEditChannel else { return }
                state.destination = .postDeleteConfirmation(
                    PostDeleteConfirmation.State(postID: detail.postID)
                )

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

            case let .destination(.postDeleteConfirmation(.deleteButtonTapped(postID))):
                guard state.canEditChannel,
                      postID.channelID == state.channelID else { return }
                state.destination = nil
                store.addTask {
                    do {
                        try await database.write { db in
                            guard try CommsPost.find(postID).fetchOne(db) != nil else {
                                throw PostDeleteError()
                            }
                            try CommsPostRead.find(postID).delete().execute(db)
                            try CommsPost.find(postID).delete().execute(db)
                            try LocalImageBlob
                                .where { $0.organizerID.eq(postID.organizerID) }
                                .where { $0.eventID.eq(postID.eventID) }
                                .where { $0.parentKind.eq(LocalImageBlob.ParentKind.communicationPost) }
                                .where { $0.parentLocalID.eq(postID.postID.rawValue) }
                                .delete()
                                .execute(db)
                        }
                        try store.modify {
                            $0.errorMessage = nil
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to delete this post."
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

@Feature
public struct PostDeleteConfirmation: Prompt {
    public struct State: Identifiable {
        public init(postID: CommsPost.ID) {
            self.postID = postID
        }

        public let postID: CommsPost.ID
        public var id: CommsPost.ID { postID }
    }

    public enum Action {
        case deleteButtonTapped(CommsPost.ID)
    }
}

public struct CommunicationChannelDetailView: View {
    @Bindable var store: StoreOf<CommunicationChannelDetail>

    public init(store: StoreOf<CommunicationChannelDetail>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let channel = store.channel {
                CommunicationChannelControlsView(store: store, channel: channel)
            } else {
                ViewerPlaceholderView(
                    title: "Channel",
                    systemImage: "megaphone",
                    description: "This communication channel could not be loaded."
                )
            }
        }
        .sheet(
            item: $store.scope(\.destination, action: \.destination).composer
        ) { composerStore in
            NavigationStack {
                CommsPostComposerView(store: composerStore)
            }
        }
        .accessibilityIdentifier(
            "view.channel-detail.\(store.channelID.rawValue.rawValue)"
        )
    }
}

struct CommunicationChannelControlsView: View {
    @Bindable var store: StoreOf<CommunicationChannelDetail>
    let channel: OMERecord.Channel

    init(
        store: StoreOf<CommunicationChannelDetail>,
        channel: OMERecord.Channel
    ) {
        self.store = store
        self.channel = channel
    }

    var body: some View {
        CommunicationChannelFormSheetView(store: store, channel: channel)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    CommunicationChannelNotificationMenu(
                        store: store,
                        channel: channel
                    )
                }

                if store.canEditChannel {
                    ToolbarItem(placement: .primaryAction) {
                        CommunicationChannelSettingsMenu(
                            store: store,
                            channel: channel
                        )
                    }
                }
            }
            .confirmationDialog(
                "Delete Channel?",
                isPresented: $store.scope(
                    \.destination,
                    action: \.destination
                ).deleteChannelConfirmation.isPresented,
                titleVisibility: .visible
            ) {
                Button("Delete Channel", role: .destructive) {
                    store.send(
                        .destination(
                            .deleteChannelConfirmation(
                                .deleteButtonTapped(store.channelID)
                            )
                        )
                    )
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the channel. Posts already published in it are not changed.")
            }
            .confirmationDialog(
                "Delete Post?",
                isPresented: $store.scope(
                    \.destination,
                    action: \.destination
                ).postDeleteConfirmation.isPresented,
                titleVisibility: .visible
            ) {
                Button("Delete Post", role: .destructive) {
                    guard case let .postDeleteConfirmation(confirmation) = store.destination else {
                        return
                    }
                    store.send(
                        .destination(
                            .postDeleteConfirmation(
                                .deleteButtonTapped(confirmation.postID)
                            )
                        )
                    )
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the post from this channel.")
            }
    }
}

struct CommunicationChannelFormSheetView: View {
    @Bindable var store: StoreOf<CommunicationChannelDetail>
    let channel: OMERecord.Channel

    init(
        store: StoreOf<CommunicationChannelDetail>,
        channel: OMERecord.Channel
    ) {
        self.store = store
        self.channel = channel
    }

    var body: some View {
        CommunicationChannelComposerSheetView(store: store, channel: channel)
            .sheet(
                item: $store.scope(\.destination, action: \.destination).channelForm
            ) { formStore in
                NavigationStack {
                    ChannelFormView(store: formStore)
                }
            }
    }
}

struct CommunicationChannelComposerSheetView: View {
    @Bindable var store: StoreOf<CommunicationChannelDetail>
    let channel: OMERecord.Channel

    init(
        store: StoreOf<CommunicationChannelDetail>,
        channel: OMERecord.Channel
    ) {
        self.store = store
        self.channel = channel
    }

    var body: some View {
        CommunicationChannelPostDestinationView(store: store, channel: channel)
    }
}

struct CommunicationChannelPostDestinationView: View {
    @Bindable var store: StoreOf<CommunicationChannelDetail>
    let channel: OMERecord.Channel

    init(
        store: StoreOf<CommunicationChannelDetail>,
        channel: OMERecord.Channel
    ) {
        self.store = store
        self.channel = channel
    }

    var body: some View {
        CommunicationChannelDetailList(store: store, channel: channel)
            .navigationTitle(channel.name)
            .navigationDestination(
                item: $store.scope(\.destination, action: \.destination).postDetail
            ) { postStore in
                CommsPostDetailView(store: postStore)
            }
    }
}

struct CommunicationChannelDetailList: View {
    let store: StoreOf<CommunicationChannelDetail>
    let channel: OMERecord.Channel

    var body: some View {
        List {
            Section {
                Text(channel.description)
                    .font(.subheadline)
            } footer: {
                if store.shouldShowEmptyPostsFooter {
                    Text("There are no posts in this channel yet.")
                }
            }

            if !store.pinnedPosts.isEmpty {
                Section("Pinned Posts") {
                    ForEach(store.pinnedPosts) { post in
                        CommunicationChannelPostRow(store: store, post: post)
                    }
                }
            }

            if !store.recentPosts.isEmpty {
                Section("Recent Posts") {
                    ForEach(store.recentPosts) { post in
                        CommunicationChannelPostRow(store: store, post: post)
                    }
                }
            }

            if channel.notificationsRequired || store.errorMessage != nil {
                Section("Notifications") {
                    if channel.notificationsRequired {
                        Label(
                            "Notifications are required for this channel.",
                            mappedSystemImage: "bell.badge"
                        )
                        .foregroundStyle(.secondary)
                    }

                    if let errorMessage = store.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}

struct CommunicationChannelPostRow: View {
    let store: StoreOf<CommunicationChannelDetail>
    let post: CommsPost

    var body: some View {
        let isRead = store.readPostIDs.contains(post.id)
        Button {
            store.send(.postButtonTapped(post.id))
        } label: {
            CommsPostRowView(post: post, isRead: isRead)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("button.communication-post.\(post.id.postID.rawValue)")
        .contextMenu {
            Button {
                store.send(.markPostReadButtonTapped(post.id))
            } label: {
                Label(
                    "Mark as Read",
                    systemImage: isRead ? "checkmark" : "mail-open"
                )
            }
            .disabled(isRead)

            Button {
                store.send(.markPostUnreadButtonTapped(post.id))
            } label: {
                Label(
                    "Mark as Unread",
                    systemImage: isRead ? "mail-unread" : "checkmark"
                )
            }
            .disabled(!isRead)

            if store.canEditChannel {
                Button(role: .destructive) {
                    store.send(.deletePostButtonTapped(post.id))
                } label: {
                    Label("Delete Post", systemImage: "trash")
                }
            }
        }
        .swipeActions {
            if store.canEditChannel {
                Button(role: .destructive) {
                    store.send(.deletePostButtonTapped(post.id))
                } label: {
                    Label("Delete Post", systemImage: "trash")
                }
            }
        }
    }
}

struct PostDeleteError: Error {}

struct CommsPostRowView: View {
    let post: CommsPost
    let isRead: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if !isRead {
                        Circle()
                            .fill(.tint)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }

                    Text(post.title)
                        .font(.headline)
                        .fontWeight(isRead ? .regular : .semibold)
                        .foregroundStyle(.primary)

                    Spacer()
                }

                if let timestamp = post.timestamp {
                    Text(timestamp, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            CommsMarkdownText(post.contents)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
        }
        .padding(.vertical, 4)
        .accessibilityValue(Text(isRead ? "Read" : "Unread"))
    }
}

struct CommunicationChannelSettingsMenu: View {
    let store: StoreOf<CommunicationChannelDetail>
    let channel: OMERecord.Channel

    var body: some View {
        Menu {
            Button {
                store.send(.newPostButtonTapped)
            } label: {
                Label("New Post", mappedSystemImage: "square.and.pencil")
            }

            Button {
                store.send(.editChannelButtonTapped(channel))
            } label: {
                Label("Edit Channel", systemImage: "pencil")
            }

            Button(role: .destructive) {
                store.send(.deleteChannelButtonTapped)
            } label: {
                Label("Delete Channel", systemImage: "trash")
            }
        } label: {
            Label("Channel Settings", mappedSystemImage: "gearshape")
        }
    }
}

struct CommunicationChannelNotificationMenu: View {
    let store: StoreOf<CommunicationChannelDetail>
    let channel: OMERecord.Channel

    private var notificationState: OMERecord.Channel.NotificationState {
        store.effectiveNotificationState ?? channel.defaultNotificationState
    }

    private var isSubscribed: Bool {
        notificationState == .subscribed
    }

    private var isUnsubscribed: Bool {
        notificationState == .unsubscribed
    }

    private var subscribeSystemImage: String {
        isSubscribed ? "checkmark" : "bell"
    }

    private var unsubscribeSystemImage: String {
        isUnsubscribed ? "checkmark" : "bell.slash"
    }

    private var menuTitle: String {
        channel.notificationsRequired
            ? "Notifications Required"
            : "Notifications: \(notificationState.menuTitle)"
    }

    private var menuSystemImage: String {
        channel.notificationsRequired
            ? "bell.badge"
            : notificationState.systemImage
    }

    var body: some View {
        Menu {
            Button {
                store.send(.notificationStateButtonTapped(.subscribed))
            } label: {
                Label {
                    Text("Notify Me For New Posts")
                } icon: {
                    MappedSystemImage(systemName: subscribeSystemImage)
                }
            }
            .disabled(isSubscribed)
            .accessibilityIdentifier("button.channel-notifications.subscribe")

            Button {
                store.send(.notificationStateButtonTapped(.unsubscribed))
            } label: {
                Label {
                    Text("Don't Notify Me For New Posts")
                } icon: {
                    MappedSystemImage(systemName: unsubscribeSystemImage)
                }
            }
            .disabled(channel.notificationsRequired || isUnsubscribed)
            .accessibilityIdentifier("button.channel-notifications.unsubscribe")
        } label: {
            Label {
                Text(menuTitle)
            } icon: {
                MappedSystemImage(systemName: menuSystemImage)
            }
        }
        .accessibilityIdentifier(
            "menu.channel-notifications.\(channel.id.channelID.rawValue.rawValue)"
        )
    }
}
