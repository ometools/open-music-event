import ATProto
import ATProtoHTTP
import Foundation
import Hummingbird
import HTTPTypes
import OpenMusicEventLexicon

extension OpenMusicEventAppViewServer {
    static func installCalendarMapRoutes<Context: RequestContext>(on router: Router<Context>, store: OpenMusicEventAppViewStore?) {
        router.register(CalendarBrowseQuery.self) { parameters, _ in
            guard let store else { throw XRPC.ResponseError(.serviceUnavailable, error: "EventIndexUnavailable") }
            do { return try store.browseEventSummaries(parameters) }
            catch is CalendarBrowseError { throw XRPC.ResponseError(.badRequest, error: "InvalidParameters") }
            catch is CalendarEventBrowseProjectionError { throw XRPC.ResponseError(.badRequest, error: "UnknownCatalog") }
            catch is OME.CalendarEvent.BrowseEvents.ParameterError { throw XRPC.ResponseError(.badRequest, error: "InvalidBounds") }
            catch OpenMusicEventAppViewStoreError.invalidCursor { throw XRPC.ResponseError(.badRequest, error: "InvalidCursor") }
        }
        router.register(CalendarSearchMapQuery.self) { parameters, _ in
            guard let store else { throw XRPC.ResponseError(.serviceUnavailable, error: "EventIndexUnavailable") }
            do { return try store.searchMapItems(parameters) }
            catch is CalendarBrowseError { throw XRPC.ResponseError(.badRequest, error: "InvalidParameters") }
        }
        router.get("/map/events/{z}/{x}/{tile}") { request, context async throws -> Response in
            guard let store else { throw HTTPError(.serviceUnavailable) }
            guard let z = context.parameters.get("z").flatMap(Int.init),
                  let x = context.parameters.get("x").flatMap(Int.init),
                  let filename = context.parameters.get("tile"), filename.hasSuffix(".mvt"),
                  let y = Int(filename.dropLast(4)) else { throw HTTPError(.badRequest) }
            let query = request.uri.query.map { String($0) } ?? ""
            let items = URLComponents(string: "http://localhost/?" + query)?.queryItems ?? []
            let catalogValues = items.filter { $0.name == "catalogs" }
            let catalogs = catalogValues.compactMap { $0.value.flatMap { ATProto.NSID($0) } }
            guard catalogValues.count == catalogs.count else { throw HTTPError(.badRequest) }
            let tileRequest: CalendarMapTileRequest
            do {
                tileRequest = try .init(z: z, x: x, y: y, catalogs: catalogs,
                    dates: items.first { $0.name == "dates" }?.value ?? "current")
            } catch { throw HTTPError(.badRequest) }
            let tile: CalendarMapTile
            do { tile = try await store.mapTiles.tile(tileRequest, store: store) }
            catch CalendarBrowseError.mapNotReady { throw HTTPError(.serviceUnavailable) }
            catch CalendarBrowseError.mapBusy {
                return Response(status: .serviceUnavailable, headers: [.retryAfter: "1"])
            }
            return calendarTileResponse(tile, request: request)
        }
    }

    private static func calendarTileResponse(_ tile: CalendarMapTile, request: Request) -> Response {
            let gzip = acceptsBundleGzip(request.headers[.acceptEncoding])
            let etag = "\"" + tile.etag + (gzip ? "-gzip" : "") + "\""
            var headers: HTTPFields = [.contentType: "application/vnd.mapbox-vector-tile",
                .cacheControl: "public, max-age=10, must-revalidate", .vary: "Accept-Encoding", .eTag: etag]
            headers[HTTPField.Name("Server-Timing")!] = "db;dur=\(tile.databaseMilliseconds), features;desc=\"\(tile.featureCount)\", cache;desc=\"\(tile.cacheHit ? "hit" : "miss")\""
            if gzip { headers[.contentEncoding] = "gzip" }
            if request.headers[.ifNoneMatch]?.split(separator: ",").contains(where: {
                let value = $0.trimmingCharacters(in: .whitespaces)
                return value == etag || value == "W/" + etag || value == "*"
            }) == true { return Response(status: .notModified, headers: headers) }
            return Response(status: .ok, headers: headers,
                body: .init(byteBuffer: .init(data: gzip ? tile.gzip : tile.data)))
    }
}
