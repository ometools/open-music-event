import ATProto
import ComposableNotifications
import ComposableNotificationsServer
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource

/// One verified Tangled repository revision that may advance an application source.
///
/// This value is the boundary between Tangled webhook intake and source projection. The AppView
/// processor checks out the exact revisions, validates the configured event, and advances its
/// durable communication-post projection before announcing changed channels.
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
/// accept at-least-once invocation. Channel signals and the source checkpoint use the same durable
/// database transaction, while provider delivery continues independently from the outbox.
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

    /// Projects communication post identities from exact Tangled revisions and only announces
    /// channels that gained posts. The projection checkpoint and outbox inserts share one database
    /// transaction, making webhook retries safe.
    public static func channelNotifications(
        store: OpenMusicEventAppViewStore
    ) -> Self {
        channelNotifications(store: store, load: TangledSourceSnapshot.load)
    }

    static func channelNotifications(
        store: OpenMusicEventAppViewStore,
        load: @escaping @Sendable (TangledSourceUpdate, String) async throws
            -> TangledSourceSnapshot
    ) -> Self {
        Self { update in
            let checkpoint = try await store.tangledSourceCheckpoint(watchID: update.watchID)
            if let checkpoint {
                try checkpoint.validateWatch(for: update)
                if checkpoint.revision == update.after {
                    return
                }
                guard checkpoint.revision == update.before else {
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
                before = try await load(update, update.before)
            }
            let after = try await load(update, update.after)
            _ = try await store.apply(after, replacing: before, for: update)
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
        guard let organizerID = OME.Organizer.ID(update.repositoryDID.description) else {
            throw TangledSourceProjectionError.invalidOrganizer(update.repositoryDID.description)
        }
        let repository = "at://\(update.repositoryDID)/sh.tangled.repo/\(update.repositoryKey.rawValue)"
        let result = try await OpenMusicEventSourceValidator(
            OpenMusicEventSourceValidationRequest(
                source: repository,
                organizerID: organizerID,
                ref: revision
            )
        )
        .validate()
        guard let eventID = result.insertedEventIDs.first(where: {
            OME.Event.reference(id: $0).uri.description == update.source.id.rawValue
        }) else {
            throw TangledSourceProjectionError.eventNotFound(
                sourceID: update.source.id.rawValue,
                revision: revision
            )
        }
        let posts: [OME.SourceDatabaseInsertion.CommunicationPost] =
            result.insertion.communicationPosts.filter {
                $0.id.organizerID == eventID.organizerID
                    && $0.id.eventID == eventID.eventID
            }
        return Self(revision: revision, posts: posts)
    }
}

enum TangledSourceProjectionError: Error, Equatable, Sendable {
    case eventNotFound(sourceID: String, revision: String)
    case invalidOrganizer(String)
}

private extension String {
    var isZeroRevision: Bool {
        !isEmpty && allSatisfy { $0 == "0" }
    }
}
