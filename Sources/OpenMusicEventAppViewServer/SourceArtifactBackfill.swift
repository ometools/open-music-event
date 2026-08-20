import Dependencies
import Foundation

public struct SourceArtifactBackfillResult: Equatable, Sendable {
    public init(
        watchID: String,
        revision: String,
        reference: String,
        objectKey: String,
        checksumSHA256: String
    ) {
        self.watchID = watchID
        self.revision = revision
        self.reference = reference
        self.objectKey = objectKey
        self.checksumSHA256 = checksumSHA256
    }

    public let watchID: String
    public let revision: String
    public let reference: String
    public let objectKey: String
    public let checksumSHA256: String
}

public enum SourceArtifactBackfillError: Error, Equatable, Sendable {
    case databaseUnavailable
    case sourceArtifactConfigurationUnavailable
    case tangledWebhookConfigurationUnavailable
    case tangledSourceCheckpointMissing(String)
    case tangledSourcePublishedArtifactMissing(String)
}

public extension OpenMusicEventAppViewServer {
    static func backfillSourceArtifacts(
        configuration: AppViewConfiguration
    ) async throws -> [SourceArtifactBackfillResult] {
        guard let databaseURL = configuration.databaseURL else {
            throw SourceArtifactBackfillError.databaseUnavailable
        }
        guard let tangledWebhook = configuration.tangledWebhook else {
            throw SourceArtifactBackfillError.tangledWebhookConfigurationUnavailable
        }
        guard let sourceArtifactConfiguration = configuration.sourceArtifacts else {
            throw SourceArtifactBackfillError.sourceArtifactConfigurationUnavailable
        }
        let store = try OpenMusicEventAppViewStore(
            databaseURL: databaseURL,
            webhookSecretProtection: configuration.webhookSecretProtection,
            initiallyReady: configuration.ingestion == nil
        )
        return try await backfillSourceArtifacts(
            watches: tangledWebhook.watches,
            store: store,
            sourceArtifacts: .s3(configuration: sourceArtifactConfiguration),
            load: ValidatedSourceArchive.load
        )
    }

    internal static func backfillSourceArtifacts(
        watches: [TangledWebhookWatch],
        store: OpenMusicEventAppViewStore,
        sourceArtifacts: SourceArtifactPublisher,
        load: @escaping @Sendable (TangledSourceUpdate, String) async throws
            -> ValidatedSourceArchive
    ) async throws -> [SourceArtifactBackfillResult] {
        @Dependency(\.date.now) var now
        @Dependency(\.uuid) var uuid
        let processor = TangledSourceUpdateProcessor.channelNotifications(
            store: store,
            sourceArtifacts: sourceArtifacts,
            load: load
        )

        var results: [SourceArtifactBackfillResult] = []
        for watch in watches {
            guard let checkpoint = try await store.tangledSourceCheckpoint(watchID: watch.id) else {
                throw SourceArtifactBackfillError.tangledSourceCheckpointMissing(
                    watch.id.rawValue
                )
            }
            let update = TangledSourceUpdate(
                watchID: watch.id,
                deliveryID: .init(rawValue: uuid().uuidString.lowercased()),
                repositoryOwnerDID: watch.repositoryOwnerDID,
                repositoryKey: watch.repositoryKey,
                ref: watch.ref,
                before: checkpoint.revision,
                after: checkpoint.revision,
                receivedAt: now,
                canonicalSource: watch.canonicalSource,
                artifactRepository: watch.artifactRepository
            )
            try checkpoint.validateWatch(for: update)
            try await processor.process(update)
            guard let publishedArtifact = try await store
                .tangledSourceCheckpoint(watchID: watch.id)?
                .publishedArtifact
            else {
                throw SourceArtifactBackfillError.tangledSourcePublishedArtifactMissing(
                    watch.id.rawValue
                )
            }
            results.append(
                SourceArtifactBackfillResult(
                    watchID: watch.id.rawValue,
                    revision: publishedArtifact.revision,
                    reference: publishedArtifact.reference,
                    objectKey: publishedArtifact.objectKey,
                    checksumSHA256: publishedArtifact.checksumSHA256
                )
            )
        }
        return results
    }
}
