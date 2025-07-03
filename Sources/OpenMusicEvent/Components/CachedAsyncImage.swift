#if canImport(Nuke)
@_exported import Nuke
#endif
//
import SwiftUI
import SkipFuse

let imageCachingLogger = Logger(subsystem: "CachedAsyncImageView", category: "skip-image-caching")
//
public struct CachedAsyncImage<I: View, P: View>: View {
    var requests: [PipelinedRequest]

    @ViewBuilder
    let content: (Image) -> I

    var label: LocalizedStringKey?
    var placeholder: P

    public init(
        requests: [PipelinedRequest],
        label: LocalizedStringKey? = nil,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: () -> P
    ) {
        self.requests = requests
        self.label = label
        self.content = content
        self.placeholder = placeholder()
    }

    public init(
        requests: [ImageRequest],
        on pipeline: ImagePipeline = .shared,
        label: LocalizedStringKey? = nil,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: () -> P
    ) {
        self.init(
            requests: requests.map { PipelinedRequest(request: $0, on: pipeline) },
            label: label,
            content: content,
            placeholder: placeholder
        )
    }
//
    #if os(iOS)
    @State var model = Model()

    public var body: some View {
        Group {
            if let image = model.image {
                content(image)
            } else {
                placeholder
            }
        }
            .accessibilityLabel(label)
            .task(id: requests.map(\.id)) {
                await model.task(requests: requests)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @Observable
    @MainActor
    class Model {
        #if canImport(SwiftUI)
        public var image: Image? {
            #if os(macOS)
            platformImage.map { Image(nsImage: $0) }
            #elseif os(iOS)
            platformImage.map { Image(uiImage: $0) }
            #endif
        }
        #endif

        private var label: Text?
        private var platformImage: PlatformImage?
        private var displayedURLOffset: Int = .max


        private let lock = NSLock()
        func task(requests: [PipelinedRequest]) async {
            imageCachingLogger.info("Loading  Requests: \(dump(requests.map(\.description)))")
            let validRequests = requests.filter { $0.url != nil }
            guard !validRequests.isEmpty else {
                imageCachingLogger.info("No requests to load")
                return
            }

            // Get first available in cache
            let cachedImage = validRequests
                .lazy
                .enumerated()
                .compactMap { offset, request in
                    request.cachedImage.map { (image: $0, offset: offset, request: request) }
                }
            .first

            if let cachedImage {
                let request = cachedImage.request.imageRequest
                imageCachingLogger.info("Cached image found: \(dump(request.description)) at offset: \(cachedImage.offset)")
                self.platformImage = cachedImage.image
                self.displayedURLOffset = cachedImage.offset
            }


            imageCachingLogger.info("Fetching images from cache...")
            await withTaskGroup(of: (offset: Int, result: PlatformImage?).self) { @MainActor group in
                for (offset, request) in validRequests.enumerated() {
                    group.addTask {
                        let fetchedImage = try? await request.image()
                        return (offset, fetchedImage)
                    }
                }

                for await (offset, image) in group {
                    imageCachingLogger.info("Fetching image complete: \(offset)")
                    if let image, offset < displayedURLOffset {
                        imageCachingLogger.info("Displayed image updated: \(offset) to \(image)")
                        self.displayedURLOffset = offset
                        self.platformImage = image
                    }
                }
            }
        }
    }
    #elseif SKIP

    public var body: some View {
        AsyncImage(url: requests.first { $0.imageRequest.url != nil }?.imageRequest.url) { image in
            image.resizable()
        } placeholder: {
            placeholder()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

}

private struct ImageTagKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var imageTag: String? {
        get { self[ImageTagKey.self] }
        set { self[ImageTagKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func accessibilityLabel(_ label: Text?) -> some View {
        if let label {
            self.accessibilityLabel(label)
        } else {
            self
        }

    }

    @ViewBuilder
    func accessibilityLabel(_ label: LocalizedStringKey?) -> some View {
        if let label {
            self.accessibilityLabel(label)
        } else {
            self
        }

    }
}

#if os(iOS)
@dynamicMemberLookup
#endif
public struct PipelinedRequest: @unchecked Sendable {
    public var imageRequest: ImageRequest

    public var pipeline: ImagePipeline

    public var id: some Hashable {
        imageRequest.imageId
    }

    public init(request: ImageRequest, on pipeline: ImagePipeline) {
        self.imageRequest = request
        self.pipeline = pipeline
    }

    #if os(iOS)
    public func image() async throws -> PlatformImage? {
        try await pipeline.image(for: imageRequest)
    }

    public var cachedImage: PlatformImage? {
        print(self.pipeline.cache)
        return self.pipeline.cache[self.imageRequest]?.image
    }

    public subscript<T>(dynamicMember keyPath: KeyPath<ImageRequest, T>) -> T {
        imageRequest[keyPath: keyPath]
    }
    #endif
}


// MARK: Simple Android implementations for compatibility
#if SKIP
public struct ImagePipeline: Sendable {
    public var configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    var cache: DataCache = .init(name: "")

    public static let shared = ImagePipeline()

    public struct Configuration {
        public var dataCache: DataCache?
        public var imageCache: ImageCache?

        public init(dataCache: DataCache? = nil, imageCache: ImageCache? = nil) {
            self.dataCache = dataCache
            self.imageCache = imageCache
        }

        public static var withDataCache = Configuration()
    }
}
struct Unimplemented: Error {}

public struct DataCache {
    public let name: String
    public var sizeLimit: Int = 1024*1024*150

    public init(name: String) throws {
        self.name = name
    }
}

public struct ImageCache: Sendable, Equatable {
    public init() {}
}

public struct ImageRequest: Sendable, Equatable {
    public init(url: URL?, processors: [ImageProcessor] = []) {
        self.url = url
    }

    public let url: URL?
    public let processors: [ImageProcessor] = []
    
    public var imageId: String {
        url?.absoluteString ?? "no-url"
    }
    
    public var description: String {
        "ImageRequest(url: \(url?.absoluteString ?? "nil"))"
    }
}

public struct ImageProcessor: Sendable, Equatable {
//    public static func resize(size: CGSize) -> ImageProcessor {
//        ImageProcessor()
//    }

    public static func resize(width: CGFloat? = nil, height: CGFloat? = nil) -> ImageProcessor {
        ImageProcessor()
    }
}
public typealias PlatformImage = Image
#endif





extension ImageRequest {
    public func withPipeline(_ pipeline: ImagePipeline) -> PipelinedRequest {
        PipelinedRequest(request: self, on: pipeline)
    }
}
//
