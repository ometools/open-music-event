import ATProto
import ATProtoOAuth
import Dependencies
import DependenciesTestSupport
import Foundation
import HTTPClient
import HTTPTypes
import Sharing
import TCATProtoAuthentication
import Testing

@Suite(.dependencies {
    $0.httpClient = .liveValue
    $0.formEncoder = FormURLEncoder()
    $0[OAuth.Client.self] = .liveValue
    $0.requestInterceptors = []
    $0.errorInterceptors = []
    $0.uuid = .constant(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
    $0.p256Sign = { try $1.signature(for: $0).rawRepresentation }
})
struct StoredAccountRequestTests {
    @Test
    func removedAccountDoesNotSendARequest() async throws {
        let alice = account("alice")
        let storage = storage(alice)
        storage.sessionStore.withLock { $0.sessions[alice.accountID.rawValue] = nil }
        await #expect(throws: OAuth.TerminalAuthenticatedSessionFailure.self) {
            try await withDependencies {
                $0.dataForURL = { _, _ in
                    Issue.record("Removed accounts must not send HTTP requests")
                    throw CancellationError()
                }
            } operation: {
                _ = try await read(storage, alice.accountID)
            }
        }
    }

    @Test(arguments: [false, true])
    func refreshFailureRetainsTheAccountForRetryOrSignIn(terminal: Bool) async throws {
        let alice = account("alice")
        let storage = storage(alice)
        do {
            _ = try await withDependencies {
                $0.dataForURL = { request, _ in
                    guard request.path == "/oauth/token" else { return expired() }
                    if terminal {
                        return (Data(#"{"error":"invalid_grant"}"#.utf8), HTTPResponse(status: .badRequest))
                    }
                    throw URLError(.notConnectedToInternet)
                }
            } operation: {
                try await read(storage, alice.accountID)
            }
            Issue.record("The failed refresh must fail the request")
        } catch {
            #expect(isTerminalAuthenticatedSessionFailure(error) == terminal)
        }
        #expect(storage.sessionStore.wrappedValue.sessions[alice.accountID.rawValue] == alice)
    }

    @Test
    func concurrentRequestsRotateOnceAndPersistBeforeReturning() async throws {
        let alice = account("alice")
        let keychain = InMemoryKeychainStorage()
        let item = KeychainStorageItem(service: "test.stored-account", account: UUID().uuidString)
        let sessions = withDependencies {
            $0.keychainStorage = .inMemory(keychain)
        } operation: {
            Shared(wrappedValue: OAuth.SessionStore(selectedAccountID: alice.accountID,
                sessions: [alice.accountID.rawValue: alice]), KeychainSharedKey(item: item))
        }
        let storage = OAuthSessionStorage(sessionStore: sessions, authFailureMessage: Shared(value: nil))
        let transport = RefreshTransport(account: alice, minimumExpiredRequests: 2)
        try await withDependencies {
            $0.dataForURL = { request, body in try await transport.respond(request, body) }
        } operation: {
            async let first = read(storage, alice.accountID)
            async let second = read(storage, alice.accountID)
            _ = try await (first, second)
        }
        #expect(await transport.refreshCount == 1)
        let saved = try JSONDecoder().decode(OAuth.SessionStore.self,
            from: #require(keychain.data(for: item)))
        #expect(saved.sessions[alice.accountID.rawValue]?.refreshToken?.rawValue == "fixture-refresh-next")
        #expect(sessions.wrappedValue.selectedAccountID == alice.accountID)
    }

    @Test
    func lateUnauthorizedResponseUsesAlreadyRotatedCredentials() async throws {
        let alice = account("alice")
        let storage = storage(alice)
        let heldRequest = RequestGate()
        let releaseRequest = RequestGate()
        let transport = RefreshTransport(account: alice)
        try await withDependencies {
            $0.dataForURL = { request, body in
                if request.path == "/held" && request.headerFields[.authorization] == "DPoP fixture-access-alice" {
                    await heldRequest.open()
                    await releaseRequest.wait()
                    return expired()
                }
                return try await transport.respond(request, body)
            }
        } operation: {
            let late = Task { try await read(storage, alice.accountID, path: "/held") }
            await heldRequest.wait()
            _ = try await read(storage, alice.accountID)
            await releaseRequest.open()
            _ = try await late.value
        }
        #expect(await transport.refreshCount == 1)
    }

    @Test(arguments: [false, true])
    func logoutOrNewAuthorizationCannotBeOverwrittenByPendingRefresh(replace: Bool) async throws {
        let alice = account("alice")
        let storage = storage(alice)
        let started = RequestGate()
        let release = RequestGate()
        let transport = RefreshTransport(account: alice)
        let replacement = account("alice") // Same account; a fresh authorization has a different DPoP key.
        try await withDependencies {
            $0.dataForURL = { request, body in
                if request.path == "/oauth/token" {
                    await started.open()
                    await release.wait()
                }
                return try await transport.respond(request, body)
            }
        } operation: {
            let request = Task { try await read(storage, alice.accountID) }
            await started.wait()
            storage.sessionStore.withLock { $0.sessions[alice.accountID.rawValue] = replace ? replacement : nil }
            await release.open()
            do {
                _ = try await request.value
                Issue.record("An operation for a removed authorization must be cancelled")
            } catch is CancellationError {} 
        }
        #expect(storage.sessionStore.wrappedValue.sessions[alice.accountID.rawValue] == (replace ? replacement : nil))
    }

    @Test
    func switchingSelectionDoesNotRedirectAnAccountRequest() async throws {
        let alice = account("alice")
        let bob = account("bob")
        let storage = storage(alice)
        storage.sessionStore.withLock { $0.upsert(bob, select: false) }
        let started = RequestGate()
        let release = RequestGate()
        let transport = RefreshTransport(account: alice)
        try await withDependencies {
            $0.dataForURL = { request, body in
                if request.path == "/oauth/token" {
                    await started.open()
                    await release.wait()
                }
                return try await transport.respond(request, body)
            }
        } operation: {
            let request = Task { try await read(storage, alice.accountID) }
            await started.wait()
            storage.sessionStore.withLock { $0.selectedAccountID = bob.accountID }
            await release.open()
            _ = try await request.value
        }
        #expect(storage.sessionStore.wrappedValue.selectedAccountID == bob.accountID)
        #expect(storage.sessionStore.wrappedValue.sessions[bob.accountID.rawValue] == bob)
        #expect(storage.sessionStore.wrappedValue.sessions[alice.accountID.rawValue]?.refreshToken?.rawValue == "fixture-refresh-next")
    }
}

private func account(_ name: String) -> OAuth.Session {
    OAuth.Session(accountID: .init(DID("did:plc:\(name)")!), pdsHost: "pds.example.test",
        tokenEndpoint: .init(URL(string: "https://pds.example.test/oauth/token")!), scope: "atproto",
        accessToken: .init(rawValue: "fixture-access-\(name)"),
        refreshToken: .init(rawValue: "fixture-refresh-\(name)"), dpopKey: .init())
}
private func storage(_ session: OAuth.Session) -> OAuthSessionStorage {
    OAuthSessionStorage(sessionStore: Shared(value: OAuth.SessionStore(
        selectedAccountID: session.accountID, sessions: [session.accountID.rawValue: session])),
        authFailureMessage: Shared(value: nil))
}
private func read(_ storage: OAuthSessionStorage, _ id: Atmosphere.Account.ID, path: String = "/resource") async throws -> Data {
    try await storage.withAccount(id) {
        try await withDefaultSessionAuthentication {
            @Dependency(\.httpClient) var http
            return try await http.get(URL(string: "https://pds.example.test" + path)!, decodingTo: Data.self)
        }
    }
}
private func expired() -> (Data, HTTPResponse) {
    (Data(#"{"error":"invalid_token"}"#.utf8), HTTPResponse(status: .unauthorized))
}
private actor RequestGate {
    var isOpen = false
    var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
private actor RefreshTransport {
    let account: OAuth.Session
    var refreshCount = 0
    var expiredCount = 0
    let minimumExpiredRequests: Int
    let expiredRequests = RequestGate()
    init(account: OAuth.Session, minimumExpiredRequests: Int = 1) {
        self.account = account
        self.minimumExpiredRequests = minimumExpiredRequests
    }
    func respond(_ request: HTTPRequest, _ body: Data?) async throws -> (Data, HTTPResponse) {
        #expect(request.headerFields[HTTPField.Name("DPoP")!] != nil)
        if request.path == "/oauth/token" {
            refreshCount += 1
            #expect(String(data: body ?? Data(), encoding: .utf8)?.contains("grant_type=refresh_token") == true)
            let data = try JSONSerialization.data(withJSONObject: [
                "sub": account.accountID.rawValue.description, "access_token": "fixture-access-next",
                "refresh_token": "fixture-refresh-next", "scope": "atproto", "token_type": "DPoP", "expires_in": 60
            ])
            return (data, HTTPResponse(status: .ok))
        }
        if request.headerFields[.authorization] != "DPoP fixture-access-next" {
            expiredCount += 1
            if expiredCount >= minimumExpiredRequests { await expiredRequests.open() }
            await expiredRequests.wait()
            return expired()
        }
        return (Data("verified".utf8), HTTPResponse(status: .ok))
    }
}
