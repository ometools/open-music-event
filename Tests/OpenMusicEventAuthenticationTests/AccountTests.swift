import ATProto
import ATProtoOAuth
import BlueskyActorCache
import Clocks
import ComposableArchitecture2
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import Sharing
import SQLiteData
import TCATProtoAuthentication
import Testing

@testable import OpenMusicEventAuthentication

@MainActor
@Suite(
    "Account",
    .serialized,
    .dependencies {
        $0.defaultDatabase = try makeAccountTestDatabase()
    }
)
struct AccountTests {
    @Test
    func loggedOutAccountDefaultsToSignInMode() {
        let store = Store(initialState: Account.State.localTestState()) {
            Account()
        }

        #expect(store.presentation == nil)
        #expect(store.selectedMode == .signIn)
        #expect(store.accountIDDescription == nil)
        #expect(store.surface == .authentication)
    }

    @Test
    func signInButtonPresentsAuthentication() async {
        let store = Store(initialState: Account.State.localTestState()) {
            Account()
        }

        let task = store.send(.signInButtonTapped)
        await task?.value

        #expect(store.presentation == .authentication(.direct))
    }

    @Test
    func signInButtonPresentsAuthenticationWhenAlreadySignedIn() async throws {
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

        let task = store.send(.signInButtonTapped)
        await task?.value

        #expect(store.presentation == .authentication(.direct))
        #expect(store.sessionStore[session.accountID] == session)
        #expect(store.surface == .accountManagement)
    }

    @Test
    func accountListButtonPresentsAccountsSheet() async throws {
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

        let presentationTask = store.send(.accountListButtonTapped)
        await presentationTask?.value

        #expect(store.presentation == .accountManagement)

        let dismissalTask = store.send(.accountPresentationCloseButtonTapped)
        await dismissalTask?.value

        #expect(store.presentation == nil)
    }

    @Test
    func addAnotherAccountClearsSignInFormAndKeepsAccountReturnRoute() async throws {
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

        let task = store.send(.addAnotherAccountButtonTapped)
        await task?.value

        #expect(store.presentation == .authentication(.accountManagement))
        #expect(store.selectedMode == .signIn)
        #expect(store.signInLoginHint == "")
    }

    @Test
    func dismissingAuthenticationClearsPresentation() async {
        let store = Store(
            initialState: Account.State.localTestState(
                presentation: .authentication(.direct)
            )
        ) {
            Account()
        }

        let task = store.send(.accountPresentationDismissed)
        await task?.value

        #expect(store.presentation == nil)
    }

    @Test
    func closingAddAnotherAccountReturnsToAccountManagement() async throws {
        let session = try accountTestSession(
            did: "did:plc:alice123",
            pdsHost: "alice.pds.example"
        )
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(session)
        let store = Store(
            initialState: Account.State.localTestState(
                presentation: .authentication(.accountManagement),
                sessionStore: Shared(value: sessionStoreValue),
                selectedSessionID: Shared(value: session.accountID as Atmosphere.Account.ID?)
            )
        ) {
            Account()
        }

        let task = store.send(.accountPresentationCloseButtonTapped)
        await task?.value

        #expect(store.presentation == .accountManagement)
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
    func `selecting a sign-in autofill starts web authorization`() async throws {
        let authorizationRequests = AccountAuthorizationRecorder(
            signInContinuation: .suspended
        )
        let typeaheadQueries = AccountObservationRecorder<String>()
        let identity = ActorIdentity(
            did: try #require(DID("did:plc:alice123")),
            handle: Atmosphere.Account.Handle(rawValue: "alice.bsky.social"),
            displayName: "Alice Example",
            source: .typeahead
        )
        let state = Account.State.localTestState(
            presentation: .authentication(.direct)
        )
        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.actorTypeaheadSearch.search = { query in
                await typeaheadQueries.record(query.normalizedText)
                return [identity]
            }
            $0.openMusicEventAuthorizationRequests = .recording(
                authorizationRequests,
                sessionStore: state.oauth.state.$sessionStore
            )
        } operation: {
            Store(initialState: state) { Account() }
        }

        // The user searches for their account and sees Alice's profile offered as an autofill.
        await store.send(.signInActorSearchQueryChanged(" alice "))?.value

        let typeaheadQueryValues = await typeaheadQueries.values
        expectNoDifference(store.signInActorSearchResults, [identity])
        expectNoDifference(typeaheadQueryValues, ["alice"])
        #expect(store.signInActorSearchIsLoading == false)

        // Tapping the autofill immediately starts the web authorization flow for that handle.
        let selectionTask = store.send(.signInActorIdentityTapped(identity))
        try await waitForCondition {
            store.isLoginInProgress
        }

        #expect(store.signInLoginHint == "alice.bsky.social")
        #expect(store.signInActorSearchResults.isEmpty)
        let signInRequests = await authorizationRequests.loginRequests
        expectNoDifference(
            signInRequests,
            [
                AccountAuthorizationRecorder.LoginRequest(
                    requirement: OpenMusicEventOAuth.baseAuthRequirement,
                    loginHint: "alice.bsky.social"
                )
            ]
        )

        // Completing the web flow signs the user in and closes the sheet.
        await authorizationRequests.resumeSignIn(returning: .placeholder)
        await selectionTask?.value
        try await waitForCondition {
            store.session == .placeholder && store.presentation == nil
        }

        #expect(store.session == .placeholder)
        #expect(store.presentation == nil)
    }

    @Test
    func signInActorSearchLooksUpExactHandleOrDIDOnSubmit() async throws {
        let exactLookupInputs = AccountObservationRecorder<String>()
        let identity = ActorIdentity(
            did: try #require(DID("did:plc:exact123")),
            handle: Atmosphere.Account.Handle(rawValue: "exact.example.com"),
            displayName: "Exact Example",
            source: .canonicalResolution
        )
        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.actorTypeaheadSearch.search = { _ in [] }
            $0.actorIdentityLookup.resolve = { input in
                await exactLookupInputs.record(input)
                return identity
            }
        } operation: {
            Store(initialState: Account.State.localTestState()) {
                Account()
            }
        }

        await store.send(.signInActorSearchQueryChanged("exact.example.com"))?.value
        await store.send(.signInActorSearchSubmitted)?.value

        #expect(store.signInActorSearchResults == [identity])
        #expect(await exactLookupInputs.values == ["exact.example.com"])
        #expect(store.signInActorSearchFailures.isEmpty)
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
        let database = try makeAccountTestDatabase()
        let fetchedAt = Date(timeIntervalSince1970: 1_000)
        let session = try accountTestSession(
            did: "did:plc:alice123",
            pdsHost: "alice.pds.example"
        )
        let avatarURL = URL(string: "https://cdn.example/alice-avatar.jpg")
        try await seedAccountTestIdentity(
            in: database,
            did: "did:plc:alice123",
            handle: "alice.example.com",
            displayName: "Alice Example",
            avatar: avatarURL,
            fetchedAt: fetchedAt
        )
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(session)
        let store = withDependencies {
            $0.date.now = fetchedAt
            $0.defaultDatabase = database
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

        let task = store.send(.accountSessionsChanged)
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
    func `account rows hydrate a missing requested identity into the shared cache`() async throws {
        let database = try makeAccountTestDatabase()
        let actor = "did:plc:alice123"
        let avatarURL = URL(string: "https://cdn.example/alice-avatar.jpg")
        let session = try accountTestSession(
            did: actor,
            pdsHost: "alice.pds.example"
        )
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(session)
        let requestedActors = AccountObservationRecorder<String>()
        let validation = AccountSessionValidationRecorder(
            results: [session.accountID: .accepted(session)]
        )
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.blueskyActorProfileCache = BlueskyActorProfileCacheClient(
                cachedProfile: { _ in nil },
                refreshProfile: { actor in
                    BlueskyActorProfile(did: actor, handle: "unused.example")
                },
                refreshProfileIfNeeded: { actor, _, _ in
                    await requestedActors.record(actor)
                    try await seedAccountTestIdentity(
                        in: database,
                        did: actor,
                        handle: "alice.example.com",
                        displayName: "Alice Example",
                        avatar: avatarURL
                    )
                    return BlueskyActorProfile(
                        did: actor,
                        handle: "alice.example.com",
                        displayName: "Alice Example",
                        avatar: avatarURL
                    )
                }
            )
            $0.openMusicEventAccountSessionValidationClient = .recording(validation)
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

        #expect(store.accountRows.first?.title == "Account")

        try await waitForCondition {
            store.accountRows.first?.title == "Alice Example"
        }

        let actors = await requestedActors.values
        expectNoDifference(actors, [actor])
        let row = try #require(store.accountRows.first)
        #expect(row.subtitle == "alice.example.com")
        #expect(row.pickerHandle == "@alice.example.com")
        #expect(row.identity?.avatar == avatarURL)
    }

    @Test
    func accountStoresObserveOneActorIdentityCache() async throws {
        let database = try makeAccountTestDatabase()
        let session = try accountTestSession(
            did: "did:plc:alice123",
            pdsHost: "alice.pds.example"
        )
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(session)

        let stores = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            (
                Store(
                    initialState: Account.State.localTestState(
                        sessionStore: Shared(value: sessionStoreValue),
                        selectedSessionID: Shared(
                            value: session.accountID as Atmosphere.Account.ID?
                        )
                    )
                ) {
                    Account()
                },
                Store(
                    initialState: Account.State.localTestState(
                        sessionStore: Shared(value: sessionStoreValue),
                        selectedSessionID: Shared(
                            value: session.accountID as Atmosphere.Account.ID?
                        )
                    )
                ) {
                    Account()
                }
            )
        }

        #expect(stores.0.accountRows.first?.title == "Account")
        #expect(stores.1.accountRows.first?.title == "Account")

        try await database.write { db in
            try BlueskyActorProfile.insert {
                BlueskyActorProfile(
                    did: "did:plc:alice123",
                    handle: "alice.example.com",
                    displayName: "Alice Example"
                )
            }
            .execute(db)
            try BlueskyActorProfileCacheEntry.insert {
                BlueskyActorProfileCacheEntry(
                    actor: "did:plc:alice123",
                    did: "did:plc:alice123"
                )
            }
            .execute(db)
        }

        try await waitForCondition {
            stores.0.accountRows.first?.title == "Alice Example"
                && stores.1.accountRows.first?.title == "Alice Example"
        }
        #expect(stores.0.accountRows.first?.pickerHandle == "@alice.example.com")
        #expect(stores.1.accountRows.first?.pickerHandle == "@alice.example.com")
    }

    @Test
    func accountRowsFallbackDoesNotSurfaceDID() async throws {
        let database = try makeAccountTestDatabase()
        let session = try accountTestSession(
            did: "did:plc:fallback123",
            pdsHost: "fallback.pds.example"
        )
        try await seedAccountTestIdentity(
            in: database,
            did: "did:plc:fallback123",
            handle: "did:plc:fallback123"
        )
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(session)
        let state = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            Account.State.localTestState(
                sessionStore: Shared(value: sessionStoreValue),
                selectedSessionID: Shared(value: session.accountID as Atmosphere.Account.ID?)
            )
        }

        let row = try #require(state.accountRows.first)

        #expect(row.title == "Account")
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
    func accountRowsMarkTerminalAuthFailuresAsNeedingRelog() async throws {
        let alice = try accountTestSession(did: "did:plc:alice123", pdsHost: "alice.pds.example")
        let bob = try accountTestSession(did: "did:plc:bob123", pdsHost: "bob.pds.example")
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(alice)
        sessionStoreValue.upsert(bob, select: false)
        let validation = AccountSessionValidationRecorder(
            results: [
                alice.accountID: .requiresRelog,
                bob.accountID: .accepted(bob),
            ]
        )
        let store = withDependencies {
            $0.openMusicEventAccountSessionValidationClient = .recording(validation)
        } operation: {
            Store(
                initialState: Account.State.localTestState(
                    sessionStore: Shared(value: sessionStoreValue),
                    selectedSessionID: Shared(value: alice.accountID as Atmosphere.Account.ID?)
                )
            ) {
                Account()
            }
        }

        let task = store.send(.accountSessionsChanged)
        await task?.value
        try await waitForCondition {
            store.accountRows.first { $0.id == alice.accountID }?.requiresRelog == true
        }

        let validatedAccountIDs = await validation.snapshotValidatedAccountIDs()
        expectNoDifference(
            Set(validatedAccountIDs),
            Set([alice.accountID, bob.accountID])
        )
        let aliceRow = try #require(store.accountRows.first { $0.id == alice.accountID })
        #expect(aliceRow.requiresRelog)
        #expect(aliceRow.isSelected == false)
        #expect(aliceRow.subtitle == "Sign in again")
        let bobRow = try #require(store.accountRows.first { $0.id == bob.accountID })
        #expect(bobRow.requiresRelog == false)
    }

    @Test
    func accountRowValidationPersistsRefreshedSessionWithoutChangingSelection() async throws {
        let keychainStorage = InMemoryKeychainStorage()
        let sessionStoreItem = KeychainStorageItem(
            service: "fm.woody.openMusicEvent.tests",
            account: "account.validation.sessionStore"
        )
        let alice = try accountTestSession(did: "did:plc:alice123", pdsHost: "alice.pds.example")
        let bob = try accountTestSession(did: "did:plc:bob123", pdsHost: "bob.pds.example")
        var refreshedBob = bob
        refreshedBob.accessToken = OAuth.AccessToken(rawValue: "bob-refreshed-access-token")
        refreshedBob.refreshToken = OAuth.RefreshToken(rawValue: "bob-refreshed-refresh-token")
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(alice)
        sessionStoreValue.upsert(bob, select: false)
        let sessionStore = Shared(
            wrappedValue: sessionStoreValue,
            KeychainSharedKey(item: sessionStoreItem)
        )
        let validation = AccountSessionValidationRecorder(
            results: [
                alice.accountID: .accepted(alice),
                bob.accountID: .accepted(refreshedBob),
            ]
        )
        let store = withDependencies {
            $0.keychainStorage = .inMemory(keychainStorage)
            $0.openMusicEventAccountSessionValidationClient = .recording(validation)
        } operation: {
            Store(
                initialState: Account.State.localTestState(
                    sessionStore: sessionStore,
                    selectedSessionID: Shared(value: alice.accountID as Atmosphere.Account.ID?)
                )
            ) {
                Account()
            }
        }

        let task = store.send(.accountSessionsChanged)
        await task?.value
        try await waitForCondition {
            store.sessionStore[bob.accountID]?.accessToken == refreshedBob.accessToken
        }

        #expect(store.selectedSessionID == alice.accountID)
        #expect(store.session == alice)
        #expect(store.sessionStore[bob.accountID] == refreshedBob)
        try await waitForCondition {
            keychainStorage.data(for: sessionStoreItem) != nil
        }
        let savedSessionStore = try JSONDecoder().decode(
            OAuth.SessionStore.self,
            from: try #require(keychainStorage.data(for: sessionStoreItem))
        )
        #expect(savedSessionStore[bob.accountID] == refreshedBob)
    }

    @Test
    func accountRowValidationLeavesNonAuthFailuresSelectable() async throws {
        let alice = try accountTestSession(did: "did:plc:alice123", pdsHost: "alice.pds.example")
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(alice)
        let validation = AccountSessionValidationRecorder(
            results: [alice.accountID: .unverified]
        )
        let store = withDependencies {
            $0.openMusicEventAccountSessionValidationClient = .recording(validation)
        } operation: {
            Store(
                initialState: Account.State.localTestState(
                    sessionStore: Shared(value: sessionStoreValue),
                    selectedSessionID: Shared(value: nil)
                )
            ) {
                Account()
            }
        }

        let validationTask = store.send(.accountSessionsChanged)
        await validationTask?.value
        try await waitForCondition {
            store.accountRows.first?.sessionValidationStatus == .unverified
        }
        let row = try #require(store.accountRows.first)
        #expect(row.requiresRelog == false)
        #expect(row.subtitle == "Hosted by alice.pds.example")

        let selectionTask = store.send(.accountRowTapped(alice.accountID))
        await selectionTask?.value

        #expect(store.selectedSessionID == alice.accountID)
        #expect(store.session == alice)
    }

    @Test
    func tappingRelogAccountRowPresentsSignInWithoutSelectingStaleSession() async throws {
        let database = try makeAccountTestDatabase()
        let alice = try accountTestSession(did: "did:plc:alice123", pdsHost: "alice.pds.example")
        let bob = try accountTestSession(did: "did:plc:bob123", pdsHost: "bob.pds.example")
        try await seedAccountTestIdentity(
            in: database,
            did: "did:plc:alice123",
            handle: "alice.example.com",
            displayName: "Alice Example"
        )
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(bob)
        sessionStoreValue.upsert(alice, select: false)
        let state = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            Account.State.localTestState(
                sessionStore: Shared(value: sessionStoreValue),
                selectedSessionID: Shared(value: bob.accountID as Atmosphere.Account.ID?)
            )
        }
        let validation = AccountSessionValidationRecorder(
            results: [
                alice.accountID: .requiresRelog,
                bob.accountID: .accepted(bob),
            ]
        )
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
            $0.openMusicEventAccountSessionValidationClient = .recording(validation)
        } operation: {
            Store(initialState: state) {
                Account()
            }
        }
        try await waitForCondition {
            store.accountSessionValidationStatuses[alice.accountID] == .requiresRelog
        }

        let task = store.send(.accountRowTapped(alice.accountID))
        await task?.value

        #expect(store.selectedSessionID == bob.accountID)
        #expect(store.session == bob)
        #expect(store.presentation == .authentication(.direct))
        #expect(store.selectedMode == .signIn)
        #expect(store.signInLoginHint == "alice.example.com")
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
    func signInFormLaunchesSharedAuthorizationWithLoginHint() async throws {
        let authorizationRequests = AccountAuthorizationRecorder()
        let hydratedActors = AccountObservationRecorder<String>()
        let state = Account.State.localTestState(
            presentation: .authentication(.direct),
            signInLoginHint: "  woody.fm  "
        )
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.openMusicEventAuthorizationRequests = .recording(
                authorizationRequests,
                sessionStore: state.oauth.state.$sessionStore
            )
            $0.blueskyActorProfileCache = .recordingHydrations(hydratedActors)
        } operation: {
            Store(initialState: state) {
                Account()
            }
        }

        let task = store.send(.submitAuthenticationFormButtonTapped)
        await task?.value
        try await waitForCondition {
            store.session == .placeholder
                && store.presentation == nil
                && !store.isLoginInProgress
        }

        #expect(
            await authorizationRequests.loginRequests == [
                AccountAuthorizationRecorder.LoginRequest(
                    requirement: OpenMusicEventOAuth.baseAuthRequirement,
                    loginHint: "woody.fm"
                )
            ]
        )
        #expect(store.session == .placeholder)
        #expect(store.presentation == nil)
        #expect(store.isLoginInProgress == false)
        #expect(store.errorMessage == nil)
        let hydratedActorValues = await hydratedActors.values
        expectNoDifference(
            hydratedActorValues,
            [OAuth.Session.placeholder.accountID.rawValue.description]
        )
    }

    @Test
    func signInFormAddsSecondAccountAndSelectsIt() async throws {
        let alice = try accountTestSession(did: "did:plc:alice123", pdsHost: "alice.pds.example")
        let bob = try accountTestSession(did: "did:plc:bob123", pdsHost: "bob.pds.example")
        var sessionStoreValue = OAuth.SessionStore()
        sessionStoreValue.upsert(alice)
        let sessionStore = Shared(value: sessionStoreValue)
        let authorizationRequests = AccountAuthorizationRecorder(
            signInContinuation: .suspended
        )
        let state = Account.State.localTestState(
            presentation: .authentication(.accountManagement),
            signInLoginHint: "bob.example.com",
            sessionStore: sessionStore,
            selectedSessionID: Shared(value: alice.accountID as Atmosphere.Account.ID?)
        )
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.openMusicEventAuthorizationRequests = .recording(
                authorizationRequests,
                sessionStore: sessionStore
            )
        } operation: {
            Store(initialState: state) {
                Account()
            }
        }

        let task = store.send(.submitAuthenticationFormButtonTapped)
        try await waitForCondition {
            store.isLoginInProgress
        }
        #expect(
            await authorizationRequests.loginRequests == [
                AccountAuthorizationRecorder.LoginRequest(
                    requirement: OpenMusicEventOAuth.baseAuthRequirement,
                    loginHint: "bob.example.com"
                )
            ]
        )

        await authorizationRequests.resumeSignIn(returning: bob)
        await task?.value
        try await waitForCondition {
            store.session == bob
        }

        #expect(store.sessionStore[alice.accountID] == alice)
        #expect(store.sessionStore[bob.accountID] == bob)
        #expect(store.selectedSessionID == bob.accountID)
        #expect(store.presentation == .accountManagement)
    }

    @Test
    func signInFormKeepsSheetPresentedWhileAuthorizationIsInFlight() async throws {
        let authorizationRequests = AccountAuthorizationRecorder(
            signInContinuation: .suspended
        )
        let state = Account.State.localTestState(
            presentation: .authentication(.direct),
            signInLoginHint: "woody.fm"
        )
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.openMusicEventAuthorizationRequests = .recording(
                authorizationRequests,
                sessionStore: state.oauth.state.$sessionStore
            )
        } operation: {
            Store(initialState: state) {
                Account()
            }
        }

        let task = store.send(.submitAuthenticationFormButtonTapped)
        try await waitForCondition {
            store.isLoginInProgress
        }

        #expect(store.presentation == .authentication(.direct))
        #expect(store.isLoginInProgress)
        #expect(store.errorMessage == nil)

        await authorizationRequests.resumeSignIn(returning: .placeholder)
        await task?.value
        try await waitForCondition {
            store.session == .placeholder
                && store.presentation == nil
                && !store.isLoginInProgress
        }

        #expect(store.presentation == nil)
        #expect(store.isLoginInProgress == false)
        #expect(store.session == .placeholder)
    }

    @Test
    func signInCancellationClearsProgressWithoutError() async throws {
        let authorizationRequests = AccountAuthorizationRecorder(
            signInContinuation: .suspended
        )
        let state = Account.State.localTestState(
            presentation: .authentication(.direct),
            signInLoginHint: "woody.fm"
        )
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.openMusicEventAuthorizationRequests = .recording(
                authorizationRequests,
                sessionStore: state.oauth.state.$sessionStore
            )
        } operation: {
            Store(initialState: state) {
                Account()
            }
        }

        let task = store.send(.submitAuthenticationFormButtonTapped)
        try await waitForCondition {
            store.isLoginInProgress
        }
        await authorizationRequests.resumeSignIn(throwing: CancellationError())
        await task?.value
        try await waitForCondition {
            !store.isLoginInProgress
        }

        #expect(store.presentation == .authentication(.direct))
        #expect(store.isLoginInProgress == false)
        #expect(store.errorMessage == nil)
        #expect(store.session == nil)
    }

    @Test
    func signUpFormLaunchesSharedAuthorizationWithSelectedServer() async throws {
        let authorizationRequests = AccountAuthorizationRecorder()
        let hydratedActors = AccountObservationRecorder<String>()
        let state = Account.State.localTestState(
            presentation: .authentication(.direct),
            selectedMode: .signUp
        )
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.openMusicEventAuthorizationRequests = .recording(
                authorizationRequests,
                sessionStore: state.oauth.state.$sessionStore
            )
            $0.blueskyActorProfileCache = .recordingHydrations(hydratedActors)
        } operation: {
            Store(initialState: state) {
                Account()
            }
        }

        let task = store.send(.submitAuthenticationFormButtonTapped)
        await task?.value
        try await waitForCondition {
            store.session == .placeholder
                && store.presentation == nil
                && !store.isSignUpInProgress
        }

        #expect(
            await authorizationRequests.signUpRequests == [
                AccountAuthorizationRecorder.SignUpRequest(
                    requirement: OpenMusicEventOAuth.baseAuthRequirement,
                    serverHost: state.signUpServerConfiguration.defaultServerHost
                )
            ]
        )
        #expect(store.session == .placeholder)
        #expect(store.presentation == nil)
        #expect(store.isSignUpInProgress == false)
        #expect(store.errorMessage == nil)
        let hydratedActorValues = await hydratedActors.values
        expectNoDifference(
            hydratedActorValues,
            [OAuth.Session.placeholder.accountID.rawValue.description]
        )
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
        let authorizationRequests = AccountAuthorizationRecorder()
        let state = Account.State.localTestState(
            selectedMode: .signUp,
            sessionStore: sessionStore,
            selectedSessionID: selectedSessionID
        )
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.keychainStorage = .inMemory(keychainStorage)
            $0.openMusicEventAuthorizationRequests = .recording(
                authorizationRequests,
                sessionStore: sessionStore
            )
        } operation: {
            Store(initialState: state) {
                Account()
            }
        }

        let task = store.send(.submitAuthenticationFormButtonTapped)
        await task?.value
        try await waitForCondition {
            store.session == .placeholder && !store.isSignUpInProgress
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
        let authorizationRequests = AccountAuthorizationRecorder(
            signUpContinuation: .suspended
        )
        let state = Account.State.localTestState(
            presentation: .authentication(.direct),
            selectedMode: .signUp
        )
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.openMusicEventAuthorizationRequests = .recording(
                authorizationRequests,
                sessionStore: state.oauth.state.$sessionStore
            )
        } operation: {
            Store(initialState: state) {
                Account()
            }
        }

        let task = store.send(.submitAuthenticationFormButtonTapped)
        try await waitForCondition {
            store.isSignUpInProgress
        }
        await authorizationRequests.resumeSignUp(throwing: CancellationError())
        await task?.value
        try await waitForCondition {
            !store.isSignUpInProgress
        }

        #expect(store.presentation == .authentication(.direct))
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
            $0.openMusicEventAuthorizationRequests = .recording(
                recorder,
                sessionStore: state.oauth.state.$sessionStore
            )
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
    func accountManagementLogOutReturnsToAuthenticationSurfaceInSamePresentation() async {
        let recorder = AccountAuthorizationRecorder()
        let state = Account.State.localTestState(presentation: .accountManagement)
        state.oauth.state.$sessionStore.withLock { $0.upsert(.placeholder) }
        state.$selectedSessionID.withLock {
            $0 = OAuth.Session.placeholder.accountID
        }
        let store = withDependencies {
            $0.openMusicEventAuthorizationRequests = .recording(
                recorder,
                sessionStore: state.oauth.state.$sessionStore
            )
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
        #expect(store.presentation == .accountManagement)
        #expect(await recorder.didCancel)
    }
}

private actor AccountObservationRecorder<Value: Sendable> {
    var values: [Value] = []

    func record(_ value: Value) {
        values.append(value)
    }
}

private extension BlueskyActorProfileCacheClient {
    static func recordingHydrations(
        _ recorder: AccountObservationRecorder<String>
    ) -> Self {
        Self(
            cachedProfile: { _ in nil },
            refreshProfile: { actor in
                await recorder.record(actor)
                return BlueskyActorProfile(
                    did: actor,
                    handle: "hydrated.example"
                )
            },
            refreshProfileIfNeeded: { _, _, _ in nil }
        )
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
        presentation: Account.Presentation? = nil,
        selectedMode: Account.Mode = .signIn,
        signInLoginHint: String = "",
        signUpServerConfiguration: OAuthSignUpServerConfiguration? = nil,
        authFailureMessage: Shared<ErrorMessage?> = Shared(value: nil),
        sessionStore: Shared<OAuth.SessionStore> = Shared(value: OAuth.SessionStore()),
        selectedSessionID: Shared<Atmosphere.Account.ID?> = Shared(value: nil),
        recentlyUsedAccountIDs: Shared<[Atmosphere.Account.ID]> = Shared(value: [])
    ) -> Self {
        Self(
            presentation: presentation,
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

private func makeAccountTestDatabase() throws -> any DatabaseWriter {
    let database = try SQLiteData.defaultDatabase()
    var migrator = DatabaseMigrator()
    BlueskyActorCacheMigrations.register(into: &migrator)
    try migrator.migrate(database)
    return database
}

private func seedAccountTestIdentity(
    in database: any DatabaseWriter,
    did: String,
    handle: String,
    displayName: String? = nil,
    avatar: URL? = nil,
    fetchedAt: Date? = nil
) async throws {
    try await database.write { db in
        try BlueskyActorProfile.insert {
            BlueskyActorProfile(
                did: did,
                handle: handle,
                displayName: displayName,
                avatar: avatar
            )
        }
        .execute(db)
        try BlueskyActorProfileCacheEntry.insert {
            BlueskyActorProfileCacheEntry(
                actor: did,
                did: did,
                lastFetchedAt: fetchedAt,
                lastFetchAttemptAt: fetchedAt
            )
        }
        .execute(db)
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
    enum AuthorizationContinuation {
        case immediate
        case suspended
    }

    struct LoginRequest: Equatable {
        var requirement: OAuth.AuthRequirement
        var loginHint: String
    }

    struct SignUpRequest: Equatable {
        var requirement: OAuth.AuthRequirement
        var serverHost: String
    }

    private(set) var didCancel = false
    private(set) var loginRequests: [LoginRequest] = []
    private(set) var requirements: [OAuth.AuthRequirement] = []
    private(set) var signUpRequests: [SignUpRequest] = []
    private let signInContinuationMode: AuthorizationContinuation
    private let signUpContinuationMode: AuthorizationContinuation
    private var pendingSignInResume: Result<OAuth.Session, any Error>?
    private var pendingSignUpResume: Result<OAuth.Session, any Error>?
    private var signInContinuation: CheckedContinuation<OAuth.Session, any Error>?
    private var signUpContinuation: CheckedContinuation<OAuth.Session, any Error>?

    init(
        signInContinuation: AuthorizationContinuation = .immediate,
        signUpContinuation: AuthorizationContinuation = .immediate
    ) {
        self.signInContinuationMode = signInContinuation
        self.signUpContinuationMode = signUpContinuation
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
    ) async throws -> OAuth.Session {
        loginRequests.append(
            LoginRequest(
                requirement: requirement,
                loginHint: loginHint
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

private actor AccountSessionValidationRecorder {
    private let results: [Atmosphere.Account.ID: OpenMusicEventAccountSessionValidationClient.ValidationResult]
    private var validatedAccountIDs: [Atmosphere.Account.ID] = []

    init(
        results: [Atmosphere.Account.ID: OpenMusicEventAccountSessionValidationClient.ValidationResult]
    ) {
        self.results = results
    }

    func validate(
        _ session: OAuth.Session
    ) -> OpenMusicEventAccountSessionValidationClient.ValidationResult {
        validatedAccountIDs.append(session.accountID)
        return results[session.accountID] ?? .accepted(session)
    }

    func snapshotValidatedAccountIDs() -> [Atmosphere.Account.ID] {
        validatedAccountIDs
    }
}

private extension OpenMusicEventAuthorizationRequests {
    static func recording(
        _ recorder: AccountAuthorizationRecorder,
        sessionStore: Shared<OAuth.SessionStore>
    ) -> Self {
        Self(
            authorizeWithLoginHint: { requirement, loginHint in
                let session = try await recorder.recordLogin(
                    requirement,
                    loginHint: loginHint
                )
                sessionStore.withLock { $0.upsert(session) }
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
                let session = try await recorder.recordSignUp(
                    requirement,
                    serverHost: serverHost
                )
                sessionStore.withLock { $0.upsert(session) }
            },
            signUpWithConfiguration: { requirement, configuration in
                let session = try await recorder.recordSignUp(
                    requirement,
                    serverHost: configuration.defaultServerHost
                )
                sessionStore.withLock { $0.upsert(session) }
            },
            succeed: {},
            fail: { _ in },
            cancel: {
                await recorder.recordCancel()
            }
        )
    }
}

private extension OpenMusicEventAccountSessionValidationClient {
    static func recording(_ recorder: AccountSessionValidationRecorder) -> Self {
        Self { session in
            await recorder.validate(session)
        }
    }
}
