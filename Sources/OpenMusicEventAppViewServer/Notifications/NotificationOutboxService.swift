import ComposableNotifications
import ComposableNotificationsServer
import Dependencies
import Foundation
import GRDB
import ServiceLifecycle

struct NotificationOutboxService: Service {
    let database: any DatabaseWriter
    let destinationProtection: NotificationDestinationProtection
    let legacyAPNSEnvironments: [Push.ApplicationID: Push.APNS.Environment]
    let provider: NotificationProviderClient

    init(
        database: any DatabaseWriter,
        destinationProtection: NotificationDestinationProtection,
        legacyAPNSEnvironments: [Push.ApplicationID: Push.APNS.Environment],
        provider: NotificationProviderClient
    ) {
        self.database = database
        self.destinationProtection = destinationProtection
        self.legacyAPNSEnvironments = legacyAPNSEnvironments
        self.provider = provider
    }

    func run() async throws {
        do {
            try await withDependencies {
                $0.defaultDatabase = database
                $0.notificationDestinationProtectionClient = destinationProtection.client(
                    legacyAPNSEnvironments: legacyAPNSEnvironments
                )
                $0.notificationProviderClient = provider
            } operation: {
                try await cancelWhenGracefulShutdown {
                    try await NotificationDelivery().run()
                }
            }
        } catch is CancellationError {
            return
        }
    }
}
