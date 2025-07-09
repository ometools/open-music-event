import Foundation

#if canImport(NukeUI)
@preconcurrency import NukeUI
#endif

import SkipFuse
import SwiftUI

public struct CachedAsyncImage: View {
    public var url: URL?

    public init(url: URL?) {
        self.url = url
    }


    #if os(Android)
    public var body: some View {
        AsyncImage(url: url) {
            $0.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ProgressView()
        }
    }
    #elseif canImport(NukeUI)
    public var body: some View {
        LazyImage(request: ImageRequest(url: url)) { state in
            if let image = state.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else if state.error != nil {
                Color.red // Indicates an error
            } else {
                ProgressView()
            }
        }
        .pipeline(.shared)
    }
    #endif
}

