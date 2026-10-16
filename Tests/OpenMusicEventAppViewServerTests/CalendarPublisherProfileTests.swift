import CustomDump
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OpenMusicEventAppViewServer

@Suite(AppViewTestTime()) struct CalendarPublisherProfileTests {
    @Test func `public profile transport batches DIDs anonymously and rejects unrelated identities`() async throws {
        let client = CalendarPublisherProfileClient.bluesky { request in
            expectNoDifference(request.url?.host, "public.api.bsky.app")
            expectNoDifference(request.url?.path, "/xrpc/app.bsky.actor.getProfiles")
            expectNoDifference(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems,
                               [.init(name: "actors", value: "did:plc:source")])
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            return (Data(#"{"profiles":[{"did":"did:plc:source","handle":"source.example","displayName":"Boulder Calendar"}]}"#.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let profiles = try await client.profiles(["did:plc:source"])
        expectNoDifference(profiles.first?.displayName, "Boulder Calendar")
        let unrelated = CalendarPublisherProfileClient.bluesky { request in
            (Data(#"{"profiles":[{"did":"did:plc:other","handle":"other.example"}]}"#.utf8),
             HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await #expect(throws: CalendarPublisherProfileClient.Failure.self) {
            try await unrelated.profiles(["did:plc:source"])
        }
    }

    @Test func `cached profiles are searchable keep filter identity and survive upstream failures`() async throws {
        let store = try OpenMusicEventAppViewStore(database: DatabaseQueue())
        let before = try store.calendarPublishers(.init())
        let did = CalendarPublisher.laughTown
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let profile = CalendarPublisherProfile(did: did, handle: "calendar.example", displayName: "Café Boulder",
            avatar: "https://cdn.bsky.app/img/avatar/plain/example", labels: [])
        try await withDependencies {
            $0.date.now = now
            $0[CalendarPublisherProfileClient.self].profiles = { dids in
                expectNoDifference(dids, [did])
                return [profile]
            }
        } operation: {
            _ = try await CalendarPublisherProfileService(store: store).refreshBatch()
        }
        let result = try store.calendarPublishers(.init(query: "CAFE"))
        expectNoDifference(result.publishers.first?.label, "Café Boulder")
        expectNoDifference(result.publishers.first?.handle, "calendar.example")
        expectNoDifference(result.publishers.first?.id, before.publishers.first?.id)
        expectNoDifference(result.defaults, before.defaults)
        expectNoDifference(try store.calendarPublishers(.init(query: "calendar.example")).publishers.count, 1)

        // A warm directory read and refresh do not need another network lookup.
        try await withDependencies {
            $0.date.now = now.addingTimeInterval(60)
            $0[CalendarPublisherProfileClient.self].profiles = { _ in Issue.record("Fresh cache fetched again"); return [] }
        } operation: {
            let delay = try await CalendarPublisherProfileService(store: store).refreshBatch()
            expectNoDifference(delay, .seconds(60))
        }
        // An upstream outage retains the cached display fields and postpones retries.
        try await withDependencies {
            $0.date.now = now.addingTimeInterval(86_401)
            $0[CalendarPublisherProfileClient.self].profiles = { _ in throw CalendarPublisherProfileClient.Failure.rateLimited(600) }
        } operation: {
            let delay = try await CalendarPublisherProfileService(store: store).refreshBatch()
            expectNoDifference(delay, .seconds(600))
        }
        expectNoDifference(try store.calendarPublishers(.init()).publishers.first?.label, "Café Boulder")
        // A successful response without the actor clears deleted metadata, not the publisher.
        try await withDependencies {
            $0.date.now = now.addingTimeInterval(87_002)
            $0[CalendarPublisherProfileClient.self].profiles = { _ in [] }
        } operation: {
            _ = try await CalendarPublisherProfileService(store: store).refreshBatch()
        }
        let missing = try store.calendarPublishers(.init())
        expectNoDifference(missing.publishers.first?.id, before.publishers.first?.id)
        #expect(missing.publishers.first?.handle == nil)
        #expect(missing.publishers.first?.avatarURL == nil)
    }

    @Test func `hidden profiles are not exposed`() async throws {
        let store = try OpenMusicEventAppViewStore(database: DatabaseQueue())
        try await withDependencies {
            $0[CalendarPublisherProfileClient.self].profiles = { _ in [
                .init(did: CalendarPublisher.laughTown, handle: "hidden.example", displayName: "Hidden",
                      avatar: "https://cdn.bsky.app/img/avatar/plain/hidden", labels: [.init(val: "!no-unauthenticated")])
            ] }
        } operation: {
            _ = try await CalendarPublisherProfileService(store: store).refreshBatch()
        }
        let profile = try #require(try store.calendarPublishers(.init()).publishers.first)
        #expect(profile.handle == nil)
        #expect(profile.avatarURL == nil)
        expectNoDifference(profile.label, "laugh.town")
    }

    @Test(arguments: ["http://cdn.bsky.app/image", "https://untrusted.example/image", "javascript:alert(1)"])
    func `unsafe avatars do not prevent a readable publisher name`(avatar: String) async throws {
        let store = try OpenMusicEventAppViewStore(database: DatabaseQueue())
        try await withDependencies {
            $0[CalendarPublisherProfileClient.self].profiles = { _ in [
                .init(did: CalendarPublisher.laughTown, handle: "calendar.example", displayName: "Calendar",
                      avatar: avatar, labels: [])
            ] }
        } operation: {
            _ = try await CalendarPublisherProfileService(store: store).refreshBatch()
        }
        let profile = try #require(try store.calendarPublishers(.init()).publishers.first)
        expectNoDifference(profile.label, "Calendar")
        #expect(profile.avatarURL == nil)
    }

    @Test func `cancellation leaves the publisher ready for the next worker`() async throws {
        let store = try OpenMusicEventAppViewStore(database: DatabaseQueue())
        try await withDependencies {
            $0[CalendarPublisherProfileClient.self].profiles = { _ in throw CancellationError() }
        } operation: {
            await #expect(throws: CancellationError.self) {
                try await CalendarPublisherProfileService(store: store).refreshBatch()
            }
        }
        let attempt = try await store.database.read { db in
            try CalendarPublisher.all.select(\.profileNextAttempt).fetchOne(db)
        }
        expectNoDifference(attempt, 0)
    }
}
