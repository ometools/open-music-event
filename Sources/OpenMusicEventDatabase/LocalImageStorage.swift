import ATProto
import ATProtoTypes
import Crypto
import Dependencies
import Foundation
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

public func stageLocalImageBlob(
    _ data: Data,
    mimeType: ATProto.MIMEType
) throws -> ATProto.Blob {
    @Dependency(\.localImageFileStore) var fileStore

    return try stageLocalImageBlob(data, mimeType: mimeType, using: fileStore)
}

public func stageLocalImageBlob(
    _ data: Data,
    mimeType: ATProto.MIMEType,
    using fileStore: LocalImageFileStoreClient
) throws -> ATProto.Blob {

    let cidBytes: [UInt8] = [0x01, 0x55, 0x12, 0x20] + Array(SHA256.hash(data: data))
    let cid = ATProto.CID(rawValue: "b" + base32Lowercase(cidBytes))
    _ = try fileStore.write(cid.rawValue, data, mimeType.rawValue)
    return ATProto.Blob(ref: cid, mimeType: mimeType, size: data.count)
}

public func stagedLocalImageBlobURL(for blob: ATProto.Blob) throws -> URL? {
    @Dependency(\.localImageFileStore) var fileStore
    return try fileStore.existingFileURL(blob.ref.rawValue, blob.mimeType.rawValue)
}

private func base32Lowercase(_ bytes: [UInt8]) -> String {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
    var result = ""
    var value: UInt16 = 0
    var bitCount = 0

    for byte in bytes {
        value = (value << 8) | UInt16(byte)
        bitCount += 8
        while bitCount >= 5 {
            bitCount -= 5
            result.append(alphabet[Int((value >> bitCount) & 0x1f)])
        }
        value &= (1 << bitCount) - 1
    }
    if bitCount > 0 {
        result.append(alphabet[Int((value << (5 - bitCount)) & 0x1f)])
    }
    return result
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

