import ATProto
import Crypto
import Foundation
import OpenMusicEventLexicon

public enum OpenMusicEventSourcePublicationCompiler {
    /// Shared canonical encoding for imported records and saved app edits.
    public static func encodeEvent(_ record: OpenMusicEventLexicon.Event) throws -> (
        value: Lexicon.JSONValue, data: Data, sha256: String
    ) {
        try record.validateReferences()
        for case let .known(medium) in record.media ?? [] {
            try medium.validateForPublication()
        }
        let value = try record.encodeLexicon()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return (value, data, Data(SHA256.hash(data: data)).base64EncodedString())
    }

    public struct EventIdentity: Equatable, Sendable {
        public var sourceDirectory: String
        public var uri: ATProto.URI
        public var createdAt: Date

        public init(
            sourceDirectory: String,
            uri: ATProto.URI,
            createdAt: Date
        ) {
            self.sourceDirectory = sourceDirectory
            self.uri = uri
            self.createdAt = createdAt
        }
    }

    public struct PreparedEventRecord: Equatable, Sendable {
        public var sourceDirectory: String
        public var record: OpenMusicEventLexicon.Event
        public var payload: Data
        public var payloadSHA256: String

        public init(
            sourceDirectory: String,
            record: OpenMusicEventLexicon.Event,
            payload: Data,
            payloadSHA256: String
        ) {
            self.sourceDirectory = sourceDirectory
            self.record = record
            self.payload = payload
            self.payloadSHA256 = payloadSHA256
        }
    }

    public enum CompilationError: Error, Equatable {
        case accountDoesNotOwnRecord(
            sourceDirectory: String,
            account: DID,
            uri: ATProto.URI
        )
        case duplicateRecordURI(ATProto.URI)
        case duplicateSourceDirectory(String)
        case invalidEventRecordURI(
            sourceDirectory: String,
            uri: ATProto.URI
        )
        case missingIdentity(String)
        case unknownSourceDirectory(String)
    }

    public static func compileEvents(
        repository: OpenMusicEventSourceRepository,
        account: DID,
        identities: [EventIdentity]
    ) throws -> [PreparedEventRecord] {
        let sourceDirectories = Set(repository.events.map(\.directoryName))
        var identitiesBySourceDirectory: [String: EventIdentity] = [:]
        var recordURIs: Set<ATProto.URI> = []

        for identity in identities {
            guard sourceDirectories.contains(identity.sourceDirectory) else {
                throw CompilationError.unknownSourceDirectory(identity.sourceDirectory)
            }
            guard identitiesBySourceDirectory[identity.sourceDirectory] == nil else {
                throw CompilationError.duplicateSourceDirectory(identity.sourceDirectory)
            }
            guard recordURIs.insert(identity.uri).inserted else {
                throw CompilationError.duplicateRecordURI(identity.uri)
            }
            guard case let .did(authority) = identity.uri.authority,
                  authority == account
            else {
                throw CompilationError.accountDoesNotOwnRecord(
                    sourceDirectory: identity.sourceDirectory,
                    account: account,
                    uri: identity.uri
                )
            }
            guard identity.uri.collection == OpenMusicEventLexicon.Event.lexiconID.nsid,
                  identity.uri.rkey != nil
            else {
                throw CompilationError.invalidEventRecordURI(
                    sourceDirectory: identity.sourceDirectory,
                    uri: identity.uri
                )
            }
            identitiesBySourceDirectory[identity.sourceDirectory] = identity
        }

        return try repository.events
            .sorted { $0.directoryName < $1.directoryName }
            .map { sourceEvent in
                guard let identity = identitiesBySourceDirectory[sourceEvent.directoryName] else {
                    throw CompilationError.missingIdentity(sourceEvent.directoryName)
                }
                guard let recordKey = identity.uri.rkey else {
                    throw CompilationError.invalidEventRecordURI(
                        sourceDirectory: sourceEvent.directoryName,
                        uri: identity.uri
                    )
                }

                var draft = sourceEvent.components.event.recordDraft
                draft.id = OME.Event.ID(
                    organizerID: account,
                    eventID: OME.ID<OME.Event>(recordKey)
                )

                let sourceRecord = try JSONDecoder().decode(
                    OME.Event.self,
                    from: JSONEncoder().encode(draft)
                )
                let record = try OpenMusicEventLexicon.Event(
                    id: identity.uri,
                    event: sourceRecord,
                    createdAt: ATProto.DateTime(rawValue: ISO8601DateFormatter().string(from: identity.createdAt))
                )
                let encoded = try encodeEvent(record)

                return PreparedEventRecord(
                    sourceDirectory: sourceEvent.directoryName,
                    record: record,
                    payload: encoded.data,
                    payloadSHA256: encoded.sha256
                )
            }
    }
}
