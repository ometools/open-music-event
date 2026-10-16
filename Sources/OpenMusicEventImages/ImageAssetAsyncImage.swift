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
    let recordImage: OME.Image?
    let recordID: Event.ID?
    var contentMode: ContentMode?
    var renderedImageSize: ImageFocusCGSize?
    var focusSafeAreaInsets: EdgeInsets
    let onIntrinsicSizeLoaded: (ImageFocusCGSize) -> Void
    @ViewBuilder var placeholder: (ImageAssetPlaceholderReason) -> Placeholder
    @Dependency(ATProto.Repository.PDSHostResolver.self) var pdsHosts
    @State var resolvedRecordURL: URL?
    @State var resolvedTaskID: String?
    @State var failedTaskID: String?

    public init(
        image: DisplayImageAsset?,
        contentMode: ContentMode? = nil,
        renderedImageSize: ImageFocusCGSize? = nil,
        focusSafeAreaInsets: EdgeInsets = EdgeInsets(),
        onIntrinsicSizeLoaded: @escaping (ImageFocusCGSize) -> Void = { _ in },
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        switch image {
        case let .record(recordImage, recordID):
            self.recordImage = recordImage
            self.recordID = recordID
        case .none:
            self.recordImage = nil
            self.recordID = nil
        }
        self.contentMode = contentMode
        self.renderedImageSize = renderedImageSize
        self.focusSafeAreaInsets = focusSafeAreaInsets
        self.onIntrinsicSizeLoaded = onIntrinsicSizeLoaded
        self.placeholder = { _ in placeholder() }
    }

    public init(
        image: DisplayImageAsset?,
        contentMode: ContentMode? = nil,
        renderedImageSize: ImageFocusCGSize? = nil,
        focusSafeAreaInsets: EdgeInsets = EdgeInsets(),
        onIntrinsicSizeLoaded: @escaping (ImageFocusCGSize) -> Void = { _ in },
        @ViewBuilder placeholder: @escaping (ImageAssetPlaceholderReason) -> Placeholder
    ) {
        switch image {
        case let .record(recordImage, recordID):
            self.recordImage = recordImage
            self.recordID = recordID
        case .none:
            self.recordImage = nil
            self.recordID = nil
        }
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
        } else if let url = displayURL {
            CachedRemoteImage(
                url: url,
                cacheKey: renderingCacheKey,
                targetSize: renderedImageSize
            ) { phase in
                switch phase {
                case .empty:
                    placeholder(.loading)
                case let .success(image, intrinsicSize):
                    renderedImage(image, intrinsicSize: intrinsicSize)
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

    var displayURL: URL? {
        resolvedTaskID == resolutionTaskID
            ? resolvedRecordURL ?? recordSourceURL
            : recordSourceURL
    }

    var recordSourceURL: URL? {
        guard let recordImage,
              case let .known(.url(url)) = recordImage.source else { return nil }
        return url
    }

    var recordBlob: ATProto.Blob? {
        guard let recordImage,
              case let .known(.blob(blob)) = recordImage.source else { return nil }
        return blob
    }

    var shouldResolveAsset: Bool {
        recordBlob != nil
            && recordID != nil
            && resolvedTaskID != resolutionTaskID
            && failedTaskID != resolutionTaskID
    }

    var blobCID: String? {
        recordBlob?.ref.rawValue
    }

    var recordRoleID: String? {
        guard let recordImage,
              case let .known(role) = recordImage.role else { return nil }
        return role.rawValue
    }

    var recordRenderingModeID: String? {
        guard let recordImage,
              case let .known(mode) = recordImage.renderingMode else { return nil }
        return mode.rawValue
    }

    var resolutionTaskID: String {
        return [
            recordSourceURL?.absoluteString ?? "nil",
            recordID?.description ?? "nil",
            blobCID ?? "nil",
            recordRoleID ?? "nil",
            recordRenderingModeID ?? "nil",
        ].joined(separator: "|")
    }

    var renderingCacheKey: String {
        [
            resolutionTaskID,
            displayURL?.absoluteString ?? "nil",
        ].joined(separator: "|")
    }

    var resolvedContentMode: ContentMode {
        if let contentMode {
            return contentMode
        }
        return recordImage?.renderingMode == .known(.template) ? .fit : .fill
    }

    @ViewBuilder
    func renderedImage(
        _ image: Image,
        intrinsicSize: ImageFocusCGSize
    ) -> some View {
        let image = image
            .renderingMode(
                recordImage?.renderingMode == .known(.template) ? .template : .original
            )
            .resizable()

        if resolvedContentMode == .fill,
           let focalPoint = recordImage?.focalPoint?.point {
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
        guard let blob = recordBlob, let recordID, shouldResolveAsset else { return }
        let taskID = resolutionTaskID
        do {
            let url: URL
            if let fileURL = try stagedLocalImageBlobURL(for: blob) {
                url = fileURL
            } else {
                let host = try await pdsHosts.pdsHost(forRecordURI: recordID)
                url = try Self.blobURL(recordID: recordID, blob: blob, host: host)
            }
            guard !Task.isCancelled else { return }
            resolvedRecordURL = url
            resolvedTaskID = taskID
            failedTaskID = nil
        } catch {
            guard !Task.isCancelled else { return }
            failedTaskID = taskID
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
    let imageSize: ImageFocusCGSize
    let focalPoint: ImageFocusCGPoint
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

    func safeRect(in size: ImageFocusCGSize) -> ImageFocusCGRect {
        let width = size.width - safeAreaInsets.leading - safeAreaInsets.trailing
        let height = size.height - safeAreaInsets.top - safeAreaInsets.bottom
        guard width > 0, height > 0 else {
            return ImageFocusCGRect(origin: .zero, size: size)
        }
        return ImageFocusCGRect(
            x: safeAreaInsets.leading,
            y: safeAreaInsets.top,
            width: width,
            height: height
        )
    }
}

private extension OME.Image.FocalPoint {
    var point: ImageFocusCGPoint {
        ImageFocusCGPoint(x: x, y: y)
    }
}
