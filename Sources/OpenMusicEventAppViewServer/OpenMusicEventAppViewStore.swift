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
import OpenMusicEventRouting
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

    func tangledSourceCheckpoint(
        watchID: WebhookInboxDelivery.WatchID
    ) async throws -> TangledSourceCheckpoint? {
        try await database.read { database in
            try TangledSourceRevisionRow
                .find(watchID.rawValue)
                .fetchOne(database)
                .map(TangledSourceCheckpoint.init)
        }
    }

    @discardableResult
    func apply(
        _ after: TangledSourceSnapshot,
        replacing before: TangledSourceSnapshot?,
        publishedArtifact: PublishedSourceArtifact,
        for update: TangledSourceUpdate
    ) async throws -> Int {
        try await database.write { database in
            guard after.revision == update.after else {
                throw OpenMusicEventAppViewStoreError.tangledSourceRevisionMismatch(
                    watchID: update.watchID.rawValue,
                    expected: update.after,
                    actual: after.revision
                )
            }
            guard publishedArtifact.revision == update.after else {
                throw OpenMusicEventAppViewStoreError.tangledSourceRevisionMismatch(
                    watchID: update.watchID.rawValue,
                    expected: update.after,
                    actual: publishedArtifact.revision
                )
            }

            let current = try TangledSourceRevisionRow
                .find(update.watchID.rawValue)
                .fetchOne(database)

            if let current {
                try current.validateWatch(for: update)
                if current.revision == update.after {
                    if current.publishedArtifact != publishedArtifact {
                        try TangledSourceRevisionRow.upsert {
                            TangledSourceRevisionRow(
                                update: update,
                                publishedArtifact: publishedArtifact
                            )
                        }
                        .execute(database)
                    }
                    return 0
                }
                guard current.revision == update.before else {
                    throw OpenMusicEventAppViewStoreError.tangledSourceRevisionMismatch(
                        watchID: update.watchID.rawValue,
                        expected: update.before,
                        actual: current.revision
                    )
                }
            } else {
                guard before?.revision == update.before else {
                    throw OpenMusicEventAppViewStoreError.tangledSourceRevisionMismatch(
                        watchID: update.watchID.rawValue,
                        expected: update.before,
                        actual: nil
                    )
                }
            }

            let previousPostKeys: Set<TangledSourceCommunicationPostKey>
            if current != nil {
                previousPostKeys = try Set(
                    TangledSourceCommunicationPostRow
                        .where { $0.watchID.eq(update.watchID.rawValue) }
                        .fetchAll(database)
                        .map(\.key)
                )
            } else {
                previousPostKeys = Set(
                    before?.posts.map { TangledSourceCommunicationPostKey($0.id) } ?? []
                )
            }
            let addedPosts = after.posts.filter {
                !previousPostKeys.contains(TangledSourceCommunicationPostKey($0.id))
            }

            try TangledSourceRevisionRow.upsert {
                TangledSourceRevisionRow(
                    update: update,
                    publishedArtifact: publishedArtifact
                )
            }
            .execute(database)
            try TangledSourceCommunicationPostRow
                .where { $0.watchID.eq(update.watchID.rawValue) }
                .delete()
                .execute(database)
            if !after.posts.isEmpty {
                try TangledSourceCommunicationPostRow.insert {
                    after.posts.map {
                        TangledSourceCommunicationPostRow(
                            watchID: update.watchID.rawValue,
                            postID: $0.id
                        )
                    }
                }
                .execute(database)
            }

            let channelSources = Dictionary(grouping: addedPosts) { post in
                TangledSourceChannelKey(
                    organizerID: post.id.organizerID,
                    eventID: post.id.eventID,
                    channelID: post.id.channelID
                )
            }
            .keys
            .map { channel in
                NotificationSource(
                    id: .init(
                        rawValue: openMusicEventEventPathRouter.communicationChannelPath(
                            eventID: OME.Event.ID(
                                organizerID: channel.organizerID,
                                eventID: channel.eventID
                            ),
                            channelID: channel.channelID
                        )
                    ),
                    version: .init(rawValue: update.after)
                )
            }
            .sorted { $0.id.rawValue < $1.id.rawValue }

            var enqueuedCount = try channelSources.reduce(into: 0) { count, source in
                count += try NotificationDatabase.enqueue(
                    source: source,
                    at: update.receivedAt,
                    in: database
                )
            }

            for post in addedPosts.sorted(by: {
                $0.id.postID.rawValue.rawValue < $1.id.postID.rawValue.rawValue
            }) {
                let eventID = OME.Event.ID(
                    organizerID: post.id.organizerID,
                    eventID: post.id.eventID
                )
                let source = NotificationSource(
                    id: .init(
                        rawValue: openMusicEventEventPathRouter.communicationChannelPath(
                            eventID: eventID,
                            channelID: post.id.channelID
                        )
                    ),
                    version: .init(rawValue: update.after)
                )
                let route = TangledCommunicationPostNotificationRoute(
                    notificationRoute: openMusicEventEventPathRouter.communicationPostPath(
                        eventID: eventID,
                        channelID: post.id.channelID,
                        postID: post.id.postID.rawValue.rawValue
                    )
                )
                enqueuedCount += try NotificationDatabase.enqueue(
                    content: NotificationContent(
                        source: source,
                        route: route,
                        presentation: NotificationPresentation(
                            title: post.title,
                            body: post.contents
                        )
                    ),
                    at: update.receivedAt,
                    in: database
                )
            }
            return enqueuedCount
        }
    }

    private static func migrate(_ database: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        AppViewIndexMigrations.register(into: &migrator)
        CommunityCalendarEventProjection.registerMigration(into: &migrator)
        NotificationDatabase.registerMigrations(into: &migrator)
        TangledSourceProjectionSchema.registerMigration(into: &migrator)
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
    case tangledSourceWatchMismatch(watchID: String)
    case tangledSourceRevisionMismatch(watchID: String, expected: String, actual: String?)
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

struct TangledSourceCheckpoint: Equatable, Sendable {
    fileprivate init(_ row: TangledSourceRevisionRow) {
        watchID = .init(rawValue: row.watchID)
        repositoryOwnerDID = row.repositoryOwnerDID
        repositoryKey = row.repositoryKey
        ref = row.ref
        canonicalSourceReference = row.canonicalSourceReference
        revision = row.revision
        publishedArtifact = row.publishedArtifact
    }

    let watchID: WebhookInboxDelivery.WatchID
    let repositoryOwnerDID: String
    let repositoryKey: String
    let ref: String
    let canonicalSourceReference: String
    let revision: String
    let publishedArtifact: PublishedSourceArtifact?

    func validateWatch(for update: TangledSourceUpdate) throws {
        guard repositoryOwnerDID == update.repositoryOwnerDID.description,
              repositoryKey == update.repositoryKey.rawValue,
              ref == update.ref,
              canonicalSourceReference == update.canonicalSource.reference
        else {
            throw OpenMusicEventAppViewStoreError.tangledSourceWatchMismatch(
                watchID: update.watchID.rawValue
            )
        }
    }
}

@Table("tangledSourceRevisions")
private struct TangledSourceRevisionRow: Equatable, Sendable {
    @Column(primaryKey: true) var watchID: String
    @Column("repositoryDID") var repositoryOwnerDID: String
    var repositoryKey: String
    var ref: String
    @Column("sourceID") var canonicalSourceReference: String
    var revision: String
    var artifactReference: String?
    var artifactObjectKey: String?
    var artifactChecksumSHA256: String?
    var artifactByteCount: Int?
    var artifactPublishedAt: Date?

    init(
        update: TangledSourceUpdate,
        publishedArtifact: PublishedSourceArtifact
    ) {
        watchID = update.watchID.rawValue
        repositoryOwnerDID = update.repositoryOwnerDID.description
        repositoryKey = update.repositoryKey.rawValue
        ref = update.ref
        canonicalSourceReference = update.canonicalSource.reference
        revision = update.after
        artifactReference = publishedArtifact.reference
        artifactObjectKey = publishedArtifact.objectKey
        artifactChecksumSHA256 = publishedArtifact.checksumSHA256
        artifactByteCount = publishedArtifact.byteCount
        artifactPublishedAt = publishedArtifact.publishedAt
    }

    var publishedArtifact: PublishedSourceArtifact? {
        guard let artifactReference,
              let artifactObjectKey,
              let artifactChecksumSHA256,
              let artifactByteCount,
              let artifactPublishedAt
        else { return nil }
        return PublishedSourceArtifact(
            reference: artifactReference,
            objectKey: artifactObjectKey,
            revision: revision,
            checksumSHA256: artifactChecksumSHA256,
            byteCount: artifactByteCount,
            publishedAt: artifactPublishedAt
        )
    }

    func validateWatch(for update: TangledSourceUpdate) throws {
        try TangledSourceCheckpoint(self).validateWatch(for: update)
    }
}

private struct TangledSourceCommunicationPostKey: Hashable, Sendable {
    init(organizerID: String, eventID: String, channelID: String, postID: String) {
        self.organizerID = organizerID
        self.eventID = eventID
        self.channelID = channelID
        self.postID = postID
    }

    init(_ postID: OME.SourceDatabaseInsertion.CommunicationPost.ID) {
        organizerID = postID.organizerID.description
        eventID = postID.eventID.rawValue.rawValue
        channelID = postID.channelID.rawValue.rawValue
        self.postID = postID.postID.rawValue.rawValue
    }

    let organizerID: String
    let eventID: String
    let channelID: String
    let postID: String
}

private struct TangledSourceChannelKey: Hashable, Sendable {
    let organizerID: OME.Organizer.ID
    let eventID: OME.ID<OME.Event>
    let channelID: OME.ID<OME.Channel>
}

private struct TangledCommunicationPostNotificationRoute: NotificationRoute {
    let notificationRoute: String

    init(notificationRoute: String) {
        self.notificationRoute = notificationRoute
    }
}

@Table("tangledSourceCommunicationPosts")
private struct TangledSourceCommunicationPostRow: Equatable, Sendable {
    var watchID: String
    var organizerID: String
    var eventID: String
    var channelID: String
    var postID: String

    init(
        watchID: String,
        postID: OME.SourceDatabaseInsertion.CommunicationPost.ID
    ) {
        self.watchID = watchID
        let key = TangledSourceCommunicationPostKey(postID)
        organizerID = key.organizerID
        eventID = key.eventID
        channelID = key.channelID
        self.postID = key.postID
    }

    var key: TangledSourceCommunicationPostKey {
        TangledSourceCommunicationPostKey(
            organizerID: organizerID,
            eventID: eventID,
            channelID: channelID,
            postID: postID
        )
    }
}

private enum TangledSourceProjectionSchema {
    static func registerMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create Tangled source notification projections") { database in
            let revisionTable = TangledSourceRevisionRow.tableName
            let postTable = TangledSourceCommunicationPostRow.tableName
            try #sql(
                """
                CREATE TABLE \(quote: revisionTable) (
                  "watchID" TEXT PRIMARY KEY NOT NULL,
                  "repositoryDID" TEXT NOT NULL,
                  "repositoryKey" TEXT NOT NULL,
                  "ref" TEXT NOT NULL,
                  "sourceID" TEXT NOT NULL,
                  "revision" TEXT NOT NULL
                ) STRICT
                """
            )
            .execute(database)
            try #sql(
                """
                CREATE TABLE \(quote: postTable) (
                  "watchID" TEXT NOT NULL REFERENCES \(quote: revisionTable)("watchID") ON DELETE CASCADE,
                  "organizerID" TEXT NOT NULL,
                  "eventID" TEXT NOT NULL,
                  "channelID" TEXT NOT NULL,
                  "postID" TEXT NOT NULL,
                  PRIMARY KEY ("watchID", "organizerID", "eventID", "channelID", "postID")
                ) STRICT
                """
            )
            .execute(database)
        }
        migrator.registerMigration("Add Tangled source artifact publications") { database in
            let revisionTable = TangledSourceRevisionRow.tableName
            try #sql(
                "ALTER TABLE \(quote: revisionTable) ADD COLUMN \"artifactReference\" TEXT"
            )
            .execute(database)
            try #sql(
                "ALTER TABLE \(quote: revisionTable) ADD COLUMN \"artifactObjectKey\" TEXT"
            )
            .execute(database)
            try #sql(
                "ALTER TABLE \(quote: revisionTable) ADD COLUMN \"artifactChecksumSHA256\" TEXT"
            )
            .execute(database)
            try #sql(
                "ALTER TABLE \(quote: revisionTable) ADD COLUMN \"artifactByteCount\" INTEGER"
            )
            .execute(database)
            try #sql(
                "ALTER TABLE \(quote: revisionTable) ADD COLUMN \"artifactPublishedAt\" TEXT"
            )
            .execute(database)
        }
    }
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
