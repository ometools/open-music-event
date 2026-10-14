import ATProto
import ATProtoAppView
import ComposableNotificationsServer
import Foundation
import GRDB
import OpenMusicEventDatabase

public struct OpenMusicEventAppViewStore: WebhookInboxStore, Sendable {
    public let readiness: OpenMusicEventAppViewReadiness
    let eventBundles = EventBundleCache()
    let mapTiles = CalendarMapTileCache()
    let database: any DatabaseWriter
    let communityCalendarExcludedPublishers: [DID]
    let webhookSecretProtection: WebhookSecretProtection?

    public init(
        database: any DatabaseWriter,
        webhookSecretProtection: WebhookSecretProtection? = nil,
        geocodingOverrides: [String: CalendarEventGeocodingClient.Coordinates] = [:],
        communityCalendarExcludedPublishers: [DID] = [DID("did:plc:k6owgpe2rkkchoiivxhzp2t4")!],
        initiallyReady: Bool = true
    ) throws {
        self.database = database
        self.communityCalendarExcludedPublishers = communityCalendarExcludedPublishers
        self.webhookSecretProtection = webhookSecretProtection
        self.readiness = OpenMusicEventAppViewReadiness(
            state: initiallyReady ? .ready(cursor: nil) : .catchingUp
        )
        try Self.migrate(database)
        while try !backfillCommunityCalendarDomainBatch() {}
        try database.write { db in
            for publisher in communityCalendarExcludedPublishers {
                try db.execute(sql: "INSERT OR IGNORE INTO \"\(CalendarPublisher.tableName)\" (did) VALUES (?)",
                               arguments: [publisher.description])
            }
        }
        let geocodingOverridesChanged = try cacheGeocodingOverrides(geocodingOverrides)
        try rebuildCalendarEventBrowseProjectionIfNeeded(
            force: geocodingOverridesChanged
        )
        while try !rebuildMapBatch() {}
        while try expireMapEvents() == 500 {}
    }

    public init(
        databaseURL: URL,
        webhookSecretProtection: WebhookSecretProtection? = nil,
        geocodingOverrides: [String: CalendarEventGeocodingClient.Coordinates] = [:],
        communityCalendarExcludedPublishers: [DID] = [DID("did:plc:k6owgpe2rkkchoiivxhzp2t4")!],
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
            geocodingOverrides: geocodingOverrides,
            communityCalendarExcludedPublishers: communityCalendarExcludedPublishers,
            initiallyReady: initiallyReady
        )
    }

    private static func migrate(_ database: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        AppViewIndexMigrations.register(into: &migrator)
        EventRecordMigrations.register(into: &migrator)
        CommunityCalendarEventProjection.registerMigration(into: &migrator)
        CommunityCalendarDomainOutcome.registerMigration(into: &migrator)
        CalendarEventBrowseProjection.registerMigration(into: &migrator)
        CalendarEventBrowseSearch.registerKeyMigration(into: &migrator)
        CalendarMapBuild.registerMigration(into: &migrator)
        CalendarPublisher.registerMigration(into: &migrator)
        CalendarPublisher.registerProfileMigration(into: &migrator)
        VenueProfileProjection.registerMigration(into: &migrator)
        CalendarGeocode.registerMigration(into: &migrator)
        CalendarLocationContext.registerMigration(into: &migrator)
        CommunityCalendarEventProjection.registerBackfillMigration(into: &migrator)
        CalendarEventBrowseProjection.registerBackfillMigration(into: &migrator)
        CommunityCalendarEventProjection.registerArtworkMigration(into: &migrator)
        NotificationDatabase.registerMigrations(into: &migrator)
        TangledSourceProjectionSchema.registerMigration(into: &migrator)
        WebhookInboxSchema.registerMigration(into: &migrator)
        TangledWorkspaceProposalSchema.registerMigration(into: &migrator)
        WebhookSecretSchema.registerMigration(into: &migrator)
        try migrator.migrate(database)
    }
}

public actor OpenMusicEventAppViewReadiness {
    public enum State: Equatable, Sendable {
        case catchingUp
        case ready(cursor: UInt64?)
    }

    public init(state: State = .ready(cursor: nil)) {
        self.state = state
    }

    private var state: State
    private var expectedSubscriptionIDs: Set<String> = []
    private var readySubscriptionIDs: Set<String> = []

    public func configure(subscriptionIDs: Set<String>) {
        expectedSubscriptionIDs = subscriptionIDs
        readySubscriptionIDs = []
        state = subscriptionIDs.isEmpty ? .ready(cursor: nil) : .catchingUp
    }

    public func markCatchingUp() {
        state = .catchingUp
    }

    public func markReady(cursor: UInt64?) {
        state = .ready(cursor: cursor)
    }

    public func markReady(subscriptionID: String, cursor: UInt64?) {
        readySubscriptionIDs.insert(subscriptionID)
        guard expectedSubscriptionIDs.isSubset(of: readySubscriptionIDs) else {
            state = .catchingUp
            return
        }
        state = .ready(
            cursor: expectedSubscriptionIDs.count == 1 ? cursor : nil
        )
    }

    public func snapshot() -> State {
        state
    }
}

public enum OpenMusicEventAppViewStoreError: Error, Equatable, Sendable {
    case invalidCursor(String)
    case tangledSourceCheckpointMissing(watchID: String)
    case tangledSourcePublishedArtifactMissing(watchID: String)
    case tangledSourceWatchMismatch(watchID: String)
    case tangledSourceRevisionMismatch(watchID: String, expected: String, actual: String?)
}

public enum WebhookSecretPersistenceError: Error, Equatable, Sendable {
    case emptySecret
    case protectionUnavailable
}
