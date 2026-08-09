import ComposableArchitecture2
import ComposableAuthoring
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventSourceEditing
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
        public var canManageChannels = false
        public var destination: Destination.State?
        public var errorMessage: String?

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
            event != nil && (!(event?.reportingLinks ?? []).isEmpty || !channels.isEmpty)
        }
    }

    public enum Action {
        case addChannelButtonTapped
        case channelButtonTapped(OMERecord.ID<OMERecord.Channel>)
        case deleteChannelButtonTapped(OMERecord.ID<OMERecord.Channel>)
        case destination(Destination.Action)
        case editChannelButtonTapped(OMERecord.Channel)
    }

    @Feature
    public enum Destination {
        case channelForm(Spawn<ChannelForm>)
        case channelDetail(Spawn<CommunicationChannelDetail>)
        case deleteChannelConfirmation(ChannelDeleteConfirmation)
    }

    @Dependency(\.defaultDatabase) var database
    @FeatureEnvironment(ComposableAuthoring.AuthoringContext<AuthoringGrant>.self)
    var authoring

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
                    Spawn(ChannelForm.State(eventID: state.eventID))
                )

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
                state.destination = .channelForm(Spawn(ChannelForm.State(channel: channel)))

            case .destination:
                break
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .onChange(of: authoring.grant.wrappedValue, initial: true) { _, grant, state in
            state.canManageChannels = grant?.access.canEditContent == true
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
                    if store.channelRows.isEmpty {
                        Section {
                            Text("No communication channels have been added to this event yet.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Section("Channels") {
                            ForEach(store.channelRows) { row in
                                HStack(spacing: 12) {
                                    Button {
                                        store.send(.channelButtonTapped(row.channel.id.channelID))
                                    } label: {
                                        CommunicationChannelRowView(row: row)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .portableContentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    if store.canManageChannels {
                                        Menu {
                                            Button {
                                                store.send(
                                                    .editChannelButtonTapped(row.channel)
                                                )
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
                                        } label: {
                                            Label("Channel actions", systemImage: "ellipsis")
                                                .labelStyle(.iconOnly)
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
        }

        public let channelID: OMERecord.ID<OMERecord.Channel>
        public let eventID: OMERecord.Event.ID
        public var destination: Destination.State?
        public var errorMessage: String?
        public var canEditChannel = false

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
        case deleteChannelButtonTapped
        case editChannelButtonTapped(OMERecord.Channel)
        case notifyMeButtonTapped
        case newPostButtonTapped
        case postButtonTapped(CommsPost.ID)
        case stopNotifyingMeButtonTapped
        case destination(Destination.Action)
    }

    @Feature
    public enum Destination {
        case channelForm(Spawn<ChannelForm>)
        case composer(CommsPostComposer)
        case deleteChannelConfirmation(ChannelDeleteConfirmation)
        case postDetail(Spawn<CommsPostDetail>)
    }

    @Dependency(\.defaultDatabase) var database
    @FeatureEnvironment(ComposableAuthoring.AuthoringContext<AuthoringGrant>.self)
    var authoring

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

            case .deleteChannelButtonTapped:
                state.destination = .deleteChannelConfirmation(
                    ChannelDeleteConfirmation.State(channelID: state.channelID)
                )

            case let .editChannelButtonTapped(channel):
                state.destination = .channelForm(Spawn(ChannelForm.State(channel: channel)))

            case .newPostButtonTapped:
                guard state.canEditChannel else { return }
                state.destination = .composer(
                    CommsPostComposer.State(
                        channelID: state.channelRecordID
                    )
                )

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
        .onChange(of: authoring.grant.wrappedValue, initial: true) { _, grant, state in
            state.canEditChannel = grant?.access.canEditContent == true
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
                    if store.canEditChannel {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                store.send(.newPostButtonTapped)
                            } label: {
                                Label("New Post", systemImage: "square.and.pencil")
                            }
                        }
                    }

                    if store.isSubscribed {
                        ToolbarItem(placement: .primaryAction) {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(Color.accentColor)
                                .font(.caption)
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
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

                    if store.canEditChannel {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
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
                                Label("Channel actions", systemImage: "ellipsis")
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

            CommsMarkdownText(post.contents)
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
}
