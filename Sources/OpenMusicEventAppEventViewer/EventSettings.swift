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
        public var eventID: OMERecord.Event.ID
    }

    public enum Action {
        case enterAuthoringButtonTapped
        case eventPoliciesButtonTapped
        case exitAuthoringButtonTapped
        case retryWorkspacePreparationButtonTapped
        case testErrorButtonTapped
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
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
                store.addTask {
                    let task = try store.post(key: AuthoringExitRequested.self, value: ())
                    await task?.value
                }

            case .retryWorkspacePreparationButtonTapped:
                store.addTask {
                    let task = try store.post(
                        key: SourceWorkspacePreparationRetryRequested.self,
                        value: ()
                    )
                    await task?.value
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
            }
        }
    }
}

public struct EventSettingsView: View {
    @Bindable var store: StoreOf<EventSettings>
    let authoringAccess: AuthoringAccess
    let authoringAdmission: ComposableAuthoring.AuthoringAdmission?
    let authoringPhase: AuthoringPhase<AuthoringGrant>?
    @Environment(\.openMusicEventWorkspacePhase) var workspacePhase

    public init(
        store: StoreOf<EventSettings>,
        authoringAccess: AuthoringAccess,
        authoringAdmission: ComposableAuthoring.AuthoringAdmission?,
        authoringPhase: AuthoringPhase<AuthoringGrant>? = nil
    ) {
        self.store = store
        self.authoringAccess = authoringAccess
        self.authoringAdmission = authoringAdmission
        self.authoringPhase = authoringPhase
    }

    public var body: some View {
        Form {
            if authoringPhase?.isEntering == true {
                Section("Authoring") {
                    ProgressView("Authorizing source access")
                }
            } else if authoringPhase?.isRestoring == true {
                Section("Authoring") {
                    ProgressView("Restoring source access")
                }
            } else if authoringPhase?.isExiting == true {
                Section("Authoring") {
                    ProgressView("Exiting authoring")
                }
            } else if workspacePhase.isPreparingSource {
                Section("Authoring") {
                    ProgressView("Preparing source workspace")
                    Button("Exit Authoring") {
                        store.send(.exitAuthoringButtonTapped)
                    }
                }
            } else if case .sourcePreparationFailed = workspacePhase {
                Section("Authoring") {
                    WorkspacePublicationStatusView(phase: workspacePhase)
                    Button("Retry workspace preparation") {
                        store.send(.retryWorkspacePreparationButtonTapped)
                    }
                    Button("Exit Authoring") {
                        store.send(.exitAuthoringButtonTapped)
                    }
                }
            } else if authoringPhase?.isActive == true,
                      !authoringAccess.canEditContent
            {
                Section("Authoring") {
                    ProgressView("Starting source workspace")
                    Button("Exit Authoring") {
                        store.send(.exitAuthoringButtonTapped)
                    }
                }
            } else if authoringAccess.canEditContent {
                Section("Authoring") {
                    Button("Exit Authoring") {
                        store.send(.exitAuthoringButtonTapped)
                    }
                }
            } else if case .available = authoringAdmission {
                Section("Authoring") {
                    Button("Enter Authoring") {
                        store.send(.enterAuthoringButtonTapped)
                    }
                }
            }

            if authoringAccess.canEditContent {
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
    }
}

private extension AuthoringPhase {
    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var isEntering: Bool {
        if case .entering = self { return true }
        return false
    }

    var isExiting: Bool {
        if case .exiting = self { return true }
        return false
    }

    var isRestoring: Bool {
        if case .restoring = self { return true }
        return false
    }
}

private extension WorkspacePhase where ChangeSet == SourcePatch {
    var isPreparingSource: Bool {
        if case .preparingSource = self { return true }
        return false
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
}

private extension ErrorOperation {
    static let eventSettingsTestError = Self("event.settings.test-error")
}

private extension ErrorKind {
    static let eventSettingsTestError = Self("event.settings.test-error")
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
