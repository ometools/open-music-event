#if canImport(SwiftUI)
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
import XRPCClient

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

    public enum AccountSessionValidationStatus: Equatable, Sendable {
        case unchecked
        case checking
        case accepted
        case requiresRelog
        case unverified

        var canStartChecking: Bool {
            self != .checking
        }

        var requiresRelog: Bool {
            self == .requiresRelog
        }
    }

    public struct AccountRow: Equatable, Identifiable, Sendable {
        public var id: Atmosphere.Account.ID
        public var identity: ActorIdentity?
        public var isSelected: Bool
        public var pdsHost: String
        public var sessionValidationStatus: AccountSessionValidationStatus

        public var title: String {
            identity?.displayName?.accountDisplayValue
                ?? identity?.handle?.rawValue.accountDisplayValue
                ?? "Account"
        }

        public var subtitle: String {
            if sessionValidationStatus.requiresRelog {
                return "Sign in again"
            }
            if identity?.displayName?.accountDisplayValue != nil,
               let handle = identity?.handle?.rawValue.accountDisplayValue {
                return handle
            }
            return "Hosted by \(pdsHost)"
        }

        var requiresRelog: Bool {
            sessionValidationStatus.requiresRelog
        }

        func visibleSubtitle(showsTechnicalDetails: Bool) -> String? {
            if identity?.displayName?.accountDisplayValue != nil,
               let handle = identity?.handle?.rawValue.accountDisplayValue {
                return handle.hasPrefix("@") ? handle : "@\(handle)"
            }
            return showsTechnicalDetails ? "Hosted by \(pdsHost)" : nil
        }

        var avatarInitials: String {
            let words = title
                .split(separator: " ")
                .prefix(2)
                .compactMap(\.first)
            let initials = String(words).uppercased()
            return initials.isEmpty ? "AT" : initials
        }

        var pickerHandle: String {
            guard let handle = identity?.handle?.rawValue.accountDisplayValue else {
                return "Account unavailable"
            }
            return handle.hasPrefix("@") ? handle : "@\(handle)"
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
            authRequirement: OAuth.AuthRequirement = OpenMusicEventOAuth.baseAuthRequirement,
            selectedMode: Mode = .signIn,
            signInLoginHint: String = "",
            signUpServerConfiguration: OAuthSignUpServerConfiguration? = nil,
            selectedSessionID: Shared<Atmosphere.Account.ID?> = OpenMusicEventOAuth.selectedSessionID,
            recentlyUsedAccountIDs: Shared<[Atmosphere.Account.ID]> = OpenMusicEventOAuth.recentlyUsedAccountIDs,
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
            self._recentlyUsedAccountIDs = recentlyUsedAccountIDs
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
            selectedSessionID: Shared<Atmosphere.Account.ID?> = Shared(value: nil),
            recentlyUsedAccountIDs: Shared<[Atmosphere.Account.ID]> = Shared(value: [])
        ) {
            self.init(
                isAuthenticationSheetPresented: isAuthenticationSheetPresented,
                authRequirement: authRequirement,
                selectedMode: selectedMode,
                signInLoginHint: signInLoginHint,
                signUpServerConfiguration: signUpServerConfiguration,
                selectedSessionID: selectedSessionID,
                recentlyUsedAccountIDs: recentlyUsedAccountIDs,
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
        public var accountSessionValidationStatuses: [Atmosphere.Account.ID: AccountSessionValidationStatus] = [:]
        public var oauth: Spawn<OAuthAccount>
        @Shared public var selectedSessionID: Atmosphere.Account.ID?
        @Shared public var recentlyUsedAccountIDs: [Atmosphere.Account.ID]
        public var selectedMode: Mode
        public var selectedSignUpServerOptionID: OAuthSignUpServerOption.ID?
        public var signUpServerConfiguration: OAuthSignUpServerConfiguration
        public var signInActorSearchFailures: [PredictiveSearchFailure] = []
        public var signInActorSearchIsLoading = false
        public var signInActorSearchResults: [ActorIdentity] = []
        public var signInForm: SignInFormFeature.State
        public var signUpForm: SignUpFormFeature.State
        public var usesCustomSignUpServerHost: Bool

        public var accountIDDescription: String? {
            oauth.accountIDDescription
        }

        public var accountRows: [AccountRow] {
            let recentUseRanks = accountRowRecentUseRanks
            return sessionStore.sessions.values
                .map { session in
                    let validationStatus = accountSessionValidationStatuses[session.accountID] ?? .unchecked
                    return AccountRow(
                        id: session.accountID,
                        identity: accountIdentities[session.accountID]?.identity,
                        isSelected: session.accountID == selectedSessionID && !validationStatus.requiresRelog,
                        pdsHost: session.pdsHost.rawValue,
                        sessionValidationStatus: validationStatus
                    )
                }
                .sorted { lhs, rhs in
                    let lhsRecentUseRank = recentUseRanks[lhs.id] ?? Int.max
                    let rhsRecentUseRank = recentUseRanks[rhs.id] ?? Int.max
                    if lhsRecentUseRank != rhsRecentUseRank {
                        return lhsRecentUseRank < rhsRecentUseRank
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

        var accountIDsSortedByRecentUse: [Atmosphere.Account.ID] {
            var accountIDs: [Atmosphere.Account.ID] = []
            if let selectedSessionID {
                accountIDs.append(selectedSessionID)
            } else if let selectedAccountID = sessionStore.selectedAccountID {
                accountIDs.append(selectedAccountID)
            }
            for accountID in recentlyUsedAccountIDs where !accountIDs.contains(accountID) {
                accountIDs.append(accountID)
            }
            return accountIDs
        }

        var accountRowRecentUseRanks: [Atmosphere.Account.ID: Int] {
            Dictionary(
                uniqueKeysWithValues: accountIDsSortedByRecentUse.enumerated().map { offset, accountID in
                    (accountID, offset)
                }
            )
        }

        func mostRecentlyUsedAccountID(excluding excludedAccountID: Atmosphere.Account.ID) -> Atmosphere.Account.ID? {
            let accountIDs = Set(sessionStore.sessions.values.map(\.accountID))
            return accountIDsSortedByRecentUse.first { accountID in
                accountID != excludedAccountID && accountIDs.contains(accountID)
            }
        }

        func reloginHint(for accountID: Atmosphere.Account.ID) -> String {
            accountIdentities[accountID]?
                .identity?
                .handle?
                .rawValue
                .accountDisplayValue
            ?? accountID.rawValue.description
        }

        mutating func syncRecentlyUsedAccountIDs(selectedAccountID: Atmosphere.Account.ID?) {
            let accountIDs = Set(sessionStore.sessions.values.map(\.accountID))
            let selectedAccountID = selectedAccountID.flatMap { accountID in
                accountIDs.contains(accountID) ? accountID : nil
            }
            $recentlyUsedAccountIDs.withLock { recentlyUsedAccountIDs in
                var sortedAccountIDs: [Atmosphere.Account.ID] = []
                if let selectedAccountID {
                    sortedAccountIDs.append(selectedAccountID)
                }
                for accountID in recentlyUsedAccountIDs
                where accountIDs.contains(accountID) && !sortedAccountIDs.contains(accountID) {
                    sortedAccountIDs.append(accountID)
                }
                recentlyUsedAccountIDs = sortedAccountIDs
            }
        }

        public var signInLoginHint: String {
            get { signInForm.value.handle }
            set { signInForm.value.handle = newValue }
        }

        mutating func resetSignInActorSearch() {
            signInActorSearchFailures = []
            signInActorSearchIsLoading = false
            signInActorSearchResults = []
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
        case accountLogOutButtonTapped(Atmosphere.Account.ID)
        case accountRowTapped(Atmosphere.Account.ID)
        case accountRowsAppeared
        case accountSessionValidationResponse(
            Atmosphere.Account.ID,
            OpenMusicEventAccountSessionValidationClient.ValidationResult
        )
        case authenticationSheetDismissed
        case customSignUpServerOptionTapped
        case loginResponse(Result<OAuth.Session, OAuthAccount.LoginFailure>)
        case selectedModeChanged(Mode)
        case signOutAllButtonTapped
        case signInActorIdentityTapped(ActorIdentity)
        case signInActorSearchQueryChanged(String)
        case signInActorSearchResponse(PredictiveSearchResponse<ActorIdentity>)
        case signInActorSearchSubmitted
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
    @Dependency(\.openMusicEventAccountSessionValidationClient) var accountSessionValidationClient
    @Dependency(\.openMusicEventAuthorizationRequests) var authorizationRequests
    @Dependency(\.openMusicEventSignUpServerConfiguration) var signUpServerConfiguration
    @StoreTaskID var signInActorSearchTask

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
                    state.selectedMode = .signIn
                    state.signInForm = SignInFormFeature.State(value: SignInFormValue())
                    state.resetSignInActorSearch()
                    state.isAuthenticationSheetPresented = true

                case .accountIdentityResponse(let accountID, let identity):
                    guard state.sessionStore[accountID] != nil else { return }
                    state.accountIdentities[accountID] = identity.map {
                        .loaded($0)
                    } ?? .failed

                case .accountLogOutButtonTapped(let accountID):
                    guard state.sessionStore[accountID] != nil else { return }
                    state.accountIdentities[accountID] = nil
                    state.accountSessionValidationStatuses[accountID] = nil
                    state.oauth.state.errorMessage = nil
                    state.oauth.state.isLoginInProgress = false
                    state.oauth.state.isSignUpInProgress = false
                    let selectedAccountWasRemoved =
                        state.selectedSessionID == accountID ||
                        state.sessionStore.selectedAccountID == accountID
                    state.oauth.state.$sessionStore.withLock {
                        $0.remove(accountID)
                    }
                    var selectedSessionID = state.selectedSessionID
                    if selectedAccountWasRemoved || state.sessionStore[selectedSessionID] == nil {
                        selectedSessionID =
                            state.mostRecentlyUsedAccountID(excluding: accountID) ??
                            state.sessionStore.selectedAccountID
                    }
                    state.oauth.state.$sessionStore.withLock {
                        $0.selectedAccountID = selectedSessionID
                    }
                    state.$selectedSessionID.withLock {
                        $0 = selectedSessionID
                    }
                    state.syncRecentlyUsedAccountIDs(selectedAccountID: selectedSessionID)
                    let shouldCancelAuthorization = state.sessionStore.sessions.isEmpty
                    let sessionStore = state.oauth.state.$sessionStore
                    let selectedSessionIDStore = state.$selectedSessionID
                    store.addTask {
                        await saveOpenMusicEventAuthenticationStorage(
                            sessionStore: sessionStore,
                            selectedSessionID: selectedSessionIDStore
                        )
                        if shouldCancelAuthorization {
                            await authorizationRequests.cancel()
                        }
                    }

                case .accountRowTapped(let accountID):
                    guard state.sessionStore[accountID] != nil else { return }
                    if state.accountSessionValidationStatuses[accountID]?.requiresRelog == true {
                        state.selectedMode = .signIn
                        state.signInForm = SignInFormFeature.State(
                            value: SignInFormValue(handle: state.reloginHint(for: accountID))
                        )
                        state.isAuthenticationSheetPresented = true
                        return
                    }
                    state.$selectedSessionID.withLock {
                        $0 = accountID
                    }
                    state.oauth.state.$sessionStore.withLock {
                        $0.selectedAccountID = accountID
                    }
                    state.syncRecentlyUsedAccountIDs(selectedAccountID: accountID)
                    let selectedSessionID = state.$selectedSessionID
                    store.addTask {
                        await saveOpenMusicEventSelectedSessionID(selectedSessionID)
                    }

                case .accountRowsAppeared:
                    state.syncRecentlyUsedAccountIDs(
                        selectedAccountID: state.selectedSessionID ?? state.sessionStore.selectedAccountID
                    )
                    let sessions = Array(state.sessionStore.sessions.values)
                    let accountIDs = Set(sessions.map(\.accountID))
                    state.accountIdentities = state.accountIdentities.filter {
                        accountIDs.contains($0.key)
                    }
                    state.accountSessionValidationStatuses = state.accountSessionValidationStatuses.filter {
                        accountIDs.contains($0.key)
                    }
                    let accountIDsToLoad = accountIDs.filter { accountID in
                        state.accountIdentities[accountID]?.needsLoading ?? true
                    }
                    for accountID in accountIDsToLoad {
                        state.accountIdentities[accountID] = .loading
                    }
                    if !accountIDsToLoad.isEmpty {
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
                    }
                    let sessionsToValidate = sessions.filter { session in
                        (
                            state.accountSessionValidationStatuses[session.accountID] ?? .unchecked
                        )
                        .canStartChecking
                    }
                    for session in sessionsToValidate {
                        state.accountSessionValidationStatuses[session.accountID] = .checking
                    }
                    if !sessionsToValidate.isEmpty {
                        store.addTask {
                            for session in sessionsToValidate {
                                let result = await accountSessionValidationClient.validate(session)
                                try store.send(.accountSessionValidationResponse(session.accountID, result))
                            }
                        }
                    }

                case .accountSessionValidationResponse(let accountID, let result):
                    guard state.sessionStore[accountID] != nil else { return }
                    switch result {
                    case .accepted(let session):
                        guard session.accountID == accountID else {
                            state.accountSessionValidationStatuses[accountID] = .unverified
                            return
                        }
                        state.oauth.state.$sessionStore.withLock {
                            $0[accountID] = session
                        }
                        state.accountSessionValidationStatuses[accountID] = .accepted
                        let sessionStore = state.oauth.state.$sessionStore
                        store.addTask {
                            await saveOpenMusicEventSessionStore(sessionStore)
                        }

                    case .requiresRelog:
                        state.accountSessionValidationStatuses[accountID] = .requiresRelog

                    case .unverified:
                        state.accountSessionValidationStatuses[accountID] = .unverified
                    }

                case .authenticationSheetDismissed:
                    state.isAuthenticationSheetPresented = false
                    state.resetSignInActorSearch()

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
                    state.accountSessionValidationStatuses[session.accountID] = .accepted
                    state.$selectedSessionID.withLock {
                        $0 = session.accountID
                    }
                    state.syncRecentlyUsedAccountIDs(selectedAccountID: session.accountID)
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

                    if mode == .signUp {
                        state.resetSignInActorSearch()
                    }

                case let .signInActorIdentityTapped(identity):
                    state.signInLoginHint = identity.handle?.rawValue ?? identity.did.description
                    state.resetSignInActorSearch()
                    store.addTask {
                        try store.send(.signInForm(.submittedForm))
                    }

                case let .signInActorSearchQueryChanged(query):
                    state.signInLoginHint = query
                    searchSignInActors(query: query, includingExactLookup: false, state: &state)

                case .signInActorSearchResponse(let response):
                    guard response.query == state.signInLoginHint.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ) else {
                        return
                    }
                    state.signInActorSearchIsLoading = false
                    state.signInActorSearchFailures = response.failures
                    state.signInActorSearchResults = response.results

                case .signInActorSearchSubmitted:
                    searchSignInActors(
                        query: state.signInLoginHint,
                        includingExactLookup: true,
                        state: &state
                    )

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
                    state.accountSessionValidationStatuses[session.accountID] = .accepted
                    state.$selectedSessionID.withLock {
                        $0 = session.accountID
                    }
                    state.syncRecentlyUsedAccountIDs(selectedAccountID: session.accountID)
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
                    state.accountSessionValidationStatuses = [:]
                    state.oauth.state.errorMessage = nil
                    state.oauth.state.isLoginInProgress = false
                    state.oauth.state.isSignUpInProgress = false
                    state.oauth.state.$authFailureMessage.withLock { $0 = nil }
                    state.oauth.state.$sessionStore.withLock { $0 = OAuth.SessionStore() }
                    state.$selectedSessionID.withLock { $0 = nil }
                    state.syncRecentlyUsedAccountIDs(selectedAccountID: nil)
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

    private func searchSignInActors(
        query: String,
        includingExactLookup: Bool,
        state: inout State
    ) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            state.resetSignInActorSearch()
            return
        }

        state.signInActorSearchIsLoading = true
        store.addTask(id: signInActorSearchTask) {
            let response = await (
                includingExactLookup ? Self.exactSignInActorSearch : Self.signInActorTypeaheadSearch
            )
            .search(query)
            try Task.checkCancellation()
            try store.send(.signInActorSearchResponse(response))
        }
    }

    static let exactSignInActorSearch = PredictiveSearch(
        actorIdentitySources: [
            .exactActorIdentityLookup(title: "Exact match"),
        ],
        minimumQueryLength: 2
    )

    static let signInActorTypeaheadSearch = PredictiveSearch(
        actorIdentitySources: [
            .appBskyActorTypeahead(title: "Profiles", limit: 10),
        ],
        minimumQueryLength: 2
    )
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

public struct AccountPicker: View {
    @Bindable var store: StoreOf<Account>

    public init(store: StoreOf<Account>) {
        self.store = store
    }

    public var body: some View {
        Menu {
            if store.accountRows.isEmpty {
                Button {
                    store.send(.accountButtonTapped)
                } label: {
                    Label("Sign In", systemImage: "person")
                }
            } else {
                ForEach(store.accountRows) { row in
                    Button {
                        select(row)
                    } label: {
                        AccountPickerRow(row: row)
                    }
                }
            }
        } label: {
            AccountPickerLabel(row: store.accountRows.first(where: \.isSelected))
        }
        .accessibilityLabel(accessibilityLabel)
        .accountAuthenticationSheet(store: store)
        .task(id: store.accountRows.map(\.id)) {
            await store.send(.accountRowsAppeared)?.value
        }
    }

    private var accessibilityLabel: String {
        if let row = store.accountRows.first(where: \.isSelected) {
            return "Signed in as \(row.pickerHandle)"
        }
        return "Sign in"
    }

    private func select(_ row: Account.AccountRow) {
        guard !row.isSelected else { return }
        withAnimation(SwiftUI.Animation.easeInOut(duration: 0.2)) {
            _ = store.send(.accountRowTapped(row.id))
        }
    }
}

struct AccountPickerLabel: View {
    let row: Account.AccountRow?

    var body: some View {
        if let row {
            AccountPickerRow(row: row, showsSelection: false)
        } else {
            Image(systemName: "person")
                .imageScale(.large)
        }
    }
}

struct AccountPickerRow: View {
    let row: Account.AccountRow
    let showsSelection: Bool

    init(row: Account.AccountRow, showsSelection: Bool = true) {
        self.row = row
        self.showsSelection = showsSelection
    }

    var body: some View {
        HStack(spacing: 8) {
            AccountAvatar(
                identity: row.identity,
                initials: row.avatarInitials,
                size: 24
            )
            .clipShape(Circle())
            .compositingGroup()

            Text(row.pickerHandle)
                .lineLimit(1)

            if showsSelection, row.isSelected {
                Spacer(minLength: 4)
                Image(systemName: "checkmark")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AccountManagementSection: View {
    @Bindable var store: StoreOf<Account>

    var body: some View {
        Section("Account") {
            ForEach(store.accountRows) { row in
                Button {
                    select(row)
                } label: {
                    AccountRowView(row: row)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        logOut(row)
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
                .contextMenu {
                    Button {
                        select(row)
                    } label: {
                        Label(
                            row.requiresRelog
                                ? "Sign In Again"
                                : row.isSelected ? "Current Account" : "Select Account",
                            systemImage: row.isSelected ? "checkmark" : "checkmark.circle"
                        )
                    }
                    .disabled(row.isSelected && !row.requiresRelog)

                    Button(role: .destructive) {
                        logOut(row)
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }

            Button {
                store.send(.accountButtonTapped)
            } label: {
                Label("Add Another Account", systemImage: "person.badge.plus")
            }

            Button(role: .destructive) {
                store.send(.signOutAllButtonTapped)
            } label: {
                Label("Log Out of All Accounts", systemImage: "rectangle.portrait.and.arrow.right")
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

    private func logOut(_ row: Account.AccountRow) {
        withAnimation(SwiftUI.Animation.easeInOut(duration: 0.2)) {
            _ = store.send(.accountLogOutButtonTapped(row.id))
        }
    }

    private func select(_ row: Account.AccountRow) {
        guard !row.isSelected else { return }
        withAnimation(SwiftUI.Animation.easeInOut(duration: 0.2)) {
            _ = store.send(.accountRowTapped(row.id))
        }
    }
}

struct AccountRowView: View {
    let row: Account.AccountRow
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        HStack(spacing: 12) {
            AccountAvatar(identity: row.identity, initials: row.avatarInitials)
                .opacity(row.requiresRelog ? 0.48 : 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.body.weight(row.isSelected ? .semibold : .regular))
                    .foregroundStyle(row.requiresRelog ? .secondary : .primary)
                    .lineLimit(1)

                if let subtitle = row.visibleSubtitle(
                    showsTechnicalDetails: showsTechnicalDetails
                ) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .opacity(row.requiresRelog ? 0.68 : 1)

            Spacer(minLength: 8)

            if row.isSelected && !row.requiresRelog {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 8)
        .animation(SwiftUI.Animation.easeInOut(duration: 0.2), value: row.isSelected)
        .animation(SwiftUI.Animation.easeInOut(duration: 0.2), value: row.requiresRelog)
        .foregroundStyle(.primary)
    }
}

struct AccountAvatar: View {
    let identity: ActorIdentity?
    let initials: String
    let size: CGFloat

    init(
        identity: ActorIdentity?,
        initials: String,
        size: CGFloat = 44
    ) {
        self.identity = identity
        self.initials = initials
        self.size = size
    }

    var body: some View {
        AsyncImage(url: identity?.avatar) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()

            case .empty, .failure:
                AccountAvatarPlaceholder(initials: initials, size: size)

            @unknown default:
                AccountAvatarPlaceholder(initials: initials, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.secondary.opacity(0.16))
        }
    }
}

struct AccountAvatarPlaceholder: View {
    let initials: String
    let size: CGFloat

    init(initials: String, size: CGFloat = 44) {
        self.initials = initials
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(.secondary.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
    }
}

public extension View {
    func accountPickerToolbar(store: StoreOf<Account>) -> some View {
        toolbar {
            #if os(macOS) && !SKIP
            ToolbarItem(placement: .automatic) {
                AccountPicker(store: store)
            }
            #else
            ToolbarItem(placement: .topBarLeading) {
                AccountPicker(store: store)
            }
            #endif
        }
    }

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
            #if os(macOS)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            #endif
            .navigationTitle("Account")
            .safeEdgeExpansion(edge: .bottom) {
                AccountAuthenticationSafeEdgeAction(store: store)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        store.send(.authenticationSheetDismissed)
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
    }
}

struct AccountAuthenticationFormSections: View {
    @Bindable var store: StoreOf<Account>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
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
                        showsTechnicalDetails
                            ? "Use one portable social account across Open Music Event and other AT Protocol apps."
                            : "Use one portable social account across Open Music Event and other compatible apps."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }

        Section("Account") {
            Picker("Action", selection: $store.selectedMode) {
                ForEach(Account.Mode.allCases, id: \.self) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }

        switch store.selectedMode {
        case .signIn:
            Section {
                Text(store.selectedMode.helperText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField(
                    "Search profiles",
                    text: $store.signInForm.value.handle,
                    prompt: Text("name.atmo.social")
                )
                #if os(iOS) || os(macOS)
                .textContentType(.username)
                #endif
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .onSubmit {
                    store.send(.signInActorSearchSubmitted)
                }
                .onChange(of: store.signInLoginHint) { _, query in
                    store.send(.signInActorSearchQueryChanged(query))
                }

                if store.signInActorSearchIsLoading {
                    ProgressView()
                }

                ForEach(
                    store.signInActorSearchResults.filter {
                        showsTechnicalDetails || $0.handle != nil
                    }
                ) { identity in
                    Button {
                        store.send(.signInActorIdentityTapped(identity))
                    } label: {
                        AccountActorIdentityRow(identity: identity)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isWorking)
                }

                ForEach(store.signInActorSearchFailures, id: \.sourceID) { failure in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(failure.title)
                        Text(failure.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                FormFieldValidationStatus(
                    validation: store.signInForm.validation[AccountFormFieldID.signInHandle]
                )
            } header: {
                Text(showsTechnicalDetails ? "ATProto Identity" : "Account")
            } footer: {
                Text("Already use Bluesky? Your Bluesky handle works too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        case .signUp:
            Section {
                Text(store.selectedMode.helperText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Account provider")
            }

            AccountSignUpServerFormView(store: store)
        }

        if let errorMessage = store.errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
    }
}

struct AccountActorIdentityRow: View {
    let identity: ActorIdentity
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        HStack(spacing: 12) {
            AccountActorAvatar(identity: identity)

            VStack(alignment: .leading, spacing: 3) {
                Text(identity.authenticationDisplayTitle(showsTechnicalDetails: showsTechnicalDetails))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = identity.authenticationDisplaySubtitle(
                    showsTechnicalDetails: showsTechnicalDetails
                ) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct AccountActorAvatar: View {
    let identity: ActorIdentity

    var body: some View {
        AsyncImage(url: identity.avatar) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)

            case .empty, .failure:
                AccountActorAvatarPlaceholder(identity: identity)

            @unknown default:
                AccountActorAvatarPlaceholder(identity: identity)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }
}

struct AccountActorAvatarPlaceholder: View {
    let identity: ActorIdentity
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        Circle()
            .fill(.secondary.opacity(0.18))
            .overlay {
                Text(identity.authenticationAvatarInitials(
                    showsTechnicalDetails: showsTechnicalDetails
                ))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
    }
}

private extension ActorIdentity {
    func authenticationDisplayTitle(showsTechnicalDetails: Bool) -> String {
        TechnicalDetails.identityTitle(
            displayName: displayName,
            handle: handle?.rawValue,
            technicalID: did.description,
            isVisible: showsTechnicalDetails
        )
    }

    func authenticationDisplaySubtitle(showsTechnicalDetails: Bool) -> String? {
        TechnicalDetails.identitySubtitle(
            displayName: displayName,
            handle: handle?.rawValue,
            technicalID: did.description,
            isVisible: showsTechnicalDetails
        )
    }

    func authenticationAvatarInitials(showsTechnicalDetails: Bool) -> String {
        String(
            authenticationDisplayTitle(showsTechnicalDetails: showsTechnicalDetails).prefix(2)
        )
        .uppercased()
    }
}

struct AccountAuthenticationSubmitSection: View {
    @Bindable var store: StoreOf<Account>

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            AccountAuthenticationSubmitButton(store: store)
                .frame(minWidth: 220)
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
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
        #if os(iOS) || os(macOS)
        if #available(iOS 26, macOS 26, *) {
            content.safeAreaBar(edge: edge, spacing: spacing) {
                styledExpansionContent
            }
        } else {
            content.safeAreaInset(edge: edge, spacing: spacing) {
                styledExpansionContent
            }
            .safeEdgeExpansionScrollEdgeEffect(edge)
        }
        #else
        content.safeAreaInset(edge: edge, spacing: spacing) {
            styledExpansionContent
        }
        .safeEdgeExpansionScrollEdgeEffect(edge)
        #endif
    }

    var styledExpansionContent: some View {
        expansionContent
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
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
                Text("Use another account provider")
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

private func saveOpenMusicEventSessionStore(
    _ sessionStore: Shared<OAuth.SessionStore>
) async {
    do {
        try await sessionStore.save()
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
#endif
