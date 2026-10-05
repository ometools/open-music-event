import ATProto
import ATProtoOAuth
import ATProtoSQLite
import Crypto
import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData
#if canImport(ImageIO)
import ImageIO
#endif

public func localImageBlob(_ data: Data, mimeType: ATProto.MIMEType) -> ATProto.Blob {
    let bytes: [UInt8] = [0x01, 0x55, 0x12, 0x20] + Array(SHA256.hash(data: data))
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
    var result = "b"
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
    if bitCount > 0 { result.append(alphabet[Int((value << (5 - bitCount)) & 0x1f)]) }
    return ATProto.Blob(ref: ATProto.CID(rawValue: result), mimeType: mimeType, size: data.count)
}

/// The exact records and image bytes reviewed for one publisher account.
public struct EventRecordPublication: Equatable, Sendable {
    public struct Image: Equatable, Sendable {
        public let blob: ATProto.Blob
        public let bytes: Data
    }

    public struct Record: Equatable, Sendable, Identifiable {
        public let event: Event
        public let payload: Lexicon.JSONValue
        public let payloadSHA256: String
        public let images: [Image]
        public var id: Event.ID { event.id }
    }

    public let account: DID
    public let records: [Record]

    public static func prepare(
        events: [Event],
        account: DID,
        imageBytes: (ATProto.Blob) throws -> Data
    ) throws -> Self {
        guard !events.isEmpty else { throw PublicationError.noEvents }
        var identities: Set<Event.ID> = []
        let records = try events.sorted { $0.id.description < $1.id.description }.map { event in
            guard identities.insert(event.id).inserted else {
                throw PublicationError.duplicateEvent(event.id)
            }
            guard event.id.authority == .did(account) else {
                throw PublicationError.wrongAccount
            }
            let encoded = try OpenMusicEventSourcePublicationCompiler.encodeEvent(event)
            let blobs = try imageBlobs(in: encoded.value)
            let images = try blobs.map { blob in
                let bytes = try imageBytes(blob)
                try validateImage(bytes, blob: blob)
                return Image(blob: blob, bytes: bytes)
            }
            return Record(
                event: event, payload: encoded.value,
                payloadSHA256: encoded.sha256,
                images: images
            )
        }
        return Self(account: account, records: records)
    }

    public var authorization: OAuth.AuthRequirement {
        OAuth.AuthRequirement(
            account: .did(account),
            permissions: Set([
                OAuth.Permission("repo:events.openmusic.event?action=create"),
                OAuth.Permission("repo:events.openmusic.event?action=update"),
            ] + records.flatMap { $0.images.map { OAuth.Permission.blob($0.blob.mimeType.rawValue) } }),
            reason: "Publish these events and their images to your repository."
        )
    }

    static func imageBlobs(in value: Lexicon.JSONValue) throws -> [ATProto.Blob] {
        var blobs: [ATProto.Blob] = []
        func visit(_ value: Lexicon.JSONValue) throws {
            switch value {
            case let .object(object):
                if object["$type"] == .string("blob") {
                    let blob = try JSONDecoder().decode(ATProto.Blob.self, from: JSONEncoder().encode(value))
                    if !blobs.contains(blob) { blobs.append(blob) }
                } else {
                    for key in object.keys.sorted() { try visit(object[key]!) }
                }
            case let .array(values):
                for value in values { try visit(value) }
            default:
                break
            }
        }
        try visit(value)
        return blobs
    }

    static func validateImage(_ bytes: Data, blob: ATProto.Blob) throws {
        guard !bytes.isEmpty, bytes.count <= 50_000_000, blob.size == bytes.count,
              blob.mimeType == .png || blob.mimeType == .jpeg else {
            throw PublicationError.invalidImage(blob.ref)
        }
        let isPNG = bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
        let isJPEG = bytes.starts(with: [255, 216, 255]) && bytes.suffix(2) == Data([255, 217])
        guard (blob.mimeType == .png && isPNG) || (blob.mimeType == .jpeg && isJPEG) else {
            throw PublicationError.invalidImage(blob.ref)
        }
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw PublicationError.invalidImage(blob.ref)
        }
        #endif
        // Staging uses the protocol's raw SHA-256 CID, without changing the bytes.
        let actual = localImageBlob(bytes, mimeType: blob.mimeType)
        guard actual == blob else { throw PublicationError.invalidImage(blob.ref) }
    }

    public enum PublicationError: Error, Equatable, LocalizedError {
        case noEvents
        case duplicateEvent(Event.ID)
        case wrongAccount
        case reviewChanged
        case missingImage(ATProto.CID)
        case invalidImage(ATProto.CID)
        case uploadMismatch(ATProto.CID)
        case readbackMismatch(Event.ID)

        public var errorDescription: String? {
            switch self {
            case .noEvents: "There are no events to publish."
            case .duplicateEvent: "An event appears more than once in this publication."
            case .wrongAccount: "Select the account that owns these event records and review again."
            case .reviewChanged: "The events changed. Review the current content before publishing."
            case .missingImage: "An image's local bytes are unavailable. Import it again before publishing."
            case .invalidImage: "An image does not match its content, format, or size requirements."
            case .uploadMismatch: "The server returned different image metadata. The event was not published."
            case .readbackMismatch: "The published record could not be verified. Retry to check its status."
            }
        }
    }
}

@Table("eventRecordPublicationReceipts")
public struct EventRecordPublicationReceipt: Codable, Equatable, Sendable, Identifiable {
    public let id: Event.ID
    public let cid: ATProto.CID
    public let payloadSHA256: String
    @Column(as: [ATProto.Blob].JSONRepresentation.self)
    public var images: [ATProto.Blob]
}

public struct EventRecordPublicationResult: Equatable, Sendable {
    public var receipts: [EventRecordPublicationReceipt] = []
    public var failures: [Event.ID: String] = [:]
}

public struct EventRecordPublisher: Sendable {
    public var upload: @Sendable (EventRecordPublication.Image, OAuth.AuthRequirement) async throws -> ATProto.Blob
    public var put: @Sendable (EventRecordPublication.Record, OAuth.AuthRequirement) async throws -> ATProto.Repository.WriteRecordOutput
    public var read: @Sendable (Event.ID, ATProto.CID) async throws -> ATProto.Repository.ListedRecord<Lexicon.JSONValue>

    public func publish(_ publication: EventRecordPublication) async throws -> EventRecordPublicationResult {
        var result = EventRecordPublicationResult()
        for record in publication.records {
            do {
                try Task.checkCancellation()
                for image in record.images {
                    let uploaded = try await upload(image, publication.authorization)
                    guard uploaded == image.blob else {
                        throw EventRecordPublication.PublicationError.uploadMismatch(image.blob.ref)
                    }
                }
                let written = try await put(record, publication.authorization)
                guard written.uri == record.id else {
                    throw EventRecordPublication.PublicationError.readbackMismatch(record.id)
                }
                let observed = try await read(written.uri, written.cid)
                guard observed.uri == record.id, observed.cid == written.cid,
                      observed.value == record.payload else {
                    throw EventRecordPublication.PublicationError.readbackMismatch(record.id)
                }
                result.receipts.append(.init(
                    id: record.id, cid: written.cid, payloadSHA256: record.payloadSHA256,
                    images: record.images.map(\.blob)
                ))
            } catch is CancellationError {
                result.failures[record.id] = "Publication was cancelled. Retry to verify this record."
                return result
            } catch {
                result.failures[record.id] = error.localizedDescription
            }
        }
        return result
    }
}

extension EventRecordPublisher: DependencyKey {
    public static var liveValue: Self {
        Self(
            upload: { image, requirement in
                @Dependency(XRPC.Client.self) var xrpc
                return try await xrpc.run(ATProto.Repository.UploadBlobRequest(
                    body: image.bytes, contentType: image.blob.mimeType,
                    authorizationPolicy: .required(requirement)
                )).blob
            },
            put: { record, requirement in
                @Dependency(XRPC.Client.self) var xrpc
                return try await xrpc.run(ATProto.Repository.PutRecordRequest(
                    input: .init(
                        repo: record.id.authority, collection: Event.lexiconID.nsid,
                        rkey: record.id.rkey!, record: record.payload
                    ),
                    authorizationPolicy: .required(requirement)
                ))
            },
            read: { id, cid in
                @Dependency(XRPC.Client.self) var xrpc
                @Dependency(ATProto.Repository.PDSHostResolver.self) var pdsHosts
                let host = try await pdsHosts.pdsHost(forRecordURI: id)
                return try await xrpc.getRecord(
                    Lexicon.JSONValue.self,
                    repo: id.authority, collection: Event.lexiconID.nsid,
                    rkey: id.rkey!, cid: cid, pdsHost: host
                )
            }
        )
    }
}
