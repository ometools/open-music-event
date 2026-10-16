import ComposableArchitecture2
import Foundation
import OpenMusicEventLexicon
import SwiftUI

struct SocialPostList: View {
    let store: StoreOf<SocialCategoryDetail>

    var body: some View {
        Group {
            if !store.pinnedPosts.isEmpty {
                Section("Pinned Posts") {
                    ForEach(store.pinnedPosts) { post in
                        SocialPostRow(store: store, post: post)
                    }
                }
            }

            if !store.recentPosts.isEmpty {
                Section("Recent Posts") {
                    ForEach(store.recentPosts) { post in
                        SocialPostRow(store: store, post: post)
                    }
                }
            }
        }
    }
}

struct SocialPostRow: View {
    let store: StoreOf<SocialCategoryDetail>
    let post: Social.Post

    var body: some View {
        let isRead = store.readPostIDs.contains(post.id)
        let pinned = store.channel?.pinnedPosts ?? []
        HStack {
            Button {
                store.send(.postButtonTapped(post.id))
            } label: {
                SocialPostRowContent(post: post, isRead: isRead)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("button.communication-post.\(post.id.description)")

            if store.canEditChannel {
                Menu {
                    if pinned.contains(post.id) {
                        Button("Move Up") { store.send(.movePinnedPostButtonTapped(post.id, -1)) }
                            .disabled(pinned.first == post.id)
                        Button("Move Down") { store.send(.movePinnedPostButtonTapped(post.id, 1)) }
                            .disabled(pinned.last == post.id)
                        Button("Unpin Post") { store.send(.unpinPostButtonTapped(post.id)) }
                    } else {
                        Button("Pin Post") { store.send(.pinPostButtonTapped(post.id)) }
                    }
                    if store.state.canEditPost(post) {
                        Divider()
                        Button("Edit Post") { store.send(.editPostButtonTapped(post.id)) }
                        Button("Delete Post", role: .destructive) {
                            store.send(.deletePostButtonTapped(post.id))
                        }
                    }
                } label: {
                    Label("Post Actions", systemImage: "ellipsis-horizontal-circle")
                        .labelStyle(.iconOnly)
                }
                .disabled(store.isSavingPins)
            }
        }
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

            if store.state.canEditPost(post) {
                Button(role: .destructive) {
                    store.send(.deletePostButtonTapped(post.id))
                } label: {
                    Label("Delete Post", systemImage: "trash")
                }
            }
        }
        .swipeActions {
            if store.state.canEditPost(post) {
                Button(role: .destructive) {
                    store.send(.deletePostButtonTapped(post.id))
                } label: {
                    Label("Delete Post", systemImage: "trash")
                }
            }
        }
    }
}

struct SocialPostRowContent: View {
    let post: Social.Post
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

                    Text(post.title ?? "Post")
                        .font(.headline)
                        .fontWeight(isRead ? .regular : .semibold)
                        .foregroundStyle(.primary)

                    Spacer()
                }

                if let timestamp = ISO8601DateFormatter().date(from: post.createdAt.rawValue) {
                    Text(timestamp, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            CommsMarkdownText(post.text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
        }
        .padding(.vertical, 4)
        .accessibilityValue(Text(isRead ? "Read" : "Unread"))
    }
}
