import ComposableArchitecture2
import ComposableAuthoring
import ComposableWorkspace
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventEditors
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct EventSettings {
    public init() {}

    public struct State {
        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
            _event = FetchOne(
                OMERecord.Event.where { $0.id.eq(eventID) }
            )
        }

        @FetchOne public var event: OMERecord.Event?
        public var destination: Destination.State?
        public var eventID: OMERecord.Event.ID
        @SharedReader(.devicePermissions) public var permissions: DevicePermissions

        public var notificationIndicatorValue: Int? {
            permissions.notificationSetupBadgeValue
        }
    }

    public enum Action {
        case criticalAlertPermissionButtonTapped
        case destination(Destination.Action)
        case enterAuthoringButtonTapped
        case eventPoliciesButtonTapped
        case exitAuthoringButtonTapped
        case notificationPermissionButtonTapped
        case testErrorButtonTapped
    }

    @Feature
    public enum Destination {
        case exitAuthoringConfirmation(ExitAuthoringConfirmation)
    }

    @Feature
    public struct ExitAuthoringConfirmation: Prompt {
        public enum Action {
            case cancelButtonTapped
            case exitAndDeleteButtonTapped
        }
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.devicePermissions) var devicePermissions
    @FeatureEnvironment(WorkspaceContext<SourceWorkspaceResource, SourcePatch>.self)
    var workspace

    private func requestAuthoringExit() {
        store.addTask {
            let task = try store.post(key: AuthoringExitRequested.self, value: ())
            await task?.value
        }
    }

    public var body: some Feature {
        let _ = Self._logChanges()

        Update { state, action in
            switch action {
            case .destination(.exitAuthoringConfirmation(.cancelButtonTapped)):
                break

            case .destination(.exitAuthoringConfirmation(.exitAndDeleteButtonTapped)):
                requestAuthoringExit()

            case .enterAuthoringButtonTapped:
                store.addTask {
                    let task = try store.post(key: AuthoringRequested.self, value: ())
                    await task?.value
                }

            case .eventPoliciesButtonTapped:
                let eventID = state.eventID
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .editEventPolicies(eventID)
                    )
                    await task?.value
                }

            case .exitAuthoringButtonTapped:
                guard let source = workspace.source.wrappedValue else {
                    // Without the prepared reference, cleanliness cannot be proven. Preserve the
                    // same explicit destructive confirmation used for a known dirty workspace.
                    state.destination = .exitAuthoringConfirmation(
                        ExitAuthoringConfirmation.State()
                    )
                    return
                }
                let sourceWorkspace = source.workspace
                let referenceDatabase = source.referenceDatabase
                let database = database
                store.addTask {
                    let hasNoUnpublishedChanges: Bool
                    do {
                        let summary = try await database.read { db in
                            try SourceWorkspaceEditSummary.query(
                                workspace: sourceWorkspace,
                                in: db,
                                referenceDatabase: referenceDatabase
                            )
                        }
                        hasNoUnpublishedChanges = summary.availability == .available
                            && summary.totalCount == 0
                    } catch {
                        // If the comparison cannot prove the workspace is clean, require the same
                        // explicit destructive confirmation as a known dirty workspace.
                        hasNoUnpublishedChanges = false
                    }

                    if hasNoUnpublishedChanges {
                        let task = try store.post(key: AuthoringExitRequested.self, value: ())
                        await task?.value
                    } else {
                        try store.modify {
                            $0.destination = .exitAuthoringConfirmation(
                                ExitAuthoringConfirmation.State()
                            )
                        }
                    }
                }

            case .criticalAlertPermissionButtonTapped:
                switch state.permissions.criticalAlerts {
                case .disabled where state.permissions.notificationsAreAllowed:
                    store.addTask {
                        do {
                            _ = try await devicePermissions.requestCriticalAlerts()
                            try await store.state.$permissions.load()
                        } catch {
                            await store.reportError(
                                error,
                                fallbackMessage: .notificationPermissionRequestFailed,
                                operation: .notificationPermissionRequest
                            )
                        }
                    }

                case .disabled where state.permissions.notifications == .unknown:
                    store.addTask {
                        do {
                            _ = try await devicePermissions.requestNotifications()
                            try await store.state.$permissions.load()
                        } catch {
                            await store.reportError(
                                error,
                                fallbackMessage: .notificationPermissionRequestFailed,
                                operation: .notificationPermissionRequest
                            )
                        }
                    }

                case .disabled, .enabled:
                    store.addTask {
                        _ = await devicePermissions.openNotificationSettings()
                    }

                case .unavailable:
                    break
                }

            case .notificationPermissionButtonTapped:
                guard state.permissions.notifications == .unknown else {
                    store.addTask {
                        _ = await devicePermissions.openNotificationSettings()
                    }
                    return
                }

                store.addTask {
                    do {
                        _ = try await devicePermissions.requestNotifications()
                        try await store.state.$permissions.load()
                    } catch {
                        await store.reportError(
                            error,
                            fallbackMessage: .notificationPermissionRequestFailed,
                            operation: .notificationPermissionRequest
                        )
                    }
                }

            case .testErrorButtonTapped:
                store.addTask {
                    _ = await store.withErrorHandling(
                        fallbackMessage: .eventSettingsTestError,
                        operation: .eventSettingsTestError
                    ) {
                        try await throwEventSettingsTestError()
                    }
                }

            case .destination:
                break
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct EventSettingsView: View {
    @Bindable var store: StoreOf<EventSettings>
    @Environment(\.openMusicEventAuthoringPhase) var authoringPhase

    public init(store: StoreOf<EventSettings>) {
        self.store = store
    }

    var criticalAlertPermissionButtonTitle: LocalizedStringKey {
        switch store.permissions.criticalAlerts {
        case .disabled where store.permissions.notificationsAreAllowed:
            "Allow Critical Alerts"
        case .disabled where store.permissions.notifications == .unknown:
            "Allow Notifications"
        case .disabled:
            "Open Notification Settings"
        case .enabled:
            "Manage Critical Alerts"
        case .unavailable:
            "Unavailable"
        }
    }

    var criticalAlertStatusTitle: LocalizedStringKey {
        switch store.permissions.criticalAlerts {
        case .disabled:
            "Off"
        case .enabled:
            "On"
        case .unavailable:
            "Unavailable"
        }
    }

    var notificationPermissionButtonTitle: LocalizedStringKey {
        switch store.permissions.notifications {
        case .authorized, .limited:
            "Manage Notifications"
        case .denied, .restricted:
            "Open Notification Settings"
        case .unknown:
            "Allow Notifications"
        }
    }

    var notificationStatusTitle: LocalizedStringKey {
        switch store.permissions.notifications {
        case .authorized:
            "On"
        case .limited:
            "Quiet"
        case .denied, .restricted:
            "Off"
        case .unknown:
            "Set Up"
        }
    }

    public var body: some View {
        Form {
            switch authoringPhase {
            case .some(.entering):
                Section {
                    ProgressView {
                        Text(
                            "Entering workspace",
                            bundle: .module,
                            comment: "Progress shown while source workspace access starts"
                        )
                    }
                } header: {
                    Text(
                        "Workspace",
                        bundle: .module,
                        comment: "Settings section for entering or leaving the event workspace"
                    )
                }

            case .some(.restoring):
                Section {
                    ProgressView {
                        Text(
                            "Restoring workspace",
                            bundle: .module,
                            comment: "Progress shown while saved workspace access is restored"
                        )
                    }
                } header: {
                    Text(
                        "Workspace",
                        bundle: .module,
                        comment: "Settings section for entering or leaving the event workspace"
                    )
                }

            case .some(.exiting):
                Section {
                    ProgressView {
                        Text(
                            "Leaving workspace",
                            bundle: .module,
                            comment: "Progress shown while workspace access and local edits are removed"
                        )
                    }
                } header: {
                    Text(
                        "Workspace",
                        bundle: .module,
                        comment: "Settings section for entering or leaving the event workspace"
                    )
                }

            case .some(.active):
                Section {
                    Button {
                        store.send(.exitAuthoringButtonTapped)
                    } label: {
                        Text(
                            "Leave Workspace",
                            bundle: .module,
                            comment: "Button that leaves the event editing workspace"
                        )
                    }
                } header: {
                    Text(
                        "Workspace",
                        bundle: .module,
                        comment: "Settings section for entering or leaving the event workspace"
                    )
                }

            case .some(.inactive(.eligible)):
                Section {
                    Button {
                        store.send(.enterAuthoringButtonTapped)
                    } label: {
                        Text(
                            "Enter Workspace",
                            bundle: .module,
                            comment: "Button that enters the event editing workspace"
                        )
                    }
                } header: {
                    Text(
                        "Workspace",
                        bundle: .module,
                        comment: "Settings section for entering or leaving the event workspace"
                    )
                }

            case .some(.inactive), .none:
                EmptyView()
            }

            #if os(iOS) || os(Android)
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Notifications")

                        Spacer()

                        Text(notificationStatusTitle)
                            .foregroundStyle(.secondary)
                    }

                    if store.permissions.notificationsAreAllowed {
                        Button {
                            store.send(.notificationPermissionButtonTapped)
                        } label: {
                            Text(notificationPermissionButtonTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            store.send(.notificationPermissionButtonTapped)
                        } label: {
                            Text(notificationPermissionButtonTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 6)
            }

            #if os(iOS)
            if store.permissions.criticalAlerts != .unavailable {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label {
                                Text("Critical Alerts")
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                            }

                            Spacer()

                            Text(criticalAlertStatusTitle)
                                .foregroundStyle(.secondary)
                        }

                        if store.permissions.criticalAlerts == .enabled {
                            Button {
                                store.send(.criticalAlertPermissionButtonTapped)
                            } label: {
                                Text(criticalAlertPermissionButtonTitle)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                store.send(.criticalAlertPermissionButtonTapped)
                            } label: {
                                Text(criticalAlertPermissionButtonTitle)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Always Deliver Immediately")
                } footer: {
                    Text(
                        "Critical Alerts appear on the Lock Screen and play a sound even if a Focus is on or iPhone is muted."
                    )
                }
            }
            #endif
            #endif

            if case let .some(.active(grant)) = authoringPhase,
               grant.access.canEditContent
            {
                Section("Policies") {
                    Button {
                        store.send(.eventPoliciesButtonTapped)
                    } label: {
                        Label {
                            Text(
                                "Event Policies",
                                bundle: .module,
                                comment: "Button that opens the event policy editor"
                            )
                        } icon: {
                            MappedSystemImage(systemName: "slider.horizontal.3")
                        }
                    }
                }

                Section("Error Handling") {
                    Button {
                        store.send(.testErrorButtonTapped)
                    } label: {
                        Label {
                            Text(
                                "Send Test Error",
                                bundle: .module,
                                comment: "Developer button that reports a test error"
                            )
                        } icon: {
                            MappedSystemImage(systemName: "exclamationmark.triangle")
                        }
                    }
                }
            }
        }
        .navigationTitle("Event Settings")
        .alert(
            "Delete unpublished changes?",
            isPresented: $store.scope(
                \.destination,
                action: \.destination
            ).exitAuthoringConfirmation.isPresented
        ) {
            Button(role: .destructive) {
                store.send(
                    .destination(
                        .exitAuthoringConfirmation(.exitAndDeleteButtonTapped)
                    )
                )
            } label: {
                Text(
                    "Leave and Delete Changes",
                    bundle: .module,
                    comment: "Destructive confirmation that leaves the workspace and deletes local edits"
                )
            }
            Button("Keep Editing", role: .cancel) {
                store.send(
                    .destination(
                        .exitAuthoringConfirmation(.cancelButtonTapped)
                    )
                )
            }
        } message: {
            Text(
                "Leaving the workspace restores Published content and permanently deletes unpublished changes on this device.",
                bundle: .module,
                comment: "Warning shown before leaving a workspace with unpublished edits"
            )
        }
    }
}

private struct EventSettingsTestError: UserFacingErrorConvertible {
    func userFacingError(in context: ErrorHandlingContext) -> ParsedError {
        ParsedError(
            message: .eventSettingsTestError,
            kind: .eventSettingsTestError,
            debugDescription: "Event settings test error"
        )
    }
}

private func throwEventSettingsTestError() async throws {
    throw EventSettingsTestError()
}

private extension UserFacingText {
    static let eventSettingsTestError = Self(
        "Test error.",
        fallback: "Test error."
    )

    static let notificationPermissionRequestFailed = Self(
        "Open Music Event could not request notification permission.",
        fallback: "Open Music Event could not request notification permission."
    )
}

private extension ErrorOperation {
    static let eventSettingsTestError = Self("event.settings.test-error")
    static let notificationPermissionRequest = Self("event.settings.notification-permission")
}

private extension ErrorKind {
    static let eventSettingsTestError = Self("event.settings.test-error")
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
