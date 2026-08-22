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

@Feature
public struct CommsPostDetail {
    public init() {}

    public struct State: Identifiable {
        enum LoadState: Equatable, Sendable {
            case failed
            case loaded(CommsPost)
            case loading
        }

        public init(postID: CommsPost.ID) {
            self.postID = postID
            _post = FetchOne(CommsPost.where { $0.id.eq(postID) })
        }

        public let postID: CommsPost.ID
        @FetchOne public var post: CommsPost?
        public var errorMessage: String?
        public var id: CommsPost.ID { postID }

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
            switch store.loadState {
            case let .loaded(post):
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
    }
}
