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

        var destination: CommunicationChannelView.Store?

        func didTapChannel(_ channel: CommunicationChannel.ID) {
            self.destination = .init(channel)
        }

        func task() async {
            let id = musicEventID
            let values = ValueObservation.tracking { db in
                try CommunicationChannel
                    .filter(Column("musicEventID") == id)
                    .order(Column("sortIndex"))
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

    @Bindable var store: Store

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
        .navigationDestination(item: $store.destination) {
            CommunicationChannelView(store: $0)
        }
        .navigationTitle("Updates")
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
                    Icons.bellFill
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
    class Store: Identifiable {
        init(_ channelID: CommunicationChannel.ID) {
            self.id = channelID
        }

        let id: CommunicationChannel.ID

        var channel: CommunicationChannel = .placeholder
        var pinnedPosts: [CommunicationChannel.Post] = []
        var regularPosts: [CommunicationChannel.Post] = []

        var shouldShowContentUnavailable: Bool {
            pinnedPosts.isEmpty && regularPosts.isEmpty
        }

        var destination: CommunicationChannel.Post?

        @ObservationIgnored
        @Dependency(\.defaultDatabase) var defaultDatabase

        func task() async {
            let channelID = id

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

        func didTapPost(_ post: CommunicationChannel.Post) {
            self.destination = post
        }

        func didTapNotifyMe() {
            updateNotificationState(.subscribed)
        }

        func didTapStopNotifyingMe() {
            updateNotificationState(.unsubscribed)
        }

        private func updateNotificationState(_ state: CommunicationChannel.UserNotificationState) {
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

    @Bindable var store: Store

    public var body: some View {
        List {
            Section {
                Text(store.channel.description)
                    .font(.subheadline)
            } footer: {
                if store.shouldShowContentUnavailable {
                    Text("There are no posts in this channel yet.")
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
        .task { await store.task() }
        .navigationTitle(store.channel.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    if store.channel.userNotificationState == .subscribed {
                        Icons.bellFill
                            .foregroundStyle(Color.accentColor)
                            .font(.caption)
                    }

                    Menu {
                        switch store.channel.notificationState {
                        case .subscribed:
                            Button("Don't Notify Me For New Posts", image: Icons.bellBadgeSlash) {
                                store.didTapStopNotifyingMe()
                            }
                        case .unsubscribed:
                            Button("Notify Me For New Posts", image: Icons.bellBadge) {
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
        .navigationDestination(item: $store.destination) {
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
                
                Text(post.contents)
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
//}
//#endif

extension View {
    public func navigationDestination<D, C: View>(
          item: Binding<D?>,
          @ViewBuilder destination: @escaping (D) -> C
        ) -> some View {
          navigationDestination(isPresented: Binding(item)) {
            if let item = item.wrappedValue {
              destination(item)
            }
          }
        }
}
  import IssueReporting
  import SwiftUI

  extension Binding {
    /// Creates a binding by projecting the base optional value to a Boolean value.
    ///
    /// Writing `false` to the binding will `nil` out the base value. Writing `true` produces a
    /// runtime warning.
    ///
    /// - Parameter base: A value to project to a Boolean value.
    public init<V>(
      _ base: Binding<V?>,
    ) where Value == Bool {
      self =
        base[]
    }
  }

  extension Optional {
    fileprivate subscript() -> Bool {
      get { self != nil }
      set {
        if newValue {
          reportIssue(
            """
            Boolean presentation binding attempted to write 'true' to a generic 'Binding<Item?>' \
            (i.e., 'Binding<\(Wrapped.self)?>').

            This is not a valid thing to do, as there is no way to convert 'true' to a new \
            instance of '\(Wrapped.self)'.
            """
          )
        } else {
          self = nil
        }
      }
    }
  }
