import Dependencies
import Foundation
import HTTPClient
import OpenMusicEventLexicon
import SQLiteData

@Table("localImageBlobs")
public struct LocalImageBlob: Equatable, Sendable, Identifiable {
    @Column(primaryKey: true) public var assetKey: String
    public var organizerID: OME.Organizer.ID
    public var eventID: OME.ID<OME.Event>
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
        eventID: OME.ID<OME.Event>,
        parentKind: ParentKind,
        parentLocalID: String,
        role: OME.ImageAsset.Role
    ) -> String {
        [
            organizerID.description,
            eventID.rawValue.rawValue,
            parentKind.rawValue,
            parentLocalID,
            role.rawValue,
        ]
        .joined(separator: "|")
    }

    public enum ParentKind: String, Codable, Sendable, Equatable, CaseIterable, SQLiteType {
        case event
        case stage
        case participant
        case poster
    }
}

public struct LocalImageCacheContext: Equatable, Sendable {
    public enum Parent: Equatable, Sendable {
        case event(OME.Event.ID)
        case stage(OME.Stage.ID)
        case participant(OME.Participant.ID)
        case poster(OME.Poster.ID)
    }

    public init(eventID: OME.Event.ID) {
        self.parent = .event(eventID)
    }

    public init(stageID: OME.Stage.ID) {
        self.parent = .stage(stageID)
    }

    public init(participantID: OME.Participant.ID) {
        self.parent = .participant(participantID)
    }

    public init(posterID: OME.Poster.ID) {
        self.parent = .poster(posterID)
    }

    public var parent: Parent

    public var organizerID: OME.Organizer.ID {
        switch parent {
        case let .event(id):
            id.organizerID
        case let .stage(id):
            id.organizerID
        case let .participant(id):
            id.organizerID
        case let .poster(id):
            id.organizerID
        }
    }

    public var eventID: OME.ID<OME.Event> {
        switch parent {
        case let .event(id):
            id.eventID
        case let .stage(id):
            id.eventID
        case let .participant(id):
            id.eventID
        case let .poster(id):
            id.eventID
        }
    }

    public var parentKind: LocalImageBlob.ParentKind {
        switch parent {
        case .event:
            .event
        case .stage:
            .stage
        case .participant:
            .participant
        case .poster:
            .poster
        }
    }

    public var parentLocalID: String {
        switch parent {
        case let .event(id):
            id.eventID.rawValue.rawValue
        case let .stage(id):
            id.stageID.rawValue.rawValue
        case let .participant(id):
            id.participantID.rawValue.rawValue
        case let .poster(id):
            id.posterID.rawValue.rawValue
        }
    }
}

public struct LocalImageFileStoreClient: Sendable {
    public init(write: @escaping @Sendable (_ assetKey: String, _ data: Data, _ mimeType: String) throws -> URL) {
        self.write = write
    }

    public var write: @Sendable (_ assetKey: String, _ data: Data, _ mimeType: String) throws -> URL
}

private enum LocalImageFileStoreKey: DependencyKey {
    static var liveValue: LocalImageFileStoreClient {
        LocalImageFileStoreClient { assetKey, data, mimeType in
            let directory = try fileStoreRootURL()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let fileURL = directory
                .appending(path: assetKey.fileSafeComponent)
                .appendingPathExtension(mimeType.fileExtension)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        }
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

public struct LocalImageImportRequest: Equatable, Sendable {
    public init(
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
        role: request.role
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

public struct EventImagePrefetchClient: Sendable {
    public init(prefetchAssetsOnOpen: @escaping @Sendable (_ eventID: OME.Event.ID) async throws -> Void) {
        self.prefetchAssetsOnOpen = prefetchAssetsOnOpen
    }

    public var prefetchAssetsOnOpen: @Sendable (_ eventID: OME.Event.ID) async throws -> Void
}

public extension EventImagePrefetchClient {
    static var live: Self {
        EventImagePrefetchClient { eventID in
            @Dependency(\.defaultDatabase) var database
            @Dependency(\.httpClient) var httpClient
            @Dependency(\.localImageFileStore) var localImageFileStore
            let snapshot = try await database.read { db in
                (
                    try OME.Event.where { $0.id.eq(eventID) }.fetchOne(db),
                    try OME.Stage
                        .where { $0.id.organizerID.eq(eventID.organizerID) }
                        .where { $0.id.eventID.eq(eventID.eventID) }
                        .fetchAll(db),
                    try OME.Participant
                        .where { $0.id.organizerID.eq(eventID.organizerID) }
                        .where { $0.id.eventID.eq(eventID.eventID) }
                        .fetchAll(db),
                    try LocalImageBlob
                        .where { $0.organizerID.eq(eventID.organizerID) }
                        .where { $0.eventID.eq(eventID.eventID) }
                        .fetchAll(db)
                )
            }

            guard let event = snapshot.0 else { return }
            let storedBlobs = Dictionary(
                uniqueKeysWithValues: snapshot.3.map { ($0.assetKey, $0) }
            )

            let materializer = LocalImageMaterializer(
                now: Date(),
                httpClientGet: { url in
                    try await httpClient.get(url, decodingTo: Data.self)
                },
                localFileWriter: localImageFileStore.write,
                storedBlobs: storedBlobs
            )

            let materializedEvent = try await materializer.materialize(
                event: event
            )
            let materializedStages = try await snapshot.1.asyncMap { try await materializer.materialize(stage: $0) }
            let materializedParticipants = try await snapshot.2.asyncMap { try await materializer.materialize(participant: $0) }

            let blobs = materializedEvent.blobs
                + materializedStages.flatMap(\.blobs)
                + materializedParticipants.flatMap(\.blobs)

            try await database.write { db in
                if materializedEvent.value != event {
                    try OME.Event.upsert { materializedEvent.value }.execute(db)
                }
                for item in materializedStages where item.value != snapshot.1.first(where: { $0.id == item.value.id }) {
                    try OME.Stage.upsert { item.value }.execute(db)
                }
                for item in materializedParticipants where item.value != snapshot.2.first(where: { $0.id == item.value.id }) {
                    try OME.Participant.upsert { item.value }.execute(db)
                }
                if !blobs.isEmpty {
                    try LocalImageBlob.insert { blobs }.execute(db)
                }
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
        LazyImageCacheClient { image, context in
            guard image.materializationPolicy == .lazy else { return image }
            if let url = image.url,
               url.isFileURL,
               FileManager.default.fileExists(atPath: url.path) {
                return image
            }

            @Dependency(\.date.now) var now
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

            let materializer = LocalImageMaterializer(
                now: now,
                httpClientGet: { url in
                    try await httpClient.get(url, decodingTo: Data.self)
                },
                localFileWriter: localImageFileStore.write,
                storedBlobs: storedBlob.map { [$0.assetKey: $0] } ?? [:]
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
                    try LocalImageBlob.insert { [blob] }.execute(db)
                }
            }

            return materialized.image
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

    func materialize(event: OME.Event) async throws -> Result<OME.Event> {
        let images = try await materializeImages(
            images: event.images,
            organizerID: event.id.organizerID,
            eventID: event.id.eventID,
            parentKind: .event,
            parentLocalID: event.id.eventID.rawValue.rawValue
        )
        var event = event
        event.images = images.images
        return .init(value: event, blobs: images.blobs)
    }

    func materialize(stage: OME.Stage) async throws -> Result<OME.Stage> {
        let images = try await materializeImages(
            images: stage.images,
            organizerID: stage.id.organizerID,
            eventID: stage.id.eventID,
            parentKind: .stage,
            parentLocalID: stage.id.stageID.rawValue.rawValue
        )
        var stage = stage
        stage.images = images.images
        return .init(value: stage, blobs: images.blobs)
    }

    func materialize(participant: OME.Participant) async throws -> Result<OME.Participant> {
        let images = try await materializeImages(
            images: participant.images,
            organizerID: participant.id.organizerID,
            eventID: participant.id.eventID,
            parentKind: .participant,
            parentLocalID: participant.id.participantID.rawValue.rawValue
        )
        var participant = participant
        participant.images = images.images
        return .init(value: participant, blobs: images.blobs)
    }

    private func materializeImages(
        images: [OME.ImageAsset]?,
        organizerID: OME.Organizer.ID,
        eventID: OME.ID<OME.Event>,
        parentKind: LocalImageBlob.ParentKind,
        parentLocalID: String
    ) async throws -> (images: [OME.ImageAsset]?, blobs: [LocalImageBlob]) {
        guard let images else { return (nil, []) }

        var blobs: [LocalImageBlob] = []
        var resolvedImages = images

        try await withThrowingTaskGroup(of: (Int, ImageResult).self) { group in
            for (index, image) in images.enumerated() {
                guard image.materializationPolicy == .prefetchOnOpen else {
                    continue
                }

                group.addTask {
                    let result = try await materializeImage(
                        image,
                        organizerID: organizerID,
                        eventID: eventID,
                        parentKind: parentKind,
                        parentLocalID: parentLocalID
                    )
                    return (index, result)
                }
            }

            for try await (index, result) in group {
                if result.shouldPersistImage {
                    resolvedImages[index] = result.image
                }
                if let blob = result.blob {
                    blobs.append(blob)
                }
            }
        }

        return (resolvedImages.isEmpty ? nil : resolvedImages, blobs)
    }

    func materializeImage(
        _ image: OME.ImageAsset,
        organizerID: OME.Organizer.ID,
        eventID: OME.ID<OME.Event>,
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
        eventID: OME.ID<OME.Event>,
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
        }

        return true
    }
}

private func updateCachedImage(
    _ cachedImage: OME.ImageAsset,
    replacing originalImage: OME.ImageAsset,
    context: LocalImageCacheContext,
    in db: Database
) throws -> Bool {
    switch context.parent {
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

    case let .participant(id):
        guard var participant = try OME.Participant.where({ $0.id.eq(id) }).fetchOne(db),
              replaceImage(originalImage, with: cachedImage, in: &participant.images) else {
            return false
        }
        try OME.Participant.upsert { participant }.execute(db)
        return true

    case let .poster(id):
        guard var poster = try OME.Poster.where({ $0.id.eq(id) }).fetchOne(db),
              poster.image.representsSameImage(as: originalImage) else {
            return false
        }
        poster.image = cachedImage
        try OME.Poster.upsert { poster }.execute(db)
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
