import Bluesky
import ATProto
import Clocks
import ComposableArchitecture2
import ComposableNotifications
import CustomDump
import Dependencies
import DependenciesTestSupport
import DebugSnapshots
import Foundation
import IssueReporting
import Observation
import OpenMusicEventDatabase
import OpenMusicEventAuthentication
import OpenMusicEventImages
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import Sharing
import SQLiteData
import SourceEditing
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Testing
import ATProto

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventEditors

extension NavigationTests {
    @Test
    func contributorDetailHydratesItsCanonicalSubjectProfile() async throws {
        let database = try makePreparedDatabase()
        let actor = try #require(DID("did:plc:alice123"))
        let contributor = try await insertCanonicalContributor(
            into: database,
            name: "Alice at Wicked Woods",
            subject: actor
        )
        let profile = BlueskyActorProfile(
            did: actor.description,
            handle: "alice.bsky.social",
            displayName: "Alice Example",
            description: "ATProto builder",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg"),
            banner: URL(string: "https://cdn.example/alice-banner.jpg")
        )
        let requestRecorder = BlueskyProfileRequestRecorder()

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.blueskyActorProfileCache = BlueskyActorProfileCacheClient(
                cachedProfile: { _ in nil },
                refreshProfile: { requestedActor in
                    await requestRecorder.record(requestedActor)
                    return profile
                },
                refreshProfileIfNeeded: { requestedActor, _, _ in
                    await requestRecorder.record(requestedActor)
                    try await database.write { db in
                        try BlueskyActorProfile.insert { profile }
                            .execute(db)
                        try BlueskyActorProfileCacheEntry.insert {
                            BlueskyActorProfileCacheEntry(
                                actor: requestedActor,
                                did: profile.did,
                                lastFetchedAt: Date(timeIntervalSince1970: 1_000),
                                lastFetchAttemptAt: Date(timeIntervalSince1970: 1_000)
                            )
                        }
                        .execute(db)
                    }
                    return profile
                }
            )
        } operation: {
            Store(initialState: ContributorDetail.State(
                contributorID: contributor.id,
                eventID: contributor.event
            )) {
                ContributorDetail()
            }
        }

        try await waitForBlueskyProfile(in: store)

        #expect(await requestRecorder.actors == [actor.description])
        #expect(store.contributorActor == actor)
        #expect(!store.usesActorProfileAsPrimary)
        let contributorProfile = try #require(store.profile)
        #expect(contributorProfile.name == "Alice at Wicked Woods")
        #expect(contributorProfile.bio == nil)
        #expect(contributorProfile.handle == "alice.bsky.social")
        #expect(contributorProfile.artworkAsset?.url?.absoluteString == "https://cdn.example/alice-avatar.jpg")
        #expect(contributorProfile.artworkCacheContext == nil)
    }

    @Test
    func explicitContributorDisplayDoesNotGetOverwrittenByBlueskyProfileData() async throws {
        let database = try makePreparedDatabase()
        let actor = try #require(DID("did:plc:alice123"))
        let explicitImageURL = try #require(URL(string: "https://example.com/explicit.jpg"))
        var contributor = try await insertCanonicalContributor(
            into: database,
            name: "Explicit Alice",
            subject: actor,
            description: "OME bio"
        )
        contributor.media = [.known(.image(OME.Image(
            source: .known(.url(explicitImageURL)),
            role: .known(.photo)
        )))]
        let savedContributor = contributor
        try await database.write { db in
            try Contributor.upsert { savedContributor }.execute(db)
        }
        let profile = BlueskyActorProfile(
            did: actor.description,
            handle: "alice.bsky.social",
            displayName: "Alice Example",
            description: "Bluesky bio",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg"),
            banner: URL(string: "https://cdn.example/alice-banner.jpg")
        )
        let requestRecorder = BlueskyProfileRequestRecorder()

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.blueskyActorProfileCache = BlueskyActorProfileCacheClient(
                cachedProfile: { _ in nil },
                refreshProfile: { requestedActor in
                    await requestRecorder.record(requestedActor)
                    return profile
                },
                refreshProfileIfNeeded: { requestedActor, _, _ in
                    await requestRecorder.record(requestedActor)
                    try await database.write { db in
                        try BlueskyActorProfile.insert { profile }
                            .execute(db)
                        try BlueskyActorProfileCacheEntry.insert {
                            BlueskyActorProfileCacheEntry(
                                actor: requestedActor,
                                did: profile.did,
                                lastFetchedAt: Date(timeIntervalSince1970: 1_000),
                                lastFetchAttemptAt: Date(timeIntervalSince1970: 1_000)
                            )
                        }
                        .execute(db)
                    }
                    return profile
                }
            )
        } operation: {
            Store(initialState: ContributorDetail.State(
                contributorID: contributor.id,
                eventID: contributor.event
            )) {
                ContributorDetail()
            }
        }
        try await waitForBlueskyProfile(in: store)

        #expect(await requestRecorder.actors == [actor.description])
        #expect(store.contributorActor == actor)
        #expect(!store.usesActorProfileAsPrimary)
        let contributorProfile = try #require(store.profile)
        #expect(contributorProfile.name == "Explicit Alice")
        #expect(contributorProfile.handle == "alice.bsky.social")
        #expect(contributorProfile.bio == "OME bio")
        #expect(contributorProfile.artworkAsset?.url == explicitImageURL)
        #expect(contributorProfile.artworkCacheContext == nil)
    }

    @Test
    func createContributorSavesNewContributor() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = EditContributor.State(eventID: eventID)
            state.form.value.name = " New Contributor "
            state.form.value.bio = " Bio "

            return TestStore(initialState: state) {
                EditContributor()
            }
        }

        let submittedValue = store.state.form.value
        let submission = store.send(.saveButtonTapped)
        let save = await store.receive(
            \.formSubmitted,
            .equals(submittedValue),
            timeout: .seconds(1)
        )
        let dismissal = await store.receive(\.saveSucceeded, timeout: .seconds(1))
        await dismissal?.value
        await save?.value
        await submission?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let contributors = try await database.read { db in
            try Contributor.where { $0.event.eq(eventID) }.fetchAll(db)
        }
        expectNoDifference(contributors.count, 1)
        let contributor = try #require(contributors.first)
        expectNoDifference(contributor.name, "New Contributor")
        expectNoDifference(contributor.description, "Bio")
    }

}
