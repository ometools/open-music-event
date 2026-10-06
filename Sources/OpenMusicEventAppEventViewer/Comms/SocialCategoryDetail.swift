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
public struct SocialCategoryDetail {
    public init() {}

    public struct State: Identifiable {
        public init(
            channelID: Social.Category.ID,
            eventID: Event.ID,
            destination: Destination.State? = nil
        ) {
            self._workspaceSession = .eventWorkspaceSession(for: eventID)
            self.currentWorkspaceAccount = CurrentWorkspaceAccount()
            self.channelID = channelID
            self.eventID = eventID
            self.destination = destination
            _channel = FetchOne(
                SocialCategoryDetail.channelQuery(channelID: channelID)
            )
            _preference = FetchOne(
                SocialCategoryDetail.preferenceQuery(channelID: channelID)
            )
            _posts = FetchAll(
                SocialCategoryDetail.postsQuery(channelID: channelID)
            )
            _postReads = FetchAll(
                SocialCategoryDetail.postReadsQuery()
            )
        }

        public let channelID: Social.Category.ID
        public let eventID: Event.ID
        @SharedReader
        public var workspaceSession: EventWorkspaceSession?
        @DebugSnapshotIgnored let currentWorkspaceAccount: CurrentWorkspaceAccount
        public var destination: Destination.State?
        public var errorMessage: String?
        public var isSavingPins = false

        @FetchOne public var channel: Social.Category?
        @FetchOne public var preference: ChannelPreferences?
        @FetchAll public var posts: [Social.Post]
        @FetchAll public var postReads: [CommsPostRead]

        public var id: Social.Category.ID { channelID }

        var canChangeNotificationState: Bool {
            channel?.notificationsRequired != true
        }

        public var canEditChannel: Bool {
            validatedWorkspaceSession != nil
        }

        var validatedWorkspaceSession: EventWorkspaceSession? {
            currentWorkspaceAccount.validated(workspaceSession, for: eventID)
        }

        func canEditPost(_ post: Social.Post) -> Bool {
            guard let session = validatedWorkspaceSession else { return false }
            return post.id.authority == .did(session.actorID)
        }

        var effectiveNotificationState: Social.Category.NotificationState? {
            channel?.effectiveNotificationState(preference: preference)
        }

        var pinnedPosts: [Social.Post] {
            let postsByID = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
            return (channel?.pinnedPosts ?? []).compactMap { postsByID[$0] }
        }

        var recentPosts: [Social.Post] {
            let pinnedIDs = Set(channel?.pinnedPosts ?? [])
            return posts.filter { !pinnedIDs.contains($0.id) }
        }

        var shouldShowEmptyPostsFooter: Bool {
            posts.isEmpty
        }

        var readPostIDs: Set<Social.Post.ID> {
            Set(postReads.map(\.id))
        }
    }

    public enum Action {
        case deleteChannelButtonTapped
        case editChannelButtonTapped(Social.Category)
        case markPostReadButtonTapped(Social.Post.ID)
        case markPostUnreadButtonTapped(Social.Post.ID)
        case deletePostButtonTapped(Social.Post.ID)
        case editPostButtonTapped(Social.Post.ID)
        case pinPostButtonTapped(Social.Post.ID)
        case unpinPostButtonTapped(Social.Post.ID)
        case movePinnedPostButtonTapped(Social.Post.ID, Int)
        case newPostButtonTapped
        case notificationStateButtonTapped(Social.Category.NotificationState)
        case postButtonTapped(Social.Post.ID)
        case destination(Destination.Action)
    }

    @Feature
    public enum Destination {
        case channelForm(SocialCategoryForm)
        case composer(SocialPostForm)
        case deleteChannelConfirmation(ChannelDeleteConfirmation)
        case postDeleteConfirmation(PostDeleteConfirmation)
        case postDetail(SocialPostDetail)
    }

    @Dependency(\.defaultDatabase) var database

    static func channelQuery(
        channelID: Social.Category.ID
    ) -> some SelectStatementOf<Social.Category> {
        Social.Category.where { $0.id.eq(channelID) }
    }

    static func preferenceQuery(
        channelID: Social.Category.ID
    ) -> some SelectStatementOf<ChannelPreferences> {
        ChannelPreferences.where { $0.id.eq(channelID) }
    }

    static func postsQuery(
        channelID: Social.Category.ID
    ) -> some SelectStatementOf<Social.Post> {
        Social.Post
            .where { $0.category.eq(channelID) }
            .order { $0.createdAt.desc() }
    }

    static func postReadsQuery() -> some SelectStatementOf<CommsPostRead> {
        CommsPostRead.all
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .deleteChannelButtonTapped:
                state.destination = .deleteChannelConfirmation(
                    ChannelDeleteConfirmation.State(channelID: state.channelID)
                )

            case let .editChannelButtonTapped(channel):
                state.destination = .channelForm(SocialCategoryForm.State(category: channel))

            case let .markPostReadButtonTapped(postID):
                updateReadState(true, postID: postID)

            case let .markPostUnreadButtonTapped(postID):
                updateReadState(false, postID: postID)

            case let .deletePostButtonTapped(postID):
                guard let post = state.posts.first(where: { $0.id == postID }),
                      state.canEditPost(post) else { return }
                state.destination = .postDeleteConfirmation(
                    PostDeleteConfirmation.State(postID: postID)
                )

            case let .editPostButtonTapped(postID):
                guard let post = state.posts.first(where: { $0.id == postID }),
                      state.canEditPost(post),
                      let author = state.validatedWorkspaceSession?.actorID else { return }
                state.destination = .composer(
                    SocialPostForm.State(post: post, eventID: state.eventID, author: author)
                )

            case let .pinPostButtonTapped(postID):
                guard state.canEditChannel, !state.isSavingPins,
                      state.channel != nil,
                      state.posts.contains(where: { $0.id == postID }) else { return }
                var pinned = state.channel?.pinnedPosts ?? []
                guard !pinned.contains(postID) else { return }
                pinned.append(postID)
                state.isSavingPins = true
                savePinnedPosts(pinned, eventID: state.eventID, categoryID: state.channelID)

            case let .unpinPostButtonTapped(postID):
                guard state.canEditChannel, !state.isSavingPins,
                      let pinned = state.channel?.pinnedPosts,
                      pinned.contains(postID) else { return }
                state.isSavingPins = true
                savePinnedPosts(
                    pinned.filter { $0 != postID },
                    eventID: state.eventID,
                    categoryID: state.channelID
                )

            case let .movePinnedPostButtonTapped(postID, offset):
                guard state.canEditChannel, !state.isSavingPins,
                      var pinned = state.channel?.pinnedPosts,
                      let index = pinned.firstIndex(of: postID),
                      pinned.indices.contains(index + offset) else { return }
                pinned.swapAt(index, index + offset)
                state.isSavingPins = true
                savePinnedPosts(pinned, eventID: state.eventID, categoryID: state.channelID)

            case .newPostButtonTapped:
                guard state.canEditChannel,
                      let author = state.validatedWorkspaceSession?.actorID else { return }
                state.destination = .composer(
                    SocialPostForm.State(
                        eventID: state.eventID,
                        categoryID: state.channelID,
                        author: author
                    )
                )

            case let .notificationStateButtonTapped(notificationState):
                guard
                    notificationState != .unsubscribed
                        || state.canChangeNotificationState
                else { return }
                updateNotificationState(notificationState, state: state)

            case let .postButtonTapped(postID):
                state.destination = .postDetail(
                    SocialPostDetail.State(postID: postID, eventID: state.eventID)
                )

            case let .destination(.deleteChannelConfirmation(.deleteButtonTapped(channelID))):
                guard channelID == state.channelID else { return }
                let eventID = state.eventID
                state.destination = nil
                store.addTask {
                    do {
                        try await database.write { db in
                            try SocialCategoryRecordEditing.delete(
                                channelID, eventID: eventID, in: db
                            )
                        }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to delete this channel."
                        }
                    }
                }

            case let .destination(.postDeleteConfirmation(.deleteButtonTapped(postID))):
                guard let post = state.posts.first(where: { $0.id == postID }),
                      state.canEditPost(post),
                      let author = state.validatedWorkspaceSession?.actorID else { return }
                state.destination = nil
                store.addTask {
                    do {
                        try await database.write { db in
                            try SocialPostRecordEditing.delete(postID, author: author, in: db)
                            try CommsPostRead.find(postID).delete().execute(db)
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
        .ifLet(\.destination) {
            Destination.body
        }
    }

    private func updateNotificationState(
        _ notificationState: Social.Category.NotificationState,
        state: SocialCategoryDetail.State
    ) {
        guard state.channel != nil else { return }

        let channelPreference = ChannelPreferences(
            id: state.channelID,
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

    func updateReadState(_ isRead: Bool, postID: Social.Post.ID) {
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

    private func savePinnedPosts(
        _ postIDs: [Social.Post.ID],
        eventID: Event.ID,
        categoryID: Social.Category.ID
    ) {
        store.addTask {
            do {
                try await database.write { db in
                    try SocialCategoryRecordEditing.setPinnedPosts(
                        postIDs,
                        categoryID: categoryID,
                        eventID: eventID,
                        in: db
                    )
                }
                try store.modify {
                    $0.errorMessage = nil
                    $0.isSavingPins = false
                }
            } catch {
                try store.modify {
                    $0.errorMessage = "Unable to update pinned posts."
                    $0.isSavingPins = false
                }
            }
        }
    }

}

@Feature
public struct PostDeleteConfirmation: Prompt {
    public struct State: Identifiable {
        public init(postID: Social.Post.ID) {
            self.postID = postID
        }

        public let postID: Social.Post.ID
        public var id: Social.Post.ID { postID }
    }

    public enum Action {
        case deleteButtonTapped(Social.Post.ID)
    }
}

public struct SocialCategoryDetailView: View {
    @Bindable var store: StoreOf<SocialCategoryDetail>

    public init(store: StoreOf<SocialCategoryDetail>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let channel = store.channel {
                SocialCategoryControlsView(store: store, channel: channel)
            } else {
                ViewerPlaceholderView(
                    title: "Channel",
                    systemImage: "megaphone",
                    description: "This communication channel could not be loaded."
                )
            }
        }
        .sheet(
            item: $store.scope(\.destination).composer
        ) { composerStore in
            NavigationStack {
                SocialPostFormView(store: composerStore)
            }
        }
        .accessibilityIdentifier(
            "view.channel-detail.\(store.channelID.description)"
        )
    }
}

struct SocialCategoryControlsView: View {
    @Bindable var store: StoreOf<SocialCategoryDetail>
    let channel: Social.Category

    init(
        store: StoreOf<SocialCategoryDetail>,
        channel: Social.Category
    ) {
        self.store = store
        self.channel = channel
    }

    var body: some View {
        SocialCategoryFormSheetView(store: store, channel: channel)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SocialCategoryNotificationMenu(
                        store: store,
                        channel: channel
                    )
                }

                if store.canEditChannel {
                    ToolbarItem(placement: .primaryAction) {
                        SocialCategorySettingsMenu(
                            store: store,
                            channel: channel
                        )
                    }
                }
            }
            .confirmationDialog(
                "Delete Channel?",
                isPresented: $store.scope(\.destination).deleteChannelConfirmation.isPresented,
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
                Text("Move or delete this channel's posts before deleting it.")
            }
            .confirmationDialog(
                "Delete Post?",
                isPresented: $store.scope(\.destination).postDeleteConfirmation.isPresented,
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

struct SocialCategoryFormSheetView: View {
    @Bindable var store: StoreOf<SocialCategoryDetail>
    let channel: Social.Category

    init(
        store: StoreOf<SocialCategoryDetail>,
        channel: Social.Category
    ) {
        self.store = store
        self.channel = channel
    }

    var body: some View {
        SocialCategoryComposerSheetView(store: store, channel: channel)
            .sheet(
                item: $store.scope(\.destination).channelForm
            ) { formStore in
                NavigationStack {
                    SocialCategoryFormView(store: formStore)
                }
            }
    }
}

struct SocialCategoryComposerSheetView: View {
    @Bindable var store: StoreOf<SocialCategoryDetail>
    let channel: Social.Category

    init(
        store: StoreOf<SocialCategoryDetail>,
        channel: Social.Category
    ) {
        self.store = store
        self.channel = channel
    }

    var body: some View {
        SocialCategoryPostDestinationView(store: store, channel: channel)
    }
}

struct SocialCategoryPostDestinationView: View {
    @Bindable var store: StoreOf<SocialCategoryDetail>
    let channel: Social.Category

    init(
        store: StoreOf<SocialCategoryDetail>,
        channel: Social.Category
    ) {
        self.store = store
        self.channel = channel
    }

    var body: some View {
        SocialCategoryDetailList(store: store, channel: channel)
            .navigationTitle(channel.name)
            .navigationDestination(
                item: $store.scope(\.destination).postDetail
            ) { postStore in
                SocialPostDetailView(store: postStore)
            }
    }
}

struct SocialCategoryDetailList: View {
    let store: StoreOf<SocialCategoryDetail>
    let channel: Social.Category

    var body: some View {
        List {
            Section {
                Text(channel.description ?? "")
                    .font(.subheadline)
            } footer: {
                if store.shouldShowEmptyPostsFooter && !store.canEditChannel {
                    Text("There are no posts in this channel yet.")
                }
            }

            if store.shouldShowEmptyPostsFooter && store.canEditChannel {
                Section {
                    Text("Write the first post to share an update in this channel.")
                        .foregroundStyle(.secondary)
                    Button("New Post") { store.send(.newPostButtonTapped) }
                }
            }

            SocialPostList(store: store)

            if channel.notificationsRequired == true {
                Section("Notifications") {
                    Label(
                        "Notifications are required for this channel.",
                        mappedSystemImage: "bell.badge"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

struct SocialCategorySettingsMenu: View {
    let store: StoreOf<SocialCategoryDetail>
    let channel: Social.Category

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

struct SocialCategoryNotificationMenu: View {
    let store: StoreOf<SocialCategoryDetail>
    let channel: Social.Category

    private var notificationState: Social.Category.NotificationState {
        store.effectiveNotificationState ?? channel.effectiveNotificationState(preference: store.preference)
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
        channel.notificationsRequired == true
            ? "Notifications Required"
            : "Notifications: \(notificationState.menuTitle)"
    }

    private var menuSystemImage: String {
        channel.notificationsRequired == true
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
            .disabled(channel.notificationsRequired == true || isUnsubscribed)
            .accessibilityIdentifier("button.channel-notifications.unsubscribe")
        } label: {
            Label {
                Text(menuTitle)
            } icon: {
                MappedSystemImage(systemName: menuSystemImage)
            }
        }
        .accessibilityIdentifier(
            "menu.channel-notifications.\(channel.id.description)"
        )
    }
}
