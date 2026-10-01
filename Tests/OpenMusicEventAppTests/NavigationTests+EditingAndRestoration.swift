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
    func editContributorLoadsExistingContributorOnAppear() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let contributorID = canonicalRouteRecordID(
            "events.openmusic.contributor", "3mrdbziccpcaj"
        )
        _ = try await insertCanonicalContributor(
            into: database, name: "Artist One"
        )

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: EditContributor.State(
                    contributorID: contributorID,
                    eventID: eventID
                )
            ) {
                EditContributor()
            }
        }

        await store.send(.onAppear)?.value

        #expect(store.state.hasLoadedDraft)
        #expect(store.state.form.value.name == "Artist One")
        #expect(store.state.mode.contributorID == contributorID)
    }


    @Test
    func contributorDetailObservesSavedContributorChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let contributorID = canonicalRouteRecordID(
            "events.openmusic.contributor", "3mrdbziccpcaj"
        )
        _ = try await insertCanonicalContributor(
            into: database, name: "Old Name"
        )

        @Bindable var detailStore = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: ContributorDetail.State(contributorID: contributorID, eventID: eventID)) {
                ContributorDetail()
            }
        }

        let editStore = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EditContributor.State(contributorID: contributorID, eventID: eventID)) {
                EditContributor()
            }
        }

        #expect(editStore.state.hasLoadedDraft)
        #expect(editStore.state.form.value.name == "Old Name")
        editStore.modify { $0.form.value.name = "New Name" }
        let submittedValue = editStore.state.form.value
        let submission = editStore.send(.saveButtonTapped)
        let save = await editStore.receive(
            \.formSubmitted,
            .equals(submittedValue),
            timeout: .seconds(1)
        )
        let dismissal = await editStore.receive(\.saveSucceeded, timeout: .seconds(1))
        await dismissal?.value
        await save?.value
        await submission?.value

        let contributor = try await database.read { db in
            try #require(
                try ContributorDetail.contributorQuery(
                    contributorID: contributorID,
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }

        #expect(contributor.name == "New Name")
        await waitForObservation {
            detailStore.contributor?.name == "New Name"
        }
        #expect(detailStore.contributor?.name == "New Name")
    }

    @Test
    func spawnedContributorDetailObservesSavedChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let contributorID = canonicalRouteRecordID(
            "events.openmusic.contributor", "3mrdbziccpcaj"
        )
        _ = try await insertCanonicalContributor(
            into: database, name: "Old Name"
        )

        @Bindable var contributorsStore = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: ContributorsViewer.State(eventID: eventID)) {
                ContributorsViewer()
            }
        }

        contributorsStore.send(.contributorButtonTapped(contributorID))
        @Bindable var detailStore = try #require(
            $contributorsStore
                .scope(\.destination)
                .contributorDetail
                .wrappedValue
        )

        let viewObservationRecorder = ObservationRecorder<String>()
        withObservationTracking {
            _ = ContributorDetailView(store: detailStore).body
        } onChange: {
            Task {
                await viewObservationRecorder.record("invalidated")
            }
        }

        let editStore = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EditContributor.State(contributorID: contributorID, eventID: eventID)) {
                EditContributor()
            }
        }
        editStore.modify { $0.form.value.name = "New Name" }
        let submittedValue = editStore.state.form.value
        let submission = editStore.send(.saveButtonTapped)
        let save = await editStore.receive(
            \.formSubmitted,
            .equals(submittedValue),
            timeout: .seconds(1)
        )
        let dismissal = await editStore.receive(\.saveSucceeded, timeout: .seconds(1))
        await dismissal?.value
        await save?.value
        await submission?.value
        for _ in 0..<100 {
            if await viewObservationRecorder.values == ["invalidated"] {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(await viewObservationRecorder.values == ["invalidated"])
        await waitUntil { detailStore.contributor?.name == "New Name" }
        #expect(detailStore.contributor?.name == "New Name")
    }

    @Test
    func contributorDetailUsesTheCanonicalContributorsSubject() async throws {
        let database = try makePreparedDatabase()
        let actor = try #require(DID("did:plc:alice123"))
        let contributor = try await insertCanonicalContributor(
            into: database,
            name: "Alice",
            subject: actor
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: ContributorDetail.State(
                contributorID: contributor.id,
                eventID: contributor.event
            )) {
                ContributorDetail()
            }
        }

        #expect(store.contributorActor == actor)
        #expect(store.actorProfileLoadRequest?.actor == actor)
        #expect(!store.usesActorProfileAsPrimary)
    }

    @Test
    func editContributorKeepsAnUnassertedSubjectEmpty() async throws {
        let database = try makePreparedDatabase()
        let contributor = try await insertCanonicalContributor(
            into: database,
            name: "Alice"
        )

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EditContributor.State(
                contributorID: contributor.id,
                eventID: contributor.event
            )) {
                EditContributor()
            }
        }

        #expect(store.hasLoadedDraft)
        #expect(store.contributorDID == nil)
        #expect(store.contributorActor == nil)
    }

    @Test
    func contributorProfileHydratesOnlyItsCanonicalSubject() async throws {
        let database = try makePreparedDatabase()
        let contributorDID = try #require(DID("did:plc:alice123"))
        let contributor = try await insertCanonicalContributor(
            into: database,
            name: "Local Alice",
            subject: contributorDID
        )
        let contributorProfile = BlueskyActorProfile(
            did: contributorDID.description,
            handle: "alice.bsky.social",
            displayName: "Alice Profile",
            description: "Alice profile bio"
        )
        let unrelatedProfile = BlueskyActorProfile(
            did: "did:plc:bob456",
            handle: "bob.bsky.social",
            displayName: "Bob Profile",
            description: "Bob profile bio"
        )

        try await database.write { db in
            try BlueskyActorProfile.insert { contributorProfile }.execute(db)
            try BlueskyActorProfile.insert { unrelatedProfile }.execute(db)
        }

        let profile = try await database.read { db in
            try #require(
                try ContributorProfile
                    .one(
                        contributorID: contributor.id,
                        eventID: contributor.event,
                        hydration: .bskyActorProfile
                    )
                    .fetchOne(db)
            )
        }

        #expect(profile.contributorActor == contributorDID)
        #expect(profile.handle == "alice.bsky.social")
        #expect(profile.name == "Local Alice")
        #expect(profile.bio == nil)
        #expect(profile.actorProfileLoadRequest?.actor == contributorDID)
    }

}
