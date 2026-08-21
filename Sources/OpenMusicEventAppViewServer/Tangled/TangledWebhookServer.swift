import ATProto
import Crypto
import Foundation

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
                ref: payload.ref,
                before: payload.before,
                after: payload.after,
                receivedAt: receivedAt,
                canonicalSource: watch.canonicalSource,
                repository: watch.repository
            )
        )
    }
}

struct TangledWebhookReception: Equatable, Sendable {
    let recordResult: WebhookInboxRecordResult
    let sourceUpdate: TangledSourceUpdate
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
