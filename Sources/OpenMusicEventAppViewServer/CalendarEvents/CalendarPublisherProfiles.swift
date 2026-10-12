import Dependencies
import Foundation
import GRDB
import Logging
import ServiceLifecycle
import SQLiteData
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct CalendarPublisherProfile: Decodable, Sendable {
    var did: String
    var handle: String
    var displayName: String?
    var avatar: String?
    var labels: [Label]?
    struct Label: Decodable, Sendable { var val: String }
}

struct CalendarPublisherProfileClient: Sendable, DependencyKey {
    var profiles: @Sendable ([String]) async throws -> [CalendarPublisherProfile]
    static var liveValue: Self { bluesky() }
    static var testValue: Self { .init(profiles: { _ in [] }) }
    enum Failure: Error { case invalidResponse; case rateLimited(TimeInterval) }

    static func bluesky(
        dataForRequest: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        }
    ) -> Self {
        .init { dids in
            guard !dids.isEmpty, dids.count <= 25 else { throw Failure.invalidResponse }
            var url = URLComponents(string: "https://public.api.bsky.app/xrpc/app.bsky.actor.getProfiles")!
            url.queryItems = dids.map { .init(name: "actors", value: $0) }
            var request = URLRequest(url: url.url!, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await dataForRequest(request)
            guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
            if response.statusCode == 429 {
                let seconds = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 300
                throw Failure.rateLimited(seconds.isFinite ? min(86_400, max(60, seconds)) : 300)
            }
            guard response.statusCode == 200, data.count <= 2_000_000 else { throw Failure.invalidResponse }
            struct Payload: Decodable { var profiles: [CalendarPublisherProfile] }
            let profiles = try JSONDecoder().decode(Payload.self, from: data).profiles
            guard profiles.count <= dids.count, Set(profiles.map(\.did)).count == profiles.count,
                  profiles.allSatisfy({ dids.contains($0.did) }) else { throw Failure.invalidResponse }
            return profiles
        }
    }
}

extension CalendarPublisher {
    static func registerProfileMigration(into migrator: inout DatabaseMigrator) {
        migrator.registerMigration("Cache publisher actor profiles") { db in
            try db.execute(sql: """
                ALTER TABLE "\(tableName)" ADD COLUMN displayName TEXT;
                ALTER TABLE "\(tableName)" ADD COLUMN handle TEXT;
                ALTER TABLE "\(tableName)" ADD COLUMN avatarURL TEXT;
                ALTER TABLE "\(tableName)" ADD COLUMN profileSearch TEXT NOT NULL DEFAULT '';
                ALTER TABLE "\(tableName)" ADD COLUMN profileNextAttempt REAL NOT NULL DEFAULT 0;
                CREATE INDEX calendar_publisher_profile_refresh ON "\(tableName)" (profileNextAttempt,id);
                """)
        }
    }

    static func foldProfileSearch(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

struct CalendarPublisherProfileService: Service {
    let store: OpenMusicEventAppViewStore
    @Dependency(CalendarPublisherProfileClient.self) var client
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    let logger = Logger(label: "ome.publisher-profiles")

    func refreshBatch() async throws -> Duration {
        let publishers = try await store.database.read { db in
            try CalendarPublisher.where { $0.profileNextAttempt <= now.timeIntervalSince1970 }
                .order(by: \.profileNextAttempt).order(by: \.id).limit(25).fetchAll(db)
        }
        guard !publishers.isEmpty else { return .seconds(60) }
        let profiles: [CalendarPublisherProfile]
        do {
            profiles = try await client.profiles(publishers.map(\.did))
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            let retry: TimeInterval
            if case let CalendarPublisherProfileClient.Failure.rateLimited(delay) = error { retry = delay }
            else { retry = 300 }
            try await store.database.write { db in
                try CalendarPublisher.where { $0.id.in(publishers.map(\.id)) }.update {
                    $0.profileNextAttempt = #bind(now.addingTimeInterval(retry).timeIntervalSince1970)
                }.execute(db)
            }
            logger.warning("Publisher profile enrichment unavailable; retaining cached metadata")
            return .seconds(retry)
        }
        try Task.checkCancellation()
        try await store.database.write { db in
            for publisher in publishers {
                let profile = profiles.first { $0.did == publisher.did }
                let hidden = profile?.labels?.contains { ["!hide", "!no-unauthenticated"].contains($0.val) } == true
                let displayName = hidden ? nil : profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let handle = hidden || profile?.handle == "handle.invalid" ? nil : profile?.handle
                let avatar = profile?.avatar.flatMap { value -> String? in
                    guard !hidden, profile?.labels?.isEmpty != false,
                          let url = URL(string: value), url.scheme == "https", url.host == "cdn.bsky.app",
                          url.user == nil, url.password == nil else { return nil }
                    return url.absoluteString
                }
                let name = displayName?.isEmpty == false ? displayName : nil
                let search = CalendarPublisher.foldProfileSearch([name, handle].compactMap { $0 }.joined(separator: " "))
                try CalendarPublisher.find(publisher.id).update {
                    $0.displayName = #bind(name)
                    $0.handle = #bind(handle)
                    $0.avatarURL = #bind(avatar)
                    $0.profileSearch = #bind(search)
                    $0.profileNextAttempt = #bind(now.addingTimeInterval(profile == nil ? 3_600 : 86_400).timeIntervalSince1970)
                }.execute(db)
            }
        }
        return .seconds(1)
    }

    func run() async throws {
        do {
            try await cancelWhenGracefulShutdown {
                while !Task.isCancelled {
                    let delay = try await refreshBatch()
                    try await clock.sleep(for: delay)
                }
            }
        } catch is CancellationError {}
    }
}
