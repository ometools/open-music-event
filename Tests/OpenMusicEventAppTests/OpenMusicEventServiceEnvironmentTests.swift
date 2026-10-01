import ATProto
import ComposableArchitecture2
import ComposableCalendarEvents
import ComposableNotifications
import CustomDump
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import OpenMusicEventAppEventViewer
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import SQLiteData
import Synchronization
import Testing

@testable import OpenMusicEventApp

struct OpenMusicEventServiceEnvironmentTests {
    @Test
    func `white label workspace identity follows the selected environment`() throws {
        let database = try makeServiceEnvironmentDatabase()
        let productionOrganizerID = try #require(
            OME.Organizer.ID("did:plc:productionfestival")
        )
        let stagingOrganizerID = try #require(
            OME.Organizer.ID("did:plc:stagingfestival")
        )
        let variant = OpenMusicEventAppVariant.whiteLabel(
            production: .init(
                configuration: WhiteLabelAppConfiguration(
                    brand: WhiteLabelBrand(displayName: "Festival"),
                    organizerID: productionOrganizerID
                )
            ),
            staging: .init(
                configuration: WhiteLabelAppConfiguration(
                    brand: WhiteLabelBrand(displayName: "Festival"),
                    organizerID: stagingOrganizerID
                )
            )
        )

        let (production, staging) = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            (
                OpenMusicEventAppRoot.State(
                    variant: variant,
                    serviceEnvironment: .production
                ),
                OpenMusicEventAppRoot.State(
                    variant: variant,
                    serviceEnvironment: .staging
                )
            )
        }

        expectNoDifference(
            production.whiteLabelRoot?.state.configuration.organizerID,
            productionOrganizerID
        )
        expectNoDifference(
            staging.whiteLabelRoot?.state.configuration.organizerID,
            stagingOrganizerID
        )
    }

    @Test
    func `canonical event installation uses the active runtime database`() async throws {
        let productionDatabase = try makeServiceEnvironmentDatabase()
        let stagingDatabase = try makeServiceEnvironmentDatabase()
        let eventID = try #require(Event.ID(
            "at://did:plc:stagingfestival/events.openmusic.event/3mrdbziccpcah"
        ))
        let programID = try #require(Program.ID(
            "at://did:plc:stagingfestival/events.openmusic.program/3mrdbziccpcah"
        ))
        let graph = try EventRecordGraph(
            event: Event(
                id: eventID,
                name: "Staging Festival 2026",
                createdAt: "2026-09-01T12:00:00Z",
                timeZone: .gmt,
                programs: [programID]
            ),
            programs: [
                Program(
                    id: programID,
                    event: eventID,
                    title: "Music",
                    createdAt: "2026-09-01T12:00:00Z",
                    eventPlaces: []
                )
            ]
        )
        try await stagingDatabase.write { db in
            try graph.upsert(in: db)
        }

        let installedEventID = try await withDependencies {
            $0.context = .test
            $0.defaultDatabase = stagingDatabase
        } operation: {
            try await EventRecordClient.testValue.install(eventID)
        }

        expectNoDifference(installedEventID, eventID)
        let stagingInstallation = try await stagingDatabase.read {
            try InstalledEvent.find(eventID).fetchOne($0)?.id
        }
        let productionInstallation = try await productionDatabase.read {
            try InstalledEvent.find(eventID).fetchOne($0)
        }

        expectNoDifference(stagingInstallation, eventID)
        #expect(productionInstallation == nil)
    }

    @Test @MainActor
    func `persisted app delegate restores the selected environment and retains injected permissions`() async throws {
        #if os(Android)
        let userDefaults = UserDefaults.standard
        let previousEnvironment = userDefaults.string(
            forKey: OpenMusicEventServiceEnvironment.userDefaultsKey
        )
        defer {
            if let previousEnvironment {
                userDefaults.set(
                    previousEnvironment,
                    forKey: OpenMusicEventServiceEnvironment.userDefaultsKey
                )
            } else {
                userDefaults.removeObject(
                    forKey: OpenMusicEventServiceEnvironment.userDefaultsKey
                )
            }
        }
        #else
        let suiteName = "OpenMusicEventServiceEnvironmentTests.persistedDelegate"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        #endif
        userDefaults.set(
            OpenMusicEventServiceEnvironment.staging.rawValue,
            forKey: OpenMusicEventServiceEnvironment.userDefaultsKey
        )

        let expectedPermissions = DevicePermissions(
            criticalAlerts: .enabled,
            notifications: .authorized
        )
        let appDelegate = try withDependencies {
            $0.context = .test
            $0.devicePermissions.load = { expectedPermissions }
            try $0.bootstrapDatabase()
        } operation: {
            #if os(Android)
            OpenMusicEventAppDelegate.persisted(variant: .generic)
            #else
            OpenMusicEventAppDelegate.persisted(
                variant: .generic,
                userDefaults: userDefaults
            )
            #endif
        }

        expectNoDifference(appDelegate.serviceEnvironment, .staging)
        let permissions = appDelegate.store.state.content.content.$permissions
        try await permissions.load()
        expectNoDifference(permissions.wrappedValue, expectedPermissions)
    }

    @Test @MainActor
    func `delegate-backed application root uses the delegate runtime`() throws {
        var dependencies = DependencyValues()
        dependencies.context = .test
        try dependencies.bootstrapDatabase()
        let notificationsClient = NotificationsClient(
            registerDestination: { _ in },
            replaceSubscriptions: { _ in },
            synchronize: {},
            signals: { AsyncStream { $0.finish() } }
        )
        let runtime = makeServiceEnvironmentRuntime(
            database: dependencies.defaultDatabase,
            environment: .staging,
            notificationsClient: notificationsClient
        )
        let appDelegate = OpenMusicEventAppDelegate(
            variant: .generic,
            environment: .staging,
            runtime: runtime
        )

        let root = OpenMusicEventApplicationRootView(appDelegate: appDelegate)

        #expect(root.appDelegate === appDelegate)
        expectNoDifference(root.activeServiceEnvironment, .staging)
    }

    @Test
    func `production and staging preserve separate application databases`() {
        let applicationSupportURL = URL(
            fileURLWithPath: "/Application Support",
            isDirectory: true
        )

        expectNoDifference(
            OpenMusicEventServiceEnvironment.production.databaseURL(
                in: applicationSupportURL
            ),
            applicationSupportURL.appendingPathComponent("open-music-event.sqlite")
        )
        expectNoDifference(
            OpenMusicEventServiceEnvironment.staging.databaseURL(
                in: applicationSupportURL
            ),
            applicationSupportURL.appendingPathComponent(
                "open-music-event-staging.sqlite"
            )
        )
    }

    @Test
    func `preparing staging dependencies installs the staging OME service environment`() throws {
        let database = try SQLiteData.defaultDatabase()
        let configuredEnvironment = withDependencies {
            $0.context = .test
            OME.prepareDependencies(
                &$0,
                database: database,
                environment: .staging
            )
        } operation: {
            @Dependency(\.openMusicEventServiceEnvironment) var environment
            return environment
        }

        expectNoDifference(configuredEnvironment, .staging)
        expectNoDifference(
            OpenMusicEventServiceEnvironment.staging.appViewHost,
            ATProto.PDSHost("stg.openmusicevent.app")
        )
    }

    @Test
    func `canonical event requests use the selected staging AppView`() async throws {
        let eventURI = try #require(Event.ID(
            "at://did:plc:5df2u7ief6m6tn77jznicxob/events.openmusic.event/3mrdbziccpcah"
        ))
        let record = try Event(
            id: eventURI,
            name: "Wicked Woods 2026",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        let response = try JSONEncoder().encode(Event.IndexedRecord(
            uri: eventURI,
            cid: nil,
            value: record.encodeLexicon()
        ))

        let event = try await withDependencies {
            $0.httpClient = HTTPClient { request, body in
                #expect(body == nil)
                let url = try #require(request.url)
                expectNoDifference(url.host(), "stg.openmusicevent.app")
                expectNoDifference(url.path(), "/xrpc/events.openmusic.getEvent")
                return response
            }
            $0[XRPC.Client.self] = .liveValue
            $0.requestInterceptors = []
        } operation: {
            try await CalendarEventsClient
                .openMusicEventAndAtmo(
                    appViewHost: OpenMusicEventServiceEnvironment.staging.appViewHost
                )
                .event(eventURI)
        }

        expectNoDifference(event.uri, eventURI)
        expectNoDifference(event.source.collection, ATProto.NSID(Event.lexiconID.rawValue))
    }
    @Test @MainActor
    func `switching clears old subscriptions and replays the notification destination`() async throws {
        var dependencies = DependencyValues()
        dependencies.context = .test
        try dependencies.bootstrapDatabase()
        let database = dependencies.defaultDatabase
        let oldSubscriptionReplacements = TestMutex<[Set<NotificationSubscription>]>([])
        let clearedServiceEnvironments = TestMutex<[OpenMusicEventServiceEnvironment]>([])
        let newDestinations = TestMutex<[Push.Destination]>([])
        let oldNotificationsClient = NotificationsClient(
            registerDestination: { _ in },
            replaceSubscriptions: { subscriptions in
                @Dependency(\.openMusicEventServiceEnvironment) var serviceEnvironment
                oldSubscriptionReplacements.withLock { $0.append(subscriptions) }
                clearedServiceEnvironments.withLock { $0.append(serviceEnvironment) }
            },
            synchronize: {},
            signals: { AsyncStream { $0.finish() } }
        )
        let newNotificationsClient = NotificationsClient(
            registerDestination: { destination in
                newDestinations.withLock { $0.append(destination) }
            },
            replaceSubscriptions: { _ in },
            synchronize: {},
            signals: { AsyncStream { $0.finish() } }
        )
        let oldStoreRuntime = makeServiceEnvironmentRuntime(
            database: database,
            environment: .staging,
            notificationsClient: NotificationsClient(
                registerDestination: { _ in },
                replaceSubscriptions: { _ in },
                synchronize: {},
                signals: { AsyncStream { $0.finish() } }
            )
        )
        let oldRuntime = OpenMusicEventApplicationRuntime(
            notificationsClient: oldNotificationsClient,
            store: oldStoreRuntime.store
        )
        let newRuntime = makeServiceEnvironmentRuntime(
            database: database,
            notificationsClient: newNotificationsClient
        )
        let destination = Push.Destination.apns(
            Push.APNS(
                applicationID: .init(rawValue: "app.openmusicevent"),
                environment: .development,
                deviceToken: .init(rawValue: "staging-device-token")
            )
        )
        let appDelegate = OpenMusicEventAppDelegate(
            variant: .generic,
            environment: .staging,
            runtime: oldRuntime
        )
        appDelegate.latestNotificationDestination = destination

        _ = try await appDelegate.activateServiceEnvironment(
            .production,
            replacementRuntime: newRuntime
        )

        expectNoDifference(
            oldSubscriptionReplacements.withLock { $0 },
            [Set<NotificationSubscription>()]
        )
        expectNoDifference(clearedServiceEnvironments.withLock { $0 }, [.staging])
        expectNoDifference(newDestinations.withLock { $0 }, [destination])
        expectNoDifference(appDelegate.serviceEnvironment, .production)
    }
}

private func makeServiceEnvironmentDatabase() throws -> any DatabaseWriter {
    let database = try SQLiteData.defaultDatabase()
    var migrator = DatabaseMigrator()
    OME.DatabaseMigrations.register(into: &migrator)
    OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
    try migrator.migrate(database)
    return database
}

@MainActor
func makeServiceEnvironmentRuntime(
    database: any DatabaseWriter,
    environment: OpenMusicEventServiceEnvironment = .production,
    notificationsClient: NotificationsClient
) -> OpenMusicEventApplicationRuntime {
    let httpClient = HTTPClient { _, _ in nil }
    return withDependencies {
        $0.context = .test
        $0.httpClient = httpClient
    } operation: {
        withDependencies {
            OME.prepareDependencies(
                &$0,
                database: database,
                environment: environment
            )
            $0.notificationsClient = notificationsClient
        } operation: {
            OpenMusicEventApplicationRuntime(
                notificationsClient: notificationsClient,
                store: StoreOf<OpenMusicEventApp>(
                    initialState: .init(
                        content: OpenMusicEventApplication.State(
                            storage: OpenMusicEventOAuth.storage
                        ) {
                            OpenMusicEventAppRoot.State()
                        }
                    )
                ) {
                    OpenMusicEventApp(
                        eventTrigger: \OpenMusicEventApplication.State.content.appDelegateEvent,
                        notificationDestinationTrigger:
                            \OpenMusicEventApplication.State.content.notificationDestination,
                        notificationEventTrigger:
                            \OpenMusicEventApplication.State.content.notificationEvent
                    ) {
                        OpenMusicEventApplication(storage: OpenMusicEventOAuth.storage) {
                            OpenMusicEventAppRoot()
                        }
                    }
                }
            )
        }
    }
}
