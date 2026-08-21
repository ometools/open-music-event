import ATProto
import ComposableNotifications
import ComposableNotificationsServer
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone

/// One verified Tangled repository revision that may advance an application source.
///
/// This value is the boundary between Tangled webhook intake and source projection. The AppView
/// processor downloads and validates the exact revisions, publishes the current archive, and then
/// advances its durable source projection and notification outbox together.
public struct TangledSourceUpdate: Equatable, Sendable {
    public init(
        watchID: WebhookInboxDelivery.WatchID,
        deliveryID: WebhookInboxDelivery.DeliveryID,
        repositoryOwnerDID: DID,
        ref: String,
        before: String,
        after: String,
        receivedAt: Date,
        canonicalSource: CanonicalTangledSource,
        repository: TangledRepositoryReference
    ) {
        self.watchID = watchID
        self.deliveryID = deliveryID
        self.repositoryOwnerDID = repositoryOwnerDID
        self.ref = ref
        self.before = before
        self.after = after
        self.receivedAt = receivedAt
        self.canonicalSource = canonicalSource
        self.repository = repository
    }

    public let watchID: WebhookInboxDelivery.WatchID
    public let deliveryID: WebhookInboxDelivery.DeliveryID
    public let repositoryOwnerDID: DID
    public let ref: String
    public let before: String
    public let after: String
    public let receivedAt: Date
    public let canonicalSource: CanonicalTangledSource
    public let repository: TangledRepositoryReference

    public var repositoryKey: ATProto.Record.Key {
        .init(rawValue: repository.repository)
    }
}

/// Host-installed processing for a verified Tangled source update.
///
/// Tangled can retry a delivery when it does not receive an acknowledgement, so processors must
/// accept at-least-once invocation. Event signals and the source checkpoint use the same durable
/// database transaction, while provider delivery continues independently from the outbox.
public struct TangledSourceUpdateProcessor: Sendable {
    public var process: @Sendable (TangledSourceUpdate) async throws -> Void

    public init(
        process: @escaping @Sendable (TangledSourceUpdate) async throws -> Void
    ) {
        self.process = process
    }

    /// Validates and publishes the exact Tangled revision before advancing the source projection.
    /// The projection checkpoint and notification outbox then share one database transaction,
    /// making webhook retries safe.
    public static func publishSourceAndNotifyChannels(
        store: OpenMusicEventAppViewStore,
        artifactPublisher: SourceArtifactPublisher
    ) -> Self {
        publishSourceAndNotifyChannels(
            store: store,
            artifactPublisher: artifactPublisher,
            downloadAndValidate: ValidatedSourceArchive.downloadAndValidate
        )
    }

    static func publishSourceAndNotifyChannels(
        store: OpenMusicEventAppViewStore,
        artifactPublisher: SourceArtifactPublisher,
        downloadAndValidate: @escaping @Sendable (TangledSourceUpdate, String) async throws
            -> ValidatedSourceArchive
    ) -> Self {
        Self { update in
            let checkpoint = try await store.tangledSourceCheckpoint(watchID: update.watchID)
            if let checkpoint {
                try checkpoint.validateWatch(for: update)
                if checkpoint.revision == update.after,
                   checkpoint.publishedArtifact != nil
                {
                    return
                }
                guard checkpoint.revision == update.before
                    || checkpoint.revision == update.after
                else {
                    throw OpenMusicEventAppViewStoreError.tangledSourceRevisionMismatch(
                        watchID: update.watchID.rawValue,
                        expected: update.before,
                        actual: checkpoint.revision
                    )
                }
            }

            let previousSource: TangledSourceSnapshot
            if checkpoint != nil || update.before.isZeroRevision {
                previousSource = .empty(revision: update.before)
            } else {
                previousSource = try await downloadAndValidate(update, update.before).snapshot
            }

            let currentArchive = try await downloadAndValidate(update, update.after)
            let publishedArtifact = try await artifactPublisher.publish(
                SourceArtifactPublicationRequest(
                    archiveData: currentArchive.data,
                    repository: update.repository,
                    revision: update.after
                )
            )
            _ = try await store.apply(
                currentArchive.snapshot,
                replacing: previousSource,
                publishedArtifact: publishedArtifact,
                for: update
            )
        }
    }
}

private extension String {
    var isZeroRevision: Bool {
        !isEmpty && allSatisfy { $0 == "0" }
    }
}
