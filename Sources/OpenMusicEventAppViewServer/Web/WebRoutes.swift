import ATProto
import Dependencies
import OpenMusicEventOAuthClient
import Foundation
import Hummingbird
import OpenMusicEventLexicon
import OpenMusicEventRouting

extension OpenMusicEventAppViewServer {
    static func installWebRoutes<Context: RequestContext>(
        on router: Router<Context>,
        oauthClient: OpenMusicEventOAuthClient,
        routeResolver: OpenMusicEventRouter,
        staticSiteFiles: StaticSiteFiles,
        wellKnownFiles: WellKnownFiles,
        store: OpenMusicEventAppViewStore?,
        webPDSHosts: [String: ATProto.PDSHost] = [:]
    ) {
        router.get(RouterPath(oauthClient.metadataURL.path)) { request, _ async throws -> Response in
            let data: Data
            if oauthClient == .privateAuthentication {
                guard request.authority == oauthClient.metadataURL.host else {
                    throw HTTPError(.notFound)
                }
                data = try oauthClient.privateMetadataData()
            } else {
                guard let file = try staticSiteFiles.file(requestPath: oauthClient.metadataURL.path) else {
                    throw HTTPError(.notFound)
                }
                data = try oauthClient.metadataData(from: file.data)
            }
            return Response(status: .ok, headers: [.contentType: "application/json", .cacheControl: "no-store"],
                            body: .init(byteBuffer: .init(data: data)))
        }

        router.get("/.well-known/{file}") { request, context async throws -> Response in
            return try response(
                host: request.authority,
                path: "/.well-known/\(context.parameters.get("file") ?? "")",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                store: store
            )
        }

        router.get("/apple-app-site-association") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/apple-app-site-association",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                store: store
            )
        }

        router.get("/events/{eventClaim}") { request, context async throws -> Response in
            let route = try routeResolver.route(host: request.authority,
                path: "/events/\(context.parameters.get("eventClaim") ?? "")")
            guard case .brandedEvent(let claim) = route else { throw HTTPError(.notFound) }
            if let store, case .catchingUp = await store.readiness.snapshot() {
                return textResponse("Event index is catching up.", status: .serviceUnavailable)
            }
            return try viewerResponse(claim: claim, canonicalURL: routeResolver.url(for: route),
                query: request.uri.query, store: store)
        }
        router.get("/event-media") { request, _ async throws -> Response in
            let selection = try EventViewerSelection(query: request.uri.query)
            guard let recordText = selection.values["record"], let record = ATProto.URI(recordText),
                  let cid = selection.values["cid"], try store?.containsWebBlob(record: record, cid: cid) == true
            else { throw HTTPError(.notFound) }
            @Dependency(ATProto.Repository.PDSHostResolver.self) var hosts
            let host: ATProto.PDSHost
            if let configured = webPDSHosts[record.authority.description] { host = configured }
            else { host = try await hosts.pdsHost(forRecordURI: record) }
            let url = "https://\(host.rawValue)/xrpc/com.atproto.sync.getBlob" + webQuery(["did": record.authority.description, "cid": cid])
            return Response(status: .temporaryRedirect, headers: [.location: url])
        }

        router.get("/healthz") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/healthz",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                store: store
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
                store: store
            )
        }

        router.get("/") { request, _ async throws -> Response in
            if oauthClient == .privateAuthentication {
                guard request.authority == oauthClient.homepageURL.host else { throw HTTPError(.notFound) }
                return textResponse("OME Private Authentication Tests")
            }
            return try response(
                host: request.authority,
                path: "/",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                store: store
            )
        }

        router.get("/index.html") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/index.html",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                store: store
            )
        }

        router.get("/styles.css") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/styles.css",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                store: store
            )
        }

        router.get("/favicon.png") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/favicon.png",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                store: store
            )
        }

        router.get("/apple-touch-icon.png") { request, _ async throws -> Response in
            try response(
                host: request.authority,
                path: "/apple-touch-icon.png",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                store: store
            )
        }

        router.get("/assets/{file}") { request, context async throws -> Response in
            try response(
                host: request.authority,
                path: "/assets/\(context.parameters.get("file") ?? "")",
                routeResolver: routeResolver,
                staticSiteFiles: staticSiteFiles,
                wellKnownFiles: wellKnownFiles,
                store: store
            )
        }
    }

    static func response(
        host: String,
        path: String,
        routeResolver: OpenMusicEventRouter,
        staticSiteFiles: StaticSiteFiles,
        wellKnownFiles: WellKnownFiles,
        store: OpenMusicEventAppViewStore?
    ) throws -> Response {
        let route = try routeResolver.route(host: host, path: path)
        return try response(
            for: route,
            host: host,
            routeResolver: routeResolver,
            staticSiteFiles: staticSiteFiles,
            wellKnownFiles: wellKnownFiles,
            store: store
        )
    }

    static func response(
        for route: OpenMusicEventRoute,
        host: String,
        routeResolver: OpenMusicEventRouter,
        staticSiteFiles: StaticSiteFiles,
        wellKnownFiles: WellKnownFiles,
        store: OpenMusicEventAppViewStore?
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
            return try viewerResponse(claim: claim, canonicalURL: routeResolver.url(for: route), query: nil, store: store)

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
