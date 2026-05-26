import ComposableArchitecture2
import ErrorHandling
import OpenMusicEventAuthentication
import SwiftUI

@Feature
public struct Settings {
    public init() {}

    public struct State: Equatable {
        public init() {}

        public var account = Spawn(Account.State())
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
                        fallbackMessage: .settingsTestError,
                        operation: .settingsTestError
                    ) {
                        try await throwSettingsTestError()
                    }
                }
            }
        }
        .spawn(\.account) {
            Account()
        }
    }
}

public struct SettingsFeatureView: View {
    let store: StoreOf<Settings>

    public init(store: StoreOf<Settings>) {
        self.store = store
    }

    public var body: some View {
        Form {
            AccountView(store: store.spawn(\.account))

            Section("Error Handling") {
                Button {
                    store.send(.testErrorButtonTapped)
                } label: {
                    Label("Send Test Error", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .navigationTitle("Settings")
    }
}

private struct SettingsTestError: UserFacingErrorConvertible {
    func userFacingError(in context: ErrorHandlingContext) -> ParsedError {
        ParsedError(
            message: .settingsTestError,
            kind: .settingsTestError,
            debugDescription: "Settings test error"
        )
    }
}

private func throwSettingsTestError() async throws {
    throw SettingsTestError()
}
