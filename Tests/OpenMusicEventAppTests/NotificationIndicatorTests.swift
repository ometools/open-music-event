import ATProto
import Bluesky
import ComposableArchitecture2
import ComposableNotifications
import CustomDump
import Dependencies
import Foundation
@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Sharing
import Synchronization
import Testing

@MainActor
@Suite(.serialized, .tcaExhaustivity(.off))
struct NotificationIndicatorTests {
    @Test
    func installedNotificationEnabledPostsContributeOnlyUnreadCounts() async throws {
        let database = try Self.preparedDatabase()
        let installed = Self.eventID("installed")
        let quiet = Self.eventID("quiet")
        let uninstalled = Self.eventID("uninstalled")
        try await database.write { db in
            try Self.insertEvent(db, id: installed, name: "Installed")
            try Self.insertEvent(db, id: quiet, name: "Quiet")
            try Self.insertEvent(db, id: uninstalled, name: "Uninstalled")
            try InstalledEvent.insert { InstalledEvent(id: installed) }.execute(db)
            try InstalledEvent.insert { InstalledEvent(id: quiet) }.execute(db)

            try Self.insertCategory(db, eventID: installed, name: "required",
                                    defaultState: .unsubscribed, required: true)
            try Self.insertPost(db, eventID: installed, category: "required", name: "one")
            try Self.insertCategory(db, eventID: installed, name: "default-on",
                                    defaultState: .subscribed)
            try Self.insertPost(db, eventID: installed, category: "default-on", name: "two")
            try Self.insertPost(db, eventID: installed, category: "default-on", name: "read")
            try CommsPostRead.insert {
                CommsPostRead(id: Self.postID("read", eventID: installed))
            }.execute(db)

            try Self.insertCategory(db, eventID: installed, name: "preference-on",
                                    defaultState: .unsubscribed)
            try ChannelPreferences.insert {
                ChannelPreferences(
                    id: Self.categoryID("preference-on", eventID: installed),
                    notificationState: .subscribed
                )
            }.execute(db)
            try Self.insertPost(db, eventID: installed, category: "preference-on", name: "three")
            try Self.insertCategory(db, eventID: installed, name: "preference-off",
                                    defaultState: .subscribed)
            try ChannelPreferences.insert {
                ChannelPreferences(
                    id: Self.categoryID("preference-off", eventID: installed),
                    notificationState: .unsubscribed
                )
            }.execute(db)
            try Self.insertPost(db, eventID: installed, category: "preference-off", name: "excluded")
            try Self.insertCategory(db, eventID: uninstalled, name: "general",
                                    defaultState: .subscribed)
            try Self.insertPost(db, eventID: uninstalled, category: "general", name: "other")
        }

        let summary = try await database.read {
            try ApplicationNotificationIndicatorSummaryRequest().fetch($0)
        }
        expectNoDifference(summary.totalCount, 3)
        expectNoDifference(summary.count(for: installed), 3)
        expectNoDifference(summary.count(for: quiet), 0)
        expectNoDifference(summary.count(for: uninstalled), 0)

        let rows = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = installed
        } operation: {
            SocialCategoryList.State(eventID: installed).channelRows
        }
        let unreadByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.unreadPostCount) })
        expectNoDifference(unreadByID[Self.categoryID("required", eventID: installed)], 1)
        expectNoDifference(unreadByID[Self.categoryID("default-on", eventID: installed)], 1)
        expectNoDifference(unreadByID[Self.categoryID("preference-on", eventID: installed)], 1)
        expectNoDifference(unreadByID[Self.categoryID("preference-off", eventID: installed)], 1)

        let root = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            OpenMusicEventAppRoot.State()
        }
        let sourceIDs = Set(root.notificationSubscriptions.map { $0.sourceID.rawValue })
        expectNoDifference(sourceIDs, Set([
            installed.description,
            quiet.description,
            AppRoute.event(installed, .channel(Self.categoryID("required", eventID: installed)))
                .notificationRoute,
            AppRoute.event(installed, .channel(Self.categoryID("default-on", eventID: installed)))
                .notificationRoute,
            AppRoute.event(installed, .channel(Self.categoryID("preference-on", eventID: installed)))
                .notificationRoute
        ]))
    }

    @Test
    func categoryPreferencesReplaceApplicationSubscriptions() async throws {
        let database = try Self.preparedDatabase()
        let eventID = Self.eventID("festival")
        let on = Self.categoryID("default-on", eventID: eventID)
        let off = Self.categoryID("default-off", eventID: eventID)
        let required = Self.categoryID("required", eventID: eventID)
        let added = Self.categoryID("added", eventID: eventID)
        try await database.write { db in
            try Self.insertEvent(db, id: eventID, name: "Festival")
            try InstalledEvent.insert { InstalledEvent(id: eventID) }.execute(db)
            try Self.insertCategory(db, eventID: eventID, name: "default-on",
                                    defaultState: .subscribed)
            try Self.insertCategory(db, eventID: eventID, name: "default-off",
                                    defaultState: .unsubscribed)
            try Self.insertCategory(db, eventID: eventID, name: "required",
                                    defaultState: .subscribed, required: true)
        }

        let replacements = TestMutex<[Set<NotificationSubscription>]>([])
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.notificationsClient = NotificationsClient(
                registerDestination: { _ in },
                replaceSubscriptions: { subscriptions in
                    replacements.withLock { $0.append(subscriptions) }
                },
                synchronize: {},
                signals: { AsyncStream { $0.finish() } }
            )
        } operation: {
            Store(initialState: OpenMusicEventAppRoot.State()) {
                OpenMusicEventAppRoot()
            }
        }
        let route: (Social.Category.ID) -> String = {
            AppRoute.event(eventID, .channel($0)).notificationRoute
        }
        let initial = Set([eventID.description, route(on), route(required)])
        await Self.waitUntil {
            Set(replacements.withLock { $0.last?.map { $0.sourceID.rawValue } ?? [] }) == initial
        }

        try await database.write { db in
            try ChannelPreferences.upsert {
                ChannelPreferences(id: on, notificationState: .unsubscribed)
            }.execute(db)
            try ChannelPreferences.upsert {
                ChannelPreferences(id: off, notificationState: .subscribed)
            }.execute(db)
            try ChannelPreferences.upsert {
                ChannelPreferences(id: required, notificationState: .unsubscribed)
            }.execute(db)
        }
        let updated = Set([eventID.description, route(off), route(required)])
        await Self.waitUntil {
            Set(replacements.withLock { $0.last?.map { $0.sourceID.rawValue } ?? [] }) == updated
        }

        try await database.write { db in
            try Self.insertCategory(db, eventID: eventID, name: "added",
                                    defaultState: .subscribed)
        }
        let final = updated.union([route(added)])
        await Self.waitUntil {
            Set(replacements.withLock { $0.last?.map { $0.sourceID.rawValue } ?? [] }) == final
        }
        withExtendedLifetime(store) {}
    }

    @Test
    func postActionsAndDetailSharePersistentReadState() async throws {
        let database = try Self.preparedDatabase()
        let eventID = Self.eventID("festival")
        let categoryID = Self.categoryID("general", eventID: eventID)
        let postID = Self.postID("welcome", eventID: eventID)
        try await database.write { db in
            try Self.insertEvent(db, id: eventID, name: "Festival")
            try Self.insertCategory(db, eventID: eventID, name: "general",
                                    defaultState: .subscribed)
            try Self.insertPost(db, eventID: eventID, category: "general", name: "welcome")
        }

        let channel = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            TestStore(
                initialState: SocialCategoryDetail.State(
                    channelID: categoryID, eventID: eventID
                )
            ) { SocialCategoryDetail() }
        }
        await channel.send(.markPostReadButtonTapped(postID))?.value
        #expect(try await Self.isRead(postID, in: database))
        await channel.send(.markPostUnreadButtonTapped(postID))?.value
        #expect(try await !Self.isRead(postID, in: database))

        let detail = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            TestStore(initialState: SocialPostDetail.State(postID: postID, eventID: eventID)) {
                SocialPostDetail()
            }
        }
        #expect(detail.state.post?.title == "welcome")
        await detail.send(.postBecameVisible)?.value
        #expect(try await Self.isRead(postID, in: database))
    }

    @Test
    func categoryReadActionsAffectOnlyItsPosts() async throws {
        let database = try Self.preparedDatabase()
        let eventID = Self.eventID("festival")
        let general = Self.categoryID("general", eventID: eventID)
        let welcome = Self.postID("welcome", eventID: eventID)
        let arrival = Self.postID("arrival", eventID: eventID)
        let weather = Self.postID("weather", eventID: eventID)
        try await database.write { db in
            try Self.insertEvent(db, id: eventID, name: "Festival")
            try Self.insertCategory(db, eventID: eventID, name: "general",
                                    defaultState: .subscribed)
            try Self.insertCategory(db, eventID: eventID, name: "alerts",
                                    defaultState: .subscribed)
            try Self.insertPost(db, eventID: eventID, category: "general", name: "welcome")
            try Self.insertPost(db, eventID: eventID, category: "general", name: "arrival")
            try Self.insertPost(db, eventID: eventID, category: "alerts", name: "weather")
            try CommsPostRead.setRead(true, postID: weather, in: db)
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            TestStore(initialState: SocialCategoryList.State(eventID: eventID)) {
                SocialCategoryList()
            }
        }
        await store.send(.markAllPostsReadButtonTapped(general))?.value
        let readAfterMarkingAll = try await Self.readPostIDs(in: database)
        expectNoDifference(readAfterMarkingAll, Set([welcome, arrival, weather]))
        await store.send(.markAllPostsUnreadButtonTapped(general))?.value
        let readAfterMarkingUnread = try await Self.readPostIDs(in: database)
        expectNoDifference(readAfterMarkingUnread, Set([weather]))
    }

    @Test
    func authoringDeletesPostAndItsReadState() async throws {
        let database = try Self.preparedDatabase()
        let eventID = Self.eventID("festival")
        let categoryID = Self.categoryID("general", eventID: eventID)
        let postID = Self.postID("welcome", eventID: eventID)
        try await database.write { db in
            try Self.insertEvent(db, id: eventID, name: "Festival")
            try Self.insertCategory(db, eventID: eventID, name: "general",
                                    defaultState: .subscribed)
            try Self.insertPost(db, eventID: eventID, category: "general", name: "welcome")
            try CommsPostRead.insert { CommsPostRead(id: postID) }.execute(db)
        }
        let baseline = try CanonicalWorkspaceBaseline.openOrCapture(
            at: FileManager.default.temporaryDirectory
                .appending(path: "OME-DeletePost-\(UUID()).sqlite").path,
            from: database
        )
        let session = EventWorkspaceSession(
            eventID: eventID,
            actorID: Self.organizerDID,
            baseline: baseline
        )
        let oauth = canonicalWorkspaceTestOAuthSession(actorID: Self.organizerDID)
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.getOptionalDefaultSession = { oauth }
        } operation: {
            Shared<EventWorkspaceSession?>(.defaultEventWorkspaceSession)
                .withLock { $0 = session }
            return TestStore(
                initialState: SocialCategoryDetail.State(
                    channelID: categoryID, eventID: eventID
                )
            ) { SocialCategoryDetail() }
        }

        store.send(.postButtonTapped(postID))
        store.send(.destination(.postDetail(.deleteButtonTapped)))
        #expect(store.state.destination?.postDeleteConfirmation?.postID == postID)
        await store.send(
            .destination(.postDeleteConfirmation(.deleteButtonTapped(postID)))
        )?.value

        let saved = try await database.read { db in
            (
                try Social.Post.find(postID).fetchOne(db),
                try CommsPostRead.find(postID).fetchOne(db)
            )
        }
        #expect(saved.0 == nil)
        #expect(saved.1 == nil)
        #expect(store.state.posts.isEmpty)
    }

    @Test
    func badgeFollowsCommittedCanonicalPostAndReadState() async throws {
        let database = try Self.preparedDatabase()
        let eventID = Self.eventID("festival")
        let postID = Self.postID("welcome", eventID: eventID)
        try await database.write { db in
            try Self.insertEvent(db, id: eventID, name: "Festival")
            try InstalledEvent.insert { InstalledEvent(id: eventID) }.execute(db)
            try Self.insertCategory(db, eventID: eventID, name: "general",
                                    defaultState: .subscribed)
        }
        let counts = TestMutex<[Int]>([])
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.applicationIconBadgeClient = ApplicationIconBadgeClient(
                setCount: { count in counts.withLock { $0.append(count) } }
            )
        } operation: {
            Store(initialState: OpenMusicEventAppRoot.State()) {
                OpenMusicEventAppRoot()
            }
        }
        await Self.waitUntil { counts.withLock { $0.last } == 0 }

        try await database.write { db in
            try Self.insertPost(db, eventID: eventID, category: "general", name: "welcome")
        }
        await Self.waitUntil { counts.withLock { $0.last } == 1 }
        try await database.write { db in
            try CommsPostRead.setRead(true, postID: postID, in: db)
        }
        await Self.waitUntil { counts.withLock { $0.last } == 0 }
        withExtendedLifetime(store) {}
    }

    static let organizerDID = DID("did:plc:notificationindicators")!

    static func preparedDatabase() throws -> any DatabaseWriter {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        BlueskyActorCacheMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }

    nonisolated static func key(_ name: String) -> String {
        switch name {
        case "installed": "3mrdbziccpcah"
        case "quiet": "3mrdbziccpcaj"
        case "uninstalled": "3mrdbziccpcak"
        case "festival": "3mrdbziccpcam"
        case "required": "3mrdbziccpcan"
        case "default-on": "3mrdbziccpcap"
        case "default-off": "3mrdbziccpcar"
        case "preference-on": "3mrdbziccpcas"
        case "preference-off": "3mrdbziccpcat"
        case "general": "3mrdbziccpcau"
        case "alerts": "3mrdbziccpcav"
        case "added": "3mrdbziccpcaw"
        case "one": "3mrdbziccpcax"
        case "two": "3mrdbziccpcay"
        case "read": "3mrdbziccpcaz"
        case "three": "3mrdbziccpcba"
        case "excluded": "3mrdbziccpcbb"
        case "other": "3mrdbziccpcbc"
        case "welcome": "3mrdbziccpcbd"
        case "arrival": "3mrdbziccpcbe"
        case "weather": "3mrdbziccpcbf"
        default: preconditionFailure("Unexpected fixture record: " + name)
        }
    }

    nonisolated static func eventID(_ name: String) -> Event.ID {
        Event.ID("at://did:plc:notificationindicators/events.openmusic.event/" + key(name))!
    }

    nonisolated static func categoryID(_ name: String, eventID: Event.ID) -> Social.Category.ID {
        Social.Category.ID(
            "at://" + eventID.authority.description + "/social.ome.category/" + key(name)
        )!
    }

    nonisolated static func postID(_ name: String, eventID: Event.ID) -> Social.Post.ID {
        Social.Post.ID(
            "at://" + eventID.authority.description + "/social.ome.post/" + key(name)
        )!
    }

    nonisolated static func insertEvent(_ db: Database, id: Event.ID, name: String) throws {
        let event = try Event(
            id: id, name: name, createdAt: "2026-09-01T12:00:00Z", timeZone: .gmt
        )
        try Event.insert { event }.execute(db)
    }

    nonisolated static func insertCategory(
        _ db: Database,
        eventID: Event.ID,
        name: String,
        defaultState: Social.Category.NotificationState,
        required: Bool = false
    ) throws {
        var category = try Social.Category(
            id: categoryID(name, eventID: eventID),
            event: eventID,
            name: name,
            createdAt: "2026-09-01T12:00:00Z"
        )
        category.defaultNotificationState = .known(required ? .subscribed : defaultState)
        category.notificationsRequired = required
        try Social.Category.insert { category }.execute(db)
        var event = try #require(try Event.find(eventID).fetchOne(db))
        event.categories = (event.categories ?? []) + [category.id]
        try Event.upsert { event }.execute(db)
    }

    nonisolated static func insertPost(
        _ db: Database, eventID: Event.ID, category: String, name: String
    ) throws {
        var post = try Social.Post(
            id: postID(name, eventID: eventID),
            text: "Post body",
            event: eventID,
            category: categoryID(category, eventID: eventID),
            createdAt: "2026-09-01T12:00:00Z"
        )
        post.title = name
        try Social.Post.insert { post }.execute(db)
    }

    static func isRead(
        _ postID: Social.Post.ID, in database: any DatabaseReader
    ) async throws -> Bool {
        try await database.read {
            try CommsPostRead.find(postID).fetchCount($0) == 1
        }
    }

    static func readPostIDs(in database: any DatabaseReader) async throws -> Set<Social.Post.ID> {
        try await database.read {
            Set(try CommsPostRead.fetchAll($0).map { $0.id })
        }
    }

    static func waitUntil(_ predicate: @escaping @Sendable () -> Bool) async {
        for _ in 0..<100 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(predicate())
    }
}
