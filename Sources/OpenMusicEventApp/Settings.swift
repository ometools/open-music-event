import ComposableArchitecture2
import ComposableAtmosphereUserInputUI
import Dependencies
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
        public init() {
            @Dependency(\.openMusicEventAppConfiguration) var configuration
            self.showsFeedbackBoard = configuration.productFeedbackBoard?.userInputConfiguration != nil
        }

        public var account = Spawn(Account.State())
        public var destination: Destination.State?
        public var showsFeedbackBoard: Bool
    }

    public enum Action {
        case aboutOpenMusicEventButtonTapped
        case destination(Destination.Action)
        case feedbackButtonTapped
        case testErrorButtonTapped
    }

    @Feature
    public enum Destination {
        case aboutOpenMusicEvent(AboutOpenMusicEvent)
        case feedbackBoard(Spawn<UserInputFeedbackBoard>)
    }

    @Dependency(\.openMusicEventAppConfiguration) var configuration

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .aboutOpenMusicEventButtonTapped:
                state.destination = .aboutOpenMusicEvent(
                    AboutOpenMusicEvent.State()
                )

            case .destination:
                break

            case .feedbackButtonTapped:
                guard configuration.productFeedbackBoard?.userInputConfiguration != nil else {
                    return
                }
                state.destination = .feedbackBoard(
                    Spawn(UserInputFeedbackBoard.State())
                )

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
                .transformDependency(\.userInputFeedbackBoardConfiguration) {
                    $0 = configuration.productFeedbackBoard?.userInputConfiguration
                }
        }
        .onEvent(UserInputFeedbackBoardOperationFailed.self) { failure, _ in
            store.addTask {
                switch failure.operation {
                case .createDiscussion:
                    await store.reportError(
                        failure.underlyingError,
                        fallbackMessage: .feedbackSubmissionFailed,
                        operation: .feedbackSubmission
                    )
                case .loadBoard:
                    await store.reportError(
                        failure.underlyingError,
                        fallbackMessage: .feedbackBoardLoadFailed,
                        operation: .feedbackBoardLoad
                    )
                }
            }
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

            if store.showsFeedbackBoard {
                Section("Feedback") {
                    Button {
                        store.send(.feedbackButtonTapped)
                    } label: {
                        Label("Feedback", systemImage: "chatbubbles")
                    }
                    .navigationLinkListRowStyle()
                }
            }

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
        .navigationDestination(
            item: $store.scope(\.destination, action: \.destination).feedbackBoard
        ) { feedbackBoardStore in
            UserInputFeedbackBoardView(store: feedbackBoardStore)
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
