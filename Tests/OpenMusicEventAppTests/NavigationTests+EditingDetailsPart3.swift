import Bluesky
import ATProto
import Clocks
import ComposableArchitecture2
import ComposableNotifications
import CustomDump
import Dependencies
import DependenciesTestSupport
import DebugSnapshots
import Foundation
import IssueReporting
import Observation
import OpenMusicEventDatabase
import OpenMusicEventAuthentication
import OpenMusicEventImages
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import Sharing
import SQLiteData
import SourceEditing
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Testing
import ATProto

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventEditors

extension NavigationTests {
    @Test
    func communicationsViewerRowsPreferStoredPreferenceBeforeChannelDefault() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(
                db, id: channelID, eventID: eventID, name: "General",
                defaultNotificationState: .unsubscribed
            )
            try ChannelPreferences.insert {
                ChannelPreferences(
                    id: channelID,
                    notificationState: .subscribed
                )
            }
            .execute(db)
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: SocialCategoryList.State(eventID: eventID)) {
                SocialCategoryList()
            }
        }

        expectNoDifference(
            store.state.channelRows.map(\.effectiveNotificationState),
            [.subscribed]
        )
    }

    @Test
    func communicationsViewerNotificationPromptRequestsPermissionAndThenDisappears() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let permissionWasRequested = TestMutex(false)
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(
                db, id: canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan"),
                eventID: eventID, name: "General"
            )
        }
        let client = DevicePermissionsClient(
            load: {
                DevicePermissions(
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
            TestStore(initialState: SocialCategoryList.State(eventID: eventID)) {
                SocialCategoryList()
            }
        }

        // Comms starts with the notification prompt while device permission is undecided.
        try await store.state.$permissions.load()
        #expect(store.state.shouldShowNotificationPrompt)

        // Allowing notifications reloads the shared device state and removes the prompt.
        await store.send(.notificationPermissionButtonTapped)?.value
        #expect(permissionWasRequested.withLock { $0 })
        #expect(!store.state.shouldShowNotificationPrompt)
    }

    @Test
    func communicationsViewerOffersCriticalAlertsAfterNotificationsAreAllowed() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let criticalAlertsWereRequested = TestMutex(false)
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(
                db, id: canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan"),
                eventID: eventID, name: "General"
            )
        }
        let client = DevicePermissionsClient(
            load: {
                DevicePermissions(
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
            TestStore(initialState: SocialCategoryList.State(eventID: eventID)) {
                SocialCategoryList()
            }
        }

        // Existing users do not see the ordinary notification prompt again.
        try await store.state.$permissions.load()
        #expect(!store.state.shouldShowNotificationPrompt)
        #expect(store.state.shouldShowCriticalAlertPrompt)

        // The Comms prompt requests Critical Alerts independently and disappears when enabled.
        await store.send(.criticalAlertPermissionButtonTapped)?.value

        #expect(criticalAlertsWereRequested.withLock { $0 })
        #expect(!store.state.shouldShowCriticalAlertPrompt)
    }

    @Test
    func communicationsViewerNotificationPromptOpensSettingsWhenPermissionIsOff() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let settingsOpenCount = TestMutex(0)
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(
                db, id: canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan"),
                eventID: eventID, name: "General"
            )
        }
        let client = DevicePermissionsClient(
            load: { DevicePermissions(notifications: .denied) },
            openNotificationSettings: {
                settingsOpenCount.withLock { $0 += 1 }
                return true
            },
            requestCriticalAlerts: { .unavailable },
            requestNotifications: { .denied }
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.devicePermissions = client
        } operation: {
            TestStore(initialState: SocialCategoryList.State(eventID: eventID)) {
                SocialCategoryList()
            }
        }

        try await store.state.$permissions.load()
        #expect(store.state.shouldShowNotificationPrompt)

        await store.send(.openNotificationSettingsButtonTapped)?.value

        expectNoDifference(settingsOpenCount.withLock { $0 }, 1)
    }

    @Test
    func communicationsViewerNotificationActionWritesPreference() async throws {
        // An attendee changes a channel preference from either the row's long-press
        // menu or its swipe action. Both UI surfaces send this same feature action.
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(
                db, id: channelID, eventID: eventID, name: "General",
                defaultNotificationState: .unsubscribed
            )
        }

        let refreshCount = TestMutex(0)
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: SocialCategoryList.State(eventID: eventID)) {
                SocialCategoryList()
                    .onEvent(NotificationSubscriptionsRefreshRequested.self) { _, _ in
                        refreshCount.withLock { $0 += 1 }
                    }
            }
        }

        let preferenceTask = store.send(
            .notificationStateButtonTapped(channelID, .subscribed)
        )
        await preferenceTask?.value
        expectNoDifference(refreshCount.withLock { $0 }, 1)

        let preference = try await database.read { db in
            try ChannelPreferences
                .where { $0.id.eq(channelID) }
                .fetchOne(db)
        }

        #expect(preference?.notificationState == .subscribed)
    }

    @Test
    func communicationsViewerRequiredChannelDoesNotWriteUnsubscribePreference() async throws {
        // Required channels still show the complete notification menu, but the
        // feature boundary refuses an unsubscribe even if an action reaches it.
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let channelID = canonicalRouteRecordID("social.ome.category", "3mrdbziccpcan")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalCategory(
                db, id: channelID, eventID: eventID, name: "General",
                defaultNotificationState: .subscribed, notificationsRequired: true
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: SocialCategoryList.State(eventID: eventID)) {
                SocialCategoryList()
            }
        }

        store.send(.notificationStateButtonTapped(channelID, .unsubscribed))

        let preference = try await database.read { db in
            try ChannelPreferences
                .where { $0.id.eq(channelID) }
                .fetchOne(db)
        }

        #expect(preference == nil)
    }


}
