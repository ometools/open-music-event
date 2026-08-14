import ComposableCalendarEvents
import ComposableNotifications
import ComposableNotificationsServer
import Dependencies
import Foundation
import Hummingbird
import HydrantClient
import HydrantClientHummingbird
import OpenMusicEventLexicon
import OpenMusicEventRouting
import ServiceLifecycle
import XRPCClient
import XRPCHummingbird

public enum OpenMusicEventAppViewServer {
    public static func router(
        configuration: AppViewConfiguration = .init(),
        store: OpenMusicEventAppViewStore? = nil,
        commsPostSubmission: CommsPostSubmission? = nil,
        notificationRegistration: NotificationRegistrationServer? = nil,
        tangledSourceUpdateProcessor: TangledSourceUpdateProcessor? = nil
    ) -> Router<BasicRequestContext> {
        router(
            context: BasicRequestContext.self,
            configuration: configuration,
            store: store,
            commsPostSubmission: commsPostSubmission,
            notificationRegistration: notificationRegistration,
            tangledSourceUpdateProcessor: tangledSourceUpdateProcessor
        )
    }

    public static func router<Context: RequestContext>(
        context: Context.Type,
        configuration: AppViewConfiguration = .init(),
        store: OpenMusicEventAppViewStore? = nil,
        commsPostSubmission: CommsPostSubmission? = nil,
        notificationRegistration: NotificationRegistrationServer? = nil,
        tangledSourceUpdateProcessor: TangledSourceUpdateProcessor? = nil
    ) -> Router<Context> {
        let hummingbirdRouter = Router(context: context, options: [.autoGenerateHeadEndpoints])
        let routeResolver = OpenMusicEventRouter(
            configuration: OpenMusicEventRoutingConfiguration(
                brandedEventRouteClaims: configuration.brandedEventRouteClaims
            )
        )
        let staticSiteFiles = StaticSiteFiles(rootDirectory: configuration.siteRoot)
        let wellKnownFiles = WellKnownFiles(rootDirectory: configuration.wellKnownRoot)

        installRoutes(
            on: hummingbirdRouter,
            routeResolver: routeResolver,
            staticSiteFiles: staticSiteFiles,
            wellKnownFiles: wellKnownFiles,
            store: store,
            commsPostSubmission: commsPostSubmission,
            notificationRegistration: notificationRegistration,
            tangledWebhookConfiguration: configuration.tangledWebhook,
            tangledSourceUpdateProcessor: tangledSourceUpdateProcessor
        )

        return hummingbirdRouter
    }

    public static func application(
        configuration: AppViewConfiguration = .init(),
        store providedStore: OpenMusicEventAppViewStore? = nil,
        hydrantClient: HydrantClient? = nil,
        commsPostSubmission: CommsPostSubmission? = nil,
        notificationRegistration: NotificationRegistrationServer? = nil,
        notificationProvider: NotificationProviderClient? = nil,
        tangledSourceUpdateProcessor providedTangledSourceUpdateProcessor:
            TangledSourceUpdateProcessor? = nil
    ) throws -> some ApplicationProtocol {
        let store: OpenMusicEventAppViewStore?
        if let providedStore {
            store = providedStore
        } else if let databaseURL = configuration.databaseURL {
            store = try OpenMusicEventAppViewStore(
                databaseURL: databaseURL,
                webhookSecretProtection: configuration.webhookSecretProtection,
                initiallyReady: configuration.ingestion == nil
            )
        } else {
            store = nil
        }
        if configuration.tangledWebhook != nil, store == nil {
            throw OpenMusicEventAppViewServerError.tangledWebhookRequiresDatabase
        }

        var services: [any Service] = []
        if let ingestion = configuration.ingestion {
            guard let store else {
                throw OpenMusicEventAppViewServerError.ingestionRequiresDatabase
            }
            services.append(
                OpenMusicEventAppViewIngestion(
                    store: store,
                    configuration: ingestion,
                    client: hydrantClient ?? .hummingbird()
                )
            )
        }
        let notificationRegistration = try notificationRegistration
            ?? withNotificationDependencies(configuration: configuration, store: store) {
                try configuredNotificationRegistration(
                    configuration: configuration,
                    store: store
                )
            }
        let tangledSourceUpdateProcessor: TangledSourceUpdateProcessor?
        if let providedTangledSourceUpdateProcessor {
            tangledSourceUpdateProcessor = providedTangledSourceUpdateProcessor
        } else if configuration.tangledWebhook != nil, store != nil {
            tangledSourceUpdateProcessor = withNotificationDependencies(
                configuration: configuration,
                store: store
            ) {
                .notificationOutbox()
            }
        } else {
            tangledSourceUpdateProcessor = nil
        }
        if let notificationProvider {
            guard let store else {
                throw OpenMusicEventAppViewServerError.notificationDeliveryRequiresDatabase
            }
            guard let destinationProtection = configuration.notificationDestinationProtection else {
                throw OpenMusicEventAppViewServerError
                    .notificationDeliveryRequiresDestinationProtection
            }
            services.append(
                NotificationOutboxService(
                    database: store.database,
                    destinationProtection: destinationProtection,
                    provider: notificationProvider
                )
            )
        }
        let hummingbirdRouter = router(
            configuration: configuration,
            store: store,
            commsPostSubmission: commsPostSubmission,
            notificationRegistration: notificationRegistration,
            tangledSourceUpdateProcessor: tangledSourceUpdateProcessor
        )

        return Application(
            router: hummingbirdRouter,
            configuration: configuration.hummingbirdConfiguration,
            services: services
        )
    }

    private static func configuredNotificationRegistration(
        configuration: AppViewConfiguration,
        store: OpenMusicEventAppViewStore?
    ) throws -> NotificationRegistrationServer? {
        guard let notificationConfiguration = configuration.notificationRegistration else {
            return nil
        }
        guard store != nil else {
            throw OpenMusicEventAppViewServerError.notificationRegistrationRequiresDatabase
        }
        guard configuration.notificationDestinationProtection != nil else {
            throw OpenMusicEventAppViewServerError
                .notificationRegistrationRequiresDestinationProtection
        }
        let providerApplications = configuration.notificationProviders.map { providers in
            NotificationRegistrationPolicy.ProviderApplications(
                apns: providers.apns.map { Set($0.applications.keys) } ?? [],
                fcm: providers.fcm.map { Set($0.applications.keys) } ?? []
            )
        }

        switch notificationConfiguration.authorization {
        case .anonymous:
            let notificationDatabase = NotificationDatabase()
            return NotificationRegistrationServer(
                database: notificationDatabase,
                installationAuthorizer: .anonymous(database: notificationDatabase),
                policy: NotificationRegistrationPolicy(
                    allowedApplicationIDs: notificationConfiguration.allowedApplicationIDs,
                    providerApplications: providerApplications
                )
            )
        }
    }

    private static func withNotificationDependencies<Value>(
        configuration: AppViewConfiguration,
        store: OpenMusicEventAppViewStore?,
        operation: () throws -> Value
    ) rethrows -> Value {
        try withDependencies {
            if let store {
                $0.defaultDatabase = store.database
            }
            if let protection = configuration.notificationDestinationProtection {
                $0.notificationDestinationProtectionClient = protection.client
            }
        } operation: {
            try operation()
        }
    }

    private static func installRoutes<Context: RequestContext>(
        on hummingbirdRouter: Router<Context>,
        routeResolver: OpenMusicEventRouter,
        staticSiteFiles: StaticSiteFiles,
        wellKnownFiles: WellKnownFiles,
        store: OpenMusicEventAppViewStore?,
        commsPostSubmission: CommsPostSubmission?,
        notificationRegistration: NotificationRegistrationServer?,
        tangledWebhookConfiguration: TangledWebhookConfiguration?,
        tangledSourceUpdateProcessor: TangledSourceUpdateProcessor?
    ) {
        if let commsPostSubmission {
            hummingbirdRouter.register(
                OME.Comms.SubmitPost.self,
                authenticatingWith: commsPostSubmission.verifier
            ) { input, authentication, _ in
                guard input.uri.authority == .did(authentication.issuer) else {
                    throw XRPC.ResponseError(
                        .forbidden,
                        error: "PostAuthorityMismatch",
                        message: "The authenticated account does not own the submitted post."
                    )
                }
                guard input.uri.collection == OME.Announcement.nsid,
                      input.uri.rkey != nil
                else {
                    throw XRPC.ResponseError(
                        .badRequest,
                        error: "UnsupportedPostCollection",
                        message: "The submitted post must be an OpenMusicEvent announcement record."
                    )
                }

                return try await commsPostSubmission.submit(input, authentication)
            }
        }

        hummingbirdRouter.register(OME.CalendarEvent.GetEvent.self) { parameters, _ in
            let event: OME.CalendarEvent?
            if parameters.uri.collection == OME.Event.nsid {
                event = try BundledCalendarEventCatalog.event(uri: parameters.uri)
            } else if parameters.uri.collection == Community.CalendarEvent.nsid, let store {
                event = try store.communityCalendarEvent(uri: parameters.uri)
            } else {
                event = nil
            }

            guard let event else {
                throw XRPC.ResponseError(
                    .notFound,
                    error: "EventNotFound",
                    message: "The requested calendar event is not available."
                )
            }
            return event
        }

        hummingbirdRouter.register(OME.CalendarEvent.GetEvents.self) { parameters, _ in
            do {
                if parameters.catalog == OME.Event.nsid {
                    return try BundledCalendarEventCatalog.page(
                        cursor: parameters.cursor,
                        limit: parameters.limit
                    )
                }
                if parameters.catalog == Community.CalendarEvent.nsid, let store {
                    return try store.communityCalendarEventPage(
                        cursor: parameters.cursor,
                        limit: parameters.limit
                    )
                }
                throw XRPC.ResponseError(
                    .notFound,
                    error: "UnknownCatalog",
                    message: "The requested calendar event catalog is not available."
                )
            } catch BundledCalendarEventCatalogError.invalidCursor {
                throw XRPC.ResponseError(
                    .badRequest,
                    error: "InvalidCursor",
                    message: "The XRPC cursor is invalid."
                )
            } catch OpenMusicEventAppViewStoreError.invalidCursor {
                throw XRPC.ResponseError(
                    .badRequest,
                    error: "InvalidCursor",
                    message: "The XRPC cursor is invalid."
                )
            }
        }

        hummingbirdRouter.put(.init(NotificationRegistrationEndpoint.destinationPath)) {
            request,
            context async throws -> Response in
            try await observeNotificationRegistration(
                operation: "replace_destination",
                context: context
            ) {
                guard let notificationRegistration else {
                    throw HTTPError(.serviceUnavailable)
                }
                let installationID = try await notificationRegistration
                    .installationAuthorizer
                    .authenticateInstallation(request)
                let payload = try await request.decode(
                    as: NotificationDestinationPayload.self,
                    context: context
                )
                try notificationRegistration.policy.validate(payload)
                try await notificationRegistration.database.replaceDestination(
                    payload.destination,
                    for: installationID
                )
                context.logger.info(
                    "Notification destination registered",
                    metadata: [
                        "notification.application.id": .string(payload.applicationID),
                        "notification.destination.provider": .string(payload.provider.rawValue),
                        "notification.installation.id": .string(installationID.rawValue),
                    ]
                )
                return Response(status: .noContent)
            }
        }

        hummingbirdRouter.put(.init(NotificationRegistrationEndpoint.subscriptionsPath)) {
            request,
            context async throws -> Response in
            try await observeNotificationRegistration(
                operation: "replace_subscriptions",
                context: context
            ) {
                guard let notificationRegistration else {
                    throw HTTPError(.serviceUnavailable)
                }
                let installationID = try await notificationRegistration
                    .installationAuthorizer
                    .authenticateInstallation(request)
                let payload = try await request.decode(
                    as: NotificationSubscriptionsPayload.self,
                    context: context
                )
                try notificationRegistration.policy.validate(payload)
                try await notificationRegistration.database.replaceSubscriptions(
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

        hummingbirdRouter.post(.init(NotificationRegistrationEndpoint.installationsPath)) {
            _, context async throws -> Response in
            try await observeNotificationRegistration(
                operation: "create_installation",
                context: context
            ) {
                guard let notificationRegistration else {
                    throw HTTPError(.serviceUnavailable)
                }
                let installation = try await notificationRegistration
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

        if let tangledWebhookConfiguration {
            @Dependency(\.date.now) var now
            hummingbirdRouter.post(.init(TangledWebhookEndpoint.path)) {
                request,
                context async throws -> Response in
                guard let store else {
                    throw HTTPError(.serviceUnavailable)
                }
                let tangledWebhook = TangledWebhookServer(
                    configuration: tangledWebhookConfiguration,
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
                    if let tangledSourceUpdateProcessor {
                        try await tangledSourceUpdateProcessor.process(reception.sourceUpdate)
                        context.logger.info(
                            "Tangled source update processed",
                            metadata: [
                                "notification.source.id": .string(
                                    reception.sourceUpdate.source.id.rawValue
                                ),
                                "notification.source.version": .string(
                                    reception.sourceUpdate.source.version.rawValue
                                ),
                                "webhook.delivery.id": .string(
                                    reception.sourceUpdate.deliveryID.rawValue
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
                         .repositoryMismatch:
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

        hummingbirdRouter.get("/.well-known/{file}") { request, context async throws -> Response in
            return try response(
                host: request.authority,
                path: "/.well-known/\(context.parameters.get("file") ?? "")",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles
            )
        }

        hummingbirdRouter.get("/apple-app-site-association") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/apple-app-site-association",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles
            )
        }

        hummingbirdRouter.get("/events/{eventClaim}") { request, context async throws -> Response in
            try response(
                host: request.authority,
                path: "/events/\(context.parameters.get("eventClaim") ?? "")",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles
            )
        }

        hummingbirdRouter.get("/healthz") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/healthz",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles
            )
        }

        hummingbirdRouter.get("/readyz") { request, _ async throws -> Response in
            if let store, case .catchingUp = await store.readiness.snapshot() {
                return textResponse("catching up", status: .serviceUnavailable)
            }
            return try response(
                host: request.authority,
                path: "/readyz",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles
            )
        }

        hummingbirdRouter.get("/") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles
            )
        }

        hummingbirdRouter.get("/index.html") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/index.html",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles
            )
        }

        hummingbirdRouter.get("/styles.css") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/styles.css",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles
            )
        }

        hummingbirdRouter.get("/favicon.png") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/favicon.png",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles
            )
        }

        hummingbirdRouter.get("/apple-touch-icon.png") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/apple-touch-icon.png",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles
            )
        }

        hummingbirdRouter.get("/assets/{file}") { request, context async throws -> Response in
            try response(
                host: request.authority,
                path: "/assets/\(context.parameters.get("file") ?? "")",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles
            )
        }
    }

    private static func response(
        host: String,
        path: String,
        routeResolver: OpenMusicEventRouter,
        staticSiteFiles: StaticSiteFiles,
        wellKnownFiles: WellKnownFiles
    ) throws -> Response {
        let route = try routeResolver.route(host: host, path: path)

        return try response(
            for: route,
            host: host,
            routeResolver: routeResolver,
            staticSiteFiles: staticSiteFiles,
            wellKnownFiles: wellKnownFiles
        )
    }

    private static func response(
        for route: OpenMusicEventRoute,
        host: String,
        routeResolver: OpenMusicEventRouter,
        staticSiteFiles: StaticSiteFiles,
        wellKnownFiles: WellKnownFiles
    ) throws -> Response {
        switch route {
        case .appleAppSiteAssociation:
            guard let file = try wellKnownFiles.file(
                host: host,
                requestPath: routeResolver.path(for: route)
            ) else {
                throw HTTPError(.notFound)
            }
            return file.response

        case let .brandedEvent(claim):
            guard let event = try BundledCalendarEventCatalog.event(
                uri: OME.Event.reference(id: claim.eventID).uri
            ) else {
                return textResponse(
                    "Event \(claim.eventClaim) is temporarily unavailable.",
                    status: .serviceUnavailable
                )
            }
            return brandedEventResponse(
                event: event,
                canonicalURL: routeResolver.url(for: route)
            )

        case .health:
            return textResponse("ok")

        case .ready:
            return textResponse("ready")

        case let .site(siteRoute):
            guard let file = try staticSiteFiles.file(
                requestPath: routeResolver.path(for: .site(siteRoute))
            ) else {
                throw HTTPError(.notFound)
            }
            return file.response

        case let .wellKnown(wellKnownFile):
            let requestPath = routeResolver.path(for: .wellKnown(wellKnownFile))
            if wellKnownFile == .oauthClientMetadata {
                guard let file = try staticSiteFiles.file(requestPath: requestPath) else {
                    throw HTTPError(.notFound)
                }
                return file.response
            }

            guard let file = try wellKnownFiles.file(
                host: host,
                requestPath: requestPath
            ) else {
                throw HTTPError(.notFound)
            }
            return file.response
        }
    }

    private static func textResponse(
        _ text: String,
        status: HTTPResponse.Status = .ok
    ) -> Response {
        Response(
            status: status,
            headers: [.contentType: "text/plain; charset=utf-8"],
            body: .init(byteBuffer: .init(data: Data(text.utf8)))
        )
    }

    private static func brandedEventResponse(
        event: OME.CalendarEvent,
        canonicalURL: URL
    ) -> Response {
        let hero = event.media.first { $0.role == OME.ImageAsset.Role.hero.rawValue }
            ?? event.media.first
        let organizerName = event.organizer.displayName ?? "OpenMusicEvent"
        let heroMarkup = hero.map {
            "<img class=\"hero-mark\" src=\"\($0.url.absoluteString.htmlEscaped)\" alt=\"\(($0.alt ?? event.name).htmlEscaped)\">"
        } ?? ""
        let descriptionMarkup = event.description.map {
            "<p class=\"lede\">\($0.htmlEscaped)</p>"
        } ?? ""
        let imageMetadata = hero.map {
            "<meta property=\"og:image\" content=\"\($0.url.absoluteString.htmlEscaped)\">"
        } ?? ""
        let canonicalURLString = canonicalURL.absoluteString.htmlEscaped
        let eventName = event.name.htmlEscaped
        let html = """
            <!doctype html>
            <html lang="en">
              <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <title>\(eventName)</title>
                <link rel="canonical" href="\(canonicalURLString)">
                <meta property="og:title" content="\(eventName)">
                <meta property="og:url" content="\(canonicalURLString)">
                \(imageMetadata)
                <link rel="stylesheet" href="/styles.css">
              </head>
              <body>
                <main>
                  <section class="hero" aria-label="\(eventName)">
                    \(heroMarkup)
                    <div class="hero-copy">
                      <p class="eyebrow">\(organizerName.htmlEscaped)</p>
                      <h1>\(eventName)</h1>
                      \(descriptionMarkup)
                    </div>
                  </section>
                </main>
              </body>
            </html>
            """
        return Response(
            status: .ok,
            headers: [.contentType: "text/html; charset=utf-8"],
            body: .init(byteBuffer: .init(data: Data(html.utf8)))
        )
    }

    private static func observeNotificationRegistration<Context: RequestContext, Value>(
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

public enum OpenMusicEventAppViewServerError: Error, Equatable, Sendable {
    case ingestionRequiresDatabase
    case notificationDeliveryRequiresDatabase
    case notificationDeliveryRequiresDestinationProtection
    case notificationRegistrationRequiresDatabase
    case notificationRegistrationRequiresDestinationProtection
    case tangledWebhookRequiresDatabase
}

private extension Request {
    var authority: String {
        let value = self.head.authority ?? "localhost"
        return value.split(separator: ":").first.map(String.init) ?? "localhost"
    }
}

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

private extension OpenMusicEventRouter {
    func route(host: String, path: String) throws -> OpenMusicEventRoute {
        guard let route = route(
            OpenMusicEventIncomingRequest(
                host: OpenMusicEventHost(rawValue: host),
                path: OpenMusicEventPath(rawValue: path)
            )
        ) else {
            throw HTTPError(.notFound)
        }
        return route
    }
}
