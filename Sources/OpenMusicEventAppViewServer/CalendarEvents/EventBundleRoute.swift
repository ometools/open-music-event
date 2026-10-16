import ATProto
import Crypto
import Foundation
import Gzip
import GRDB
import Hummingbird
import OpenMusicEventDatabase
import OpenMusicEventLexicon

/// A bounded cache of the original indexed payloads, keyed by all record CIDs.
actor EventBundleCache {
    struct Entry {
        var versions: [String: String]
        var json: Data
        var gzip: Data
        var revision: String
    }
    var entries: [Event.ID: Entry] = [:]
    var recency: [Event.ID] = []

    func bundle(id: Event.ID, store: OpenMusicEventAppViewStore) throws -> Entry? {
        guard id.collection?.rawValue == Event.lexiconID.rawValue else { return nil }
        let snapshot = try store.database.read { db -> [Row]? in
            guard try String.fetchOne(db, sql: "SELECT id FROM \"events.openmusic.event\" WHERE id = ?", arguments: [id.description]) != nil else { return nil }
            let collections = ["events.openmusic.program", "events.openmusic.schedule", "events.openmusic.eventPlace",
                "events.openmusic.contributor", "events.openmusic.programItem", "social.ome.category", "social.ome.post"]
            var addresses = [id.description]
            for collection in collections {
                let children = try String.fetchAll(db, sql: "SELECT id FROM \"\(collection)\" WHERE event = ?", arguments: [id.description])
                addresses.append(contentsOf: children.filter {
                    collection != "social.ome.post" || ATProto.URI($0)?.authority == id.authority
                })
            }
            var rows: [Row] = []
            for start in stride(from: 0, to: addresses.count, by: 500) {
                let chunk = Array(addresses[start..<min(start + 500, addresses.count)])
                let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                rows += try Row.fetchAll(db,
                    sql: "SELECT uri, cid, value FROM appViewIndexedRecords WHERE isDeleted = 0 AND uri IN (\(placeholders))",
                    arguments: StatementArguments(chunk))
            }
            guard rows.count == addresses.count else { throw ValidationError("Event records are not fully indexed") }
            return rows
        }
        guard let rows = snapshot else {
            entries[id] = nil
            recency.removeAll { $0 == id }
            return nil
        }
        let versions = Dictionary(uniqueKeysWithValues: rows.map { row -> (String, String) in (row["uri"], row["cid"]) })
        recency.removeAll { $0 == id }
        if let existing = entries[id], existing.versions == versions {
            recency.append(id)
            return existing
        }
        entries[id] = nil
        var references: [ATProto.URI: References] = [:]
        let records = try rows.map { row -> Event.IndexedRecord in
            let uri: String = row["uri"]
            let cid: String = row["cid"]
            let data: Data = row["value"]
            guard let address = ATProto.URI(uri) else { throw ValidationError("Invalid indexed record URI") }
            references[address] = try JSONDecoder().decode(References.self, from: data)
            return .init(uri: address, cid: ATProto.CID(rawValue: cid),
                value: try JSONDecoder().decode(Lexicon.JSONValue.self, from: data))
        }.sorted { $0.uri.description < $1.uri.description }
        try validateReferences(references, event: id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let content = Event.Bundle(uri: id, revision: "", records: records)
        let revision = SHA256.hash(data: try encoder.encode(content)).map { String(format: "%02x", $0) }.joined()
        let json = try encoder.encode(Event.Bundle(uri: id, revision: revision, records: records))
        let entry = Entry(versions: versions, json: json, gzip: try json.gzipped(), revision: revision)
        entries[id] = entry
        recency.append(id)
        let byteLimit = 32 * 1024 * 1024
        var bytes = entries.values.reduce(into: 0) { $0 += $1.json.count; $0 += $1.gzip.count }
        while entries.count > 8 || bytes > byteLimit {
            guard !recency.isEmpty else { break }
            if let removed = entries.removeValue(forKey: recency.removeFirst()) {
                bytes -= removed.json.count + removed.gzip.count
            }
        }
        return entry
    }

    /// Ingestion already validates record schemas. Decode only graph references here;
    /// decoding rich display models would repeat expensive schema work on every request.
    private struct References: Decodable {
        var event: String?
        var programs: [String]?
        var schedules: [String]?
        var categories: [String]?
        var eventPlaces: [String]?
        var pinnedPosts: [String]?
        var program: String?
        var schedule: String?
        var eventPlace: String?
        var category: String?
        var credits: [Credit]?
        struct Credit: Decodable { var contributor: String? }
    }

    private func validateReferences(_ records: [ATProto.URI: References], event: Event.ID) throws {
        func ids(_ collection: String) -> Set<String> {
            Set(records.keys.filter { $0.collection == ATProto.NSID(collection) }.map(\.description))
        }
        let programs = ids("events.openmusic.program")
        let schedules = ids("events.openmusic.schedule")
        let places = ids("events.openmusic.eventPlace")
        let contributors = ids("events.openmusic.contributor")
        let categories = ids("social.ome.category")
        let posts = ids("social.ome.post")
        guard let root = records[event], Set(root.programs ?? []) == programs,
              Set(root.schedules ?? []) == schedules, Set(root.categories ?? []) == categories else {
            throw ValidationError("The event bundle is missing declared records")
        }
        for (uri, refs) in records where uri != event {
            guard refs.event == event.description else { throw ValidationError("Mismatched event ownership") }
            let collection = uri.collection?.rawValue
            if collection == "events.openmusic.program" {
                guard Set(refs.eventPlaces ?? []).isSubset(of: places) else { throw ValidationError("Missing program place") }
            } else if collection == "events.openmusic.programItem" {
                guard let program = refs.program, programs.contains(program),
                      refs.schedule.map({ schedules.contains($0) }) ?? true,
                      refs.eventPlace.map({ place in
                          places.contains(place) && records.first(where: { $0.key.description == program })?.value.eventPlaces?.contains(place) == true
                      }) ?? true,
                      (refs.credits ?? []).allSatisfy({ $0.contributor.map { contributors.contains($0) } ?? true })
                else { throw ValidationError("Missing program item dependency") }
            } else if collection == "social.ome.category" {
                guard Set(refs.pinnedPosts ?? []).isSubset(of: posts) else { throw ValidationError("Missing pinned post") }
            } else if collection == "social.ome.post" {
                guard uri.authority == event.authority, refs.category.map({ categories.contains($0) }) ?? true else {
                    throw ValidationError("Invalid organizer post")
                }
            }
        }
    }
}

extension OpenMusicEventAppViewServer {
    static func installEventBundleRoute<Context: RequestContext>(
        on router: Router<Context>, store: OpenMusicEventAppViewStore?
    ) {
        router.get(RouterPath("/xrpc/" + Event.GetEventBundle.nsid.rawValue)) { request, _ async throws -> Response in
            guard let store else { return bundleError(.serviceUnavailable, "EventIndexUnavailable") }
            if case .catchingUp = await store.readiness.snapshot() {
                return bundleError(.serviceUnavailable, "EventIndexCatchingUp")
            }
            let query = URLComponents(string: "?" + (request.uri.query ?? ""))?.queryItems ?? []
            let values = query.filter { $0.name == "uri" }
            guard values.count == 1, let value = values.first?.value, let id = Event.ID(value) else {
                return bundleError(.badRequest, "InvalidEventURI")
            }
            do { try LexiconCoding.validateRecordURI(id, type: Event.self) }
            catch { return bundleError(.badRequest, "InvalidEventURI") }

            let entry: EventBundleCache.Entry
            do {
                guard let result = try await store.eventBundles.bundle(id: id, store: store) else {
                    return bundleError(.notFound, "EventNotFound")
                }
                entry = result
            } catch is ValidationError {
                return bundleError(.serviceUnavailable, "EventBundleIncomplete")
            }
            let gzip = acceptsBundleGzip(request.headers[.acceptEncoding])
            let tag = "\"" + entry.revision + (gzip ? "-gzip" : "-identity") + "\""
            var headers: HTTPFields = [
                .contentType: "application/json",
                .cacheControl: "public, max-age=0, s-maxage=30, must-revalidate",
                .vary: "Accept-Encoding",
                .eTag: tag,
            ]
            if gzip { headers[.contentEncoding] = "gzip" }
            if let condition = request.headers[.ifNoneMatch],
               condition.split(separator: ",").contains(where: {
                   let candidate = $0.trimmingCharacters(in: .whitespaces)
                   return candidate == "*" || candidate == tag || candidate == "W/" + tag
               }) {
                return Response(status: .notModified, headers: headers)
            }
            return Response(status: .ok, headers: headers,
                body: .init(byteBuffer: .init(data: gzip ? entry.gzip : entry.json)))
        }
    }

    static func acceptsBundleGzip(_ header: String?) -> Bool {
        var wildcard: Double = 0
        for entry in (header ?? "").lowercased().split(separator: ",") {
            let parts = entry.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            let quality = parts.dropFirst().first(where: { $0.hasPrefix("q=") })
                .flatMap { Double($0.dropFirst(2)) } ?? 1
            if parts.first == "gzip" { return quality > 0 }
            if parts.first == "*" { wildcard = quality }
        }
        return wildcard > 0
    }

    static func bundleError(_ status: HTTPResponse.Status, _ error: String) -> Response {
        Response(status: status, headers: [.contentType: "application/json", .cacheControl: "no-store"],
            body: .init(byteBuffer: .init(string: "{\"error\":\"\(error)\"}")))
    }
}
