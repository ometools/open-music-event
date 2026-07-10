import ATProto
import ATProtoOAuth
import ComposableArchitecture2
import ComposableForms
import Dependencies
import IssueReporting
import OpenMusicEventComponents
import Sharing
import SwiftUI
import Tagged
import TCATProtoAuthentication

@Feature
public struct Account {
    public init() {}

    public struct SignInFormValue: Equatable, Sendable {
        public init(handle: String = "") {
            self.handle = handle
        }

        public var handle: String
    }

    public typealias SignInFormFeature = ComposableForms.Form<SignInFormValue>

    public struct SignUpFormValue: Equatable, Sendable {
        public init(serverHost: String = "") {
            self.serverHost = serverHost
        }

        public var serverHost: String
    }

    public typealias SignUpFormFeature = ComposableForms.Form<SignUpFormValue>

    public enum AccountIdentityResolution: Equatable, Sendable {
        case loading
        case loaded(ActorIdentity)
        case failed

        var identity: ActorIdentity? {
            guard case let .loaded(identity) = self else { return nil }
            return identity
        }

        var needsLoading: Bool {
            switch self {
            case .loading, .loaded:
                false
            case .failed:
                true
            }
        }
    }

    public struct AccountRow: Equatable, Identifiable, Sendable {
        public var id: Atmosphere.Account.ID
        public var identity: ActorIdentity?
        public var isSelected: Bool
        public var pdsHost: String

        public var title: String {
            identity?.displayName?.accountDisplayValue
                ?? identity?.handle?.rawValue.accountDisplayValue
                ?? "AT Protocol account"
        }

        public var subtitle: String {
            if identity?.displayName?.accountDisplayValue != nil,
               let handle = identity?.handle?.rawValue.accountDisplayValue {
                return handle
            }
            return "Hosted by \(pdsHost)"
        }

        var avatarInitials: String {
            let words = title
                .split(separator: " ")
                .prefix(2)
                .compactMap(\.first)
            let initials = String(words).uppercased()
            return initials.isEmpty ? "AT" : initials
        }
    }

    public enum Surface: Equatable, Sendable {
        case authentication
        case accountManagement
    }

    public enum Mode: String, CaseIterable, Equatable, Hashable, Sendable {
        case signIn
        case signUp

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
                "Sign Up"
            }
        }
    }

    public struct State: Equatable {
        public init(
            isAuthenticationSheetPresented: Bool = false,
            authRequirement: OAuth.AuthRequirement = OpenMusicEventOAuth.baseAuthRequirement,
            selectedMode: Mode = .signIn,
            signInLoginHint: String = "",
            signUpServerConfiguration: OAuthSignUpServerConfiguration? = nil,
            selectedSessionID: Shared<Atmosphere.Account.ID?> = OpenMusicEventOAuth.selectedSessionID,
            storage: OAuthSessionStorage = OpenMusicEventOAuth.storage
        ) {
            @Dependency(\.openMusicEventSignUpServerConfiguration)
            var defaultSignUpServerConfiguration
            let signUpServerConfiguration =
                signUpServerConfiguration ?? defaultSignUpServerConfiguration
            let signUpServerHost = signUpServerConfiguration.defaultServerHost
            let selectedSignUpServerOptionID = signUpServerConfiguration
                .availableOption(serverHost: signUpServerHost)?
                .id

            self.authRequirement = authRequirement
            self.isAuthenticationSheetPresented = isAuthenticationSheetPresented
            self._selectedSessionID = selectedSessionID
            self.oauth = Spawn(OAuthAccount.State(storage: storage))
            self.selectedMode = selectedMode
            self.selectedSignUpServerOptionID = selectedSignUpServerOptionID
            self.signUpServerConfiguration = signUpServerConfiguration
            self.signInForm = SignInFormFeature.State(
                value: SignInFormValue(handle: signInLoginHint)
            )
            self.signUpForm = SignUpFormFeature.State(
                value: SignUpFormValue(serverHost: signUpServerHost)
            )
            self.usesCustomSignUpServerHost =
                !signUpServerConfiguration.options.isEmpty &&
                signUpServerConfiguration.allowsCustomServerHost &&
                selectedSignUpServerOptionID == nil
        }

        public init(
            isAuthenticationSheetPresented: Bool = false,
            authRequirement: OAuth.AuthRequirement = OpenMusicEventOAuth.baseAuthRequirement,
            selectedMode: Mode = .signIn,
            signInLoginHint: String = "",
            signUpServerConfiguration: OAuthSignUpServerConfiguration? = nil,
            authFailureMessage: Shared<TCATProtoAuthentication.ErrorMessage?>,
            sessionStore: Shared<OAuth.SessionStore>,
            selectedSessionID: Shared<Atmosphere.Account.ID?> = Shared(value: nil)
        ) {
            self.init(
                isAuthenticationSheetPresented: isAuthenticationSheetPresented,
                authRequirement: authRequirement,
                selectedMode: selectedMode,
                signInLoginHint: signInLoginHint,
                signUpServerConfiguration: signUpServerConfiguration,
                selectedSessionID: selectedSessionID,
                storage: OAuthSessionStorage(
                    sessionStore: sessionStore,
                    authFailureMessage: authFailureMessage,
                    selectedSessionID: selectedSessionID
                )
            )
        }

        public var authRequirement: OAuth.AuthRequirement
        public var isAuthenticationSheetPresented: Bool
        public var accountIdentities: [Atmosphere.Account.ID: AccountIdentityResolution] = [:]
        public var oauth: Spawn<OAuthAccount>
        @Shared public var selectedSessionID: Atmosphere.Account.ID?
        public var selectedMode: Mode
        public var selectedSignUpServerOptionID: OAuthSignUpServerOption.ID?
        public var signUpServerConfiguration: OAuthSignUpServerConfiguration
        public var signInForm: SignInFormFeature.State
        public var signUpForm: SignUpFormFeature.State
        public var usesCustomSignUpServerHost: Bool

        public var accountIDDescription: String? {
            oauth.accountIDDescription
        }

        public var accountRows: [AccountRow] {
            sessionStore.sessions.values
                .map { session in
                    AccountRow(
                        id: session.accountID,
                        identity: accountIdentities[session.accountID]?.identity,
                        isSelected: session.accountID == selectedSessionID,
                        pdsHost: session.pdsHost.rawValue
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.isSelected != rhs.isSelected {
                        return lhs.isSelected
                    }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
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
                return signInLoginHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    !signInForm.canSubmit
            case .signUp:
                return signUpServerHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    !signUpForm.canSubmit
            }
        }

        public var session: OAuth.Session? {
            oauth.state.session
        }

        public var sessionStore: OAuth.SessionStore {
            oauth.state.sessionStore
        }

        public var signInLoginHint: String {
            get { signInForm.value.handle }
            set { signInForm.value.handle = newValue }
        }

        public var surface: Surface {
            accountRows.isEmpty ? .authentication : .accountManagement
        }

        public var signUpServerHost: String {
            get { signUpForm.value.serverHost }
            set { signUpForm.value.serverHost = newValue }
        }
    }

    public enum Action {
        case accountButtonTapped
        case accountIdentityResponse(Atmosphere.Account.ID, ActorIdentity?)
        case accountRowTapped(Atmosphere.Account.ID)
        case accountRowsAppeared
        case authenticationSheetDismissed
        case customSignUpServerOptionTapped
        case loginResponse(Result<OAuth.Session, OAuthAccount.LoginFailure>)
        case selectedModeChanged(Mode)
        case signOutAllButtonTapped
        case signInForm(SignInFormFeature.Action)
        case signInFormSubmitted(SignInFormValue)
        case signUpForm(SignUpFormFeature.Action)
        case signUpFormSubmitted(SignUpFormValue)
        case signUpResponse(Result<OAuth.Session, OAuthAccount.LoginFailure>)
        case signUpServerOptionTapped(OAuthSignUpServerOption.ID)
        case submitAuthenticationFormButtonTapped
    }

    @Dependency(\.actorIdentityLookup) var actorIdentityLookup
    @Dependency(\.openMusicEventAccountAuthorizationClient) var accountAuthorizationClient
    @Dependency(\.openMusicEventAuthorizationRequests) var authorizationRequests
    @Dependency(\.openMusicEventSignUpServerConfiguration) var signUpServerConfiguration

    public var body: some Feature {
        Features {
            Scope(\.signInForm, action: \.signInForm) {
                SignInFormFeature()
                    .onSubmit { value in
                        try store.send(.signInFormSubmitted(value))
                    }
            }
            Scope(\.signUpForm, action: \.signUpForm) {
                SignUpFormFeature()
                    .onSubmit { value in
                        try store.send(.signUpFormSubmitted(value))
                    }
            }
            Update { state, action in
                switch action {
                case .accountButtonTapped:
                    state.isAuthenticationSheetPresented = true

                case .accountIdentityResponse(let accountID, let identity):
                    guard state.sessionStore[accountID] != nil else { return }
                    state.accountIdentities[accountID] = identity.map {
                        .loaded($0)
                    } ?? .failed

                case .accountRowTapped(let accountID):
                    guard state.sessionStore[accountID] != nil else { return }
                    state.$selectedSessionID.withLock {
                        $0 = accountID
                    }
                    state.oauth.state.$sessionStore.withLock {
                        $0.selectedAccountID = accountID
                    }
                    let selectedSessionID = state.$selectedSessionID
                    store.addTask {
                        await saveOpenMusicEventSelectedSessionID(selectedSessionID)
                    }

                case .accountRowsAppeared:
                    let accountIDs = Set(state.sessionStore.sessions.values.map(\.accountID))
                    state.accountIdentities = state.accountIdentities.filter {
                        accountIDs.contains($0.key)
                    }
                    let accountIDsToLoad = accountIDs.filter { accountID in
                        state.accountIdentities[accountID]?.needsLoading ?? true
                    }
                    guard !accountIDsToLoad.isEmpty else { return }
                    for accountID in accountIDsToLoad {
                        state.accountIdentities[accountID] = .loading
                    }
                    store.addTask {
                        for accountID in accountIDsToLoad {
                            let identity: ActorIdentity?
                            do {
                                identity = try await actorIdentityLookup.resolve(
                                    accountID.rawValue.description
                                )
                            } catch {
                                identity = nil
                            }
                            try store.send(.accountIdentityResponse(accountID, identity))
                        }
                    }

                case .authenticationSheetDismissed:
                    state.isAuthenticationSheetPresented = false

                case .customSignUpServerOptionTapped:
                    guard state.signUpServerConfiguration.allowsCustomServerHost else { return }
                    state.selectedSignUpServerOptionID = nil
                    state.usesCustomSignUpServerHost = true
                    state.signUpServerHost = ""

                case .loginResponse(.success(let session)):
                    state.oauth.state.isLoginInProgress = false
                    state.oauth.state.errorMessage = nil
                    state.oauth.state.$sessionStore.withLock {
                        $0.upsert(session)
                    }
                    state.$selectedSessionID.withLock {
                        $0 = session.accountID
                    }
                    state.isAuthenticationSheetPresented = false
                    let sessionStore = state.oauth.state.$sessionStore
                    let selectedSessionID = state.$selectedSessionID
                    store.addTask {
                        await saveOpenMusicEventAuthenticationStorage(
                            sessionStore: sessionStore,
                            selectedSessionID: selectedSessionID
                        )
                    }

                case .loginResponse(.failure(.cancelled)):
                    state.oauth.state.isLoginInProgress = false

                case .loginResponse(.failure(.failed)):
                    state.oauth.state.isLoginInProgress = false
                    state.oauth.state.errorMessage = "Sign in failed."

                case .selectedModeChanged(let mode):
                    state.selectedMode = mode

                case .signInForm:
                    break

                case .signInFormSubmitted(let value):
                    guard !state.isSignUpInProgress else { return }
                    let loginHint = value.handle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !loginHint.isEmpty else { return }
                    let sessionStore = state.oauth.state.sessionStore
                    let authRequirement = state.authRequirement
                    state.oauth.state.errorMessage = nil
                    state.oauth.state.isLoginInProgress = true
                    store.addTask {
                        do {
                            let session = try await accountAuthorizationClient.signIn(
                                authRequirement,
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

                case .signUpForm:
                    break

                case .signUpFormSubmitted(let value):
                    guard !state.isLoginInProgress else { return }
                    let serverHost = value.serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !serverHost.isEmpty else { return }
                    let authRequirement = state.authRequirement
                    state.oauth.state.errorMessage = nil
                    state.oauth.state.isSignUpInProgress = true
                    store.addTask {
                        do {
                            let session = try await accountAuthorizationClient.signUp(
                                authRequirement,
                                serverHost
                            )
                            try store.send(.signUpResponse(.success(session)))
                        } catch is CancellationError {
                            try store.send(.signUpResponse(.failure(.cancelled)))
                        } catch {
                            try store.send(.signUpResponse(.failure(.failed(error.localizedDescription))))
                        }
                    }

                case .signUpResponse(.success(let session)):
                    state.oauth.state.isSignUpInProgress = false
                    state.oauth.state.errorMessage = nil
                    state.oauth.state.$sessionStore.withLock {
                        $0.upsert(session)
                    }
                    state.$selectedSessionID.withLock {
                        $0 = session.accountID
                    }
                    state.isAuthenticationSheetPresented = false
                    let sessionStore = state.oauth.state.$sessionStore
                    let selectedSessionID = state.$selectedSessionID
                    store.addTask {
                        await saveOpenMusicEventAuthenticationStorage(
                            sessionStore: sessionStore,
                            selectedSessionID: selectedSessionID
                        )
                    }

                case .signUpResponse(.failure(.cancelled)):
                    state.oauth.state.isSignUpInProgress = false

                case .signUpResponse(.failure(.failed)):
                    state.oauth.state.isSignUpInProgress = false
                    state.oauth.state.errorMessage = "Sign up failed."

                case .signUpServerOptionTapped(let id):
                    guard let option = state.signUpServerConfiguration.availableOption(id: id),
                          let serverHost = option.serverHost
                    else { return }
                    state.selectedSignUpServerOptionID = option.id
                    state.usesCustomSignUpServerHost = false
                    state.signUpServerHost = serverHost

                case .signOutAllButtonTapped:
                    state.accountIdentities = [:]
                    state.oauth.state.errorMessage = nil
                    state.oauth.state.isLoginInProgress = false
                    state.oauth.state.isSignUpInProgress = false
                    state.oauth.state.$authFailureMessage.withLock { $0 = nil }
                    state.oauth.state.$sessionStore.withLock { $0 = OAuth.SessionStore() }
                    state.$selectedSessionID.withLock { $0 = nil }
                    let sessionStore = state.oauth.state.$sessionStore
                    let selectedSessionID = state.$selectedSessionID
                    store.addTask {
                        await saveOpenMusicEventAuthenticationStorage(
                            sessionStore: sessionStore,
                            selectedSessionID: selectedSessionID
                        )
                        await authorizationRequests.cancel()
                    }

                case .submitAuthenticationFormButtonTapped:
                    guard !state.isAuthenticationFormSubmitDisabled else { return }

                    switch state.selectedMode {
                    case .signIn:
                        guard !state.isSignUpInProgress else { return }
                        store.addTask {
                            try store.send(.signInForm(.submittedForm))
                        }

                    case .signUp:
                        guard !state.isLoginInProgress else { return }
                        store.addTask {
                            try store.send(.signUpForm(.submittedForm))
                        }
                    }
                }
            }
        }
        .spawn(\.oauth) {
            OAuthAccount(
                baseAuthRequirement: OpenMusicEventOAuth.baseAuthRequirement,
                signUpServerConfiguration: signUpServerConfiguration
            )
        }
    }
}

private extension Account.SignInFormFeature {
    init() {
        self.init {
            Self.Field(\.handle) {
                Validation(error: "Enter your handle.") { value in
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
        }
    }
}

private extension Account.SignUpFormFeature {
    init() {
        self.init {
            Self.Field(\.serverHost) {
                Validation(error: "Choose a provider or enter a server host.") { value in
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
        }
    }
}

public struct AccountView: View {
    @Bindable var store: StoreOf<Account>

    public init(store: StoreOf<Account>) {
        self.store = store
    }

    @ViewBuilder
    public var body: some View {
        switch store.surface {
        case .authentication:
            AccountAuthenticationFormSections(store: store)
            AccountAuthenticationSubmitSection(store: store)

        case .accountManagement:
            AccountManagementSection(store: store)
        }
    }
}

struct AccountManagementSection: View {
    @Bindable var store: StoreOf<Account>

    var body: some View {
        Section("Account") {
            ForEach(store.accountRows) { row in
                Button {
                    store.send(.accountRowTapped(row.id))
                } label: {
                    AccountRowView(row: row)
                }
                .buttonStyle(.plain)
            }

            Button {
                store.send(.accountButtonTapped)
            } label: {
                Text("Add Another Account")
            }

            Button(role: .destructive) {
                store.send(.signOutAllButtonTapped)
            } label: {
                Text("Log Out of All Accounts")
            }

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .task(id: store.accountRows.map(\.id)) {
            await store.send(.accountRowsAppeared)?.value
        }
    }
}

struct AccountRowView: View {
    let row: Account.AccountRow

    var body: some View {
        HStack(spacing: 12) {
            AccountAvatarPlaceholder(initials: row.avatarInitials)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(row.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if row.isSelected {
                Text("Current")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .foregroundStyle(.primary)
    }
}

struct AccountAvatarPlaceholder: View {
    let initials: String

    var body: some View {
        Circle()
            .fill(.secondary.opacity(0.18))
            .frame(width: 44, height: 44)
            .overlay {
                Text(initials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
            SwiftUI.Form {
                AccountAuthenticationFormSections(store: store)
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

struct AccountAuthenticationFormSections: View {
    @Bindable var store: StoreOf<Account>
    let showsIntro: Bool

    init(
        store: StoreOf<Account>,
        showsIntro: Bool = true
    ) {
        self.store = store
        self.showsIntro = showsIntro
    }

    var body: some View {
        if showsIntro {
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

                TextField("name.atmo.social", text: $store.signInForm.value.handle)
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                FormFieldValidationStatus(
                    validation: store.signInForm.validation[AccountFormFieldID.signInHandle]
                )

            case .signUp:
                Text(store.selectedMode.helperText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if store.selectedMode == .signUp {
                AccountSignUpServerFormView(store: store)
            }
        } footer: {
            Text("Already use Bluesky? Your Bluesky handle works too.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if let errorMessage = store.errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
    }
}

struct AccountAuthenticationSubmitSection: View {
    @Bindable var store: StoreOf<Account>

    var body: some View {
        Section {
            AccountAuthenticationSubmitButton(store: store)
                .controlSize(.extraLarge)
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
                .controlSize(.extraLarge)
        }
    }
}

struct AccountAuthenticationSubmitButton: View {
    @Bindable var store: StoreOf<Account>

    var body: some View {
        SubmitButton(
            isInProgress: store.isWorking,
            isDisabled: store.isAuthenticationFormSubmitDisabled
        ) {
            store.send(.submitAuthenticationFormButtonTapped)
        }
    }
}

struct AccountProminentSignInButton: View {
    @Bindable var store: StoreOf<Account>

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            AccountAuthenticationSubmitButton(store: store)
                .frame(minWidth: 220)

            Spacer(minLength: 0)
        }
    }
}

struct AccountSignUpServerFormView: View {
    @Bindable var store: StoreOf<Account>

    var body: some View {
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

        if store.usesCustomSignUpServerHost ||
            store.signUpServerConfiguration.options.isEmpty {
            Section("Server") {
                TextField("Server Host", text: $store.signUpForm.value.serverHost)
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                FormFieldValidationStatus(
                    validation: store.signUpForm.validation[AccountFormFieldID.signUpServerHost]
                )
            }
        }
    }
}

private enum AccountFormFieldID {
    static var signInHandle: AnyHashable { AnyHashable(\Account.SignInFormValue.handle) }
    static var signUpServerHost: AnyHashable { AnyHashable(\Account.SignUpFormValue.serverHost) }
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

private func saveOpenMusicEventAuthenticationStorage(
    sessionStore: Shared<OAuth.SessionStore>,
    selectedSessionID: Shared<Atmosphere.Account.ID?>
) async {
    do {
        try await sessionStore.save()
        try await selectedSessionID.save()
    } catch {
        reportIssue(error)
    }
}

private func saveOpenMusicEventSelectedSessionID(
    _ selectedSessionID: Shared<Atmosphere.Account.ID?>
) async {
    do {
        try await selectedSessionID.save()
    } catch {
        reportIssue(error)
    }
}

private extension String {
    var accountDisplayValue: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard !value.lowercased().hasPrefix("did:") else { return nil }
        return value
    }
}

public extension OAuthAccount {
    init() {
        @Dependency(\.openMusicEventSignUpServerConfiguration)
        var signUpServerConfiguration
        self.init(
            baseAuthRequirement: OpenMusicEventOAuth.baseAuthRequirement,
            signUpServerConfiguration: signUpServerConfiguration
        )
    }
}

public extension OAuthAccount.State {
    init() {
        self.init(storage: OpenMusicEventOAuth.storage)
    }

    init(
        authFailureMessage: Shared<TCATProtoAuthentication.ErrorMessage?>,
        sessionStore: Shared<OAuth.SessionStore>,
        selectedSessionID: Shared<Atmosphere.Account.ID?> = OpenMusicEventOAuth.selectedSessionID
    ) {
        self.init(
            storage: OAuthSessionStorage(
                sessionStore: sessionStore,
                authFailureMessage: authFailureMessage,
                selectedSessionID: selectedSessionID
            )
        )
    }
}
