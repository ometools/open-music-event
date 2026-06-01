import ComposableArchitecture2
import ErrorHandling
import OpenMusicEventDatabase
import SwiftUI

@Feature
public struct EventSettings {
    public init() {}

    public struct State {
        public init(
            eventID: OMERecord.Event.ID,
            destination: Destination.State? = nil
        ) {
            self.destination = destination
            self.eventID = eventID
        }

        public var destination: Destination.State?
        public var eventID: OMERecord.Event.ID
    }

    public enum Action {
        case destination(Destination.Action)
        case eventPoliciesButtonTapped
        case testErrorButtonTapped
    }

    @Feature
    public enum Destination {
        case editEventPolicies(Spawn<EditEventPolicies>)
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case .eventPoliciesButtonTapped:
                store.withDependencies {
                    state.destination = .editEventPolicies(
                        Spawn(EditEventPolicies.State(eventID: state.eventID))
                    )
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
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct EventSettingsView: View {
    @Bindable var store: StoreOf<EventSettings>

    public init(store: StoreOf<EventSettings>) {
        self.store = store
    }

    public var body: some View {
        Form {
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
        .navigationTitle("Event Settings")
        .navigationDestination(
            item: $store.scope(\.destination, action: \.destination).editEventPolicies
        ) { editStore in
            EditEventPoliciesView(store: editStore)
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
}

private extension ErrorOperation {
    static let eventSettingsTestError = Self("event.settings.test-error")
}

private extension ErrorKind {
    static let eventSettingsTestError = Self("event.settings.test-error")
}
