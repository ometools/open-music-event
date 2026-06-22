import ATProtoOAuth
import Clocks
import ComposableArchitecture2
import Dependencies
import Sharing
import TCATProtoAuthentication
import Testing

@testable import OpenMusicEventAuthentication

@MainActor
@Suite("Account", .serialized)
struct AccountTests {
    @Test
    func loggedOutAccountDefaultsToSignInMode() {
        let store = Store(initialState: Account.State.localTestState()) {
            Account()
        }

        #expect(store.isAuthenticationSheetPresented == false)
        #expect(store.selectedMode == .signIn)
        #expect(store.accountIDDescription == nil)
    }

    @Test
    func accountButtonPresentsAuthenticationSheet() async {
        let store = Store(initialState: Account.State.localTestState()) {
            Account()
        }

        let task = store.send(.accountButtonTapped)
        await task?.value

        #expect(store.isAuthenticationSheetPresented)
    }

    @Test
    func dismissingAuthenticationSheetClearsPresentation() async {
        let store = Store(
            initialState: Account.State.localTestState(isAuthenticationSheetPresented: true)
        ) {
            Account()
        }

        let task = store.send(.authenticationSheetDismissed)
        await task?.value

        #expect(store.isAuthenticationSheetPresented == false)
    }

    @Test
    func selectingEuroskyUpdatesSignUpServerHost() async {
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
        } operation: {
            Store(initialState: Account.State.localTestState(selectedMode: .signUp)) {
                Account()
            }
        }

        let task = store.send(.signUpServerOptionTapped("eurosky"))
        await task?.value

        #expect(store.selectedSignUpServerOptionID == "eurosky")
        #expect(store.signUpServerHost == "eurosky.social")
        #expect(store.usesCustomSignUpServerHost == false)
    }

    @Test
    func comingSoonSignUpServerCannotBeSelected() async {
        let store = Store(initialState: Account.State.localTestState(selectedMode: .signUp)) {
            Account()
        }
        let originalOptionID = store.selectedSignUpServerOptionID
        let originalServerHost = store.signUpServerHost

        let task = store.send(.signUpServerOptionTapped("ome"))
        await task?.value

        #expect(store.selectedSignUpServerOptionID == originalOptionID)
        #expect(store.signUpServerHost == originalServerHost)
        #expect(store.usesCustomSignUpServerHost == false)
    }

    @Test
    func customSignUpServerClearsSelectedProviderAndRequiresHost() async {
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
        } operation: {
            Store(initialState: Account.State.localTestState(selectedMode: .signUp)) {
                Account()
            }
        }

        let task = store.send(.customSignUpServerOptionTapped)
        await task?.value

        #expect(store.selectedSignUpServerOptionID == nil)
        #expect(store.signUpServerHost == "")
        #expect(store.usesCustomSignUpServerHost)
        #expect(store.isAuthenticationFormSubmitDisabled)
    }

    @Test
    func selectedModeCanChangeToSignUp() async {
        let store = Store(initialState: Account.State.localTestState()) {
            Account()
        }

        let task = store.send(.selectedModeChanged(.signUp))
        await task?.value

        #expect(store.selectedMode == .signUp)
    }

    @Test
    func accountStateUsesSignUpServerConfigurationDependency() {
        let configuration = accountTestSignUpServerConfiguration

        withDependencies {
            $0.openMusicEventSignUpServerConfiguration = configuration
        } operation: {
            let state = Account.State.localTestState(selectedMode: .signUp)

            #expect(state.signUpServerConfiguration == configuration)
            #expect(state.signUpServerHost == configuration.defaultServerHost)
            #expect(state.selectedSignUpServerOptionID == "account-test")
        }
    }

    @Test
    func signInFormLaunchesDirectAuthorizationWithLoginHint() async {
        let accountAuthorization = AccountDirectAuthorizationRecorder()
        let authorizationRequests = AccountAuthorizationRecorder()
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.openMusicEventAccountAuthorizationClient = .recording(accountAuthorization)
            $0.openMusicEventAuthorizationRequests = .recording(authorizationRequests)
        } operation: {
            Store(
                initialState: Account.State.localTestState(
                    isAuthenticationSheetPresented: true,
                    signInLoginHint: "  woody.fm  "
                )
            ) {
                Account()
            }
        }

        let task = store.send(.submitAuthenticationFormButtonTapped)
        await task?.value

        #expect(
            await accountAuthorization.signInRequests == [
                AccountDirectAuthorizationRecorder.SignInRequest(
                    requirement: OpenMusicEventOAuth.baseAuthRequirement,
                    loginHint: "woody.fm",
                    sessionStore: OAuth.SessionStore()
                )
            ]
        )
        #expect(await authorizationRequests.loginRequests.isEmpty)
        #expect(store.session == .placeholder)
        #expect(store.isAuthenticationSheetPresented == false)
        #expect(store.isLoginInProgress == false)
        #expect(store.errorMessage == nil)
    }

    @Test
    func signInFormKeepsSheetPresentedWhileAuthorizationIsInFlight() async throws {
        let accountAuthorization = AccountDirectAuthorizationRecorder(
            signInContinuation: .suspended
        )
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.openMusicEventAccountAuthorizationClient = .recording(accountAuthorization)
        } operation: {
            Store(
                initialState: Account.State.localTestState(
                    isAuthenticationSheetPresented: true,
                    signInLoginHint: "woody.fm"
                )
            ) {
                Account()
            }
        }

        let task = store.send(.submitAuthenticationFormButtonTapped)
        try await waitForCondition {
            store.isLoginInProgress
        }

        #expect(store.isAuthenticationSheetPresented)
        #expect(store.isLoginInProgress)
        #expect(store.errorMessage == nil)

        await accountAuthorization.resumeSignIn(returning: .placeholder)
        await task?.value
        try await waitForCondition {
            store.session == .placeholder
        }

        #expect(store.isAuthenticationSheetPresented == false)
        #expect(store.isLoginInProgress == false)
        #expect(store.session == .placeholder)
    }

    @Test
    func signInCancellationClearsProgressWithoutError() async throws {
        let accountAuthorization = AccountDirectAuthorizationRecorder(
            signInContinuation: .suspended
        )
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.openMusicEventAccountAuthorizationClient = .recording(accountAuthorization)
        } operation: {
            Store(
                initialState: Account.State.localTestState(
                    isAuthenticationSheetPresented: true,
                    signInLoginHint: "woody.fm"
                )
            ) {
                Account()
            }
        }

        let task = store.send(.submitAuthenticationFormButtonTapped)
        try await waitForCondition {
            store.isLoginInProgress
        }
        await accountAuthorization.resumeSignIn(throwing: CancellationError())
        await task?.value
        try await waitForCondition {
            !store.isLoginInProgress
        }

        #expect(store.isAuthenticationSheetPresented)
        #expect(store.isLoginInProgress == false)
        #expect(store.errorMessage == nil)
        #expect(store.session == nil)
    }

    @Test
    func signUpFormLaunchesDirectAuthorizationWithSelectedServer() async {
        let accountAuthorization = AccountDirectAuthorizationRecorder()
        let authorizationRequests = AccountAuthorizationRecorder()
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.openMusicEventAccountAuthorizationClient = .recording(accountAuthorization)
            $0.openMusicEventAuthorizationRequests = .recording(authorizationRequests)
        } operation: {
            Store(
                initialState: Account.State.localTestState(
                    isAuthenticationSheetPresented: true,
                    selectedMode: .signUp
                )
            ) {
                Account()
            }
        }

        let task = store.send(.submitAuthenticationFormButtonTapped)
        await task?.value

        #expect(
            await accountAuthorization.signUpRequests == [
                AccountDirectAuthorizationRecorder.SignUpRequest(
                    requirement: OpenMusicEventOAuth.baseAuthRequirement,
                    serverHost: OpenMusicEventOAuth
                        .signUpServerConfiguration
                        .defaultServerHost
                )
            ]
        )
        #expect(await authorizationRequests.signUpRequests.isEmpty)
        #expect(store.session == .placeholder)
        #expect(store.isAuthenticationSheetPresented == false)
        #expect(store.isSignUpInProgress == false)
        #expect(store.errorMessage == nil)
    }

    @Test
    func signUpSuccessStoresSelectedSession() async throws {
        let accountAuthorization = AccountDirectAuthorizationRecorder()
        let state = Account.State.localTestState(selectedMode: .signUp)
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.openMusicEventAccountAuthorizationClient = .recording(accountAuthorization)
        } operation: {
            Store(initialState: state) {
                Account()
            }
        }

        let task = store.send(.submitAuthenticationFormButtonTapped)
        await task?.value
        try await waitForCondition {
            store.session == .placeholder
        }

        #expect(store.session == .placeholder)
        #expect(store.isSignUpInProgress == false)
        #expect(store.errorMessage == nil)
    }

    @Test
    func signUpCancellationClearsProgressWithoutError() async throws {
        let accountAuthorization = AccountDirectAuthorizationRecorder(
            signUpContinuation: .suspended
        )
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.openMusicEventAccountAuthorizationClient = .recording(accountAuthorization)
        } operation: {
            Store(
                initialState: Account.State.localTestState(
                    isAuthenticationSheetPresented: true,
                    selectedMode: .signUp
                )
            ) {
                Account()
            }
        }

        let task = store.send(.submitAuthenticationFormButtonTapped)
        try await waitForCondition {
            store.isSignUpInProgress
        }
        await accountAuthorization.resumeSignUp(throwing: CancellationError())
        await task?.value
        try await waitForCondition {
            !store.isSignUpInProgress
        }

        #expect(store.isAuthenticationSheetPresented)
        #expect(store.isSignUpInProgress == false)
        #expect(store.errorMessage == nil)
    }

    @Test
    func logoutClearsStoredSessionAndCancelsRequests() async {
        let recorder = AccountAuthorizationRecorder()
        let state = Account.State.localTestState()
        state.oauth.state.$session.withLock { $0 = .placeholder }
        state.oauth.state.$sessionStore.withLock { $0.upsert(.placeholder) }
        let store = withDependencies {
            $0.openMusicEventAuthorizationRequests = .recording(recorder)
        } operation: {
            Store(initialState: state) {
                Account()
            }
        }

        let task = store.spawn(\.oauth).send(.logoutButtonTapped)
        await task?.value

        #expect(store.session == nil)
        #expect(store.sessionStore.selectedSession == nil)
        #expect(await recorder.didCancel)
    }
}

@MainActor
private func waitForCondition(
    _ condition: @escaping @MainActor () -> Bool
) async throws {
    for _ in 0..<100 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(condition())
}

private extension Account.State {
    static func localTestState(
        isAuthenticationSheetPresented: Bool = false,
        selectedMode: Account.Mode = .signIn,
        signInLoginHint: String = ""
    ) -> Self {
        Self(
            isAuthenticationSheetPresented: isAuthenticationSheetPresented,
            selectedMode: selectedMode,
            signInLoginHint: signInLoginHint,
            authFailureMessage: Shared<ErrorMessage?>(value: nil),
            session: Shared<OAuth.Session?>(value: nil),
            sessionStore: Shared<OAuth.SessionStore>(value: OAuth.SessionStore())
        )
    }
}

private let accountTestSignUpServerConfiguration = OAuthSignUpServerConfiguration(
    defaultServerHost: "account.example",
    options: [
        OAuthSignUpServerOption(
            id: "account-test",
            title: "Account Test",
            subtitle: "account.example",
            description: "A test account provider.",
            imageURL: nil,
            metadataSource: "test",
            availability: .available(serverHost: "account.example")
        ),
    ],
    allowsCustomServerHost: false
)

private actor AccountAuthorizationRecorder {
    struct LoginRequest: Equatable {
        var requirement: OAuth.AuthRequirement
        var loginHint: String
    }

    struct SignUpRequest: Equatable {
        var requirement: OAuth.AuthRequirement
        var signUpServerConfiguration: OAuthSignUpServerConfiguration
    }

    private(set) var didCancel = false
    private(set) var loginRequests: [LoginRequest] = []
    private(set) var requirements: [OAuth.AuthRequirement] = []
    private(set) var signUpRequests: [SignUpRequest] = []
    private let signUpError: (any Error)?

    init(signUpError: (any Error)? = nil) {
        self.signUpError = signUpError
    }

    func recordCancel() {
        didCancel = true
    }

    func recordRequirement(_ requirement: OAuth.AuthRequirement) {
        requirements.append(requirement)
    }

    func recordLogin(
        _ requirement: OAuth.AuthRequirement,
        loginHint: String
    ) {
        loginRequests.append(
            LoginRequest(
                requirement: requirement,
                loginHint: loginHint
            )
        )
    }

    func recordSignUp(
        _ requirement: OAuth.AuthRequirement,
        signUpServerConfiguration: OAuthSignUpServerConfiguration
    ) throws {
        signUpRequests.append(
            SignUpRequest(
                requirement: requirement,
                signUpServerConfiguration: signUpServerConfiguration
            )
        )
        if let signUpError {
            throw signUpError
        }
    }
}

private actor AccountDirectAuthorizationRecorder {
    enum AuthorizationContinuation {
        case immediate
        case suspended
    }

    struct SignInRequest: Equatable {
        var requirement: OAuth.AuthRequirement
        var loginHint: String
        var sessionStore: OAuth.SessionStore
    }

    struct SignUpRequest: Equatable {
        var requirement: OAuth.AuthRequirement
        var serverHost: String
    }

    private let signInContinuationMode: AuthorizationContinuation
    private let signUpContinuationMode: AuthorizationContinuation
    private var pendingSignInResume: Result<OAuth.Session, any Error>?
    private var pendingSignUpResume: Result<OAuth.Session, any Error>?
    private var signInContinuation: CheckedContinuation<OAuth.Session, any Error>?
    private var signUpContinuation: CheckedContinuation<OAuth.Session, any Error>?
    private(set) var signInRequests: [SignInRequest] = []
    private(set) var signUpRequests: [SignUpRequest] = []

    init(
        signInContinuation: AuthorizationContinuation = .immediate,
        signUpContinuation: AuthorizationContinuation = .immediate
    ) {
        self.signInContinuationMode = signInContinuation
        self.signUpContinuationMode = signUpContinuation
    }

    func recordSignIn(
        _ requirement: OAuth.AuthRequirement,
        loginHint: String,
        sessionStore: OAuth.SessionStore
    ) async throws -> OAuth.Session {
        signInRequests.append(
            SignInRequest(
                requirement: requirement,
                loginHint: loginHint,
                sessionStore: sessionStore
            )
        )

        switch signInContinuationMode {
        case .immediate:
            return .placeholder

        case .suspended:
            return try await withCheckedThrowingContinuation { continuation in
                if let pendingSignInResume {
                    self.pendingSignInResume = nil
                    continuation.resume(with: pendingSignInResume)
                } else {
                    self.signInContinuation = continuation
                }
            }
        }
    }

    func resumeSignIn(returning session: OAuth.Session) {
        if let signInContinuation {
            self.signInContinuation = nil
            signInContinuation.resume(returning: session)
        } else {
            pendingSignInResume = .success(session)
        }
    }

    func resumeSignIn(throwing error: any Error) {
        if let signInContinuation {
            self.signInContinuation = nil
            signInContinuation.resume(throwing: error)
        } else {
            pendingSignInResume = .failure(error)
        }
    }

    func recordSignUp(
        _ requirement: OAuth.AuthRequirement,
        serverHost: String
    ) async throws -> OAuth.Session {
        signUpRequests.append(
            SignUpRequest(
                requirement: requirement,
                serverHost: serverHost
            )
        )

        switch signUpContinuationMode {
        case .immediate:
            return .placeholder

        case .suspended:
            return try await withCheckedThrowingContinuation { continuation in
                if let pendingSignUpResume {
                    self.pendingSignUpResume = nil
                    continuation.resume(with: pendingSignUpResume)
                } else {
                    self.signUpContinuation = continuation
                }
            }
        }
    }

    func resumeSignUp(returning session: OAuth.Session) {
        if let signUpContinuation {
            self.signUpContinuation = nil
            signUpContinuation.resume(returning: session)
        } else {
            pendingSignUpResume = .success(session)
        }
    }

    func resumeSignUp(throwing error: any Error) {
        if let signUpContinuation {
            self.signUpContinuation = nil
            signUpContinuation.resume(throwing: error)
        } else {
            pendingSignUpResume = .failure(error)
        }
    }
}

private extension OpenMusicEventAuthorizationRequests {
    static func recording(_ recorder: AccountAuthorizationRecorder) -> Self {
        Self(
            authorizeWithLoginHint: { requirement, loginHint in
                await recorder.recordLogin(requirement, loginHint: loginHint)
            },
            broker: {
                OAuth.AuthorizationBroker { requirement in
                    await recorder.recordRequirement(requirement)
                }
            },
            requests: {
                AsyncStream { continuation in
                    continuation.finish()
                }
            },
            signUp: { requirement, serverHost in
                try await recorder.recordSignUp(
                    requirement,
                    signUpServerConfiguration: OAuthSignUpServerConfiguration(
                        defaultServerHost: serverHost
                    )
                )
            },
            signUpWithConfiguration: { requirement, configuration in
                try await recorder.recordSignUp(
                    requirement,
                    signUpServerConfiguration: configuration
                )
            },
            succeed: {},
            fail: { _ in },
            cancel: {
                await recorder.recordCancel()
            }
        )
    }
}

private extension OpenMusicEventAccountAuthorizationClient {
    static func recording(_ recorder: AccountDirectAuthorizationRecorder) -> Self {
        Self(
            signIn: { requirement, loginHint, sessionStore in
                try await recorder.recordSignIn(
                    requirement,
                    loginHint: loginHint,
                    sessionStore: sessionStore
                )
            },
            signUp: { requirement, serverHost in
                try await recorder.recordSignUp(
                    requirement,
                    serverHost: serverHost
                )
            }
        )
    }
}
