import ComposableArchitecture2
import ErrorHandling
import OpenMusicEventAuthentication
import OpenMusicEventAppEventViewer
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

    public struct State {
        public init() {}

        public var account = Spawn(Account.State())
        public var destination: Destination.State?
    }

    public enum Action {
        case aboutOpenMusicEventButtonTapped
        case destination(Destination.Action)
        case testErrorButtonTapped
    }

    @Feature
    public enum Destination {
        case aboutOpenMusicEvent(AboutOpenMusicEvent)
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .aboutOpenMusicEventButtonTapped:
                state.destination = .aboutOpenMusicEvent(
                    AboutOpenMusicEvent.State()
                )

            case .destination:
                break

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
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct SettingsFeatureView: View {
    @Bindable var store: StoreOf<Settings>
    @Bindable var accountStore: StoreOf<Account>

    public init(store: StoreOf<Settings>) {
        self.store = store
        self.accountStore = store.spawn(\.account)
    }

    public var body: some View {
        _SwiftUIForm {
            AccountView(store: accountStore)

            Section("About") {
                Button("About OpenMusicEvent") {
                    store.send(.aboutOpenMusicEventButtonTapped)
                }
                .navigationLinkListRowStyle()
            }

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
        .sheet(
            item: $accountStore.presentation,
            onDismiss: { accountStore.send(.accountPresentationDismissed) }
        ) { _ in
            AccountPresentationView(store: accountStore)
        }
        .navigationDestination(
            item: $store.scope(\.destination, action: \.destination).aboutOpenMusicEvent
        ) { aboutStore in
            AboutOpenMusicEventView(store: aboutStore)
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
