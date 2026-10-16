import ATProto
import FileTree
import Foundation
import OpenMusicEventLexicon

public struct OpenMusicEventSourcePublicationPlan: Codable, Equatable, Sendable {
    public struct Event: Codable, Equatable, Sendable {
        public var sourceDirectory: String
        public var recordKey: String
        public var createdAt: Date

        public init(
            sourceDirectory: String,
            recordKey: String,
            createdAt: Date
        ) {
            self.sourceDirectory = sourceDirectory
            self.recordKey = recordKey
            self.createdAt = createdAt
        }
    }

    public var events: [Event]

    public init(events: [Event]) {
        self.events = events
    }
}

public struct OpenMusicEventSourcePublicationManifest: Codable, Equatable, Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public var sourceDirectory: String
        public var uri: String
        public var collection: String
        public var recordKey: String
        public var createdAt: Date
        public var payloadSHA256: String
        public var payload: Lexicon.JSONValue

        public init(
            sourceDirectory: String,
            uri: String,
            collection: String,
            recordKey: String,
            createdAt: Date,
            payloadSHA256: String,
            payload: Lexicon.JSONValue
        ) {
            self.sourceDirectory = sourceDirectory
            self.uri = uri
            self.collection = collection
            self.recordKey = recordKey
            self.createdAt = createdAt
            self.payloadSHA256 = payloadSHA256
            self.payload = payload
        }
    }

    public var formatVersion: Int
    public var account: String
    public var source: String
    public var records: [Record]

    public init(
        formatVersion: Int = 1,
        account: String,
        source: String,
        records: [Record]
    ) {
        self.formatVersion = formatVersion
        self.account = account
        self.source = source
        self.records = records
    }
}

public enum OpenMusicEventSourcePublicationPreparer {
    public enum PreparationError: Error, Equatable {
        case invalidEventRecordKey(sourceDirectory: String, recordKey: String)
    }

    public static func decodePlan(_ data: Data) throws -> OpenMusicEventSourcePublicationPlan {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OpenMusicEventSourcePublicationPlan.self, from: data)
    }

    public static func prepare(
        sourceURL: URL,
        account: DID,
        plan: OpenMusicEventSourcePublicationPlan
    ) throws -> OpenMusicEventSourcePublicationManifest {
        let sourceURL = sourceURL.standardizedFileURL
        let repository = try OpenMusicEventSourceRepositoryFileTree()
            .read(from: sourceURL)
            .output
            .requiredValue
        let collection = OpenMusicEventLexicon.Event.lexiconID.nsid
        let identities = try plan.events.map { event in
            guard let uri = ATProto.URI(
                "at://\(account.description)/\(collection)/\(event.recordKey)"
            ), uri.rkey != nil else {
                throw PreparationError.invalidEventRecordKey(
                    sourceDirectory: event.sourceDirectory,
                    recordKey: event.recordKey
                )
            }
            return OpenMusicEventSourcePublicationCompiler.EventIdentity(
                sourceDirectory: event.sourceDirectory,
                uri: uri,
                createdAt: event.createdAt
            )
        }
        let preparedRecords = try OpenMusicEventSourcePublicationCompiler.compileEvents(
            repository: repository,
            account: account,
            identities: identities
        )
        let eventsBySourceDirectory = Dictionary(
            uniqueKeysWithValues: plan.events.map { ($0.sourceDirectory, $0) }
        )

        return try OpenMusicEventSourcePublicationManifest(
            account: account.description,
            source: sourceURL.path,
            records: preparedRecords.map { prepared in
                guard let identity = eventsBySourceDirectory[prepared.sourceDirectory],
                      let recordKey = prepared.record.id.rkey
                else {
                    throw OpenMusicEventSourcePublicationCompiler.CompilationError
                        .missingIdentity(prepared.sourceDirectory)
                }
                return try OpenMusicEventSourcePublicationManifest.Record(
                    sourceDirectory: prepared.sourceDirectory,
                    uri: prepared.record.id.description,
                    collection: collection.rawValue,
                    recordKey: recordKey.rawValue,
                    createdAt: identity.createdAt,
                    payloadSHA256: prepared.payloadSHA256,
                    payload: JSONDecoder().decode(
                        Lexicon.JSONValue.self,
                        from: prepared.payload
                    )
                )
            }
        )
    }

    public static func encodeManifest(
        _ manifest: OpenMusicEventSourcePublicationManifest
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(manifest)
        data.append(0x0A)
        return data
    }
}
