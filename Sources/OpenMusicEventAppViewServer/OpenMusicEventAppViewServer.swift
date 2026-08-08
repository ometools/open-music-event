import ComposableCalendarEvents
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
        store: OpenMusicEventAppViewStore? = nil
    ) -> Router<BasicRequestContext> {
        router(
            context: BasicRequestContext.self,
            configuration: configuration,
            store: store
        )
    }

    public static func router<Context: RequestContext>(
        context: Context.Type,
        configuration: AppViewConfiguration = .init(),
        store: OpenMusicEventAppViewStore? = nil
    ) -> Router<Context> {
        let hummingbirdRouter = Router(context: context, options: [.autoGenerateHeadEndpoints])
        let routeResolver = OpenMusicEventRouter()
        let staticSiteFiles = StaticSiteFiles(rootDirectory: configuration.siteRoot)
        let wellKnownFiles = WellKnownFiles(rootDirectory: configuration.wellKnownRoot)

        installRoutes(
            on: hummingbirdRouter,
            routeResolver: routeResolver,
            staticSiteFiles: staticSiteFiles,
            wellKnownFiles: wellKnownFiles,
            store: store
        )

        return hummingbirdRouter
    }

    public static func application(
        configuration: AppViewConfiguration = .init(),
        store providedStore: OpenMusicEventAppViewStore? = nil,
        hydrantClient: HydrantClient? = nil
    ) throws -> some ApplicationProtocol {
        let store: OpenMusicEventAppViewStore?
        if let providedStore {
            store = providedStore
        } else if let databaseURL = configuration.databaseURL {
            store = try OpenMusicEventAppViewStore(
                databaseURL: databaseURL,
                initiallyReady: configuration.ingestion == nil
            )
        } else {
            store = nil
        }

        let services: [any Service]
        if let ingestion = configuration.ingestion {
            guard let store else {
                throw OpenMusicEventAppViewServerError.ingestionRequiresDatabase
            }
            services = [
                OpenMusicEventAppViewIngestion(
                    store: store,
                    configuration: ingestion,
                    client: hydrantClient ?? .hummingbird()
                )
            ]
        } else {
            services = []
        }
        let hummingbirdRouter = router(
            configuration: configuration,
            store: store
        )

        return Application(
            router: hummingbirdRouter,
            configuration: configuration.hummingbirdConfiguration,
            services: services
        )
    }

    private static func installRoutes<Context: RequestContext>(
        on hummingbirdRouter: Router<Context>,
        routeResolver: OpenMusicEventRouter,
        staticSiteFiles: StaticSiteFiles,
        wellKnownFiles: WellKnownFiles,
        store: OpenMusicEventAppViewStore?
    ) {
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
}

public enum OpenMusicEventAppViewServerError: Error, Equatable, Sendable {
    case ingestionRequiresDatabase
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
