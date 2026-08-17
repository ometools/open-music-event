import ComposableArchitecture2
import Dependencies
import ErrorHandling
import OpenMusicEventAuthentication
import OpenMusicEventComponents
import OpenMusicEventLexicon
import OpenMusicEventWhiteLabel
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

/// A branded entry point into an organizer's public detail and events.
@Feature
public struct WhiteLabelRoot {
    public init() {}

    public struct State {
        public init(configuration: WhiteLabelAppConfiguration) {
            self.configuration = configuration
        }

        public var configuration: WhiteLabelAppConfiguration
        public var errorMessage: String?
        public var isLoading = false
        public var organizationDetail: Spawn<OrganizationDetail>?
        public var settings: Settings.State?
    }

    public enum Action {
        case retryButtonTapped
        case settings(Settings.Action)
        case settingsButtonTapped
        case task
    }

    @Dependency(\.whiteLabelOrganizerIdentityResolver) var identityResolver

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .retryButtonTapped, .task:
                guard !state.isLoading else { return }
                state.isLoading = true
                state.errorMessage = nil
                let configuration = state.configuration
                store.addTask {
                    let organizerID = await store.withErrorHandling(
                        fallbackMessage: .whiteLabelLoadFailed,
                        operation: .whiteLabelLoad
                    ) {
                        try await Self.organizerID(
                            configuration,
                            identityResolver: identityResolver
                        )
                    }

                    guard let organizerID else {
                        try store.modify {
                            $0.isLoading = false
                            $0.errorMessage = UserFacingText.whiteLabelLoadFailed.localizedString
                        }
                        return
                    }
                    try store.modify {
                        $0.isLoading = false
                        $0.organizationDetail = Spawn(
                            OrganizationDetail.State(organizerID: organizerID)
                        )
                    }
                }

            case .settings:
                break

            case .settingsButtonTapped:
                state.settings = Settings.State()
            }
        }
        .onMount { state in
            guard !state.isLoading else { return }
            state.isLoading = true
            state.errorMessage = nil
            let configuration = state.configuration
            store.addTask {
                let organizerID = await store.withErrorHandling(
                    fallbackMessage: .whiteLabelLoadFailed,
                    operation: .whiteLabelLoad
                ) {
                    try await Self.organizerID(
                        configuration,
                        identityResolver: identityResolver
                    )
                }
                guard let organizerID else {
                    try store.modify {
                        $0.isLoading = false
                        $0.errorMessage = UserFacingText.whiteLabelLoadFailed.localizedString
                    }
                    return
                }
                try store.modify {
                    $0.isLoading = false
                    $0.organizationDetail = Spawn(
                        OrganizationDetail.State(organizerID: organizerID)
                    )
                }
            }
        }
        .ifLet(\.organizationDetail) {
            OrganizationDetail()
        }
        .ifLet(\.settings, action: \.settings) {
            Settings()
        }
    }

    private static func organizerID(
        _ configuration: WhiteLabelAppConfiguration,
        identityResolver: WhiteLabelOrganizerIdentityResolverClient
    ) async throws -> OME.Organizer.ID {
        if let organizerID = configuration.organizerID {
            return organizerID
        }
        if let handle = configuration.handle {
            return try await identityResolver.resolve(handle)
        }
        if let organizerID = configuration.developmentOrganizerID {
            return organizerID
        }
        throw WhiteLabelError.missingOrganizerIdentity(configuration.brand.displayName)
    }
}

public struct WhiteLabelRootView: View {
    public init(
        store: StoreOf<WhiteLabelRoot>,
        serviceEnvironment: OpenMusicEventServiceEnvironment,
        isServiceEnvironmentSelectionEnabled: Bool,
        isServiceEnvironmentSwitching: Bool,
        serviceEnvironmentSelected: @escaping (OpenMusicEventServiceEnvironment) -> Void
    ) {
        self.store = store
        self.serviceEnvironment = serviceEnvironment
        self.isServiceEnvironmentSelectionEnabled = isServiceEnvironmentSelectionEnabled
        self.isServiceEnvironmentSwitching = isServiceEnvironmentSwitching
        self.serviceEnvironmentSelected = serviceEnvironmentSelected
    }

    @Bindable var store: StoreOf<WhiteLabelRoot>
    let serviceEnvironment: OpenMusicEventServiceEnvironment
    let isServiceEnvironmentSelectionEnabled: Bool
    let isServiceEnvironmentSwitching: Bool
    let serviceEnvironmentSelected: (OpenMusicEventServiceEnvironment) -> Void

    public var body: some View {
        NavigationStack {
            Group {
                if let organizationStore = store.spawn(\.organizationDetail) {
                    OrganizationDetailView(store: organizationStore)
                } else {
                    VStack(spacing: 16) {
                        if let loadingImage = store.configuration.brand.loadingImage {
                            Image(loadingImage.name, bundle: Bundle(url: loadingImage.bundleURL))
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 320, maxHeight: 240)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: store.configuration.brand.systemImage)
                                .font(.largeTitle)
                        }
                        Text(store.configuration.brand.displayName)
                            .font(.title)
                        if store.isLoading {
                            ProgressView()
                        }
                        if let errorMessage = store.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Try Again") { store.send(.retryButtonTapped) }
                        }
                    }
                    .padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.settingsButtonTapped)
                    } label: {
                        MappedSystemImage(systemName: "gearshape")
                    }
                    .accessibilityLabel(
                        Text(
                            "Settings",
                            bundle: .module,
                            comment: "button that opens white-label application settings"
                        )
                    )
                }
            }
        }
        .sheet(item: $store.scope(\.settings, action: \.settings)) { settingsStore in
            NavigationStack {
                SettingsFeatureView(
                    store: settingsStore,
                    serviceEnvironment: serviceEnvironment,
                    isServiceEnvironmentSelectionEnabled: isServiceEnvironmentSelectionEnabled,
                    isServiceEnvironmentSwitching: isServiceEnvironmentSwitching,
                    serviceEnvironmentSelected: serviceEnvironmentSelected
                )
            }
        }
    }
}

private extension UserFacingText {
    static let whiteLabelLoadFailed = Self(
        "Unable to load organizer.",
        fallback: "Unable to load organizer."
    )
}

private extension ErrorOperation {
    static let whiteLabelLoad = Self("white-label.load")
}
