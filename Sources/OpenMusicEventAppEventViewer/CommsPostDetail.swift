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
