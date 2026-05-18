import ComposableArchitecture2
import ErrorHandling
import OpenMusicEventDatabase
import SwiftUI

@Feature
public struct EventSettings {
    public init() {}

    public struct State {
        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
        }

        public var eventID: OMERecord.Event.ID
    }

    public enum Action {
        case testErrorButtonTapped
    }

    public var body: some Feature {
        Update { _, action in
            switch action {
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
    let store: StoreOf<EventSettings>

    public init(store: StoreOf<EventSettings>) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Error Handling") {
                Button {
                    store.send(.testErrorButtonTapped)
                } label: {
                    Label("Send Test Error", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .navigationTitle("Event Settings")
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
