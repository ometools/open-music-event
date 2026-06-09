import ComposableArchitecture2
import CustomDump
import Dependencies
import ErrorHandling
import Foundation
import IssueReporting
import Lexicon
import SQLiteData
import SwiftUI
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

@MainActor
struct SettingsFeatureTests {
    @Test
    func testErrorButtonReportsGlobalError() async {
        let store = withDependencies {
            $0.exhaustivity = .off
        } operation: {
            TestStore(initialState: SettingsErrorHost.State()) {
                SettingsErrorHost()
            }
        }

        await withIssueReporters([]) {
            await store.send(to: \.settings, .testErrorButtonTapped)?.value
        }

        let latestError = store.state.errorNotifications.state.latestError
        #expect(latestError?.kind == .settingsTestError)
        #expect(latestError?.message.fallback == "Test error.")
        #expect(latestError?.operation == .settingsTestError)
        #expect(latestError?.debugDescription == "Settings test error")
    }

    @Test
    func eventSettingsTestErrorButtonReportsGlobalError() async {
        let store = withDependencies {
            $0.exhaustivity = .off
        } operation: {
            TestStore(initialState: EventSettingsErrorHost.State()) {
                EventSettingsErrorHost()
            }
        }

        await withIssueReporters([]) {
            await store.send(to: \.eventSettings, .testErrorButtonTapped)?.value
        }

        let latestError = store.state.errorNotifications.state.latestError
        #expect(latestError?.kind.rawValue == "event.settings.test-error")
        #expect(latestError?.message.fallback == "Test error.")
        #expect(latestError?.operation.rawValue == "event.settings.test-error")
        #expect(latestError?.debugDescription == "Event settings test error")
    }

    @Test
    func eventPoliciesButtonOpensPolicyEditor() throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.exhaustivity = .off
        } operation: {
            TestStore(initialState: EventSettings.State(eventID: eventID)) {
                EventSettings()
            }
        }

        store.send(.eventPoliciesButtonTapped)

        #expect(store.state.destination?.editEventPolicies?.eventID == eventID)
    }

    @Test
    func eventPolicyEditorLoadsExistingPolicies() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        let policies = contributorPolicies(
            listing: .known(.scheduleContributors),
            profile: .known(
                .actorProfiles(
                    .init(providers: [.known(.bskyActorProfile)])
                )
            )
        )
        try await insertEvent(eventID, policies: policies, into: database)

        let store = makePolicyEditorStore(database: database, eventID: eventID)

        #expect(store.hasLoadedDraft)
        #expect(store.form.value.contributorListing == .scheduleContributors)
        #expect(store.form.value.contributorProfile == .actorProfiles)
        #expect(store.form.value.usesBlueskyActorProfile)
        #expect(store.form.value.preservedProfileProviders.isEmpty)
        #expect(store.errorMessage == nil)
    }

    @Test
    func eventPolicyEditorSavesScheduleContributorListing() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        try await insertEvent(eventID, into: database)

        @Bindable var store = makePolicyEditorStore(database: database, eventID: eventID)
        $store.form.value.contributorListing.wrappedValue = .scheduleContributors

        await store.send(.saveButtonTapped)?.value

        let event = try await fetchEvent(eventID, from: database)
        expectNoDifference(
            event.policies,
            contributorPolicies(listing: .known(.scheduleContributors))
        )
    }

    @Test
    func eventPolicyEditorSavesActorProfilePolicy() async throws {
        try await saveProfilePolicy(.actorProfiles)
    }

    @Test
    func eventPolicyEditorSavesClaimedArtistsOnlyProfilePolicy() async throws {
        try await saveProfilePolicy(.claimedArtistsOnly)
    }

    @Test
    func eventPolicyEditorClearsPoliciesWhenNoPoliciesRemain() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        try await insertEvent(
            eventID,
            policies: contributorPolicies(
                listing: .known(.scheduleContributors),
                profile: .known(
                    .actorProfiles(
                        .init(providers: [.known(.bskyActorProfile)])
                    )
                )
            ),
            into: database
        )

        @Bindable var store = makePolicyEditorStore(database: database, eventID: eventID)
        $store.form.value.contributorListing.wrappedValue = .none
        $store.form.value.contributorProfile.wrappedValue = .none
        $store.form.value.usesBlueskyActorProfile.wrappedValue = false

        await store.send(.saveButtonTapped)?.value

        let event = try await fetchEvent(eventID, from: database)
        #expect(event.policies == nil)
    }

    @Test
    func eventPolicyEditorPreservesUnsupportedPolicyValues() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        let policies = contributorPolicies(
            listing: .unknown(
                .object([
                    "type": .string("customListing"),
                    "mode": .string("source"),
                ])
            ),
            profile: .unknown(
                .object([
                    "type": .string("customProfile"),
                    "provider": .string("social.example.profile"),
                ])
            )
        )
        try await insertEvent(eventID, policies: policies, into: database)

        let store = makePolicyEditorStore(database: database, eventID: eventID)

        #expect(store.form.value.contributorListing == .unsupported)
        #expect(store.form.value.contributorProfile == .unsupported)
        await store.send(.saveButtonTapped)?.value

        let event = try await fetchEvent(eventID, from: database)
        expectNoDifference(event.policies, policies)
    }

    @Test
    func eventPolicyEditorPreservesUnsupportedProfileProviders() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        let unsupportedProvider: Open<OMERecord.Event.ContributorProfileProvider> =
            .unknown(.string("social.example.profile"))
        let policies = contributorPolicies(
            profile: .known(
                .actorProfiles(
                    .init(providers: [unsupportedProvider])
                )
            )
        )
        try await insertEvent(eventID, policies: policies, into: database)

        let store = makePolicyEditorStore(database: database, eventID: eventID)

        #expect(store.form.value.contributorProfile == .actorProfiles)
        #expect(!store.form.value.usesBlueskyActorProfile)
        expectNoDifference(store.form.value.preservedProfileProviders, [unsupportedProvider])
        await store.send(.saveButtonTapped)?.value

        let event = try await fetchEvent(eventID, from: database)
        expectNoDifference(event.policies, policies)
    }

    @Test
    func eventPolicyEditorBlocksKnownProfilePolicyWithoutProviders() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        try await insertEvent(eventID, into: database)

        @Bindable var store = makePolicyEditorStore(database: database, eventID: eventID)
        $store.form.value.contributorProfile.wrappedValue = .actorProfiles
        $store.form.value.usesBlueskyActorProfile.wrappedValue = false

        await store.send(.saveButtonTapped)?.value

        #expect(store.errorMessage == "Choose at least one profile provider.")
        let event = try await fetchEvent(eventID, from: database)
        #expect(event.policies == nil)
    }

    private func saveProfilePolicy(
        _ profile: EditEventPolicies.ContributorProfileSelection
    ) async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        try await insertEvent(eventID, into: database)

        @Bindable var store = makePolicyEditorStore(database: database, eventID: eventID)
        $store.form.value.contributorProfile.wrappedValue = profile
        $store.form.value.usesBlueskyActorProfile.wrappedValue = true

        await store.send(.saveButtonTapped)?.value

        let expectedProfile: Open<OMERecord.Event.ContributorProfilePolicy>
        switch profile {
        case .actorProfiles:
            expectedProfile = .known(
                .actorProfiles(
                    .init(providers: [.known(.bskyActorProfile)])
                )
            )
        case .claimedArtistsOnly:
            expectedProfile = .known(
                .claimedArtistsOnly(
                    .init(providers: [.known(.bskyActorProfile)])
                )
            )
        case .none, .unsupported:
            fatalError("Unsupported profile test input.")
        }

        let event = try await fetchEvent(eventID, from: database)
        expectNoDifference(
            event.policies,
            contributorPolicies(profile: expectedProfile)
        )
    }
}

@Feature
private struct SettingsErrorHost {
    struct State {
        var errorNotifications = Spawn(ErrorNotifications.State())
        @DebugSnapshotIgnored
        var settings = Spawn(Settings.State())
    }

    enum Action {}

    var body: some Feature {
        Update { _, _ in }
            .spawn(\.errorNotifications) {
                ErrorNotifications()
            }
            .spawn(\.settings) {
                Settings()
            }
            .onEvent(ErrorReported.self) { error, state in
                state.errorNotifications.state.report(error)
            }
    }
}

@Feature
private struct EventSettingsErrorHost {
    struct State {
        var errorNotifications = Spawn(ErrorNotifications.State())
        @DebugSnapshotIgnored
        var eventSettings = Spawn(EventSettings.State(eventID: testEventID()))
    }

    enum Action {}

    var body: some Feature {
        Update { _, _ in }
            .spawn(\.errorNotifications) {
                ErrorNotifications()
            }
            .spawn(\.eventSettings) {
                EventSettings()
            }
            .onEvent(ErrorReported.self) { error, state in
                state.errorNotifications.state.report(error)
            }
    }
}

private func testEventID() -> OMERecord.Event.ID {
    OMERecord.Event.ID(
        organizerID: OMERecord.Organizer.ID("did:web:example.com")!,
        eventID: .init("event-1")
    )
}

private func contributorPolicies(
    listing: Open<OMERecord.Event.ContributorListingPolicy>? = nil,
    profile: Open<OMERecord.Event.ContributorProfilePolicy>? = nil
) -> OMERecord.Event.Policies {
    OMERecord.Event.Policies(
        contributors: .init(
            listing: listing,
            profile: profile
        )
    )
}

@MainActor
private func makePolicyEditorStore(
    database: any DatabaseWriter,
    eventID: OMERecord.Event.ID
) -> StoreOf<EditEventPolicies> {
    withDependencies {
        $0.context = .test
        $0.continuousClock = ImmediateClock()
        $0.defaultDatabase = database
        $0.exhaustivity = .off
    } operation: {
        Store(initialState: EditEventPolicies.State(eventID: eventID)) {
            EditEventPolicies()
        }
    }
}

private func makePreparedDatabase() throws -> any DatabaseWriter {
    try withDependencies {
        $0.context = .test
        try OME.prepareDependencies(&$0)
    } operation: {
        @Dependency(\.defaultDatabase) var database
        return database
    }
}

private func insertEvent(
    _ eventID: OMERecord.Event.ID,
    policies: OMERecord.Event.Policies? = nil,
    into database: any DatabaseWriter
) async throws {
    try await database.write { db in
        try OMERecord.Organizer.insert {
            OMERecord.Organizer.Draft(id: eventID.organizerID)
        }
        .execute(db)
        try OMERecord.Event.insert {
            OMERecord.Event.Draft(
                id: eventID,
                name: "Event One",
                description: nil,
                startDate: nil,
                endDate: nil,
                status: nil,
                mode: nil,
                locations: nil,
                uris: nil,
                timeZone: TimeZone(identifier: "UTC")!,
                images: nil,
                contactNumbers: nil,
                categoryConfigs: nil,
                policies: policies
            )
        }
        .execute(db)
    }
}

private func fetchEvent(
    _ eventID: OMERecord.Event.ID,
    from database: any DatabaseWriter
) async throws -> OMERecord.Event {
    try await database.read { db in
        try #require(
            try OMERecord.Event
                .where { $0.id.eq(eventID) }
                .fetchOne(db)
        )
    }
}
