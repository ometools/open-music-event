import AppViewHydrant
import AppViewIndex
import Dependencies
import Hummingbird
import HydrantClient
import HydrantClientHummingbird
import ServiceLifecycle

public struct OpenMusicEventAppViewIngestion: Service {
    public init(
        store: OpenMusicEventAppViewStore,
        configuration: AppViewIngestionConfiguration,
        tangledWebhookConfiguration: TangledWebhookConfiguration? = nil,
        client: HydrantClient = .hummingbird()
    ) {
        self.store = store
        self.configuration = configuration
        self.tangledWebhookConfiguration = tangledWebhookConfiguration
        self.client = client
    }

    public var store: OpenMusicEventAppViewStore
    public var configuration: AppViewIngestionConfiguration
    public var tangledWebhookConfiguration: TangledWebhookConfiguration?
    public var client: HydrantClient

    public func run() async throws {
        await store.readiness.markCatchingUp()
        let readiness = store.readiness
        let repositoryDIDs = tangledWebhookConfiguration?.repositoryDIDs ?? []
        let hydrantConfiguration = HydrantClient.Configuration(
            endpoint: configuration.endpoint
        )

        try await withDependencies {
            $0.defaultDatabase = store.database
        } operation: {
            if !repositoryDIDs.isEmpty {
                try await AppViewIngest(
                    provider: .hydrant(
                        configuration: hydrantConfiguration,
                        subscriptionID: "\(configuration.subscriptionID)|workspace-pulls",
                        client: client,
                        caughtUpBehavior: .finish
                    ),
                    indexer: AppViewRecordIndexer {
                        store.tangledWorkspaceProposalRecordIndex(
                            repositoryDIDs: repositoryDIDs
                        )
                    }
                )
                .run()
            }

            try await AppViewIngest(
                provider: .hydrant(
                    configuration: hydrantConfiguration,
                    subscriptionID: configuration.subscriptionID,
                    client: client,
                    caughtUpBehavior: .continueStreaming,
                    caughtUp: { marker in
                        await readiness.markReady(cursor: marker.cursor)
                    }
                ),
                indexer: store.appViewRecordIndexer(
                    tangledWebhookConfiguration: tangledWebhookConfiguration
                )
            )
            .run()
        }
    }
}
