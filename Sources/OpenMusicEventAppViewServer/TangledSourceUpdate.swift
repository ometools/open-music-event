import ATProto
import ComposableNotifications
import ComposableNotificationsServer
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource

/// One verified Tangled repository revision that may advance an application source.
///
/// This value is the boundary between Tangled webhook intake and source projection. The AppView
/// processor checks out the exact revisions, validates every event in the canonical source, and
/// advances its durable communication-post projection before announcing changed channels.
public struct TangledSourceUpdate: Equatable, Sendable {
    public init(
        watchID: WebhookInboxDelivery.WatchID,
        deliveryID: WebhookInboxDelivery.DeliveryID,
        repositoryOwnerDID: DID,
        repositoryKey: ATProto.Record.Key,
        ref: String,
        before: String,
        after: String,
        receivedAt: Date,
        canonicalSource: CanonicalTangledSource,
        artifactRepository: SourceArtifactRepository
    ) {
        self.watchID = watchID
        self.deliveryID = deliveryID
        self.repositoryOwnerDID = repositoryOwnerDID
        self.repositoryKey = repositoryKey
        self.ref = ref
        self.before = before
        self.after = after
        self.receivedAt = receivedAt
        self.canonicalSource = canonicalSource
        self.artifactRepository = artifactRepository
    }

    public let watchID: WebhookInboxDelivery.WatchID
    public let deliveryID: WebhookInboxDelivery.DeliveryID
    public let repositoryOwnerDID: DID
    public let repositoryKey: ATProto.Record.Key
    public let ref: String
    public let before: String
    public let after: String
    public let receivedAt: Date
    public let canonicalSource: CanonicalTangledSource
    public let artifactRepository: SourceArtifactRepository
}

/// Host-installed processing for a verified Tangled source update.
///
/// Tangled can retry a delivery when it does not receive an acknowledgement, so processors must
/// accept at-least-once invocation. Channel signals and the source checkpoint use the same durable
/// database transaction, while provider delivery continues independently from the outbox.
public struct TangledSourceUpdateProcessor: Sendable {
    public var process: @Sendable (TangledSourceUpdate) async throws -> Void

    public init(
        process: @escaping @Sendable (TangledSourceUpdate) async throws -> Void
    ) {
        self.process = process
    }

    /// Projects communication post identities from exact Tangled revisions and only announces
    /// channels that gained posts. The projection checkpoint and outbox inserts share one database
    /// transaction, making webhook retries safe.
    public static func channelNotifications(
        store: OpenMusicEventAppViewStore,
        sourceArtifacts: SourceArtifactPublisher
    ) -> Self {
        channelNotifications(
            store: store,
            sourceArtifacts: sourceArtifacts,
            load: ValidatedSourceArchive.load
        )
    }

    static func channelNotifications(
        store: OpenMusicEventAppViewStore,
        sourceArtifacts: SourceArtifactPublisher,
        load: @escaping @Sendable (TangledSourceUpdate, String) async throws
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

            let before: TangledSourceSnapshot
            if checkpoint != nil {
                before = TangledSourceSnapshot(revision: update.before, posts: [])
            } else if update.before.isZeroRevision {
                before = TangledSourceSnapshot(revision: update.before, posts: [])
            } else {
                before = try await load(update, update.before).snapshot
            }
            let after = try await load(update, update.after)
            let publishedArtifact = try await sourceArtifacts.publish(
                SourceArtifactPublicationRequest(
                    archiveData: after.data,
                    repository: update.artifactRepository,
                    revision: update.after
                )
            )
            _ = try await store.apply(
                after.snapshot,
                replacing: before,
                publishedArtifact: publishedArtifact,
                for: update
            )
        }
    }
}

struct TangledSourceSnapshot: Equatable, Sendable {
    let revision: String
    let posts: [OME.SourceDatabaseInsertion.CommunicationPost]

    static func load(
        update: TangledSourceUpdate,
        revision: String
    ) async throws -> Self {
        let repository =
            "at://\(update.repositoryOwnerDID)/sh.tangled.repo/\(update.repositoryKey.rawValue)"
        let result = try await OpenMusicEventSourceValidator(
            OpenMusicEventSourceValidationRequest(
                source: repository,
                organizerID: update.canonicalSource.organizerID,
                sourceProvenance: update.canonicalSource.provenance(ref: revision),
                ref: revision
            )
        )
        .validate()
        return Self(revision: revision, posts: result.insertion.communicationPosts)
    }
}

private extension String {
    var isZeroRevision: Bool {
        !isEmpty && allSatisfy { $0 == "0" }
    }
}
