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
    func editContributorInlineProfileSearchUsesTypeaheadUntilSubmitted() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let contributorID = canonicalRouteRecordID(
            "events.openmusic.contributor", "3mrdbziccpcaj"
        )
        let exactLookupInputs = ObservationRecorder<String>()
        let typeaheadQueries = ObservationRecorder<String>()
        let exactIdentity = ActorIdentity(
            did: try #require(DID("did:plc:alice123")),
            handle: Atmosphere.Account.Handle(rawValue: "alice.example.com"),
            displayName: "Alice Exact",
            source: .canonicalResolution
        )
        let typeaheadIdentity = ActorIdentity(
            did: try #require(DID("did:plc:alice456")),
            handle: Atmosphere.Account.Handle(rawValue: "alice.bsky.social"),
            displayName: "Alice Typeahead",
            avatar: try #require(URL(string: "https://example.com/alice.jpg")),
            source: .typeahead
        )

        _ = try await insertCanonicalContributor(into: database, name: "Alice")

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
            $0.actorTypeaheadSearch.search = { query in
                await typeaheadQueries.record(query.normalizedText)
                return [typeaheadIdentity]
            }
            $0.actorIdentityLookup.resolve = { input in
                await exactLookupInputs.record(input)
                return exactIdentity
            }
        } operation: {
            Store(initialState: EditContributor.State(contributorID: contributorID, eventID: eventID)) {
                EditContributor()
            }
        }

        await store.send(.actorSearchQueryChanged(" alice "))?.value

        expectNoDifference(
            store.actorSearchSections.map(\.title),
            ["Profiles"]
        )
        expectNoDifference(
            store.actorSearchSections.flatMap(\.results),
            [typeaheadIdentity]
        )
        #expect(await typeaheadQueries.values == ["alice"])
        #expect(await exactLookupInputs.values == [])
        #expect(store.actorSearchIsLoading == false)
        #expect(store.actorSearchFailures.isEmpty)

        await store.send(.actorSearchSubmitted)?.value

        expectNoDifference(
            store.actorSearchSections.map(\.title),
            ["Exact match"]
        )
        expectNoDifference(
            store.actorSearchSections.flatMap(\.results),
            [exactIdentity]
        )
        #expect(await typeaheadQueries.values == ["alice"])
        #expect(await exactLookupInputs.values == ["alice"])
        #expect(store.actorSearchIsLoading == false)
        #expect(store.actorSearchFailures.isEmpty)
    }

    @Test
    func editContributorActorPickerSavesSelectedSubjectDID() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let previousActor = try #require(DID("did:plc:previous123"))
        let selectedIdentity = ActorIdentity(
            did: try #require(DID("did:plc:alice123")),
            handle: Atmosphere.Account.Handle(rawValue: "alice.bsky.social"),
            displayName: "Alice",
            source: .canonicalResolution
        )
        let contributor = try await insertCanonicalContributor(
            into: database,
            name: "Alice",
            subject: previousActor
        )
        let requestRecorder = BlueskyProfileRequestRecorder()

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.continuousClock = ContinuousClock()
            $0.blueskyActorProfileCache = BlueskyActorProfileCacheClient(
                cachedProfile: { _ in nil },
                refreshProfile: { requestedActor in
                    await requestRecorder.record(requestedActor)
                    return BlueskyActorProfile(
                        did: selectedIdentity.did.description,
                        handle: "alice.bsky.social"
                    )
                },
                refreshProfileIfNeeded: { requestedActor, _, _ in
                    await requestRecorder.record(requestedActor)
                    return BlueskyActorProfile(
                        did: selectedIdentity.did.description,
                        handle: "alice.bsky.social"
                    )
                }
            )
        } operation: {
            TestStore(
                initialState: EditContributor.State(
                    contributorID: contributor.id, eventID: eventID
                )
            ) {
                EditContributor()
            }
        }
        await store.send(.onAppear)?.value
        #expect(store.state.form.value.name == "Alice")
        #expect(store.state.contributorDID == previousActor)

        let profileLookup = store.send(.actorIdentityTapped(selectedIdentity))
        let profileResponse = await store.receive(
            \.actorProfileResponse,
            TestStoreMatcher<BlueskyActorProfile?>(
                matching: { $0?.did == selectedIdentity.did.description }
            ),
            timeout: .seconds(1)
        )
        await profileResponse?.value
        await profileLookup?.value

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

        let saved = try await database.read { db in
            try Contributor.find(contributor.id).fetchOne(db)
        }
        expectNoDifference(saved?.subject, selectedIdentity.did)
        expectNoDifference(saved?.id, contributor.id)
        expectNoDifference(saved?.name, "Alice")
        #expect(await requestRecorder.actors == [selectedIdentity.did.description])
        #expect(store.state.contributorActor == selectedIdentity.did)
        #expect(store.state.actorSearchQuery == "")
        #expect(store.state.actorSearchSections.isEmpty)
        #expect(store.state.isSavingActor == false)
        #expect(store.state.actorSearchErrorMessage == nil)
    }

    @Test
    func createContributorActorPickerPrefillsBlankFieldsAndSavesSubject() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let selectedIdentity = ActorIdentity(
            did: try #require(DID("did:plc:alice123")),
            handle: Atmosphere.Account.Handle(rawValue: "alice.bsky.social"),
            displayName: "Alice Typeahead",
            avatar: try #require(URL(string: "https://example.com/alice-avatar.jpg")),
            source: .typeahead
        )
        let profile = BlueskyActorProfile(
            did: selectedIdentity.did.description,
            handle: "alice.bsky.social",
            displayName: "Alice Profile",
            description: "ATProto builder",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg")
        )
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
            $0.blueskyActorProfileCache = BlueskyActorProfileCacheClient(
                cachedProfile: { _ in nil },
                refreshProfile: { _ in profile },
                refreshProfileIfNeeded: { _, _, _ in profile }
            )
        } operation: {
            TestStore(initialState: EditContributor.State(eventID: eventID)) {
                EditContributor()
            }
        }

        let profileLookup = store.send(.actorIdentityTapped(selectedIdentity))
        let profileResponse = await store.receive(
            \.actorProfileResponse,
            .equals(Optional(profile)),
            timeout: .seconds(1)
        )
        await profileResponse?.value
        await profileLookup?.value

        expectNoDifference(store.state.contributorDID, selectedIdentity.did)
        expectNoDifference(store.state.form.value.name, "Alice Typeahead")
        expectNoDifference(store.state.form.value.bio, "ATProto builder")
        expectNoDifference(
            store.state.imageURL, "https://example.com/alice-avatar.jpg"
        )

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

        let saved = try await database.read { db in
            try Contributor.where { $0.event.eq(eventID) }.fetchAll(db)
        }
        expectNoDifference(saved.count, 1)
        let contributor = try #require(saved.first)
        expectNoDifference(contributor.subject, selectedIdentity.did)
        expectNoDifference(contributor.name, "Alice Typeahead")
        expectNoDifference(contributor.description, "ATProto builder")
        let photoURL = contributor.media?.compactMap { medium -> URL? in
            guard case let .known(.image(image)) = medium else { return nil }
            return image.displayImageAsset(recordID: eventID)?.asset.url
        }.first
        expectNoDifference(
            photoURL?.absoluteString, "https://example.com/alice-avatar.jpg"
        )
    }

    @Test
    func createContributorActorPickerDoesNotOverwriteEnteredFields() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let manualPhotoURL = try #require(URL(string: "https://example.com/manual-photo.jpg"))
        let selectedIdentity = ActorIdentity(
            did: try #require(DID("did:plc:alice123")),
            handle: Atmosphere.Account.Handle(rawValue: "alice.bsky.social"),
            displayName: "Alice Typeahead",
            avatar: try #require(URL(string: "https://example.com/alice-avatar.jpg")),
            source: .typeahead
        )
        let profile = BlueskyActorProfile(
            did: selectedIdentity.did.description,
            handle: "alice.bsky.social",
            displayName: "Alice Profile",
            description: "ATProto builder",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg")
        )

        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.blueskyActorProfileCache = BlueskyActorProfileCacheClient(
                cachedProfile: { _ in nil },
                refreshProfile: { _ in profile },
                refreshProfileIfNeeded: { _, _, _ in profile }
            )
        } operation: {
            var state = EditContributor.State(eventID: eventID)
            state.form.value.name = "Manual Artist"
            state.form.value.bio = "Manual bio"
            state.imageURL = manualPhotoURL.absoluteString
            return Store(initialState: state) {
                EditContributor()
            }
        }

        await store.send(.actorIdentityTapped(selectedIdentity))?.value

        #expect(store.contributorDID == selectedIdentity.did)
        #expect(store.form.value.name == "Manual Artist")
        #expect(store.form.value.bio == "Manual bio")
        #expect(store.imageURL == manualPhotoURL.absoluteString)
    }

}
