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

    static func apply(
        _ mutation: AppView.RecordMutation<Data>,
        in database: Database
    ) throws {
        switch mutation {
        case let .create(current), let .update(_, current):
            try upsert(current, updateBrowseProjection: true, in: database)

        case let .delete(_, current):
            try Self.find(current.uri.description)
                .delete()
                .execute(database)
            try CalendarEventBrowseProjection.delete(
                uri: current.uri.description,
                in: database
            )
        }
    }

    static func upsert(
        _ current: AppView.RecordVersion<Data>,
        updateBrowseProjection: Bool,
        in database: Database
    ) throws {
        let event: OME.CalendarEvent
        let createdAt: Date
        do {
            let record = try decode(current.value)
            event = try OME.CalendarEvent(
                communityCalendarRecord: record,
                uri: current.uri,
                cid: current.cid
            )
            guard let eventCreatedAt = event.createdAt else {
                throw CommunityCalendarEventHydrationError.invalidTimestamp(
                    record.createdAt
                )
            }
            createdAt = eventCreatedAt
        } catch {
            reportIssue(
                error,
                "Could not project community calendar event \(current.uri.description)."
            )
            return
        }
        let encodedEvent = try JSONEncoder().encode(event)
        try Self.upsert {
            Self(
                uri: current.uri.description,
                cid: current.cid.rawValue,
                startsAt: event.startsAt,
                createdAt: createdAt,
                sequence: current.sequence,
                event: encodedEvent
            )
        }
        .execute(database)
        if updateBrowseProjection {
            try CalendarEventBrowseProjection.upsert(event, in: database)
        }
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
