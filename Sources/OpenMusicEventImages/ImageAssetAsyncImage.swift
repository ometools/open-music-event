import Dependencies
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SwiftUI

public struct ImageAssetAsyncImage<Placeholder: View>: View {
    let asset: OME.ImageAsset?
    let cacheContext: LocalImageCacheContext?
    var contentMode: ContentMode?
    @ViewBuilder var placeholder: () -> Placeholder
    @Dependency(\.lazyImageCache) var lazyImageCache
    @State var cachedAsset: OME.ImageAsset?
    @State var cachedTaskID: String?
    @State var failedTaskID: String?

    public init(
        asset: OME.ImageAsset?,
        cacheContext: LocalImageCacheContext? = nil,
        contentMode: ContentMode? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.asset = asset
        self.cacheContext = cacheContext
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    public var body: some View {
        if shouldShowCachePlaceholder {
            placeholder()
                .task(id: cacheTaskID) {
                    await cacheLazyImageIfNeeded()
                }
        } else if let url = displayAsset?.url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    placeholder()
                case let .success(image):
                    image
                        .renderingMode(displayAsset?.isTemplateLike == true ? .template : .original)
                        .resizable()
                        .aspectRatio(contentMode: resolvedContentMode)
                case .failure:
                    placeholder()
                @unknown default:
                    placeholder()
                }
            }
        } else {
            placeholder()
        }
    }

    private var displayAsset: OME.ImageAsset? {
        cachedTaskID == cacheTaskID ? cachedAsset ?? asset : asset
    }

    private var shouldShowCachePlaceholder: Bool {
        guard let asset,
              cacheContext != nil,
              asset.materializationPolicy == .lazy,
              cachedTaskID != cacheTaskID,
              failedTaskID != cacheTaskID else {
            return false
        }

        if let url = asset.url,
           url.isFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            return false
        }

        return true
    }

    private var cacheTaskID: String {
        [
            asset?.assetKey ?? asset?.url?.absoluteString ?? "nil",
            cacheContext?.organizerID.description ?? "nil",
            cacheContext?.eventID.rawValue.rawValue ?? "nil",
            cacheContext?.parentKind.rawValue ?? "nil",
            cacheContext?.parentLocalID ?? "nil",
        ]
        .joined(separator: "|")
    }

    private var resolvedContentMode: ContentMode {
        if let contentMode {
            return contentMode
        }
        return displayAsset?.renderKind == .transparent ? .fit : .fill
    }

    private func cacheLazyImageIfNeeded() async {
        guard let asset,
              let cacheContext,
              shouldShowCachePlaceholder else {
            return
        }

        do {
            let cachedAsset = try await lazyImageCache.cache(asset, cacheContext)
            self.cachedAsset = cachedAsset
            self.cachedTaskID = cacheTaskID
            self.failedTaskID = nil
        } catch {
            self.failedTaskID = cacheTaskID
        }
    }
}
