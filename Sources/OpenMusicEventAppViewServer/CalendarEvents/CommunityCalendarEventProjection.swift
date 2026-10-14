import ATProto
import ATProtoAppView
import ComposableCalendarEvents
import Foundation
import GRDB
import IssueReporting
import OpenMusicEventLexicon
import SQLiteData

extension OpenMusicEventAppViewStore {
    public func communityCalendarEventPage(
        cursor: String?,
        limit: Int
    ) throws -> OME.CalendarEvent.Page {
        let offset: Int
        if let cursor {
            guard let parsedOffset = Int(cursor), parsedOffset >= 0 else {
                throw OpenMusicEventAppViewStoreError.invalidCursor(cursor)
            }
            offset = parsedOffset
        } else {
            offset = 0
        }

        let (encodedEvents, count) = try database.read { database in
            let tableName = CommunityCalendarEventProjection.tableName
            let count = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM \"\(tableName)\""
            ) ?? 0
            guard offset <= count else {
                throw OpenMusicEventAppViewStoreError.invalidCursor(String(offset))
            }
            let encodedEvents = try Data.fetchAll(
                database,
                sql: """
                    SELECT "event"
                    FROM "\(tableName)"
                    ORDER BY
                      "startsAt" ASC NULLS LAST,
                      "createdAt" ASC,
                      "uri" ASC
                    LIMIT ? OFFSET ?
                    """,
                arguments: [limit, offset]
            )
            return (encodedEvents, count)
        }

        let events = try encodedEvents.map {
            try JSONDecoder().decode(OME.CalendarEvent.self, from: $0)
        }
        let nextOffset = offset + events.count
        return OME.CalendarEvent.Page(
            events: events,
            cursor: nextOffset < count ? String(nextOffset) : nil
        )
    }

    public func communityCalendarEvent(
        uri: ATProto.URI
    ) throws -> OME.CalendarEvent? {
        let encodedEvent = try database.read { database in
            let tableName = CommunityCalendarEventProjection.tableName
            return try Data.fetchOne(
                database,
                sql: """
                    SELECT "event"
                    FROM "\(tableName)"
                    WHERE "uri" = ?
                    """,
                arguments: [uri.description]
            )
        }
        return try encodedEvent.map {
            try JSONDecoder().decode(OME.CalendarEvent.self, from: $0)
        }
    }

    func communityCalendarEventRecordIndex() -> AppViewRecordIndex<Data> {
        AppViewRecordIndex<Data>(
            collection: Community.CalendarEvent.nsid,
            decode: { $0 }
        )
        .project { mutation, database in
            try CommunityCalendarEventProjection.apply(mutation, in: database)
        }
    }
}

@Table("communityCalendarEventProjections")
struct CommunityCalendarEventProjection: Codable, Equatable, Sendable {
    @Column(primaryKey: true) var uri: String
    var cid: String
    var startsAt: Date?
    var createdAt: Date
    var sequence: Int64
    var event: Data

    static func registerMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create community calendar event projections") { database in
            let tableName = Self.tableName
            let browseIndexName = "\(tableName)_browse"
            try #sql(
                """
                CREATE TABLE IF NOT EXISTS \(quote: tableName) (
                  "uri" TEXT PRIMARY KEY NOT NULL,
                  "cid" TEXT NOT NULL,
                  "startsAt" TEXT,
                  "createdAt" TEXT NOT NULL,
                  "sequence" INTEGER NOT NULL,
                  "event" BLOB NOT NULL
                ) STRICT
                """
            )
            .execute(database)

            try #sql(
                """
                CREATE INDEX IF NOT EXISTS \(quote: browseIndexName)
                ON \(quote: tableName) (
                  "startsAt",
                  "createdAt",
                  "uri"
                )
                """
            )
            .execute(database)
        }
    }

    static func registerBackfillMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration(
            "Backfill community calendar events with lenient optional URI decoding"
        ) { database in
            try backfillPresentRecords(in: database)
        }
    }

    static func backfillPresentRecords(in database: Database) throws {
        for record in try AppViewIndexDatabase.presentRecords(
            collection: Community.CalendarEvent.nsid,
            in: database
        ) {
            try upsert(record, updateBrowseProjection: false, in: database)
        }
    }

    static func registerArtworkMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Preserve community calendar event artwork") { database in
            var changed = false
            for record in try AppViewIndexDatabase.presentRecords(
                collection: Community.CalendarEvent.nsid, in: database
            ) {
                let images = try artwork(record.value, uri: record.uri)
                guard !images.isEmpty,
                      let existing = try Self.find(record.uri.description).select(\.event).fetchOne(database)
                else { continue }
                let media = try JSONSerialization.jsonObject(with: JSONEncoder().encode(images))
                let event = try replacingArtwork(in: existing, with: media)
                try Self.find(record.uri.description).update { $0.event = #bind(event) }.execute(database)
                if let browse = try CalendarEventBrowseProjection.find(record.uri.description)
                    .select(\.event).fetchOne(database) {
                    let updated = try replacingArtwork(in: browse, with: media)
                    let marker = try images.first.map { try JSONEncoder().encode($0) }
                    try CalendarEventBrowseProjection.find(record.uri.description).update {
                        $0.event = #bind(updated)
                        $0.markerMedia = #bind(marker)
                    }.execute(database)
                }
                changed = true
            }
            if changed {
                try database.execute(
                    sql: "UPDATE \"\(CalendarMapRevision.tableName)\" SET revision = revision + 1 WHERE id LIKE ?",
                    arguments: ["%|\(Community.CalendarEvent.nsid.rawValue)"]
                )
            }
        }
    }

    static func replacingArtwork(in data: Data, with media: Any) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["media"] = media
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func artwork(_ data: Data, uri: ATProto.URI) throws -> [OME.CalendarEvent.Media] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var images: [OME.CalendarEvent.Media] = []
        if let poster = object["poster"] as? [String: Any],
           let text = poster["url"] as? String, let url = webImageURL(text) {
            images.append(.init(url: url, role: "poster", renderKind: .fullImage))
        }
        for item in object["media"] as? [[String: Any]] ?? [] {
            guard let content = item["content"] as? [String: Any],
                  content["$type"] as? String == "blob",
                  let mime = content["mimeType"] as? String,
                  ["image/jpeg", "image/png", "image/webp", "image/gif", "image/avif"].contains(mime),
                  let ref = content["ref"] as? [String: Any],
                  let cid = ref["$link"] as? String, !cid.isEmpty
            else { continue }
            let url = blobURL(uri: uri, cid: cid)
            guard !images.contains(where: { $0.url == url }) else { continue }
            let role = item["role"] as? String
            images.append(.init(url: url, alt: item["alt"] as? String,
                role: role == "poster" ? "poster" : "photo", renderKind: .fullImage))
        }
        return images
    }

    static func blobURL(uri: ATProto.URI, cid: String) -> URL {
        var url = URLComponents()
        url.path = "/event-media"
        url.queryItems = [.init(name: "record", value: uri.description), .init(name: "cid", value: cid)]
        return url.url!
    }

    static func webImageURL(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func apply(
        _ mutation: AppView.RecordMutation<Data>,
        in database: Database
    ) throws {
        switch mutation {
        case let .create(current), let .update(_, current):
            try upsert(current, updateBrowseProjection: true, in: database)

        case let .delete(_, current):
            try deleteCanonical(uri: current.uri, sequence: current.sequence, in: database)
        }
    }

    static func upsert(
        _ current: AppView.RecordVersion<Data>,
        updateBrowseProjection: Bool,
        in database: Database
    ) throws {
        try ingestCanonical(current, updateBrowseProjection: updateBrowseProjection, in: database)
    }

    /// Community Calendar records in the wild use AT URIs alongside web URLs in
    /// their optional `uris` array. Foundation's `URL` decoder rejects AT URIs
    /// whose DID authority contains colons. Preserve the event and omit only
    /// links that the projected `OME.CalendarEvent.Link` cannot represent.
    static func decode(_ data: Data) throws -> Community.CalendarEvent {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return try JSONDecoder().decode(Community.CalendarEvent.self, from: data)
        }
        if let uris = object["uris"] as? [Any] {
            object["uris"] = uris.compactMap { value -> [String: Any]? in
                guard
                    let link = value as? [String: Any],
                    let rawURI = link["uri"] as? String,
                    URL(string: rawURI) != nil
                else { return nil }
                return link
            }
        }
        return try JSONDecoder().decode(
            Community.CalendarEvent.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
}

private enum CommunityCalendarEventHydrationError: Error, Equatable {
    case invalidRecordType(String)
    case invalidOrganizer(String)
    case invalidTimestamp(String)
}

private extension OME.CalendarEvent {
    init(
        communityCalendarRecord record: Community.CalendarEvent,
        uri: ATProto.URI,
        cid: ATProto.CID
    ) throws {
        guard record.type == Community.CalendarEvent.nsid else {
            throw CommunityCalendarEventHydrationError.invalidRecordType(record.type.rawValue)
        }
        guard case let .did(organizerID) = uri.authority else {
            throw CommunityCalendarEventHydrationError.invalidOrganizer(uri.description)
        }

        let locations: [Community.CalendarEvent.Location] =
            (record.locations ?? []).compactMap { location in
                guard case let .known(location) = location else { return nil }
                return location
            }
        self.init(
            uri: uri,
            cid: cid,
            name: record.name,
            description: record.description,
            startsAt: try record.startsAt.map(Self.communityCalendarDate),
            endsAt: try record.endsAt.map(Self.communityCalendarDate),
            createdAt: try Self.communityCalendarDate(record.createdAt),
            status: record.status.map(Self.communityCalendarStatus),
            mode: record.mode.map(Self.communityCalendarMode),
            locations: locations.map(\.openMusicEventLocation),
            links: (record.uris ?? []).map(\.openMusicEventLink)
                + locations.compactMap(\.openMusicEventLink),
            organizer: OME.CalendarEvent.Organizer(id: organizerID),
            source: OME.CalendarEvent.Source(
                collection: Community.CalendarEvent.nsid,
                appViewHost: ATProto.PDSHost("openmusicevent.app")
            )
        )
    }

    static func communityCalendarDate(_ value: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        guard let date = wholeSeconds.date(from: value) else {
            throw CommunityCalendarEventHydrationError.invalidTimestamp(value)
        }
        return date
    }

    static func communityCalendarMode(_ value: String) -> Mode {
        switch value {
        case "community.lexicon.calendar.event#hybrid": .hybrid
        case "community.lexicon.calendar.event#inperson": .inPerson
        case "community.lexicon.calendar.event#virtual": .virtual
        default: .unknown(value)
        }
    }

    static func communityCalendarStatus(_ value: String) -> Status {
        switch value {
        case "community.lexicon.calendar.event#cancelled": .cancelled
        case "community.lexicon.calendar.event#planned": .planned
        case "community.lexicon.calendar.event#postponed": .postponed
        case "community.lexicon.calendar.event#rescheduled": .rescheduled
        case "community.lexicon.calendar.event#scheduled": .scheduled
        default: .unknown(value)
        }
    }
}

private extension Community.CalendarEvent.URI {
    var openMusicEventLink: OME.CalendarEvent.Link {
        OME.CalendarEvent.Link(name: name, uri: uri)
    }
}

private extension Community.CalendarEvent.Location {
    var openMusicEventLocation: OME.CalendarEvent.Location {
        switch self {
        case let .uri(location):
            OME.CalendarEvent.Location(
                name: location.name ?? location.uri.absoluteString,
                source: location.uri.absoluteString
            )
        case let .address(location):
            OME.CalendarEvent.Location(
                name: location.name,
                street: location.street,
                locality: location.locality,
                region: location.region,
                postalCode: location.postalCode,
                country: location.country
            )
        case let .foursquare(location):
            OME.CalendarEvent.Location(
                name: location.name,
                latitude: location.latitude,
                longitude: location.longitude,
                source: location.fsqPlaceID
            )
        case let .geo(location):
            OME.CalendarEvent.Location(
                name: location.name,
                latitude: location.latitude,
                longitude: location.longitude
            )
        case let .hthree(location):
            OME.CalendarEvent.Location(
                name: location.name ?? location.value,
                source: location.value
            )
        }
    }

    var openMusicEventLink: OME.CalendarEvent.Link? {
        guard case let .uri(location) = self else { return nil }
        return location.openMusicEventLink
    }
}
