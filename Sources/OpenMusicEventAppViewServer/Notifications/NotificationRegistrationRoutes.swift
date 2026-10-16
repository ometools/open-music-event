import ComposableNotifications
import ComposableNotificationsServer
import Foundation
import Hummingbird

extension OpenMusicEventAppViewServer {
    static func installNotificationRegistrationRoutes<Context: RequestContext>(
        on router: Router<Context>,
        registration: NotificationRegistrationServer?
    ) {
        router.put(.init(NotificationRegistrationEndpoint.destinationPath)) {
            request,
            context async throws -> Response in
            try await observeNotificationRegistration(
                operation: "replace_destination",
                context: context
            ) {
                guard let registration else {
                    throw HTTPError(.serviceUnavailable)
                }
                let installationID = try await registration
                    .installationAuthorizer
                    .authenticateInstallation(request)
                let payload = try await request.decode(
                    as: NotificationDestinationPayload.self,
                    context: context
                )
                let destination = try registration.policy.validate(payload)
                try await registration.database.replaceDestination(
                    destination,
                    for: installationID
                )
                switch destination {
                case .apns(let registration):
                    context.logger.info(
                        "Notification destination registered",
                        metadata: [
                            "notification.application.id": .string(payload.applicationID),
                            "notification.apns.environment": .string(
                                registration.environment.rawValue
                            ),
                            "notification.destination.provider": .string(payload.provider.rawValue),
                            "notification.installation.id": .string(installationID.rawValue),
                        ]
                    )
                case .fcm:
                    context.logger.info(
                        "Notification destination registered",
                        metadata: [
                            "notification.application.id": .string(payload.applicationID),
                            "notification.destination.provider": .string(payload.provider.rawValue),
                            "notification.installation.id": .string(installationID.rawValue),
                        ]
                    )
                }
                return Response(status: .noContent)
            }
        }

        router.put(.init(NotificationRegistrationEndpoint.subscriptionsPath)) {
            request,
            context async throws -> Response in
            try await observeNotificationRegistration(
                operation: "replace_subscriptions",
                context: context
            ) {
                guard let registration else {
                    throw HTTPError(.serviceUnavailable)
                }
                let installationID = try await registration
                    .installationAuthorizer
                    .authenticateInstallation(request)
                let payload = try await request.decode(
                    as: NotificationSubscriptionsPayload.self,
                    context: context
                )
                try registration.policy.validate(payload)
                try await registration.database.replaceSubscriptions(
                    payload.subscriptions,
                    for: installationID
                )
                context.logger.info(
                    "Notification subscriptions registered",
                    metadata: [
                        "notification.installation.id": .string(installationID.rawValue),
                        "notification.subscription.count": .string("\(payload.subscriptions.count)"),
                    ]
                )
                return Response(status: .noContent)
            }
        }

        router.post(.init(NotificationRegistrationEndpoint.installationsPath)) {
            _, context async throws -> Response in
            try await observeNotificationRegistration(
                operation: "create_installation",
                context: context
            ) {
                guard let registration else {
                    throw HTTPError(.serviceUnavailable)
                }
                let installation = try await registration
                    .installationAuthorizer
                    .createInstallation()
                let data = try JSONEncoder().encode(
                    NotificationInstallationCredentialPayload(
                        credential: installation.credential
                    )
                )
                context.logger.info(
                    "Notification installation created",
                    metadata: [
                        "notification.installation.id": .string(installation.id.rawValue)
                    ]
                )
                return Response(
                    status: .created,
                    headers: [
                        .cacheControl: "no-store",
                        .contentLength: "\(data.count)",
                        .contentType: "application/json",
                    ],
                    body: .init(byteBuffer: ByteBuffer(bytes: data))
                )
            }
        }
    }

    static func observeNotificationRegistration<Context: RequestContext, Value>(
        operation: String,
        context: Context,
        _ body: () async throws -> Value
    ) async throws -> Value {
        do {
            return try await body()
        } catch {
            let status = (error as? any HTTPResponseError)?.status.code ?? 500
            #if DEBUG
            let message = "Notification registration failed: \(String(describing: error))"
            #else
            let message = "Notification registration failed"
            #endif
            context.logger.log(
                level: status >= 500 ? .error : .warning,
                "\(message)",
                metadata: [
                    "error.type": .string(String(reflecting: type(of: error))),
                    "http.response.status_code": .string("\(status)"),
                    "notification.registration.operation": .string(operation),
                ]
            )
            throw error
        }
    }
}
