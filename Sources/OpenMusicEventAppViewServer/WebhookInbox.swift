import Foundation
import Tagged

public struct WebhookInboxDelivery: Equatable, Sendable {
    public enum SourceTag {}
    public typealias Source = Tagged<SourceTag, String>

    public enum WatchIDTag {}
    public typealias WatchID = Tagged<WatchIDTag, String>

    public enum DeliveryIDTag {}
    public typealias DeliveryID = Tagged<DeliveryIDTag, String>

    public init(
        source: Source,
        watchID: WatchID,
        deliveryID: DeliveryID,
        event: String,
        payload: Data,
        receivedAt: Date
    ) {
        self.source = source
        self.watchID = watchID
        self.deliveryID = deliveryID
        self.event = event
        self.payload = payload
        self.receivedAt = receivedAt
    }

    public let source: Source
    public let watchID: WatchID
    public let deliveryID: DeliveryID
    public let event: String
    public let payload: Data
    public let receivedAt: Date
}

public extension WebhookInboxDelivery.Source {
    static var tangled: Self { Self(rawValue: "tangled") }
}

public enum WebhookInboxRecordResult: Equatable, Sendable {
    case inserted
    case duplicate
}

public enum WebhookInboxError: Error, Equatable, Sendable {
    case deliveryConflict(
        source: WebhookInboxDelivery.Source,
        deliveryID: WebhookInboxDelivery.DeliveryID
    )
}

public protocol WebhookInboxStore: Sendable {
    func record(
        _ delivery: WebhookInboxDelivery
    ) async throws -> WebhookInboxRecordResult
}
