import Foundation
#if canImport(ImageIO)
import ImageIO
#endif
#if os(Android) || SKIP_BRIDGE
#if os(Android)
import SkipAndroidBridge
#endif
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

#if os(Android) || canImport(SwiftUI)
// SKIP INSERT: import skip.ui.*

#if os(Android) || SKIP_BRIDGE
public typealias CachedRemoteImageSize = SkipSwiftUI.CGSize
typealias CachedRemoteImageCGFloat = SkipSwiftUI.CGFloat
#else
public typealias CachedRemoteImageSize = CGSize
typealias CachedRemoteImageCGFloat = CGFloat
#endif

public enum CachedRemoteImagePhase {
    case empty
    case success(Image, intrinsicSize: CachedRemoteImageSize)
    case failure
    case unavailable
}

public struct CachedRemoteImage<Content: View>: View {
    public init(
        url: URL?,
        cacheKey: String? = nil,
        targetSize: CachedRemoteImageSize? = nil,
        @ViewBuilder content: @escaping (CachedRemoteImagePhase) -> Content
    ) {
        self.url = url
        self.cacheKey = cacheKey
        self.targetSize = targetSize
        self.content = content
    }

    let url: URL?
    let cacheKey: String?
    let targetSize: CachedRemoteImageSize?
    let content: (CachedRemoteImagePhase) -> Content

    #if os(iOS)
    @Environment(\.displayScale) var displayScale
    #endif
    @State var phase = CachedRemoteImagePhase.empty
    @State var phaseRequestID: String?

    public var body: some View {
        content(currentPhase)
            .task(id: requestID) {
                await loadImage()
            }
    }

    var targetPixelSize: CachedRemoteImageSize? {
        #if os(iOS)
        cachedRemotePixelSize(targetSize: targetSize, displayScale: displayScale)
        #elseif os(Android) || SKIP_BRIDGE
        cachedRemotePixelSize(
            targetSize: targetSize,
            displayScale: CachedRemoteImageAndroidDisplay.scale
        )
        #else
        targetSize
        #endif
    }

    var requestID: String {
        let pixelSize = targetPixelSize.map {
            "\(Int($0.width.rounded()))x\(Int($0.height.rounded()))"
        } ?? "original"
        return [sourceRequestID, pixelSize].joined(separator: "|")
    }

    var sourceRequestID: String {
        return [
            cacheKey ?? url?.absoluteString ?? "nil",
            url?.absoluteString ?? "nil",
        ].joined(separator: "|")
    }

    @MainActor
    var currentPhase: CachedRemoteImagePhase {
        guard url != nil else { return .unavailable }
        #if os(iOS)
        if let cachedImage = CachedRemoteImageStore.shared.cachedImage(key: requestID) {
            return .success(cachedImage.image, intrinsicSize: cachedImage.intrinsicSize)
        }
        #endif
        return phaseRequestID == requestID ? phase : .empty
    }

    @MainActor
    func loadImage() async {
        guard let url else {
            phase = .unavailable
            return
        }

        let requestID = requestID
        phaseRequestID = requestID
        phase = .empty
        do {
            #if os(iOS)
            let loadedImage = try await CachedRemoteImageStore.shared.image(
                url: url,
                key: requestID,
                dataKey: sourceRequestID,
                targetPixelSize: targetPixelSize
            )
            #elseif os(Android) || SKIP_BRIDGE
            let data = try await CachedRemoteImageDataLoader.shared.data(
                url: url,
                key: sourceRequestID
            )
            let loadedImage = try await CachedRemoteAndroidImageStore.shared.image(
                data: data,
                key: requestID,
                targetPixelSize: targetPixelSize
            )
            #else
            let data = try await CachedRemoteImageDataLoader.shared.data(
                url: url,
                key: sourceRequestID
            )
            let loadedImage = try decodeCachedRemoteImage(data)
            #endif
            guard !Task.isCancelled else { return }
            phaseRequestID = requestID
            phase = .success(loadedImage.image, intrinsicSize: loadedImage.intrinsicSize)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phaseRequestID = requestID
            phase = .failure
        }
    }
}

struct CachedRemoteLoadedImage {
    let image: Image
    let intrinsicSize: CachedRemoteImageSize
}

#if os(iOS)
import UIKit

@MainActor
final class CachedRemoteImageStore {
    static let shared = CachedRemoteImageStore()

    let images = NSCache<NSString, UIImage>()

    init() {
        images.countLimit = 256
        images.totalCostLimit = 96 * 1_024 * 1_024
    }

    func cachedImage(key: String) -> CachedRemoteLoadedImage? {
        guard let image = images.object(forKey: key as NSString) else {
            return nil
        }
        return CachedRemoteLoadedImage(
            image: Image(uiImage: image),
            intrinsicSize: image.size
        )
    }

    func image(
        url: URL,
        key: String,
        dataKey: String,
        targetPixelSize: CGSize?
    ) async throws -> CachedRemoteLoadedImage {
        let key = key as NSString
        if let cachedImage = images.object(forKey: key) {
            return CachedRemoteLoadedImage(
                image: Image(uiImage: cachedImage),
                intrinsicSize: cachedImage.size
            )
        }

        let data = try await CachedRemoteImageDataLoader.shared.data(
            url: url,
            key: dataKey
        )
        if let cachedImage = images.object(forKey: key) {
            return CachedRemoteLoadedImage(
                image: Image(uiImage: cachedImage),
                intrinsicSize: cachedImage.size
            )
        }

        let preparedImage: UIImage
        if let targetPixelSize {
            let decodedImage = try decodeCachedRemoteCGImage(
                data,
                targetPixelSize: targetPixelSize
            )
            preparedImage = UIImage(cgImage: decodedImage)
        } else {
            guard let decodedImage = UIImage(data: data) else {
                throw CachedRemoteImageError.invalidImageData
            }
            preparedImage = decodedImage
        }
        let cost = Int(preparedImage.size.width * preparedImage.scale)
            * Int(preparedImage.size.height * preparedImage.scale)
            * 4
        images.setObject(preparedImage, forKey: key, cost: cost)
        return CachedRemoteLoadedImage(
            image: Image(uiImage: preparedImage),
            intrinsicSize: preparedImage.size
        )
    }
}

#elseif os(macOS) && !SKIP_BRIDGE
import AppKit

func decodeCachedRemoteImage(_ data: Data) throws -> CachedRemoteLoadedImage {
    guard let image = NSImage(data: data),
          image.size.width > 0,
          image.size.height > 0 else {
        throw CachedRemoteImageError.invalidImageData
    }
    return CachedRemoteLoadedImage(
        image: Image(nsImage: image),
        intrinsicSize: image.size
    )
}

#elseif os(Android) || SKIP_BRIDGE

actor CachedRemoteAndroidImageStore {
    static let shared = CachedRemoteAndroidImageStore()

    let images = NSCache<NSString, UIImage>()

    init() {
        images.countLimit = 256
        images.totalCostLimit = 96 * 1_024 * 1_024
    }

    func image(
        data: Data,
        key: String,
        targetPixelSize: CachedRemoteImageSize?
    ) throws -> CachedRemoteLoadedImage {
        let key = key as NSString
        if let cachedImage = images.object(forKey: key) {
            return loadedImage(cachedImage)
        }

        let preparedImage = try decodeCachedRemoteUIImage(
            data,
            targetPixelSize: targetPixelSize
        )
        let cost = Int(preparedImage.size.width)
            * Int(preparedImage.size.height)
            * 4
        images.setObject(preparedImage, forKey: key, cost: cost)
        return loadedImage(preparedImage)
    }

    func loadedImage(_ image: UIImage) -> CachedRemoteLoadedImage {
        CachedRemoteLoadedImage(
            image: Image(uiImage: image),
            intrinsicSize: image.size
        )
    }
}

func decodeCachedRemoteUIImage(
    _ data: Data,
    targetPixelSize: CachedRemoteImageSize?
) throws -> UIImage {
    guard let decodedImage = UIImage(data: data),
          decodedImage.size.width > 0,
          decodedImage.size.height > 0 else {
        throw CachedRemoteImageError.invalidImageData
    }

    guard let targetPixelSize else { return decodedImage }
    guard let thumbnailSize = cachedRemoteThumbnailSize(
        intrinsicSize: decodedImage.size,
        targetPixelSize: targetPixelSize
    ), let thumbnail = decodedImage.preparingThumbnail(of: thumbnailSize) else {
        throw CachedRemoteImageError.invalidImageData
    }
    return thumbnail
}

extension CachedRemoteLoadedImage: @unchecked Sendable {}
#endif

actor CachedRemoteImageDataLoader {
    static let shared = CachedRemoteImageDataLoader()

    var inFlight: [String: Task<Data, Error>] = [:]

    func data(url: URL, key: String) async throws -> Data {
        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task<Data, Error> {
            if url.isFileURL {
                return try Data(contentsOf: url, options: .mappedIfSafe)
            }

            let (data, response) = try await URLSession.shared.data(from: url)
            if let response = response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                throw CachedRemoteImageError.httpStatus(response.statusCode)
            }
            return data
        }
        inFlight[key] = task

        do {
            let data = try await task.value
            inFlight[key] = nil
            return data
        } catch {
            inFlight[key] = nil
            throw error
        }
    }
}

enum CachedRemoteImageError: Error {
    case httpStatus(Int)
    case invalidImageData
}

func cachedRemotePixelSize(
    targetSize: CachedRemoteImageSize?,
    displayScale: CachedRemoteImageCGFloat
) -> CachedRemoteImageSize? {
    precondition(
        displayScale.isFinite && displayScale > 0,
        "Display scale must be finite and greater than zero"
    )
    return targetSize.map {
        CachedRemoteImageSize(
            width: $0.width * displayScale,
            height: $0.height * displayScale
        )
    }
}

#if os(Android) || SKIP_BRIDGE
enum CachedRemoteImageAndroidDisplay {
    static let scale: CachedRemoteImageCGFloat = {
        let context = ProcessInfo.processInfo.dynamicAndroidContext()
        guard let resources: AnyDynamicObject = try? context.getResources(),
              let displayMetrics: AnyDynamicObject = try? resources.getDisplayMetrics(),
              let density: Float = displayMetrics.density,
              density.isFinite,
              density > 0 else {
            preconditionFailure("Android display density is unavailable")
        }
        return CachedRemoteImageCGFloat(density)
    }()
}
#endif

func cachedRemoteThumbnailSize(
    intrinsicSize: CachedRemoteImageSize,
    targetPixelSize: CachedRemoteImageSize
) -> CachedRemoteImageSize? {
    guard intrinsicSize.width > 0,
          intrinsicSize.height > 0,
          targetPixelSize.width > 0,
          targetPixelSize.height > 0 else {
        return nil
    }

    let scale = min(
        1,
        min(
            targetPixelSize.width / intrinsicSize.width,
            targetPixelSize.height / intrinsicSize.height
        )
    )
    return CachedRemoteImageSize(
        width: max(1, (intrinsicSize.width * scale).rounded()),
        height: max(1, (intrinsicSize.height * scale).rounded())
    )
}

#if canImport(ImageIO) && !os(Android) && !SKIP_BRIDGE
func decodeCachedRemoteCGImage(
    _ data: Data,
    targetPixelSize: CGSize
) throws -> CGImage {
    guard targetPixelSize.width > 0,
          targetPixelSize.height > 0,
          let source = CGImageSourceCreateWithData(
              data as CFData,
              [kCGImageSourceShouldCache: false] as CFDictionary
          ),
          let image = CGImageSourceCreateThumbnailAtIndex(
              source,
              0,
              [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceShouldCacheImmediately: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(
                      targetPixelSize.width,
                      targetPixelSize.height
                  ),
              ] as CFDictionary
          ) else {
        throw CachedRemoteImageError.invalidImageData
    }
    return image
}
#endif
#endif
