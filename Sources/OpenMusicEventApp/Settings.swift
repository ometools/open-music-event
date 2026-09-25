import ATProto
import Bluesky
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
        .ifLet(\.destination) {
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
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    let serviceEnvironment: OpenMusicEventServiceEnvironment
    let isServiceEnvironmentSelectionEnabled: Bool
    let isServiceEnvironmentSwitching: Bool
    let serviceEnvironmentSelected: (OpenMusicEventServiceEnvironment) -> Void

    public init(
        store: StoreOf<Settings>,
        serviceEnvironment: OpenMusicEventServiceEnvironment,
        isServiceEnvironmentSelectionEnabled: Bool,
        isServiceEnvironmentSwitching: Bool,
        serviceEnvironmentSelected: @escaping (OpenMusicEventServiceEnvironment) -> Void
    ) {
        self.store = store
        self.accountStore = store.spawn(\.account)
        self.serviceEnvironment = serviceEnvironment
        self.isServiceEnvironmentSelectionEnabled = isServiceEnvironmentSelectionEnabled
        self.isServiceEnvironmentSwitching = isServiceEnvironmentSwitching
        self.serviceEnvironmentSelected = serviceEnvironmentSelected
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

            if showsTechnicalDetails {
                OpenMusicEventServiceEnvironmentSettingsSection(
                    serviceEnvironment: serviceEnvironment,
                    isSelectionEnabled: isServiceEnvironmentSelectionEnabled,
                    isSwitching: isServiceEnvironmentSwitching,
                    serviceEnvironmentSelected: serviceEnvironmentSelected
                )
            }

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
            item: $store.scope(\.destination).aboutOpenMusicEvent
        ) { aboutStore in
            AboutOpenMusicEventView(store: aboutStore)
        }
        .navigationDestination(
            item: $store.scope(\.destination).feedbackBoard
        ) { feedbackBoardStore in
            UserInputFeedbackBoardView(store: feedbackBoardStore)
        }
        .navigationTitle("Settings")
    }
}

struct OpenMusicEventServiceEnvironmentSettingsSection: View {
    let serviceEnvironment: OpenMusicEventServiceEnvironment
    let isSelectionEnabled: Bool
    let isSwitching: Bool
    let serviceEnvironmentSelected: (OpenMusicEventServiceEnvironment) -> Void

    var body: some View {
        Section {
            Menu {
                Button {
                    serviceEnvironmentSelected(.production)
                } label: {
                    HStack {
                        OpenMusicEventServiceEnvironmentName(environment: .production)
                        if serviceEnvironment == .production {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Button {
                    serviceEnvironmentSelected(.staging)
                } label: {
                    HStack {
                        OpenMusicEventServiceEnvironmentName(environment: .staging)
                        if serviceEnvironment == .staging {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            } label: {
                Label {
                    HStack {
                        Text(
                            "Environment",
                            bundle: .module,
                            comment: "label for the OME service environment picker"
                        )
                        Spacer()
                        OpenMusicEventServiceEnvironmentName(
                            environment: serviceEnvironment
                        )
                    }
                } icon: {
                    Image(systemName: "server")
                }
            }
            .disabled(!isSelectionEnabled || isSwitching)
        } header: {
            Text(
                "OpenMusicEvent Services",
                bundle: .module,
                comment: "header for advanced OME service environment settings"
            )
        } footer: {
            Text(
                "Switching returns to the app root, uses a separate database, and registers notifications with the selected service.",
                bundle: .module,
                comment: "explanation below the OME service environment picker"
            )
        }
    }
}

struct OpenMusicEventServiceEnvironmentName: View {
    let environment: OpenMusicEventServiceEnvironment

    var body: some View {
        switch environment {
        case .production:
            Text(
                "Production",
                bundle: .module,
                comment: "production OME service environment name"
            )
        case .staging:
            Text(
                "Staging",
                bundle: .module,
                comment: "staging OME service environment name"
            )
        }
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
