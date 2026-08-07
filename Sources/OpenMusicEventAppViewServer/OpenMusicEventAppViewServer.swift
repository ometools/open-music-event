import Foundation
import Hummingbird
import OpenMusicEventLexicon
import OpenMusicEventRouting
import XRPCClient
import XRPCHummingbird

public enum OpenMusicEventAppViewServer {
    public static func router(configuration: AppViewConfiguration = .init()) -> Router<BasicRequestContext> {
        router(context: BasicRequestContext.self, configuration: configuration)
    }

    public static func router<Context: RequestContext>(
        context: Context.Type,
        configuration: AppViewConfiguration = .init()
    ) -> Router<Context> {
        let hummingbirdRouter = Router(context: context, options: [.autoGenerateHeadEndpoints])
        let routeResolver = OpenMusicEventRouter()
        let staticSiteFiles = StaticSiteFiles(rootDirectory: configuration.siteRoot)
        let wellKnownFiles = WellKnownFiles(rootDirectory: configuration.wellKnownRoot)

        installRoutes(
            on: hummingbirdRouter,
            routeResolver: routeResolver,
            staticSiteFiles: staticSiteFiles,
            wellKnownFiles: wellKnownFiles
        )

        return hummingbirdRouter
    }

    public static func application(configuration: AppViewConfiguration = .init()) throws -> some ApplicationProtocol {
        let hummingbirdRouter = router(configuration: configuration)

        return Application(
            router: hummingbirdRouter,
            configuration: configuration.hummingbirdConfiguration
        )
    }

    private static func installRoutes<Context: RequestContext>(
        on hummingbirdRouter: Router<Context>,
        routeResolver: OpenMusicEventRouter,
        staticSiteFiles: StaticSiteFiles,
        wellKnownFiles: WellKnownFiles
    ) {
        hummingbirdRouter.register(OME.CalendarEvent.GetEvents.self) { parameters, _ in
            guard parameters.catalog == OME.Event.nsid else {
                throw XRPC.ResponseError(
                    .notFound,
                    error: "UnknownCatalog",
                    message: "The requested calendar event catalog is not available."
                )
            }

            do {
                return try BundledCalendarEventCatalog.page(
                    cursor: parameters.cursor,
                    limit: parameters.limit
                )
            } catch BundledCalendarEventCatalogError.invalidCursor {
                throw XRPC.ResponseError(
                    .badRequest,
                    error: "InvalidCursor",
                    message: "The XRPC cursor is invalid."
                )
            }
        }

        hummingbirdRouter.get("/.well-known/{file}") { request, context async throws -> Response in
            try response(
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
            try response(
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

    private static func textResponse(_ text: String) -> Response {
        Response(
            status: .ok,
            headers: [.contentType: "text/plain; charset=utf-8"],
            body: .init(byteBuffer: .init(data: Data(text.utf8)))
        )
    }
}

private extension Request {
    var authority: String {
        self.head.authority?.split(separator: ":").first.map(String.init) ?? "localhost"
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
