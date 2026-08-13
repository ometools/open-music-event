import ComposableNotifications
import ComposableNotificationsServer
import ComposableArchitecture2
import Dependencies
import Foundation
import GRDB
import ServiceLifecycle

struct NotificationOutboxService: Service {
    @Dependency(\.continuousClock) var clock

    let database: any DatabaseWriter
    let destinationProtection: NotificationDestinationProtection
    let provider: NotificationProviderClient

    init(
        database: any DatabaseWriter,
        destinationProtection: NotificationDestinationProtection,
        provider: NotificationProviderClient
    ) {
        self.database = database
        self.destinationProtection = destinationProtection
        self.provider = provider
    }

    func run() async throws {
        #if os(Linux)
        try await runDeliveryFeature()
        #else
        if #available(macOS 26, *) {
            try await runDeliveryFeature()
        } else {
            throw NotificationOutboxServiceError.storeActorRequiresMacOS26
        }
        #endif
    }

    @available(macOS 26, *)
    private func runDeliveryFeature() async throws {
        do {
            let deliveryStore = await withDependencies {
                $0.defaultDatabase = database
                $0.notificationDestinationProtectionClient = destinationProtection.client
                $0.notificationProviderClient = provider
            } operation: {
                await StoreActor(initialState: NotificationDelivery.State()) {
                    NotificationDelivery()
                }
            }
            try await cancelWhenGracefulShutdown {
                while true { try await clock.sleep(for: .seconds(86_400)) }
            }
            _ = deliveryStore
        } catch is CancellationError {
            // Cancellation and graceful shutdown both end this long-running service normally.
        }
    }
}

private enum NotificationOutboxServiceError: Error {
    case storeActorRequiresMacOS26
}
