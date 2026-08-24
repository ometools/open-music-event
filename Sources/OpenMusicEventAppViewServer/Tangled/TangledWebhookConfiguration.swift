import ATProto
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone

/// The stable OME identity assigned to source bytes, independent of which Tangled repository
/// physically supplies those bytes in a particular environment.
public struct CanonicalTangledSource: Equatable, Hashable, Sendable {
    public init(
        organizerID: OME.Organizer.ID,
        repositoryRecordKey: ATProto.Record.Key
    ) {
        self.organizerID = organizerID
        self.repositoryRecordKey = repositoryRecordKey
    }

    public let organizerID: OME.Organizer.ID
    public let repositoryRecordKey: ATProto.Record.Key

    public var reference: String {
        "at://\(organizerID)/sh.tangled.repo/\(repositoryRecordKey.rawValue)"
    }

    func provenance(ref: String) -> OME.SourceDatabaseInsertion.SourceProvenance {
        OME.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: reference,
            ref: ref
        )
    }
}

public struct TangledWebhookWatch: Equatable, Sendable {
    public init(
        repository: TangledRepositoryReference,
        hookID: Int64,
        repositoryOwnerDID: DID,
        ref: String,
        canonicalSource: CanonicalTangledSource
    ) {
        self.repository = repository
        self.hookID = hookID
        self.repositoryOwnerDID = repositoryOwnerDID
        self.ref = ref
        self.canonicalSource = canonicalSource
    }

    /// The physical Tangled repository that signs webhooks, supplies source bytes, and names the
    /// public artifact path. The canonical source below remains the event's stable OME identity.
    public let repository: TangledRepositoryReference
    public let hookID: Int64
    public let repositoryOwnerDID: DID
    public let ref: String
    public let canonicalSource: CanonicalTangledSource

    public var id: WebhookInboxDelivery.WatchID {
        .init(rawValue: "\(repository.displayName)#\(ref)")
    }

    public var repositoryKey: ATProto.Record.Key {
        .init(rawValue: repository.repository)
    }

    var repositoryFullName: String {
        "\(repositoryOwnerDID.description)/\(repository.repository)"
    }
}

public struct TangledWebhookConfiguration: Sendable {
    public init(watches: [TangledWebhookWatch]) throws {
        var watchesByHookID: [Int64: TangledWebhookWatch] = [:]
        var watchesByID: [WebhookInboxDelivery.WatchID: TangledWebhookWatch] = [:]
        var watchIDs: Set<WebhookInboxDelivery.WatchID> = []
        var repositoryReferences: Set<String> = []
        var canonicalSourceReferences: Set<String> = []
        for watch in watches {
            guard watchesByHookID.updateValue(watch, forKey: watch.hookID) == nil else {
                throw TangledWebhookConfigurationError.duplicateHookID(watch.hookID)
            }
            guard watchIDs.insert(watch.id).inserted else {
                throw TangledWebhookConfigurationError.duplicateWatchID(watch.id)
            }
            watchesByID[watch.id] = watch
            let repositoryReference = "\(watch.repositoryFullName)#\(watch.ref)"
            guard repositoryReferences.insert(repositoryReference).inserted else {
                throw TangledWebhookConfigurationError.duplicateRepositoryReference(
                    repositoryReference
                )
            }
            guard canonicalSourceReferences.insert(watch.canonicalSource.reference).inserted else {
                throw TangledWebhookConfigurationError.duplicateCanonicalSource(
                    watch.canonicalSource.reference
                )
            }
            guard watch.repository.owner.isSourceArtifactPathComponent,
                  watch.repository.repository.isSourceArtifactPathComponent
            else {
                throw TangledWebhookConfigurationError.invalidRepositoryPath(
                    watch.repository.displayName
                )
            }
        }

        self.watches = watches
        self.watchesByHookID = watchesByHookID
        self.watchesByID = watchesByID
    }

    public let watches: [TangledWebhookWatch]
    let watchesByHookID: [Int64: TangledWebhookWatch]
    let watchesByID: [WebhookInboxDelivery.WatchID: TangledWebhookWatch]
}

public enum TangledWebhookConfigurationError: Error, Equatable, Sendable {
    case duplicateCanonicalSource(String)
    case duplicateHookID(Int64)
    case duplicateRepositoryReference(String)
    case duplicateWatchID(WebhookInboxDelivery.WatchID)
    case invalidRepositoryPath(String)
}

extension AppViewConfiguration {
    static func tangledWebhookConfiguration(
        environment: [String: String]
    ) throws -> TangledWebhookConfiguration? {
        guard let path = environment["OME_TANGLED_WEBHOOK_CONFIGURATION_PATH"] else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw AppViewConfigurationError.tangledWebhookConfigurationUnreadable(path)
        }

        let file: TangledWebhookConfigurationFile
        do {
            file = try JSONDecoder().decode(TangledWebhookConfigurationFile.self, from: data)
        } catch {
            throw AppViewConfigurationError.tangledWebhookConfigurationInvalid(path)
        }

        let watches = try file.watches.map { configuredWatch in
            let repository = try configuredWatch.physicalRepository()
            guard let repositoryOwnerDID = DID(configuredWatch.repositoryOwnerDID) else {
                throw AppViewConfigurationError.invalidTangledWebhookRepositoryOwnerDID(
                    configuredWatch.repositoryOwnerDID
                )
            }
            guard let organizerID = OME.Organizer.ID(
                configuredWatch.canonicalSource.organizerID
            ) else {
                throw AppViewConfigurationError.invalidTangledCanonicalSourceOrganizerID(
                    configuredWatch.canonicalSource.organizerID
                )
            }
            return TangledWebhookWatch(
                repository: repository,
                hookID: configuredWatch.hookID,
                repositoryOwnerDID: repositoryOwnerDID,
                ref: configuredWatch.ref,
                canonicalSource: CanonicalTangledSource(
                    organizerID: organizerID,
                    repositoryRecordKey: ATProto.Record.Key(
                        rawValue: configuredWatch.canonicalSource.repositoryRecordKey
                    )
                )
            )
        }
        return try TangledWebhookConfiguration(watches: watches)
    }

    static func webhookSecretProtection(
        environment: [String: String]
    ) throws -> WebhookSecretProtection? {
        guard let path = environment["OME_WEBHOOK_SECRET_KEY_PATH"] else {
            guard environment["OME_WEBHOOK_SECRET_KEY_VERSION"] == nil else {
                throw AppViewConfigurationError.webhookSecretKeyMissing
            }
            return nil
        }
        let encodedKey: String
        do {
            encodedKey = try String(
                contentsOf: URL(fileURLWithPath: path),
                encoding: .utf8
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw AppViewConfigurationError.webhookSecretKeyUnreadable(path)
        }
        let rawKeyVersion = environment["OME_WEBHOOK_SECRET_KEY_VERSION"] ?? "1"
        guard let keyVersion = Int(rawKeyVersion), keyVersion > 0 else {
            throw AppViewConfigurationError.invalidWebhookSecretKeyVersion(rawKeyVersion)
        }
        return try WebhookSecretProtection(
            base64EncodedKey: encodedKey,
            keyVersion: keyVersion
        )
    }
}

private struct TangledWebhookConfigurationFile: Decodable {
    var watches: [Watch]

    struct Watch: Decodable {
        var id: String
        var hookID: Int64
        var repositoryOwnerDID: String
        var ref: String
        var canonicalSource: CanonicalSource
    }

    struct CanonicalSource: Decodable {
        var organizerID: String
        var repositoryRecordKey: String
    }
}

private extension TangledWebhookConfigurationFile.Watch {
    func physicalRepository() throws -> TangledRepositoryReference {
        guard let separator = id.firstIndex(of: "#") else {
            throw AppViewConfigurationError.invalidTangledWebhookWatchID(id)
        }
        let repositoryReference = String(id[..<separator])
        let idRef = String(id[id.index(after: separator)...])
        guard idRef == ref,
              let repository = try? TangledRepositoryReference(parsing: repositoryReference),
              id == "\(repository.displayName)#\(ref)"
        else {
            throw AppViewConfigurationError.invalidTangledWebhookWatchID(id)
        }
        return repository
    }
}

private extension String {
    var isSourceArtifactPathComponent: Bool {
        !isEmpty
            && self != "."
            && self != ".."
            && allSatisfy { character in
                character.isASCII
                    && (character.isLetter
                        || character.isNumber
                        || character == "."
                        || character == "-"
                        || character == "_")
            }
    }
}
