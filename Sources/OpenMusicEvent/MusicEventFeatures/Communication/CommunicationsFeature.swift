//
//  CommunicationsFeature.swift
//  open-music-event
//
//  Created by Woodrow Melling on 7/31/25.
//
import SwiftUI
import Foundation
import CoreModels
import GRDB
import Dependencies
import CasePaths

extension CommunicationChannel {
//    @Selection
    struct ChannelUserInfo: Identifiable, Equatable, FetchableRecord {
        var id: CommunicationChannel.ID
        var name: String
        var description: String
        var notificationsRequired: Bool
        var notificationState: CommunicationChannel.UserNotificationState?

        init(
            id: CommunicationChannel.ID,
            name: String,
            description: String,
            notificationsRequired: Bool,
            notificationState: CommunicationChannel.UserNotificationState?
        ) {
            self.id = id
            self.name = name
            self.description = description
            self.notificationsRequired = notificationsRequired
            self.notificationState = notificationState
        }

        static let placeholder = ChannelUserInfo(id: "", name: "", description: "", notificationsRequired: false, notificationState: nil)

        init(row: Row) throws {
            self.id = row["id"]
            self.name = row["name"]
            self.description = row["description"]
            self.notificationsRequired = row["notificationsRequired"]
            
            // Parse the notification state from the raw value if it exists
            if let rawValue: String = row["userNotificationState"] {
                self.notificationState = CommunicationChannel.UserNotificationState(rawValue: rawValue)
            } else {
                self.notificationState = nil
            }
        }
    }
}

public struct CommunicationsFeatureView: View {

    @Observable
    @MainActor
    public class Store {

        public init() {}

        var channels: [CommunicationChannel.ChannelUserInfo] = []

        @ObservationIgnored
        @Dependency(\.defaultDatabase) var defaultDatabase

        @ObservationIgnored
        @Dependency(\.musicEventID) var musicEventID


        @CasePathable
        enum Destination {
            case channel(CommunicationChannelView.Store)
            case createChannel
        }

        var destination: Destination?

        func didTapChannel(_ channel: CommunicationChannel.ID) {
            withDependencies(from: self) {
                self.destination = .channel(.init(channel))
            }
        }

        func didTapCreateChannel() {
            withDependencies(from: self) {
                self.destination = .createChannel
            }
        }

        func task() async {
            let id = musicEventID
            await withErrorReporting {
                let values = ValueObservation.tracking { db in
                    try Queries.communicationChannelUserInfoQuery(for: id).fetchAll(db)
                }
                .values(in: defaultDatabase)
    //
                do {
                    for try await rows in values {
                        self.channels = rows
                    }
                } catch {
                    reportIssue(error)
                }
            }
        }
    }

    @Bindable var store: Store
    @Environment(\.editingMode) var editingMode

    public var body: some View {
        List {
            Section {
                ForEach(store.channels) { channel in
                    NavigationLinkButton {
                        store.didTapChannel(channel.id)
                    } label: {
                        Row(channel: channel)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Channels")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            if editingMode == .editing {
                Button("Create Channel", systemImage: "plus") {
                    store.didTapCreateChannel()
                }
            }
        }
        .navigationDestination(item: $store.destination.channel) {
            CommunicationChannelView(store: $0)
        }
        .navigationTitle("Updates")
        .task { await store.task() }
    }

    struct Row: View {
        var channel: CommunicationChannel.ChannelUserInfo

        var isSubscribed: Bool {
            channel.notificationState == .subscribed
        }

        var body: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(channel.name)
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                    }
                    
                    MarkdownText(channel.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()

                if isSubscribed {
                    Icons.bellFill
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}


class ChannelForm {}

public struct CommunicationChannelView: View {
    @MainActor
    @Observable
    class Store: Identifiable {
        init(_ channelID: CommunicationChannel.ID) {
            self.id = channelID
        }

        let id: CommunicationChannel.ID

        var channel: CommunicationChannel.ChannelUserInfo = .placeholder

        var pinnedPosts: [CommunicationChannel.Post] = []
        var regularPosts: [CommunicationChannel.Post] = []

        var shouldShowContentUnavailable: Bool {
            pinnedPosts.isEmpty && regularPosts.isEmpty
        }

        @CasePathable
        enum Destination {
            case post(CommunicationChannel.Post)
            case editPost
        }


        var destination: Destination?

        @ObservationIgnored
        @Dependency(\.defaultDatabase) var defaultDatabase

        @ObservationIgnored
        @Dependency(\.musicEventID) var musicEventID

        func task() async {
            let channelID = id
            let musicEventID = musicEventID

            let postsObservation = ValueObservation.tracking { db in
                let channel = try SQLRequest<CommunicationChannel.ChannelUserInfo>(
                    sql: """
                        SELECT 
                            c.id,
                            c.name,
                            c.description,
                            c.notificationsRequired,
                            COALESCE(cp.userNotificationState, c.defaultNotificationState) as userNotificationState
                        
                        FROM channels c
                        LEFT JOIN channelPreferences cp ON c.id = cp.channelID
                        WHERE c.id = ?
                        """,
                    arguments: [channelID]
                )
                .fetchOne(db)

                let posts = try CommunicationChannel.Post
                    .filter(Column("channelID") == channelID)
                    .order(Column("timestamp"))
                    .fetchAll(db)

                return (channel, posts)

            }
            .values(in: defaultDatabase)
            
            await withErrorReporting {
                for try await (updatedChannel, posts) in postsObservation {
                    if let updatedChannel {
                        self.channel = updatedChannel
                    }
                    self.pinnedPosts = posts.filter(\.isPinned)
                    self.regularPosts = posts.filter { !$0.isPinned }
                }
            }
        }

        func didTapPost(_ post: CommunicationChannel.Post) {
            self.destination = .post(post)
        }

        func didTapNotifyMe() {
            updateNotificationState(.subscribed)
        }

        func didTapStopNotifyingMe() {
            updateNotificationState(.unsubscribed)
        }

        func didTapCreatePost() {
            self.destination = .editPost
        }

        private func updateNotificationState(_ state: CommunicationChannel.UserNotificationState) {
            withErrorReporting {
                try defaultDatabase.write { db in
                    try db.execute(
                        sql: "INSERT INTO \(CommunicationChannel.Preferences.tableName) (channelID, userNotificationState) VALUES (?, ?) ON CONFLICT(channelID) DO UPDATE SET userNotificationState = excluded.userNotificationState",
                        arguments: [channel.id.rawValue, state.rawValue]
                    )
                }
            }
        }
    }

    @Bindable var store: Store

    public var body: some View {
        List {
            if !store.channel.description.isEmpty {
                Section {
                    Text(store.channel.description)
                        .font(.subheadline)
                } footer: {
                    if store.shouldShowContentUnavailable {
                        Text("There are no posts in this channel yet.")
                    }
                }
            }

            if !store.pinnedPosts.isEmpty {
                Section {
                    ForEach(store.pinnedPosts) { post in
                        NavigationLinkButton {
                            store.didTapPost(post)
                        } label: {
                            Row(post: post)
                        }
                    }
                }
            }

            // Show regular posts
            if !store.regularPosts.isEmpty {
                Section {
                    ForEach(store.regularPosts) { post in
                        NavigationLink {
                            PostDetailView(post: post)
                        } label: {
                            Row(post: post)
                        }
                    }
                } header: {
                    Text("Recent Posts")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: store.id) { await store.task() }
        .navigationTitle(store.channel.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    if store.channel.notificationState == .subscribed {
                        Icons.notificationsEnabled
                            .foregroundStyle(Color.accentColor)
                            .font(.caption)
                    }

                    Menu {
                        switch store.channel.notificationState {
                        case .subscribed:
                            Button("Don't Notify Me For New Posts", image: Icons.disableNotifications) {
                                store.didTapStopNotifyingMe()
                            }
                        case .unsubscribed, .none:
                            Button("Notify Me For New Posts", image: Icons.enableNotifications) {
                                store.didTapNotifyMe()
                            }
                        }
                    } label: {
                        Label("Options", systemImage: "ellipsis")
                    }
                    .disabled(store.channel.notificationsRequired)
                }
            }
        }
        .navigationDestination(item: $store.destination.post) {
            PostDetailView(post: $0)
        }
    }

    struct Row: View {
        var post: CommunicationChannel.Post

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if post.isPinned {
                                Icons.pin
                                    .foregroundStyle(Color.accentColor)
                                    .font(.caption)
                            }
                            
                            Text(post.title)
                                .font(.headline)
                                .fontWeight(.medium)
                            
                            Spacer()

                            if let timestamp = post.timestamp {
                                Text(timestamp, format: .relative(presentation: .named))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                    }
                    
                    Spacer()
                }
                
                MarkdownText(post.contents)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PostDetailView: View {
    let post: CommunicationChannel.Post
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let imageURL = post.headerImageURL {
                    CachedAsyncImage(url: imageURL)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if post.isPinned {
                            Icons.pin
                                .foregroundStyle(Color.accentColor)
                        }
                        
                        Text(post.title)
                            .font(.title2)
                            .fontWeight(.bold)
                    }


                    if let timeStamp = post.timestamp {
                        Text(timeStamp, format: .relative(presentation: .named))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                MarkdownText(post.contents)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(.horizontal)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

//
//
//
//#if !os(ANDROID)
//#Preview {
//    try! prepareDependencies {
//        $0.defaultDatabase = try appDatabase()
//        $0.musicEventID = ""
//    }
//
//    return NavigationStack {
//        CommunicationsFeatureView(store: .init())
//    }
//    .environment(\.editingMode, .editing)
//}
//#endif
