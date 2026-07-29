import Foundation
import SwiftUI

public enum CachedRemoteImagePhase {
    case empty
    case success(Image)
    case failure
    case unavailable
}

public struct CachedRemoteImage<Content: View>: View {
    public init(
        url: URL?,
        cacheKey: String? = nil,
        targetSize: CGSize? = nil,
        @ViewBuilder content: @escaping (CachedRemoteImagePhase) -> Content
    ) {
        self.url = url
        self.cacheKey = cacheKey
        self.targetSize = targetSize
        self.content = content
    }

    let url: URL?
    let cacheKey: String?
    let targetSize: CGSize?
    let content: (CachedRemoteImagePhase) -> Content

    #if os(iOS)
    @Environment(\.displayScale) var displayScale
    @State var phase = CachedRemoteImagePhase.empty
    @State var phaseRequestID: String?
    #endif

    public var body: some View {
        #if os(iOS)
        content(currentPhase)
            .task(id: requestID) {
                await loadImage()
            }
        #else
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                content(url == nil ? .unavailable : .empty)
            case let .success(image):
                content(.success(image))
            case .failure:
                content(.failure)
            @unknown default:
                content(.unavailable)
            }
        }
        #endif
    }

    #if os(iOS)
    var targetPixelSize: CGSize? {
        targetSize.map {
            CGSize(width: $0.width * displayScale, height: $0.height * displayScale)
        }
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
        if let cachedImage = CachedRemoteImageStore.shared.cachedImage(key: requestID) {
            return .success(cachedImage)
        }
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
            let image = try await CachedRemoteImageStore.shared.image(
                url: url,
                key: requestID,
                dataKey: sourceRequestID,
                targetPixelSize: targetPixelSize
            )
            guard !Task.isCancelled else { return }
            phaseRequestID = requestID
            phase = .success(image)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phaseRequestID = requestID
            phase = .failure
        }
    }
    #endif
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

    func cachedImage(key: String) -> Image? {
        guard let image = images.object(forKey: key as NSString) else {
            return nil
        }
        return Image(uiImage: image)
    }

    func image(
        url: URL,
        key: String,
        dataKey: String,
        targetPixelSize: CGSize?
    ) async throws -> Image {
        let key = key as NSString
        if let cachedImage = images.object(forKey: key) {
            return Image(uiImage: cachedImage)
        }

        let data = try await CachedRemoteImageDataLoader.shared.data(
            url: url,
            key: dataKey
        )
        if let cachedImage = images.object(forKey: key) {
            return Image(uiImage: cachedImage)
        }

        guard let decodedImage = UIImage(data: data) else {
            throw CachedRemoteImageError.invalidImageData
        }
        let preparedImage = decodedImage.preparingThumbnail(
            targetPixelSize: targetPixelSize
        )
        let cost = Int(preparedImage.size.width * preparedImage.scale)
            * Int(preparedImage.size.height * preparedImage.scale)
            * 4
        images.setObject(preparedImage, forKey: key, cost: cost)
        return Image(uiImage: preparedImage)
    }
}

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

extension UIImage {
    func preparingThumbnail(targetPixelSize: CGSize?) -> UIImage {
        guard let targetPixelSize,
              targetPixelSize.width > 0,
              targetPixelSize.height > 0 else {
            return self
        }

        let sourcePixelSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )
        let scaleRatio = min(
            targetPixelSize.width / sourcePixelSize.width,
            targetPixelSize.height / sourcePixelSize.height,
            1
        )
        guard scaleRatio < 1 else { return self }

        let thumbnailSize = CGSize(
            width: max(1, sourcePixelSize.width * scaleRatio),
            height: max(1, sourcePixelSize.height * scaleRatio)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: thumbnailSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: thumbnailSize))
        }
    }
}
#endif
