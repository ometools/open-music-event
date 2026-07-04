import Dependencies
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SwiftUI

public enum ImageAssetPlaceholderReason: Equatable, Sendable {
    case loading
    case failure
    case unavailable
}

public struct ImageAssetAsyncImage<Placeholder: View>: View {
    let asset: OME.ImageAsset?
    let cacheContext: LocalImageCacheContext?
    var contentMode: ContentMode?
    @ViewBuilder var placeholder: (ImageAssetPlaceholderReason) -> Placeholder
    @Dependency(\.lazyImageCache) var lazyImageCache
    @Dependency(\.localImageDisplayCache) var localImageDisplayCache
    @State var cachedAsset: OME.ImageAsset?
    @State var cachedTaskID: String?
    @State var failedTaskID: String?
    @State var cacheMissTaskID: String?

    public init(
        asset: OME.ImageAsset?,
        cacheContext: LocalImageCacheContext? = nil,
        contentMode: ContentMode? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.asset = asset
        self.cacheContext = cacheContext
        self.contentMode = contentMode
        self.placeholder = { _ in placeholder() }
    }

    public init(
        asset: OME.ImageAsset?,
        cacheContext: LocalImageCacheContext? = nil,
        contentMode: ContentMode? = nil,
        @ViewBuilder placeholder: @escaping (ImageAssetPlaceholderReason) -> Placeholder
    ) {
        self.asset = asset
        self.cacheContext = cacheContext
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    public init(
        image: DisplayImageAsset?,
        contentMode: ContentMode? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.asset = image?.asset
        self.cacheContext = image?.cacheContext
        self.contentMode = contentMode
        self.placeholder = { _ in placeholder() }
    }

    public init(
        image: DisplayImageAsset?,
        contentMode: ContentMode? = nil,
        @ViewBuilder placeholder: @escaping (ImageAssetPlaceholderReason) -> Placeholder
    ) {
        self.asset = image?.asset
        self.cacheContext = image?.cacheContext
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    public var body: some View {
        if shouldShowCachePlaceholder {
            placeholder(.loading)
                .task(id: cacheTaskID) {
                    await cacheLazyImageIfNeeded()
                }
        } else if shouldResolveDisplayCache {
            placeholder(.loading)
                .task(id: cacheTaskID) {
                    await resolveCachedImageIfAvailable()
                }
        } else if let url = displayAsset?.url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    placeholder(.loading)
                case let .success(image):
                    image
                        .renderingMode(displayAsset?.isTemplateLike == true ? .template : .original)
                        .resizable()
                        .aspectRatio(contentMode: resolvedContentMode)
                case .failure:
                    placeholder(.failure)
                @unknown default:
                    placeholder(.unavailable)
                }
            }
        } else {
            placeholder(.unavailable)
        }
    }

    private var displayAsset: OME.ImageAsset? {
        if cachedTaskID == cacheTaskID {
            return cachedAsset ?? asset
        }

        if shouldResolveDisplayCache {
            return nil
        }

        return asset
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

    private var shouldResolveDisplayCache: Bool {
        guard let asset,
              cacheContext != nil,
              asset.materializationPolicy == .prefetchOnOpen,
              cachedTaskID != cacheTaskID,
              failedTaskID != cacheTaskID,
              cacheMissTaskID != cacheTaskID else {
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
        let assetID = asset?.assetKey ?? asset?.url?.absoluteString ?? "nil"
        let organizerID = cacheContext?.organizerID.description ?? "nil"
        let eventID = cacheContext?.eventID?.rawValue.rawValue ?? "nil"
        let parentKind = cacheContext?.parentKind.rawValue ?? "nil"
        let parentLocalID = cacheContext?.parentLocalID ?? "nil"
        return [
            assetID,
            organizerID,
            eventID,
            parentKind,
            parentLocalID,
        ].joined(separator: "|")
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

    private func resolveCachedImageIfAvailable() async {
        guard let asset,
              let cacheContext,
              shouldResolveDisplayCache else {
            return
        }

        do {
            if let cachedAsset = try await localImageDisplayCache.resolve(asset, cacheContext) {
                self.cachedAsset = cachedAsset
                self.cachedTaskID = cacheTaskID
                self.failedTaskID = nil
                self.cacheMissTaskID = nil
            } else {
                self.cacheMissTaskID = cacheTaskID
            }
        } catch {
            self.failedTaskID = cacheTaskID
        }
    }
}
