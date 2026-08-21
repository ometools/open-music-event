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
    case tangledWebhookConfigurationUnavailable
    case sourceArtifactConfigurationUnavailable
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
            artifactPublisher: .s3(configuration: sourceArtifactConfiguration),
            downloadAndValidate: ValidatedSourceArchive.downloadAndValidate
        )
    }

    internal static func backfillSourceArtifacts(
        watches: [TangledWebhookWatch],
        store: OpenMusicEventAppViewStore,
        artifactPublisher: SourceArtifactPublisher,
        downloadAndValidate: @escaping @Sendable (TangledSourceUpdate, String) async throws
            -> ValidatedSourceArchive
    ) async throws -> [SourceArtifactBackfillResult] {
        @Dependency(\.date.now) var now
        @Dependency(\.uuid) var uuid
        let processor = TangledSourceUpdateProcessor.publishSourceAndNotifyChannels(
            store: store,
            artifactPublisher: artifactPublisher,
            downloadAndValidate: downloadAndValidate
        )

        var results: [SourceArtifactBackfillResult] = []
        for watch in watches {
            guard let checkpoint = try await store.tangledSourceCheckpoint(watchID: watch.id) else {
                throw SourceArtifactBackfillError.tangledSourceCheckpointMissing(
                    watch.id.rawValue
                )
            }
            let sameRevisionUpdate = TangledSourceUpdate(
                watchID: watch.id,
                deliveryID: .init(rawValue: uuid().uuidString.lowercased()),
                repositoryOwnerDID: watch.repositoryOwnerDID,
                ref: watch.ref,
                before: checkpoint.revision,
                after: checkpoint.revision,
                receivedAt: now,
                canonicalSource: watch.canonicalSource,
                repository: watch.repository
            )
            try checkpoint.validateWatch(for: sameRevisionUpdate)
            try await processor.process(sameRevisionUpdate)

            let repairedCheckpoint = try await store.tangledSourceCheckpoint(watchID: watch.id)
            guard let publishedArtifact = repairedCheckpoint?.publishedArtifact
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
