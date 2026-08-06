import Foundation
#if canImport(ImageIO)
import ImageIO
#endif
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

#if os(Android) || canImport(SwiftUI)
// SKIP INSERT: import skip.ui.*

#if os(Android)
public typealias CachedRemoteImageSize = SkipSwiftUI.CGSize
#else
public typealias CachedRemoteImageSize = CGSize
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
        targetSize.map {
            CGSize(width: $0.width * displayScale, height: $0.height * displayScale)
        }
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

#elseif os(macOS)
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

#elseif os(Android)

func decodeCachedRemoteImage(_ data: Data) throws -> CachedRemoteLoadedImage {
    guard let image = UIImage(data: data),
          image.size.width > 0,
          image.size.height > 0 else {
        throw CachedRemoteImageError.invalidImageData
    }
    return CachedRemoteLoadedImage(
        image: Image(uiImage: image),
        intrinsicSize: image.size
    )
}
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

#if canImport(ImageIO) && !os(Android)
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
