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
    }

    public enum Action {
        case destination(Destination.Action)
        case enterAuthoringButtonTapped
        case eventPoliciesButtonTapped
        case exitAuthoringButtonTapped
        case notificationPermissionButtonTapped
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

            case .notificationPermissionButtonTapped:
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
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct EventSettingsView: View {
    @Bindable var store: StoreOf<EventSettings>
    @Environment(\.openMusicEventAuthoringPhase) var authoringPhase
    @State var isNotificationPermissionExpanded: Bool

    public init(store: StoreOf<EventSettings>) {
        self.store = store
        _isNotificationPermissionExpanded = State(
            initialValue: store.permissions.notifications == .unknown
        )
    }

    var notificationStatusTitle: String {
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

    var notificationSystemImage: String {
        switch store.permissions.notifications {
        case .authorized, .limited:
            "bell.fill"
        case .denied, .restricted:
            "bell.slash"
        case .unknown:
            "bell"
        }
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
            Section("Permissions") {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        isNotificationPermissionExpanded.toggle()
                    } label: {
                        HStack(spacing: 10) {
                            MappedSystemImage(systemName: notificationSystemImage)
                                .frame(width: 22, height: 22)

                            Text("Notifications")

                            Spacer()

                            Text(notificationStatusTitle)
                                .foregroundStyle(.secondary)

                            MappedSystemImage(
                                systemName: isNotificationPermissionExpanded
                                    ? "chevron.up"
                                    : "chevron.down"
                            )
                            .frame(width: 12, height: 12)
                        }
                    }
                    .buttonStyle(.plain)

                    if isNotificationPermissionExpanded {
                        Divider()

                        switch store.permissions.notifications {
                        case .authorized:
                            Text("Get schedule changes and important updates from this event.")
                                .foregroundStyle(.secondary)
                            Button("Manage Notifications") {
                                store.send(.openNotificationSettingsButtonTapped)
                            }

                        case .limited:
                            Text("Notifications are being delivered quietly.")
                                .foregroundStyle(.secondary)
                            Button("Manage Notifications") {
                                store.send(.openNotificationSettingsButtonTapped)
                            }

                        case .denied, .restricted:
                            Text("Turn notifications on in system settings to get event updates.")
                                .foregroundStyle(.secondary)
                            Button("Open Notification Settings") {
                                store.send(.openNotificationSettingsButtonTapped)
                            }

                        case .unknown:
                            Text("Get schedule changes and important updates from this event.")
                                .foregroundStyle(.secondary)
                            Button("Allow Notifications") {
                                store.send(.notificationPermissionButtonTapped)
                            }
                        }
                    }
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
        .onChange(of: store.permissions.notifications) { _, authorization in
            if authorization != .unknown {
                isNotificationPermissionExpanded = false
            }
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
