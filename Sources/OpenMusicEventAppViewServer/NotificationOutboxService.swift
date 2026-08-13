import ComposableNotifications
import Dependencies
import Foundation
import ServiceLifecycle

struct NotificationOutboxService: Service {
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now

    let outbox: NotificationOutbox
    var idlePollInterval: Duration = .seconds(1)

    init(
        client: NotificationOutboxClient,
        provider: NotificationProviderClient,
        idlePollInterval: Duration = .seconds(1)
    ) {
        self.outbox = NotificationOutbox(client: client, provider: provider)
        self.idlePollInterval = idlePollInterval
    }

    func run() async throws {
        do {
            try await cancelWhenGracefulShutdown {
                while true {
                    switch try await outbox.deliverNext(at: now) {
                    case .delivered, .retryScheduled:
                        continue
                    case .idle:
                        try await clock.sleep(for: idlePollInterval)
                    }
                }
            }
        } catch is CancellationError {
            // Cancellation and graceful shutdown both end this long-running service normally.
        }
    }
}
