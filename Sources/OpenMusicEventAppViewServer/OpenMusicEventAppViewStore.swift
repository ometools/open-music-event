import ATProtoAppView
import ComposableNotificationsServer
import Foundation
import GRDB
import OpenMusicEventDatabase

public struct OpenMusicEventAppViewStore: WebhookInboxStore, Sendable {
    public let readiness: OpenMusicEventAppViewReadiness
    let eventBundles = EventBundleCache()
    let database: any DatabaseWriter
    let webhookSecretProtection: WebhookSecretProtection?

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

    private static func migrate(_ database: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        AppViewIndexMigrations.register(into: &migrator)
        EventRecordMigrations.register(into: &migrator)
        LegacyCommunityCalendarEventMigration.registerMigration(into: &migrator)
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
