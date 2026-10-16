import Dependencies
import Foundation
import Hummingbird

public enum TangledWebhookEndpoint {
    public static let path = "/webhooks/tangled"
}

extension OpenMusicEventAppViewServer {
    static func installTangledWebhookRoute<Context: RequestContext>(
        on router: Router<Context>,
        configuration: TangledWebhookConfiguration?,
        store: OpenMusicEventAppViewStore?,
        sourceUpdateProcessor: TangledSourceUpdateProcessor?
    ) {
        guard let configuration else { return }

        @Dependency(\.date.now) var now
        router.post(.init(TangledWebhookEndpoint.path)) {
            request,
            context async throws -> Response in
            guard let store else {
                throw HTTPError(.serviceUnavailable)
            }
            let tangledWebhook = TangledWebhookServer(
                configuration: configuration,
                inbox: store,
                secret: { watchID in
                    try await store.webhookSecret(source: .tangled, watchID: watchID)
                }
            )
            let buffer = try await request.body.collect(upTo: 1_048_576)
            let webhookRequest = TangledWebhookRequest(
                event: request.headers[.init("X-Tangled-Event")!],
                hookID: request.headers[.init("X-Tangled-Hook-ID")!],
                deliveryID: request.headers[.init("X-Tangled-Delivery")!],
                repository: request.headers[.init("X-Tangled-Repo")!],
                signature: request.headers[.init("X-Tangled-Signature-256")!],
                payload: Data(buffer.readableBytesView)
            )

            do {
                let reception = try await tangledWebhook.receive(
                    webhookRequest,
                    receivedAt: now
                )
                if case let .sourceUpdate(sourceUpdate) = reception.event,
                   let sourceUpdateProcessor
                {
                    try await sourceUpdateProcessor.process(sourceUpdate)
                    context.logger.info(
                        "Tangled source update processed",
                        metadata: [
                            "notification.source.reference": .string(
                                sourceUpdate.canonicalSource.reference
                            ),
                            "notification.source.revision": .string(
                                sourceUpdate.after
                            ),
                            "tangled.repository": .string(
                                "\(sourceUpdate.repositoryOwnerDID)/"
                                    + sourceUpdate.repositoryKey.rawValue
                            ),
                            "webhook.delivery.id": .string(
                                sourceUpdate.deliveryID.rawValue
                            ),
                        ]
                    )
                }
                return Response(status: .accepted)
            } catch let error as TangledWebhookReceiveError {
                switch error {
                case .authenticationFailed:
                    throw HTTPError(.unauthorized)
                case .secretUnavailable:
                    throw HTTPError(.serviceUnavailable)
                case .unsupportedEvent,
                     .invalidDeliveryID,
                     .invalidPayload,
                     .refMismatch,
                     .repositoryMismatch,
                     .pullRequestMismatch:
                    throw HTTPError(.badRequest)
                }
            } catch let error as WebhookInboxError {
                switch error {
                case .deliveryConflict:
                    throw HTTPError(.conflict)
                }
            }
        }
    }
}
