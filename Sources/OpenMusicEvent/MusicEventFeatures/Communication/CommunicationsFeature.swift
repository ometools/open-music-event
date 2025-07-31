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

public struct CommunicationsFeatureView: View {

    @Observable
    @MainActor
    public class Store {

        public init() {}

        var channels: [CommunicationChannel] = []

        @ObservationIgnored
        @Dependency(\.defaultDatabase) var defaultDatabase

        @ObservationIgnored
        @Dependency(\.musicEventID) var musicEventID

        func task() async {
            let id = musicEventID
            let values = ValueObservation.tracking { db in
                try CommunicationChannel
                    .filter(Column("musicEventID") == id)
                    .fetchAll(db)
            }
            .values(in: defaultDatabase)

            do {
                for try await channels in values {
                    self.channels = channels
                }
            } catch {
                reportIssue(error)
            }
        }
    }

    let store: Store

    public var body: some View {
        List {
            Section {
                ForEach(store.channels) { channel in
                    NavigationLink {
                        CommunicationChannelView(store: .init(channel))
                    } label: {
                        Row(channel: channel)
                    }
                }
            } header: {
                Text("Channels")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Communication")
        .task { await store.task() }
    }

    struct Row: View {
        var channel: CommunicationChannel

        var isSubscribed: Bool {
            channel.userNotificationState == .subscribed
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
                    
                    Text(channel.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()

                if isSubscribed {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

public struct CommunicationChannelView: View {
    @MainActor
    @Observable
    class Store {
        init(_ channel: CommunicationChannel) {
            self.channel = channel
        }

        var channel: CommunicationChannel
        var pinnedPosts: [CommunicationChannel.Post] = []
        var regularPosts: [CommunicationChannel.Post] = []

        @ObservationIgnored
        @Dependency(\.defaultDatabase) var defaultDatabase

        func task() async {
            let channelID = channel.id
            
            let postsObservation = ValueObservation.tracking { db in
                let channel = try CommunicationChannel
                    .filter(Column("id") == channelID)
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

        func didTapNotifyMe() {
            updateNotificationState(.subscribed)
        }

        func didTapStopNotifyingMe() {
            updateNotificationState(.unsubscribed)
        }
        
        private func updateNotificationState(_ state: CommunicationChannel.NotificationState) {
            withErrorReporting {
                try defaultDatabase.write { db in
                    try db.execute(
                        sql: "UPDATE \(CommunicationChannel.tableName) SET userNotificationState = ? WHERE id = ?", 
                        arguments: [state.rawValue, channel.id.rawValue]
                    )
                }
            }
        }
    }

    let store: Store

    public var body: some View {
        List {
            Text(store.channel.description)
                .font(.subheadline)

            if !store.pinnedPosts.isEmpty {
                Section {
                    ForEach(store.pinnedPosts) { post in
                        NavigationLink {
                            PostDetailView(post: post)
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
        .listStyle(.plain)
        .task { await store.task() }
        .navigationTitle(store.channel.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    if store.channel.userNotificationState == .subscribed {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.caption)
                    }
                    
                    Menu("Options", systemImage: "ellipsis") {
                        switch store.channel.userNotificationState {
                        case .subscribed:
                            Button("Don't Notify Me For New Posts", systemImage: "bell.badge.slash") {
                                store.didTapStopNotifyingMe()
                            }
                        case .unsubscribed:
                            Button("Notify Me For New Posts", systemImage: "bell.badge") {
                                store.didTapNotifyMe()
                            }
                        }
                    }
                }
            }
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
                                Image(systemName: "pin.fill")
                                    .foregroundStyle(.blue)
                                    .font(.caption)
                            }
                            
                            Text(post.title)
                                .font(.headline)
                                .fontWeight(.medium)
                        }
                        
                        Text(post.timestamp, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                
                Text(post.contents)
                    .font(.body)
                    .foregroundStyle(.primary)
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
                            Image(systemName: "pin.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        
                        Text(post.title)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    Text(post.timestamp, format: .relative(presentation: .named))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Text(post.contents)
                    .font(.body)
                #if !os(Android)
                    .lineSpacing(4)
                #endif

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
//}
//#endif
