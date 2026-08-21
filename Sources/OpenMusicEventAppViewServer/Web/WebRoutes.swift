import Foundation
import Hummingbird
import OpenMusicEventLexicon
import OpenMusicEventRouting

extension OpenMusicEventAppViewServer {
    static func installWebRoutes<Context: RequestContext>(
        on router: Router<Context>,
        routeResolver: OpenMusicEventRouter,
        staticSiteFiles: StaticSiteFiles,
        wellKnownFiles: WellKnownFiles,
        openMusicEventCatalog: OpenMusicEventCalendarCatalog,
        store: OpenMusicEventAppViewStore?
    ) {
        router.get("/.well-known/{file}") { request, context async throws -> Response in
            return try response(
                host: request.authority,
                path: "/.well-known/\(context.parameters.get("file") ?? "")",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                openMusicEventCatalog: openMusicEventCatalog
            )
        }

        router.get("/apple-app-site-association") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/apple-app-site-association",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                openMusicEventCatalog: openMusicEventCatalog
            )
        }

        router.get("/events/{eventClaim}") { request, context async throws -> Response in
            try response(
                host: request.authority,
                path: "/events/\(context.parameters.get("eventClaim") ?? "")",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                openMusicEventCatalog: openMusicEventCatalog
            )
        }

        router.get("/healthz") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/healthz",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                openMusicEventCatalog: openMusicEventCatalog
            )
        }

        router.get("/readyz") { request, _ async throws -> Response in
            if let store, case .catchingUp = await store.readiness.snapshot() {
                return textResponse("catching up", status: .serviceUnavailable)
            }
            return try response(
                host: request.authority,
                path: "/readyz",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                openMusicEventCatalog: openMusicEventCatalog
            )
        }

        router.get("/") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                openMusicEventCatalog: openMusicEventCatalog
            )
        }

        router.get("/index.html") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/index.html",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                openMusicEventCatalog: openMusicEventCatalog
            )
        }

        router.get("/styles.css") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/styles.css",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                openMusicEventCatalog: openMusicEventCatalog
            )
        }

        router.get("/favicon.png") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/favicon.png",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                openMusicEventCatalog: openMusicEventCatalog
            )
        }

        router.get("/apple-touch-icon.png") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/apple-touch-icon.png",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                openMusicEventCatalog: openMusicEventCatalog
            )
        }

        router.get("/assets/{file}") { request, context async throws -> Response in
            try response(
                host: request.authority,
                path: "/assets/\(context.parameters.get("file") ?? "")",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                openMusicEventCatalog: openMusicEventCatalog
            )
        }
    }

    static func response(
        host: String,
        path: String,
        routeResolver: OpenMusicEventRouter,
        staticSiteFiles: StaticSiteFiles,
        wellKnownFiles: WellKnownFiles,
        openMusicEventCatalog: OpenMusicEventCalendarCatalog
    ) throws -> Response {
        let route = try routeResolver.route(host: host, path: path)
        return try response(
            for: route,
            host: host,
            routeResolver: routeResolver,
            staticSiteFiles: staticSiteFiles,
            wellKnownFiles: wellKnownFiles,
            openMusicEventCatalog: openMusicEventCatalog
        )
    }

    static func response(
        for route: OpenMusicEventRoute,
        host: String,
        routeResolver: OpenMusicEventRouter,
        staticSiteFiles: StaticSiteFiles,
        wellKnownFiles: WellKnownFiles,
        openMusicEventCatalog: OpenMusicEventCalendarCatalog
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
            guard let event = try openMusicEventCatalog.event(
                uri: OME.Event.reference(id: claim.eventID).uri
            ) else {
                return textResponse(
                    "Event \(claim.eventClaim) is temporarily unavailable.",
                    status: .serviceUnavailable
                )
            }
            return BrandedEventPage.response(
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

    static func textResponse(
        _ text: String,
        status: HTTPResponse.Status = .ok
    ) -> Response {
        Response(
            status: status,
            headers: [.contentType: "text/plain; charset=utf-8"],
            body: .init(byteBuffer: .init(data: Data(text.utf8)))
        )
    }
}

private extension Request {
    var authority: String {
        let value = self.head.authority ?? "localhost"
        return value.split(separator: ":").first.map(String.init) ?? "localhost"
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
