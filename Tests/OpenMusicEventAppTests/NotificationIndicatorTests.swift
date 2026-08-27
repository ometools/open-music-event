import ATProto
import BlueskyActorCache
import ComposableArchitecture2
import ComposableNotifications
import CustomDump
import Dependencies
import Foundation
@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventWhiteLabel
import SQLiteData
import Sharing
import Synchronization
import Testing

@MainActor
@Suite(.serialized, .tcaExhaustivity(.off))
struct NotificationIndicatorTests {
    @Test
    func `installed notification-enabled comms posts contribute their unread count`() async throws {
        let database = try Self.preparedDatabase()
        let installedEventID = try Self.eventID("installed")
        let quietInstalledEventID = try Self.eventID("quiet-installed")
        let uninstalledEventID = try Self.eventID("authoring-only")

        try await database.write { database in
            try Self.insertOrganizer(database)
            try Self.insertEvent(database, id: installedEventID, name: "Installed")
            try Self.insertEvent(database, id: quietInstalledEventID, name: "Quiet")
            try Self.insertEvent(database, id: uninstalledEventID, name: "Authoring Only")
            try InstalledEventRecord.insert {
                InstalledEventRecord(id: installedEventID)
            }
            .execute(database)
            try InstalledEventRecord.insert {
                InstalledEventRecord(id: quietInstalledEventID)
            }
            .execute(database)

            try Self.insertChannel(
                database,
                eventID: installedEventID,
                channelID: "required",
                defaultState: .unsubscribed,
                notificationsRequired: true
            )
            try Self.insertPost(
                database,
                eventID: installedEventID,
                channelID: "required",
                postID: "one"
            )

            try Self.insertChannel(
                database,
                eventID: installedEventID,
                channelID: "default-on",
                defaultState: .subscribed
            )
            try Self.insertPost(
                database,
                eventID: installedEventID,
                channelID: "default-on",
                postID: "two"
            )
            let readPostID = Self.postID(
                "already-read",
                channelID: "default-on",
                eventID: installedEventID
            )
            try Self.insertPost(
                database,
                eventID: installedEventID,
                channelID: "default-on",
                postID: "already-read"
            )
            try CommsPostRead.insert { CommsPostRead(id: readPostID) }.execute(database)

            try Self.insertChannel(
                database,
                eventID: installedEventID,
                channelID: "preference-on",
                defaultState: .unsubscribed
            )
            let preferenceOnID = Self.channelID(
                "preference-on",
                eventID: installedEventID
            )
            try ChannelPreferences.insert {
                ChannelPreferences(id: preferenceOnID, notificationState: .subscribed)
            }
            .execute(database)
            try Self.insertPost(
                database,
                eventID: installedEventID,
                channelID: "preference-on",
                postID: "three"
            )

            try Self.insertChannel(
                database,
                eventID: installedEventID,
                channelID: "preference-off",
                defaultState: .subscribed
            )
            let preferenceOffID = Self.channelID(
                "preference-off",
                eventID: installedEventID
            )
            try ChannelPreferences.insert {
                ChannelPreferences(id: preferenceOffID, notificationState: .unsubscribed)
            }
            .execute(database)
            try Self.insertPost(
                database,
                eventID: installedEventID,
                channelID: "preference-off",
                postID: "excluded-by-preference"
            )

            try Self.insertChannel(
                database,
                eventID: uninstalledEventID,
                channelID: "authoring",
                defaultState: .subscribed
            )
            try Self.insertPost(
                database,
                eventID: uninstalledEventID,
                channelID: "authoring",
                postID: "excluded-by-installation-boundary"
            )
        }

        let summary = try await database.read { database in
            try ApplicationNotificationIndicatorSummaryRequest().fetch(database)
        }
        expectNoDifference(summary.totalCount, 3)
        expectNoDifference(summary.count(for: installedEventID), 3)
        expectNoDifference(summary.count(for: quietInstalledEventID), 0)
        expectNoDifference(summary.count(for: uninstalledEventID), 0)
        expectNoDifference(
            summary.contributions.map(\.id.sourceID),
            [.unreadCommsPosts]
        )

        let communicationsState = withDependencies {
            $0.context = .test
            $0.defaultEventID = installedEventID
            $0.defaultDatabase = database
        } operation: {
            CommunicationsViewer.State(eventID: installedEventID)
        }
        let channelRowsByID = Dictionary(
            uniqueKeysWithValues: communicationsState.channelRows.map { ($0.id, $0) }
        )
        expectNoDifference(
            channelRowsByID[Self.channelID("required", eventID: installedEventID)]?.unreadPostCount,
            1
        )
        expectNoDifference(
            channelRowsByID[Self.channelID("default-on", eventID: installedEventID)]?.unreadPostCount,
            1
        )
        expectNoDifference(
            channelRowsByID[Self.channelID("preference-on", eventID: installedEventID)]?.unreadPostCount,
            1
        )
        expectNoDifference(
            channelRowsByID[Self.channelID("preference-off", eventID: installedEventID)]?.unreadPostCount,
            1
        )

        let emergencyContribution = ApplicationNotificationIndicatorContribution(
            id: .init(
                sourceID: .init(rawValue: "emergency.active-alerts"),
                scopeID: OMERecord.Event.reference(id: installedEventID).uri.description
            ),
            count: 2
        )
        let multiDomainSummary = ApplicationNotificationIndicatorSummary(
            contributions: summary.contributions + [emergencyContribution]
        )
        expectNoDifference(multiDomainSummary.totalCount, 5)
        expectNoDifference(multiDomainSummary.count(for: installedEventID), 5)

        let rootState = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            OpenMusicEventAppRoot.State()
        }
        expectNoDifference(
            Set(rootState.notificationSubscriptions.map(\.sourceID.rawValue)),
            [
                OMERecord.Event.reference(id: installedEventID).uri.description,
                OMERecord.Event.reference(id: quietInstalledEventID).uri.description,
                AppRoute.event(
                    installedEventID,
                    .channel(Self.channelID("required", eventID: installedEventID).channelID)
                ).notificationRoute,
                AppRoute.event(
                    installedEventID,
                    .channel(Self.channelID("default-on", eventID: installedEventID).channelID)
                ).notificationRoute,
                AppRoute.event(
                    installedEventID,
                    .channel(Self.channelID("preference-on", eventID: installedEventID).channelID)
                ).notificationRoute,
            ]
        )
    }

    @Test
    func `authoring can delete a post and its read state`() async throws {
        let database = try Self.preparedDatabase()
        let eventID = try Self.eventID("delete-post")
        let channelID = Self.channelID("general", eventID: eventID)
        let postID = Self.postID("welcome", channelID: "general", eventID: eventID)

        try await database.write { database in
            try Self.insertOrganizer(database)
            try Self.insertEvent(database, id: eventID, name: "Delete Post")
            try Self.insertChannel(
                database,
                eventID: eventID,
                channelID: "general",
                defaultState: .subscribed
            )
            try Self.insertPost(
                database,
                eventID: eventID,
                channelID: "general",
                postID: "welcome"
            )
            try CommsPostRead.insert { CommsPostRead(id: postID) }.execute(database)
        }

        let workspace = SourceWorkspace(
            organizerID: eventID.organizerID,
            repository: "tangled.org/example/delete-post",
            branch: "main"
        )
        let grant = AuthoringGrant(
            principal: AuthoringPrincipal(
                actorID: try #require(DID(eventID.organizerID.description))
            ),
            role: .owner,
            workspaceID: workspace.id
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            let authoringGrant = Shared<AuthoringGrant?>(.defaultAuthoringGrant)
            authoringGrant.withLock { $0 = grant }
            return TestStore(
                initialState: CommunicationChannelDetail.State(
                    channelID: channelID.channelID,
                    eventID: eventID
                )
            ) {
                CommunicationChannelDetail()
            }
        }

        store.send(.postButtonTapped(postID))
        store.send(.destination(.postDetail(.deleteButtonTapped)))
        #expect(store.state.destination?.postDeleteConfirmation?.postID == postID)

        await store.send(
            .destination(
                .postDeleteConfirmation(
                    .deleteButtonTapped(postID)
                )
            )
        )?.value

        let remainingPost = try await database.read { database in
            try CommsPost.find(postID).fetchOne(database)
        }
        let remainingReadState = try await database.read { database in
            try CommsPostRead.find(postID).fetchOne(database)
        }
        #expect(remainingPost == nil)
        #expect(remainingReadState == nil)
        #expect(store.state.posts.isEmpty)
    }

    @Test
    func `channel and preference changes replace the application notification subscriptions`() async throws {
        let database = try Self.preparedDatabase()
        let eventID = try Self.eventID("festival")
        let defaultOnChannelID = Self.channelID("default-on", eventID: eventID)
        let defaultOffChannelID = Self.channelID("default-off", eventID: eventID)
        let requiredChannelID = Self.channelID("required", eventID: eventID)
        let addedChannelID = Self.channelID("added-later", eventID: eventID)
        try await database.write { database in
            try Self.insertOrganizer(database)
            try Self.insertEvent(database, id: eventID, name: "Festival")
            try InstalledEventRecord.insert { InstalledEventRecord(id: eventID) }
                .execute(database)
            try Self.insertChannel(
                database,
                eventID: eventID,
                channelID: "default-on",
                defaultState: .subscribed
            )
            try Self.insertChannel(
                database,
                eventID: eventID,
                channelID: "default-off",
                defaultState: .unsubscribed
            )
            try Self.insertChannel(
                database,
                eventID: eventID,
                channelID: "required",
                defaultState: .unsubscribed,
                notificationsRequired: true
            )
        }

        let replacements = TestMutex<[Set<NotificationSubscription>]>([])
        let store = withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database)
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

        let eventSourceID = OMERecord.Event.reference(id: eventID).uri.description
        let defaultOnSourceID = AppRoute.event(
            eventID,
            .channel(defaultOnChannelID.channelID)
        ).notificationRoute
        let defaultOffSourceID = AppRoute.event(
            eventID,
            .channel(defaultOffChannelID.channelID)
        ).notificationRoute
        let requiredSourceID = AppRoute.event(
            eventID,
            .channel(requiredChannelID.channelID)
        ).notificationRoute
        let initialSourceIDs = Set([eventSourceID, defaultOnSourceID, requiredSourceID])
        await Self.waitUntil {
            replacements.withLock { replacements in
                Set(replacements.last?.map(\.sourceID.rawValue) ?? []) == initialSourceIDs
            }
        }

        try await database.write { database in
            try ChannelPreferences.upsert {
                ChannelPreferences(
                    id: defaultOnChannelID,
                    notificationState: .unsubscribed
                )
            }
            .execute(database)
            try ChannelPreferences.upsert {
                ChannelPreferences(
                    id: defaultOffChannelID,
                    notificationState: .subscribed
                )
            }
            .execute(database)
            try ChannelPreferences.upsert {
                ChannelPreferences(
                    id: requiredChannelID,
                    notificationState: .unsubscribed
                )
            }
            .execute(database)
        }

        let updatedSourceIDs = Set([eventSourceID, defaultOffSourceID, requiredSourceID])
        await Self.waitUntil {
            replacements.withLock { replacements in
                Set(replacements.last?.map(\.sourceID.rawValue) ?? []) == updatedSourceIDs
            }
        }

        try await database.write { database in
            try Self.insertChannel(
                database,
                eventID: eventID,
                channelID: "added-later",
                defaultState: .subscribed
            )
        }
        let addedSourceID = AppRoute.event(
            eventID,
            .channel(addedChannelID.channelID)
        ).notificationRoute
        let finalSourceIDs = updatedSourceIDs.union([addedSourceID])
        await Self.waitUntil {
            replacements.withLock { replacements in
                Set(replacements.last?.map(\.sourceID.rawValue) ?? []) == finalSourceIDs
            }
        }
        expectNoDifference(
            Set(replacements.withLock { $0.last?.map(\.sourceID.rawValue) ?? [] }),
            finalSourceIDs
        )
        withExtendedLifetime(store) {}
    }

    @Test
    func `post long-press actions and opening detail share persistent read state`() async throws {
        let database = try Self.preparedDatabase()
        let eventID = try Self.eventID("festival")
        let postID = Self.postID("welcome", channelID: "general", eventID: eventID)
        try await database.write { database in
            try Self.insertOrganizer(database)
            try Self.insertEvent(database, id: eventID, name: "Festival")
            try Self.insertChannel(
                database,
                eventID: eventID,
                channelID: "general",
                defaultState: .subscribed
            )
            try Self.insertPost(
                database,
                eventID: eventID,
                channelID: "general",
                postID: "welcome"
            )
        }

        let channelStore = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            TestStore(
                initialState: CommunicationChannelDetail.State(
                    channelID: OMERecord.ID<OMERecord.Channel>(rawValue: "general"),
                    eventID: eventID
                )
            ) {
                CommunicationChannelDetail()
            }
        }

        await channelStore.send(.markPostReadButtonTapped(postID))?.value
        #expect(try await Self.isRead(postID, in: database))

        await channelStore.send(.markPostUnreadButtonTapped(postID))?.value
        #expect(try await !Self.isRead(postID, in: database))

        let postStore = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            TestStore(initialState: CommsPostDetail.State(postID: postID)) {
                CommsPostDetail()
            }
        }
        #expect(postStore.state.post?.title == "welcome")
        await postStore.send(.postBecameVisible)?.value
        #expect(try await Self.isRead(postID, in: database))
    }

    @Test
    func `channel long-press actions update every post in only that channel`() async throws {
        let database = try Self.preparedDatabase()
        let eventID = try Self.eventID("festival")
        let generalChannelID = Self.channelID("general", eventID: eventID)
        let welcomePostID = Self.postID("welcome", channelID: "general", eventID: eventID)
        let arrivalPostID = Self.postID("arrival", channelID: "general", eventID: eventID)
        let alertPostID = Self.postID("weather", channelID: "alerts", eventID: eventID)
        try await database.write { database in
            try Self.insertOrganizer(database)
            try Self.insertEvent(database, id: eventID, name: "Festival")
            try Self.insertChannel(
                database,
                eventID: eventID,
                channelID: "general",
                defaultState: .subscribed
            )
            try Self.insertChannel(
                database,
                eventID: eventID,
                channelID: "alerts",
                defaultState: .subscribed
            )
            try Self.insertPost(
                database,
                eventID: eventID,
                channelID: "general",
                postID: "welcome"
            )
            try Self.insertPost(
                database,
                eventID: eventID,
                channelID: "general",
                postID: "arrival"
            )
            try Self.insertPost(
                database,
                eventID: eventID,
                channelID: "alerts",
                postID: "weather"
            )
            try CommsPostRead.setRead(true, postID: alertPostID, in: database)
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            TestStore(initialState: CommunicationsViewer.State(eventID: eventID)) {
                CommunicationsViewer()
            }
        }

        await store.send(.markAllPostsReadButtonTapped(generalChannelID))?.value
        let readPostIDs = try await Self.readPostIDs(in: database)
        expectNoDifference(
            readPostIDs,
            Set([welcomePostID, arrivalPostID, alertPostID])
        )

        await store.send(.markAllPostsUnreadButtonTapped(generalChannelID))?.value
        let remainingReadPostIDs = try await Self.readPostIDs(in: database)
        expectNoDifference(
            remainingReadPostIDs,
            Set([alertPostID])
        )
    }

    @Test
    func `application badge replaces its absolute count when read state changes`() async throws {
        let database = try Self.preparedDatabase()
        let eventID = try Self.eventID("festival")
        let postID = Self.postID("welcome", channelID: "general", eventID: eventID)
        try await database.write { database in
            try Self.insertOrganizer(database)
            try Self.insertEvent(database, id: eventID, name: "Festival")
            try InstalledEventRecord.insert { InstalledEventRecord(id: eventID) }
                .execute(database)
            try Self.insertChannel(
                database,
                eventID: eventID,
                channelID: "general",
                defaultState: .subscribed
            )
            try Self.insertPost(
                database,
                eventID: eventID,
                channelID: "general",
                postID: "welcome"
            )
        }
        let badgeCounts = TestMutex<[Int]>([])
        let store = withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database)
            $0.applicationIconBadgeClient = ApplicationIconBadgeClient(
                setCount: { count in
                    badgeCounts.withLock { $0.append(count) }
                }
            )
        } operation: {
            Store(initialState: OpenMusicEventAppRoot.State()) {
                OpenMusicEventAppRoot()
            }
        }

        await Self.waitUntil {
            badgeCounts.withLock { $0.last } == 1
        }
        try await database.write { database in
            try CommsPostRead.setRead(true, postID: postID, in: database)
        }
        await Self.waitUntil {
            badgeCounts.withLock { $0.last } == 0
        }
        expectNoDifference(badgeCounts.withLock { $0.last }, 0)
        withExtendedLifetime(store) {}
    }

    @Test
    func `silent channel update commits a new unread post before replacing the badge`() async throws {
        let database = try Self.preparedDatabase()
        let eventID = try Self.eventID("festival")
        try await database.write { database in
            try Self.insertOrganizer(database)
            try Self.insertEvent(database, id: eventID, name: "Festival")
            try InstalledEventRecord.insert { InstalledEventRecord(id: eventID) }
                .execute(database)
            try Self.insertChannel(
                database,
                eventID: eventID,
                channelID: "general",
                defaultState: .subscribed
            )
        }
        let badgeCounts = TestMutex<[Int]>([])
        let synchronizedEventIDs = TestMutex<[OMERecord.Event.ID]>([])
        let store = withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database)
            $0.applicationIconBadgeClient = ApplicationIconBadgeClient(
                setCount: { count in
                    badgeCounts.withLock { $0.append(count) }
                }
            )
            $0.notificationsClient = NotificationsClient(
                registerDestination: { _ in },
                replaceSubscriptions: { _ in },
                synchronize: {},
                signals: { AsyncStream { $0.finish() } }
            )
            $0.omeEventInstallation = OMEEventInstallationClient(
                ensureInstalled: { _ in eventID },
                synchronizeInstalledEvent: { synchronizedEventID in
                    synchronizedEventIDs.withLock { $0.append(synchronizedEventID) }
                    try await database.write { database in
                        try Self.insertPost(
                            database,
                            eventID: eventID,
                            channelID: "general",
                            postID: "arrived-in-background"
                        )
                    }
                }
            )
        } operation: {
            Store(
                initialState: OpenMusicEventAppRoot.State(
                    variant: .whiteLabel(
                        WickedWoodsWhiteLabel.configuration(
                            organizerID: eventID.organizerID
                        )
                    )
                )
            ) {
                OpenMusicEventAppRoot()
            }
        }

        await Self.waitUntil {
            badgeCounts.withLock { $0.last } == 0
        }
        let channelSourceID = AppRoute.event(
            eventID,
            .channel(Self.channelID("general", eventID: eventID).channelID)
        ).notificationRoute
        let providerJSON = """
        {
          "aps": {
            "content-available": 1
          },
          "kind": "source_available",
          "source": "\(channelSourceID)",
          "version": "new-comms-post-1"
        }
        """
        let notificationTask = try store.state.notificationEvent(
            NotificationEvent(
                json: providerJSON,
                delivery: .contentAvailable
            )
        )
        await notificationTask?.value

        expectNoDifference(synchronizedEventIDs.withLock { $0 }, [eventID])
        expectNoDifference(badgeCounts.withLock { $0.last }, 1)
        let committedPostCount = try await database.read { database in
            try CommsPost.fetchCount(database)
        }
        expectNoDifference(committedPostCount, 1)
        withExtendedLifetime(store) {}
    }

    @Test
    func `read-state migration preserves an existing app selection`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OMERecord.DatabaseMigrations.register(into: &migrator)
        BlueskyActorCacheMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(
            database,
            upTo: "Create OpenMusicEvent user schedule schema"
        )
        let eventID = try Self.eventID("selected")
        try await database.write { database in
            try AppState.update {
                $0.organizerID = #bind(eventID.organizerID)
                $0.eventID = #bind(eventID.eventID)
            }
            .execute(database)
        }

        try migrator.migrate(database)

        let result = try await database.read { database in
            (
                try database.tableExists(CommsPostRead.tableName),
                try AppState.find(1).fetchOne(database)?.selectedEventID
            )
        }
        #expect(result.0)
        expectNoDifference(result.1, eventID)
    }

    @Test
    func `failed read-state migration leaves existing app state recoverable`() async throws {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OMERecord.DatabaseMigrations.register(into: &migrator)
        BlueskyActorCacheMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(
            database,
            upTo: "Create OpenMusicEvent user schedule schema"
        )
        let eventID = try Self.eventID("selected")
        try await database.write { database in
            try AppState.update {
                $0.organizerID = #bind(eventID.organizerID)
                $0.eventID = #bind(eventID.eventID)
            }
            .execute(database)
            try database.execute(
                sql: #"CREATE TABLE "commsPostReads" ("sentinel" TEXT NOT NULL) STRICT"#
            )
            try database.execute(
                sql: #"INSERT INTO "commsPostReads" ("sentinel") VALUES ('recoverable')"#
            )
        }

        #expect(throws: (any Error).self) {
            try migrator.migrate(database)
        }

        let result = try await database.read { database in
            (
                try AppState.find(1).fetchOne(database)?.selectedEventID,
                try String.fetchOne(
                    database,
                    sql: #"SELECT "sentinel" FROM "commsPostReads""#
                )
            )
        }
        expectNoDifference(result.0, eventID)
        expectNoDifference(result.1, "recoverable")
    }

    static func preparedDatabase() throws -> any DatabaseWriter {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OMERecord.DatabaseMigrations.register(into: &migrator)
        BlueskyActorCacheMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }

    nonisolated static func eventID(_ rawValue: String) throws -> OMERecord.Event.ID {
        OMERecord.Event.ID(
            organizerID: try #require(DID("did:web:notification-indicators.test")),
            eventID: OMERecord.ID<OMERecord.Event>(
                rawValue: ATProto.Record.Key(rawValue: rawValue)
            )
        )
    }

    nonisolated static func channelID(
        _ rawValue: String,
        eventID: OMERecord.Event.ID
    ) -> OMERecord.Channel.ID {
        OMERecord.Channel.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            channelID: OMERecord.ID<OMERecord.Channel>(
                rawValue: ATProto.Record.Key(rawValue: rawValue)
            )
        )
    }

    nonisolated static func postID(
        _ rawValue: String,
        channelID: String,
        eventID: OMERecord.Event.ID
    ) -> CommsPost.ID {
        CommsPost.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            channelID: OMERecord.ID<OMERecord.Channel>(
                rawValue: ATProto.Record.Key(rawValue: channelID)
            ),
            postID: CommsPost.PostID(rawValue)
        )
    }

    nonisolated static func insertOrganizer(_ database: Database) throws {
        let organizerID = try #require(DID("did:web:notification-indicators.test"))
        try OMERecord.Organizer.insert {
            OMERecord.Organizer.Draft(id: organizerID)
        }
        .execute(database)
    }

    nonisolated static func insertEvent(
        _ database: Database,
        id: OMERecord.Event.ID,
        name: String
    ) throws {
        try OMERecord.Event.insert {
            testEventDraft(id: id, name: name)
        }
        .execute(database)
    }

    nonisolated static func insertChannel(
        _ database: Database,
        eventID: OMERecord.Event.ID,
        channelID: String,
        defaultState: OMERecord.Channel.NotificationState,
        notificationsRequired: Bool = false
    ) throws {
        try OMERecord.Channel.insert {
            OMERecord.Channel.Draft(
                id: Self.channelID(channelID, eventID: eventID),
                name: channelID,
                description: "Updates from \(channelID)",
                iconImageURL: nil,
                headerImageURL: nil,
                sortIndex: nil,
                defaultNotificationState: defaultState,
                notificationsRequired: notificationsRequired
            )
        }
        .execute(database)
    }

    nonisolated static func insertPost(
        _ database: Database,
        eventID: OMERecord.Event.ID,
        channelID: String,
        postID: String
    ) throws {
        try CommsPost.insert {
            CommsPost(
                id: Self.postID(postID, channelID: channelID, eventID: eventID),
                title: postID,
                contents: "Post body",
                sortIndex: 0
            )
        }
        .execute(database)
    }

    static func isRead(
        _ postID: CommsPost.ID,
        in database: any DatabaseReader
    ) async throws -> Bool {
        try await database.read { database in
            try CommsPostRead.find(postID).fetchCount(database) == 1
        }
    }

    static func readPostIDs(
        in database: any DatabaseReader
    ) async throws -> Set<CommsPost.ID> {
        try await database.read { database in
            Set(try CommsPostRead.fetchAll(database).map(\.id))
        }
    }

    static func waitUntil(
        _ predicate: @escaping @Sendable () -> Bool
    ) async {
        for _ in 0..<100 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(predicate())
    }
}
