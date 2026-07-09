import ATProtoOAuth
import ComposableArchitecture2
import Dependencies
import OpenMusicEventComponents
import SwiftUI
import TCATProtoAuthentication

public typealias AuthenticationCoordinator = OAuthAuthenticationCoordinator
public typealias AuthorizationFlowSheetView = OpenMusicEventAuthorizationFlowSheetView

public extension OAuthAuthenticationCoordinator.State {
    init() {
        self.init(storage: OpenMusicEventOAuth.storage)
    }
}

public struct AuthenticationCoordinatorView<Content: View>: View {
    @Bindable var store: StoreOf<AuthenticationCoordinator>
    let isPresentationEnabled: Bool
    let content: Content

    public init(
        store: StoreOf<AuthenticationCoordinator>,
        isPresentationEnabled: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.store = store
        self.isPresentationEnabled = isPresentationEnabled
        self.content = content()
    }

    public var body: some View {
        if isPresentationEnabled {
            content
                .sheet(item: $store.scope(\.authorization, action: \.authorization)) { authorizationStore in
                    OpenMusicEventAuthorizationFlowSheetView(store: authorizationStore)
                }
        } else {
            content
        }
    }
}

public struct OpenMusicEventAuthorizationFlowSheetView: View {
    @Bindable var store: StoreOf<AuthorizationFlow>

    public init(store: StoreOf<AuthorizationFlow>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            OpenMusicEventAuthorizationFormView(store: store)
        }
    }
}

public struct OpenMusicEventAuthorizationFormView: View {
    @Bindable var store: StoreOf<AuthorizationFlow>

    public init(store: StoreOf<AuthorizationFlow>) {
        self.store = store
    }

    public var body: some View {
        SwiftUI.Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Atmosphere account")
                        .font(.headline)
                    Text(
                        "Use one portable social account across Open Music Event and other AT Protocol apps."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker("Account action", selection: selectedAccountAction) {
                    ForEach(AccountAction.allCases) { action in
                        Text(action.title)
                            .tag(action)
                    }
                }
                .pickerStyle(.segmented)

                switch store.mode {
                case .signIn:
                    Text(AccountAction.signIn.helperText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextField("name.atmo.social", text: $store.loginHint)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif

                case .signUp:
                    Text(AccountAction.signUp.helperText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if store.mode == .signUp {
                    authorizationSignUpServerForm
                }
            } footer: {
                Text("Already use Bluesky? Your Bluesky handle works too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = store.error {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(error.message)
                            .font(.headline)
                        if let subtitle = error.subtitle {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Account")
        .safeEdgeExpansion(edge: .bottom) {
            authorizationSubmitButton
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    store.send(.cancel)
                }
            }
        }
    }

    @ViewBuilder
    private var authorizationSignUpServerForm: some View {
        Section("Provider") {
            ForEach(store.signUpServerConfiguration.options) { option in
                Button {
                    store.send(.signUpServerOptionTapped(option.id))
                } label: {
                    AccountSignUpServerOptionRow(
                        option: option,
                        isSelected: store.selectedSignUpServerOptionID == option.id
                    )
                }
                .buttonStyle(.plain)
                .disabled(option.isComingSoon)
            }

            if store.signUpServerConfiguration.allowsCustomServerHost {
                Button {
                    store.send(.customSignUpServerOptionTapped)
                } label: {
                    AccountCustomSignUpServerOptionRow(
                        isSelected: store.usesCustomSignUpServerHost
                    )
                }
                .buttonStyle(.plain)
            }
        }

        if store.showsSignUpServerTextField {
            Section("Server") {
                TextField("Server Host", text: $store.serverHost)
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            }
        }
    }

    private var authorizationSubmitButton: some View {
        SubmitButton(
            isInProgress: store.isLoading,
            isDisabled: store.isSubmitDisabled
        ) {
            store.send(.submit)
        }
        .controlSize(.extraLarge)
    }

    private var selectedAccountAction: Binding<AccountAction> {
        Binding {
            AccountAction(mode: store.mode)
        } set: { action in
            $store.mode.wrappedValue = action.mode
        }
    }
}

private enum AccountAction: String, CaseIterable, Identifiable {
    case signIn
    case signUp

    var id: Self { self }

    init(mode: AuthorizationPresentationMode) {
        switch mode {
        case .signIn:
            self = .signIn
        case .signUp:
            self = .signUp
        }
    }

    var mode: AuthorizationPresentationMode {
        switch self {
        case .signIn:
            .signIn
        case .signUp:
            .signUp
        }
    }

    var helperText: String {
        switch self {
        case .signIn:
            "Sign in with your handle, like name.atmo.social or your own domain."
        case .signUp:
            "Choose a provider to create your Atmosphere account. Your provider hosts your account and data, and you can move later."
        }
    }

    var title: String {
        switch self {
        case .signIn:
            "Sign In"
        case .signUp:
            "Create Account"
        }
    }
}

public extension OpenMusicEventOAuth {
    static func authorizationFlowState(
        for request: AuthorizationPresentationRequest,
        session: OAuth.Session?,
        sessionStore: OAuth.SessionStore
    ) -> AuthorizationFlow.State {
        @Dependency(\.openMusicEventSignUpServerConfiguration)
        var signUpServerConfiguration
        return OAuthAuthenticationCoordinator.authorizationFlowState(
            for: request.openMusicEventDefaultingSignUpServerConfiguration(
                signUpServerConfiguration
            ),
            session: session,
            sessionStore: sessionStore
        )
    }

    static func authorizationFlowState(
        for request: AuthorizationPresentationRequest
    ) -> AuthorizationFlow.State {
        authorizationFlowState(
            for: request,
            session: session.wrappedValue,
            sessionStore: sessionStore.wrappedValue
        )
    }
}
