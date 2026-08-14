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

struct CommunicationChannelRow: Equatable, Identifiable, Sendable {
    let channel: OMERecord.Channel
    let preference: ChannelPreferences?
    let unreadPostCount: Int

    var id: OMERecord.Channel.ID { channel.id }

    var effectiveNotificationState: OMERecord.Channel.NotificationState {
        channel.effectiveNotificationState(preference: preference)
    }

    var notificationSystemImage: String {
        channel.notificationsRequired
            ? "bell.badge"
            : effectiveNotificationState.systemImage
    }
}

@Feature
public struct ChannelDeleteConfirmation: Prompt {
    public struct State: Identifiable {
        public init(channelID: OMERecord.ID<OMERecord.Channel>) {
            self.channelID = channelID
        }

        public let channelID: OMERecord.ID<OMERecord.Channel>
        public var id: OMERecord.ID<OMERecord.Channel> { channelID }
    }

    public enum Action {
        case deleteButtonTapped(OMERecord.ID<OMERecord.Channel>)
    }
}

@Feature
public struct CommunicationsViewer {
    public init() {}

    public struct State {
        public let eventID: OMERecord.Event.ID
        @SharedReader(.defaultAuthoringGrant)
        public var authoringGrant: AuthoringGrant?
        @SharedReader(.devicePermissions)
        public var permissions: DevicePermissions
        public var destination: Destination.State?
        public var errorMessage: String?

        @FetchAll public var channels: [OMERecord.Channel]
        @FetchAll public var channelPreferences: [ChannelPreferences]
        @FetchOne public var event: OMERecord.Event?
        @Fetch public var unreadPostCounts: CommsUnreadPostCounts

        public init(
            eventID: OMERecord.Event.ID,
            destination: Destination.State? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            _channels = FetchAll(CommunicationsViewer.channelsQuery(eventID: eventID))
            _channelPreferences = FetchAll(CommunicationsViewer.channelPreferencesQuery(eventID: eventID))
            _event = FetchOne(OMERecord.Event.where { $0.id.eq(eventID) })
            _unreadPostCounts = Fetch(
                wrappedValue: CommsUnreadPostCounts(),
                CommsUnreadPostCountsRequest(eventIDs: [eventID])
            )
        }

        var channelRows: [CommunicationChannelRow] {
            let preferencesByID = Dictionary(
                uniqueKeysWithValues: channelPreferences.map { ($0.id, $0) }
            )
            return channels.map { channel in
                CommunicationChannelRow(
                    channel: channel,
                    preference: preferencesByID[channel.id],
                    unreadPostCount: unreadPostCounts.count(for: channel.id)
                )
            }
        }

        var hasContent: Bool {
            event != nil && (
                shouldShowNotificationPrompt
                    || !(event?.reportingLinks ?? []).isEmpty
                    || !channels.isEmpty
            )
        }

        var shouldShowNotificationPrompt: Bool {
            !permissions.notificationsAreAllowed
        }

        public var canManageChannels: Bool {
            authoringGrant?.access.canEditContent == true
        }

        public var unreadPostCount: Int {
            unreadPostCounts.count(for: eventID)
        }
    }

    public enum Action {
        case addChannelButtonTapped
        case channelButtonTapped(OMERecord.ID<OMERecord.Channel>)
        case deleteChannelButtonTapped(OMERecord.ID<OMERecord.Channel>)
        case destination(Destination.Action)
        case editChannelButtonTapped(OMERecord.Channel)
        case markAllPostsReadButtonTapped(OMERecord.Channel.ID)
        case markAllPostsUnreadButtonTapped(OMERecord.Channel.ID)
        case notificationPermissionButtonTapped
        case notificationStateButtonTapped(
            OMERecord.Channel.ID,
            OMERecord.Channel.NotificationState
        )
        case openNotificationSettingsButtonTapped
    }

    @Feature
    public enum Destination {
        case channelForm(ChannelForm)
        case channelDetail(CommunicationChannelDetail)
        case deleteChannelConfirmation(ChannelDeleteConfirmation)
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.devicePermissions) var devicePermissions

    static func channelsQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Channel> {
        OMERecord.Channel
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { ($0.sortIndex.asc(nulls: .last), $0.name.collate(.nocase)) }
    }

    static func channelPreferencesQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<ChannelPreferences> {
        ChannelPreferences
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addChannelButtonTapped:
                guard state.canManageChannels else { return }
                state.destination = .channelForm(
                    ChannelForm.State(eventID: state.eventID)
                )

            case let .channelButtonTapped(channelID):
                state.destination = .channelDetail(
                    CommunicationChannelDetail.State(
                        channelID: channelID,
                        eventID: state.eventID
                    )
                )

            case let .deleteChannelButtonTapped(channelID):
                state.destination = .deleteChannelConfirmation(
                    ChannelDeleteConfirmation.State(channelID: channelID)
                )

            case let .destination(.deleteChannelConfirmation(.deleteButtonTapped(channelID))):
                let recordID = OMERecord.Channel.ID(
                    organizerID: state.eventID.organizerID,
                    eventID: state.eventID.eventID,
                    channelID: channelID
                )
                state.destination = nil
                store.addTask {
                    do {
                        try await database.write { db in
                            try OMERecord.Channel.find(recordID).delete().execute(db)
                        }
                        try store.modify { $0.errorMessage = nil }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to delete this channel."
                        }
                    }
                }

            case let .editChannelButtonTapped(channel):
                state.destination = .channelForm(ChannelForm.State(channel: channel))

            case let .markAllPostsReadButtonTapped(channelID):
                store.addTask {
                    do {
                        try await database.write { database in
                            try CommsPostRead.setRead(
                                true,
                                channelID: channelID,
                                in: database
                            )
                        }
                        try store.modify { $0.errorMessage = nil }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to mark all posts in this channel as read."
                        }
                    }
                }

            case let .markAllPostsUnreadButtonTapped(channelID):
                store.addTask {
                    do {
                        try await database.write { database in
                            try CommsPostRead.setRead(
                                false,
                                channelID: channelID,
                                in: database
                            )
                        }
                        try store.modify { $0.errorMessage = nil }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to mark all posts in this channel as unread."
                        }
                    }
                }

            case .notificationPermissionButtonTapped:
                store.addTask {
                    do {
                        _ = try await devicePermissions.requestNotifications()
                        try await store.state.$permissions.load()
                        try store.modify { $0.errorMessage = nil }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to request notification permission."
                        }
                    }
                }

            case let .notificationStateButtonTapped(channelID, notificationState):
                guard
                    let channel = state.channels.first(where: { $0.id == channelID }),
                    notificationState != .unsubscribed || !channel.notificationsRequired
                else { return }

                let channelPreference = ChannelPreferences(
                    id: channelID,
                    notificationState: notificationState
                )
                store.addTask {
                    do {
                        try await database.write { db in
                            try ChannelPreferences.upsert { channelPreference }.execute(db)
                        }
                        try store.modify {
                            $0.errorMessage = nil
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to update notification preference."
                        }
                    }
                }

            case .openNotificationSettingsButtonTapped:
                store.addTask {
                    _ = await devicePermissions.openNotificationSettings()
                }

            case .destination:
                break
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct CommunicationsViewerView: View {
    @Bindable var store: StoreOf<CommunicationsViewer>

    public init(store: StoreOf<CommunicationsViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasContent {
                List {
                    if store.shouldShowNotificationPrompt {
                        Section {
                            Button {
                                if store.permissions.notifications == .unknown {
                                    store.send(.notificationPermissionButtonTapped)
                                } else {
                                    store.send(.openNotificationSettingsButtonTapped)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    MappedSystemImage(systemName: "bell.badge")
                                        .frame(width: 24, height: 24)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Turn On Notifications")
                                            .foregroundStyle(.primary)
                                        Text("This event wants to send you important updates.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text(
                                        store.permissions.notifications == .unknown
                                            ? "Allow"
                                            : "Settings"
                                    )
                                    .font(.subheadline.weight(.semibold))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if store.channelRows.isEmpty {
                        Section {
                            Text("No communication channels have been added to this event yet.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Section("Channels") {
                            ForEach(store.channelRows) { row in
                                Button {
                                    store.send(.channelButtonTapped(row.channel.id.channelID))
                                } label: {
                                    CommunicationChannelRowView(row: row)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .portableContentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if !row.channel.notificationsRequired {
                                        if row.effectiveNotificationState == .subscribed {
                                            Button {
                                                store.send(
                                                    .notificationStateButtonTapped(
                                                        row.channel.id,
                                                        .unsubscribed
                                                    )
                                                )
                                            } label: {
                                                Label(
                                                    "Don't Notify Me For New Posts",
                                                    mappedSystemImage: "bell.slash"
                                                )
                                            }
                                        } else {
                                            Button {
                                                store.send(
                                                    .notificationStateButtonTapped(
                                                        row.channel.id,
                                                        .subscribed
                                                    )
                                                )
                                            } label: {
                                                Label(
                                                    "Notify Me For New Posts",
                                                    mappedSystemImage: "bell"
                                                )
                                            }
                                        }
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if store.canManageChannels {
                                        Button {
                                            store.send(.editChannelButtonTapped(row.channel))
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }

                                        Button(role: .destructive) {
                                            store.send(
                                                .deleteChannelButtonTapped(row.channel.id.channelID)
                                            )
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        store.send(
                                            .markAllPostsReadButtonTapped(row.channel.id)
                                        )
                                    } label: {
                                        Label("Mark All as Read", systemImage: "mail-open")
                                    }

                                    Button {
                                        store.send(
                                            .markAllPostsUnreadButtonTapped(row.channel.id)
                                        )
                                    } label: {
                                        Label("Mark All as Unread", systemImage: "mail-unread")
                                    }

                                    Divider()

                                    Menu {
                                        Button {
                                            store.send(
                                                .notificationStateButtonTapped(
                                                    row.channel.id,
                                                    .subscribed
                                                )
                                            )
                                        } label: {
                                            Label(
                                                "Notify Me For New Posts",
                                                mappedSystemImage: row.effectiveNotificationState == .subscribed
                                                    ? "checkmark"
                                                    : "bell"
                                            )
                                        }
                                        .disabled(row.effectiveNotificationState == .subscribed)

                                        Button {
                                            store.send(
                                                .notificationStateButtonTapped(
                                                    row.channel.id,
                                                    .unsubscribed
                                                )
                                            )
                                        } label: {
                                            Label(
                                                "Don't Notify Me For New Posts",
                                                mappedSystemImage: row.effectiveNotificationState == .unsubscribed
                                                    ? "checkmark"
                                                    : "bell.slash"
                                            )
                                        }
                                        .disabled(
                                            row.channel.notificationsRequired
                                                || row.effectiveNotificationState == .unsubscribed
                                        )
                                    } label: {
                                        Label(
                                            "Notifications: \(row.effectiveNotificationState.menuTitle)",
                                            mappedSystemImage: row.notificationSystemImage
                                        )
                                    }

                                    if store.canManageChannels {
                                        Divider()

                                        Button {
                                            store.send(.editChannelButtonTapped(row.channel))
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }

                                        Button(role: .destructive) {
                                            store.send(
                                                .deleteChannelButtonTapped(row.channel.id.channelID)
                                            )
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
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
            } else {
                ViewerPlaceholderView(
                    title: "Comms",
                    systemImage: "megaphone",
                    description: store.event == nil
                        ? "This event could not be loaded."
                        : "No communication channels have been added to this event yet."
                )
            }
        }
        .navigationTitle("Comms")
        .navigationDestination(item: $store.scope(\.destination, action: \.destination).channelDetail) { detailStore in
            CommunicationChannelDetailView(store: detailStore)
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).channelForm) { formStore in
            NavigationStack {
                ChannelFormView(store: formStore)
            }
        }
        .toolbar {
            if store.canManageChannels {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.addChannelButtonTapped)
                    } label: {
                        Label("Add Channel", systemImage: "plus")
                    }
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
                if let channelID = store.destination?.deleteChannelConfirmation?.channelID {
                    store.send(
                        .destination(
                            .deleteChannelConfirmation(
                                .deleteButtonTapped(channelID)
                            )
                        )
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the channel. Posts already published in it are not changed.")
        }
    }
}

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
            .order { ($0.sortIndex, $0.title.collate(.nocase)) }
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
                try database.write { db in
                    try ChannelPreferences.upsert { channelPreference }.execute(db)
                }
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

public struct CommunicationChannelDetailView: View {
    @Bindable var store: StoreOf<CommunicationChannelDetail>

    public init(store: StoreOf<CommunicationChannelDetail>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let channel = store.channel {
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
                                postRow(post)
                            }
                        }
                    }

                    if !store.recentPosts.isEmpty {
                        Section("Recent Posts") {
                            ForEach(store.recentPosts) { post in
                                postRow(post)
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
                .navigationTitle(channel.name)
                .navigationDestination(item: $store.scope(\.destination, action: \.destination).postDetail) { postStore in
                    CommsPostDetailView(store: postStore)
                }
                .sheet(item: $store.scope(\.destination, action: \.destination).composer) { composerStore in
                    NavigationStack {
                        CommsPostComposerView(store: composerStore)
                    }
                }
                .sheet(item: $store.scope(\.destination, action: \.destination).channelForm) { formStore in
                    NavigationStack {
                        ChannelFormView(store: formStore)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                store.send(.notificationStateButtonTapped(.subscribed))
                            } label: {
                                Label(
                                    "Notify Me For New Posts",
                                    mappedSystemImage: store.effectiveNotificationState == .subscribed
                                        ? "checkmark"
                                        : "bell"
                                )
                            }
                            .disabled(store.effectiveNotificationState == .subscribed)

                            Button {
                                store.send(.notificationStateButtonTapped(.unsubscribed))
                            } label: {
                                Label(
                                    "Don't Notify Me For New Posts",
                                    mappedSystemImage: store.effectiveNotificationState == .unsubscribed
                                        ? "checkmark"
                                        : "bell.slash"
                                )
                            }
                            .disabled(
                                channel.notificationsRequired
                                    || store.effectiveNotificationState == .unsubscribed
                            )
                        } label: {
                            Label(
                                channel.notificationsRequired
                                    ? "Notifications Required"
                                    : "Notifications: \(store.effectiveNotificationState?.menuTitle ?? channel.defaultNotificationState.menuTitle)",
                                mappedSystemImage: channel.notificationsRequired
                                    ? "bell.badge"
                                    : (store.effectiveNotificationState ?? channel.defaultNotificationState).systemImage
                            )
                        }
                    }

                    if store.canEditChannel {
                        ToolbarItem(placement: .primaryAction) {
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
            } else {
                ViewerPlaceholderView(
                    title: "Channel",
                    systemImage: "megaphone",
                    description: "This communication channel could not be loaded."
                )
            }
        }
    }

    @ViewBuilder
    func postRow(_ post: CommsPost) -> some View {
        let isRead = store.readPostIDs.contains(post.id)
        Button {
            store.send(.postButtonTapped(post.id))
        } label: {
            CommsPostRowView(post: post, isRead: isRead)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
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
        }
    }
}

@Feature
public struct CommsPostDetail {
    public init() {}

    public struct State: Identifiable {
        public init(postID: CommsPost.ID) {
            self.postID = postID
            _post = FetchOne(CommsPost.where { $0.id.eq(postID) })
        }

        public let postID: CommsPost.ID
        @FetchOne public var post: CommsPost?
        public var errorMessage: String?
        public var id: CommsPost.ID { postID }
    }

    public enum Action {
        case postBecameVisible
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .postBecameVisible:
                guard state.post != nil else { return }
                let postID = state.postID
                store.addTask {
                    do {
                        try await database.write { database in
                            try CommsPostRead.setRead(true, postID: postID, in: database)
                        }
                        try store.modify {
                            $0.errorMessage = nil
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to mark this post as read."
                        }
                    }
                }
            }
        }
    }
}

public struct CommsPostDetailView: View {
    let store: StoreOf<CommsPostDetail>

    public init(store: StoreOf<CommsPostDetail>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let post = store.post {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let headerImageURL = post.headerImageURL {
                            CachedRemoteImage(url: headerImageURL) { phase in
                                switch phase {
                                case let .success(image, _):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                case .empty:
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                case .failure, .unavailable:
                                    Color.clear
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(post.title)
                                .font(.title2)
                                .fontWeight(.bold)

                            if let timestamp = post.timestamp {
                                Text(timestamp, format: .relative(presentation: .named))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        CommsMarkdownText(post.contents)
                            .multilineTextAlignment(.leading)

                        if let errorMessage = store.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        ForEach((post.images ?? []).indices, id: \.self) { index in
                            let image = (post.images ?? [])[index]
                            ImageAssetAsyncImage(
                                asset: image,
                                cacheContext: LocalImageCacheContext(commsPostID: post.id),
                                contentMode: .fit
                            ) {
                                ImageAssetPickerThumbnailPlaceholder()
                            }
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .task(id: post.id) {
                    await store.send(.postBecameVisible)?.value
                }
            } else {
                ViewerPlaceholderView(
                    title: "Post",
                    systemImage: "doc.text",
                    description: "This post could not be loaded."
                )
            }
        }
    }
}

struct CommsPostRowView: View {
    let post: CommsPost
    let isRead: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

struct CommsMarkdownText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        #if os(Android)
        Text(CommsMarkdown.fallbackText(text))
        #else
        Text(CommsMarkdown.renderedText(text))
        #endif
    }
}

enum CommsMarkdown {
    static func fallbackText(_ markdown: String) -> String {
        markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                var text = String(line)
                while text.first == "#" {
                    text.removeFirst()
                }
                text = text.trimmingCharacters(in: .whitespaces)

                if text.hasPrefix("- ") || text.hasPrefix("* ") {
                    text = "• " + String(text.dropFirst(2))
                }

                return text
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "*", with: "")
                    .replacingOccurrences(of: "`", with: "")
            }
            .joined(separator: "\n")
    }

    static func renderedText(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(markdown)
    }

    static func richEditorText(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(markdown)
    }

    @available(iOS 26.0, macOS 26.0, *)
    static func markdown(from richText: AttributedString) -> String {
        richText.runs.map { run in
            var text = String(richText[run.range].characters)
            let intents = run.inlinePresentationIntent ?? []

            if intents.contains(.code) {
                return "`\(text)`"
            }
            if intents.contains(.stronglyEmphasized) {
                text = "**\(text)**"
            }
            if intents.contains(.emphasized) {
                text = "*\(text)*"
            }
            if intents.contains(.strikethrough) {
                text = "~~\(text)~~"
            }
            return text
        }
        .joined()
    }
}

struct CommunicationChannelRowView: View {
    let row: CommunicationChannelRow

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.channel.name)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                if let description = row.channel.displayDescription {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if row.unreadPostCount > 0 {
                Text("\(row.unreadPostCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .portableMonospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.tint, in: Capsule())
                    .accessibilityLabel(
                        Text("Unread posts: \(row.unreadPostCount)")
                    )
            }

            notificationImage
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    var notificationImage: some View {
        if row.channel.notificationsRequired {
            MappedSystemImage(systemName: "bell.badge")
                .frame(width: 20, height: 20)
                .accessibilityLabel("Notifications required")
        } else if row.effectiveNotificationState == .subscribed {
            MappedSystemImage(systemName: "bell.fill")
                .frame(width: 20, height: 20)
                .accessibilityLabel("Notifications enabled")
        }
    }
}

struct IncidentReportingLinkRow: View {
    let reportingLink: OMERecord.Event.ReportingLink

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Link(destination: reportingLink.url) {
                Text(reportingLink.name)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .portableAccessibilityHint(
                Text("Opens \(reportingLink.name) in a browser.")
            )

            if let description = reportingLink.displayDescription {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private extension OMERecord.Event.ReportingLink {
    var displayDescription: String? {
        guard let description else { return nil }

        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension OMERecord.Channel {
    var displayDescription: String? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension OMERecord.Channel.NotificationState {
    var menuTitle: String {
        switch self {
        case .subscribed:
            "Subscribed"
        case .unsubscribed:
            "Unsubscribed"
        }
    }

    var systemImage: String {
        switch self {
        case .subscribed:
            "bell.fill"
        case .unsubscribed:
            "bell.slash"
        }
    }
}
