import Dependencies
import Foundation
import HTTPClient
import OpenMusicEventLexicon
import SQLiteData

@Table("localImageBlobs")
public struct LocalImageBlob: Equatable, Sendable, Identifiable {
    @Column(primaryKey: true) public var assetKey: String
    public var organizerID: OME.Organizer.ID
    public var eventID: OME.ID<OME.Event>?
    public var parentKind: ParentKind
    public var parentLocalID: String
    public var role: OME.ImageAsset.Role
    public var renderKind: OME.ImageAsset.RenderKind
    public var mimeType: String
    public var data: Data
    public var sourceURL: URL?
    public var lastFetchedAt: Date?

    public var id: String { assetKey }

    public static func assetKey(
        organizerID: OME.Organizer.ID,
        eventID: OME.ID<OME.Event>?,
        parentKind: ParentKind,
        parentLocalID: String,
        role: OME.ImageAsset.Role,
        discriminator: String? = nil
    ) -> String {
        var components = [organizerID.description]
        if let eventID {
            components.append(eventID.rawValue.rawValue)
        }
        components.append(contentsOf: [
            parentKind.rawValue,
            parentLocalID,
            role.rawValue,
        ])
        if let discriminator, !discriminator.isEmpty {
            components.append(discriminator)
        }
        return components.joined(separator: "|")
    }

    public enum ParentKind: String, Codable, Sendable, Equatable, CaseIterable, SQLiteType {
        case calendar
        case event
        case stage
        case contributor
        case poster
        case communicationPost
    }
}

public struct LocalImageCacheContext: Equatable, Sendable {
    public enum Parent: Equatable, Sendable {
        case calendar(OME.Calendar.ID)
        case event(OME.Event.ID)
        case stage(OME.Stage.ID)
        case contributor(OME.Contributor.ID)
        case poster(OME.Poster.ID)
        case communicationPost(CommsPost.ID)
    }

    public init(calendarID: OME.Calendar.ID) {
        self.parent = .calendar(calendarID)
    }

    public init(eventID: OME.Event.ID) {
        self.parent = .event(eventID)
    }

    public init(stageID: OME.Stage.ID) {
        self.parent = .stage(stageID)
    }

    public init(contributorID: OME.Contributor.ID) {
        self.parent = .contributor(contributorID)
    }

    public init(posterID: OME.Poster.ID) {
        self.parent = .poster(posterID)
    }

    public init(commsPostID: CommsPost.ID) {
        self.parent = .communicationPost(commsPostID)
    }

    public var parent: Parent

    public var organizerID: OME.Organizer.ID {
        switch parent {
        case let .calendar(id):
            id.ownerID
        case let .event(id):
            id.organizerID
        case let .stage(id):
            id.organizerID
        case let .contributor(id):
            id.organizerID
        case let .poster(id):
            id.organizerID
        case let .communicationPost(id):
            id.organizerID
        }
    }

    public var eventID: OME.ID<OME.Event>? {
        switch parent {
        case .calendar:
            nil
        case let .event(id):
            id.eventID
        case let .stage(id):
            id.eventID
        case let .contributor(id):
            id.eventID
        case let .poster(id):
            id.eventID
        case let .communicationPost(id):
            id.eventID
        }
    }

    public var parentKind: LocalImageBlob.ParentKind {
        switch parent {
        case .calendar:
            .calendar
        case .event:
            .event
        case .stage:
            .stage
        case .contributor:
            .contributor
        case .poster:
            .poster
        case .communicationPost:
            .communicationPost
        }
    }

    public var parentLocalID: String {
        switch parent {
        case let .calendar(id):
            id.calendarID.rawValue.rawValue
        case let .event(id):
            id.eventID.rawValue.rawValue
        case let .stage(id):
            id.stageID.rawValue.rawValue
        case let .contributor(id):
            id.contributorID.rawValue.rawValue
        case let .poster(id):
            id.posterID.rawValue.rawValue
        case let .communicationPost(id):
            "\(id.channelID.rawValue.rawValue)|\(id.postID.rawValue)"
        }
    }
}

public struct LocalImageFileStoreClient: Sendable {
    public init(
        existingFileURL: @escaping @Sendable (
            _ assetKey: String,
            _ mimeType: String
        ) throws -> URL? = { _, _ in nil },
        write: @escaping @Sendable (
            _ assetKey: String,
            _ data: Data,
            _ mimeType: String
        ) throws -> URL
    ) {
        self.existingFileURL = existingFileURL
        self.write = write
    }

    public var existingFileURL: @Sendable (
        _ assetKey: String,
        _ mimeType: String
    ) throws -> URL?
    public var write: @Sendable (_ assetKey: String, _ data: Data, _ mimeType: String) throws -> URL
}

private enum LocalImageFileStoreKey: DependencyKey {
    static var liveValue: LocalImageFileStoreClient {
        LocalImageFileStoreClient(
            existingFileURL: { assetKey, mimeType in
                let fileURL = try localImageFileURL(
                    assetKey: assetKey,
                    mimeType: mimeType
                )
                return FileManager.default.fileExists(atPath: fileURL.path)
                    ? fileURL
                    : nil
            },
            write: { assetKey, data, mimeType in
                let directory = try fileStoreRootURL()
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )

                let fileURL = try localImageFileURL(
                    assetKey: assetKey,
                    mimeType: mimeType
                )
                try data.write(to: fileURL, options: .atomic)
                return fileURL
            }
        )
    }

    static var testValue: LocalImageFileStoreClient {
        liveValue
    }
}

public extension DependencyValues {
    var localImageFileStore: LocalImageFileStoreClient {
        get { self[LocalImageFileStoreKey.self] }
        set { self[LocalImageFileStoreKey.self] = newValue }
    }
}

private func localImageFileURL(assetKey: String, mimeType: String) throws -> URL {
    try fileStoreRootURL()
        .appending(path: assetKey.fileSafeComponent)
        .appendingPathExtension(mimeType.fileExtension)
}

public struct LocalImageImportRequest: Equatable, Sendable {
    public init(
        assetKeyDiscriminator: String? = nil,
        data: Data,
        mimeType: String,
        sourceURL: URL? = nil,
        role: OME.ImageAsset.Role,
        renderKind: OME.ImageAsset.RenderKind,
        appearance: OME.ImageAsset.Appearance? = nil,
        materializationPolicy: OME.ImageAsset.MaterializationPolicy,
        thumbhash: String? = nil,
        focalPoint: OME.ImageAsset.FocalPoint? = nil
    ) {
        self.assetKeyDiscriminator = assetKeyDiscriminator
        self.data = data
        self.mimeType = mimeType
        self.sourceURL = sourceURL
        self.role = role
        self.renderKind = renderKind
        self.appearance = appearance
        self.materializationPolicy = materializationPolicy
        self.thumbhash = thumbhash
        self.focalPoint = focalPoint
    }

    public var assetKeyDiscriminator: String?
    public var data: Data
    public var mimeType: String
    public var sourceURL: URL?
    public var role: OME.ImageAsset.Role
    public var renderKind: OME.ImageAsset.RenderKind
    public var appearance: OME.ImageAsset.Appearance?
    public var materializationPolicy: OME.ImageAsset.MaterializationPolicy
    public var thumbhash: String?
    public var focalPoint: OME.ImageAsset.FocalPoint?
}

public struct LocalImageImportResult: Equatable, Sendable {
    public init(image: OME.ImageAsset, blob: LocalImageBlob) {
        self.image = image
        self.blob = blob
    }

    public var image: OME.ImageAsset
    public var blob: LocalImageBlob
}

public func materializeImportedLocalImage(
    _ request: LocalImageImportRequest,
    context: LocalImageCacheContext
) throws -> LocalImageImportResult {
    @Dependency(\.date.now) var now
    @Dependency(\.localImageFileStore) var localImageFileStore

    let assetKey = LocalImageBlob.assetKey(
        organizerID: context.organizerID,
        eventID: context.eventID,
        parentKind: context.parentKind,
        parentLocalID: context.parentLocalID,
        role: request.role,
        discriminator: request.assetKeyDiscriminator
    )
    let fileURL = try localImageFileStore.write(
        assetKey,
        request.data,
        request.mimeType
    )
    let image = OME.ImageAsset(
        assetKey: assetKey,
        source: .url(fileURL),
        role: request.role,
        renderKind: request.renderKind,
        appearance: request.appearance,
        materializationPolicy: request.materializationPolicy,
        thumbhash: request.thumbhash,
        focalPoint: request.focalPoint
    )
    return LocalImageImportResult(
        image: image,
        blob: LocalImageBlob(
            assetKey: assetKey,
            organizerID: context.organizerID,
            eventID: context.eventID,
            parentKind: context.parentKind,
            parentLocalID: context.parentLocalID,
            role: request.role,
            renderKind: request.renderKind,
            mimeType: request.mimeType,
            data: request.data,
            sourceURL: request.sourceURL,
            lastFetchedAt: now
        )
    )
}

public struct ImageAssetResolverClient: Sendable {
    public init(
        resolve: @escaping @Sendable (
            _ image: OME.ImageAsset,
            _ context: LocalImageCacheContext
        ) async throws -> OME.ImageAsset
    ) {
        self.resolve = resolve
    }

    public var resolve: @Sendable (
        _ image: OME.ImageAsset,
        _ context: LocalImageCacheContext
    ) async throws -> OME.ImageAsset
}

public extension ImageAssetResolverClient {
    static var live: Self {
        live(now: Date.init)
    }

    fileprivate static func live(
        now: @escaping @Sendable () -> Date
    ) -> Self {
        let coordinator = ImageAssetResolutionCoordinator()
        return ImageAssetResolverClient { image, context in
            let key = ImageAssetResolutionKey(image: image, context: context)
            return try await coordinator.resolve(key: key) {
                try await resolveImageAsset(
                    image,
                    context: context,
                    now: now
                )
            }
        }
    }

    static let noop = Self { image, _ in image }
}

private enum ImageAssetResolverKey: DependencyKey {
    static let liveValue = ImageAssetResolverClient.live

    static var testValue: ImageAssetResolverClient {
        .noop
    }
}

public extension DependencyValues {
    var imageAssetResolver: ImageAssetResolverClient {
        get { self[ImageAssetResolverKey.self] }
        set { self[ImageAssetResolverKey.self] = newValue }
    }
}

private struct ImageAssetResolutionKey: Hashable, Sendable {
    @_optimize(none)
    init(image: OME.ImageAsset, context: LocalImageCacheContext) {
        self.assetKey = LocalImageMaterializer.assetKey(
            for: image,
            organizerID: context.organizerID,
            eventID: context.eventID,
            parentKind: context.parentKind,
            parentLocalID: context.parentLocalID
        )
        self.organizerID = context.organizerID.description
        self.eventID = context.eventID?.rawValue.rawValue
        self.parentKind = context.parentKind.rawValue
        self.parentLocalID = context.parentLocalID
        self.sourceURL = image.url?.absoluteString
        self.role = image.role.rawValue
        self.renderKind = image.renderKind.rawValue
    }

    var assetKey: String
    var organizerID: String
    var eventID: String?
    var parentKind: String
    var parentLocalID: String
    var sourceURL: String?
    var role: String
    var renderKind: String
}

private actor ImageAssetResolutionCoordinator {
    var inFlight: [ImageAssetResolutionKey: Task<OME.ImageAsset, Error>] = [:]
    var resolved: [ImageAssetResolutionKey: OME.ImageAsset] = [:]

    func resolve(
        key: ImageAssetResolutionKey,
        operation: @escaping @Sendable () async throws -> OME.ImageAsset
    ) async throws -> OME.ImageAsset {
        if let image = resolved[key] {
            if let url = image.url,
               url.isFileURL,
               !FileManager.default.fileExists(atPath: url.path) {
                resolved[key] = nil
            } else {
                return image
            }
        }
        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task {
            try await operation()
        }
        inFlight[key] = task

        do {
            let image = try await task.value
            inFlight[key] = nil
            resolved[key] = image
            return image
        } catch {
            inFlight[key] = nil
            throw error
        }
    }
}

private func resolveImageAsset(
    _ image: OME.ImageAsset,
    context: LocalImageCacheContext,
    now: @escaping @Sendable () -> Date
) async throws -> OME.ImageAsset {
    if let url = image.url,
       url.isFileURL,
       FileManager.default.fileExists(atPath: url.path) {
        return image
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.httpClient) var httpClient
    @Dependency(\.localImageFileStore) var localImageFileStore

    let assetKey = LocalImageMaterializer.assetKey(
        for: image,
        organizerID: context.organizerID,
        eventID: context.eventID,
        parentKind: context.parentKind,
        parentLocalID: context.parentLocalID
    )
    let storedBlob = try await database.read { db in
        try LocalImageBlob
            .where { $0.assetKey.eq(assetKey) }
            .fetchOne(db)
    }
    let reusableBlob = storedBlob.flatMap { blob in
        isReusable(blob, for: image) ? blob : nil
    }

    if let reusableBlob,
       let existingFileURL = try localImageFileStore.existingFileURL(
           reusableBlob.assetKey,
           reusableBlob.mimeType
       ) {
        return image.resolved(assetKey: reusableBlob.assetKey, fileURL: existingFileURL)
    }

    let materializer = LocalImageMaterializer(
        now: now(),
        httpClientGet: { url in
            try await httpClient.get(url, decodingTo: Data.self)
        },
        localFileWriter: localImageFileStore.write,
        storedBlobs: reusableBlob.map { [$0.assetKey: $0] } ?? [:]
    )
    let materialized = try await materializer.materializeImage(
        image,
        organizerID: context.organizerID,
        eventID: context.eventID,
        parentKind: context.parentKind,
        parentLocalID: context.parentLocalID
    )

    guard materialized.image != image || materialized.blob != nil else {
        return image
    }

    try await database.write { db in
        if materialized.shouldPersistImage {
            _ = try updateCachedImage(
                materialized.image,
                replacing: image,
                context: context,
                in: db
            )
        }
        if let blob = materialized.blob {
            try LocalImageBlob.upsert { blob }.execute(db)
        }
    }

    return materialized.image
}

private func isReusable(
    _ blob: LocalImageBlob,
    for image: OME.ImageAsset
) -> Bool {
    guard blob.role == image.role,
          blob.renderKind == image.renderKind else {
        return false
    }

    if let url = image.url,
       url.isFileURL,
       image.assetKey == blob.assetKey {
        return true
    }

    return blob.sourceURL == image.url
}

private extension OME.ImageAsset {
    func resolved(assetKey: String, fileURL: URL) -> Self {
        var image = self
        image.assetKey = assetKey
        image.source = .url(fileURL)
        return image
    }
}

public struct EventImagePrefetchClient: Sendable {
    public init(prefetchAssetsOnOpen: @escaping @Sendable (_ eventID: OME.Event.ID) async throws -> Void) {
        self.prefetchAssetsOnOpen = prefetchAssetsOnOpen
    }

    public var prefetchAssetsOnOpen: @Sendable (_ eventID: OME.Event.ID) async throws -> Void
}

public extension EventImagePrefetchClient {
    static var live: Self {
        let resolver = ImageAssetResolverClient.live
        return EventImagePrefetchClient { eventID in
            @Dependency(\.defaultDatabase) var database
            let resolve = resolver.resolve
            let snapshot = try await database.read { db in
                (
                    try OME.Event.where { $0.id.eq(eventID) }.fetchOne(db),
                    try OME.Stage
                        .where { $0.id.organizerID.eq(eventID.organizerID) }
                        .where { $0.id.eventID.eq(eventID.eventID) }
                        .fetchAll(db),
                    try OME.Contributor
                        .where { $0.id.organizerID.eq(eventID.organizerID) }
                        .where { $0.id.eventID.eq(eventID.eventID) }
                        .fetchAll(db)
                )
            }

            guard let event = snapshot.0 else { return }

            try await withThrowingTaskGroup(of: Void.self) { group in
                for image in event.images ?? []
                where image.materializationPolicy == .prefetchOnOpen {
                    group.addTask {
                        _ = try await resolve(
                            image,
                            LocalImageCacheContext(eventID: event.id)
                        )
                    }
                }
                for stage in snapshot.1 {
                    for image in stage.images ?? []
                    where image.materializationPolicy == .prefetchOnOpen {
                        group.addTask {
                            _ = try await resolve(
                                image,
                                LocalImageCacheContext(stageID: stage.id)
                            )
                        }
                    }
                }
                for contributor in snapshot.2 {
                    for image in contributor.images ?? []
                    where image.materializationPolicy == .prefetchOnOpen {
                        group.addTask {
                            _ = try await resolve(
                                image,
                                LocalImageCacheContext(contributorID: contributor.id)
                            )
                        }
                    }
                }

                try await group.waitForAll()
            }
        }
    }

    static let noop = Self { _ in }
}

private enum EventImagePrefetchKey: DependencyKey {
    static var liveValue: EventImagePrefetchClient {
        .live
    }

    static var testValue: EventImagePrefetchClient {
        .noop
    }
}

public extension DependencyValues {
    var eventImagePrefetch: EventImagePrefetchClient {
        get { self[EventImagePrefetchKey.self] }
        set { self[EventImagePrefetchKey.self] = newValue }
    }
}

public struct LocalImageDisplayCacheClient: Sendable {
    public init(
        resolve: @escaping @Sendable (
            _ image: OME.ImageAsset,
            _ context: LocalImageCacheContext
        ) async throws -> OME.ImageAsset?
    ) {
        self.resolve = resolve
    }

    public var resolve: @Sendable (
        _ image: OME.ImageAsset,
        _ context: LocalImageCacheContext
    ) async throws -> OME.ImageAsset?
}

public extension LocalImageDisplayCacheClient {
    static var live: Self {
        let resolver = ImageAssetResolverClient.live
        return LocalImageDisplayCacheClient { image, context in
            if let url = image.url,
               url.isFileURL,
               FileManager.default.fileExists(atPath: url.path) {
                return image
            }
            let resolved = try await resolver.resolve(
                image,
                context
            )
            guard resolved != image else {
                return nil
            }
            return resolved
        }
    }

    static let noop = Self { _, _ in nil }
}

private enum LocalImageDisplayCacheKey: DependencyKey {
    static var liveValue: LocalImageDisplayCacheClient {
        .live
    }

    static var testValue: LocalImageDisplayCacheClient {
        .noop
    }
}

public extension DependencyValues {
    var localImageDisplayCache: LocalImageDisplayCacheClient {
        get { self[LocalImageDisplayCacheKey.self] }
        set { self[LocalImageDisplayCacheKey.self] = newValue }
    }
}

public struct LazyImageCacheClient: Sendable {
    public init(
        cache: @escaping @Sendable (
            _ image: OME.ImageAsset,
            _ context: LocalImageCacheContext
        ) async throws -> OME.ImageAsset
    ) {
        self.cache = cache
    }

    public var cache: @Sendable (
        _ image: OME.ImageAsset,
        _ context: LocalImageCacheContext
    ) async throws -> OME.ImageAsset
}

public extension LazyImageCacheClient {
    static var live: Self {
        @Dependency(\.date.now) var now
        let resolver = ImageAssetResolverClient.live(now: { now })
        return LazyImageCacheClient { image, context in
            guard image.materializationPolicy == .lazy else { return image }
            return try await resolver.resolve(
                image,
                context
            )
        }
    }

    static let noop = Self { image, _ in image }
}

private enum LazyImageCacheKey: DependencyKey {
    static var liveValue: LazyImageCacheClient {
        .live
    }

    static var testValue: LazyImageCacheClient {
        .noop
    }
}

public extension DependencyValues {
    var lazyImageCache: LazyImageCacheClient {
        get { self[LazyImageCacheKey.self] }
        set { self[LazyImageCacheKey.self] = newValue }
    }
}

struct LocalImageMaterializer {
    var now: Date
    var httpClientGet: @Sendable (URL) async throws -> Data
    var localFileWriter: @Sendable (_ assetKey: String, _ data: Data, _ mimeType: String) throws -> URL
    var storedBlobs: [String: LocalImageBlob] = [:]

    struct Result<Value: Sendable>: Sendable {
        var value: Value
        var blobs: [LocalImageBlob]
    }

    struct ImageResult: Sendable {
        var image: OME.ImageAsset
        var blob: LocalImageBlob?
        var shouldPersistImage: Bool
    }

    func materializeImage(
        _ image: OME.ImageAsset,
        organizerID: OME.Organizer.ID,
        eventID: OME.ID<OME.Event>?,
        parentKind: LocalImageBlob.ParentKind,
        parentLocalID: String
    ) async throws -> ImageResult {
        let assetKey = Self.assetKey(
            for: image,
            organizerID: organizerID,
            eventID: eventID,
            parentKind: parentKind,
            parentLocalID: parentLocalID
        )
        let storedBlob = storedBlobs[assetKey]
        var image = image

        if let storedBlob {
            guard shouldRestoreImage(image, from: storedBlob) else {
                return .init(image: image, blob: nil, shouldPersistImage: false)
            }

            let shouldPersistImage = shouldPersistCachedImage(originalImage: image)
            let localFileURL = try localFileWriter(storedBlob.assetKey, storedBlob.data, storedBlob.mimeType)
            image.assetKey = storedBlob.assetKey
            image.source = .url(localFileURL)
            return .init(
                image: image,
                blob: nil,
                shouldPersistImage: shouldPersistImage
            )
        }

        guard let url = image.url else {
            return .init(image: image, blob: nil, shouldPersistImage: false)
        }

        let data: Data
        let sourceURL: URL
        let mimeType: String
        let shouldPersistImage = url.isFileURL
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .init(image: image, blob: nil, shouldPersistImage: false)
            }
            data = try Data(contentsOf: url)
            sourceURL = url
            mimeType = url.inferredImageMimeType
        } else {
            data = try await httpClientGet(url)
            sourceURL = url
            mimeType = url.inferredImageMimeType
        }

        let localFileURL = try localFileWriter(assetKey, data, mimeType)
        image.assetKey = assetKey
        image.source = .url(localFileURL)

        return .init(
            image: image,
            blob: LocalImageBlob(
                assetKey: assetKey,
                organizerID: organizerID,
                eventID: eventID,
                parentKind: parentKind,
                parentLocalID: parentLocalID,
                role: image.role,
                renderKind: image.renderKind,
                mimeType: mimeType,
                data: data,
                sourceURL: sourceURL,
                lastFetchedAt: now
            ),
            shouldPersistImage: shouldPersistImage
        )
    }

    private func shouldPersistCachedImage(originalImage: OME.ImageAsset) -> Bool {
        guard let url = originalImage.url else {
            return false
        }

        return url.isFileURL
    }

    static func assetKey(
        for image: OME.ImageAsset,
        organizerID: OME.Organizer.ID,
        eventID: OME.ID<OME.Event>?,
        parentKind: LocalImageBlob.ParentKind,
        parentLocalID: String
    ) -> String {
        image.assetKey
        ?? LocalImageBlob.assetKey(
            organizerID: organizerID,
            eventID: eventID,
            parentKind: parentKind,
            parentLocalID: parentLocalID,
            role: image.role
        )
    }

    private func shouldRestoreImage(
        _ image: OME.ImageAsset,
        from storedBlob: LocalImageBlob
    ) -> Bool {
        guard image.role == storedBlob.role,
              image.renderKind == storedBlob.renderKind else {
            return false
        }

        guard let url = image.url else {
            return true
        }

        if url.isFileURL {
            return !FileManager.default.fileExists(atPath: url.path)
                && (
                    image.assetKey == storedBlob.assetKey
                        || storedBlob.sourceURL == url
                )
        }

        return storedBlob.sourceURL == url
    }
}

private func updateCachedImage(
    _ cachedImage: OME.ImageAsset,
    replacing originalImage: OME.ImageAsset,
    context: LocalImageCacheContext,
    in db: Database
) throws -> Bool {
    switch context.parent {
    case let .calendar(id):
        guard var calendar = try OME.Calendar.where({ $0.id.eq(id) }).fetchOne(db),
              replaceImage(originalImage, with: cachedImage, in: &calendar.images) else {
            return false
        }
        try OME.Calendar.upsert { calendar }.execute(db)
        return true

    case let .event(id):
        guard var event = try OME.Event.where({ $0.id.eq(id) }).fetchOne(db),
              replaceImage(originalImage, with: cachedImage, in: &event.images) else {
            return false
        }
        try OME.Event.upsert { event }.execute(db)
        return true

    case let .stage(id):
        guard var stage = try OME.Stage.where({ $0.id.eq(id) }).fetchOne(db),
              replaceImage(originalImage, with: cachedImage, in: &stage.images) else {
            return false
        }
        try OME.Stage.upsert { stage }.execute(db)
        return true

    case let .contributor(id):
        guard var contributor = try OME.Contributor.where({ $0.id.eq(id) }).fetchOne(db),
              replaceImage(originalImage, with: cachedImage, in: &contributor.images) else {
            return false
        }
        try OME.Contributor.upsert { contributor }.execute(db)
        return true

    case let .poster(id):
        guard var poster = try OME.Poster.where({ $0.id.eq(id) }).fetchOne(db),
              poster.image.representsSameImage(as: originalImage) else {
            return false
        }
        poster.image = cachedImage
        try OME.Poster.upsert { poster }.execute(db)
        return true

    case let .communicationPost(id):
        guard var post = try CommsPost.where({ $0.id.eq(id) }).fetchOne(db),
              replaceImage(originalImage, with: cachedImage, in: &post.images) else {
            return false
        }
        try CommsPost.upsert { post }.execute(db)
        return true
    }
}

private func replaceImage(
    _ originalImage: OME.ImageAsset,
    with cachedImage: OME.ImageAsset,
    in images: inout [OME.ImageAsset]?
) -> Bool {
    guard var resolvedImages = images,
          let index = resolvedImages.firstIndex(where: { $0.representsSameImage(as: originalImage) }),
          resolvedImages[index] != cachedImage else {
        return false
    }

    resolvedImages[index] = cachedImage
    images = resolvedImages
    return true
}

private extension OME.ImageAsset {
    func representsSameImage(as other: OME.ImageAsset) -> Bool {
        if let assetKey,
           let otherAssetKey = other.assetKey {
            return assetKey == otherAssetKey
        }
        return role == other.role
            && appearance == other.appearance
            && source == other.source
    }
}

private func fileStoreRootURL() throws -> URL {
    let applicationSupportURL = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    return applicationSupportURL
        .appending(path: "open-music-event-images", directoryHint: .isDirectory)
}

private extension String {
    var fileSafeComponent: String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? UUID().uuidString
    }
}

private extension String {
    var fileExtension: String {
        switch self {
        case "image/png":
            return "png"
        case "image/jpeg":
            return "jpg"
        case "image/webp":
            return "webp"
        case "image/gif":
            return "gif"
        case "image/svg+xml":
            return "svg"
        default:
            return "bin"
        }
    }
}

extension URL {
    var inferredImageMimeType: String {
        switch pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        case "svg":
            return "image/svg+xml"
        default:
            return "application/octet-stream"
        }
    }
}

private extension Array {
    func asyncMap<T>(_ transform: @Sendable (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        result.reserveCapacity(count)
        for element in self {
            result.append(try await transform(element))
        }
        return result
    }
}
