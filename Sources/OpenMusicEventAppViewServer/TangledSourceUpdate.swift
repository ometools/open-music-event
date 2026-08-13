import ATProto
import ComposableNotifications
import ComposableNotificationsServer
import Foundation

/// One verified Tangled repository revision that may advance an application source.
///
/// This value is the boundary between Tangled webhook intake and source ingestion. A later
/// processor can fetch the revision, validate and insert its source records, publish records to
/// ATProto, and write artifacts before announcing the resulting source version. The first
/// processor only announces the version already identified by the verified webhook.
public struct TangledSourceUpdate: Equatable, Sendable {
    public init(
        watchID: WebhookInboxDelivery.WatchID,
        deliveryID: WebhookInboxDelivery.DeliveryID,
        repositoryDID: DID,
        repositoryKey: ATProto.Record.Key,
        ref: String,
        before: String,
        after: String,
        receivedAt: Date,
        source: NotificationSource
    ) {
        self.watchID = watchID
        self.deliveryID = deliveryID
        self.repositoryDID = repositoryDID
        self.repositoryKey = repositoryKey
        self.ref = ref
        self.before = before
        self.after = after
        self.receivedAt = receivedAt
        self.source = source
    }

    public let watchID: WebhookInboxDelivery.WatchID
    public let deliveryID: WebhookInboxDelivery.DeliveryID
    public let repositoryDID: DID
    public let repositoryKey: ATProto.Record.Key
    public let ref: String
    public let before: String
    public let after: String
    public let receivedAt: Date
    public let source: NotificationSource
}

/// Host-installed processing for a verified Tangled source update.
///
/// Tangled can retry a delivery when it does not receive an acknowledgement, so processors must
/// accept at-least-once invocation. `sourceAvailable` is intentionally an idempotent refresh hint;
/// richer visible notifications will use their own durable delivery ledger.
public struct TangledSourceUpdateProcessor: Sendable {
    public var process: @Sendable (TangledSourceUpdate) async throws -> Void

    public init(
        process: @escaping @Sendable (TangledSourceUpdate) async throws -> Void
    ) {
        self.process = process
    }

    public static func notificationOutbox(
        database: NotificationDatabase = NotificationDatabase()
    ) -> Self {
        Self { update in
            try await database.enqueue(source: update.source, at: update.receivedAt)
        }
    }
}
