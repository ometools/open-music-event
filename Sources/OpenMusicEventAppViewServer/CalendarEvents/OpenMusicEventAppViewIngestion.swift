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
        client: HydrantClient = .hummingbird()
    ) {
        self.store = store
        self.configuration = configuration
        self.client = client
    }

    public var store: OpenMusicEventAppViewStore
    public var configuration: AppViewIngestionConfiguration
    public var client: HydrantClient

    public func run() async throws {
        await store.readiness.markCatchingUp()
        let readiness = store.readiness
        let provider = AppView.RecordProvider.hydrant(
            configuration: HydrantClient.Configuration(
                endpoint: configuration.endpoint
            ),
            subscriptionID: configuration.subscriptionID,
            client: client,
            caughtUp: { marker in
                await readiness.markReady(cursor: marker.cursor)
            }
        )

        try await withDependencies {
            $0.defaultDatabase = store.database
        } operation: {
            try await AppViewIngest(
                provider: provider,
                indexer: store.communityCalendarEventIndexer
            )
            .run()
        }
    }
}
