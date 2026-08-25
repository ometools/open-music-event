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
        public var criticalAlertsAreAllowed = false
        public var destination: Destination.State?
        public var eventID: OMERecord.Event.ID
        public var notificationsAreAllowed = false
        @SharedReader(.devicePermissions) public var permissions: DevicePermissions

        public var notificationIndicatorValue: Int? {
            permissions.notificationSetupBadgeValue
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case enterAuthoringButtonTapped
        case eventPoliciesButtonTapped
        case exitAuthoringButtonTapped
        case openNotificationSettingsButtonTapped
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

            case .openNotificationSettingsButtonTapped:
                store.addTask {
                    _ = await devicePermissions.openNotificationSettings()
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
        .onChange(of: store.criticalAlertsAreAllowed) { _, isOn, state in
            guard isOn else { return }

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

            case .disabled:
                state.criticalAlertsAreAllowed = false
                store.addTask {
                    _ = await devicePermissions.openNotificationSettings()
                }

            case .enabled, .unavailable:
                break
            }
        }
        .onChange(of: store.notificationsAreAllowed) { _, isOn, state in
            guard isOn else { return }

            switch state.permissions.notifications {
            case .unknown:
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

            case .denied, .restricted:
                state.notificationsAreAllowed = false
                store.addTask {
                    _ = await devicePermissions.openNotificationSettings()
                }

            case .authorized, .limited:
                break
            }
        }
        .onChange(of: store.permissions, initial: true) { _, permissions, state in
            state.criticalAlertsAreAllowed = permissions.criticalAlerts == .enabled
            state.notificationsAreAllowed = permissions.notificationsAreAllowed
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

    public var body: some View {
        Form {
            switch authoringPhase {
            case .some(.entering):
                Section("Authoring") {
                    ProgressView("Authorizing source access")
                }

            case .some(.restoring):
                Section("Authoring") {
                    ProgressView("Restoring source access")
                }

            case .some(.exiting):
                Section("Authoring") {
                    ProgressView("Exiting authoring")
                }

            case .some(.active):
                Section("Authoring") {
                    Button("Exit Authoring") {
                        store.send(.exitAuthoringButtonTapped)
                    }
                }

            case .some(.inactive(.eligible)):
                Section("Authoring") {
                    Button("Enter Authoring") {
                        store.send(.enterAuthoringButtonTapped)
                    }
                }

            case .some(.inactive), .none:
                EmptyView()
            }

            #if os(iOS) || os(Android)
            Section {
                Toggle(
                    "Allow Notifications",
                    isOn: $store.notificationsAreAllowed
                )
                .tint(.green)
            }

            #if os(iOS)
            if store.permissions.criticalAlerts != .unavailable {
                Section {
                    Toggle(
                        isOn: $store.criticalAlertsAreAllowed
                    ) {
                        Label {
                            Text("Critical Alerts")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .disabled(!store.notificationsAreAllowed)
                    .tint(.green)
                } header: {
                    Text("Always Deliver Immediately")
                } footer: {
                    Text(
                        "Critical Alerts appear on the Lock Screen and play a sound even if a Focus is on or iPhone is muted."
                    )
                }
            }
            #endif

            Section("Alerts") {
                Button("Open Notification Settings") {
                    store.send(.openNotificationSettingsButtonTapped)
                }
            }
            #endif

            if case let .some(.active(grant)) = authoringPhase,
               grant.access.canEditContent
            {
                Section("Policies") {
                    Button {
                        store.send(.eventPoliciesButtonTapped)
                    } label: {
                        Label("Event Policies", systemImage: "slider.horizontal.3")
                    }
                }

                Section("Error Handling") {
                    Button {
                        store.send(.testErrorButtonTapped)
                    } label: {
                        Label("Send Test Error", systemImage: "exclamationmark.triangle")
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
            Button("Exit and Delete Changes", role: .destructive) {
                store.send(
                    .destination(
                        .exitAuthoringConfirmation(.exitAndDeleteButtonTapped)
                    )
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
                "Exiting authoring restores Published content and permanently deletes unpublished changes on this device."
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
