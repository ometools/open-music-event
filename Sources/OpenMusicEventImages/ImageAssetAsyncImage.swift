import ATProto
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventLexicon
#if os(Android) || SKIP_BRIDGE
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

public enum ImageAssetPlaceholderReason: Equatable, Sendable {
    case loading
    case failure
    case unavailable
}

public struct ImageAssetAsyncImage<Placeholder: View>: View {
    let asset: OME.ImageAsset?
    let cacheContext: LocalImageCacheContext?
    let recordID: Event.ID?
    var contentMode: ContentMode?
    var renderedImageSize: CGSize?
    var focusSafeAreaInsets: EdgeInsets
    let onIntrinsicSizeLoaded: (CGSize) -> Void
    @ViewBuilder var placeholder: (ImageAssetPlaceholderReason) -> Placeholder
    @Dependency(\.imageAssetResolver) var imageAssetResolver
    @Dependency(ATProto.Repository.PDSHostResolver.self) var pdsHosts
    @State var resolvedAsset: OME.ImageAsset?
    @State var resolvedTaskID: String?
    @State var failedTaskID: String?

    public init(
        asset: OME.ImageAsset?,
        cacheContext: LocalImageCacheContext? = nil,
        contentMode: ContentMode? = nil,
        renderedImageSize: CGSize? = nil,
        focusSafeAreaInsets: EdgeInsets = EdgeInsets(),
        onIntrinsicSizeLoaded: @escaping (CGSize) -> Void = { _ in },
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.asset = asset
        self.cacheContext = cacheContext
        self.recordID = nil
        self.contentMode = contentMode
        self.renderedImageSize = renderedImageSize
        self.focusSafeAreaInsets = focusSafeAreaInsets
        self.onIntrinsicSizeLoaded = onIntrinsicSizeLoaded
        self.placeholder = { _ in placeholder() }
    }

    public init(
        asset: OME.ImageAsset?,
        cacheContext: LocalImageCacheContext? = nil,
        contentMode: ContentMode? = nil,
        renderedImageSize: CGSize? = nil,
        focusSafeAreaInsets: EdgeInsets = EdgeInsets(),
        onIntrinsicSizeLoaded: @escaping (CGSize) -> Void = { _ in },
        @ViewBuilder placeholder: @escaping (ImageAssetPlaceholderReason) -> Placeholder
    ) {
        self.asset = asset
        self.cacheContext = cacheContext
        self.recordID = nil
        self.contentMode = contentMode
        self.renderedImageSize = renderedImageSize
        self.focusSafeAreaInsets = focusSafeAreaInsets
        self.onIntrinsicSizeLoaded = onIntrinsicSizeLoaded
        self.placeholder = placeholder
    }

    public init(
        image: DisplayImageAsset?,
        contentMode: ContentMode? = nil,
        renderedImageSize: CGSize? = nil,
        focusSafeAreaInsets: EdgeInsets = EdgeInsets(),
        onIntrinsicSizeLoaded: @escaping (CGSize) -> Void = { _ in },
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.asset = image?.asset
        self.cacheContext = image?.cacheContext
        self.recordID = image?.recordID
        self.contentMode = contentMode
        self.renderedImageSize = renderedImageSize
        self.focusSafeAreaInsets = focusSafeAreaInsets
        self.onIntrinsicSizeLoaded = onIntrinsicSizeLoaded
        self.placeholder = { _ in placeholder() }
    }

    public init(
        image: DisplayImageAsset?,
        contentMode: ContentMode? = nil,
        renderedImageSize: CGSize? = nil,
        focusSafeAreaInsets: EdgeInsets = EdgeInsets(),
        onIntrinsicSizeLoaded: @escaping (CGSize) -> Void = { _ in },
        @ViewBuilder placeholder: @escaping (ImageAssetPlaceholderReason) -> Placeholder
    ) {
        self.asset = image?.asset
        self.cacheContext = image?.cacheContext
        self.recordID = image?.recordID
        self.contentMode = contentMode
        self.renderedImageSize = renderedImageSize
        self.focusSafeAreaInsets = focusSafeAreaInsets
        self.onIntrinsicSizeLoaded = onIntrinsicSizeLoaded
        self.placeholder = placeholder
    }

    public var body: some View {
        if shouldResolveAsset {
            placeholder(.loading)
                .task(id: resolutionTaskID) {
                    await resolveAsset()
                }
        } else if failedTaskID == resolutionTaskID {
            placeholder(.failure)
        } else if let displayAsset,
                  let url = displayAsset.url {
            CachedRemoteImage(
                url: url,
                cacheKey: renderingCacheKey,
                targetSize: renderedImageSize
            ) { phase in
                switch phase {
                case .empty:
                    placeholder(.loading)
                case let .success(image, intrinsicSize):
                    renderedImage(
                        image,
                        intrinsicSize: intrinsicSize,
                        asset: displayAsset
                    )
                    .frame(
                        width: renderedImageSize?.width,
                        height: renderedImageSize?.height
                    )
                    .onAppear {
                        onIntrinsicSizeLoaded(intrinsicSize)
                    }
                case .failure:
                    placeholder(.failure)
                case .unavailable:
                    placeholder(.unavailable)
                }
            }
        } else {
            placeholder(.unavailable)
        }
    }

    var displayAsset: OME.ImageAsset? {
        Self.displayAsset(
            asset: asset,
            resolvedAsset: resolvedTaskID == resolutionTaskID
                ? resolvedAsset
                : nil
        )
    }

    static func displayAsset(
        asset: OME.ImageAsset?,
        resolvedAsset: OME.ImageAsset?
    ) -> OME.ImageAsset? {
        guard var asset, let resolvedAsset else { return asset }
        asset.assetKey = resolvedAsset.assetKey
        asset.source = resolvedAsset.source
        return asset
    }

    var shouldResolveAsset: Bool {
        guard let asset,
              cacheContext != nil || isRecordBlob,
              resolvedTaskID != resolutionTaskID,
              failedTaskID != resolutionTaskID else {
            return false
        }

        if let url = asset.url,
           url.isFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            return false
        }

        return true
    }

    var isRecordBlob: Bool {
        guard recordID != nil, let asset else { return false }
        if case .blob = asset.source { return true }
        return false
    }

    var blobCID: String? {
        guard let asset, case let .blob(blob) = asset.source else { return nil }
        return blob.ref.rawValue
    }

    var resolutionTaskID: String {
        let organizerID = cacheContext?.organizerID.description ?? "nil"
        let eventID = cacheContext?.eventID?.rawValue.rawValue ?? "nil"
        let parentKind = cacheContext?.parentKind.rawValue ?? "nil"
        let parentLocalID = cacheContext?.parentLocalID ?? "nil"
        return [
            asset?.assetKey ?? "nil",
            asset?.url?.absoluteString ?? "nil",
            recordID?.description ?? "nil",
            blobCID ?? "nil",
            asset?.role.rawValue ?? "nil",
            asset?.renderKind.rawValue ?? "nil",
            organizerID,
            eventID,
            parentKind,
            parentLocalID,
        ].joined(separator: "|")
    }

    var renderingCacheKey: String {
        [
            resolutionTaskID,
            displayAsset?.url?.absoluteString ?? "nil",
        ].joined(separator: "|")
    }

    var resolvedContentMode: ContentMode {
        if let contentMode {
            return contentMode
        }
        return displayAsset?.renderKind == .transparent ? .fit : .fill
    }

    @ViewBuilder
    func renderedImage(
        _ image: Image,
        intrinsicSize: CGSize,
        asset: OME.ImageAsset?
    ) -> some View {
        let image = image
            .renderingMode(asset?.isTemplateLike == true ? .template : .original)
            .resizable()

        if resolvedContentMode == .fill,
           let focalPoint = asset?.focalPoint?.point {
            FocusedAsyncImage(
                image: image,
                imageSize: intrinsicSize,
                focalPoint: focalPoint,
                safeAreaInsets: focusSafeAreaInsets
            )
        } else {
            image.aspectRatio(contentMode: resolvedContentMode)
        }
    }

    func resolveAsset() async {
        guard let asset,
              shouldResolveAsset else {
            return
        }

        do {
            let taskID = resolutionTaskID
            let resolvedAsset: OME.ImageAsset
            if case let .blob(blob) = asset.source,
               let fileURL = try stagedLocalImageBlobURL(for: blob) {
                var image = asset
                image.source = .url(fileURL)
                resolvedAsset = image
            } else if let recordID, case let .blob(blob) = asset.source {
                let host = try await pdsHosts.pdsHost(forRecordURI: recordID)
                var image = asset
                image.source = .url(try Self.blobURL(recordID: recordID, blob: blob, host: host))
                resolvedAsset = image
            } else if let cacheContext {
                resolvedAsset = try await imageAssetResolver.resolve(asset, cacheContext)
            } else {
                return
            }
            guard !Task.isCancelled else { return }
            self.resolvedAsset = resolvedAsset
            self.resolvedTaskID = taskID
            self.failedTaskID = nil
        } catch {
            guard !Task.isCancelled else { return }
            self.failedTaskID = resolutionTaskID
        }
    }

    static func blobURL(
        recordID: Event.ID,
        blob: ATProto.Blob,
        host: ATProto.PDSHost
    ) throws -> URL {
        guard case let .did(did) = recordID.authority,
              var components = URLComponents(string: "https://\(host)") else {
            throw URLError(.badURL)
        }
        components.path = "/xrpc/com.atproto.sync.getBlob"
        components.queryItems = [
            URLQueryItem(name: "did", value: did.description),
            URLQueryItem(name: "cid", value: blob.ref.rawValue),
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        return url
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
                .padding(
                    EdgeInsets(
                        top: layout.frame.minY,
                        leading: layout.frame.minX,
                        bottom: geometry.size.height - layout.frame.maxY,
                        trailing: geometry.size.width - layout.frame.maxX
                    )
                )
        }
        .clipped()
    }

    func safeRect(in size: CGSize) -> CGRect {
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

private extension OME.ImageAsset.FocalPoint {
    var point: CGPoint {
        CGPoint(x: x, y: y)
    }
}
