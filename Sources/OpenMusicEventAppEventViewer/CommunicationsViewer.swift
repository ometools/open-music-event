import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventDatabase
import SQLiteData
import SwiftUI
import Tagged

struct CommunicationChannelRow: Equatable, Identifiable, Sendable {
    let channel: OMERecord.Channel
    let preference: ChannelPreferences?

    var id: OMERecord.Channel.ID { channel.id }

    var effectiveNotificationState: OMERecord.Channel.NotificationState {
        preference?.notificationState ?? channel.defaultNotificationState
    }
}

@Feature
public struct CommunicationsViewer {
    public init() {}

    public struct State {
        public let eventID: OMERecord.Event.ID
        public var destination: Destination.State?

        @FetchAll public var channels: [OMERecord.Channel]
        @FetchAll public var channelPreferences: [ChannelPreferences]
        @FetchOne public var event: OMERecord.Event?

        public init(
            eventID: OMERecord.Event.ID,
            destination: Destination.State? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            _channels = FetchAll(CommunicationsViewer.channelsQuery(eventID: eventID))
            _channelPreferences = FetchAll(CommunicationsViewer.channelPreferencesQuery(eventID: eventID))
            _event = FetchOne(OMERecord.Event.where { $0.id.eq(eventID) })
        }

        var channelRows: [CommunicationChannelRow] {
            let preferencesByID = Dictionary(
                uniqueKeysWithValues: channelPreferences.map { ($0.id, $0) }
            )
            return channels.map { channel in
                CommunicationChannelRow(
                    channel: channel,
                    preference: preferencesByID[channel.id]
                )
            }
        }

        var hasContent: Bool {
            event != nil && (event?.reportingLink != nil || !channels.isEmpty)
        }
    }

    public enum Action {
        case channelButtonTapped(OMERecord.ID<OMERecord.Channel>)
        case destination(Destination.Action)
    }

    @Feature
    public enum Destination {
        case channelDetail(Spawn<CommunicationChannelDetail>)
    }

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
            case let .channelButtonTapped(channelID):
                store.withDependencies {
                    state.destination = .channelDetail(
                        Spawn(
                            CommunicationChannelDetail.State(
                                channelID: channelID,
                                eventID: state.eventID
                            )
                        )
                    )
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
                    if let reportingLink = store.event?.reportingLink {
                        Section("Incident Reporting") {
                            Link(destination: reportingLink.url) {
                                ReportingLinkLabel(reportingLink: reportingLink)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens this event's reporting link in a browser.")
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
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .navigationTitle("Comms")
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
        .navigationDestination(item: $store.scope(\.destination, action: \.destination).channelDetail) { detailStore in
            CommunicationChannelDetailView(store: detailStore)
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
        }

        public let channelID: OMERecord.ID<OMERecord.Channel>
        public let eventID: OMERecord.Event.ID
        public var destination: Destination.State?
        public var errorMessage: String?

        @FetchOne public var channel: OMERecord.Channel?
        @FetchOne public var preference: ChannelPreferences?
        @FetchAll public var posts: [CommsPost]

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

        var effectiveNotificationState: OMERecord.Channel.NotificationState? {
            preference?.notificationState ?? channel?.defaultNotificationState
        }

        var isSubscribed: Bool {
            effectiveNotificationState == .subscribed
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
    }

    public enum Action {
        case notifyMeButtonTapped
        case postButtonTapped(CommsPost.ID)
        case stopNotifyingMeButtonTapped
        case destination(Destination.Action)
    }

    @Feature
    public enum Destination {
        case postDetail(Spawn<CommsPostDetail>)
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

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .notifyMeButtonTapped:
                updateNotificationState(.subscribed, state: state)

            case let .postButtonTapped(postID):
                guard let post = state.posts.first(where: { $0.id == postID })
                else { return }
                store.withDependencies {
                    state.destination = .postDetail(
                        Spawn(CommsPostDetail.State(post: post))
                    )
                }

            case .stopNotifyingMeButtonTapped:
                guard state.canChangeNotificationState else { return }
                updateNotificationState(.unsubscribed, state: state)

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
                                Button {
                                    store.send(.postButtonTapped(post.id))
                                } label: {
                                    CommsPostRowView(post: post)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !store.recentPosts.isEmpty {
                        Section("Recent Posts") {
                            ForEach(store.recentPosts) { post in
                                Button {
                                    store.send(.postButtonTapped(post.id))
                                } label: {
                                    CommsPostRowView(post: post)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Section("Notifications") {
                        LabeledContent("Default", value: channel.defaultNotificationState.menuTitle)

                        if let effectiveNotificationState = store.effectiveNotificationState {
                            LabeledContent("Current", value: effectiveNotificationState.menuTitle)
                        }

                        if channel.notificationsRequired {
                            Label("Notifications are required for this channel.", systemImage: "bell.badge")
                                .foregroundStyle(.secondary)
                        }

                        if let errorMessage = store.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .navigationTitle(channel.name)
                .navigationDestination(item: $store.scope(\.destination, action: \.destination).postDetail) { postStore in
                    CommsPostDetailView(store: postStore)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 8) {
                            if store.isSubscribed {
                                Image(systemName: "bell.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .font(.caption)
                            }

                            Menu {
                                if store.isSubscribed {
                                    Button {
                                        store.send(.stopNotifyingMeButtonTapped)
                                    } label: {
                                        Label("Don't Notify Me For New Posts", systemImage: "bell.slash")
                                    }
                                } else {
                                    Button {
                                        store.send(.notifyMeButtonTapped)
                                    } label: {
                                        Label("Notify Me For New Posts", systemImage: "bell")
                                    }
                                }
                            } label: {
                                Label("Options", systemImage: "ellipsis")
                            }
                            .disabled(channel.notificationsRequired)
                        }
                    }
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
}

@Feature
public struct CommsPostDetail {
    public init() {}

    public struct State: Identifiable {
        public init(post: CommsPost) {
            self.post = post
        }

        public var post: CommsPost
        public var id: CommsPost.ID { post.id }
    }

    public enum Action {}

    public var body: some Feature {
        Update { _, _ in }
    }
}

public struct CommsPostDetailView: View {
    let store: StoreOf<CommsPostDetail>

    public init(store: StoreOf<CommsPostDetail>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let headerImageURL = store.post.headerImageURL {
                    AsyncImage(url: headerImageURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(store.post.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let timestamp = store.post.timestamp {
                        Text(timestamp, format: .relative(presentation: .named))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                CommsMarkdownText(store.post.contents)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }
}

struct CommsPostRowView: View {
    let post: CommsPost

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(post.title)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Spacer()

                if let timestamp = post.timestamp {
                    Text(timestamp, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(post.contents)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
        }
        .padding(.vertical, 4)
    }
}

struct CommsMarkdownText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        #if os(Android)
        Text(text)
        #else
        if let markdown = try? AttributedString(
            markdown: text,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            Text(markdown)
        } else {
            Text(text)
        }
        #endif
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

            notificationImage
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    var notificationImage: some View {
        if row.channel.notificationsRequired {
            Image(systemName: "bell.badge")
                .accessibilityLabel("Notifications required")
        } else if row.effectiveNotificationState == .subscribed {
            Image(systemName: "bell.fill")
                .accessibilityLabel("Notifications enabled")
        }
    }
}

struct ReportingLinkLabel: View {
    let reportingLink: OMERecord.Event.ReportingLink

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(reportingLink.name)
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(.red, in: RoundedRectangle(cornerRadius: 8))

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
}
