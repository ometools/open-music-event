import ATProto
import Dependencies
import Foundation
import SQLiteData
import XRPCClient

private let blueskyAppViewAudience = "did:web:api.bsky.app#bsky_appview"

private extension XRPC.AuthorizationPolicy {
    static func blueskyActorCacheOptionalAppViewRPC(_ nsid: ATProto.NSID) -> Self {
        .optional(
            ATProto.OAuth.AuthRequirement(
                permissions: [.rpc(nsid, audience: blueskyAppViewAudience)]
            )
        )
    }
}

private extension XRPC.Routing {
    static let blueskyActorCacheAppViewRead = XRPC.Routing(
        unauthenticated: .host("public.api.bsky.app"),
        authenticated: .serviceProxy(blueskyAppViewAudience)
    )
}

@Table("blueskyActorProfiles")
public struct BlueskyActorProfile: Codable, Equatable, Sendable, Identifiable {
    @Column(primaryKey: true) public var did: String
    public var handle: String
    public var displayName: String?
    public var description: String?
    public var avatar: URL?
    public var banner: URL?
    public var followersCount: Int?
    public var followsCount: Int?
    public var postsCount: Int?

    public init(
        did: String,
        handle: String,
        displayName: String? = nil,
        description: String? = nil,
        avatar: URL? = nil,
        banner: URL? = nil,
        followersCount: Int? = nil,
        followsCount: Int? = nil,
        postsCount: Int? = nil
    ) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.description = description
        self.avatar = avatar
        self.banner = banner
        self.followersCount = followersCount
        self.followsCount = followsCount
        self.postsCount = postsCount
    }

    public var id: String { did }
    public var didValue: DID? { DID(did) }
}

@Table("blueskyActorProfileCacheEntries")
public struct BlueskyActorProfileCacheEntry: Equatable, Sendable, Identifiable {
    @Column(primaryKey: true) public var actor: String
    public var did: String?
    public var lastFetchedAt: Date?
    public var lastFetchAttemptAt: Date?

    public init(
        actor: String,
        did: String? = nil,
        lastFetchedAt: Date? = nil,
        lastFetchAttemptAt: Date? = nil
    ) {
        self.actor = Self.normalizedActor(actor)
        self.did = did
        self.lastFetchedAt = lastFetchedAt
        self.lastFetchAttemptAt = lastFetchAttemptAt
    }

    public var id: String { actor }

    public static func normalizedActor(_ actor: String) -> String {
        let actor = actor.trimmingCharacters(in: .whitespacesAndNewlines)
        if actor.lowercased().hasPrefix("did:") {
            return actor
        }
        return actor.lowercased()
    }
}

public struct CachedActorIdentities: Equatable, Sendable {
    public init(byActor: [String: ActorIdentity] = [:]) {
        self.byActor = byActor
    }

    public var byActor: [String: ActorIdentity]

    public subscript(actor: String) -> ActorIdentity? {
        byActor[BlueskyActorProfileCacheEntry.normalizedActor(actor)]
    }
}

public struct CachedActorIdentitiesRequest: FetchKeyRequest {
    public init() {}

    public func fetch(_ db: Database) throws -> CachedActorIdentities {
        let profilesByDID = Dictionary(
            uniqueKeysWithValues: try BlueskyActorProfile
                .fetchAll(db)
                .map { ($0.did, $0) }
        )
        let identities = try BlueskyActorProfileCacheEntry
            .fetchAll(db)
            .reduce(into: [String: ActorIdentity]()) { identities, entry in
                guard let did = entry.did,
                      let profile = profilesByDID[did],
                      let identity = ActorIdentity(profile)
                else { return }
                identities[entry.actor] = identity
            }
        return CachedActorIdentities(byActor: identities)
    }
}

public struct BlueskyActorGetProfileRequest: XRPC.Request, Sendable {
    public static var nsid: ATProto.NSID { ATProto.NSID("app.bsky.actor.getProfile") }
    public static var type: XRPC.RequestType { .query }
    public static var authorizationPolicy: XRPC.AuthorizationPolicy {
        .blueskyActorCacheOptionalAppViewRPC(nsid)
    }
    public static var routing: XRPC.Routing { .blueskyActorCacheAppViewRead }

    public typealias Input = Never
    public typealias Output = BlueskyActorProfile

    public struct Parameters: Encodable, Sendable {
        public var actor: String

        public init(actor: String) {
            self.actor = actor
        }
    }

    public var parameters: Parameters

    public init(actor: String) {
        self.parameters = Parameters(
            actor: BlueskyActorProfileCacheEntry.normalizedActor(actor)
        )
    }
}

public enum BlueskyActorCacheMigrations {
    public static func register(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Create Bluesky actor profile cache") { db in
            try #sql("""
                CREATE TABLE IF NOT EXISTS "blueskyActorProfiles" (
                  "did" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "handle" TEXT NOT NULL,
                  "displayName" TEXT,
                  "description" TEXT,
                  "avatar" TEXT,
                  "banner" TEXT,
                  "followersCount" INTEGER,
                  "followsCount" INTEGER,
                  "postsCount" INTEGER
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE TABLE IF NOT EXISTS "blueskyActorProfileCacheEntries" (
                  "actor" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE,
                  "did" TEXT,
                  "lastFetchedAt" TEXT,
                  "lastFetchAttemptAt" TEXT,
                  FOREIGN KEY ("did")
                    REFERENCES "blueskyActorProfiles"("did")
                    ON DELETE SET NULL
                ) STRICT
                """)
                .execute(db)

            try #sql("""
                CREATE INDEX IF NOT EXISTS "blueskyActorProfiles_handle"
                ON "blueskyActorProfiles" ("handle")
                """)
                .execute(db)
        }

        migrator.registerMigration("Backfill Bluesky actor profile aliases") { db in
            try #sql("""
                INSERT INTO "blueskyActorProfileCacheEntries" (
                  "actor",
                  "did",
                  "lastFetchedAt",
                  "lastFetchAttemptAt"
                )
                SELECT
                  "blueskyActorProfiles"."did",
                  "blueskyActorProfiles"."did",
                  MAX("blueskyActorProfileCacheEntries"."lastFetchedAt"),
                  MAX("blueskyActorProfileCacheEntries"."lastFetchAttemptAt")
                FROM "blueskyActorProfiles"
                LEFT JOIN "blueskyActorProfileCacheEntries"
                  ON "blueskyActorProfileCacheEntries"."did" = "blueskyActorProfiles"."did"
                GROUP BY "blueskyActorProfiles"."did"
                ON CONFLICT ("actor") DO UPDATE SET
                  "did" = excluded."did",
                  "lastFetchedAt" = COALESCE(
                    "blueskyActorProfileCacheEntries"."lastFetchedAt",
                    excluded."lastFetchedAt"
                  ),
                  "lastFetchAttemptAt" = COALESCE(
                    "blueskyActorProfileCacheEntries"."lastFetchAttemptAt",
                    excluded."lastFetchAttemptAt"
                  )
                """)
                .execute(db)

            try #sql("""
                INSERT INTO "blueskyActorProfileCacheEntries" (
                  "actor",
                  "did",
                  "lastFetchedAt",
                  "lastFetchAttemptAt"
                )
                SELECT
                  LOWER(TRIM("blueskyActorProfiles"."handle")),
                  "blueskyActorProfiles"."did",
                  MAX("blueskyActorProfileCacheEntries"."lastFetchedAt"),
                  MAX("blueskyActorProfileCacheEntries"."lastFetchAttemptAt")
                FROM "blueskyActorProfiles"
                LEFT JOIN "blueskyActorProfileCacheEntries"
                  ON "blueskyActorProfileCacheEntries"."did" = "blueskyActorProfiles"."did"
                WHERE TRIM("blueskyActorProfiles"."handle") <> ''
                GROUP BY "blueskyActorProfiles"."did", "blueskyActorProfiles"."handle"
                ON CONFLICT ("actor") DO UPDATE SET
                  "did" = excluded."did",
                  "lastFetchedAt" = COALESCE(
                    "blueskyActorProfileCacheEntries"."lastFetchedAt",
                    excluded."lastFetchedAt"
                  ),
                  "lastFetchAttemptAt" = COALESCE(
                    "blueskyActorProfileCacheEntries"."lastFetchAttemptAt",
                    excluded."lastFetchAttemptAt"
                  )
                """)
                .execute(db)
        }
    }
}

public struct BlueskyActorProfileCacheClient: Sendable {
    public var cachedProfile: @Sendable (String) async throws -> BlueskyActorProfile?
    public var refreshProfile: @Sendable (String) async throws -> BlueskyActorProfile
    public var refreshProfileIfNeeded: @Sendable (
        _ actor: String,
        _ staleAfter: TimeInterval,
        _ retryAfter: TimeInterval
    ) async throws -> BlueskyActorProfile?

    public init(
        cachedProfile: @escaping @Sendable (String) async throws -> BlueskyActorProfile?,
        refreshProfile: @escaping @Sendable (String) async throws -> BlueskyActorProfile,
        refreshProfileIfNeeded: @escaping @Sendable (
            _ actor: String,
            _ staleAfter: TimeInterval,
            _ retryAfter: TimeInterval
        ) async throws -> BlueskyActorProfile?
    ) {
        self.cachedProfile = cachedProfile
        self.refreshProfile = refreshProfile
        self.refreshProfileIfNeeded = refreshProfileIfNeeded
    }
}

public enum BlueskyActorProfileCacheClientError: Equatable, Error, Sendable {
    case unimplemented
}

extension BlueskyActorProfileCacheClient {
    public static var live: Self {
        Self(
            cachedProfile: BlueskyActorProfileCacheLive.cachedProfile,
            refreshProfile: BlueskyActorProfileCacheLive.refreshProfile,
            refreshProfileIfNeeded: BlueskyActorProfileCacheLive.refreshProfileIfNeeded
        )
    }
}

extension DependencyValues {
    public var blueskyActorProfileCache: BlueskyActorProfileCacheClient {
        get { self[BlueskyActorProfileCacheClientKey.self] }
        set { self[BlueskyActorProfileCacheClientKey.self] = newValue }
    }
}

public enum BlueskyActorCacheDependencies {
    public static func prepareDependencies(_ dependencies: inout DependencyValues) {
        dependencies.actorIdentityLookup = .blueskyActorProfileCacheBacked()
    }
}

public extension ActorIdentityLookupClient {
    static func blueskyActorProfileCacheBacked(
        fallback: ActorIdentityLookupClient = .liveValue,
        staleAfter: TimeInterval = 60 * 60 * 24,
        retryAfter: TimeInterval = 60 * 15
    ) -> Self {
        Self { input in
            @Dependency(\.blueskyActorProfileCache)
            var blueskyActorProfileCache

            let cachedProfile = try? await blueskyActorProfileCache.cachedProfile(input)
            let refreshedProfile = try? await blueskyActorProfileCache.refreshProfileIfNeeded(
                input,
                staleAfter,
                retryAfter
            )
            if let identity = (refreshedProfile ?? cachedProfile).flatMap(ActorIdentity.init) {
                return identity
            }
            return try await fallback.resolve(input)
        }
    }
}

extension ActorIdentity {
    init?(_ profile: BlueskyActorProfile) {
        guard let did = DID(profile.did) else { return nil }
        self.init(
            did: did,
            handle: Atmosphere.Account.Handle(rawValue: profile.handle),
            displayName: profile.displayName,
            avatar: profile.avatar,
            source: .canonicalResolution
        )
    }
}

private enum BlueskyActorProfileCacheClientKey: DependencyKey {
    static var liveValue: BlueskyActorProfileCacheClient { .live }

    static var testValue: BlueskyActorProfileCacheClient {
        BlueskyActorProfileCacheClient(
            cachedProfile: { _ in
                throw BlueskyActorProfileCacheClientError.unimplemented
            },
            refreshProfile: { _ in
                throw BlueskyActorProfileCacheClientError.unimplemented
            },
            refreshProfileIfNeeded: { _, _, _ in
                throw BlueskyActorProfileCacheClientError.unimplemented
            }
        )
    }
}

private enum BlueskyActorProfileCacheLive {
    static func cachedProfile(actor: String) async throws -> BlueskyActorProfile? {
        @Dependency(\.defaultDatabase) var database
        let actor = BlueskyActorProfileCacheEntry.normalizedActor(actor)
        return try await database.read { db in
            try cachedProfile(actor: actor, in: db)
        }
    }

    static func refreshProfile(actor: String) async throws -> BlueskyActorProfile {
        @Dependency(\.date.now) var now
        @Dependency(\.defaultDatabase) var database
        @Dependency(XRPC.Client.self) var xrpcClient

        let actor = BlueskyActorProfileCacheEntry.normalizedActor(actor)
        try await database.write { db in
            try upsertCacheEntry(
                actor: actor,
                did: try cacheEntry(actor: actor, in: db)?.did,
                lastFetchedAt: try cacheEntry(actor: actor, in: db)?.lastFetchedAt,
                lastFetchAttemptAt: now,
                in: db
            )
        }

        let profile = try await xrpcClient.run(
            BlueskyActorGetProfileRequest(actor: actor)
        )

        try await database.write { db in
            try upsert(profile: profile, in: db)
            try upsertCacheAliases(
                requestedActor: actor,
                profile: profile,
                fetchedAt: now,
                in: db
            )
        }

        return profile
    }

    static func refreshProfileIfNeeded(
        actor: String,
        staleAfter: TimeInterval,
        retryAfter: TimeInterval
    ) async throws -> BlueskyActorProfile? {
        @Dependency(\.date.now) var now
        @Dependency(\.defaultDatabase) var database

        let actor = BlueskyActorProfileCacheEntry.normalizedActor(actor)
        let shouldRefresh = try await database.write { db in
            let entry = try cacheEntry(actor: actor, in: db)
            let hasCachedIdentity = try cachedProfile(actor: actor, in: db)
                .flatMap(ActorIdentity.init) != nil
            if hasCachedIdentity,
               let lastFetchedAt = entry?.lastFetchedAt,
               now.timeIntervalSince(lastFetchedAt) < staleAfter {
                return false
            }
            if let lastFetchAttemptAt = entry?.lastFetchAttemptAt,
               now.timeIntervalSince(lastFetchAttemptAt) < retryAfter {
                return false
            }
            try upsertCacheEntry(
                actor: actor,
                did: entry?.did,
                lastFetchedAt: entry?.lastFetchedAt,
                lastFetchAttemptAt: now,
                in: db
            )
            return true
        }

        guard shouldRefresh else { return nil }
        @Dependency(XRPC.Client.self) var xrpcClient
        let profile = try await xrpcClient.run(
            BlueskyActorGetProfileRequest(actor: actor)
        )
        try await database.write { db in
            try upsert(profile: profile, in: db)
            try upsertCacheAliases(
                requestedActor: actor,
                profile: profile,
                fetchedAt: now,
                in: db
            )
        }
        return profile
    }

    private static func cacheEntry(
        actor: String,
        in db: Database
    ) throws -> BlueskyActorProfileCacheEntry? {
        try BlueskyActorProfileCacheEntry
            .where { $0.actor.eq(actor) }
            .fetchOne(db)
    }

    private static func cachedProfile(
        actor: String,
        in db: Database
    ) throws -> BlueskyActorProfile? {
        guard let did = try cacheEntry(actor: actor, in: db)?.did else {
            return nil
        }
        return try BlueskyActorProfile
            .where { $0.did.eq(did) }
            .fetchOne(db)
    }

    private static func upsert(
        profile: BlueskyActorProfile,
        in db: Database
    ) throws {
        try BlueskyActorProfile.insert {
            profile
        } onConflict: {
            $0.did
        } doUpdate: { profile, excluded in
            profile.handle = excluded.handle
            profile.displayName = excluded.displayName
            profile.description = excluded.description
            profile.avatar = excluded.avatar
            profile.banner = excluded.banner
            profile.followersCount = excluded.followersCount
            profile.followsCount = excluded.followsCount
            profile.postsCount = excluded.postsCount
        }
        .execute(db)
    }

    private static func upsertCacheEntry(
        actor: String,
        did: String?,
        lastFetchedAt: Date?,
        lastFetchAttemptAt: Date?,
        in db: Database
    ) throws {
        try BlueskyActorProfileCacheEntry.insert {
            BlueskyActorProfileCacheEntry(
                actor: actor,
                did: did,
                lastFetchedAt: lastFetchedAt,
                lastFetchAttemptAt: lastFetchAttemptAt
            )
        } onConflict: {
            $0.actor
        } doUpdate: { entry, excluded in
            entry.did = excluded.did
            entry.lastFetchedAt = excluded.lastFetchedAt
            entry.lastFetchAttemptAt = excluded.lastFetchAttemptAt
        }
        .execute(db)
    }

    private static func upsertCacheAliases(
        requestedActor: String,
        profile: BlueskyActorProfile,
        fetchedAt: Date,
        in db: Database
    ) throws {
        let aliases = Set(
            [requestedActor, profile.did, profile.handle]
                .map(BlueskyActorProfileCacheEntry.normalizedActor)
                .filter { !$0.isEmpty }
        )
        for alias in aliases {
            try upsertCacheEntry(
                actor: alias,
                did: profile.did,
                lastFetchedAt: fetchedAt,
                lastFetchAttemptAt: fetchedAt,
                in: db
            )
        }
    }
}
