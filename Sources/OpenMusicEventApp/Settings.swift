import ATProto
import BlueskyActorCache
import ComposableArchitecture2
import ComposableAtmosphereUserInput
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
        case feedbackBoard(UserInputFeedbackBoard)
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
                    UserInputFeedbackBoard.State()
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
                .transformDependency(\.userInputActorProfileLookup) {
                    $0 = .openMusicEventActorCache
                }
        }
        .onEvent(UserInputFeedbackBoardOperationFailed.self) { failure, _ in
            store.addTask {
                switch failure.operation {
                case .createDiscussion,
                     .createReply,
                     .deleteDiscussion,
                     .deleteReply,
                     .toggleUpvote:
                    await store.reportError(
                        failure.underlyingError,
                        fallbackMessage: .feedbackSubmissionFailed,
                        operation: .feedbackSubmission
                    )
                case .loadBoard,
                     .loadDiscussion:
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
                        Label("Feedback", systemImage: "bubble.left.and.bubble.right")
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

extension UserInputActorProfileLookupClient {
    static var openMusicEventActorCache: Self {
        Self { dids in
            @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache

            var profiles: [DID: UserInputActorProfile] = [:]
            for did in dids {
                let refreshedProfile = try? await blueskyActorProfileCache
                    .refreshProfileIfNeeded(
                        did.description,
                        60 * 60 * 24,
                        60 * 15
                    )
                let cachedProfile = try? await blueskyActorProfileCache
                    .cachedProfile(did.description)
                guard let profile = refreshedProfile ?? cachedProfile,
                      let profileDID = profile.didValue
                else { continue }
                profiles[profileDID] = UserInputActorProfile(
                    did: profileDID,
                    handle: profile.handle,
                    displayName: profile.displayName,
                    avatar: profile.avatar
                )
            }
            return profiles
        }
    }
}
