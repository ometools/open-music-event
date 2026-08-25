import ATProto
import BlueskyActorCache
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
import Lexicon
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
import Synchronization
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
import Testing
import XRPCClient

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
        let actor = try #require(
            OMERecord.Contributor.Actor("did:plc:alice123")
        )
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
@Suite(.tcaExhaustivity(.off))
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
        let summary = try await fixture.database.read { db in
            try SourceWorkspaceEditSummary.query(
                workspace: fixture.source.workspace,
                in: db,
                referenceDatabase: fixture.source.referenceDatabase
            )
        }
        #expect(summary.availability == .available)
        #expect(summary.totalCount == 0)

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
        #expect(fixture.grant.wrappedValue != nil)
        let eventName = try await fixture.database.read { db in
            try OMERecord.Event.find(fixture.eventID).fetchOne(db)?.name
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
    func eventPoliciesButtonEmitsPolicyEditorRequest() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EventSettings.State(eventID: eventID)) {
                EventSettings()
            }
        }

        let editTask = store.send(.eventPoliciesButtonTapped)
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(.editEventPolicies(eventID)),
            timeout: .seconds(1)
        )
        await editTask?.value
    }

    @Test
    func `Event Settings requests notification permission and reloads the system status`() async throws {
        let database = try makePreparedDatabase()
        let permissionWasRequested = Mutex(false)
        let loadCount = Mutex(0)
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
            TestStore(initialState: EventSettings.State(eventID: testEventID())) {
                EventSettings()
            }
        }

        try await store.state.$permissions.load()
        expectNoDifference(store.state.permissions.notifications, .unknown)
        let loadsBeforeRequest = loadCount.withLock { $0 }

        await store.send(.notificationPermissionToggleChanged(true))?.value

        expectNoDifference(permissionWasRequested.withLock { $0 }, true)
        expectNoDifference(store.state.permissions.notifications, .authorized)
        expectNoDifference(loadCount.withLock { $0 }, loadsBeforeRequest + 1)
    }

    @Test
    func `Event Settings requests Critical Alerts separately and reloads the system status`() async throws {
        let database = try makePreparedDatabase()
        let criticalAlertsWereRequested = Mutex(false)
        let loadCount = Mutex(0)
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
            TestStore(initialState: EventSettings.State(eventID: testEventID())) {
                EventSettings()
            }
        }

        // Ordinary notifications are already allowed, but Critical Alerts are still off.
        try await store.state.$permissions.load()
        expectNoDifference(store.state.permissions.notifications, .authorized)
        expectNoDifference(store.state.permissions.criticalAlerts, .disabled)
        let loadsBeforeRequest = loadCount.withLock { $0 }

        // The distinct Critical Alerts action requests only that permission and reloads system state.
        await store.send(.criticalAlertPermissionToggleChanged(true))?.value

        expectNoDifference(criticalAlertsWereRequested.withLock { $0 }, true)
        expectNoDifference(store.state.permissions.notifications, .authorized)
        expectNoDifference(store.state.permissions.criticalAlerts, .enabled)
        expectNoDifference(loadCount.withLock { $0 }, loadsBeforeRequest + 1)
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
            EventSettings.State(eventID: testEventID())
        }
        expectNoDifference(settings.notificationIndicatorValue, 1)

        #expect(DevicePermissions(notifications: .authorized).notificationsAreAllowed)
        #expect(DevicePermissions(notifications: .limited).notificationsAreAllowed)
        #expect(!DevicePermissions(notifications: .unknown).notificationsAreAllowed)
        #expect(!DevicePermissions(notifications: .denied).notificationsAreAllowed)
        #expect(!DevicePermissions(notifications: .restricted).notificationsAreAllowed)
    }

    @Test
    func `Event Settings opens system settings when denied notifications are switched on`() async throws {
        let database = try makePreparedDatabase()
        let settingsOpenCount = Mutex(0)
        let requestCount = Mutex(0)
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
            TestStore(initialState: EventSettings.State(eventID: testEventID())) {
                EventSettings()
            }
        }

        try await store.state.$permissions.load()
        expectNoDifference(store.state.permissions.notifications, .denied)

        await store.send(.notificationPermissionToggleChanged(true))?.value

        expectNoDifference(settingsOpenCount.withLock { $0 }, 1)
        expectNoDifference(requestCount.withLock { $0 }, 0)
    }

    @Test
    func `Event Settings opens system settings when allowed notifications are switched off`() async throws {
        let database = try makePreparedDatabase()
        let settingsOpenCount = Mutex(0)
        let requestCount = Mutex(0)
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
            TestStore(initialState: EventSettings.State(eventID: testEventID())) {
                EventSettings()
            }
        }

        try await store.state.$permissions.load()
        expectNoDifference(store.state.permissions.notifications, .authorized)

        await store.send(.notificationPermissionToggleChanged(false))?.value

        expectNoDifference(settingsOpenCount.withLock { $0 }, 1)
        expectNoDifference(requestCount.withLock { $0 }, 0)
    }

    @Test
    func appDelegateResumeReloadsSharedDevicePermissions() async throws {
        let database = try makePreparedDatabase()
        let loadCount = Mutex(0)
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

    @Test
    func eventPolicyEditorLoadsExistingPolicies() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        let policies = contributorPolicies(
            listing: .known(.scheduleContributors),
            profile: .known(
                .actorProfiles(
                    .init(providers: [.known(.bskyActorProfile)])
                )
            )
        )
        try await insertEvent(eventID, policies: policies, into: database)

        let store = makePolicyEditorStore(database: database, eventID: eventID)

        #expect(store.hasLoadedDraft)
        #expect(store.form.value.contributorListing == .scheduleContributors)
        #expect(store.form.value.contributorProfile == .actorProfiles)
        #expect(store.form.value.usesBlueskyActorProfile)
        #expect(store.form.value.preservedProfileProviders.isEmpty)
        #expect(store.errorMessage == nil)
    }

    @Test
    func eventPolicyEditorSavesScheduleContributorListing() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        try await insertEvent(eventID, into: database)

        @Bindable var store = makePolicyEditorStore(database: database, eventID: eventID)
        $store.form.value.contributorListing.wrappedValue = .scheduleContributors

        await store.send(.saveButtonTapped)?.value

        let event = try await fetchEvent(eventID, from: database)
        expectNoDifference(
            event.policies,
            contributorPolicies(listing: .known(.scheduleContributors))
        )
    }

    @Test
    func eventPolicyEditorSavesActorProfilePolicy() async throws {
        try await saveProfilePolicy(.actorProfiles)
    }

    @Test
    func eventPolicyEditorSavesClaimedArtistsOnlyProfilePolicy() async throws {
        try await saveProfilePolicy(.claimedArtistsOnly)
    }

    @Test
    func eventPolicyEditorClearsPoliciesWhenNoPoliciesRemain() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        try await insertEvent(
            eventID,
            policies: contributorPolicies(
                listing: .known(.scheduleContributors),
                profile: .known(
                    .actorProfiles(
                        .init(providers: [.known(.bskyActorProfile)])
                    )
                )
            ),
            into: database
        )

        @Bindable var store = makePolicyEditorStore(database: database, eventID: eventID)
        $store.form.value.contributorListing.wrappedValue = .none
        $store.form.value.contributorProfile.wrappedValue = .none
        $store.form.value.usesBlueskyActorProfile.wrappedValue = false

        await store.send(.saveButtonTapped)?.value

        let event = try await fetchEvent(eventID, from: database)
        #expect(event.policies == nil)
    }

    @Test
    func eventPolicyEditorPreservesUnsupportedPolicyValues() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        let policies = contributorPolicies(
            listing: .unknown(
                .object([
                    "type": .string("customListing"),
                    "mode": .string("source"),
                ])
            ),
            profile: .unknown(
                .object([
                    "type": .string("customProfile"),
                    "provider": .string("social.example.profile"),
                ])
            )
        )
        try await insertEvent(eventID, policies: policies, into: database)

        let store = makePolicyEditorStore(database: database, eventID: eventID)

        #expect(store.form.value.contributorListing == .unsupported)
        #expect(store.form.value.contributorProfile == .unsupported)
        await store.send(.saveButtonTapped)?.value

        let event = try await fetchEvent(eventID, from: database)
        expectNoDifference(event.policies, policies)
    }

    @Test
    func eventPolicyEditorPreservesUnsupportedProfileProviders() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        let unsupportedProvider: Open<OMERecord.Event.ContributorProfileProvider> =
            .unknown(.string("social.example.profile"))
        let policies = contributorPolicies(
            profile: .known(
                .actorProfiles(
                    .init(providers: [unsupportedProvider])
                )
            )
        )
        try await insertEvent(eventID, policies: policies, into: database)

        let store = makePolicyEditorStore(database: database, eventID: eventID)

        #expect(store.form.value.contributorProfile == .actorProfiles)
        #expect(!store.form.value.usesBlueskyActorProfile)
        expectNoDifference(store.form.value.preservedProfileProviders, [unsupportedProvider])
        await store.send(.saveButtonTapped)?.value

        let event = try await fetchEvent(eventID, from: database)
        expectNoDifference(event.policies, policies)
    }

    @Test
    func eventPolicyEditorBlocksKnownProfilePolicyWithoutProviders() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        try await insertEvent(eventID, into: database)

        @Bindable var store = makePolicyEditorStore(database: database, eventID: eventID)
        $store.form.value.contributorProfile.wrappedValue = .actorProfiles
        $store.form.value.usesBlueskyActorProfile.wrappedValue = false

        await store.send(.saveButtonTapped)?.value

        #expect(store.errorMessage == "Choose at least one profile provider.")
        let event = try await fetchEvent(eventID, from: database)
        #expect(event.policies == nil)
    }

    private func saveProfilePolicy(
        _ profile: EditEventPolicies.ContributorProfileSelection
    ) async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        try await insertEvent(eventID, into: database)

        @Bindable var store = makePolicyEditorStore(database: database, eventID: eventID)
        $store.form.value.contributorProfile.wrappedValue = profile
        $store.form.value.usesBlueskyActorProfile.wrappedValue = true

        await store.send(.saveButtonTapped)?.value

        let expectedProfile: Open<OMERecord.Event.ContributorProfilePolicy>
        switch profile {
        case .actorProfiles:
            expectedProfile = .known(
                .actorProfiles(
                    .init(providers: [.known(.bskyActorProfile)])
                )
            )
        case .claimedArtistsOnly:
            expectedProfile = .known(
                .claimedArtistsOnly(
                    .init(providers: [.known(.bskyActorProfile)])
                )
            )
        case .none, .unsupported:
            fatalError("Unsupported profile test input.")
        }

        let event = try await fetchEvent(eventID, from: database)
        expectNoDifference(
            event.policies,
            contributorPolicies(profile: expectedProfile)
        )
    }
}

private struct EventSettingsAuthoringExitFixture {
    let database: any DatabaseWriter
    let eventID: OMERecord.Event.ID
    let grant: Shared<AuthoringGrant?>
    let source: SourceWorkspaceResource
    let store: TestStore<AnyFeature<EventSettings.State, EventSettings.Action>>
}

@MainActor
private func makeEventSettingsAuthoringExitFixture(
    isDirty: Bool
) async throws -> EventSettingsAuthoringExitFixture {
    let database = try makePreparedDatabase()
    let referenceDatabase = try defaultBaselineDatabase()
    let organizerID = try #require(OMERecord.Organizer.ID("did:plc:eventsettingsowner"))
    let eventID = OMERecord.Event.ID(
        organizerID: organizerID,
        eventID: OMERecord.ID<OMERecord.Event>(rawValue: "event-settings")
    )
    let workspace = SourceWorkspace(
        organizerID: organizerID,
        repository: "tangled.org/eventsettingsowner/events",
        branch: "main"
    )
    let actorID = try #require(DID(organizerID.description))

    var referenceMigrator = DatabaseMigrator()
    OMERecord.DatabaseMigrations.register(into: &referenceMigrator)
    try referenceMigrator.migrate(referenceDatabase.database)
    for targetDatabase in [database, referenceDatabase.database as any DatabaseWriter] {
        try await targetDatabase.write { db in
            try OMERecord.Organizer.insert {
                OMERecord.Organizer.Draft(id: organizerID)
            }
            .execute(db)
            try OMERecord.Event.insert {
                testEventDraft(id: eventID, name: "Published Event Name")
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceKind: .tangled,
                    sourceReference: workspace.repository,
                    ref: workspace.defaultBranch,
                    eventIDOrigin: .explicit,
                    sourceEventDirectory: "event-settings"
                )
            }
            .execute(db)
        }
    }
    if isDirty {
        try await database.write { db in
            try OMERecord.Event.find(eventID).update {
                $0.name = "Unpublished Event Name"
            }
            .execute(db)
        }
    }

    let resource = SourceWorkspaceResource(
        workspace: workspace,
        repositoryURL: FileManager.default.temporaryDirectory,
        mainDatabase: database,
        referenceDatabase: referenceDatabase
    )
    let grant = withDependencies {
        $0.context = .test
        $0.defaultDatabase = database
        $0.defaultEventID = eventID
    } operation: {
        Shared<AuthoringGrant?>(.defaultAuthoringGrant)
    }
    grant.withLock {
        $0 = AuthoringGrant(
            principal: AuthoringPrincipal(actorID: actorID),
            role: .owner,
            workspaceID: workspace.id
        )
    }
    let store = withDependencies {
        $0.context = .test
        $0.defaultDatabase = database
    } operation: {
        TestStore(initialState: EventSettings.State(eventID: eventID)) {
            AnyFeature(
                EventSettings()
                    .environment(
                        WorkspaceContext<SourceWorkspaceResource, SourcePatch>(
                            phase: SharedReader(value: .inactive),
                            source: SharedReader(value: resource)
                        )
                    )
                )
        }
    }
    return EventSettingsAuthoringExitFixture(
        database: database,
        eventID: eventID,
        grant: grant,
        source: resource,
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
        #expect(store.state.destination?.aboutOpenMusicEvent?.sourceProvenance == nil)
    }

    @Test
    func eventAboutPresentsAboutWithEventProvenance() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        let provenance = EventSourceProvenanceRecord(
            id: eventID,
            sourceKind: .tangled,
            sourceReference: "tangled.org/woody.fm/open-music-event",
            ref: "main",
            eventIDOrigin: .explicit,
            sourceEventDirectory: "event-1"
        )
        try await insertEvent(eventID, into: database)
        try await database.write { db in
            try EventSourceProvenanceRecord.insert { provenance }
                .execute(db)
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
        expectNoDifference(
            store.state.destination?.aboutOpenMusicEvent?.sourceProvenance,
            provenance
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
        let requests = Mutex<[URL?]>([])
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
    func provenanceDescriptionsCoverGlobalTangledLocalAndMissingSources() throws {
        let eventID = testEventID()
        let global = AboutOpenMusicEvent.State()
        let missing = AboutOpenMusicEvent.State(eventID: eventID)
        let tangled = AboutOpenMusicEvent.State(
            eventID: eventID,
            sourceProvenance: EventSourceProvenanceRecord(
                id: eventID,
                sourceKind: .tangled,
                sourceReference: "tangled.org/woody.fm/open-music-event",
                ref: "main",
                eventIDOrigin: .explicit,
                sourceEventDirectory: "event-1"
            )
        )
        let localPath = "/Users/woody/private/local-event"
        let local = AboutOpenMusicEvent.State(
            eventID: eventID,
            sourceProvenance: EventSourceProvenanceRecord(
                id: eventID,
                sourceKind: .local,
                sourceReference: localPath,
                ref: nil,
                eventIDOrigin: .explicit,
                sourceEventDirectory: "event-1"
            )
        )

        #expect(global.eventInformationProviderDescription.contains("event organizers"))
        #expect(missing.eventInformationProviderDescription.contains("No external source"))
        #expect(tangled.eventInformationProviderDescription.contains("tangled.org/woody.fm/open-music-event"))
        #expect(local.eventInformationProviderDescription.contains("created or imported locally"))
        #expect(!local.eventInformationProviderDescription.contains(localPath))
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
        var eventSettings = Spawn(EventSettings.State(eventID: testEventID()))
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

private func testEventID() -> OMERecord.Event.ID {
    OMERecord.Event.ID(
        organizerID: OMERecord.Organizer.ID("did:web:example.com")!,
        eventID: .init("event-1")
    )
}

private func contributorPolicies(
    listing: Open<OMERecord.Event.ContributorListingPolicy>? = nil,
    profile: Open<OMERecord.Event.ContributorProfilePolicy>? = nil
) -> OMERecord.Event.Policies {
    OMERecord.Event.Policies(
        contributors: .init(
            listing: listing,
            profile: profile
        )
    )
}

@MainActor
private func makePolicyEditorStore(
    database: any DatabaseWriter,
    eventID: OMERecord.Event.ID
) -> StoreOf<EditEventPolicies> {
    withDependencies {
        $0.context = .test
        $0.continuousClock = ImmediateClock()
        $0.defaultDatabase = database
    } operation: {
        Store(initialState: EditEventPolicies.State(eventID: eventID)) {
            EditEventPolicies()
        }
    }
}

private func makePreparedDatabase() throws -> any DatabaseWriter {
    try withDependencies {
        $0.context = .test
        try OME.prepareDependencies(&$0)
    } operation: {
        @Dependency(\.defaultDatabase) var database
        return database
    }
}

private func insertEvent(
    _ eventID: OMERecord.Event.ID,
    policies: OMERecord.Event.Policies? = nil,
    into database: any DatabaseWriter
) async throws {
    try await database.write { db in
        try OMERecord.Organizer.insert {
            OMERecord.Organizer.Draft(id: eventID.organizerID)
        }
        .execute(db)
        try OMERecord.Event.insert {
            OMERecord.Event.Draft(
                id: eventID,
                name: "Event One",
                description: nil,
                startDate: nil,
                endDate: nil,
                status: nil,
                mode: nil,
                locations: nil,
                uris: nil,
                timeZone: TimeZone(identifier: "UTC")!,
                images: nil,
                contactNumbers: nil,
                categoryConfigs: nil,
                policies: policies
            )
        }
        .execute(db)
    }
}

private func insertDefaultCalendarEntry(
    eventID: OMERecord.Event.ID,
    into database: any DatabaseWriter
) async throws {
    let calendarID = OMERecord.Calendar.ID(
        ownerID: eventID.organizerID,
        calendarID: OMERecord.Calendar.defaultID
    )
    try await database.write { db in
        try OMERecord.Calendar.insert {
            OMERecord.Calendar.Draft(
                id: calendarID,
                name: "Default"
            )
        }
        .execute(db)
        try OMERecord.CalendarEntry.insert {
            OMERecord.CalendarEntry.Draft(
                id: OMERecord.CalendarEntry.ID(
                    calendarOwnerID: calendarID.ownerID,
                    calendarID: calendarID.calendarID,
                    entryID: OMERecord.ID<OMERecord.CalendarEntry>("entry-1")
                ),
                event: OMERecord.Event.reference(id: eventID),
                createdAt: Date(timeIntervalSince1970: 0),
                pinned: false
            )
        }
        .execute(db)
    }
}

private func fetchEvent(
    _ eventID: OMERecord.Event.ID,
    from database: any DatabaseWriter
) async throws -> OMERecord.Event {
    try await database.read { db in
        try #require(
            try OMERecord.Event
                .where { $0.id.eq(eventID) }
                .fetchOne(db)
        )
    }
}
