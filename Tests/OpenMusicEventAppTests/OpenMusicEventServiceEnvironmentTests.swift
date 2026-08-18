import ATProto
import ComposableArchitecture2
import ComposableCalendarEvents
import ComposableNotifications
import CustomDump
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import OpenMusicEventAuthentication
import OpenMusicEventLexicon
import SQLiteData
import Synchronization
import Testing
import XRPCClient

@testable import OpenMusicEventApp

struct OpenMusicEventServiceEnvironmentTests {
    @Test @MainActor
    func `persisted app delegate restores the selected environment`() throws {
        let suiteName = "OpenMusicEventServiceEnvironmentTests.persistedDelegate"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(
            OpenMusicEventServiceEnvironment.staging.rawValue,
            forKey: OpenMusicEventServiceEnvironment.userDefaultsKey
        )

        let appDelegate = try withDependencies {
            $0.context = .test
            try $0.bootstrapDatabase()
        } operation: {
            OpenMusicEventAppDelegate.persisted(
                variant: .generic,
                userDefaults: userDefaults
            )
        }

        expectNoDifference(appDelegate.serviceEnvironment, .staging)
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
    func `direct event installation requests use the selected staging AppView`() async throws {
        let organizerID = try #require(
            OME.Organizer.ID("did:plc:5df2u7ief6m6tn77jznicxob")
        )
        let eventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: OME.ID<OME.Event>(rawValue: "ome-workspace-2026")
        )
        let eventURI = OME.Event.reference(id: eventID).uri

        let event = try await withDependencies {
            $0.openMusicEventServiceEnvironment = .staging
            $0.httpClient = HTTPClient { request, body in
                #expect(body == nil)
                let url = try #require(request.url)
                expectNoDifference(url.host(), "stg.openmusicevent.app")
                return Data(
                    """
                    {
                      "uri": "\(eventURI)",
                      "name": "Wicked Woods 2026",
                      "locations": [],
                      "links": [],
                      "media": [],
                      "organizer": {
                        "id": "\(organizerID)"
                      },
                      "attendance": {
                        "going": 0,
                        "interested": 0,
                        "notGoing": 0
                      },
                      "source": {
                        "collection": "app.openmusicevent.event",
                        "appViewHost": "stg.openmusicevent.app"
                      }
                    }
                    """.utf8
                )
            }
            $0[XRPC.Client.self] = .liveValue
            $0.requestInterceptors = []
        } operation: {
            try await CalendarEventsClient.openMusicEvent(eventURI)
        }

        expectNoDifference(event.uri, eventURI)
        expectNoDifference(event.source.appViewHost, "stg.openmusicevent.app")
    }

    @Test @MainActor
    func `switching clears old subscriptions and replays the notification destination`() async throws {
        var dependencies = DependencyValues()
        dependencies.context = .test
        try dependencies.bootstrapDatabase()
        let database = dependencies.defaultDatabase
        let oldSubscriptionReplacements = Mutex<[Set<NotificationSubscription>]>([])
        let clearedServiceEnvironments = Mutex<[OpenMusicEventServiceEnvironment]>([])
        let newDestinations = Mutex<[Push.Destination]>([])
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
