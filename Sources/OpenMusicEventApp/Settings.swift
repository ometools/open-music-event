import ComposableArchitecture2
import ErrorHandling
import OpenMusicEventAuthentication
import OpenMusicEventComponents
import SwiftUI

#if os(Android)
private typealias _SwiftUIForm = SkipSwiftUI.Form
#else
private typealias _SwiftUIForm = SwiftUI.Form
#endif

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
        let accountStore = store.spawn(\.account)

        _SwiftUIForm {
            AccountView(store: accountStore)

            TechnicalDetailsSettingsSection()

            Section("Error Handling") {
                Button {
                    store.send(.testErrorButtonTapped)
                } label: {
                    Label("Send Test Error", systemImage: "exclamationmark.triangle")
                }
            }
        }
        #if os(macOS)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        #endif
        .accountAuthenticationSheet(store: accountStore)
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
