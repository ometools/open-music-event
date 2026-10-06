import ATProto
import ATProtoOAuth
import Crypto
import Dependencies
import FileTree
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import Tagged

public struct SourceRecordPublication: Sendable {
    public struct Record: Equatable, Sendable {
        public let id: ATProto.URI
        public let payload: Lexicon.JSONValue
        public let payloadSHA256: String
        public let images: [EventRecordPublication.Image]
    }
    public struct Receipt: Codable, Equatable, Sendable {
        public let id: ATProto.URI
        public let cid: ATProto.CID
        public let payloadSHA256: String
        public let value: Lexicon.JSONValue
        public init(id: ATProto.URI, cid: ATProto.CID, payloadSHA256: String, value: Lexicon.JSONValue) {
            self.id = id; self.cid = cid; self.payloadSHA256 = payloadSHA256; self.value = value
        }
    }
    public struct Result: Sendable {
        public var receipts: [Receipt] = []
        public var failures: [ATProto.URI: String] = [:]
        public init() {}
    }
    public let account: DID
    public var records: [Record] = []
    public var diagnostics: [String] = []
    public init(account: DID) { self.account = account }

    public var authorization: OAuth.AuthRequirement {
        .init(account: .did(account), permissions: Set(records.flatMap { record in
            [OAuth.Permission("repo:\(record.id.collection!.rawValue)?action=create"),
             OAuth.Permission("repo:\(record.id.collection!.rawValue)?action=update")]
            + record.images.map { OAuth.Permission.blob($0.blob.mimeType.rawValue) }
        }), reason: "Publish the source event records and their images.")
    }

    public mutating func append(id: ATProto.URI, payload: Lexicon.JSONValue, images: [ATProto.CID: Data]) throws {
        guard id.authority == .did(account), let collection = id.collection, id.rkey != nil,
              payload.object?["$type"] == .string(collection.rawValue) else {
            throw ValidationError("A source record must belong to its publisher and match its collection")
        }
        let blobs = try EventRecordPublication.imageBlobs(in: payload)
        let staged = try blobs.map { blob in
            guard let bytes = images[blob.ref] else { throw EventRecordPublication.PublicationError.missingImage(blob.ref) }
            do { try EventRecordPublication.validateImage(bytes, blob: blob) }
            catch { throw ValidationError("Image \(blob.ref.rawValue) for \(id): \(error.localizedDescription)") }
            return EventRecordPublication.Image(blob: blob, bytes: bytes)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = Data(SHA256.hash(data: try encoder.encode(payload))).base64EncodedString()
        records.append(.init(id: id, payload: payload, payloadSHA256: digest, images: staged))
    }
}

public struct SourceRecordPublisher: Sendable {
    public var put: @Sendable (SourceRecordPublication.Record, OAuth.AuthRequirement) async throws -> ATProto.Repository.WriteRecordOutput
    public var upload: @Sendable (EventRecordPublication.Image, OAuth.AuthRequirement) async throws -> ATProto.Blob
    public var read: @Sendable (ATProto.URI, ATProto.CID) async throws -> ATProto.Repository.ListedRecord<Lexicon.JSONValue>

    public func publish(_ publication: SourceRecordPublication) async -> SourceRecordPublication.Result {
        var result = SourceRecordPublication.Result()
        var uploaded: Set<ATProto.CID> = []
        let authorization = publication.authorization
        for record in publication.records {
            do {
                try Task.checkCancellation()
                for image in record.images where !uploaded.contains(image.blob.ref) {
                    guard try await upload(image, authorization) == image.blob else { throw EventRecordPublication.PublicationError.uploadMismatch(image.blob.ref) }
                    uploaded.insert(image.blob.ref)
                }
                let written = try await put(record, authorization)
                guard written.uri == record.id else { throw EventRecordPublication.PublicationError.readbackMismatch(record.id) }
                let observed = try await read(record.id, written.cid)
                guard observed.uri == record.id, observed.cid == written.cid, observed.value == record.payload else {
                    throw EventRecordPublication.PublicationError.readbackMismatch(record.id)
                }
                result.receipts.append(.init(id: record.id, cid: written.cid, payloadSHA256: record.payloadSHA256, value: observed.value))
            } catch {
                result.failures[record.id] = error.localizedDescription
                // Do not publish a parent after any of its dependencies failed verification.
                break
            }
        }
        return result
    }
}

extension SourceRecordPublisher: DependencyKey {
    public static var liveValue: Self {
        .init(put: { record, requirement in
            @Dependency(XRPC.Client.self) var xrpc
            return try await xrpc.run(ATProto.Repository.PutRecordRequest(input: .init(
                repo: record.id.authority, collection: record.id.collection!, rkey: record.id.rkey!, record: record.payload
            ), authorizationPolicy: .required(requirement)))
        }, upload: EventRecordPublisher.liveValue.upload, read: { id, cid in
            @Dependency(XRPC.Client.self) var xrpc
            @Dependency(ATProto.Repository.PDSHostResolver.self) var pdsHosts
            let host = try await pdsHosts.pdsHost(forRecordURI: id)
            return try await xrpc.getRecord(Lexicon.JSONValue.self, repo: id.authority,
                collection: id.collection!, rkey: id.rkey!, cid: cid, pdsHost: host)
        })
    }
}
