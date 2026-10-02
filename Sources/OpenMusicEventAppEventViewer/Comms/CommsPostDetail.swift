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
public struct CommsPostDetail {
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
            self._authoringGrant = .authoringGrant(for: eventID)
            _post = FetchOne(Social.Post.where { $0.id.eq(postID) })
        }

        public let postID: Social.Post.ID
        public let eventID: Event.ID
        @SharedReader
        public var authoringGrant: AuthoringGrant?
        @FetchOne public var post: Social.Post?
        public var destination: Destination.State?
        public var errorMessage: String?
        public var id: Social.Post.ID { postID }

        public var canDelete: Bool {
            guard let post, let authoringGrant else { return false }
            return authoringGrant.access.canEditContent
                && post.id.authority == .did(authoringGrant.principal.actorID)
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
        case composer(CommsPostComposer)
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
                      let author = state.authoringGrant?.principal.actorID else { return }
                state.destination = .composer(
                    CommsPostComposer.State(post: post, eventID: state.eventID, author: author)
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
                    CommsPostComposer()
                }
        }
    }
}

public struct CommsPostDetailView: View {
    @Bindable var store: StoreOf<CommsPostDetail>

    public init(store: StoreOf<CommsPostDetail>) {
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
                CommsPostComposerView(store: composerStore)
            }
        }
        .accessibilityIdentifier("view.communication-post.\(store.postID.description)")
    }
}
