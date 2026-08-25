import ATProto
import ComposableNotifications
import ComposableNotificationsServer
import Foundation
import GRDB
import OpenMusicEventLexicon
import OpenMusicEventRouting
import SQLiteData

extension OpenMusicEventAppViewStore {
    func tangledSourceCalendarEvents(
        watchIDs: [WebhookInboxDelivery.WatchID],
        appViewHost: ATProto.PDSHost
    ) throws -> [OME.CalendarEvent] {
        let selectedWatchIDs = Set(watchIDs.map(\.rawValue))
        guard !selectedWatchIDs.isEmpty else { return [] }

        return try database.read { database in
            let checkpointsByWatchID = Dictionary(
                uniqueKeysWithValues: try TangledSourceRevisionRow
                    .fetchAll(database)
                    .map { ($0.watchID, $0) }
            )
            return try TangledSourceCalendarEventRow
                .order { ($0.startsAt.desc(), $0.uri) }
                .fetchAll(database)
                .filter { selectedWatchIDs.contains($0.watchID) }
                .map { row in
                    guard let checkpoint = checkpointsByWatchID[row.watchID] else {
                        throw OpenMusicEventAppViewStoreError
                            .tangledSourceCheckpointMissing(watchID: row.watchID)
                    }
                    return try row.calendarEvent(
                        checkpoint: checkpoint,
                        appViewHost: appViewHost
                    )
                }
        }
    }

    func tangledSourceCalendarEvent(
        uri: ATProto.URI,
        watchIDs: [WebhookInboxDelivery.WatchID],
        appViewHost: ATProto.PDSHost
    ) throws -> OME.CalendarEvent? {
        try tangledSourceCalendarEvents(
            watchIDs: watchIDs,
            appViewHost: appViewHost
        )
        .first { $0.uri == uri }
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
            let repairsCurrentRevision: Bool

            if let current {
                try TangledSourceCheckpoint(current).validateWatch(for: update)
                if current.revision == update.after {
                    guard current.publishedArtifact != publishedArtifact else { return 0 }
                    repairsCurrentRevision = true
                } else {
                    guard current.revision == update.before else {
                        throw OpenMusicEventAppViewStoreError.tangledSourceRevisionMismatch(
                            watchID: update.watchID.rawValue,
                            expected: update.before,
                            actual: current.revision
                        )
                    }
                    repairsCurrentRevision = false
                }
            } else {
                guard before?.revision == update.before else {
                    throw OpenMusicEventAppViewStoreError.tangledSourceRevisionMismatch(
                        watchID: update.watchID.rawValue,
                        expected: update.before,
                        actual: nil
                    )
                }
                repairsCurrentRevision = false
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
            let calendarEventRows = try after.events.map {
                try TangledSourceCalendarEventRow(
                    watchID: update.watchID.rawValue,
                    event: $0
                )
            }

            try TangledSourceRevisionRow.upsert {
                TangledSourceRevisionRow(
                    update: update,
                    publishedArtifact: publishedArtifact
                )
            }
            .execute(database)
            try TangledSourceCalendarEventRow
                .where { $0.watchID.eq(update.watchID.rawValue) }
                .delete()
                .execute(database)
            if !calendarEventRows.isEmpty {
                try TangledSourceCalendarEventRow.insert {
                    calendarEventRows
                }
                .execute(database)
            }
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

            // Backfill repairs the durable catalog but never delivers historical notifications.
            if repairsCurrentRevision { return 0 }

            let eventSources = after.events
                .map { event in
                    NotificationSource(
                        id: .init(
                            rawValue: event.uri.description
                        ),
                        version: .init(rawValue: update.after)
                    )
                }
                .sorted { $0.id.rawValue < $1.id.rawValue }

            var enqueuedCount = try eventSources.reduce(into: 0) { count, source in
                count += try NotificationDatabase.enqueue(
                    source: source,
                    at: update.receivedAt,
                    in: database
                )
            }

            let emergencyExpiresAt = update.receivedAt.addingTimeInterval(
                OME.Announcement.Delivery.emergencyTimeToLive
            )
            for post in addedPosts.sorted(by: {
                $0.id.postID.rawValue.rawValue < $1.id.postID.rawValue.rawValue
            }) {
                let eventID = OME.Event.ID(
                    organizerID: post.id.organizerID,
                    eventID: post.id.eventID
                )
                let source: NotificationSource
                let delivery: NotificationPresentation.Delivery
                switch post.delivery {
                case .emergency:
                    source = NotificationSource(
                        id: .init(rawValue: OME.Event.reference(id: eventID).uri.description),
                        version: .init(rawValue: update.after)
                    )
                    delivery = .emergency(expiresAt: emergencyExpiresAt)

                case .silent:
                    continue

                case .standard:
                    source = NotificationSource(
                        id: .init(
                            rawValue: openMusicEventEventPathRouter.communicationChannelPath(
                                eventID: eventID,
                                channelID: post.id.channelID
                            )
                        ),
                        version: .init(rawValue: update.after)
                    )
                    delivery = .standard
                }
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
                            body: post.contents,
                            delivery: delivery
                        )
                    ),
                    at: update.receivedAt,
                    in: database
                )
            }
            return enqueuedCount
        }
    }

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
    var artifactURL: String?
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
        artifactURL = publishedArtifact.url.absoluteString
        artifactReference = publishedArtifact.reference
        artifactObjectKey = publishedArtifact.objectKey
        artifactChecksumSHA256 = publishedArtifact.checksumSHA256
        artifactByteCount = publishedArtifact.byteCount
        artifactPublishedAt = publishedArtifact.publishedAt
    }

    var publishedArtifact: PublishedSourceArtifact? {
        guard let artifactURL,
              let url = URL(string: artifactURL),
              url.scheme == "https",
              url.host(percentEncoded: false) != nil,
              let artifactReference,
              let artifactObjectKey,
              let artifactChecksumSHA256,
              let artifactByteCount,
              let artifactPublishedAt
        else { return nil }
        return PublishedSourceArtifact(
            url: url,
            reference: artifactReference,
            objectKey: artifactObjectKey,
            revision: revision,
            checksumSHA256: artifactChecksumSHA256,
            byteCount: artifactByteCount,
            publishedAt: artifactPublishedAt
        )
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

private struct TangledCommunicationPostNotificationRoute: NotificationRoute {
    let notificationRoute: String

    init(notificationRoute: String) {
        self.notificationRoute = notificationRoute
    }
}

@Table("tangledSourceCalendarEvents")
private struct TangledSourceCalendarEventRow: Equatable, Sendable {
    @Column(primaryKey: true) var uri: String
    var watchID: String
    var startsAt: Date?
    var event: Data

    init(watchID: String, event: OME.CalendarEvent) throws {
        uri = event.uri.description
        self.watchID = watchID
        startsAt = event.startsAt
        self.event = try JSONEncoder().encode(event)
    }

    func calendarEvent(
        checkpoint: TangledSourceRevisionRow,
        appViewHost: ATProto.PDSHost
    ) throws -> OME.CalendarEvent {
        guard let publishedArtifact = checkpoint.publishedArtifact else {
            throw OpenMusicEventAppViewStoreError.tangledSourcePublishedArtifactMissing(
                watchID: watchID
            )
        }
        var calendarEvent = try JSONDecoder().decode(OME.CalendarEvent.self, from: event)
        guard calendarEvent.source.sourceRecord?.ref == publishedArtifact.revision else {
            throw OpenMusicEventAppViewStoreError.tangledSourceRevisionMismatch(
                watchID: watchID,
                expected: publishedArtifact.revision,
                actual: calendarEvent.source.sourceRecord?.ref
            )
        }
        calendarEvent.source.appViewHost = appViewHost
        calendarEvent.source.resolvedArtifact = OME.CalendarEvent.Source.Artifact(
            url: publishedArtifact.url,
            revision: publishedArtifact.revision,
            checksumSHA256: publishedArtifact.checksumSHA256,
            byteCount: publishedArtifact.byteCount
        )
        calendarEvent.source.resolvedRepository = OME.CalendarEvent.Source.Repository(
            reference: publishedArtifact.reference,
            ref: publishedArtifact.revision
        )
        return calendarEvent
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

enum TangledSourceProjectionSchema {
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
        migrator.registerMigration("Create Tangled source calendar event projections") { database in
            let revisionTable = TangledSourceRevisionRow.tableName
            let eventTable = TangledSourceCalendarEventRow.tableName
            let browseIndex = "\(eventTable)_browse"
            try #sql(
                """
                CREATE TABLE \(quote: eventTable) (
                  "uri" TEXT PRIMARY KEY NOT NULL,
                  "watchID" TEXT NOT NULL REFERENCES \(quote: revisionTable)("watchID") ON DELETE CASCADE,
                  "startsAt" TEXT,
                  "event" BLOB NOT NULL
                ) STRICT
                """
            )
            .execute(database)
            try #sql(
                """
                CREATE INDEX \(quote: browseIndex)
                ON \(quote: eventTable) ("watchID", "startsAt", "uri")
                """
            )
            .execute(database)
        }
        migrator.registerMigration("Advertise exact Tangled source artifact URLs") { database in
            let revisionTable = TangledSourceRevisionRow.tableName
            try #sql(
                "ALTER TABLE \(quote: revisionTable) ADD COLUMN \"artifactURL\" TEXT"
            )
            .execute(database)
            try #sql(
                """
                UPDATE \(quote: revisionTable)
                SET "artifactURL" = rtrim("artifactReference", '/') || '/archive/' || "revision" || '.tar.gz'
                WHERE "artifactReference" IS NOT NULL
                  AND "artifactObjectKey" IS NOT NULL
                  AND "artifactChecksumSHA256" IS NOT NULL
                  AND "artifactByteCount" IS NOT NULL
                  AND "artifactPublishedAt" IS NOT NULL
                """
            )
            .execute(database)
        }
    }
}
