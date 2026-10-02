import ATProto
import Bluesky
import Clocks
import ComposableAtmosphereUserInput
import ComposableAtmosphereUserInputUI
import ComposableArchitecture2
import ComposableNotifications
import ComposableWorkspace
import CustomDump
import Dependencies
import ErrorHandling
import Foundation
import HTTPClient
import HTTPTypes
import IssueReporting
import ATProtoTypes
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
import Testing
import ATProto

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventEditors

@Suite
struct TechnicalDetailsTests {
    @Test
    func `technical details are hidden by default and enabled by the setting`() {
        // A fresh install does not surface raw implementation details.
        expectNoDifference(
            TechnicalDetails.isVisible(userPreference: false, environment: [:]),
            false
        )

        // The user can explicitly opt in from Settings.
        expectNoDifference(
            TechnicalDetails.isVisible(userPreference: true, environment: [:]),
            true
        )
    }

    @Test
    func `environment variable overrides the persisted setting`() {
        // A development launch can force technical details on.
        expectNoDifference(
            TechnicalDetails.isVisible(
                userPreference: false,
                environment: ["OME_SHOW_TECHNICAL_DETAILS": "true"]
            ),
            true
        )

        // An explicit off value wins even when the user preference was previously enabled.
        expectNoDifference(
            TechnicalDetails.isVisible(
                userPreference: true,
                environment: ["OME_SHOW_TECHNICAL_DETAILS": "0"]
            ),
            false
        )
    }

    @Test
    func `account presentation does not fall back to a DID unless opted in`() {
        let did = "did:plc:alice123"

        // Without a profile or handle, the ordinary surface stays human-facing.
        expectNoDifference(
            TechnicalDetails.identityTitle(
                displayName: nil,
                handle: nil,
                technicalID: did,
                isVisible: false
            ),
            "Account"
        )
        expectNoDifference(
            TechnicalDetails.identitySubtitle(
                displayName: nil,
                handle: nil,
                technicalID: did,
                isVisible: false
            ),
            nil
        )

        // Opting in restores the exact account identifier.
        expectNoDifference(
            TechnicalDetails.identityTitle(
                displayName: nil,
                handle: nil,
                technicalID: did,
                isVisible: true
            ),
            did
        )
    }

    @Test
    func `account presentation keeps friendly names and handles when details are hidden`() {
        expectNoDifference(
            TechnicalDetails.identityTitle(
                displayName: "Alice",
                handle: "alice.example",
                technicalID: "did:plc:alice123",
                isVisible: false
            ),
            "Alice"
        )
        expectNoDifference(
            TechnicalDetails.identitySubtitle(
                displayName: "Alice",
                handle: "alice.example",
                technicalID: "did:plc:alice123",
                isVisible: false
            ),
            "@alice.example"
        )
    }

    @Test
    func `performance editor does not turn an account identifier into a display name`() throws {
        let actor = try #require(DID("did:plc:alice123"))
        let state = ContributorRelationshipPicker.State()
        let selection = ContributorRelationshipPicker.Selection.identityOnly(
            actor: actor,
            displayTitle: nil
        )

        // The ordinary authoring surface remains human-facing.
        expectNoDifference(
            state.summary(for: selection, showsTechnicalDetails: false)?.title,
            "Account"
        )

        // The raw identifier is still available after an explicit opt-in.
        expectNoDifference(
            state.summary(for: selection, showsTechnicalDetails: true)?.title,
            actor.description
        )
    }
}

@MainActor
@Suite(.serialized, .tcaExhaustivity(.off))
struct SettingsFeatureTests {
    @Test
    func `Wicked Woods supports Critical Alerts without exposing them in generic OME`() {
        expectNoDifference(
            OpenMusicEventAppConfiguration.wickedWoods.supportsCriticalAlerts,
            true
        )
        expectNoDifference(
            OpenMusicEventAppConfiguration.openMusicEvent.supportsCriticalAlerts,
            false
        )
    }

    #if canImport(UserNotifications)
    @Test
    func `notification authorization retains native iOS status semantics`() {
        expectNoDifference(UNAuthorizationStatus.notDetermined.devicePermissionAuthorization, .unknown)
        expectNoDifference(UNAuthorizationStatus.denied.devicePermissionAuthorization, .denied)
        expectNoDifference(UNAuthorizationStatus.authorized.devicePermissionAuthorization, .authorized)
        expectNoDifference(UNAuthorizationStatus.provisional.devicePermissionAuthorization, .limited)
        #if os(iOS)
        expectNoDifference(UNAuthorizationStatus.ephemeral.devicePermissionAuthorization, .limited)
        #endif
    }

    @Test
    func `an entitled app can request Critical Alerts before authorization exists`() {
        expectNoDifference(
            UNNotificationSetting.notSupported.devicePermissionAuthorization(
                supportsCriticalAlerts: true
            ),
            .disabled
        )
        expectNoDifference(
            UNNotificationSetting.notSupported.devicePermissionAuthorization(
                supportsCriticalAlerts: false
            ),
            .unavailable
        )
    }
    #endif

    @Test
    func `clean authoring exit proceeds without a destructive prompt`() async throws {
        let fixture = try await makeEventSettingsAuthoringExitFixture(isDirty: false)
        let store = fixture.store
        let changes = try await fixture.database.read { db in
            try CanonicalWorkspaceRecordChanges.changes(
                eventID: fixture.eventID,
                in: db,
                referenceDatabase: fixture.baseline
            )
        }
        #expect(changes.isEmpty)

        let exit = store.send(.exitAuthoringButtonTapped)
        await store.receive(
            key: AuthoringExitRequested.self,
            value: TestStoreMatcher<Void>(matching: { _ in true }),
            timeout: .seconds(1)
        )
        await exit?.value

        #expect(store.destination == nil)
    }

    @Test
    func `unpublished changes require confirmation and cancel keeps editing`() async throws {
        let fixture = try await makeEventSettingsAuthoringExitFixture(isDirty: true)
        let store = fixture.store

        await store.send(.exitAuthoringButtonTapped)?.value
        #expect(store.destination?.exitAuthoringConfirmation != nil)

        store.send(
            .destination(
                .exitAuthoringConfirmation(.cancelButtonTapped)
            )
        )

        #expect(store.destination == nil)
        #expect(fixture.session.wrappedValue != nil)
        let eventName = try await fixture.database.read { db in
            try Event.find(fixture.eventID).fetchOne(db)?.name
        }
        expectNoDifference(eventName, "Unpublished Event Name")
    }

    @Test
    func `confirming unpublished changes requests the guarded authoring exit`() async throws {
        let fixture = try await makeEventSettingsAuthoringExitFixture(isDirty: true)
        let store = fixture.store

        await store.send(.exitAuthoringButtonTapped)?.value
        #expect(store.destination?.exitAuthoringConfirmation != nil)

        let confirmation = store.send(
            .destination(
                .exitAuthoringConfirmation(.exitAndDeleteButtonTapped)
            )
        )
        await store.receive(
            key: AuthoringExitRequested.self,
            value: TestStoreMatcher<Void>(matching: { _ in true }),
            timeout: .seconds(1)
        )
        await confirmation?.value

        #expect(store.destination == nil)
    }

    @Test
    func configuredFeedbackBoardMapsToUserInputConfiguration() throws {
        let configuration = try #require(
            OpenMusicEventAppConfiguration.openMusicEvent
                .productFeedbackBoard?
                .userInputConfiguration
        )

        expectNoDifference(
            configuration.space.uri.description,
            "at://did:plc:42p4f3krv45gtkxjooaekbnw/app.userinput.space/3moixlle7bs25"
        )
        expectNoDifference(
            configuration.externalURL,
            URL(
                string: "https://userinput.app/s/did:plc:42p4f3krv45gtkxjooaekbnw/3moixlle7bs25"
            )
        )
    }

    @Test
    func missingFeedbackBoardDoesNotCreateDestination() throws {
        let database = try makePreparedDatabase()
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.openMusicEventAppConfiguration = OpenMusicEventAppConfiguration(
                productFeedbackBoard: nil
            )
        } operation: {
            TestStore(initialState: Settings.State()) {
                Settings()
            }
        }

        #expect(!store.showsFeedbackBoard)
        store.send(.feedbackButtonTapped)
        #expect(store.destination == nil)
    }

    @Test
    func testErrorButtonReportsGlobalError() async throws {
        let database = try makePreparedDatabase()
        let store = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: SettingsErrorHost.State()) {
                SettingsErrorHost()
            }
        }

        await withIssueReporters([]) {
            await store.send(to: \.settings, .testErrorButtonTapped)?.value
        }

        await waitForLatestError(in: store.state.errorNotifications)
        let latestError = store.state.errorNotifications.state.latestError
        #expect(latestError?.kind == .settingsTestError)
        #expect(latestError?.message.fallback == "Test error.")
        #expect(latestError?.operation == .settingsTestError)
        #expect(latestError?.debugDescription == "Settings test error")
    }

    @Test
    func eventSettingsTestErrorButtonReportsGlobalError() async throws {
        try await TestExhaustivity.$current.withValue(.off) {
            let database = try makePreparedDatabase()
            let store: TestStore<EventSettingsErrorHost> = withDependencies {
                $0.defaultDatabase = database
            } operation: {
                TestStore(initialState: EventSettingsErrorHost.State()) {
                    EventSettingsErrorHost()
                }
            }

            await withIssueReporters([]) {
                await store.send(
                    to: \.eventSettings,
                    EventSettings.Action.testErrorButtonTapped
                )?.value
            }

            await waitForLatestError(in: store.state.errorNotifications)
            let latestError = store.state.errorNotifications.state.latestError
            #expect(latestError?.kind.rawValue == "event.settings.test-error")
            #expect(latestError?.message.fallback == "Test error.")
            #expect(latestError?.operation.rawValue == "event.settings.test-error")
            #expect(latestError?.debugDescription == "Event settings test error")
        }
    }

    @Test
    func `Event Settings requests notification permission and reloads the system status`() async throws {
        let database = try makePreparedDatabase()
        let permissionWasRequested = TestMutex(false)
        let loadCount = TestMutex(0)
        let client = DevicePermissionsClient(
            load: {
                loadCount.withLock { $0 += 1 }
                return DevicePermissions(
                    notifications: permissionWasRequested.withLock {
                        $0 ? .authorized : .unknown
                    }
                )
            },
            openNotificationSettings: { false },
            requestCriticalAlerts: { .unavailable },
            requestNotifications: {
                permissionWasRequested.withLock { $0 = true }
                return .authorized
            }
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.devicePermissions = client
        } operation: {
            TestStore(initialState: EventSettings.State(eventID: canonicalSettingsEventID)) {
                EventSettings()
            }
        }

        try await store.state.$permissions.load()
        expectNoDifference(store.state.permissions.notifications, .unknown)
        let loadsBeforeRequest = loadCount.withLock { $0 }

        await store.send(.notificationPermissionButtonTapped)?.value

        expectNoDifference(permissionWasRequested.withLock { $0 }, true)
        expectNoDifference(store.state.permissions.notifications, .authorized)
        expectNoDifference(loadCount.withLock { $0 }, loadsBeforeRequest + 1)
    }

    @Test
    func `Event Settings requests Critical Alerts separately and reloads the system status`() async throws {
        let database = try makePreparedDatabase()
        let criticalAlertsWereRequested = TestMutex(false)
        let loadCount = TestMutex(0)
        let client = DevicePermissionsClient(
            load: {
                loadCount.withLock { $0 += 1 }
                return DevicePermissions(
                    criticalAlerts: criticalAlertsWereRequested.withLock {
                        $0 ? .enabled : .disabled
                    },
                    notifications: .authorized
                )
            },
            openNotificationSettings: { false },
            requestCriticalAlerts: {
                criticalAlertsWereRequested.withLock { $0 = true }
                return .enabled
            },
            requestNotifications: { .authorized }
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.devicePermissions = client
        } operation: {
            TestStore(initialState: EventSettings.State(eventID: canonicalSettingsEventID)) {
                EventSettings()
            }
        }

        // Ordinary notifications are already allowed, but Critical Alerts are still off.
        try await store.state.$permissions.load()
        expectNoDifference(store.state.permissions.notifications, .authorized)
        expectNoDifference(store.state.permissions.criticalAlerts, .disabled)
        let loadsBeforeRequest = loadCount.withLock { $0 }

        // The Critical Alerts button requests only that permission and reloads system state.
        await store.send(.criticalAlertPermissionButtonTapped)?.value

        expectNoDifference(criticalAlertsWereRequested.withLock { $0 }, true)
        expectNoDifference(store.state.permissions.notifications, .authorized)
        expectNoDifference(store.state.permissions.criticalAlerts, .enabled)
        expectNoDifference(loadCount.withLock { $0 }, loadsBeforeRequest + 1)
    }

    @Test
    func `Event Settings requests notifications before Critical Alerts when setup has not started`() async throws {
        let database = try makePreparedDatabase()
        let criticalAlertRequestCount = TestMutex(0)
        let notificationRequestCount = TestMutex(0)
        let notificationsWereRequested = TestMutex(false)
        let client = DevicePermissionsClient(
            load: {
                DevicePermissions(
                    criticalAlerts: .disabled,
                    notifications: notificationsWereRequested.withLock {
                        $0 ? .authorized : .unknown
                    }
                )
            },
            openNotificationSettings: { false },
            requestCriticalAlerts: {
                criticalAlertRequestCount.withLock { $0 += 1 }
                return .enabled
            },
            requestNotifications: {
                notificationRequestCount.withLock { $0 += 1 }
                notificationsWereRequested.withLock { $0 = true }
                return .authorized
            }
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.devicePermissions = client
        } operation: {
            TestStore(initialState: EventSettings.State(eventID: canonicalSettingsEventID)) {
                EventSettings()
            }
        }

        try await store.state.$permissions.load()
        expectNoDifference(store.state.permissions.notifications, .unknown)
        expectNoDifference(store.state.permissions.criticalAlerts, .disabled)

        await store.send(.criticalAlertPermissionButtonTapped)?.value

        expectNoDifference(notificationRequestCount.withLock { $0 }, 1)
        expectNoDifference(criticalAlertRequestCount.withLock { $0 }, 0)
        expectNoDifference(store.state.permissions.notifications, .authorized)
        expectNoDifference(store.state.permissions.criticalAlerts, .disabled)
    }

    @Test
    func `Event Settings raises an indicator for unfinished notification setup`() throws {
        let database = try makePreparedDatabase()

        expectNoDifference(
            DevicePermissions(notifications: .unknown).notificationSetupBadgeValue,
            1
        )
        expectNoDifference(
            DevicePermissions(
                criticalAlerts: .disabled,
                notifications: .authorized
            ).notificationSetupBadgeValue,
            1
        )
        expectNoDifference(
            DevicePermissions(
                criticalAlerts: .disabled,
                notifications: .limited
            ).notificationSetupBadgeValue,
            1
        )
        expectNoDifference(
            DevicePermissions(
                criticalAlerts: .enabled,
                notifications: .authorized
            ).notificationSetupBadgeValue,
            nil
        )
        expectNoDifference(
            DevicePermissions(
                criticalAlerts: .unavailable,
                notifications: .authorized
            ).notificationSetupBadgeValue,
            nil
        )
        expectNoDifference(
            DevicePermissions(
                criticalAlerts: .disabled,
                notifications: .denied
            ).notificationSetupBadgeValue,
            nil
        )
        expectNoDifference(
            DevicePermissions(
                criticalAlerts: .disabled,
                notifications: .restricted
            ).notificationSetupBadgeValue,
            nil
        )

        let settings = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            EventSettings.State(eventID: canonicalSettingsEventID)
        }
        expectNoDifference(settings.notificationIndicatorValue, 1)

        #expect(DevicePermissions(notifications: .authorized).notificationsAreAllowed)
        #expect(DevicePermissions(notifications: .limited).notificationsAreAllowed)
        #expect(!DevicePermissions(notifications: .unknown).notificationsAreAllowed)
        #expect(!DevicePermissions(notifications: .denied).notificationsAreAllowed)
        #expect(!DevicePermissions(notifications: .restricted).notificationsAreAllowed)
    }

    @Test
    func `Event Settings opens system settings when denied notifications are managed`() async throws {
        let database = try makePreparedDatabase()
        let settingsOpenCount = TestMutex(0)
        let requestCount = TestMutex(0)
        let client = DevicePermissionsClient(
            load: { DevicePermissions(notifications: .denied) },
            openNotificationSettings: {
                settingsOpenCount.withLock { $0 += 1 }
                return true
            },
            requestCriticalAlerts: { .unavailable },
            requestNotifications: {
                requestCount.withLock { $0 += 1 }
                return .denied
            }
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.devicePermissions = client
        } operation: {
            TestStore(initialState: EventSettings.State(eventID: canonicalSettingsEventID)) {
                EventSettings()
            }
        }

        try await store.state.$permissions.load()
        expectNoDifference(store.state.permissions.notifications, .denied)

        await store.send(.notificationPermissionButtonTapped)?.value

        expectNoDifference(settingsOpenCount.withLock { $0 }, 1)
        expectNoDifference(requestCount.withLock { $0 }, 0)
    }

    @Test
    func `Event Settings opens system settings to manage allowed notifications`() async throws {
        let database = try makePreparedDatabase()
        let settingsOpenCount = TestMutex(0)
        let requestCount = TestMutex(0)
        let client = DevicePermissionsClient(
            load: { DevicePermissions(notifications: .authorized) },
            openNotificationSettings: {
                settingsOpenCount.withLock { $0 += 1 }
                return true
            },
            requestCriticalAlerts: { .unavailable },
            requestNotifications: {
                requestCount.withLock { $0 += 1 }
                return .authorized
            }
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.devicePermissions = client
        } operation: {
            TestStore(initialState: EventSettings.State(eventID: canonicalSettingsEventID)) {
                EventSettings()
            }
        }

        try await store.state.$permissions.load()
        expectNoDifference(store.state.permissions.notifications, .authorized)

        await store.send(.notificationPermissionButtonTapped)?.value

        expectNoDifference(settingsOpenCount.withLock { $0 }, 1)
        expectNoDifference(requestCount.withLock { $0 }, 0)
    }

    @Test
    func `Event Settings opens system settings to manage enabled Critical Alerts`() async throws {
        let database = try makePreparedDatabase()
        let settingsOpenCount = TestMutex(0)
        let requestCount = TestMutex(0)
        let client = DevicePermissionsClient(
            load: {
                DevicePermissions(
                    criticalAlerts: .enabled,
                    notifications: .authorized
                )
            },
            openNotificationSettings: {
                settingsOpenCount.withLock { $0 += 1 }
                return true
            },
            requestCriticalAlerts: {
                requestCount.withLock { $0 += 1 }
                return .enabled
            },
            requestNotifications: { .authorized }
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.devicePermissions = client
        } operation: {
            TestStore(initialState: EventSettings.State(eventID: canonicalSettingsEventID)) {
                EventSettings()
            }
        }

        try await store.state.$permissions.load()
        expectNoDifference(store.state.permissions.criticalAlerts, .enabled)

        await store.send(.criticalAlertPermissionButtonTapped)?.value

        expectNoDifference(settingsOpenCount.withLock { $0 }, 1)
        expectNoDifference(requestCount.withLock { $0 }, 0)
    }

    @Test
    func appDelegateResumeReloadsSharedDevicePermissions() async throws {
        let database = try makePreparedDatabase()
        let loadCount = TestMutex(0)
        let client = DevicePermissionsClient(
            load: {
                loadCount.withLock { $0 += 1 }
                return DevicePermissions(notifications: .authorized)
            },
            openNotificationSettings: { false },
            requestCriticalAlerts: { .unavailable },
            requestNotifications: { .authorized }
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.devicePermissions = client
            $0.notificationsClient = NotificationsClient(
                registerDestination: { _ in },
                replaceSubscriptions: { _ in },
                synchronize: {},
                signals: { AsyncStream { $0.finish() } }
            )
        } operation: {
            TestStore(initialState: OpenMusicEventAppRoot.State()) {
                OpenMusicEventAppRoot()
            }
        }

        try await store.state.$permissions.load()
        let loadsBeforeResume = loadCount.withLock { $0 }

        let resumeTask = try store.state.appDelegateEvent(.resumed)
        await resumeTask?.value

        expectNoDifference(loadCount.withLock { $0 }, loadsBeforeResume + 1)
        expectNoDifference(store.state.permissions.notifications, .authorized)
    }

    private func waitForLatestError(in errorNotifications: Spawn<ErrorNotifications>) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(60))
        while errorNotifications.state.latestError == nil && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(errorNotifications.state.latestError != nil)
    }


}

private struct EventSettingsAuthoringExitFixture {
    let database: any DatabaseWriter
    let eventID: Event.ID
    let session: Shared<EventWorkspaceSession?>
    let baseline: SourceBaselineDatabase
    let store: TestStore<AnyFeature<EventSettings.State, EventSettings.Action>>
}

@MainActor
private func makeEventSettingsAuthoringExitFixture(
    isDirty: Bool
) async throws -> EventSettingsAuthoringExitFixture {
    let database = try makePreparedDatabase()
    let referenceDatabase = try defaultBaselineDatabase()
    let organizerID = try #require(OMERecord.Organizer.ID("did:plc:eventsettingsowner"))
    let eventID = try #require(Event.ID(
        "at://did:plc:eventsettingsowner/events.openmusic.event/3mrdbziccpcah"
    ))
    let actorID = organizerID

    var referenceMigrator = DatabaseMigrator()
    OME.DatabaseMigrations.register(into: &referenceMigrator)
    try referenceMigrator.migrate(referenceDatabase.database)
    let event = try Event(
        id: eventID,
        name: "Published Event Name",
        createdAt: "2026-09-01T12:00:00Z",
        timeZone: try #require(TimeZone(identifier: "America/Denver"))
    )
    for targetDatabase in [database, referenceDatabase.database as any DatabaseWriter] {
        try await targetDatabase.write { db in
            try Event.insert { event }.execute(db)
        }
    }
    if isDirty {
        try await database.write { db in
            var changed = try #require(try Event.find(eventID).fetchOne(db))
            changed.name = "Unpublished Event Name"
            let saved = changed
            try Event.upsert { saved }.execute(db)
        }
    }

    let session = withDependencies {
        $0.context = .test
        $0.defaultDatabase = database
        $0.defaultEventID = eventID
    } operation: {
        Shared<EventWorkspaceSession?>(.defaultEventWorkspaceSession)
    }
    session.withLock {
        $0 = EventWorkspaceSession(
            eventID: eventID,
            actorID: actorID,
            baseline: referenceDatabase
        )
    }
    let oauth = canonicalWorkspaceTestOAuthSession(actorID: actorID)
    let store = withDependencies {
        $0.context = .test
        $0.defaultDatabase = database
        $0.defaultEventID = eventID
        $0.getOptionalDefaultSession = { oauth }
    } operation: {
        TestStore(initialState: EventSettings.State(eventID: eventID)) {
            AnyFeature(EventSettings())
        }
    }
    return EventSettingsAuthoringExitFixture(
        database: database,
        eventID: eventID,
        session: session,
        baseline: referenceDatabase,
        store: store
    )
}

@MainActor
@Suite("About OpenMusicEvent", .tcaExhaustivity(.off))
struct AboutOpenMusicEventTests {
    @Test
    func loadsContributorsOnMountWithoutAResultAction() async throws {
        let contribution = try contribution()
        let store = withDependencies {
            $0.appContributors = AppContributorsClient {
                [contribution]
            }
        } operation: {
            TestStore(initialState: AboutOpenMusicEvent.State()) {
                AboutOpenMusicEvent()
            }
        }

        await waitUntil {
            store.state.contributors == .loaded([contribution])
        }

        expectNoDifference(store.state.contributors, .loaded([contribution]))
    }

    @Test
    func failedContributorLoadCanBeRetried() async throws {
        let contribution = try contribution()
        let loader = ScriptedAppContributorsLoader(contribution: contribution)
        let store = withDependencies {
            $0.appContributors = AppContributorsClient {
                try await loader.load()
            }
        } operation: {
            TestStore(initialState: AboutOpenMusicEvent.State()) {
                AboutOpenMusicEvent()
            }
        }

        await waitUntil {
            store.state.contributors == .failed
        }
        #expect(store.state.contributors == .failed)

        await store.send(.retryButtonTapped)?.value
        await waitUntil {
            store.state.contributors == .loaded([contribution])
        }

        expectNoDifference(store.state.contributors, .loaded([contribution]))
        #expect(await loader.attemptCount == 2)
    }

    @Test
    func settingsPresentsAboutWithoutEventContext() async throws {
        let database = try makePreparedDatabase()
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.appContributors = AppContributorsClient { [] }
        } operation: {
            TestStore(initialState: Settings.State()) {
                Settings()
            }
        }

        await store.send(.aboutOpenMusicEventButtonTapped)?.value

        #expect(store.state.destination?.aboutOpenMusicEvent?.eventID == nil)
        #expect(
            store.state.destination?.aboutOpenMusicEvent?
                .eventInformationProviderDescription.contains("event organizers") == true
        )
    }

    @Test
    func eventAboutPresentsAboutWithCanonicalEventContext() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalSettingsEventID
        let event = try Event(
            id: eventID,
            name: "Event One",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        try await database.write { db in
            try Event.insert { event }.execute(db)
        }
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.appContributors = AppContributorsClient { [] }
        } operation: {
            TestStore(initialState: EventInfoViewer.State(eventID: eventID)) {
                EventInfoViewer()
            }
        }

        await store.send(.aboutOpenMusicEventButtonTapped)?.value

        #expect(store.state.destination?.aboutOpenMusicEvent?.eventID == eventID)
        #expect(
            store.state.destination?.aboutOpenMusicEvent?
                .eventInformationProviderDescription.contains("AT Protocol repository") == true
        )
    }

    @Test
    func contributorFilterAcceptsOnlyDeveloperAssertionsByTheApp() throws {
        let appDID = try #require(DID("did:plc:openmusicevent"))
        let woodyDID = try #require(DID("did:plc:woody"))
        let otherDID = try #require(DID("did:plc:other"))
        let subject = OMERecord.Relationship.IdentityReference(
            did: woodyDID,
            handle: "woody.fm",
            displayName: "Woodrow Melling"
        )

        let accepted = listedRelationship(
            author: appDID,
            subject: .identity(subject),
            role: .developer,
            object: .identity(did: appDID)
        )
        let wrongAuthor = listedRelationship(
            author: otherDID,
            subject: .identity(subject),
            role: .developer,
            object: .identity(did: appDID)
        )
        let wrongRole = listedRelationship(
            author: appDID,
            subject: .identity(subject),
            role: .maintainer,
            object: .identity(did: appDID)
        )
        let wrongObject = listedRelationship(
            author: appDID,
            subject: .identity(subject),
            role: .developer,
            object: .identity(did: otherDID)
        )

        expectNoDifference(
            [accepted, wrongAuthor, wrongRole, wrongObject].compactMap {
                AppContributorsClient.developerIdentity(from: $0, appDID: appDID)
            },
            [subject]
        )
    }

    @Test
    func liveContributorClientReadsPublicPaginatedRelationshipsAndHydratesProfiles() async throws {
        let appDID = try #require(DID("did:plc:openmusicevent"))
        let requests = TestMutex<[URL?]>([])
        let profile = BlueskyActorProfile(
            did: "did:plc:alice",
            handle: "alice.dev",
            displayName: "Alice Hydrated",
            description: "Open-source contributor.",
            avatar: URL(string: "https://cdn.example/alice.jpg")
        )

        let contributions = try await withDependencies {
            $0[Atmosphere.Account.Client.self] = Atmosphere.Account.Client(
                resolveHandle: { handle in
                    #expect(handle.rawValue == "openmusicevent.app")
                    return (
                        Atmosphere.Account(id: .init(appDID), handle: handle),
                        try aboutDIDDocument(
                            did: appDID,
                            handle: handle,
                            pdsHost: "pds.openmusicevent.app"
                        )
                    )
                },
                resolveDID: { did in
                    Issue.record("Did not expect DID resolution for \(did)")
                    throw AppContributorsClientError.unimplemented
                }
            )
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { request, _ in
                requests.withLock { $0.append(request.url) }
                #expect(request.url?.host == "pds.openmusicevent.app")
                #expect(request.url?.path.hasSuffix("/com.atproto.repo.listRecords") == true)
                #expect(request.headerFields[.authorization] == nil)
                #expect(request.url?.aboutQueryValue(named: "repo") == appDID.description)
                #expect(
                    request.url?.aboutQueryValue(named: "collection")
                        == "app.openmusicevent.relationship"
                )

                if request.url?.aboutQueryValue(named: "cursor") == nil {
                    return Data(
                        """
                        {
                          "cursor": "page-2",
                          "records": [
                            {
                              "uri": "at://did:plc:openmusicevent/app.openmusicevent.relationship/woody",
                              "cid": "bafywoody",
                              "value": {
                                "$type": "app.openmusicevent.relationship",
                                "subject": {
                                  "$type": "app.openmusicevent.relationship#identity",
                                  "did": "did:plc:woody",
                                  "handle": "woody.fm",
                                  "displayName": "Woodrow Melling"
                                },
                                "role": "developer",
                                "object": {
                                  "$type": "app.openmusicevent.relationship#identity",
                                  "did": "did:plc:openmusicevent"
                                },
                                "createdAt": "2026-08-03T00:00:00Z"
                              }
                            },
                            {
                              "uri": "at://did:plc:other/app.openmusicevent.relationship/wrong-author",
                              "cid": "bafywrongauthor",
                              "value": {
                                "$type": "app.openmusicevent.relationship",
                                "subject": {
                                  "$type": "app.openmusicevent.relationship#identity",
                                  "did": "did:plc:other-developer"
                                },
                                "role": "developer",
                                "object": {
                                  "$type": "app.openmusicevent.relationship#identity",
                                  "did": "did:plc:openmusicevent"
                                },
                                "createdAt": "2026-08-03T00:00:00Z"
                              }
                            }
                          ]
                        }
                        """
                        .utf8
                    )
                }

                #expect(request.url?.aboutQueryValue(named: "cursor") == "page-2")
                return Data(
                    """
                    {
                      "records": [
                        {
                          "uri": "at://did:plc:openmusicevent/app.openmusicevent.relationship/alice",
                          "cid": "bafyalice",
                          "value": {
                            "$type": "app.openmusicevent.relationship",
                            "subject": {
                              "$type": "app.openmusicevent.relationship#identity",
                              "did": "did:plc:alice",
                              "handle": "stale.example",
                              "displayName": "Stale Alice"
                            },
                            "role": "developer",
                            "object": {
                              "$type": "app.openmusicevent.relationship#identity",
                              "did": "did:plc:openmusicevent"
                            },
                            "createdAt": "2026-08-03T00:00:00Z"
                          }
                        },
                        {
                          "uri": "at://did:plc:openmusicevent/app.openmusicevent.relationship/wrong-object",
                          "cid": "bafywrongobject",
                          "value": {
                            "$type": "app.openmusicevent.relationship",
                            "subject": {
                              "$type": "app.openmusicevent.relationship#identity",
                              "did": "did:plc:ignored"
                            },
                            "role": "developer",
                            "object": {
                              "$type": "app.openmusicevent.relationship#identity",
                              "did": "did:plc:other-app"
                            },
                            "createdAt": "2026-08-03T00:00:00Z"
                          }
                        }
                      ]
                    }
                    """
                    .utf8
                )
            }
            $0.blueskyActorProfileCache = BlueskyActorProfileCacheClient(
                cachedProfile: { _ in nil },
                refreshProfile: { actor in
                    guard actor == profile.did else {
                        throw AppContributorsClientError.unimplemented
                    }
                    return profile
                },
                refreshProfileIfNeeded: { actor, _, _ in
                    guard actor == profile.did else {
                        throw AppContributorsClientError.unimplemented
                    }
                    return profile
                }
            )
        } operation: {
            try await AppContributorsClient.live.load()
        }

        #expect(requests.withLock { $0.count } == 2)
        #expect(contributions.count == 2)
        let alice = try #require(contributions.first)
        #expect(alice.displayName == "Alice Hydrated")
        #expect(alice.handle == "alice.dev")
        #expect(alice.bio == "Open-source contributor.")
        #expect(alice.avatarURL == URL(string: "https://cdn.example/alice.jpg"))
        let woody = try #require(contributions.last)
        #expect(woody.displayName == "Woodrow Melling")
        #expect(woody.handle == "woody.fm")
        #expect(woody.bio == nil)
        #expect(woody.avatarURL == nil)
    }

    @Test
    func eventInformationDescriptionUsesPublishedRecordAttribution() throws {
        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let global = AboutOpenMusicEvent.State()
        let event = AboutOpenMusicEvent.State(eventID: eventID)

        #expect(global.eventInformationProviderDescription.contains("event organizers"))
        #expect(event.eventInformationProviderDescription.contains("AT Protocol repository"))
    }

    private func contribution() throws -> AppContribution {
        AppContribution(
            id: "at://did:plc:openmusicevent/app.openmusicevent.relationship/developer",
            bio: "Independent developer and open-source advocate.",
            did: try #require(DID("did:plc:woody")),
            displayName: "Woodrow Melling",
            handle: "woody.fm",
            role: .developer
        )
    }

    private func listedRelationship(
        author: DID,
        subject: OMERecord.Relationship.Entity,
        role: OMERecord.Relationship.Role,
        object: OMERecord.Relationship.Entity?
    ) -> ATProto.Repository.ListedRecord<OMERecord.Relationship> {
        ATProto.Repository.ListedRecord(
            uri: ATProto.URI(
                authority: .did(author),
                collection: OMERecord.Relationship.nsid,
                rkey: ATProto.Record.Key(rawValue: UUID().uuidString.lowercased())
            ),
            value: OMERecord.Relationship(
                subject: subject,
                role: role,
                object: object,
                createdAt: "2026-08-03T00:00:00Z"
            )
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private func aboutDIDDocument(
    did: DID,
    handle: Atmosphere.Account.Handle,
    pdsHost: String
) throws -> DID.Document {
    try JSONDecoder().decode(
        DID.Document.self,
        from: Data(
            """
            {
              "id": "\(did.description)",
              "alsoKnownAs": ["at://\(handle.rawValue)"],
              "verificationMethod": [],
              "service": [
                {
                  "id": "#atproto_pds",
                  "type": "AtprotoPersonalDataServer",
                  "serviceEndpoint": "https://\(pdsHost)"
                }
              ]
            }
            """
            .utf8
        )
    )
}

private extension URL {
    func aboutQueryValue(named name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}

private actor ScriptedAppContributorsLoader {
    let contribution: AppContribution
    private(set) var attemptCount = 0

    init(contribution: AppContribution) {
        self.contribution = contribution
    }

    func load() throws -> [AppContribution] {
        attemptCount += 1
        if attemptCount == 1 {
            throw AppContributorsClientError.unimplemented
        }
        return [contribution]
    }
}

@Feature
private struct SettingsErrorHost {
    struct State {
        var errorNotifications = Spawn(ErrorNotifications.State())
        @DebugSnapshotIgnored
        var settings = Spawn(Settings.State())
    }

    enum Action {}

    var body: some Feature {
        Update { _, _ in }
            .spawn(\.errorNotifications) {
                ErrorNotifications()
            }
            .spawn(\.settings) {
                Settings()
            }
            .onEvent(ErrorReported.self) { error, state in
                state.errorNotifications.state.report(error)
            }
    }
}

@Feature
private struct EventSettingsErrorHost {
    struct State {
        var errorNotifications = Spawn(ErrorNotifications.State())
        @DebugSnapshotIgnored
        var eventSettings = Spawn(EventSettings.State(eventID: canonicalSettingsEventID))
    }

    enum Action {}

    var body: some Feature {
        Update { _, _ in }
            .spawn(\.errorNotifications) {
                ErrorNotifications()
            }
            .spawn(\.eventSettings) {
                EventSettings()
            }
            .onEvent(ErrorReported.self) { error, state in
                state.errorNotifications.state.report(error)
            }
    }
}

private let canonicalSettingsEventID = Event.ID(
    "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
)!


private func makePreparedDatabase() throws -> any DatabaseWriter {
    try withDependencies {
        $0.context = .test
        try OME.prepareDependencies(&$0)
    } operation: {
        @Dependency(\.defaultDatabase) var database
        return database
    }
}
