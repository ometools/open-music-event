import ATProto
import ATProtoAppView
import ATProtoStreams
import Dependencies
import Hummingbird
import ServiceLifecycle

public struct OpenMusicEventAppViewIngestion: Service {
    public init(
        store: OpenMusicEventAppViewStore,
        configurations: [AppViewIngestionConfiguration],
        tangledWebhookConfiguration: TangledWebhookConfiguration? = nil,
        client: HydrantClient = .hummingbird()
    ) {
        self.store = store
        self.configurations = configurations
        self.tangledWebhookConfiguration = tangledWebhookConfiguration
        self.client = client
    }

    public init(
        store: OpenMusicEventAppViewStore,
        configuration: AppViewIngestionConfiguration,
        tangledWebhookConfiguration: TangledWebhookConfiguration? = nil,
        client: HydrantClient = .hummingbird()
    ) {
        self.init(
            store: store,
            configurations: [configuration],
            tangledWebhookConfiguration: tangledWebhookConfiguration,
            client: client
        )
    }

    public var store: OpenMusicEventAppViewStore
    public var configurations: [AppViewIngestionConfiguration]
    public var tangledWebhookConfiguration: TangledWebhookConfiguration?
    public var client: HydrantClient

    public func run() async throws {
        await store.readiness.configure(
            subscriptionIDs: Set(configurations.map(\.subscriptionID))
        )
        let repositoryDIDs = tangledWebhookConfiguration?.repositoryDIDs ?? []
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, configuration) in configurations.enumerated() {
                group.addTask {
                    try await run(
                        configuration: configuration,
                        ingestWorkspacePulls: index == 0 && !repositoryDIDs.isEmpty,
                        repositoryDIDs: repositoryDIDs
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    func run(
        configuration: AppViewIngestionConfiguration,
        ingestWorkspacePulls: Bool,
        repositoryDIDs: Set<DID>
    ) async throws {
        let hydrantConfiguration = HydrantClient.Configuration(
            endpoint: configuration.endpoint
        )
        try await withDependencies {
            $0.defaultDatabase = store.database
        } operation: {
            if ingestWorkspacePulls {
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
                    subscriptionID: "\(configuration.subscriptionID)|event-graph-v3",
                    client: client,
                    caughtUpBehavior: .continueStreaming,
                    caughtUp: { marker in
                        await store.readiness.markReady(
                            subscriptionID: configuration.subscriptionID,
                            cursor: marker.cursor
                        )
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
