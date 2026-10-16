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
        #expect(contributorProfile.artworkDisplayImage?.url?.absoluteString == "https://cdn.example/alice-avatar.jpg")
        #expect(contributorProfile.artworkDisplayImage?.recordID == nil)
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
        #expect(contributorProfile.artworkDisplayImage?.url == explicitImageURL)
        #expect(contributorProfile.artworkDisplayImage?.recordID != nil)
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
            var state = ContributorForm.State(eventID: eventID)
            state.form.value.name = " New Contributor "
            state.form.value.bio = " Bio "

            return TestStore(initialState: state) {
                ContributorForm()
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

    @Test
    func `contributor form pins updates and removes an account source record`() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let actor = try #require(DID("did:plc:alice123"))
        let sourceURI = try #require(ATProto.URI(
            "at://did:plc:alice123/app.bsky.actor.profile/self"
        ))
        let firstCID = "bafyreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"
        let secondCID = "bafyreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyky"
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
        }

        var createState = ContributorForm.State(eventID: eventID)
        createState.form.value.name = "Alice"
        createState.contributorDID = actor
        createState.pinnedSourceURI = sourceURI.description
        #expect(createState.pinnedSourceValidationMessage == "Enter the source record CID.")
        createState.pinnedSourceCID = firstCID
        #expect(createState.pinnedSourceValidationMessage == nil)
        let createStore = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: createState) { ContributorForm() }
        }
        let createValue = createStore.state.form.value
        let createTask = createStore.send(.saveButtonTapped)
        let createdSubmission = await createStore.receive(
            \.formSubmitted, .equals(createValue), timeout: .seconds(1)
        )
        let createdDismissal = await createStore.receive(\.saveSucceeded, timeout: .seconds(1))
        await createdDismissal?.value
        await createdSubmission?.value
        await createTask?.value

        var contributor = try await database.read { db in
            try #require(try Contributor.where { $0.event.eq(eventID) }.fetchOne(db))
        }
        #expect(contributor.source == Contributor.Source(
            uri: sourceURI, cid: ATProto.CID(rawValue: firstCID)
        ))
        let contributorID = contributor.id

        var editState = ContributorForm.State(contributorID: contributorID, eventID: eventID)
        editState.load(contributor)
        #expect(editState.pinnedSourceCID == firstCID)
        editState.pinnedSourceCID = secondCID
        let editStore = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: editState) { ContributorForm() }
        }
        let editValue = editStore.state.form.value
        let editTask = editStore.send(.saveButtonTapped)
        let editedSubmission = await editStore.receive(
            \.formSubmitted, .equals(editValue), timeout: .seconds(1)
        )
        let editedDismissal = await editStore.receive(\.saveSucceeded, timeout: .seconds(1))
        await editedDismissal?.value
        await editedSubmission?.value
        await editTask?.value

        contributor = try await database.read { db in
            try #require(try Contributor.find(contributorID).fetchOne(db))
        }
        #expect(contributor.source?.cid == ATProto.CID(rawValue: secondCID))

        var removeState = ContributorForm.State(contributorID: contributorID, eventID: eventID)
        removeState.load(contributor)
        let removeStore = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: removeState) { ContributorForm() }
        }
        let removeAction = removeStore.send(.removePinnedSourceButtonTapped)
        await removeAction?.value
        #expect(removeStore.state.pinnedSource == nil)
        let removeValue = removeStore.state.form.value
        let saveTask = removeStore.send(.saveButtonTapped)
        let removedSubmission = await removeStore.receive(
            \.formSubmitted, .equals(removeValue), timeout: .seconds(1)
        )
        let removedDismissal = await removeStore.receive(\.saveSucceeded, timeout: .seconds(1))
        await removedDismissal?.value
        await removedSubmission?.value
        await saveTask?.value

        contributor = try await database.read { db in
            try #require(try Contributor.find(contributorID).fetchOne(db))
        }
        #expect(contributor.source == nil)
    }

}
