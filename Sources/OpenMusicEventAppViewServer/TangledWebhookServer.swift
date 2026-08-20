import ATProto
import ComposableNotifications
import Crypto
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource

public enum TangledWebhookEndpoint {
    public static let path = "/webhooks/tangled"
}

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

/// The public repository-shaped path where AppView publishes immutable source archives.
///
/// Clients already understand repository references shaped as `host/owner/repository` plus an
/// exact ref. Keeping that shape lets AppView move the bytes without changing the client contract.
public struct SourceArtifactRepository: Equatable, Hashable, Sendable {
    public init(owner: String, repository: String) {
        self.owner = owner
        self.repository = repository
    }

    public let owner: String
    public let repository: String

    fileprivate var path: String {
        "\(owner)/\(repository)"
    }
}

public struct TangledWebhookWatch: Equatable, Sendable {
    public init(
        id: WebhookInboxDelivery.WatchID,
        hookID: Int64,
        repositoryOwnerDID: DID,
        repositoryKey: ATProto.Record.Key,
        ref: String,
        canonicalSource: CanonicalTangledSource,
        artifactRepository: SourceArtifactRepository
    ) {
        self.id = id
        self.hookID = hookID
        self.repositoryOwnerDID = repositoryOwnerDID
        self.repositoryKey = repositoryKey
        self.ref = ref
        self.canonicalSource = canonicalSource
        self.artifactRepository = artifactRepository
    }

    public let id: WebhookInboxDelivery.WatchID
    public let hookID: Int64
    public let repositoryOwnerDID: DID
    public let repositoryKey: ATProto.Record.Key
    public let ref: String
    public let canonicalSource: CanonicalTangledSource
    public let artifactRepository: SourceArtifactRepository

    var repositoryFullName: String {
        "\(repositoryOwnerDID.description)/\(repositoryKey.rawValue)"
    }
}

public struct TangledWebhookConfiguration: Sendable {
    public init(watches: [TangledWebhookWatch]) throws {
        var watchesByHookID: [Int64: TangledWebhookWatch] = [:]
        var watchIDs: Set<WebhookInboxDelivery.WatchID> = []
        var repositoryReferences: Set<String> = []
        var canonicalSourceReferences: Set<String> = []
        var artifactRepositoryPaths: Set<String> = []
        for watch in watches {
            guard watchesByHookID.updateValue(watch, forKey: watch.hookID) == nil else {
                throw TangledWebhookConfigurationError.duplicateHookID(watch.hookID)
            }
            guard watchIDs.insert(watch.id).inserted else {
                throw TangledWebhookConfigurationError.duplicateWatchID(watch.id)
            }
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
            guard watch.artifactRepository.owner.isSourceArtifactPathComponent,
                  watch.artifactRepository.repository.isSourceArtifactPathComponent
            else {
                throw TangledWebhookConfigurationError.invalidArtifactRepository(
                    watch.artifactRepository.path
                )
            }
            guard artifactRepositoryPaths.insert(watch.artifactRepository.path).inserted else {
                throw TangledWebhookConfigurationError.duplicateArtifactRepository(
                    watch.artifactRepository.path
                )
            }
        }

        self.watches = watches
        self.watchesByHookID = watchesByHookID
    }

    public let watches: [TangledWebhookWatch]
    fileprivate let watchesByHookID: [Int64: TangledWebhookWatch]
}

struct TangledWebhookServer: Sendable {
    typealias Secret = @Sendable (
        _ watchID: WebhookInboxDelivery.WatchID
    ) async throws -> Data?

    init(
        configuration: TangledWebhookConfiguration,
        inbox: any WebhookInboxStore,
        secret: @escaping Secret
    ) {
        self.watchesByHookID = configuration.watchesByHookID
        self.inbox = inbox
        self.secret = secret
    }

    private let watchesByHookID: [Int64: TangledWebhookWatch]
    private let inbox: any WebhookInboxStore
    private let secret: Secret

    func receive(
        _ request: TangledWebhookRequest,
        receivedAt: Date
    ) async throws -> TangledWebhookReception {
        guard let hookIDValue = request.hookID,
              let hookID = Int64(hookIDValue),
              let watch = watchesByHookID[hookID]
        else {
            throw TangledWebhookReceiveError.authenticationFailed
        }
        let resolvedSecret: Data?
        do {
            resolvedSecret = try await secret(watch.id)
        } catch {
            throw TangledWebhookReceiveError.secretUnavailable
        }
        guard let secret = resolvedSecret, !secret.isEmpty else {
            throw TangledWebhookReceiveError.secretUnavailable
        }
        guard let signature = request.signature,
              TangledWebhookSignature.isValid(
                signature,
                authenticating: request.payload,
                secret: secret
              )
        else {
            throw TangledWebhookReceiveError.authenticationFailed
        }
        guard request.event == "push" else {
            throw TangledWebhookReceiveError.unsupportedEvent
        }
        guard let deliveryIDValue = request.deliveryID,
              let deliveryUUID = UUID(uuidString: deliveryIDValue)
        else {
            throw TangledWebhookReceiveError.invalidDeliveryID
        }
        let deliveryID = WebhookInboxDelivery.DeliveryID(
            rawValue: deliveryUUID.uuidString.lowercased()
        )

        let payload: TangledPushPayload
        do {
            payload = try JSONDecoder().decode(TangledPushPayload.self, from: request.payload)
        } catch {
            throw TangledWebhookReceiveError.invalidPayload
        }
        guard payload.ref == watch.ref else {
            throw TangledWebhookReceiveError.refMismatch
        }
        guard payload.repository.fullName == watch.repositoryFullName,
              payload.repository.owner.did == watch.repositoryOwnerDID
        else {
            throw TangledWebhookReceiveError.repositoryMismatch
        }
        if let repository = request.repository,
           repository != payload.repository.fullName
        {
            throw TangledWebhookReceiveError.repositoryMismatch
        }

        let recordResult = try await inbox.record(
            WebhookInboxDelivery(
                source: .tangled,
                watchID: watch.id,
                deliveryID: deliveryID,
                event: "push",
                payload: request.payload,
                receivedAt: receivedAt
            )
        )
        return TangledWebhookReception(
            recordResult: recordResult,
            sourceUpdate: TangledSourceUpdate(
                watchID: watch.id,
                deliveryID: deliveryID,
                repositoryOwnerDID: watch.repositoryOwnerDID,
                repositoryKey: watch.repositoryKey,
                ref: payload.ref,
                before: payload.before,
                after: payload.after,
                receivedAt: receivedAt,
                canonicalSource: watch.canonicalSource,
                artifactRepository: watch.artifactRepository
            )
        )
    }
}

struct TangledWebhookReception: Equatable, Sendable {
    let recordResult: WebhookInboxRecordResult
    let sourceUpdate: TangledSourceUpdate
}

public enum TangledWebhookConfigurationError: Error, Equatable, Sendable {
    case duplicateArtifactRepository(String)
    case duplicateCanonicalSource(String)
    case duplicateHookID(Int64)
    case duplicateRepositoryReference(String)
    case duplicateWatchID(WebhookInboxDelivery.WatchID)
    case invalidArtifactRepository(String)
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

struct TangledWebhookRequest: Sendable {
    let event: String?
    let hookID: String?
    let deliveryID: String?
    let repository: String?
    let signature: String?
    let payload: Data
}

enum TangledWebhookReceiveError: Error, Equatable, Sendable {
    case authenticationFailed
    case secretUnavailable
    case unsupportedEvent
    case invalidDeliveryID
    case invalidPayload
    case refMismatch
    case repositoryMismatch
}

enum TangledWebhookSignature {
    static func value(authenticating payload: Data, secret: Data) -> String {
        let code = HMAC<SHA256>.authenticationCode(
            for: payload,
            using: SymmetricKey(data: secret)
        )
        return "sha256=" + code.map { String(format: "%02x", $0) }.joined()
    }

    static func isValid(
        _ value: String,
        authenticating payload: Data,
        secret: Data
    ) -> Bool {
        guard value.hasPrefix("sha256="),
              let code = Data(hexEncoded: value.dropFirst("sha256=".count))
        else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(
            code,
            authenticating: payload,
            using: SymmetricKey(data: secret)
        )
    }
}

private struct TangledPushPayload: Decodable {
    let ref: String
    let before: String
    let after: String
    let repository: Repository
    let pusher: User

    struct Repository: Decodable {
        let name: String
        let fullName: String
        let owner: User

        enum CodingKeys: String, CodingKey {
            case name
            case fullName = "full_name"
            case owner
        }
    }

    struct User: Decodable {
        let did: DID
    }
}

private extension Data {
    init?<S: StringProtocol>(hexEncoded value: S) {
        guard value.count.isMultiple(of: 2) else { return nil }
        self.init(capacity: value.count / 2)
        var index = value.startIndex
        while index != value.endIndex {
            let nextIndex = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<nextIndex], radix: 16) else { return nil }
            append(byte)
            index = nextIndex
        }
    }
}
