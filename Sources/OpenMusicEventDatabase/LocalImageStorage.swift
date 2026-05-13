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

    public enum ParentKind: String, Codable, Sendable, Equatable, CaseIterable, SQLiteType {
        case event
        case stage
        case participant
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

public struct EventImagePrefetchClient: Sendable {
    public init(prefetchAssetsOnOpen: @escaping @Sendable (_ eventID: OME.Event.ID) async throws -> Void) {
        self.prefetchAssetsOnOpen = prefetchAssetsOnOpen
    }

    public var prefetchAssetsOnOpen: @Sendable (_ eventID: OME.Event.ID) async throws -> Void
}

private enum EventImagePrefetchKey: DependencyKey {
    static var liveValue: EventImagePrefetchClient {
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
                        .fetchAll(db)
                )
            }

            guard let event = snapshot.0 else { return }

            let materializer = LocalImageMaterializer(
                now: Date(),
                httpClientGet: { url in
                    try await httpClient.get(url, decodingTo: Data.self)
                },
                localFileWriter: localImageFileStore.write
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

    static var testValue: EventImagePrefetchClient {
        EventImagePrefetchClient { _ in }
    }
}

public extension DependencyValues {
    var eventImagePrefetch: EventImagePrefetchClient {
        get { self[EventImagePrefetchKey.self] }
        set { self[EventImagePrefetchKey.self] = newValue }
    }
}

struct LocalImageMaterializer {
    var now: Date
    var httpClientGet: @Sendable (URL) async throws -> Data
    var localFileWriter: @Sendable (_ assetKey: String, _ data: Data, _ mimeType: String) throws -> URL

    struct Result<Value: Sendable>: Sendable {
        var value: Value
        var blobs: [LocalImageBlob]
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

        try await withThrowingTaskGroup(of: (Int, OME.ImageAsset, LocalImageBlob?).self) { group in
            for (index, image) in images.enumerated() {
                guard image.materializationPolicy == .prefetchOnOpen,
                      let url = image.url else {
                    continue
                }

                group.addTask {
                    var image = image
                    let data: Data
                    let sourceURL: URL
                    let mimeType: String
                    if url.isFileURL {
                        data = try Data(contentsOf: url)
                        sourceURL = url
                        mimeType = url.inferredImageMimeType
                    } else {
                        data = try await httpClientGet(url)
                        sourceURL = url
                        mimeType = url.inferredImageMimeType
                    }

                    let assetKey = image.assetKey
                        ?? [organizerID.description, eventID.rawValue.rawValue, parentKind.rawValue, parentLocalID, image.role.rawValue]
                        .joined(separator: "|")
                    let localFileURL = try localFileWriter(assetKey, data, mimeType)
                    image.assetKey = assetKey
                    image.source = .url(localFileURL)

                    return (
                        index,
                        image,
                        LocalImageBlob(
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
                        )
                    )
                }
            }

            for try await (index, image, blob) in group {
                resolvedImages[index] = image
                if let blob {
                    blobs.append(blob)
                }
            }
        }

        return (resolvedImages.isEmpty ? nil : resolvedImages, blobs)
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
