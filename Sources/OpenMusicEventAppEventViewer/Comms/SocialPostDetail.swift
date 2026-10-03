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
public struct SocialPostDetail {
    public init() {}

    public struct State: Identifiable {
        enum LoadState: Equatable, Sendable {
            case failed
            case loaded(Social.Post)
            case loading
        }

        public init(postID: Social.Post.ID, eventID: Event.ID) {
            self.postID = postID
            self.eventID = eventID
            self._workspaceSession = .eventWorkspaceSession(for: eventID)
            self.currentWorkspaceAccount = CurrentWorkspaceAccount()
            _post = FetchOne(Social.Post.where { $0.id.eq(postID) })
        }

        public let postID: Social.Post.ID
        public let eventID: Event.ID
        @SharedReader
        public var workspaceSession: EventWorkspaceSession?
        @DebugSnapshotIgnored let currentWorkspaceAccount: CurrentWorkspaceAccount
        @FetchOne public var post: Social.Post?
        public var destination: Destination.State?
        public var errorMessage: String?
        public var id: Social.Post.ID { postID }

        public var canDelete: Bool {
            guard let post, let session = validatedWorkspaceSession else { return false }
            return post.id.authority == .did(session.actorID)
        }

        var validatedWorkspaceSession: EventWorkspaceSession? {
            currentWorkspaceAccount.validated(workspaceSession, for: eventID)
        }

        var loadState: LoadState {
            if let post {
                return .loaded(post)
            } else if $post.loadError != nil {
                return .failed
            } else {
                return .loading
            }
        }
    }

    public enum Action {
        case deleteButtonTapped
        case editButtonTapped
        case destination(Destination.Action)
        case postBecameVisible
    }

    @Feature
    public enum Destination {
        case composer(SocialPostForm)
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .deleteButtonTapped:
                break

            case .editButtonTapped:
                guard state.canDelete,
                      let post = state.post,
                      let author = state.validatedWorkspaceSession?.actorID else { return }
                state.destination = .composer(
                    SocialPostForm.State(post: post, eventID: state.eventID, author: author)
                )

            case .destination:
                break

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
        .ifLet(\.destination) {
            EmptyFeature()
                .ifCaseLet(\.composer) {
                    SocialPostForm()
                }
        }
    }
}

public struct SocialPostDetailView: View {
    @Bindable var store: StoreOf<SocialPostDetail>

    public init(store: StoreOf<SocialPostDetail>) {
        self.store = store
    }

    public var body: some View {
        Group {
            switch store.loadState {
            case let .loaded(post):
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(post.title ?? "Post")
                                .font(.title2)
                                .fontWeight(.bold)

                            if let timestamp = ISO8601DateFormatter().date(from: post.createdAt.rawValue) {
                                Text(timestamp, format: .relative(presentation: .named))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        CommsMarkdownText(post.text)
                            .multilineTextAlignment(.leading)
                            .selectableText()

                        if let embed = post.embed {
                            SocialPostEmbedView(embed: embed, recordID: post.id)
                        }

                        if let errorMessage = store.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .task(id: post.id) {
                    await store.send(.postBecameVisible)?.value
                }

            case .loading:
                ProgressView("Loading post")

            case .failed:
                ViewerPlaceholderView(
                    title: "Post",
                    systemImage: "doc.text",
                    description: "This post could not be loaded."
                )
            }
        }
        .toolbar {
            if store.canDelete {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Edit Post") {
                            store.send(.editButtonTapped)
                        }
                        Button(role: .destructive) {
                            store.send(.deleteButtonTapped)
                        } label: {
                            Label("Delete Post", systemImage: "trash")
                        }
                    } label: {
                        Label("Post Actions", systemImage: "gearshape")
                    }
                }
            }
        }
        .sheet(item: $store.scope(\.destination).composer) { composerStore in
            NavigationStack {
                SocialPostFormView(store: composerStore)
            }
        }
        .accessibilityIdentifier("view.communication-post.\(store.postID.description)")
    }
}

struct SocialPostEmbedView: View {
    let embed: Social.Post.Embed
    let recordID: Social.Post.ID

    var body: some View {
        switch SocialPostEmbedContent(embed) {
        case let .images(images):
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: images.count == 1 ? 1 : 2
                ),
                spacing: 8
            ) {
                ForEach(images.indices, id: \.self) { index in
                    ImageAssetAsyncImage(
                        image: .record(images[index], recordID),
                        contentMode: .fill
                    ) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.secondary.opacity(0.12))
                            .overlay { Image(systemName: "photo") }
                    }
                    .frame(height: images.count == 1 ? 220 : 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel(images[index].alt?.rawValue ?? "Post photo")
                }
            }

        case let .external(card):
            if let url = card.url {
                Link(destination: url) {
                    externalCard(card)
                }
                .buttonStyle(.plain)
            } else {
                externalCard(card)
            }

        case let .record(uri):
            Label("Referenced record", systemImage: "link")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHint(uri)

        case .unsupported:
            Label("Attached content", systemImage: "paperclip")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    func externalCard(_ card: SocialPostExternalCard) -> some View {
        HStack(spacing: 12) {
            if let thumbnail = card.thumbnail {
                ImageAssetAsyncImage(
                    image: .record(thumbnail, recordID),
                    contentMode: .fill
                ) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.secondary.opacity(0.12))
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.headline)
                if !card.summary.isEmpty {
                    Text(card.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(card.url?.host ?? card.uri)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
