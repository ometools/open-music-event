import Clocks
import ComposableArchitecture2
import CustomDump
import Dependencies
import ErrorHandling
import Foundation
import IssueReporting
import Lexicon
import OpenMusicEventComponents
import OpenMusicEventSourceEditing
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventEditors

@Suite
struct TechnicalDetailsTests {
    @Test
    func `technical details are hidden by default and enabled by the setting`() {
        // A fresh install does not surface raw implementation details.
        expectNoDifference(
            TechnicalDetails.isVisible(userPreference: false, environment: [:]),
            false
        )

        // The user can explicitly opt in from Settings.
        expectNoDifference(
            TechnicalDetails.isVisible(userPreference: true, environment: [:]),
            true
        )
    }

    @Test
    func `environment variable overrides the persisted setting`() {
        // A development launch can force technical details on.
        expectNoDifference(
            TechnicalDetails.isVisible(
                userPreference: false,
                environment: ["OME_SHOW_TECHNICAL_DETAILS": "true"]
            ),
            true
        )

        // An explicit off value wins even when the user preference was previously enabled.
        expectNoDifference(
            TechnicalDetails.isVisible(
                userPreference: true,
                environment: ["OME_SHOW_TECHNICAL_DETAILS": "0"]
            ),
            false
        )
    }

    @Test
    func `account presentation does not fall back to a DID unless opted in`() {
        let did = "did:plc:alice123"

        // Without a profile or handle, the ordinary surface stays human-facing.
        expectNoDifference(
            TechnicalDetails.identityTitle(
                displayName: nil,
                handle: nil,
                technicalID: did,
                isVisible: false
            ),
            "Account"
        )
        expectNoDifference(
            TechnicalDetails.identitySubtitle(
                displayName: nil,
                handle: nil,
                technicalID: did,
                isVisible: false
            ),
            nil
        )

        // Opting in restores the exact account identifier.
        expectNoDifference(
            TechnicalDetails.identityTitle(
                displayName: nil,
                handle: nil,
                technicalID: did,
                isVisible: true
            ),
            did
        )
    }

    @Test
    func `account presentation keeps friendly names and handles when details are hidden`() {
        expectNoDifference(
            TechnicalDetails.identityTitle(
                displayName: "Alice",
                handle: "alice.example",
                technicalID: "did:plc:alice123",
                isVisible: false
            ),
            "Alice"
        )
        expectNoDifference(
            TechnicalDetails.identitySubtitle(
                displayName: "Alice",
                handle: "alice.example",
                technicalID: "did:plc:alice123",
                isVisible: false
            ),
            "@alice.example"
        )
    }

    @Test
    func `performance editor does not turn an account identifier into a display name`() throws {
        let actor = try #require(
            OMERecord.Contributor.Actor("did:plc:alice123")
        )
        let state = ContributorRelationshipPicker.State()
        let selection = ContributorRelationshipPicker.Selection.identityOnly(
            actor: actor,
            displayTitle: nil
        )

        // The ordinary authoring surface remains human-facing.
        expectNoDifference(
            state.summary(for: selection, showsTechnicalDetails: false)?.title,
            "Account"
        )

        // The raw identifier is still available after an explicit opt-in.
        expectNoDifference(
            state.summary(for: selection, showsTechnicalDetails: true)?.title,
            actor.description
        )
    }
}

@MainActor
@Suite(.tcaExhaustivity(.off))
struct SettingsFeatureTests {
    @Test
    func testErrorButtonReportsGlobalError() async {
        let store = TestStore(initialState: SettingsErrorHost.State()) {
            SettingsErrorHost()
        }

        await withIssueReporters([]) {
            await store.send(to: \.settings, .testErrorButtonTapped)?.value
        }

        await waitForLatestError(in: store.state.errorNotifications)
        let latestError = store.state.errorNotifications.state.latestError
        #expect(latestError?.kind == .settingsTestError)
        #expect(latestError?.message.fallback == "Test error.")
        #expect(latestError?.operation == .settingsTestError)
        #expect(latestError?.debugDescription == "Settings test error")
    }

    @Test
    func eventSettingsTestErrorButtonReportsGlobalError() async throws {
        try await TestExhaustivity.$current.withValue(.off) {
            let database = try makePreparedDatabase()
            let store: TestStore<EventSettingsErrorHost> = withDependencies {
                $0.defaultDatabase = database
            } operation: {
                TestStore(initialState: EventSettingsErrorHost.State()) {
                    EventSettingsErrorHost()
                }
            }

            await withIssueReporters([]) {
                await store.send(
                    to: \.eventSettings,
                    EventSettings.Action.testErrorButtonTapped
                )?.value
            }

            await waitForLatestError(in: store.state.errorNotifications)
            let latestError = store.state.errorNotifications.state.latestError
            #expect(latestError?.kind.rawValue == "event.settings.test-error")
            #expect(latestError?.message.fallback == "Test error.")
            #expect(latestError?.operation.rawValue == "event.settings.test-error")
            #expect(latestError?.debugDescription == "Event settings test error")
        }
    }

    @Test
    func eventPoliciesButtonEmitsPolicyEditorRequest() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EventSettings.State(eventID: eventID)) {
                EventSettings()
            }
        }

        let editTask = store.send(.eventPoliciesButtonTapped)
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(.editEventPolicies(eventID)),
            timeout: .seconds(1)
        )
        await editTask?.value
    }

    @Test
    func eventSettingsButtonsEnterAndExitAuthoring() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        let workspaceID = EditingWorkspaceRecord.ID(localEventID: eventID)
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0[AuthoringPolicyClient.self] = .authoring
            $0[WorkspacePreparationClient.self] = WorkspacePreparationClient(
                prepareSource: { _ in }
            )
        } operation: {
            TestStore(
                initialState: Authoring<EventSettings>.State(workspaceID: workspaceID) {
                    EventSettings.State(eventID: eventID)
                }
            ) {
                Authoring { EventSettings() }
            }
        }

        // Event Settings is mounted in attendee mode, where the user asks to enter authoring.
        let enterTask = store.send(.content(.enterAuthoringButtonTapped))
        await enterTask?.value
        store.expect {
            $0.grant = AuthoringGrant(
                principal: .local,
                role: .owner,
                workspaceID: workspaceID
            )
        }

        // The same screen lets the author return to attendee mode.
        let exitTask = store.send(.content(.exitAuthoringButtonTapped))
        await exitTask?.value
        store.expect {
            $0.grant = nil
        }
    }

    private func waitForLatestError(in errorNotifications: Spawn<ErrorNotifications>) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(60))
        while errorNotifications.state.latestError == nil && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(errorNotifications.state.latestError != nil)
    }

    @Test
    func eventSettingsRequestsLocalEventDeletionAfterConfirmation() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        try await insertEvent(eventID, into: database)
        let store: TestStore<EventSettings> = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EventSettings.State(eventID: eventID)) {
                EventSettings()
            }
        }

        store.send(.deleteEventButtonTapped) {
            $0.isDeleteEventConfirmationPresented = true
        }
        let deleteTask = store.send(.deleteEventConfirmationDeleteButtonTapped) {
            $0.isDeleteEventConfirmationPresented = false
        }
        await store.receive(
            key: LocalEventDeletionRequested.self,
            value: .equals(eventID),
            timeout: .seconds(1)
        )
        await deleteTask?.value
    }

    @Test
    func appRootDeletesRequestedLocalEventAndDismissesViewer() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        try await insertEvent(eventID, into: database)
        try await database.write { db in
            try AppState.update {
                $0.organizerID = #bind(eventID.organizerID)
                $0.eventID = #bind(eventID.eventID)
            }
            .execute(db)
        }
        let store: TestStore<OpenMusicEventAppRoot> = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            let initialState = OpenMusicEventAppRoot.State(
                selectedEventIDAtLaunch: eventID
            )
            return TestStore(initialState: initialState) {
                OpenMusicEventAppRoot()
            }
        }

        await store.send(.localEventDeletionRequested(eventID))?.value

        let event = try await database.read { db in
            try OMERecord.Event.where { $0.id.eq(eventID) }.fetchOne(db)
        }
        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }

        #expect(event == nil)
        #expect(appState?.selectedEventID == nil)
        #expect(store.state.eventViewer == nil)
    }

    @Test
    func organizerDetailDeletesLocalEventFromListAfterConfirmation() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID()
        try await insertEvent(eventID, into: database)
        try await insertDefaultCalendarEntry(eventID: eventID, into: database)
        let store: TestStore<OrganizerDetail> = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: OrganizerDetail.State(organizerID: eventID.organizerID)) {
                OrganizerDetail()
            }
        }

        store.send(.deleteEventsButtonTapped([eventID])) {
            $0.deleteEventIDs = [eventID]
            $0.isDeleteEventsConfirmationPresented = true
        }
        await store.send(.deleteEventsConfirmationDeleteButtonTapped)?.value

        let events = try await database.read { db in
            try OMERecord.Event.fetchAll(db)
        }
        let calendarEntries = try await database.read { db in
            try OMERecord.CalendarEntry.fetchAll(db)
        }

        expectNoDifference(events.map(\.id), [])
        expectNoDifference(calendarEntries.map(\.event.localEventID), [])
        #expect(store.state.errorMessage == nil)
        #expect(!store.state.isDeleteEventsConfirmationPresented)
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

private func insertDefaultCalendarEntry(
    eventID: OMERecord.Event.ID,
    into database: any DatabaseWriter
) async throws {
    let calendarID = OMERecord.Calendar.ID(
        ownerID: eventID.organizerID,
        calendarID: OMERecord.Calendar.defaultID
    )
    try await database.write { db in
        try OMERecord.Calendar.insert {
            OMERecord.Calendar.Draft(
                id: calendarID,
                name: "Default"
            )
        }
        .execute(db)
        try OMERecord.CalendarEntry.insert {
            OMERecord.CalendarEntry.Draft(
                id: OMERecord.CalendarEntry.ID(
                    calendarOwnerID: calendarID.ownerID,
                    calendarID: calendarID.calendarID,
                    entryID: OMERecord.ID<OMERecord.CalendarEntry>("entry-1")
                ),
                event: OMERecord.Event.reference(id: eventID),
                createdAt: Date(timeIntervalSince1970: 0),
                pinned: false
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
