import ATProtoOAuth
import ComposableArchitecture2
import Dependencies
import Sharing
import SwiftUI
import TCATProtoAuthentication

@Feature
public struct Account {
    public init() {}

    public enum Mode: String, CaseIterable, Equatable, Hashable, Sendable {
        case signIn
        case signUp

        var helperText: String {
            switch self {
            case .signIn:
                "Already have one? Sign in with your handle, like name.bsky.social or your own domain."
            case .signUp:
                "Create an account with a provider. Bsky and Eurosky work today; ome.social accounts are coming soon."
            }
        }

        var progressTitle: String {
            switch self {
            case .signIn:
                "Signing In..."
            case .signUp:
                "Signing Up..."
            }
        }

        var systemImage: String {
            switch self {
            case .signIn:
                "person.crop.circle.badge.checkmark"
            case .signUp:
                "person.crop.circle.badge.plus"
            }
        }

        var title: String {
            switch self {
            case .signIn:
                "Sign In"
            case .signUp:
                "Sign Up"
            }
        }
    }

    public struct State: Equatable {
        public init(
            isAuthenticationSheetPresented: Bool = false,
            selectedMode: Mode = .signIn,
            signInLoginHint: String = "",
            storage: OAuthSessionStorage = OpenMusicEventOAuth.storage
        ) {
            let signUpServerConfiguration = OpenMusicEventOAuth.signUpServerConfiguration
            let signUpServerHost = signUpServerConfiguration.defaultServerHost
            let selectedSignUpServerOptionID = signUpServerConfiguration
                .availableOption(serverHost: signUpServerHost)?
                .id

            self.isAuthenticationSheetPresented = isAuthenticationSheetPresented
            self.oauth = Spawn(OAuthAccount.State(storage: storage))
            self.selectedMode = selectedMode
            self.selectedSignUpServerOptionID = selectedSignUpServerOptionID
            self.signInLoginHint = signInLoginHint
            self.signUpServerHost = signUpServerHost
            self.usesCustomSignUpServerHost =
                !signUpServerConfiguration.options.isEmpty &&
                signUpServerConfiguration.allowsCustomServerHost &&
                selectedSignUpServerOptionID == nil
        }

        public init(
            isAuthenticationSheetPresented: Bool = false,
            selectedMode: Mode = .signIn,
            signInLoginHint: String = "",
            authFailureMessage: Shared<ErrorMessage?>,
            session: Shared<OAuth.Session?>,
            sessionStore: Shared<OAuth.SessionStore>
        ) {
            self.init(
                isAuthenticationSheetPresented: isAuthenticationSheetPresented,
                selectedMode: selectedMode,
                signInLoginHint: signInLoginHint,
                storage: OAuthSessionStorage(
                    session: session,
                    sessionStore: sessionStore,
                    authFailureMessage: authFailureMessage
                )
            )
        }

        public var isAuthenticationSheetPresented: Bool
        public var oauth: Spawn<OAuthAccount>
        public var selectedMode: Mode
        public var selectedSignUpServerOptionID: OAuthSignUpServerOption.ID?
        public var signInLoginHint: String
        public var signUpServerHost: String
        public var usesCustomSignUpServerHost: Bool

        public var accountIDDescription: String? {
            oauth.accountIDDescription
        }

        public var errorMessage: String? {
            oauth.errorMessage
        }

        public var isLoginInProgress: Bool {
            oauth.isLoginInProgress
        }

        public var isSignUpInProgress: Bool {
            oauth.isSignUpInProgress
        }

        public var isWorking: Bool {
            isLoginInProgress || isSignUpInProgress
        }

        public var isAuthenticationFormSubmitDisabled: Bool {
            if isWorking { return true }
            switch selectedMode {
            case .signIn:
                return signInLoginHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .signUp:
                return signUpServerHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }

        public var session: OAuth.Session? {
            oauth.state.session
        }

        public var sessionStore: OAuth.SessionStore {
            oauth.state.sessionStore
        }
    }

    public enum Action {
        case accountButtonTapped
        case authenticationSheetDismissed
        case customSignUpServerOptionTapped
        case loginResponse(Result<OAuth.Session, OAuthAccount.LoginFailure>)
        case selectedModeChanged(Mode)
        case signUpResponse(Result<OAuth.Session, OAuthAccount.LoginFailure>)
        case signUpServerOptionTapped(OAuthSignUpServerOption.ID)
        case submitAuthenticationFormButtonTapped
    }

    @Dependency(\.openMusicEventAccountAuthorizationClient) var accountAuthorizationClient

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .accountButtonTapped:
                state.isAuthenticationSheetPresented = true

            case .authenticationSheetDismissed:
                state.isAuthenticationSheetPresented = false

            case .customSignUpServerOptionTapped:
                guard OpenMusicEventOAuth.signUpServerConfiguration.allowsCustomServerHost else { return }
                state.selectedSignUpServerOptionID = nil
                state.usesCustomSignUpServerHost = true
                state.signUpServerHost = ""

            case .loginResponse(.success(let session)):
                state.oauth.state.isLoginInProgress = false
                state.oauth.state.errorMessage = nil
                state.oauth.state.$sessionStore.withLock {
                    $0.upsert(session)
                }
                state.oauth.state.$session.withLock {
                    $0 = state.oauth.state.sessionStore.selectedSession
                }
                state.isAuthenticationSheetPresented = false

            case .loginResponse(.failure(.cancelled)):
                state.oauth.state.isLoginInProgress = false

            case .loginResponse(.failure(.failed)):
                state.oauth.state.isLoginInProgress = false
                state.oauth.state.errorMessage = "Sign in failed."

            case .selectedModeChanged(let mode):
                state.selectedMode = mode

            case .signUpResponse(.success(let session)):
                state.oauth.state.isSignUpInProgress = false
                state.oauth.state.errorMessage = nil
                state.oauth.state.$sessionStore.withLock {
                    $0.upsert(session)
                }
                state.oauth.state.$session.withLock {
                    $0 = state.oauth.state.sessionStore.selectedSession
                }
                state.isAuthenticationSheetPresented = false

            case .signUpResponse(.failure(.cancelled)):
                state.oauth.state.isSignUpInProgress = false

            case .signUpResponse(.failure(.failed)):
                state.oauth.state.isSignUpInProgress = false
                state.oauth.state.errorMessage = "Sign up failed."

            case .signUpServerOptionTapped(let id):
                guard let option = OpenMusicEventOAuth.signUpServerConfiguration.availableOption(id: id),
                      let serverHost = option.serverHost
                else { return }
                state.selectedSignUpServerOptionID = option.id
                state.usesCustomSignUpServerHost = false
                state.signUpServerHost = serverHost

            case .submitAuthenticationFormButtonTapped:
                guard state.session == nil else {
                    state.isAuthenticationSheetPresented = false
                    return
                }
                guard !state.isAuthenticationFormSubmitDisabled else { return }

                switch state.selectedMode {
                case .signIn:
                    guard !state.isSignUpInProgress else { return }
                    let loginHint = state.signInLoginHint.trimmingCharacters(in: .whitespacesAndNewlines)
                    let sessionStore = state.oauth.state.sessionStore
                    state.oauth.state.errorMessage = nil
                    state.oauth.state.isLoginInProgress = true
                    store.addTask {
                        do {
                            let session = try await accountAuthorizationClient.signIn(
                                OpenMusicEventOAuth.baseAuthRequirement,
                                loginHint,
                                sessionStore
                            )
                            try store.send(.loginResponse(.success(session)))
                        } catch is CancellationError {
                            try store.send(.loginResponse(.failure(.cancelled)))
                        } catch {
                            try store.send(.loginResponse(.failure(.failed(error.localizedDescription))))
                        }
                    }

                case .signUp:
                    guard !state.isLoginInProgress else { return }
                    let serverHost = state.signUpServerHost.trimmingCharacters(in: .whitespacesAndNewlines)
                    state.oauth.state.errorMessage = nil
                    state.oauth.state.isSignUpInProgress = true
                    store.addTask {
                        do {
                            let session = try await accountAuthorizationClient.signUp(
                                OpenMusicEventOAuth.baseAuthRequirement,
                                serverHost
                            )
                            try store.send(.signUpResponse(.success(session)))
                        } catch is CancellationError {
                            try store.send(.signUpResponse(.failure(.cancelled)))
                        } catch {
                            try store.send(.signUpResponse(.failure(.failed(error.localizedDescription))))
                        }
                    }
                }
            }
        }
        .spawn(\.oauth) {
            OAuthAccount(
                baseAuthRequirement: OpenMusicEventOAuth.baseAuthRequirement,
                signUpServerConfiguration: OpenMusicEventOAuth.signUpServerConfiguration
            )
        }
    }
}

public struct AccountView: View {
    @Bindable var store: StoreOf<Account>

    public init(store: StoreOf<Account>) {
        self.store = store
    }

    public var body: some View {
        if store.accountIDDescription != nil {
            OAuthAccountView(store: store.spawn(\.oauth))
        } else {
            Section("Account") {
                Button {
                    store.send(.accountButtonTapped)
                } label: {
                    Label("Sign In or Sign Up", systemImage: "person.crop.circle")
                }

                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

public extension View {
    func accountAuthenticationSheet(store: StoreOf<Account>) -> some View {
        modifier(AccountAuthenticationSheetModifier(store: store))
    }
}

private struct AccountAuthenticationSheetModifier: ViewModifier {
    @Bindable var store: StoreOf<Account>

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $store.isAuthenticationSheetPresented) {
                AccountAuthenticationSheetView(store: store)
            }
    }
}

struct AccountAuthenticationSheetView: View {
    @Bindable var store: StoreOf<Account>

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Atmosphere account")
                            .font(.headline)
                        Text(
                            "An Atmosphere account is the portable social account used by Open Music Event, BlueSky, and other AT Protocol apps."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Picker("Account action", selection: $store.selectedMode) {
                        ForEach(Account.Mode.allCases, id: \.self) { mode in
                            Text(mode.title)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch store.selectedMode {
                    case .signIn:
                            Text(store.selectedMode.helperText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            TextField("Handle", text: $store.signInLoginHint)
                                #if !os(macOS)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif

                    case .signUp:
                            Text(store.selectedMode.helperText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                    }
                }
                if store.selectedMode == .signUp {
                    AccountSignUpServerFormView(store: store)
                }

                if let errorMessage = store.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Account")
            .safeEdgeExpansion(edge: .bottom) {
                AccountAuthenticationSafeEdgeAction(store: store)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        store.send(.authenticationSheetDismissed)
                    }
                }
            }
        }
    }
}

struct SafeEdgeExpansionModifier<ExpansionContent: View>: ViewModifier {
    let edge: VerticalEdge
    let spacing: CGFloat?
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let expansionContent: ExpansionContent

    init(
        edge: VerticalEdge,
        spacing: CGFloat?,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        @ViewBuilder expansionContent: () -> ExpansionContent
    ) {
        self.edge = edge
        self.spacing = spacing
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.expansionContent = expansionContent()
    }

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: edge, spacing: spacing) {
            expansionContent
                .frame(maxWidth: .infinity)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
        }
        .safeEdgeExpansionScrollEdgeEffect(edge)
    }
}

extension View {
    func safeEdgeExpansion<ExpansionContent: View>(
        edge: VerticalEdge,
        spacing: CGFloat? = 0,
        horizontalPadding: CGFloat = 24,
        verticalPadding: CGFloat = 12,
        @ViewBuilder content: @escaping () -> ExpansionContent
    ) -> some View {
        modifier(
            SafeEdgeExpansionModifier(
                edge: edge,
                spacing: spacing,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
                expansionContent: content
            )
        )
    }
}

extension View {
    @ViewBuilder
    func safeEdgeExpansionScrollEdgeEffect(_ edge: VerticalEdge) -> some View {
        #if os(iOS) || os(macOS)
        if #available(iOS 26, macOS 26, *) {
            self.scrollEdgeEffectStyle(.soft, for: edge.edgeSet)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

extension VerticalEdge {
    var edgeSet: Edge.Set {
        switch self {
        case .top:
            .top
        case .bottom:
            .bottom
        }
    }
}

struct AccountAuthenticationSafeEdgeAction: View {
    @Bindable var store: StoreOf<Account>

    var body: some View {
        switch store.selectedMode {
        case .signIn:
            AccountProminentSignInButton(store: store)

        case .signUp:
            AccountAuthenticationSubmitButton(store: store)
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
        }
    }
}

struct AccountAuthenticationSubmitButton: View {
    @Bindable var store: StoreOf<Account>

    var body: some View {
        Button {
            store.send(.submitAuthenticationFormButtonTapped)
        } label: {
            if store.isWorking {
                Label(store.selectedMode.progressTitle, systemImage: "hourglass")
            } else {
                Label(store.selectedMode.title, systemImage: store.selectedMode.systemImage)
            }
        }
        .labelStyle(.titleAndIcon)
        .disabled(store.isAuthenticationFormSubmitDisabled)
    }
}

struct AccountProminentSignInButton: View {
    @Bindable var store: StoreOf<Account>

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            AccountAuthenticationSubmitButton(store: store)
                .frame(minWidth: 220)
                .accountProminentSignInButtonStyle()

            Spacer(minLength: 0)
        }
    }
}

extension View {
    @ViewBuilder
    func accountProminentSignInButtonStyle() -> some View {
        #if os(iOS) || os(macOS)
        if #available(iOS 26, macOS 26, *) {
            self
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
        } else {
            self
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
        }
        #else
        self
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
        #endif
    }
}

struct AccountSignUpServerFormView: View {
    @Bindable var store: StoreOf<Account>

    var body: some View {
        Section("Provider") {
            ForEach(OpenMusicEventOAuth.signUpServerConfiguration.options) { option in
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

            if OpenMusicEventOAuth.signUpServerConfiguration.allowsCustomServerHost {
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

        if store.usesCustomSignUpServerHost ||
            OpenMusicEventOAuth.signUpServerConfiguration.options.isEmpty {
            Section("Server") {
                TextField("Server Host", text: $store.signUpServerHost)
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            }
        }
    }
}

struct AccountSignUpServerOptionRow: View {
    let option: OAuthSignUpServerOption
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AccountSignUpServerImageView(url: option.imageURL)

            VStack(alignment: .leading, spacing: 4) {
                Text(option.title)
                    .font(.headline)

                if !option.subtitle.isEmpty {
                    Text(option.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !option.description.isEmpty {
                    Text(option.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if option.isComingSoon {
                Text("Coming Soon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            } else if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .foregroundStyle(.primary)
    }
}

struct AccountCustomSignUpServerOptionRow: View {
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AccountSignUpServerImageView(url: nil)

            VStack(alignment: .leading, spacing: 4) {
                Text("Custom")
                    .font(.headline)
                Text("Use another AT Protocol server")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .foregroundStyle(.primary)
    }
}

struct AccountSignUpServerImageView: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    AccountSignUpServerImagePlaceholder()
                }
            } else {
                AccountSignUpServerImagePlaceholder()
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.secondary.opacity(0.18))
        }
    }
}

struct AccountSignUpServerImagePlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.secondary.opacity(0.12))

            Image(systemName: "server.rack")
                .imageScale(.medium)
                .foregroundStyle(.secondary)
        }
    }
}

public extension OAuthAccount {
    init() {
        self.init(
            baseAuthRequirement: OpenMusicEventOAuth.baseAuthRequirement,
            signUpServerConfiguration: OpenMusicEventOAuth.signUpServerConfiguration
        )
    }
}

public extension OAuthAccount.State {
    init() {
        self.init(storage: OpenMusicEventOAuth.storage)
    }

    init(
        authFailureMessage: Shared<ErrorMessage?>,
        session: Shared<OAuth.Session?>,
        sessionStore: Shared<OAuth.SessionStore>
    ) {
        self.init(
            storage: OAuthSessionStorage(
                session: session,
                sessionStore: sessionStore,
                authFailureMessage: authFailureMessage
            )
        )
    }
}
