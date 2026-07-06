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
    var focusSafeAreaInsets: EdgeInsets
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
        focusSafeAreaInsets: EdgeInsets = EdgeInsets(),
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.asset = asset
        self.cacheContext = cacheContext
        self.contentMode = contentMode
        self.focusSafeAreaInsets = focusSafeAreaInsets
        self.placeholder = { _ in placeholder() }
    }

    public init(
        asset: OME.ImageAsset?,
        cacheContext: LocalImageCacheContext? = nil,
        contentMode: ContentMode? = nil,
        focusSafeAreaInsets: EdgeInsets = EdgeInsets(),
        @ViewBuilder placeholder: @escaping (ImageAssetPlaceholderReason) -> Placeholder
    ) {
        self.asset = asset
        self.cacheContext = cacheContext
        self.contentMode = contentMode
        self.focusSafeAreaInsets = focusSafeAreaInsets
        self.placeholder = placeholder
    }

    public init(
        image: DisplayImageAsset?,
        contentMode: ContentMode? = nil,
        focusSafeAreaInsets: EdgeInsets = EdgeInsets(),
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.asset = image?.asset
        self.cacheContext = image?.cacheContext
        self.contentMode = contentMode
        self.focusSafeAreaInsets = focusSafeAreaInsets
        self.placeholder = { _ in placeholder() }
    }

    public init(
        image: DisplayImageAsset?,
        contentMode: ContentMode? = nil,
        focusSafeAreaInsets: EdgeInsets = EdgeInsets(),
        @ViewBuilder placeholder: @escaping (ImageAssetPlaceholderReason) -> Placeholder
    ) {
        self.asset = image?.asset
        self.cacheContext = image?.cacheContext
        self.contentMode = contentMode
        self.focusSafeAreaInsets = focusSafeAreaInsets
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
                    renderedImage(image, asset: displayAsset)
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

    @ViewBuilder
    private func renderedImage(
        _ image: Image,
        asset: OME.ImageAsset?
    ) -> some View {
        let image = image
            .renderingMode(asset?.isTemplateLike == true ? .template : .original)
            .resizable()

        if resolvedContentMode == .fill,
           let dimensions = asset?.dimensions?.size,
           let focalPoint = asset?.focalPoint?.point {
            FocusedAsyncImage(
                image: image,
                imageSize: dimensions,
                focalPoint: focalPoint,
                safeAreaInsets: focusSafeAreaInsets
            )
        } else {
            image.aspectRatio(contentMode: resolvedContentMode)
        }
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

struct FocusedAsyncImage: View {
    let image: Image
    let imageSize: CGSize
    let focalPoint: CGPoint
    let safeAreaInsets: EdgeInsets

    var body: some View {
        GeometryReader { geometry in
            let safeRect = safeRect(in: geometry.size)
            let layout = ImageFocusLayout.layout(
                imageSize: imageSize,
                containerSize: geometry.size,
                focalPoint: focalPoint,
                safeRect: safeRect
            )

            image
                .frame(width: layout.frame.width, height: layout.frame.height)
                .offset(x: layout.frame.minX, y: layout.frame.minY)
        }
        .clipped()
    }

    private func safeRect(in size: CGSize) -> CGRect {
        let width = size.width - safeAreaInsets.leading - safeAreaInsets.trailing
        let height = size.height - safeAreaInsets.top - safeAreaInsets.bottom
        guard width > 0, height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        return CGRect(
            x: safeAreaInsets.leading,
            y: safeAreaInsets.top,
            width: width,
            height: height
        )
    }
}

private extension OME.ImageAsset.Dimensions {
    var size: CGSize? {
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
}

private extension OME.ImageAsset.FocalPoint {
    var point: CGPoint {
        CGPoint(x: x, y: y)
    }
}
