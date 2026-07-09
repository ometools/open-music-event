import ATProto
import CustomDump
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import SQLiteData
import Testing
import XRPCClient

@testable import BlueskyActorCache

struct BlueskyActorCacheTests {
    @Test
    func getProfileRequestBuildsPublicAppViewQuery() async throws {
        let request = BlueskyActorGetProfileRequest(actor: "Alice.BSKY.SOCIAL")

        expectNoDifference(
            try request.queryItems,
            [
                URLQueryItem(name: "actor", value: "alice.bsky.social")
            ]
        )
        expectNoDifference(
            request.routing,
            XRPC.Routing(
                unauthenticated: .host("public.api.bsky.app"),
                authenticated: .serviceProxy("did:web:api.bsky.app#bsky_appview")
            )
        )
        #expect(BlueskyActorGetProfileRequest.nsid.rawValue == "app.bsky.actor.getProfile")

        let database = try makePreparedDatabase()
        let requestRecorder = HTTPRequestRecorder()
        _ = try await withDependencies {
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 1_000)
            $0.blueskyActorProfileCache = .live
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { request, body in
                await requestRecorder.record(request, body)
                return Data(
                    """
                    {
                      "did": "did:plc:alice123",
                      "handle": "alice.bsky.social"
                    }
                    """
                    .utf8
                )
            }
        } operation: {
            @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
            return try await blueskyActorProfileCache.refreshProfile("Alice.BSKY.SOCIAL")
        }

        let requests = await requestRecorder.requests
        #expect(requests.count == 1)
        #expect(
            requests.first?.url?.absoluteString
                == "https://public.api.bsky.app/xrpc/app.bsky.actor.getProfile?actor=alice.bsky.social"
        )
        #expect(requests.first?.body == nil)
    }

    @Test
    func profileDecodesDisplayFields() throws {
        let profile = try JSONDecoder().decode(
            BlueskyActorProfile.self,
            from: Data(
                """
                {
                  "did": "did:plc:alice123",
                  "handle": "alice.bsky.social",
                  "displayName": "Alice Example",
                  "description": "ATProto builder",
                  "avatar": "https://cdn.example/alice-avatar.jpg",
                  "banner": "https://cdn.example/alice-banner.jpg",
                  "followersCount": 123,
                  "followsCount": 45,
                  "postsCount": 67
                }
                """
                .utf8
            )
        )

        expectNoDifference(
            profile,
            BlueskyActorProfile(
                did: "did:plc:alice123",
                handle: "alice.bsky.social",
                displayName: "Alice Example",
                description: "ATProto builder",
                avatar: URL(string: "https://cdn.example/alice-avatar.jpg"),
                banner: URL(string: "https://cdn.example/alice-banner.jpg"),
                followersCount: 123,
                followsCount: 45,
                postsCount: 67
            )
        )
    }

    @Test
    func refreshProfileUpsertsProfileAndActorCacheEntry() async throws {
        let database = try makePreparedDatabase()
        let fetchedAt = Date(timeIntervalSince1970: 1_000)

        let profile = try await withDependencies {
            $0.defaultDatabase = database
            $0.date.now = fetchedAt
            $0.blueskyActorProfileCache = .live
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { _, _ in
                Data(
                    """
                    {
                      "did": "did:plc:alice123",
                      "handle": "alice.bsky.social",
                      "displayName": "Alice Example"
                    }
                    """
                    .utf8
                )
            }
        } operation: {
            @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
            return try await blueskyActorProfileCache.refreshProfile("Alice.BSKY.SOCIAL")
        }

        #expect(profile.did == "did:plc:alice123")

        let cached = try await database.read { db in
            try BlueskyActorProfile
                .where { $0.did.eq("did:plc:alice123") }
                .fetchOne(db)
        }
        let entry = try await database.read { db in
            try BlueskyActorProfileCacheEntry
                .where { $0.actor.eq("alice.bsky.social") }
                .fetchOne(db)
        }
        #expect(cached?.displayName == "Alice Example")
        #expect(entry?.did == "did:plc:alice123")
        #expect(entry?.lastFetchedAt == fetchedAt)
        #expect(entry?.lastFetchAttemptAt == fetchedAt)
    }

    @Test
    func freshCacheDoesNotRefresh() async throws {
        let database = try makePreparedDatabase()
        let now = Date(timeIntervalSince1970: 1_000)
        try await database.write { db in
            try BlueskyActorProfile.insert {
                BlueskyActorProfile(
                    did: "did:plc:alice123",
                    handle: "alice.bsky.social",
                    displayName: "Cached Alice"
                )
            }
            .execute(db)
            try BlueskyActorProfileCacheEntry.insert {
                BlueskyActorProfileCacheEntry(
                    actor: "alice.bsky.social",
                    did: "did:plc:alice123",
                    lastFetchedAt: now.addingTimeInterval(-60),
                    lastFetchAttemptAt: now.addingTimeInterval(-60)
                )
            }
            .execute(db)
        }

        let requestRecorder = HTTPRequestRecorder()
        let refreshed = try await withDependencies {
            $0.defaultDatabase = database
            $0.date.now = now
            $0.blueskyActorProfileCache = .live
            $0[XRPC.Client.self] = .liveValue
            $0.httpClient = HTTPClient { request, body in
                await requestRecorder.record(request, body)
                return Data()
            }
        } operation: {
            @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
            return try await blueskyActorProfileCache.refreshProfileIfNeeded(
                "alice.bsky.social",
                24 * 60 * 60,
                15 * 60
            )
        }

        #expect(refreshed == nil)
        #expect(await requestRecorder.requests.isEmpty)
    }

    @Test
    func cacheBackedActorIdentityLookupUsesProfileCache() async throws {
        let profile = BlueskyActorProfile(
            did: "did:plc:alice123",
            handle: "alice.example.com",
            displayName: "Alice Example",
            avatar: URL(string: "https://cdn.example/alice.jpg")
        )
        let lookup = ActorIdentityLookupClient.blueskyActorProfileCacheBacked()

        let identity = try await withDependencies {
            $0.blueskyActorProfileCache = BlueskyActorProfileCacheClient(
                cachedProfile: { actor in
                    #expect(actor == "did:plc:alice123")
                    return profile
                },
                refreshProfile: { _ in
                    Issue.record("Cached profile lookup should not force a refresh.")
                    return profile
                },
                refreshProfileIfNeeded: { actor, _, _ in
                    #expect(actor == "did:plc:alice123")
                    return nil
                }
            )
        } operation: {
            try await lookup.resolve("did:plc:alice123")
        }

        expectNoDifference(
            identity,
            ActorIdentity(
                did: DID("did:plc:alice123")!,
                handle: Atmosphere.Account.Handle(rawValue: "alice.example.com"),
                displayName: "Alice Example",
                avatar: URL(string: "https://cdn.example/alice.jpg"),
                source: .canonicalResolution
            )
        )
    }

    @Test
    func cacheBackedActorIdentityLookupFallsBackWhenCacheMisses() async throws {
        var fallback = ActorIdentityLookupClient()
        fallback.resolve = { input in
            #expect(input == "did:plc:bob123")
            return ActorIdentity(
                did: DID("did:plc:bob123")!,
                handle: Atmosphere.Account.Handle(rawValue: "bob.example.com"),
                source: .canonicalResolution
            )
        }
        let lookup = ActorIdentityLookupClient.blueskyActorProfileCacheBacked(
            fallback: fallback
        )

        let identity = try await withDependencies {
            $0.blueskyActorProfileCache = BlueskyActorProfileCacheClient(
                cachedProfile: { _ in nil },
                refreshProfile: { _ in
                    Issue.record("Cache miss lookup should use refreshProfileIfNeeded.")
                    throw CacheBackedActorIdentityLookupTestError.unexpectedRefresh
                },
                refreshProfileIfNeeded: { _, _, _ in nil }
            )
        } operation: {
            try await lookup.resolve("did:plc:bob123")
        }

        #expect(identity.handle?.rawValue == "bob.example.com")
    }
}

private enum CacheBackedActorIdentityLookupTestError: Error {
    case unexpectedRefresh
}

private func makePreparedDatabase() throws -> any DatabaseWriter {
    let database = try SQLiteData.defaultDatabase()
    var migrator = DatabaseMigrator()
    BlueskyActorCacheMigrations.register(into: &migrator)
    try migrator.migrate(database)
    return database
}

private actor HTTPRequestRecorder {
    struct Request: Sendable {
        var url: URL?
        var body: Data?
    }

    private var recordedRequests: [Request] = []

    var requests: [Request] {
        recordedRequests
    }

    func record(_ request: HTTPRequest, _ body: Data?) {
        recordedRequests.append(
            Request(
                url: request.url,
                body: body
            )
        )
    }
}
