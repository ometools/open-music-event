import AppViewIndex
import ATProto
import ComposableCalendarEvents
import ComposableNotifications
import ComposableNotificationsServer
import Crypto
import Foundation
import GRDB
import IssueReporting
import OpenMusicEventLexicon
import SQLiteData

public actor OpenMusicEventAppViewReadiness {
    public enum State: Equatable, Sendable {
        case catchingUp
        case ready(cursor: UInt64?)
    }

    public init(state: State = .ready(cursor: nil)) {
        self.state = state
    }

    private var state: State

    public func markCatchingUp() {
        state = .catchingUp
    }

    public func markReady(cursor: UInt64?) {
        state = .ready(cursor: cursor)
    }

    public func snapshot() -> State {
        state
    }
}

public struct OpenMusicEventAppViewStore: WebhookInboxStore, Sendable {
    public let readiness: OpenMusicEventAppViewReadiness
    let database: any DatabaseWriter
    private let webhookSecretProtection: WebhookSecretProtection?

    public init(
        database: any DatabaseWriter,
        webhookSecretProtection: WebhookSecretProtection? = nil,
        initiallyReady: Bool = true
    ) throws {
        self.database = database
        self.webhookSecretProtection = webhookSecretProtection
        self.readiness = OpenMusicEventAppViewReadiness(
            state: initiallyReady ? .ready(cursor: nil) : .catchingUp
        )
        try Self.migrate(database)
    }

    public init(
        databaseURL: URL,
        webhookSecretProtection: WebhookSecretProtection? = nil,
        initiallyReady: Bool = true
    ) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.foreignKeysEnabled = true
        try self.init(
            database: DatabasePool(
                path: databaseURL.path(percentEncoded: false),
                configuration: configuration
            ),
            webhookSecretProtection: webhookSecretProtection,
            initiallyReady: initiallyReady
        )
    }

    public func record(
        _ delivery: WebhookInboxDelivery
    ) async throws -> WebhookInboxRecordResult {
        let row = WebhookInboxDeliveryRow(
            source: delivery.source.rawValue,
            watchID: delivery.watchID.rawValue,
            deliveryID: delivery.deliveryID.rawValue,
            event: delivery.event,
            payload: delivery.payload,
            payloadDigest: Self.webhookPayloadDigest(delivery.payload),
            receivedAt: delivery.receivedAt
        )
        return try await database.write { database in
            let existing = try WebhookInboxDeliveryRow
                .where { delivery in delivery.source.eq(row.source) }
                .where { delivery in delivery.deliveryID.eq(row.deliveryID) }
                .fetchOne(database)
            if let existing {
                guard existing.watchID == row.watchID,
                      existing.event == row.event,
                      existing.payloadDigest == row.payloadDigest,
                      existing.payload == row.payload
                else {
                    throw WebhookInboxError.deliveryConflict(
                        source: delivery.source,
                        deliveryID: delivery.deliveryID
                    )
                }
                return .duplicate
            }

            try WebhookInboxDeliveryRow.insert { row }.execute(database)
            return .inserted
        }
    }

    public func replaceWebhookSecret(
        _ secret: Data,
        source: WebhookInboxDelivery.Source,
        watchID: WebhookInboxDelivery.WatchID
    ) async throws {
        guard !secret.isEmpty else {
            throw WebhookSecretPersistenceError.emptySecret
        }
        guard let webhookSecretProtection else {
            throw WebhookSecretPersistenceError.protectionUnavailable
        }
        let ciphertext = try webhookSecretProtection.seal(
            secret,
            source: source,
            watchID: watchID
        )
        try await database.write { database in
            try WebhookSecretRow
                .where { $0.source.eq(source.rawValue) }
                .where { $0.watchID.eq(watchID.rawValue) }
                .delete()
                .execute(database)
            try WebhookSecretRow.insert {
                WebhookSecretRow(
                    source: source.rawValue,
                    watchID: watchID.rawValue,
                    secret: ciphertext,
                    secretKeyVersion: webhookSecretProtection.keyVersion
                )
            }
            .execute(database)
        }
    }

    public func webhookSecret(
        source: WebhookInboxDelivery.Source,
        watchID: WebhookInboxDelivery.WatchID
    ) async throws -> Data? {
        guard let webhookSecretProtection else {
            throw WebhookSecretPersistenceError.protectionUnavailable
        }
        guard let row = try await database.read({ database in
            try WebhookSecretRow
                .where { $0.source.eq(source.rawValue) }
                .where { $0.watchID.eq(watchID.rawValue) }
                .fetchOne(database)
        }) else { return nil }
        return try webhookSecretProtection.open(
            row.secret,
            source: source,
            watchID: watchID,
            keyVersion: row.secretKeyVersion
        )
    }

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

    var communityCalendarEventIndexer: AppViewRecordIndexer {
        AppViewRecordIndexer {
            AppViewRecordIndex<Community.CalendarEvent>(
                collection: Community.CalendarEvent.nsid
            )
            .project { mutation, database in
                try CommunityCalendarEventProjection.apply(mutation, in: database)
            }
        }
    }

    private static func migrate(_ database: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        AppViewIndexMigrations.register(into: &migrator)
        CommunityCalendarEventProjection.registerMigration(into: &migrator)
        NotificationDatabase.registerMigrations(into: &migrator)
        WebhookInboxSchema.registerMigration(into: &migrator)
        WebhookSecretSchema.registerMigration(into: &migrator)
        try migrator.migrate(database)
    }

    private static func webhookPayloadDigest(_ payload: Data) -> String {
        Data(SHA256.hash(data: payload)).base64EncodedString()
    }

}

public enum OpenMusicEventAppViewStoreError: Error, Equatable, Sendable {
    case invalidCursor(String)
}

public enum WebhookSecretPersistenceError: Error, Equatable, Sendable {
    case emptySecret
    case protectionUnavailable
}

@Table("webhookInboxDeliveries")
private struct WebhookInboxDeliveryRow: Equatable, Sendable {
    var source: String
    var watchID: String
    var deliveryID: String
    var event: String
    var payload: Data
    var payloadDigest: String
    var receivedAt: Date
}

@Table("webhookSecrets")
private struct WebhookSecretRow: Equatable, Sendable {
    var source: String
    var watchID: String
    var secret: Data
    var secretKeyVersion: Int
}

private enum WebhookInboxSchema {
    static func registerMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create webhook inbox deliveries") { database in
            let tableName = WebhookInboxDeliveryRow.tableName
            try #sql(
                """
                    CREATE TABLE \(quote: tableName) (
                      source TEXT NOT NULL,
                      watchID TEXT NOT NULL,
                      deliveryID TEXT NOT NULL,
                      event TEXT NOT NULL,
                      payload BLOB NOT NULL,
                      payloadDigest TEXT NOT NULL,
                      receivedAt TEXT NOT NULL,
                      PRIMARY KEY (source, deliveryID)
                    ) STRICT
                    """
            )
            .execute(database)
        }
    }
}

private enum WebhookSecretSchema {
    static func registerMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create webhook secrets") { database in
            let tableName = WebhookSecretRow.tableName
            try #sql(
                """
                    CREATE TABLE \(quote: tableName) (
                      source TEXT NOT NULL,
                      watchID TEXT NOT NULL,
                      secret BLOB NOT NULL,
                      secretKeyVersion INTEGER NOT NULL,
                      PRIMARY KEY (source, watchID)
                    ) STRICT
                    """
            )
            .execute(database)
        }
    }
}

@Table("communityCalendarEventProjections")
private struct CommunityCalendarEventProjection: Codable, Equatable, Sendable {
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

    static func apply(
        _ mutation: AppView.RecordMutation<Community.CalendarEvent>,
        in database: Database
    ) throws {
        switch mutation {
        case let .create(current), let .update(_, current):
            let event: OME.CalendarEvent
            let createdAt: Date
            do {
                event = try OME.CalendarEvent(
                    communityCalendarRecord: current.value,
                    uri: current.uri,
                    cid: current.cid
                )
                guard let eventCreatedAt = event.createdAt else {
                    throw CommunityCalendarEventHydrationError.invalidTimestamp(
                        current.value.createdAt
                    )
                }
                createdAt = eventCreatedAt
            } catch let error as CommunityCalendarEventHydrationError {
                reportIssue(error)
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

        case let .delete(_, current):
            try Self.find(current.uri.description)
                .delete()
                .execute(database)
        }
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
