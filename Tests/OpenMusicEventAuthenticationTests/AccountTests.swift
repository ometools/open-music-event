import ATProto
import ATProtoOAuth
import Clocks
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
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
        #expect(store.surface == .authentication)
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
    func accountButtonPresentsAuthenticationSheetWhenAlreadySignedIn() async throws {
        let session = try accountTestSession(
            did: "did:plc:alice123",
            pdsHost: "alice.pds.example"
        )
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(session)
        let store = Store(
            initialState: Account.State.localTestState(
                sessionStore: Shared(value: sessionStoreValue),
                selectedSessionID: Shared(value: session.accountID as Atmosphere.Account.ID?)
            )
        ) {
            Account()
        }

        let task = store.send(.accountButtonTapped)
        await task?.value

        #expect(store.isAuthenticationSheetPresented)
        #expect(store.sessionStore[session.accountID] == session)
        #expect(store.surface == .accountManagement)
    }

    @Test
    func accountButtonClearsSignInFormWhenAddingAnotherAccount() async throws {
        let session = try accountTestSession(
            did: "did:plc:alice123",
            pdsHost: "alice.pds.example"
        )
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(session)
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
        } operation: {
            Store(
                initialState: Account.State.localTestState(
                    selectedMode: .signUp,
                    signInLoginHint: "alice.example.com",
                    sessionStore: Shared(value: sessionStoreValue),
                    selectedSessionID: Shared(value: session.accountID as Atmosphere.Account.ID?)
                )
            ) {
                Account()
            }
        }

        let task = store.send(.accountButtonTapped)
        await task?.value

        #expect(store.isAuthenticationSheetPresented)
        #expect(store.selectedMode == .signIn)
        #expect(store.signInLoginHint == "")
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
            Store(
                initialState: Account.State.localTestState(
                    selectedMode: .signUp,
                    signUpServerConfiguration: OpenMusicEventOAuth.signUpServerConfiguration
                )
            ) {
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
    func accountRowsLoadFriendlyIdentityLabels() async throws {
        let session = try accountTestSession(
            did: "did:plc:alice123",
            pdsHost: "alice.pds.example"
        )
        let avatarURL = URL(string: "https://cdn.example/alice-avatar.jpg")
        let identity = ActorIdentity(
            did: session.accountID.rawValue,
            handle: Atmosphere.Account.Handle(rawValue: "alice.example.com"),
            displayName: "Alice Example",
            avatar: avatarURL,
            source: .canonicalResolution
        )
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(session)
        let store = withDependencies {
            $0.actorIdentityLookup.resolve = { input in
                #expect(input == "did:plc:alice123")
                return identity
            }
        } operation: {
            Store(
                initialState: Account.State.localTestState(
                    sessionStore: Shared(value: sessionStoreValue),
                    selectedSessionID: Shared(value: session.accountID as Atmosphere.Account.ID?)
                )
            ) {
                Account()
            }
        }

        let task = store.send(.accountRowsAppeared)
        await task?.value
        try await waitForCondition {
            store.accountRows.first?.title == "Alice Example"
        }

        let row = try #require(store.accountRows.first)
        #expect(row.title == "Alice Example")
        #expect(row.subtitle == "alice.example.com")
        #expect(row.pickerHandle == "@alice.example.com")
        #expect(row.identity?.avatar == avatarURL)
        #expect(!row.title.contains("did:"))
        #expect(!row.subtitle.contains("did:"))
    }

    @Test
    func accountRowsFallbackDoesNotSurfaceDID() async throws {
        let session = try accountTestSession(
            did: "did:plc:fallback123",
            pdsHost: "fallback.pds.example"
        )
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(session)
        var state = Account.State.localTestState(
            sessionStore: Shared(value: sessionStoreValue),
            selectedSessionID: Shared(value: session.accountID as Atmosphere.Account.ID?)
        )
        state.accountIdentities[session.accountID] = .loaded(
            ActorIdentity(
                did: session.accountID.rawValue,
                handle: Atmosphere.Account.Handle(
                    rawValue: session.accountID.rawValue.description
                ),
                source: .canonicalResolution
            )
        )

        let row = try #require(state.accountRows.first)

        #expect(row.title == "AT Protocol account")
        #expect(row.subtitle == "Hosted by fallback.pds.example")
        #expect(row.pickerHandle == "Account unavailable")
        #expect(!row.title.contains("did:"))
        #expect(!row.subtitle.contains("did:"))
    }

    @Test
    func accountRowsAreOrderedByMostRecentlyUsedAccount() async throws {
        let alice = try accountTestSession(did: "did:plc:alice123", pdsHost: "alice.pds.example")
        let bob = try accountTestSession(did: "did:plc:bob123", pdsHost: "bob.pds.example")
        let carla = try accountTestSession(did: "did:plc:carla123", pdsHost: "carla.pds.example")
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(alice)
        sessionStoreValue.upsert(bob, select: false)
        sessionStoreValue.upsert(carla, select: false)
        let store = Store(
            initialState: Account.State.localTestState(
                sessionStore: Shared(value: sessionStoreValue),
                selectedSessionID: Shared(value: bob.accountID as Atmosphere.Account.ID?),
                recentlyUsedAccountIDs: Shared(value: [bob.accountID, alice.accountID])
            )
        ) {
            Account()
        }

        expectNoDifference(
            store.accountRows.map(\.id),
            [bob.accountID, alice.accountID, carla.accountID]
        )

        let task = store.send(.accountRowTapped(carla.accountID))
        await task?.value

        expectNoDifference(
            store.recentlyUsedAccountIDs,
            [carla.accountID, bob.accountID, alice.accountID]
        )
        expectNoDifference(
            store.accountRows.map(\.id),
            [carla.accountID, bob.accountID, alice.accountID]
        )
    }

    @Test
    func selectingStoredAccountUpdatesSelectedSessionID() async throws {
        let keychainStorage = InMemoryKeychainStorage()
        let selectedSessionIDItem = KeychainStorageItem(
            service: "fm.woody.openMusicEvent.tests",
            account: "account.select.selectedSessionID"
        )
        let alice = try accountTestSession(did: "did:plc:alice123", pdsHost: "alice.pds.example")
        let bob = try accountTestSession(did: "did:plc:bob123", pdsHost: "bob.pds.example")
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(alice)
        sessionStoreValue.upsert(bob)
        let selectedSessionID = Shared(
            wrappedValue: alice.accountID as Atmosphere.Account.ID?,
            KeychainSharedKey(item: selectedSessionIDItem)
        )
        let store = withDependencies {
            $0.keychainStorage = .inMemory(keychainStorage)
        } operation: {
            Store(
                initialState: Account.State.localTestState(
                    sessionStore: Shared(value: sessionStoreValue),
                    selectedSessionID: selectedSessionID
                )
            ) {
                Account()
            }
        }

        let task = store.send(.accountRowTapped(bob.accountID))
        await task?.value

        #expect(store.selectedSessionID == bob.accountID)
        #expect(store.session == bob)
        try await waitForCondition {
            keychainStorage.data(for: selectedSessionIDItem) != nil
        }
        let savedSelectedSessionID = try JSONDecoder().decode(
            Atmosphere.Account.ID?.self,
            from: try #require(keychainStorage.data(for: selectedSessionIDItem))
        )
        #expect(savedSelectedSessionID == bob.accountID)
    }

    @Test
    func loggingOutSelectedStoredAccountSelectsRemainingAccountAndPersists() async throws {
        let keychainStorage = InMemoryKeychainStorage()
        let sessionStoreItem = KeychainStorageItem(
            service: "fm.woody.openMusicEvent.tests",
            account: "account.rowLogOut.sessionStore"
        )
        let selectedSessionIDItem = KeychainStorageItem(
            service: "fm.woody.openMusicEvent.tests",
            account: "account.rowLogOut.selectedSessionID"
        )
        let alice = try accountTestSession(did: "did:plc:alice123", pdsHost: "alice.pds.example")
        let bob = try accountTestSession(did: "did:plc:bob123", pdsHost: "bob.pds.example")
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(alice)
        sessionStoreValue.upsert(bob, select: false)
        let sessionStore = Shared(
            wrappedValue: sessionStoreValue,
            KeychainSharedKey(item: sessionStoreItem)
        )
        let selectedSessionID = Shared(
            wrappedValue: alice.accountID as Atmosphere.Account.ID?,
            KeychainSharedKey(item: selectedSessionIDItem)
        )
        let store = withDependencies {
            $0.keychainStorage = .inMemory(keychainStorage)
        } operation: {
            Store(
                initialState: Account.State.localTestState(
                    sessionStore: sessionStore,
                    selectedSessionID: selectedSessionID
                )
            ) {
                Account()
            }
        }

        let task = store.send(.accountLogOutButtonTapped(alice.accountID))
        await task?.value

        #expect(store.sessionStore[alice.accountID] == nil)
        #expect(store.sessionStore[bob.accountID] == bob)
        #expect(store.selectedSessionID == bob.accountID)
        #expect(store.session == bob)
        #expect(store.surface == .accountManagement)
        try await waitForCondition {
            keychainStorage.data(for: sessionStoreItem) != nil &&
                keychainStorage.data(for: selectedSessionIDItem) != nil
        }
        let savedSessionStore = try JSONDecoder().decode(
            OAuth.SessionStore.self,
            from: try #require(keychainStorage.data(for: sessionStoreItem))
        )
        let savedSelectedSessionID = try JSONDecoder().decode(
            Atmosphere.Account.ID?.self,
            from: try #require(keychainStorage.data(for: selectedSessionIDItem))
        )
        #expect(savedSessionStore[alice.accountID] == nil)
        #expect(savedSessionStore[bob.accountID] == bob)
        #expect(savedSelectedSessionID == bob.accountID)
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
    func signInFormAddsSecondAccountAndSelectsIt() async throws {
        let alice = try accountTestSession(did: "did:plc:alice123", pdsHost: "alice.pds.example")
        let bob = try accountTestSession(did: "did:plc:bob123", pdsHost: "bob.pds.example")
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(alice)
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
                    signInLoginHint: "bob.example.com",
                    sessionStore: Shared(value: sessionStoreValue),
                    selectedSessionID: Shared(value: alice.accountID as Atmosphere.Account.ID?)
                )
            ) {
                Account()
            }
        }

        let task = store.send(.submitAuthenticationFormButtonTapped)
        try await waitForCondition {
            store.isLoginInProgress
        }
        #expect(
            await accountAuthorization.signInRequests == [
                AccountDirectAuthorizationRecorder.SignInRequest(
                    requirement: OpenMusicEventOAuth.baseAuthRequirement,
                    loginHint: "bob.example.com",
                    sessionStore: sessionStoreValue
                )
            ]
        )

        await accountAuthorization.resumeSignIn(returning: bob)
        await task?.value
        try await waitForCondition {
            store.session == bob
        }

        #expect(store.sessionStore[alice.accountID] == alice)
        #expect(store.sessionStore[bob.accountID] == bob)
        #expect(store.selectedSessionID == bob.accountID)
        #expect(store.isAuthenticationSheetPresented == false)
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
        let keychainStorage = InMemoryKeychainStorage()
        let sessionStoreItem = KeychainStorageItem(
            service: "fm.woody.openMusicEvent.tests",
            account: "account.signUp.sessionStore"
        )
        let selectedSessionIDItem = KeychainStorageItem(
            service: "fm.woody.openMusicEvent.tests",
            account: "account.signUp.selectedSessionID"
        )
        let sessionStore = Shared(
            wrappedValue: OAuth.SessionStore(),
            KeychainSharedKey(item: sessionStoreItem)
        )
        let selectedSessionID = Shared(
            wrappedValue: Atmosphere.Account.ID?.none,
            KeychainSharedKey(item: selectedSessionIDItem)
        )
        let accountAuthorization = AccountDirectAuthorizationRecorder()
        let state = Account.State.localTestState(
            selectedMode: .signUp,
            sessionStore: sessionStore,
            selectedSessionID: selectedSessionID
        )
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.keychainStorage = .inMemory(keychainStorage)
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
        try await waitForCondition {
            keychainStorage.data(for: sessionStoreItem) != nil &&
                keychainStorage.data(for: selectedSessionIDItem) != nil
        }
        let savedSessionStoreData = try #require(
            keychainStorage.data(for: sessionStoreItem)
        )
        let savedSessionStore = try JSONDecoder().decode(
            OAuth.SessionStore.self,
            from: savedSessionStoreData
        )
        let savedSelectedSessionIDData = try #require(
            keychainStorage.data(for: selectedSessionIDItem)
        )
        let savedSelectedSessionID = try JSONDecoder().decode(
            Atmosphere.Account.ID?.self,
            from: savedSelectedSessionIDData
        )
        #expect(
            savedSessionStore[OAuth.Session.placeholder.accountID] == OAuth.Session.placeholder
        )
        #expect(savedSelectedSessionID == OAuth.Session.placeholder.accountID)
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
        state.oauth.state.$sessionStore.withLock { $0.upsert(.placeholder) }
        state.$selectedSessionID.withLock {
            $0 = OAuth.Session.placeholder.accountID
        }
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
        #expect(store.sessionStore[OAuth.Session.placeholder.accountID] == nil)
        #expect(await recorder.didCancel)
    }

    @Test
    func accountManagementLogOutReturnsToAuthenticationSurface() async {
        let recorder = AccountAuthorizationRecorder()
        let state = Account.State.localTestState()
        state.oauth.state.$sessionStore.withLock { $0.upsert(.placeholder) }
        state.$selectedSessionID.withLock {
            $0 = OAuth.Session.placeholder.accountID
        }
        let store = withDependencies {
            $0.openMusicEventAuthorizationRequests = .recording(recorder)
        } operation: {
            Store(initialState: state) {
                Account()
            }
        }

        #expect(store.surface == .accountManagement)

        let task = store.send(.signOutAllButtonTapped)
        await task?.value

        #expect(store.session == nil)
        #expect(store.sessionStore.sessions.isEmpty)
        #expect(store.selectedSessionID == nil)
        #expect(store.surface == .authentication)
        #expect(store.isAuthenticationSheetPresented == false)
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
        signInLoginHint: String = "",
        signUpServerConfiguration: OAuthSignUpServerConfiguration? = nil,
        authFailureMessage: Shared<ErrorMessage?> = Shared(value: nil),
        sessionStore: Shared<OAuth.SessionStore> = Shared(value: OAuth.SessionStore()),
        selectedSessionID: Shared<Atmosphere.Account.ID?> = Shared(value: nil),
        recentlyUsedAccountIDs: Shared<[Atmosphere.Account.ID]> = Shared(value: [])
    ) -> Self {
        Self(
            isAuthenticationSheetPresented: isAuthenticationSheetPresented,
            selectedMode: selectedMode,
            signInLoginHint: signInLoginHint,
            signUpServerConfiguration: signUpServerConfiguration,
            authFailureMessage: authFailureMessage,
            sessionStore: sessionStore,
            selectedSessionID: selectedSessionID,
            recentlyUsedAccountIDs: recentlyUsedAccountIDs
        )
    }
}

private func accountTestSession(
    did didString: String,
    pdsHost: String
) throws -> OAuth.Session {
    let did = try #require(DID(didString))
    return OAuth.Session(
        accountID: Atmosphere.Account.ID(did),
        pdsHost: ATProto.PDSHost(pdsHost),
        tokenEndpoint: OAuth.AuthorizationServer.TokenEndpoint(
            URL(string: "https://\(pdsHost)/oauth/token")!
        ),
        scope: "atproto",
        accessToken: OAuth.AccessToken(rawValue: "\(didString)-access-token"),
        refreshToken: OAuth.RefreshToken(rawValue: "\(didString)-refresh-token"),
        dpopKey: OAuth.DPOP.Key()
    )
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
