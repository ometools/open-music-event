import Foundation

#if canImport(NukeUI)
@preconcurrency import NukeUI
#endif

import SkipFuse
import SwiftUI

public struct CachedAsyncImage<P: View>: View {
    public var url: URL?
    public var contentMode: ContentMode
    public var backup: () -> P

    public init(
        url: URL?,
        contentMode: ContentMode = .fill,
        @ViewBuilder backup: @escaping () -> P = { EmptyView() }
    ) {
        self.url = url
        self.contentMode = contentMode
        self.backup = backup
    }


    #if os(Android)
    public var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty, .failure:
                backup()
            case .success(let image):
                image
                    .resizable().aspectRatio(contentMode: contentMode)
            }
        }
//        AsyncImage(url: url) {
//            $0.resizable().aspectRatio(contentMode: .fill)
//        } placeholder: {
//            ProgressView()
//        }
    }
    #elseif canImport(NukeUI)
    public var body: some View {
        LazyImage(request: ImageRequest(url: url)) { state in
            if let image = state.image {
                image.resizable().aspectRatio(contentMode: self.contentMode)
            } else if state.error != nil {
                backup()
            } else {
                backup()
            }
        }
        .pipeline(.shared)
    }
    #endif
}

