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
        guard let deliveryIDValue = request.deliveryID,
              let deliveryUUID = UUID(uuidString: deliveryIDValue)
        else {
            throw TangledWebhookReceiveError.invalidDeliveryID
        }
        let deliveryID = WebhookInboxDelivery.DeliveryID(
            rawValue: deliveryUUID.uuidString.lowercased()
        )

        guard let eventName = request.event else {
            throw TangledWebhookReceiveError.unsupportedEvent
        }
        let event: TangledWebhookReception.Event
        switch eventName {
        case "push":
            event = .sourceUpdate(
                try TangledSourceUpdate(
                    payload: request.payload,
                    deliveryID: deliveryID,
                    receivedAt: receivedAt,
                    watch: watch,
                    headerRepository: request.repository
                )
            )

        case "pull_request:created":
            event = .pullCreated(
                try TangledPullCreated(
                    payload: request.payload,
                    deliveryID: deliveryID,
                    receivedAt: receivedAt,
                    watch: watch,
                    headerRepository: request.repository
                )
            )

        default:
            throw TangledWebhookReceiveError.unsupportedEvent
        }

        let recordResult = try await inbox.record(
            WebhookInboxDelivery(
                source: .tangled,
                watchID: watch.id,
                deliveryID: deliveryID,
                event: eventName,
                payload: request.payload,
                receivedAt: receivedAt
            )
        )
        return TangledWebhookReception(
            recordResult: recordResult,
            event: event
        )
    }
}

struct TangledWebhookReception: Equatable, Sendable {
    enum Event: Equatable, Sendable {
        case sourceUpdate(TangledSourceUpdate)
        case pullCreated(TangledPullCreated)
    }

    let recordResult: WebhookInboxRecordResult
    let event: Event
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
    case pullRequestMismatch
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

private extension TangledSourceUpdate {
    init(
        payload data: Data,
        deliveryID: WebhookInboxDelivery.DeliveryID,
        receivedAt: Date,
        watch: TangledWebhookWatch,
        headerRepository: String?
    ) throws {
        let payload: TangledPushPayload
        do {
            payload = try JSONDecoder().decode(TangledPushPayload.self, from: data)
        } catch {
            throw TangledWebhookReceiveError.invalidPayload
        }
        guard payload.ref == watch.ref else {
            throw TangledWebhookReceiveError.refMismatch
        }
        try validate(
            payload.repository,
            headerRepository: headerRepository,
            watch: watch
        )
        self.init(
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
    }
}

extension TangledPullCreated {
    init(
        payload data: Data,
        deliveryID: WebhookInboxDelivery.DeliveryID,
        receivedAt: Date,
        watch: TangledWebhookWatch,
        headerRepository: String? = nil
    ) throws {
        let payload: TangledPullRequestPayload
        do {
            payload = try JSONDecoder().decode(TangledPullRequestPayload.self, from: data)
        } catch {
            throw TangledWebhookReceiveError.invalidPayload
        }
        guard payload.action == "created",
              payload.pullRequest.number > 0,
              payload.pullRequest.roundNumber >= 0,
              !payload.pullRequest.targetBranch.isEmpty,
              payload.pullRequest.state == "open"
        else {
            throw TangledWebhookReceiveError.pullRequestMismatch
        }
        try validate(
            payload.repository,
            headerRepository: headerRepository,
            watch: watch
        )
        try validate(
            pageURL: payload.pullRequest.htmlURL,
            patchURL: payload.pullRequest.patchURL,
            pullNumber: payload.pullRequest.number,
            roundNumber: payload.pullRequest.roundNumber,
            watch: watch
        )
        self.init(
            watchID: watch.id,
            deliveryID: deliveryID,
            webhook: Webhook(
                canonicalSource: watch.canonicalSource.reference,
                repository: Webhook.Repository(
                    host: watch.repository.host,
                    port: watch.repository.port,
                    owner: watch.repository.owner,
                    ownerDID: watch.repositoryOwnerDID,
                    name: watch.repository.repository
                ),
                pullNumber: payload.pullRequest.number,
                authorDID: payload.pullRequest.owner.did,
                title: payload.pullRequest.title,
                body: payload.pullRequest.body,
                targetBranch: payload.pullRequest.targetBranch,
                source: payload.pullRequest.source.map {
                    Webhook.Source(
                        branch: $0.branch,
                        revision: $0.sha,
                        repositoryDID: $0.repo
                    )
                },
                roundNumber: payload.pullRequest.roundNumber,
                state: payload.pullRequest.state,
                pageURL: payload.pullRequest.htmlURL,
                patchURL: payload.pullRequest.patchURL,
                createdAt: payload.pullRequest.createdAt
            ),
            receivedAt: receivedAt
        )
    }
}

private func validate(
    _ repository: TangledWebhookRepository,
    headerRepository: String?,
    watch: TangledWebhookWatch
) throws {
    guard repository.fullName == watch.repositoryFullName,
          repository.owner.did == watch.repositoryOwnerDID
    else {
        throw TangledWebhookReceiveError.repositoryMismatch
    }
    if let headerRepository, headerRepository != repository.fullName {
        throw TangledWebhookReceiveError.repositoryMismatch
    }
}

private func validate(
    pageURL: URL,
    patchURL: URL,
    pullNumber: Int64,
    roundNumber: Int,
    watch: TangledWebhookWatch
) throws {
    let repositoryOwners = [
        watch.repository.owner.trimmingCharacters(in: CharacterSet(charactersIn: "@")),
        watch.repositoryOwnerDID.description,
    ]
    guard validTangledURL(pageURL, watch: watch),
          validTangledURL(patchURL, watch: watch)
    else {
        throw TangledWebhookReceiveError.repositoryMismatch
    }
    let pagePath = pageURL.pathComponents.filter { $0 != "/" }
    let patchPath = patchURL.pathComponents.filter { $0 != "/" }
    guard pagePath.count == 4,
          repositoryOwners.contains(pagePath[0]),
          pagePath[1] == watch.repository.repository,
          pagePath[2] == "pulls",
          pagePath[3] == "\(pullNumber)",
          patchPath.count == 6,
          repositoryOwners.contains(patchPath[0]),
          patchPath[1] == watch.repository.repository,
          patchPath[2] == "pulls",
          patchPath[3] == "\(pullNumber)",
          patchPath[4] == "round",
          patchPath[5] == "\(roundNumber).patch"
    else {
        throw TangledWebhookReceiveError.pullRequestMismatch
    }
}

private func validTangledURL(_ url: URL, watch: TangledWebhookWatch) -> Bool {
    url.scheme == "https"
        && url.host(percentEncoded: false)?.lowercased() == watch.repository.host.lowercased()
        && url.port == watch.repository.port
        && url.user(percentEncoded: false) == nil
        && url.password(percentEncoded: false) == nil
        && url.query(percentEncoded: false) == nil
        && url.fragment(percentEncoded: false) == nil
}

private struct TangledPushPayload: Decodable {
    let ref: String
    let before: String
    let after: String
    let repository: TangledWebhookRepository
}

private struct TangledPullRequestPayload: Decodable {
    let action: String
    let pullRequest: PullRequest
    let repository: TangledWebhookRepository

    enum CodingKeys: String, CodingKey {
        case action
        case pullRequest = "pull_request"
        case repository
    }

    struct PullRequest: Decodable {
        let number: Int64
        let title: String
        let body: String?
        let state: String
        let targetBranch: String
        let source: Source?
        let roundNumber: Int
        let owner: TangledWebhookUser
        let htmlURL: URL
        let patchURL: URL
        let createdAt: String

        struct Source: Decodable {
            let branch: String
            let sha: String?
            let repo: String?
        }

        enum CodingKeys: String, CodingKey {
            case number
            case title
            case body
            case state
            case targetBranch = "target_branch"
            case source
            case roundNumber = "round_number"
            case owner
            case htmlURL = "html_url"
            case patchURL = "patch_url"
            case createdAt = "created_at"
        }
    }
}

private struct TangledWebhookRepository: Decodable {
    let fullName: String
    let owner: TangledWebhookUser

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case owner
    }
}

private struct TangledWebhookUser: Decodable {
    let did: DID
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
