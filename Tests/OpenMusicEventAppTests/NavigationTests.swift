import BlueskyActorCache
import ATProto
import Clocks
import ComposableArchitecture2
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
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import Sharing
import SQLiteData
import SourceEditing
import Synchronization
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Testing
import XRPCClient

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventEditors

private let testOrganizerID = OMERecord.Organizer.ID("did:web:example.com")!

private func eventID(_ string: String) -> OMERecord.Event.ID {
    OMERecord.Event.ID(
        organizerID: testOrganizerID,
        eventID: eventLocalID(string)
    )
}

private func eventLocalID(_ string: String) -> OMERecord.ID<OMERecord.Event> {
    OMERecord.ID<OMERecord.Event>(rawValue: ATProto.Record.Key(rawValue: string))
}

private func calendarLocalID(_ string: String) -> OMERecord.ID<OMERecord.Calendar> {
    OMERecord.ID<OMERecord.Calendar>(rawValue: ATProto.Record.Key(rawValue: string))
}

private func calendarEntryLocalID(_ string: String) -> OMERecord.ID<OMERecord.CalendarEntry> {
    OMERecord.ID<OMERecord.CalendarEntry>(rawValue: ATProto.Record.Key(rawValue: string))
}

private func sourceProvenance(
    _ source: String,
    ref: String? = "HEAD"
) -> OMERecord.SourceDatabaseInsertion.SourceProvenance {
    OMERecord.SourceDatabaseInsertion.SourceProvenance(
        kind: .tangled,
        reference: "tangled.org/woody.fm/\(source)",
        ref: ref
    )
}

private func contributorLocalID(_ string: String) -> OMERecord.ID<OMERecord.Contributor> {
    OMERecord.ID<OMERecord.Contributor>(rawValue: ATProto.Record.Key(rawValue: string))
}

private func performanceLocalID(_ string: String) -> OMERecord.ID<OMERecord.Performance> {
    OMERecord.ID<OMERecord.Performance>(rawValue: ATProto.Record.Key(rawValue: string))
}

private func scheduleLocalID(_ string: String) -> OMERecord.ID<OMERecord.Schedule> {
    OMERecord.ID<OMERecord.Schedule>(rawValue: ATProto.Record.Key(rawValue: string))
}

private func stageLocalID(_ string: String) -> OMERecord.ID<OMERecord.Stage> {
    OMERecord.ID<OMERecord.Stage>(rawValue: ATProto.Record.Key(rawValue: string))
}

private func channelLocalID(_ string: String) -> OMERecord.ID<OMERecord.Channel> {
    OMERecord.ID<OMERecord.Channel>(rawValue: ATProto.Record.Key(rawValue: string))
}

private func channelRecordID(
    _ string: String,
    eventID: OMERecord.Event.ID
) -> OMERecord.Channel.ID {
    OMERecord.Channel.ID(
        organizerID: eventID.organizerID,
        eventID: eventID.eventID,
        channelID: channelLocalID(string)
    )
}

private func commsPostID(
    _ string: String,
    channelID: String,
    eventID: OMERecord.Event.ID
) -> CommsPost.ID {
    CommsPost.ID(
        organizerID: eventID.organizerID,
        eventID: eventID.eventID,
        channelID: channelLocalID(channelID),
        postID: CommsPost.PostID(string)
    )
}

private actor ObservationRecorder<Value: Sendable> {
    private var recordedValues: [Value] = []

    var values: [Value] {
        recordedValues
    }

    func record(_ value: Value) {
        recordedValues.append(value)
    }
}

private actor BlueskyProfileRequestRecorder {
    private var recordedActors: [String] = []

    var actors: [String] {
        recordedActors
    }

    func record(_ actor: String) {
        recordedActors.append(actor)
    }
}

private actor SourceRefreshRecorder {
    private var recordedSourceBaselineIDs: [SourceBaselineRecord.ID] = []

    var sourceBaselineIDs: [SourceBaselineRecord.ID] {
        recordedSourceBaselineIDs
    }

    func record(_ sourceBaselineID: SourceBaselineRecord.ID) {
        recordedSourceBaselineIDs.append(sourceBaselineID)
    }
}

private actor SourceRefreshGate {
    private var isOpen = false
    private var hasStarted = false
    private var openWaiters: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func waitForStart() async {
        if hasStarted { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func pauseUntilOpened() async {
        hasStarted = true
        let startWaiters = startWaiters
        self.startWaiters.removeAll()
        startWaiters.forEach { $0.resume() }

        if isOpen { return }
        await withCheckedContinuation { continuation in
            openWaiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let openWaiters = openWaiters
        self.openWaiters.removeAll()
        openWaiters.forEach { $0.resume() }
    }
}

private actor SourceEditModePreparationRecorder {
    private var recordedSourceBaselineIDs: [SourceBaselineRecord.ID] = []
    private var waiters: [CheckedContinuation<[SourceBaselineRecord.ID], Never>] = []

    var sourceBaselineIDs: [SourceBaselineRecord.ID] {
        recordedSourceBaselineIDs
    }

    func record(_ sourceBaselineID: SourceBaselineRecord.ID) {
        recordedSourceBaselineIDs.append(sourceBaselineID)
        let waiters = waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume(returning: recordedSourceBaselineIDs) }
    }

    func waitForRecords() async -> [SourceBaselineRecord.ID] {
        if !recordedSourceBaselineIDs.isEmpty {
            return recordedSourceBaselineIDs
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private func observeAuthorizationRequest(
    from center: AuthorizationRequestCenter
) async -> Task<AuthorizationRequestCenter.Request?, Never> {
    let stream = await center.requests()
    return Task {
        var iterator = stream.makeAsyncIterator()
        while let yieldedRequest = await iterator.next() {
            if let request = yieldedRequest {
                return request
            }
        }
        return nil
    }
}

private actor SourcePatchDatabaseRecorder {
    private var recordedSourceReferences: [String?] = []

    var sourceReferences: [String?] {
        recordedSourceReferences
    }

    func record(_ sourceReference: String?) {
        recordedSourceReferences.append(sourceReference)
    }
}

private struct MissingTestReferenceDatabase: Error {}

private extension SourceReferenceDatabaseClient {
    static var missing: Self {
        Self(
            url: { _ in URL(fileURLWithPath: "/missing-reference.sqlite") },
            prepareForImport: { _ in throw MissingTestReferenceDatabase() },
            existing: { _ in nil }
        )
    }
}

private final class IssueRecordingReporter: @unchecked Sendable, IssueReporter {
    private let lock = NSLock()
    private var recordedMessages: [String] = []

    var messages: [String] {
        lock.withLock { recordedMessages }
    }

    func reportIssue(
        _ message: @autoclosure () -> String?,
        severity: IssueSeverity,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        lock.withLock {
            recordedMessages.append(message() ?? "")
        }
    }

    func reportIssue(
        _ error: any Error,
        _ message: @autoclosure () -> String?,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        lock.withLock {
            recordedMessages.append(
                "Caught error: \(error)"
                    + (message().map { ": \($0)" } ?? "")
            )
        }
    }
}

@MainActor
@Suite(
    .dependencies {
        $0.uuid = .incrementing
    },
    .tcaExhaustivity(.off)
)
struct NavigationTests {
    @Test(
        arguments: [
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1",
                AppRoute.event(eventID("event-1"), nil)
            ),
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/schedule",
                AppRoute.event(eventID("event-1"), .schedule)
            ),
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/contributors",
                AppRoute.event(eventID("event-1"), .contributors)
            ),
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/contributors/artist-1",
                AppRoute.event(eventID("event-1"), .contributor(contributorLocalID("artist-1")))
            ),
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/stages",
                AppRoute.event(eventID("event-1"), .stages)
            ),
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/stages/stage-1",
                AppRoute.event(eventID("event-1"), .stage(stageLocalID("stage-1")))
            ),
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/performances/performance-1",
                AppRoute.event(eventID("event-1"), .performance(performanceLocalID("performance-1")))
            ),
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/workspace",
                AppRoute.event(eventID("event-1"), .workspace)
            ),
            (
                "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/settings",
                AppRoute.event(eventID("event-1"), .settings)
            ),
        ]
    )
    func appRouteRoundTrips(urlString: String, expected: AppRoute) throws {
        let url = try #require(URL(string: urlString))
        let route = try #require(AppRoute(url: url))

        #expect(route == expected)
        #expect(route.path == url.path(percentEncoded: true))
    }

    @Test
    func appRouteAcceptsLegacyEditEventPathAsWorkspace() throws {
        let url = try #require(URL(
            string: "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/edit"
        ))
        #expect(AppRoute(url: url) == AppRoute.event(eventID("event-1"), .workspace))
    }

    @Test(
        arguments: [
            "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/people",
            "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/participants/artist-1",
        ]
    )
    func appRouteRejectsOldContributorURLs(urlString: String) throws {
        let url = try #require(URL(string: urlString))
        #expect(AppRoute(url: url) == nil)
    }

    @Test(
        arguments: [
            "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/performances",
            "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/performances/opening/extra",
            "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/performance/opening",
        ]
    )
    func appRouteRejectsIncompleteOrUnsupportedPerformanceURLs(urlString: String) throws {
        let url = try #require(URL(string: urlString))
        #expect(AppRoute(url: url) == nil)
    }

    @Test
    func navigationRequestSelectsEventAndMountsViewer() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let store = makeRootHarnessStore(database: database, eventID: eventID)

        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            store.send(.root(.handleNavigationRequest(.event(eventID, nil))))
        }

        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }
        #expect(appState?.selectedEventID == eventID)
        #expect(store.state.root.eventViewer?.content.content.eventID == eventID)
        #expect(
            store.state.root.eventViewer?.content.content.pendingScheduleLaunchAction == nil
        )
    }

    #if !os(Android)
    @Test
    func navigationRequestReplacesMountedEventViewer() async throws {
        let database = try makePreparedDatabase()
        let firstEventID = eventID("event-1")
        let secondEventID = eventID("event-2")
        let store = makeRootHarnessStore(database: database, eventID: firstEventID)

        store.send(.root(.handleNavigationRequest(.event(firstEventID, nil))))
        #expect(store.state.root.eventViewer?.content.content.eventID == firstEventID)

        store.send(.root(.handleNavigationRequest(.event(secondEventID, nil))))

        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }
        #expect(appState?.selectedEventID == secondEventID)
        #expect(store.state.root.eventViewer?.content.content.eventID == secondEventID)
    }
    #endif

    @Test
    func navigationRequestSelectsContributorContributorsDestination() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("contributor-1")
        let store = makeRootHarnessStore(database: database, eventID: eventID)

        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            store.send(.root(.handleNavigationRequest(.event(eventID, .contributor(contributorID)))))
        }

        #expect(
            store.state.root.eventViewer?.content.content.selectedFeature
                == .contributors
        )
        #expect(
            store.state.root.eventViewer?.content.content.contributorsViewer?
                .destination?.contributorDetail?.contributorID == contributorID
        )
    }

    @Test
    func navigationRequestSelectsStageDestination() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let stageID = stageLocalID("stage-1")
        let store = makeRootHarnessStore(database: database, eventID: eventID)

        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            store.send(.root(.handleNavigationRequest(.event(eventID, .stage(stageID)))))
        }

        #expect(
            store.state.root.eventViewer?.content.content.selectedFeature
                == .stages
        )
        #expect(
            store.state.root.eventViewer?.content.content.stagesViewer?
                .destination?.stageDetail?.stageID == stageID
        )
    }

    @Test
    func performanceDeepLinkPresentsPerformanceDetail() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let performanceID = performanceLocalID("opening")
        let date = try #require(LocalDate("2026-08-07"))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "friday", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "opening",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Opening"
            )
        }

        let store = makeRootHarnessStore(database: database, eventID: eventID)
        let url = try #require(URL(
            string: "https://openmusicevent.app/organizers/did%3Aweb%3Aexample.com/events/event-1/performances/opening"
        ))
        let route = try #require(AppRoute(url: url))

        store.send(.root(.openRoute(route)))

        #expect(
            store.state.root.eventViewer?.content.content.selectedFeature
                == .schedule(.schedule)
        )
        let scheduleViewer = try #require(
            store.state.root.eventViewer?.content.content.scheduleViewers.first {
                $0.state.scheduleDivision == .schedule
            }
        )
        let performanceDetail = try #require(scheduleViewer.state.destination?.performanceDetail)
        #expect(performanceDetail.performanceID == performanceID)
        #expect(performanceDetail.performance?.title == "Opening")
    }

    @Test
    func performanceDeepLinkPreservesIDWhenPerformanceIsUnavailable() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let performanceID = performanceLocalID("missing")
        let store = makeRootHarnessStore(database: database, eventID: eventID)

        store.send(.root(.openRoute(.event(eventID, .performance(performanceID)))))

        let scheduleViewer = try #require(
            store.state.root.eventViewer?.content.content.scheduleViewers.first {
                $0.state.scheduleDivision == .schedule
            }
        )
        let performanceDetail = try #require(scheduleViewer.state.destination?.performanceDetail)
        #expect(performanceDetail.performanceID == performanceID)
        #expect(performanceDetail.performance == nil)
    }

    @Test
    func workspaceNavigationRequestsAuthoringForItsWorkspace() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("authorized-workspace-navigation")
        let sourceProvenance = sourceProvenance("authorized-workspace-navigation")
        let authorizationRequests = Mutex<[EditingWorkspaceRecord.ID]>([])
        let preparationRequests = Mutex<[EditingWorkspaceRecord.ID]>([])
        let sourcePreparationGate = SourceRefreshGate()

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Authorized Workspace")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 1_700)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0[AuthoringPolicyClient.self] = AuthoringPolicyClient { workspaceID in
                authorizationRequests.withLock { $0.append(workspaceID) }
                return .granted(principal: .local, role: .owner)
            }
            $0[WorkspacePreparationClient.self] = WorkspacePreparationClient(
                open: { workspaceID in
                    WorkspaceContext(
                        id: workspaceID,
                        sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: database)
                    )
                },
                prepareSource: { workspaceID in
                    preparationRequests.withLock { $0.append(workspaceID) }
                    await sourcePreparationGate.pauseUntilOpened()
                }
            )
        } operation: {
            TestStore(initialState: RootHarness.State()) {
                RootHarness()
            }
        }

        let task = store.send(.root(.handleNavigationRequest(.event(eventID, .workspace))))
        #expect(
            store.state.root.eventViewer?.content.content.pendingAuthoringEntry
                == .target(.workspace)
        )
        await sourcePreparationGate.waitForStart()

        let workspaceID = EditingWorkspaceRecord.ID(
            sourceBaselineID: SourceBaselineRecord.ID(source: sourceProvenance)
        )
        expectNoDifference(authorizationRequests.withLock { $0 }, [workspaceID])
        expectNoDifference(preparationRequests.withLock { $0 }, [workspaceID])
        #expect(
            store.state.root.eventViewer?.content.access
                == .authoring(.owner)
        )
        #expect(
            store.state.root.eventViewer?.content.content.installedFeatures
                .contains(.workspace) == true
        )
        #expect(
            store.state.root.eventViewer?.content.content.selectedFeature
                == .workspace
        )
        #expect(
            store.state.root.eventViewer?.content.content.eventWorkspace?.eventID
                == eventID
        )
        #expect(
            store.state.root.eventViewer?.content.sourcePreparation.isRunning == true
        )

        await sourcePreparationGate.open()
        await task?.value
        await waitUntil {
            store.state.root.eventViewer?.content.sourcePreparation.isRunning == false
        }
    }

    @Test
    func teamWorkspaceGrantCarriesIntoEventNavigation() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("source-workspace-authoring-navigation")
        let sourceProvenance = sourceProvenance("source-workspace-authoring-navigation")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Source Workspace Authoring")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 1_800)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
        }

        try await withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0[AuthoringPolicyClient.self] = .authoring
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            @Bindable var store = Store(
                initialState: OpenMusicEventAppRoot.State()
            ) {
                OpenMusicEventAppRoot()
            }
            @Bindable var browserStore = store.spawn(\.browser)
            @Bindable var myEventsStore = browserStore.spawn(\.myEvents)

            myEventsStore.send(.didTapTeamWorkspace(sourceBaselineID))
            let teamWorkspaceStore = try #require(
                myEventsStore.scope(\.teamWorkspaceDetail, action: \.teamWorkspaceDetail)
            )
            let teamWorkspaceAuthoringStore = teamWorkspaceStore.scope(
                \.content,
                action: \.content
            )

            await teamWorkspaceAuthoringStore.send(.enterButtonTapped)?.value
            await waitUntil {
                teamWorkspaceAuthoringStore.access.canEditContent
            }
            let teamWorkspaceDetailStore = teamWorkspaceAuthoringStore.scope(
                \.content,
                action: \.content
            )
            await teamWorkspaceDetailStore.send(.eventButtonTapped(eventID))?.value

            let eventAuthoringStore = try #require(
                $store.scope(\.destination, action: \.destination).eventViewer.wrappedValue
            )
            let eventWorkspaceAuthoringStore = eventAuthoringStore.scope(
                \.content,
                action: \.content
            )
            let eventViewerStore = eventWorkspaceAuthoringStore.scope(
                \.content,
                action: \.content
            )
            #expect(eventViewerStore.eventID == eventID)
            #expect(
                eventWorkspaceAuthoringStore.access
                    == .authoring(.owner)
            )
            #expect(eventViewerStore.installedFeatures.contains(.workspace))
            #expect(eventViewerStore.installedFeatures.contains(.settings))
        }
    }

    @Test
    func browseEventTapRemainsAttendeeWithoutExplicitAuthoringEntry() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("source-event-list-authoring")
        let sourceProvenance = sourceProvenance("source-event-list-authoring")
        let workspaceID = EditingWorkspaceRecord.ID(
            sourceBaselineID: SourceBaselineRecord.ID(source: sourceProvenance)
        )
        let admissionRequests = Mutex<[EditingWorkspaceRecord.ID]>([])

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Source Event List Authoring")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 1_900)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
        }

        try await withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0[AuthoringPolicyClient.self] = AuthoringPolicyClient { workspaceID in
                admissionRequests.withLock { $0.append(workspaceID) }
                return .granted(principal: .local, role: .owner)
            }
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            @Bindable var store = Store(initialState: OpenMusicEventAppRoot.State()) {
                OpenMusicEventAppRoot()
            }
            @Bindable var browseStore = store.spawn(\.browser).spawn(\.browse)

            await browseStore.send(.eventButtonTapped(eventID))?.value

            let eventAuthoringStore = try #require(
                $store.scope(\.destination, action: \.destination).eventViewer.wrappedValue
            )
            let authoringStore = eventAuthoringStore.scope(\.content, action: \.content)
            let eventViewerStore = authoringStore.scope(\.content, action: \.content)
            await waitUntil {
                authoringStore.canEnterAuthoring
            }
            #expect(eventViewerStore.eventID == eventID)
            #expect(authoringStore.access == .attendee)
            #expect(authoringStore.canEnterAuthoring)
            #expect(!eventViewerStore.installedFeatures.contains(.workspace))
            expectNoDifference(admissionRequests.withLock { $0 }, [workspaceID])
        }
    }

    @Test
    func eventViewerConsumesContributorNavigationFromSearchDescendant() async throws {
        let contributorID = contributorLocalID("contributor-1")
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let store = try makeEventViewerHarnessStore(database: database)

        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            await store.send(
                to: \.eventViewer.eventSearch,
                EventSearch.Action.openTarget(.contributor(contributorID))
            )?.value
        }
        await Task.yield()

        #expect(
            store.state.eventViewer.eventSearch.state.destination?.contributorDetail?.state
                .contributorID == contributorID
        )
        #expect(store.state.lastRequest == nil)
    }

    @Test
    func eventViewerSearchUsesMountedEventIDForContributorNavigation() async throws {
        let selectedEventID = eventID("event-1")
        let ambientEventID = eventID("other-event")
        let contributorID = contributorLocalID("contributor-1")
        let database = try makePreparedDatabase()
        let store = try makeEventViewerHarnessStore(
            eventID: selectedEventID,
            defaultEventID: ambientEventID,
            database: database
        )

        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = ambientEventID
        } operation: {
            await store.send(
                to: \.eventViewer.eventSearch,
                EventSearch.Action.openTarget(.contributor(contributorID))
            )?.value
        }
        await Task.yield()

        #expect(
            store.state.eventViewer.eventSearch.state.destination?.contributorDetail?.state
                .eventID == selectedEventID
        )
    }

    @Test
    func eventViewerConsumesStageNavigationFromSearchDescendant() async throws {
        let stageID = stageLocalID("stage-1")
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let store = try makeEventViewerHarnessStore(database: database)

        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            await store.send(
                to: \.eventViewer.eventSearch,
                EventSearch.Action.openTarget(.stage(stageID))
            )?.value
        }
        await Task.yield()

        #expect(
            store.state.eventViewer.eventSearch.state.destination?.stageDetail?.state.stageID
                == stageID
        )
        #expect(store.state.lastRequest == nil)
    }

    @Test
    func myEventsPostsNavigationRequest() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        try await database.write { db in
            try OMERecord.Organizer.insert {
                OMERecord.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            let eventDraft = CreateEvent.makeEventDraft(
                id: eventID,
                name: "Test Event",
                startDate: nil,
                endDate: nil
            )
            try OMERecord.Event.insert {
                eventDraft
            }
            .execute(db)
        }
        let events = try await database.read { db in
            try OMERecord.Event.fetchAll(db)
        }
        let event = try #require(events.first)

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: MyEventsEventHarness.State()) {
                MyEventsEventHarness()
            }
        }

        store.send(.myEvents(.didTapEvent(event))) {
            $0.lastRequest = .event(eventID, nil)
        }
        #expect(store.state.lastRequest == .event(eventID, nil))
    }

    @Test
    func myEventsTeamWorkspaceTapPresentsTeamWorkspaceDetail() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("downloaded-event")
        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/woody.fm/wicked-woods-ome",
            ref: "HEAD"
        )
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        try database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Downloaded Event")
            try Self.insertEventOrganizer(db, eventID: eventID, organizerID: testOrganizerID)
            try SourceBaselineRecord.insert {
                SourceBaselineRecord(
                    source: sourceProvenance,
                    databaseFileName: "baseline.sqlite",
                    importedAt: Date(timeIntervalSince1970: 0)
                )
            }
            .execute(db)
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceBaselineID: sourceBaselineID,
                    sourceKind: sourceProvenance.kind,
                    sourceReference: sourceProvenance.reference,
                    ref: sourceProvenance.ref,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: "downloaded-event"
                )
            }
            .execute(db)
        }
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: MyEventsEventHarness.State()) {
                MyEventsEventHarness()
            }
        }

        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            store.send(.myEvents(.didTapTeamWorkspace(sourceBaselineID)))
        }
        #expect(
            store.state.myEvents.teamWorkspaceDetail?.content.content.sourceBaselineID
                == sourceBaselineID
        )
    }

    @Test
    func myEventsExposesMalformedTeamWorkspaceFetchLoadError() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("malformed-team-workspace-event")
        let sourceProvenance = sourceProvenance("malformed-team-workspace")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Malformed Team Workspace Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 1_700)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
            try db.execute(
                sql: #"UPDATE "sourceBaselines" SET "sourceKind" = ? WHERE "id" = ?"#,
                arguments: ["inferred", sourceBaselineID.rawValue]
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: MyEvents.State()) {
                MyEvents()
            }
        }

        #expect(store.state.teamWorkspaces.isEmpty)
        expectNoDifference(
            store.state.fetchLoadFailures.map(\.label),
            ["MyEvents.teamWorkspaces"]
        )
        let failure = try #require(store.state.fetchLoadFailures.first)
        #expect(!String(describing: failure.error).isEmpty)
    }

    @Test
    func teamWorkspaceDetailLoadsLiveCalendarFromSourceProvenance() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("live-calendar-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let importedAt = Date(timeIntervalSince1970: 1_000)
        let calendarID = OrganizerDetail.defaultCalendarID(organizerID: testOrganizerID)
        let eventID = eventID("live-event")
        let entryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("live-event")
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Live Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: importedAt
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
            try Self.insertCalendar(
                db,
                id: calendarID,
                name: "Live Calendar",
                description: "Live calendar description"
            )
            try Self.insertCalendarEntry(
                db,
                id: entryID,
                event: OMERecord.Event.reference(id: eventID),
                createdAt: importedAt,
                note: "Live note",
                pinned: true
            )
        }

        let store = try makeTeamWorkspaceDetailStore(
            sourceBaselineID: sourceBaselineID,
            database: database
        )

        let displayEntries = TeamWorkspaceDetail.displayEntries(
            calendarEntries: store.state.calendarEntries,
            events: store.state.events,
            sourceBaseline: store.state.sourceBaseline
        )

        #expect(store.state.calendar?.name == "Live Calendar")
        #expect(store.state.calendar?.description == "Live calendar description")
        #expect(displayEntries.map(\.id) == [entryID])
        #expect(displayEntries.first?.note == "Live note")
        #expect(displayEntries.first?.pinned == true)
        #expect(store.state.events.map(\.name) == ["Live Event"])
    }

    @Test
    func teamWorkspaceDetailEditCalendarPresentsLiveCalendarEditor() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("editable-live-calendar-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let calendarID = OrganizerDetail.defaultCalendarID(organizerID: testOrganizerID)
        let eventID = eventID("editable-live-event")

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Editable Live Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 1_500)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
            try Self.insertCalendar(db, id: calendarID, name: "Editable Live Calendar")
        }

        let store = try makeTeamWorkspaceDetailStore(
            sourceBaselineID: sourceBaselineID,
            database: database
        )

        store.send(.editButtonTapped)

        #expect(store.state.editCalendar?.calendarID == calendarID)
    }

    @Test
    func teamWorkspaceDetailAddEventPresentsWorkspaceCreateEvent() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("add-event-live-calendar-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let calendarID = OrganizerDetail.defaultCalendarID(organizerID: testOrganizerID)
        let eventID = eventID("add-event-live-event")

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Add Event Live Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 1_550)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
            try Self.insertCalendar(db, id: calendarID, name: "Add Event Live Calendar")
        }

        let store = try makeTeamWorkspaceDetailStore(
            sourceBaselineID: sourceBaselineID,
            database: database
        )

        store.send(.addEventButtonTapped)

        guard case let .createEvent(createEvent)? = store.state.destination else {
            Issue.record("Expected team workspace detail to present create event.")
            return
        }
        #expect(createEvent.state.sourceBaselineID == sourceBaselineID)
        #expect(createEvent.state.calendarID == calendarID)
    }

    @Test
    func teamWorkspaceDetailManageSourceMountsLiveWorkspaceDatabase() async throws {
        let repositoryURL = try temporarySourceRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try writeMinimalSourceRepository(at: repositoryURL)

        let workingDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-live-workspace-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: workingDirectoryURL) }
        try FileManager.default.createDirectory(
            at: workingDirectoryURL,
            withIntermediateDirectories: true
        )
        let workingDatabaseURL = workingDirectoryURL
            .appending(path: "open-music-event.sqlite")
        let database = try makeFileBackedPreparedDatabase(at: workingDatabaseURL)

        let referenceDatabaseURL = try SourceReferenceDatabaseClient.referenceDatabaseURL(
            repositoryURL: repositoryURL
        )
        let referenceDatabase = try makeReferenceDatabase(at: referenceDatabaseURL)
        let organizerID = try #require(OMERecord.Organizer.ID("did:plc:cqqtuv75m7e5s4uj6nw4czyu"))
        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .tangled,
            reference: "tangled.org/woody.fm/wicked-woods-ome",
            ref: "HEAD"
        )
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let workspaceID = EditingWorkspaceRecord.ID(sourceBaselineID: sourceBaselineID)
        let calendarID = OrganizerDetail.defaultCalendarID(organizerID: organizerID)
        let eventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: eventLocalID("wicked-woods-ome-2025")
        )
        let importedAt = Date(timeIntervalSince1970: 1_788_000_000)
        let recorder = SourceEditModePreparationRecorder()

        try await database.write { db in
            try Self.insertLiveWorkspaceSourceFixture(
                db,
                organizerID: organizerID,
                calendarID: calendarID,
                eventID: eventID,
                sourceProvenance: sourceProvenance,
                importedAt: importedAt
            )
        }
        try referenceDatabase.write { db in
            try Self.insertLiveWorkspaceSourceFixture(
                db,
                organizerID: organizerID,
                calendarID: calendarID,
                eventID: eventID,
                sourceProvenance: sourceProvenance,
                importedAt: importedAt
            )
        }

        let workspace = try await withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
            $0.sourceEditModePreparation = SourceEditModePreparationClient { sourceBaselineID in
                await recorder.record(sourceBaselineID)
            }
            $0.sourceRepositoryStorage = SourceRepositoryStorageClient(
                repositoryURL: { _ in repositoryURL },
                store: { _, _ in repositoryURL },
                remove: { _ in }
            )
            $0.sourceWorkspaceDatabase = .fileBacked(workingDirectory: workingDirectoryURL)
            $0[WorkspacePreparationClient.self] = .live
        } operation: {
            @Dependency(WorkspacePreparationClient.self) var preparation
            let workspace = try preparation.open(workspaceID)
            try await preparation.prepareSource(workspaceID)
            return workspace
        }
        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
            $0.useWorkspaceContext(
                workspace.mounting(grant: SharedReader(value: nil))
            )
        } operation: {
            TestStore(initialState: TeamWorkspaceDetail.State(sourceBaselineID: sourceBaselineID)) {
                TeamWorkspaceDetail()
            }
        }

        store.send(.manageSourceButtonTapped)

        #expect(await recorder.sourceBaselineIDs == [sourceBaselineID])
        let teamWorkspaceEditor = try #require(store.state.teamWorkspaceEditor)
        #expect(teamWorkspaceEditor.sourceBaselineID == sourceBaselineID)
        #expect(teamWorkspaceEditor.calendarID == calendarID)
        #expect(teamWorkspaceEditor.sourceBaseline?.id == sourceBaselineID)
        await waitUntil {
            store.state.teamWorkspaceEditor?.sourceWorkspaceSummary.availability == .available
        }
        expectNoDifference(
            store.state.teamWorkspaceEditor?.sourceWorkspaceSummary.totalCount,
            0
        )
    }

    @Test
    func sourceWorkspaceDatabaseDoesNotRepairMissingReferenceDatabase() async throws {
        let repositoryURL = try temporarySourceRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try writeMinimalSourceRepository(at: repositoryURL)
        let workingDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-missing-reference-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: workingDirectoryURL) }
        try FileManager.default.createDirectory(
            at: workingDirectoryURL,
            withIntermediateDirectories: true
        )
        let database = try makePreparedDatabase()
        let sourceProvenance = OMERecord.SourceDatabaseInsertion.SourceProvenance(
            kind: .local,
            reference: repositoryURL.path(percentEncoded: false),
            ref: nil
        )
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let workspaceID = EditingWorkspaceRecord.ID(sourceBaselineID: sourceBaselineID)
        let referenceDatabaseURL = try SourceReferenceDatabaseClient.referenceDatabaseURL(
            repositoryURL: repositoryURL
        )

        try await database.write { db in
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 1_600)
            )
        }

        #expect(!FileManager.default.fileExists(atPath: referenceDatabaseURL.path))

        let error = #expect(throws: SourceWorkspaceDatabaseError.self) {
            try withDependencies {
                $0.context = .test
                $0.defaultDatabase = database
            } operation: {
                try SourceWorkspaceDatabaseClient
                    .fileBacked(workingDirectory: workingDirectoryURL)
                    .workspace(workspaceID)
            }
        }

        #expect(error == .workspaceReferenceDatabaseMissing(workspaceID))
        #expect(!FileManager.default.fileExists(atPath: referenceDatabaseURL.path))
    }

    @Test
    func teamWorkspaceDetailKeepsAppDatabaseWhenRoutingEditorAction() async throws {
        let database = try makePreparedDatabase()
        let workspaceDatabase = try makePreparedDatabase()
        let sourceBaselineID = SourceBaselineRecord.ID(rawValue: "source")
        let workspaceID = EditingWorkspaceRecord.ID(sourceBaselineID: sourceBaselineID)
        let calendarID = OrganizerDetail.defaultCalendarID(organizerID: testOrganizerID)
        let reporter = IssueRecordingReporter()
        let recorder = SourcePatchDatabaseRecorder()
        let appSourceReference = "app://routed-source-management"
        let patch = SourcePatch()

        try await database.write { db in
            try SourceBaselineRecord.insert {
                SourceBaselineRecord(
                    id: sourceBaselineID,
                    sourceKind: .local,
                    sourceReference: appSourceReference,
                    ref: "HEAD",
                    databaseFileName: "app-baseline.sqlite",
                    importedAt: Date(timeIntervalSince1970: 1_800)
                )
            }
            .execute(db)
        }
        try await workspaceDatabase.write { db in
            try SourceBaselineRecord.insert {
                SourceBaselineRecord(
                    id: sourceBaselineID,
                    sourceKind: .local,
                    sourceReference: "workspace://routed-source-management",
                    ref: "HEAD",
                    databaseFileName: "workspace-baseline.sqlite",
                    importedAt: Date(timeIntervalSince1970: 1_900)
                )
            }
            .execute(db)
        }
        let workspace = WorkspaceContext(
            id: workspaceID,
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: workspaceDatabase)
        )
        let grant = Shared<AuthoringGrant?>(
            value: AuthoringGrant(principal: .local, role: .owner, workspace: workspace)
        )

        let store = withIssueReporters([reporter]) {
            withDependencies {
                $0.context = .test
                $0.defaultDatabase = database
                $0.sourceReferenceDatabase = .missing
                $0.useWorkspaceContext(
                    workspace.mounting(grant: SharedReader(grant))
                )
                $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] =
                    SourcePatchGenerator { request in
                        @Dependency(\.defaultDatabase) var database
                        let sourceReference = try await database.read { db in
                            try SourceBaselineRecord
                                .where { $0.id.eq(request.sourceBaselineID) }
                                .fetchOne(db)?
                                .sourceReference
                        }
                        await recorder.record(sourceReference)
                        return patch
                    }
            } operation: {
                var state = TeamWorkspaceDetail.State(sourceBaselineID: sourceBaselineID)
                state.teamWorkspaceEditor = SourceWorkspace.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
                return TestStore(initialState: state) {
                    TeamWorkspaceDetail()
                }
            }
        }

        await withIssueReporters([reporter]) {
            let task = store.send(.teamWorkspaceEditor(.generateSourcePatchButtonTapped)) {
                $0.teamWorkspaceEditor?.sourcePatchStatus = .generating
            }
            await store.receive(
                \.teamWorkspaceEditor,
                .matching { action in
                    if case .sourcePatchGenerationResponse(.success) = action {
                        return true
                    }
                    return false
                },
                timeout: .seconds(1)
            ) {
                $0.teamWorkspaceEditor?.sourcePatchStatus = .generated(patch)
            }
            await task?.value
        }

        #expect(store.state.teamWorkspaceEditor?.sourceBaselineID == sourceBaselineID)
        let sourceReferences = await recorder.sourceReferences
        expectNoDifference(sourceReferences, [appSourceReference])
        #expect(reporter.messages.isEmpty)
    }

    @Test
    func eventViewerMountsEventWorkspaceFromWorkspaceContext() throws {
        let workspaceDatabase = try makePreparedDatabase()
        let eventID = eventID("event-workspace-source-mount")
        let reporter = IssueRecordingReporter()
        let workspaceID = EditingWorkspaceRecord.ID(localEventID: eventID)
        let workspace = WorkspaceContext(
            id: workspaceID,
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: workspaceDatabase)
        )
        let grant = Shared<AuthoringGrant?>(
            value: AuthoringGrant(principal: .local, role: .owner, workspace: workspace)
        )

        let store = withIssueReporters([reporter]) {
            withDependencies {
                $0.context = .test
                $0.defaultDatabase = workspaceDatabase
                $0.defaultEventID = eventID
                $0.useWorkspaceContext(
                    workspace.mounting(grant: SharedReader(grant))
                )
            } operation: {
                TestStore(initialState: EventViewerHarness.State(eventID: eventID)) {
                    EventViewerHarness()
                }
            }
        }

        #expect(store.state.eventViewer.authoringAccess == .authoring(.owner))
        #expect(store.state.eventViewer.eventWorkspace?.eventID == eventID)
        #expect(reporter.messages.isEmpty)
    }

    @Test
    func teamWorkspaceAuthoringRoutesAuthorizationThroughAppSheet() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("auth-source-management")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let workspaceID = EditingWorkspaceRecord.ID(sourceBaselineID: sourceBaselineID)
        let calendarID = OrganizerDetail.defaultCalendarID(organizerID: testOrganizerID)
        let eventID = eventID("auth-source-management-event")
        let requirement = OpenMusicEventOAuth.tangledPublicKeyAuthRequirement
        let authorizationCenter = AuthorizationRequestCenter()

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Authorized Source Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 1_600)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
            try Self.insertCalendar(db, id: calendarID, name: "Authorized Source Calendar")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.openMusicEventAuthorizationRequests = OpenMusicEventAuthorizationRequests(
                center: authorizationCenter
            )
            $0.oauthAuthorizationBroker = authorizationCenter.broker
            $0[AuthoringPolicyClient.self] = AuthoringPolicyClient { requestedWorkspaceID in
                #expect(requestedWorkspaceID == workspaceID)
                @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
                try await authorizationBroker.authorize(requirement)
                return .granted(principal: .local, role: .owner)
            }
        } operation: {
            TestStore(
                initialState: Authoring<TeamWorkspaceDetail>.State(workspaceID: workspaceID) {
                    TeamWorkspaceDetail.State(sourceBaselineID: sourceBaselineID)
                }
            ) {
                Authoring { TeamWorkspaceDetail() }
            }
        }

        let task = store.send(.enterButtonTapped)
        let requests = await authorizationCenter.requests()
        for await request in requests {
            guard let request else { continue }
            #expect(request.requirement == requirement)
            await authorizationCenter.succeed()
            break
        }
        await task?.value

        #expect(store.state.access == .authoring(.owner))
        store.send(.content(.manageSourceButtonTapped))
        #expect(store.state.content.teamWorkspaceEditor?.sourceBaselineID == sourceBaselineID)
        #expect(store.state.content.teamWorkspaceEditor?.calendarID == calendarID)
    }

    @Test
    func teamWorkspaceDetailScopesLiveCalendarEntriesToSourceProvenance() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("first-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let importedAt = Date(timeIntervalSince1970: 2_000)
        let firstEventID = eventID("first-source-event")
        let otherEventID = eventID("other-source-event")
        let calendarID = OrganizerDetail.defaultCalendarID(organizerID: testOrganizerID)

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: firstEventID, name: "First Source Event")
            try Self.insertEvent(db, id: otherEventID, name: "Other Source Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: importedAt
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: firstEventID,
                sourceProvenance: sourceProvenance
            )
            try Self.insertCalendar(db, id: calendarID, name: "Live Calendar")
            try Self.insertCalendarEntry(
                db,
                id: .init(
                    calendarOwnerID: testOrganizerID,
                    calendarID: OMERecord.Calendar.defaultID,
                    entryID: calendarEntryLocalID("first-source-event")
                ),
                event: OMERecord.Event.reference(id: firstEventID),
                createdAt: importedAt
            )
            try Self.insertCalendarEntry(
                db,
                id: .init(
                    calendarOwnerID: testOrganizerID,
                    calendarID: OMERecord.Calendar.defaultID,
                    entryID: calendarEntryLocalID("other-source-event")
                ),
                event: OMERecord.Event.reference(id: otherEventID),
                createdAt: Date(timeIntervalSince1970: 3_000)
            )
        }

        let store = try makeTeamWorkspaceDetailStore(
            sourceBaselineID: sourceBaselineID,
            database: database
        )
        let displayEntries = TeamWorkspaceDetail.displayEntries(
            calendarEntries: store.state.calendarEntries,
            events: store.state.events,
            sourceBaseline: store.state.sourceBaseline
        )

        #expect(store.state.calendar?.name == "Live Calendar")
        #expect(displayEntries.map(\.id.entryID) == [
            calendarEntryLocalID("first-source-event")
        ])
        #expect(store.state.events.map(\.id) == [firstEventID])
    }

    @Test
    func teamWorkspaceDetailSynthesizesRowsFromProvenanceWhenLiveCalendarEntryIsMissing() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("missing-reference-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let importedAt = Date(timeIntervalSince1970: 4_000)
        let eventID = eventID("fallback-event")

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Fallback Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                databaseFileName: "missing-reference.sqlite",
                importedAt: importedAt
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
        }

        let store = try makeTeamWorkspaceDetailStore(
            sourceBaselineID: sourceBaselineID,
            database: database
        )
        let displayEntries = TeamWorkspaceDetail.displayEntries(
            calendarEntries: store.state.calendarEntries,
            events: store.state.events,
            sourceBaseline: store.state.sourceBaseline
        )

        #expect(store.state.calendar == nil)
        #expect(store.state.canEditCalendar == true)
        #expect(displayEntries.map(\.id.entryID) == [
            calendarEntryLocalID("fallback-event")
        ])
        #expect(displayEntries.first?.createdAt == importedAt)
        #expect(displayEntries.first?.pinned == false)
        #expect(store.state.events.map(\.id) == [eventID])

        store.send(.editButtonTapped)
        #expect(
            store.state.editCalendar?.calendarID
            == OrganizerDetail.defaultCalendarID(organizerID: testOrganizerID)
        )
    }

    @Test
    func teamWorkspaceDetailEventTapPostsNavigationRequest() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("source-event")
        let sourceProvenance = sourceProvenance("navigation-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        try database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Source Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 0)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: TeamWorkspaceDetailHarness.State(sourceBaselineID: sourceBaselineID)
            ) {
                TeamWorkspaceDetailHarness()
            }
        }

        store.send(.teamWorkspaceDetail(.eventButtonTapped(eventID))) {
            $0.lastRequest = .event(eventID, nil)
        }
        #expect(store.state.lastRequest == .event(eventID, nil))
    }

    @Test
    func teamWorkspaceDetailPullToRefreshRefreshesSourceBaseline() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("events-page-refresh-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let recorder = SourceRefreshRecorder()
        try await database.write { db in
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 0)
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourceDataRefresh = SourceDataRefreshClient { sourceBaselineID in
                await recorder.record(sourceBaselineID)
            }
        } operation: {
            TestStore(initialState: TeamWorkspaceDetail.State(sourceBaselineID: sourceBaselineID)) {
                TeamWorkspaceDetail()
            }
        }

        await store.send(.didPullToRefresh)?.value

        let sourceBaselineIDs = await recorder.sourceBaselineIDs
        expectNoDifference(sourceBaselineIDs, [sourceBaselineID])
    }

    @Test
    func teamWorkspaceEditorShowsSourceRefreshProgressWhileRefreshIsRunning() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("team-workspace-refresh-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let calendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let gate = SourceRefreshGate()
        let recorder = SourceRefreshRecorder()

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourceDataRefresh = SourceDataRefreshClient { sourceBaselineID in
                await recorder.record(sourceBaselineID)
                await gate.pauseUntilOpened()
            }
        } operation: {
            TestStore(
                initialState: SourceWorkspace.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            ) {
                SourceWorkspace()
            }
        }

        let refreshTask = store.send(.refreshSourceButtonTapped) {
            $0.isRefreshingSource = true
        }
        await gate.waitForStart()
        #expect(store.state.isRefreshingSource)

        store.send(.refreshSourceButtonTapped)

        await gate.open()
        await refreshTask?.value

        #expect(store.state.isRefreshingSource == false)
        let sourceBaselineIDs = await recorder.sourceBaselineIDs
        expectNoDifference(sourceBaselineIDs, [sourceBaselineID])
    }

    @Test
    func eventInfoPullToRefreshPostsSourceDataRefreshRequest() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("refresh-source-event")
        let sourceProvenance = sourceProvenance("refresh-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Refresh Source Event")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 0)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EventInfoRefreshHarness.State(eventID: eventID)) {
                EventInfoRefreshHarness()
            }
        }

        await store.send(.eventInfo(.didPullToRefresh))?.value
        #expect(
            store.state.lastRefreshRequest == SourceDataRefreshRequest(
                eventID: eventID,
                sourceBaselineID: sourceBaselineID
            )
        )
    }

    @Test
    func eventInfoPullToRefreshNoOpsForNonSourceEvent() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("plain-event")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Plain Event")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EventInfoRefreshHarness.State(eventID: eventID)) {
                EventInfoRefreshHarness()
            }
        }

        await store.send(.eventInfo(.didPullToRefresh))?.value
        #expect(store.state.lastRefreshRequest == nil)
    }

    @Test
    func eventViewerRefreshesSourceDataFromAboutPull() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("viewer-refresh-event")
        let sourceProvenance = sourceProvenance("viewer-refresh-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let recorder = SourceRefreshRecorder()
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Viewer Refresh Event")
            try Self.insertEventOrganizer(db, eventID: eventID, organizerID: testOrganizerID)
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 0)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.sourceDataRefresh = SourceDataRefreshClient { sourceBaselineID in
                await recorder.record(sourceBaselineID)
            }
        } operation: {
            var initialState = EventViewerHarness.State(eventID: eventID)
            initialState.eventViewer.selectedFeature = .about
            return TestStore(initialState: initialState) {
                EventViewerHarness()
            }
        }

        await store.send(
            to: \EventViewerHarness.State.eventInfoViewer,
            EventInfoViewer.Action.didPullToRefresh
        )?.value
        #expect(await recorder.sourceBaselineIDs == [sourceBaselineID])
        #expect(store.state.eventViewer.selectedFeature == .about)
    }

    @Test
    func eventViewerRefreshesSourceDataFromSourceTabRefresh() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("viewer-source-refresh-event")
        let sourceProvenance = sourceProvenance("viewer-source-refresh-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let sourceBaseline = SourceBaselineRecord(
            source: sourceProvenance,
            databaseFileName: "baseline.sqlite",
            importedAt: Date(timeIntervalSince1970: 0)
        )
        let workspace = EditingWorkspaceRecord(teamSourceBaseline: sourceBaseline)
        let recorder = SourceRefreshRecorder()
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let oldBaselineDatabase = try defaultBaselineDatabase(
            path: directoryURL.appending(path: "old-baseline.sqlite").path()
        )
        let newBaselineDatabase = try defaultBaselineDatabase(
            path: directoryURL.appending(path: "new-baseline.sqlite").path()
        )
        let oldSourceEditingSession = try SourceEditingSession(
            workingDatabasePath: directoryURL.appending(path: "old-session.sqlite").path(),
            baselineDatabasePath: oldBaselineDatabase.path
        )
        let newSourceEditingSession = try SourceEditingSession(
            workingDatabasePath: directoryURL.appending(path: "new-session.sqlite").path(),
            baselineDatabasePath: newBaselineDatabase.path
        )
        let isSourceRefreshed = Mutex(false)
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Viewer Source Refresh Event")
            try Self.insertEventOrganizer(db, eventID: eventID, organizerID: testOrganizerID)
            try SourceBaselineRecord.insert { sourceBaseline }.execute(db)
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
            try EditingWorkspaceRecord.insert { workspace }.execute(db)
            try EventEditingWorkspaceRecord.insert {
                EventEditingWorkspaceRecord(
                    id: eventID,
                    workspaceID: workspace.id
                )
            }
            .execute(db)
        }
        try database.backup(to: oldBaselineDatabase.database)
        try await database.write { db in
            try OMERecord.Event
                .find(eventID)
                .update { $0.name = "Refreshed Source Event" }
                .execute(db)
        }
        try database.backup(to: newBaselineDatabase.database)
        let refreshedSummary = try withDependencies {
            $0.sourceEditingSession = newSourceEditingSession
        } operation: {
            try database.read { db in
                try EventWorkspaceSummaryRequest(eventID: eventID).fetch(db)
            }
        }
        expectNoDifference(refreshedSummary.totalCount, 0)

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.sourceEditingSession = oldSourceEditingSession
            $0.sourceDataRefresh = SourceDataRefreshClient { sourceBaselineID in
                await recorder.record(sourceBaselineID)
                isSourceRefreshed.withLock { $0 = true }
            }
            $0.sourceWorkspaceDatabase = SourceWorkspaceDatabaseClient(
                workspace: { requestedWorkspaceID in
                    #expect(requestedWorkspaceID == workspace.id)
                    let isRefreshed = isSourceRefreshed.withLock { $0 }
                    return SourceWorkspaceDatabase(
                        database: database,
                        sourceEditingSession: isRefreshed
                            ? newSourceEditingSession
                            : oldSourceEditingSession
                    )
                }
            )
        } operation: {
            var initialState = EventViewerHarness.State(eventID: eventID)
            initialState.eventViewer.selectedFeature = .workspace
            return TestStore(initialState: initialState) {
                EventViewerHarness()
            }
        }

        expectNoDifference(
            store.state.eventViewer.eventWorkspace?.state.sourceWorkspaceSummary.totalCount,
            1
        )
        await store.send(
            to: \EventViewerHarness.State.eventWorkspace,
            EventWorkspace.Action.refreshSourceButtonTapped
        )?.value
        let sourceBaselineIDs = await recorder.sourceBaselineIDs
        expectNoDifference(sourceBaselineIDs, [sourceBaselineID])
        expectNoDifference(
            store.state.eventViewer.selectedFeature,
            EventViewer.EventFeature.workspace
        )
        await waitUntil {
            store.state.eventViewer.eventWorkspace?.state.sourceWorkspaceSummary.totalCount == 0
        }
        expectNoDifference(
            store.state.eventViewer.eventWorkspace?.state.sourceWorkspaceSummary.totalCount,
            0
        )
    }

    @Test
    func eventViewerRemovesPullReviewAfterPullMerge() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("viewer-merge-refresh-event")
        let sourceProvenance = sourceProvenance("viewer-merge-refresh-source")
        let sourceBaseline = SourceBaselineRecord(
            source: sourceProvenance,
            databaseFileName: "baseline.sqlite",
            importedAt: Date(timeIntervalSince1970: 0)
        )
        let workspace = EditingWorkspaceRecord(teamSourceBaseline: sourceBaseline)
        let directoryURL = try temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let baselineDatabasePath = directoryURL
            .appending(path: "baseline.sqlite")
            .path()
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Source Event Before Merge")
            try Self.insertEventOrganizer(db, eventID: eventID, organizerID: testOrganizerID)
            try SourceBaselineRecord.insert { sourceBaseline }.execute(db)
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
            try EditingWorkspaceRecord.insert { workspace }.execute(db)
            try EventEditingWorkspaceRecord.insert {
                EventEditingWorkspaceRecord(
                    id: eventID,
                    workspaceID: workspace.id
                )
            }
            .execute(db)
        }
        do {
            let baselineDatabase = try defaultBaselineDatabase(path: baselineDatabasePath)
            try database.backup(to: baselineDatabase.database)
        }
        let workingDatabasePath = directoryURL
            .appending(path: "session.sqlite")
            .path()
        let sourceEditingSession: @Sendable (String) throws -> SourceEditingSession = { schemaName in
            try SourceEditingSession(
                workingDatabasePath: workingDatabasePath,
                baselineDatabasePath: baselineDatabasePath,
                baselineSchemaName: schemaName
            )
        }
        let initialSourceEditingSession = try sourceEditingSession("source_baseline_before_refresh")
        try await database.write { db in
            try OMERecord.Event
                .find(eventID)
                .update { $0.name = "Source Event After Merge" }
                .execute(db)
        }

        let review = TangledPullReview(
            author: "did:plc:author123",
            body: "Update the event name.",
            commentCount: 0,
            createdAt: "2026-07-03T12:01:00Z",
            patchBlobs: [],
            sourceBranch: "ome/proposal-name",
            state: "open",
            targetBranch: "main",
            targetRepositoryDID: "did:plc:targetrepo",
            title: "Update source event name",
            uri: "at://did:plc:author123/sh.tangled.repo.pull/3pull"
        )
        let refreshedSourceBaselineIDs = Mutex([SourceBaselineRecord.ID]())
        let mergeRequests = Mutex([OpenMusicEventTangledPullReviewMergeRequest]())
        let isSourceRefreshed = Mutex(false)
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.sourceDataRefresh = SourceDataRefreshClient { refreshedSourceBaselineID in
                refreshedSourceBaselineIDs.withLock { $0.append(refreshedSourceBaselineID) }
                try SourceReferenceDatabaseClient.removeSQLiteDatabase(
                    at: URL(fileURLWithPath: baselineDatabasePath)
                )
                let baselineDatabase = try defaultBaselineDatabase(path: baselineDatabasePath)
                try database.backup(to: baselineDatabase.database)
                isSourceRefreshed.withLock { $0 = true }
            }
            $0.sourceWorkspaceDatabase = SourceWorkspaceDatabaseClient(
                workspace: { requestedWorkspaceID in
                    #expect(requestedWorkspaceID == workspace.id)
                    let schemaName = isSourceRefreshed.withLock { $0 }
                        ? "source_baseline_after_refresh"
                        : "source_baseline_before_refresh"
                    return SourceWorkspaceDatabase(
                        database: database,
                        sourceEditingSession: try sourceEditingSession(schemaName)
                    )
                }
            )
            $0.tangledPullReviewClient = TangledPullReviewClient(
                list: { _ in [review] },
                merge: { request in
                    mergeRequests.withLock { $0.append(request) }
                }
            )
        } operation: {
            var initialState = EventViewerHarness.State(eventID: eventID)
            initialState.eventViewer.selectedFeature = .workspace
            initialState.eventViewer.eventWorkspace?.state.tangledPullReviewStatus = .loaded([
                review,
            ])
            initialState.eventViewer.eventWorkspace?.state.selectedTangledPullReview = .loaded(review)
            return TestStore(initialState: initialState) {
                EventViewerHarness()
            }
        }

        let initialWorkspaceSummary = try await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.sourceEditingSession = initialSourceEditingSession
        } operation: {
            try await database.read { db in
                try EventWorkspaceSummaryRequest(eventID: eventID).fetch(db)
            }
        }
        expectNoDifference(
            initialWorkspaceSummary.totalCount,
            1
        )
        await store.send(
            to: \EventViewerHarness.State.eventWorkspace,
            EventWorkspace.Action.mergeTangledPullReviewButtonTapped(review)
        )?.value

        await waitUntil {
            refreshedSourceBaselineIDs.withLock { $0 } == [sourceBaseline.id]
        }
        expectNoDifference(refreshedSourceBaselineIDs.withLock { $0 }, [sourceBaseline.id])
        expectNoDifference(
            mergeRequests.withLock { $0 },
            [
                OpenMusicEventTangledPullReviewMergeRequest(
                    eventID: eventID,
                    review: review
                ),
            ]
        )
        expectNoDifference(store.state.eventViewer.selectedFeature, EventViewer.EventFeature.workspace)
        #expect(store.state.eventViewer.eventWorkspace?.state.selectedTangledPullReview == nil)
        await waitUntil {
            store.state.eventViewer.eventWorkspace?.state.sourceWorkspaceSummary.totalCount == 0
        }
        expectNoDifference(
            store.state.eventViewer.eventWorkspace?.state.sourceWorkspaceSummary.totalCount,
            0
        )
    }

    @Test
    func eventViewerInjectsEventInfoEditingFromAboutDescendant() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-info-edit-intent")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event Info Edit Intent")
        }

        let store = withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            var initialState = EventViewerHarness.State(eventID: eventID)
            initialState.eventViewer.selectedFeature = .contributors
            return TestStore(initialState: initialState) {
                EventViewerHarness()
            }
        }

        await withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            await store.send(
                to: \EventViewerHarness.State.eventInfoViewer,
                EventInfoViewer.Action.editButtonTapped
            )?.value
        }
        await Task.yield()

        #expect(store.state.eventViewer.selectedFeature == .contributors)
        #expect(store.state.eventViewer.destination?.eventInfoForm?.eventID == eventID)
    }

    #if !os(Android)
    @Test
    func eventViewerSelectsEditorFeatureWithAuthoringGrant() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("authorized-editor-tab")
        let sourceProvenance = sourceProvenance("authorized-editor-tab")

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Authorized Editor Tab")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 1_800)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
        }
        let workspace = WorkspaceContext(
            id: EditingWorkspaceRecord.ID(
                sourceBaselineID: SourceBaselineRecord.ID(source: sourceProvenance)
            ),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: database)
        )
        let grant = Shared<AuthoringGrant?>(
            value: AuthoringGrant(principal: .local, role: .owner, workspace: workspace)
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.useWorkspaceContext(
                workspace.mounting(grant: SharedReader(grant))
            )
        } operation: {
            var initialState = EventViewerHarness.State(eventID: eventID)
            initialState.eventViewer.selectedFeature = .contributors
            return TestStore(initialState: initialState) {
                EventViewerHarness()
            }
        }

        store.modify {
            $0.eventViewer.selectedFeature = .workspace
        }

        #expect(store.state.eventViewer.authoringAccess == .authoring(.owner))
        #expect(store.state.eventViewer.selectedFeature == .workspace)
    }
    #endif

    @Test
    func eventViewerOpensEditIntentWithAuthoringGrant() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("authorized-edit-intent")

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Authorized Edit Intent")
        }
        let workspace = WorkspaceContext(
            id: EditingWorkspaceRecord.ID(localEventID: eventID),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: database)
        )
        let grant = Shared<AuthoringGrant?>(
            value: AuthoringGrant(principal: .local, role: .owner, workspace: workspace)
        )

        await withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.useWorkspaceContext(
                workspace.mounting(grant: SharedReader(grant))
            )
        } operation: {
            var initialState = EventViewerHarness.State(eventID: eventID)
            initialState.eventViewer.selectedFeature = .contributors
            @Bindable var store = Store(initialState: initialState) {
                EventViewerHarness()
            }
            @Bindable var eventInfoStore = store.spawn(\.eventInfoViewer)

            let task = eventInfoStore.send(.editButtonTapped)
            await task?.value
            await waitUntil {
                store.eventViewer.destination?.eventInfoForm?.eventID == eventID
            }

            #expect(store.eventViewer.authoringAccess == .authoring(.owner))
            #expect(store.eventViewer.destination?.eventInfoForm?.eventID == eventID)
        }
    }

    @Test
    func eventViewerIgnoresSourceRefreshForDifferentEvent() async throws {
        let database = try makePreparedDatabase()
        let viewerEventID = eventID("viewer-refresh-event")
        let otherEventID = eventID("other-refresh-event")
        let sourceProvenance = sourceProvenance("other-refresh-source")
        let recorder = SourceRefreshRecorder()
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: viewerEventID, name: "Viewer Refresh Event")
            try Self.insertEvent(db, id: otherEventID, name: "Other Refresh Event")
            try Self.insertEventOrganizer(db, eventID: viewerEventID, organizerID: testOrganizerID)
            try Self.insertEventOrganizer(db, eventID: otherEventID, organizerID: testOrganizerID)
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 0)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: otherEventID,
                sourceProvenance: sourceProvenance
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = viewerEventID
            $0.sourceDataRefresh = SourceDataRefreshClient { sourceBaselineID in
                await recorder.record(sourceBaselineID)
            }
        } operation: {
            var initialState = EventViewerHarness.State(eventID: viewerEventID)
            initialState.eventViewer.eventInfoViewer?.state = EventInfoViewer.State(eventID: otherEventID)
            return TestStore(initialState: initialState) {
                EventViewerHarness()
            }
        }

        await store.send(
            to: \EventViewerHarness.State.eventInfoViewer,
            EventInfoViewer.Action.didPullToRefresh
        )?.value
        #expect(await recorder.sourceBaselineIDs == [])
    }

    @Test
    func organizerDetailFetchesLinkedEvents() async throws {
        let database = try makePreparedDatabase()
        let linkedEventID = eventID("linked-event")
        let unlinkedEventID = eventID("unlinked-event")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: linkedEventID, name: "Linked Event")
            try Self.insertEvent(db, id: unlinkedEventID, name: "Unlinked Event")
            try Self.insertEventOrganizer(db, eventID: linkedEventID, organizerID: testOrganizerID)
        }

        let events = try await database.read { db in
            try OrganizerDetail.eventsQuery(organizerID: testOrganizerID).fetchAll(db)
        }

        #expect(events.map(\.id) == [linkedEventID])
    }

    @Test
    func organizerDetailFetchesCalendarsForOrganizer() async throws {
        let database = try makePreparedDatabase()
        let otherOrganizerID = try #require(OMERecord.Organizer.ID("did:web:other.example"))
        let defaultCalendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let sideCalendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: calendarLocalID("side-room")
        )
        let otherCalendarID = OMERecord.Calendar.ID(
            ownerID: otherOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertOrganizer(db, id: otherOrganizerID)
            try Self.insertCalendar(db, id: sideCalendarID, name: "Side Room")
            try Self.insertCalendar(db, id: defaultCalendarID, name: "Main Calendar")
            try Self.insertCalendar(db, id: otherCalendarID, name: "Other Calendar")
        }

        let calendars = try await database.read { db in
            try OrganizerDetail.calendarsQuery(organizerID: testOrganizerID).fetchAll(db)
        }

        #expect(calendars.map(\.id) == [defaultCalendarID, sideCalendarID])
    }

    @Test
    func calendarDetailResolvesEntriesWithLocalEvents() async throws {
        let database = try makePreparedDatabase()
        let calendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let firstEventID = eventID("first-event")
        let pinnedEventID = eventID("pinned-event")
        let firstEventDate = try #require(LocalDate("2026-06-01"))
        let pinnedEventDate = try #require(LocalDate("2026-05-01"))
        let firstEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("first-entry")
        )
        let pinnedEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("pinned-entry")
        )
        let unavailableEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("unavailable-entry")
        )
        let unavailableEventRef = OMERecord.Event.Reference(
            uri: ATProto.URI(
                authority: .did(try #require(OMERecord.Organizer.ID("did:web:remote.example"))),
                collection: OMERecord.Event.nsid,
                rkey: "remote-event"
            )
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(
                db,
                id: firstEventID,
                name: "First Event",
                startDate: firstEventDate
            )
            try Self.insertEvent(
                db,
                id: pinnedEventID,
                name: "Pinned Event",
                startDate: pinnedEventDate
            )
            try Self.insertCalendar(db, id: calendarID, name: "Main Calendar")
            try Self.insertCalendarEntry(
                db,
                id: firstEntryID,
                event: OMERecord.Event.reference(id: firstEventID),
                createdAt: Date(timeIntervalSince1970: 100)
            )
            try Self.insertCalendarEntry(
                db,
                id: unavailableEntryID,
                event: unavailableEventRef,
                createdAt: Date(timeIntervalSince1970: 200)
            )
            try Self.insertCalendarEntry(
                db,
                id: pinnedEntryID,
                event: OMERecord.Event.reference(id: pinnedEventID),
                createdAt: Date(timeIntervalSince1970: 50),
                note: "Pinned pick",
                pinned: true
            )
        }

        let rows = try await database.read { db in
            CalendarDetail.EntryRows(
                entries: try CalendarDetail.entriesQuery(calendarID: calendarID).fetchAll(db),
                events: try CalendarDetail.localEventsQuery.fetchAll(db)
            )
        }

        #expect(rows.rows.map(\.entry.id) == [pinnedEntryID, firstEntryID, unavailableEntryID])
        #expect(rows.rows.map(\.event?.id) == [pinnedEventID, firstEventID, nil])
        #expect(rows.rows.first?.entry.note == "Pinned pick")
    }

    @Test
    func calendarDetailEditButtonPresentsEditor() throws {
        let database = try makePreparedDatabase()
        let calendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: CalendarDetail.State(calendarID: calendarID)) {
                CalendarDetail()
            }
        }

        store.send(.editButtonTapped)

        #expect(store.state.editCalendar?.calendarID == calendarID)
    }

    @Test
    func calendarDetailAddEventPresentsCreateEvent() throws {
        let database = try makePreparedDatabase()
        let calendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: CalendarDetail.State(calendarID: calendarID)) {
                CalendarDetail()
            }
        }

        store.send(.addEventButtonTapped)

        guard case let .createEvent(createEvent)? = store.state.destination else {
            Issue.record("Expected calendar detail to present create event.")
            return
        }
        #expect(createEvent.state.organizerID == testOrganizerID)
        #expect(createEvent.state.eventOrganizerID == testOrganizerID)
    }

    @Test
    func editCalendarSavesHeroAndLogoImages() async throws {
        let database = try makePreparedDatabase()
        let calendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let logoURL = try #require(URL(string: "https://example.com/logo.png"))
        let logoImage = OMERecord.ImageAsset(
            source: .url(logoURL),
            role: .logo,
            renderKind: .transparent,
            materializationPolicy: .lazy
        )
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertCalendar(
                db,
                id: calendarID,
                name: "Main Calendar",
                description: "Calendar description",
                images: [logoImage]
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            var state = EditCalendar.State(calendarID: calendarID)
            state.hasLoadedDraft = true
            state.draft = OMERecord.Calendar.Draft(
                id: calendarID,
                name: "Main Calendar",
                description: "Calendar description",
                images: [logoImage]
            )
            state.resetImagePickers()
            state.form.value.name = " Updated Calendar "
            state.form.value.description = " Updated description "
            state.heroImagePicker.replaceURLString(" https://example.com/hero.png ")

            return TestStore(initialState: state) {
                EditCalendar()
            }
        }

        let submitTask = store.send(.saveButtonTapped)
        let saveTask = await store.receive(
            \.formSubmitted,
            .equals(
                EditCalendar.FormValue(
                    name: " Updated Calendar ",
                    description: " Updated description "
                )
            ),
            timeout: .seconds(1)
        )
        await saveTask?.value
        await submitTask?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let calendar = try await database.read { db in
            try #require(
                try OMERecord.Calendar
                    .where { $0.id.eq(calendarID) }
                    .fetchOne(db)
            )
        }

        #expect(calendar.name == "Updated Calendar")
        #expect(calendar.description == "Updated description")
        #expect(calendar.images?.imageAsset(role: .hero)?.url?.absoluteString == "https://example.com/hero.png")
        #expect(calendar.images?.imageAsset(role: .logo)?.url?.absoluteString == "https://example.com/logo.png")
    }

    @Test
    func editCalendarLoadsMissingCalendarAsDefaultDraft() throws {
        let database = try makePreparedDatabase()
        let calendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EditCalendar.State(calendarID: calendarID)) {
                EditCalendar()
            }
        }

        #expect(store.state.hasLoadedDraft == true)
        #expect(store.state.draft?.id == calendarID)
        #expect(store.state.draft?.name == "Events")
        #expect(store.state.form.value.name == "Events")
        #expect(store.state.errorMessage == nil)
    }

    @Test
    func editCalendarSavesMissingDefaultCalendar() async throws {
        let database = try makePreparedDatabase()
        let calendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            var state = EditCalendar.State(calendarID: calendarID)
            state.hasLoadedDraft = true
            state.draft = OMERecord.Calendar.Draft(
                id: calendarID,
                name: "Events",
                description: nil,
                images: nil
            )
            state.form.value.name = " Source Calendar "
            state.form.value.description = " Source description "
            state.heroImagePicker.replaceURLString("https://example.com/source-hero.png")

            return TestStore(initialState: state) {
                EditCalendar()
            }
        }

        let submitTask = store.send(.saveButtonTapped)
        let saveTask = await store.receive(
            \.formSubmitted,
            .equals(
                EditCalendar.FormValue(
                    name: " Source Calendar ",
                    description: " Source description "
                )
            ),
            timeout: .seconds(1)
        )
        await saveTask?.value
        await submitTask?.value

        let calendar = try await database.read { db in
            try #require(
                try OMERecord.Calendar
                    .where { $0.id.eq(calendarID) }
                    .fetchOne(db)
            )
        }

        #expect(calendar.name == "Source Calendar")
        #expect(calendar.description == "Source description")
        #expect(calendar.images?.imageAsset(role: .hero)?.url?.absoluteString == "https://example.com/source-hero.png")
    }

    @Test
    func editCalendarImagePickerImportAddsImageThroughParentDestination() async throws {
        let calendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let image = ImportImages.Configuration.calendarHero.importedImage(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000ca01")!,
            title: "Calendar Hero",
            sourceName: "calendar-hero.png",
            sourceURL: URL(fileURLWithPath: "/tmp/calendar-hero.png"),
            mimeType: "image/png",
            data: Data("calendar-hero".utf8)
        )

        var state = EditCalendar.State(calendarID: calendarID)
        state.hasLoadedDraft = true

        @Bindable var store = Store(initialState: state) {
            EditCalendar()
        }

        store.send(.heroImagePicker(.addButtonTapped))
        let importStore = try #require(
            $store.scope(\.destination, action: \.destination).heroImportImages.wrappedValue
        )
        importStore.send(.imagesImported([image]))
        await importStore.send(.saveButtonTapped)?.value

        await waitUntil { store.destination == nil }
        expectNoDifference(store.heroImagePicker.images.map(\.importedImage), [image])
        #expect(store.logoImagePicker.images.isEmpty)
    }

    @Test
    func organizerDetailGroupsDefaultCalendarEntries() async throws {
        let database = try makePreparedDatabase()
        let calendarID = OrganizerDetail.defaultCalendarID(organizerID: testOrganizerID)
        let currentEventID = eventID("current-event")
        let previousEventID = eventID("previous-event")
        let previousLaterEventID = eventID("previous-later-event")
        let upcomingEventID = eventID("upcoming-event")
        let upcomingLaterEventID = eventID("upcoming-later-event")
        let legacyOnlyEventID = eventID("legacy-only-event")
        let currentEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("current-event")
        )
        let previousEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("previous-event")
        )
        let previousLaterEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("previous-later-event")
        )
        let upcomingEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("upcoming-event")
        )
        let upcomingLaterEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("upcoming-later-event")
        )
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let today = try #require(LocalDate("2026-05-11"))
        let currentStartDate = try #require(LocalDate("2026-05-10"))
        let currentEndDate = try #require(LocalDate("2026-05-12"))
        let previousStartDate = try #require(LocalDate("2026-05-01"))
        let previousEndDate = try #require(LocalDate("2026-05-03"))
        let previousLaterStartDate = try #require(LocalDate("2026-05-10"))
        let previousLaterEndDate = try #require(LocalDate("2026-05-10"))
        let upcomingStartDate = try #require(LocalDate("2026-06-01"))
        let upcomingEndDate = try #require(LocalDate("2026-06-03"))
        let upcomingLaterStartDate = try #require(LocalDate("2026-06-04"))
        let upcomingLaterEndDate = try #require(LocalDate("2026-06-06"))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(
                db,
                id: currentEventID,
                name: "Current Event",
                startDate: currentStartDate,
                endDate: currentEndDate,
                timeZone: timeZone
            )
            try Self.insertEvent(
                db,
                id: previousEventID,
                name: "Previous Event",
                startDate: previousStartDate,
                endDate: previousEndDate,
                timeZone: timeZone
            )
            try Self.insertEvent(
                db,
                id: previousLaterEventID,
                name: "Previous Later Event",
                startDate: previousLaterStartDate,
                endDate: previousLaterEndDate,
                timeZone: timeZone
            )
            try Self.insertEvent(
                db,
                id: upcomingEventID,
                name: "Upcoming Event",
                startDate: upcomingStartDate,
                endDate: upcomingEndDate,
                timeZone: timeZone
            )
            try Self.insertEvent(
                db,
                id: upcomingLaterEventID,
                name: "Upcoming Later Event",
                startDate: upcomingLaterStartDate,
                endDate: upcomingLaterEndDate,
                timeZone: timeZone
            )
            try Self.insertEvent(db, id: legacyOnlyEventID, name: "Legacy Only Event")
            try Self.insertEventOrganizer(db, eventID: legacyOnlyEventID, organizerID: testOrganizerID)
            try Self.insertCalendar(db, id: calendarID, name: "Main Calendar")
            try Self.insertCalendarEntry(
                db,
                id: currentEntryID,
                event: OMERecord.Event.reference(id: currentEventID),
                createdAt: Date(timeIntervalSince1970: 100)
            )
            try Self.insertCalendarEntry(
                db,
                id: previousEntryID,
                event: OMERecord.Event.reference(id: previousEventID),
                createdAt: Date(timeIntervalSince1970: 200)
            )
            try Self.insertCalendarEntry(
                db,
                id: previousLaterEntryID,
                event: OMERecord.Event.reference(id: previousLaterEventID),
                createdAt: Date(timeIntervalSince1970: 250)
            )
            try Self.insertCalendarEntry(
                db,
                id: upcomingEntryID,
                event: OMERecord.Event.reference(id: upcomingEventID),
                createdAt: Date(timeIntervalSince1970: 300)
            )
            try Self.insertCalendarEntry(
                db,
                id: upcomingLaterEntryID,
                event: OMERecord.Event.reference(id: upcomingLaterEventID),
                createdAt: Date(timeIntervalSince1970: 350)
            )
        }
        let entryRows = try await database.read { db in
            CalendarDetail.EntryRows(
                entries: try OrganizerDetail.defaultCalendarEntriesQuery(
                    organizerID: testOrganizerID
                )
                .fetchAll(db),
                events: try CalendarDetail.localEventsQuery.fetchAll(db)
            )
        }
        let sections = OrganizerDetail.CalendarEntrySections(
            entryRows: entryRows,
            now: today.atStartOfDay(in: timeZone)
        )

        #expect(sections.currentRows.map(\.event?.id) == [currentEventID])
        #expect(sections.upcomingRows.map(\.event?.id) == [upcomingEventID, upcomingLaterEventID])
        #expect(sections.previousRows.map(\.event?.id) == [previousLaterEventID, previousEventID])
        #expect(sections.initialSection == .now)
    }

    @Test
    func contributorsViewerFetchesContributorsForEvent() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let otherEventID = eventID("event-2")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertEvent(db, id: otherEventID, name: "Event Two")
            try Self.insertContributor(db, eventID: selectedEventID, contributorID: "zara", name: "Zara")
            try Self.insertContributor(db, eventID: selectedEventID, contributorID: "amy", name: "Amy")
            try Self.insertContributor(db, eventID: otherEventID, contributorID: "other", name: "Other")
        }

        let contributors = try await database.read { db in
            try ContributorsViewer.contributorProfilesQuery(eventID: selectedEventID).fetchAll(db)
        }

        #expect(contributors.map(\.name) == ["Amy", "Zara"])
    }

    @Test
    func `authoring keeps event contributors on the app database`() async throws {
        let appDatabase = try makePreparedDatabase()
        let referenceDatabase = try makeCoreDatabase()
        let eventID = eventID("wicked-woods-2026")

        // Wicked Woods has the same source contributor in its app and reference databases.
        for database in [appDatabase, referenceDatabase] {
            try await database.write { db in
                try Self.insertOrganizer(db, id: testOrganizerID)
                try Self.insertEvent(db, id: eventID, name: "Wicked Woods 2026")
                try Self.insertContributor(
                    db,
                    eventID: eventID,
                    contributorID: "artist",
                    name: "Artist"
                )
            }
        }

        let workspace = WorkspaceContext(
            id: EditingWorkspaceRecord.ID(localEventID: eventID),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: referenceDatabase)
        )
        let grant = Shared<AuthoringGrant?>(
            value: AuthoringGrant(
                principal: .local,
                role: .owner,
                workspace: workspace
            )
        )

        // Entering authoring mounts the reference context without replacing the app database.
        let contributorNames = try await withDependencies {
            $0.defaultDatabase = appDatabase
            $0.useWorkspaceContext(
                workspace.mounting(grant: SharedReader(grant))
            )
        } operation: {
            @Dependency(\.defaultDatabase) var database
            return try await database.read { db in
                try ContributorsViewer
                    .contributorRowsQuery(
                        eventID: eventID,
                        hydration: .bskyActorProfile
                    )
                    .fetchAll(db)
                    .map(\.profile.name)
            }
        }

        // The hydrated list still reads app-only actor-cache tables and shows the contributor.
        expectNoDifference(contributorNames, ["Artist"])
    }

    @Test
    func contributorsViewerDeleteRemovesContributor() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let date = try #require(LocalDate("2026-08-07"))
        let contributorID = contributorLocalID("amy")
        let performanceID = performanceLocalID("opening")
        let contributorRecordID = OMERecord.Contributor.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            contributorID: contributorID
        )
        let performanceRecordID = OMERecord.Performance.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            performanceID: performanceID
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "friday", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(db, eventID: eventID, contributorID: "amy", name: "Amy")
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "opening",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Opening"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "opening",
                contributorID: "amy"
            )
            try OMERecord.Relationship.insert {
                OMERecord.Relationship(
                    subject: .init(contributorID: contributorRecordID),
                    role: .performer,
                    object: .init(performanceID: performanceRecordID),
                    createdAt: "2026-08-07T00:00:00Z"
                )
            }
            .execute(db)
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: ContributorsViewer.State(eventID: eventID)) {
                ContributorsViewer()
            }
        }

        await store.send(.deleteContributors([contributorID]))?.value

        #expect(store.state.errorMessage == nil)

        try await database.read { db in
            let contributor = try ContributorDetail.contributorQuery(
                contributorID: contributorID,
                eventID: eventID
            )
            .fetchOne(db)
            let performanceContributorCount = try OMERecord.Performance.Contributors
                .where { $0.performanceID.organizerID.eq(performanceRecordID.organizerID) }
                .where { $0.performanceID.eventID.eq(performanceRecordID.eventID) }
                .where { $0.performanceID.performanceID.eq(performanceRecordID.performanceID) }
                .fetchCount(db)
            let relationshipCount = try OMERecord.Relationship.fetchCount(db)

            #expect(contributor == nil)
            #expect(performanceContributorCount == 0)
            #expect(relationshipCount == 0)
        }
    }

    @Test
    func contributorProfileUnhydratedDoesNotRequireActorCacheTables() async throws {
        let database = try makeCoreDatabase()
        let selectedEventID = eventID("event-1")
        let actor = try #require(OMERecord.Contributor.Actor("alice.bsky.social"))
        let date = try #require(LocalDate("2026-08-07"))

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: selectedEventID,
                contributorID: "speaker-1",
                name: "Alice"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                contributorID: "speaker-1",
                contributorActor: actor
            )
        }

        let profiles = try await database.read { db in
            try ContributorProfile
                .all(eventID: selectedEventID, hydration: .none)
                .fetchAll(db)
        }

        let profile = try #require(profiles.first)
        #expect(profile.name == "Alice")
        #expect(profile.contributorActor == actor)
        #expect(profile.handle == nil)
        #expect(profile.subtitle == nil)

        await #expect(throws: (any Error).self) {
            try await database.read { db in
                try ContributorProfile
                    .all(eventID: selectedEventID, hydration: .bskyActorProfile)
                    .fetchAll(db)
            }
        }
    }

    @Test
    func contributorStageContextAggregatesScheduledAndLineupStages() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let otherEventID = eventID("event-2")
        let contributorID = contributorLocalID("artist")
        let date = try #require(LocalDate("2026-08-07"))

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertEvent(db, id: otherEventID, name: "Event Two")
            try Self.insertContributor(db, eventID: selectedEventID, contributorID: "artist", name: "Artist")
            try Self.insertContributor(db, eventID: otherEventID, contributorID: "artist", name: "Other Artist")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertSchedule(db, eventID: otherEventID, scheduleID: "friday", date: date)
            try Self.insertStage(
                db,
                eventID: selectedEventID,
                stageID: "main",
                name: "Main",
                sortIndex: 1,
                lineup: [contributorID]
            )
            try Self.insertStage(
                db,
                eventID: selectedEventID,
                stageID: "meadow",
                name: "Meadow",
                sortIndex: 2
            )
            try Self.insertStage(
                db,
                eventID: selectedEventID,
                stageID: "tent",
                name: "Tent",
                sortIndex: 3,
                lineup: [contributorID]
            )
            try Self.insertStage(
                db,
                eventID: otherEventID,
                stageID: "other",
                name: "Other",
                sortIndex: 0,
                lineup: [contributorID]
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "meadow-set",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 100),
                endTime: Date(timeIntervalSince1970: 200),
                title: "Meadow Set"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "tent-set",
                stageID: "tent",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 300),
                endTime: Date(timeIntervalSince1970: 400),
                title: "Tent Set"
            )
            try Self.insertPerformance(
                db,
                eventID: otherEventID,
                performanceID: "other-set",
                stageID: "other",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 50),
                endTime: Date(timeIntervalSince1970: 60),
                title: "Other Set"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: selectedEventID,
                performanceID: "meadow-set",
                contributorID: "artist"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: selectedEventID,
                performanceID: "tent-set",
                contributorID: "artist"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: otherEventID,
                performanceID: "other-set",
                contributorID: "artist"
            )
        }

        let context = try await database.read { db in
            ContributorStageContext(
                contributorID: contributorID,
                performanceRows: try PerformanceRow.forContributor(
                    contributorID: contributorID,
                    eventID: selectedEventID
                )
                .fetchAll(db),
                lineupStages: try ContributorDetail.lineupStagesQuery(
                    contributorID: contributorID,
                    eventID: selectedEventID
                )
                    .fetchAll(db)
            )
        }

        #expect(context.scheduledPerformances.map(\.title) == ["Meadow Set", "Tent Set"])
        #expect(context.lineupOnlyStages.map(\.name) == ["Main"])
        #expect(context.stages.map(\.name) == ["Main", "Meadow", "Tent"])
        #expect(context.primaryStage?.name == "Main")
        let firstPerformance = try #require(context.scheduledPerformances.first)
        #expect(context.stage(for: firstPerformance)?.name == "Meadow")

        let rowContext = try await database.read { db in
            try #require(
                ContributorsViewer.contributorRowsQuery(eventID: selectedEventID)
                    .fetchAll(db)
                    .first { $0.contributorID == contributorID }
            )
            .stageContext
        }

        #expect(rowContext.lineupOnlyStages.map(\.name) == ["Main"])
        #expect(rowContext.stages.map(\.name) == ["Main", "Meadow", "Tent"])
    }

    @Test
    func performanceRowScheduleQueryReturnsPerformanceAndStage() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "saturday", date: date)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "meadow", name: "Meadow")
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "opening",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 18, in: timeZone)),
                endTime: try #require(date.at(hour: 19, in: timeZone)),
                title: "Opening"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "next-day",
                stageID: "meadow",
                scheduleID: "saturday",
                startTime: try #require(date.at(hour: 20, in: timeZone)),
                endTime: try #require(date.at(hour: 21, in: timeZone)),
                title: "Next Day"
            )
        }

        let rows = try await database.read { db in
            try PerformanceRow
                .all(eventID: selectedEventID, scheduleID: scheduleLocalID("friday"))
                .fetchAll(db)
        }

        #expect(rows.map(\.performanceID) == [performanceLocalID("opening")])
        #expect(rows.map(\.title) == ["Opening"])
        #expect(rows.first?.stage?.name == "Meadow")
    }

    @Test
    func performanceRowContributorQueryReturnsContributorPerformancesAndStages() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let contributorID = contributorLocalID("artist")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertContributor(db, eventID: selectedEventID, contributorID: "artist", name: "Artist")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "meadow", name: "Meadow")
            try Self.insertStage(db, eventID: selectedEventID, stageID: "tent", name: "Tent")
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "meadow-set",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 18, in: timeZone)),
                endTime: try #require(date.at(hour: 19, in: timeZone)),
                title: "Meadow Set"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "tent-set",
                stageID: "tent",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 20, in: timeZone)),
                endTime: try #require(date.at(hour: 21, in: timeZone)),
                title: "Tent Set"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: selectedEventID,
                performanceID: "meadow-set",
                contributorID: "artist"
            )
        }

        let rows = try await database.read { db in
            try PerformanceRow
                .forContributor(contributorID: contributorID, eventID: selectedEventID)
                .fetchAll(db)
        }

        #expect(rows.map(\.performanceID) == [performanceLocalID("meadow-set")])
        #expect(rows.map(\.title) == ["Meadow Set"])
        #expect(rows.first?.stage?.name == "Meadow")
    }

    @Test
    func performanceRowTimeLabelsUseEventTimeZoneAndLegacyDaySegment() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let friday = try #require(LocalDate("2026-08-07"))
        let saturday = try #require(LocalDate("2026-08-08"))

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "friday", date: friday)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "evening",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(friday.at(hour: 18, in: timeZone)),
                endTime: try #require(friday.at(hour: 19, in: timeZone)),
                title: "Evening Set"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "late-night",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(saturday.at(hour: 1, minute: 30, in: timeZone)),
                endTime: try #require(saturday.at(hour: 2, minute: 30, in: timeZone)),
                title: "Late Night"
            )
        }

        let rows = try await database.read { db in
            try PerformanceRow
                .all(eventID: eventID, scheduleID: scheduleLocalID("friday"))
                .fetchAll(db)
        }
        let eveningPerformance = try #require(rows.first?.performance)
        let afterMidnightPerformance = try #require(rows.dropFirst().first?.performance)
        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.defaultEventTimeZone = timeZone
        } operation: {
            ScheduleViewer.State(eventID: eventID)
        }

        expectNoDifference(
            state.eventTimePresentation.performanceRowTimeRange(for: eveningPerformance),
            "6:00 - 7:00 pm"
        )
        expectNoDifference(
            state.eventTimePresentation.daySegment(for: eveningPerformance.startTime),
            "Friday Evening"
        )
        expectNoDifference(
            state.eventTimePresentation.performanceRowTimeRange(for: afterMidnightPerformance),
            "1:30 - 2:30 am"
        )
        expectNoDifference(
            state.eventTimePresentation.daySegment(for: afterMidnightPerformance.startTime),
            "Friday Night"
        )
        #expect(
            state.eventTimePresentation.formattedTimeRange(
                start: try #require(friday.at(hour: 23, minute: 30, in: timeZone)),
                end: try #require(saturday.at(hour: 1, minute: 15, in: timeZone))
            ) == "11:30 pm - 1:15 am"
        )
    }

    @Test
    func eventTimeZoneDisclosureUsesTheEffectiveOffsetAndSeasonalAbbreviation() throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let eventTimeZone = try #require(TimeZone(identifier: "America/Denver"))
        let matchingDeviceTimeZone = try #require(TimeZone(identifier: "America/Edmonton"))
        let differentDeviceTimeZone = try #require(TimeZone(identifier: "America/Vancouver"))
        let summer = try #require(LocalDate("2026-09-04"))
        let winter = try #require(LocalDate("2026-01-02"))
        let summerStart = try #require(summer.at(hour: 18, in: eventTimeZone))
        let summerEnd = try #require(summer.at(hour: 19, in: eventTimeZone))
        let winterStart = try #require(winter.at(hour: 18, in: eventTimeZone))
        let winterEnd = try #require(winter.at(hour: 19, in: eventTimeZone))
        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = selectedEventID
            $0.defaultEventTimeZone = eventTimeZone
        } operation: {
            ScheduleViewer.State(eventID: selectedEventID)
        }

        // A visitor whose device clock disagrees sees the event's current abbreviation.
        expectNoDifference(
            state.eventTimePresentation.formattedTimeRange(
                start: summerStart,
                end: summerEnd,
                disclosure: .whenDeviceClockDiffers(differentDeviceTimeZone)
            ),
            "6:00 - 7:00 pm (MDT)"
        )

        // Different zone identifiers do not add noise when both clocks agree.
        expectNoDifference(
            state.eventTimePresentation.formattedTimeRange(
                start: summerStart,
                end: summerEnd,
                disclosure: .whenDeviceClockDiffers(matchingDeviceTimeZone)
            ),
            "6:00 - 7:00 pm"
        )

        // The event abbreviation follows daylight-saving rules at the performance date.
        expectNoDifference(
            state.eventTimePresentation.formattedTimeRange(
                start: winterStart,
                end: winterEnd,
                disclosure: .whenDeviceClockDiffers(differentDeviceTimeZone)
            ),
            "6:00 - 7:00 pm (MST)"
        )

        // Dense schedule surfaces still render the event clock without repeating a suffix.
        expectNoDifference(
            state.eventTimePresentation.formattedTimeRange(
                start: summerStart,
                end: summerEnd,
                disclosure: .never
            ),
            "6:00 - 7:00 pm"
        )

        // The feature supplies event-clock labels to the reusable timeline components.
        expectNoDifference(
            state.eventTimePresentation.hourLabel(for: summerStart),
            "6pm"
        )
        expectNoDifference(
            state.eventTimePresentation.currentTimeLabel(
                for: summerStart,
                disclosure: .whenDeviceClockDiffers(differentDeviceTimeZone)
            ),
            "6:00p (MDT)"
        )
        expectNoDifference(
            state.eventTimePresentation.formattedTime(
                for: summerStart,
                disclosure: .whenDeviceClockDiffers(differentDeviceTimeZone)
            ),
            "6:00 pm (MDT)"
        )
    }

    @Test(arguments: ["alice.bsky.social", "did:plc:alice123"])
    func contributorProfileUsesCachedBlueskyProfileDataForGeneratedActor(actorString: String) async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let actor = try #require(OMERecord.Contributor.Actor(actorString))
        let contributorID = contributorLocalID("schedule-actor-alice.bsky.social")
        let date = try #require(LocalDate("2026-08-07"))
        let profile = BlueskyActorProfile(
            did: "did:plc:alice123",
            handle: "alice.bsky.social",
            displayName: "Alice Example",
            description: "ATProto builder",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg"),
            banner: URL(string: "https://cdn.example/alice-banner.jpg")
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: selectedEventID,
                contributorID: "schedule-actor-alice.bsky.social",
                name: "alice.bsky.social"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                contributorID: "schedule-actor-alice.bsky.social",
                contributorActor: actor
            )
            try BlueskyActorProfile.insert { profile }
                .execute(db)
            try BlueskyActorProfileCacheEntry.insert {
                BlueskyActorProfileCacheEntry(
                    actor: actor.description,
                    did: profile.did,
                    lastFetchedAt: Date(timeIntervalSince1970: 1_000),
                    lastFetchAttemptAt: Date(timeIntervalSince1970: 1_000)
                )
            }
            .execute(db)
        }

        let row = try await database.read { db in
            try #require(
                ContributorsViewer.contributorRowsQuery(
                    eventID: selectedEventID,
                    hydration: .bskyActorProfile
                )
                    .fetchAll(db)
                    .first { $0.contributorID == contributorID }
            )
        }
        let contributorProfile = row.profile

        #expect(contributorProfile.contributorActor == actor)
        #expect(contributorProfile.usesActorProfileAsPrimary)
        #expect(contributorProfile.name == "Alice Example")
        #expect(contributorProfile.handle == "alice.bsky.social")
        #expect(contributorProfile.subtitle == "@alice.bsky.social")
        #expect(contributorProfile.bio == "ATProto builder")
        #expect(contributorProfile.artworkAsset?.url?.absoluteString == "https://cdn.example/alice-avatar.jpg")
        #expect(contributorProfile.artworkCacheContext == nil)
        #expect(row.matchesSearch("Alice Example"))
        #expect(row.matchesSearch("alice.bsky.social"))
    }

    @Test
    func contributorProfileKeepsExplicitContributorFieldsAheadOfCachedBlueskyProfileData() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let actor = try #require(OMERecord.Contributor.Actor("alice.bsky.social"))
        let contributorID = contributorLocalID("speaker-1")
        let date = try #require(LocalDate("2026-08-07"))
        let explicitImageURL = try #require(URL(string: "https://example.com/explicit.jpg"))
        let profile = BlueskyActorProfile(
            did: "did:plc:alice123",
            handle: "alice.bsky.social",
            displayName: "Bluesky Alice",
            description: "Bluesky bio",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg")
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: selectedEventID,
                contributorID: "speaker-1",
                name: "Explicit Alice",
                bio: "OME bio",
                imageURL: explicitImageURL
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                contributorID: "speaker-1",
                contributorActor: actor
            )
            try BlueskyActorProfile.insert { profile }
                .execute(db)
            try BlueskyActorProfileCacheEntry.insert {
                BlueskyActorProfileCacheEntry(
                    actor: actor.description,
                    did: profile.did,
                    lastFetchedAt: Date(timeIntervalSince1970: 1_000),
                    lastFetchAttemptAt: Date(timeIntervalSince1970: 1_000)
                )
            }
            .execute(db)
        }

        let row = try await database.read { db in
            try #require(
                ContributorsViewer.contributorRowsQuery(
                    eventID: selectedEventID,
                    hydration: .bskyActorProfile
                )
                    .fetchAll(db)
                    .first { $0.contributorID == contributorID }
            )
        }
        let contributorProfile = row.profile

        #expect(contributorProfile.contributorActor == actor)
        #expect(!contributorProfile.usesActorProfileAsPrimary)
        #expect(contributorProfile.name == "Explicit Alice")
        #expect(contributorProfile.handle == "alice.bsky.social")
        #expect(contributorProfile.subtitle == "@alice.bsky.social")
        #expect(contributorProfile.bio == "OME bio")
        #expect(contributorProfile.artworkAsset?.url == explicitImageURL)
        #expect(contributorProfile.artworkCacheContext == LocalImageCacheContext(contributorID: row.contributor.id))
        #expect(row.matchesSearch("Explicit Alice"))
        #expect(row.matchesSearch("alice.bsky.social"))
        #expect(!row.matchesSearch("Bluesky Alice"))
    }

    @Test
    func contributorProfileUsesCachedBlueskyAvatarWhenExplicitContributorHasNoArtwork() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let actor = try #require(OMERecord.Contributor.Actor("alice.bsky.social"))
        let contributorID = contributorLocalID("speaker-1")
        let date = try #require(LocalDate("2026-08-07"))
        let profile = BlueskyActorProfile(
            did: "did:plc:alice123",
            handle: "alice.bsky.social",
            displayName: "Bluesky Alice",
            description: "Bluesky bio",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg")
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: selectedEventID,
                contributorID: "speaker-1",
                name: "Explicit Alice",
                bio: "OME bio"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                contributorID: "speaker-1",
                contributorActor: actor
            )
            try BlueskyActorProfile.insert { profile }
                .execute(db)
            try BlueskyActorProfileCacheEntry.insert {
                BlueskyActorProfileCacheEntry(
                    actor: actor.description,
                    did: profile.did,
                    lastFetchedAt: Date(timeIntervalSince1970: 1_000),
                    lastFetchAttemptAt: Date(timeIntervalSince1970: 1_000)
                )
            }
            .execute(db)
        }

        let row = try await database.read { db in
            try #require(
                ContributorsViewer.contributorRowsQuery(
                    eventID: selectedEventID,
                    hydration: .bskyActorProfile
                )
                .fetchAll(db)
                .first { $0.contributorID == contributorID }
            )
        }
        let contributorProfile = row.profile

        #expect(!contributorProfile.usesActorProfileAsPrimary)
        #expect(contributorProfile.name == "Explicit Alice")
        #expect(contributorProfile.bio == "OME bio")
        #expect(contributorProfile.artworkAsset?.url?.absoluteString == "https://cdn.example/alice-avatar.jpg")
        #expect(contributorProfile.artworkCacheContext == nil)
    }

    @Test(arguments: ["alice.bsky.social", "did:plc:alice123"])
    func contributorsViewerRefreshesGeneratedActorProfilesForListRows(actorString: String) async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let actor = try #require(OMERecord.Contributor.Actor(actorString))
        let contributorID = contributorLocalID("schedule-actor-alice.bsky.social")
        let date = try #require(LocalDate("2026-08-07"))
        let profile = BlueskyActorProfile(
            did: "did:plc:alice123",
            handle: "alice.bsky.social",
            displayName: "Alice Example",
            description: "ATProto builder",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg")
        )
        let requestRecorder = BlueskyProfileRequestRecorder()

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: selectedEventID,
                contributorID: "schedule-actor-alice.bsky.social",
                name: "alice.bsky.social"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: selectedEventID,
                performanceID: "talk-1",
                contributorID: "schedule-actor-alice.bsky.social",
                contributorActor: actor
            )
        }

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
            Store(initialState: ContributorsViewer.State(eventID: selectedEventID)) {
                ContributorsViewer()
            }
        }

        try await waitForContributorListBlueskyProfile(in: store, contributorID: contributorID)

        #expect(await requestRecorder.actors == [actor.description])
        let row = try #require(store.contributorRows.first { $0.contributorID == contributorID })
        #expect(row.profile.name == "Alice Example")
        #expect(row.profile.subtitle == "@alice.bsky.social")
        #expect(row.profile.artworkAsset?.url?.absoluteString == "https://cdn.example/alice-avatar.jpg")
    }

    @Test
    func stagesViewerFetchesStagesForEventInOrder() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let otherEventID = eventID("event-2")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertEvent(db, id: otherEventID, name: "Event Two")
            try Self.insertStage(db, eventID: selectedEventID, stageID: "late", name: "Late", sortIndex: 2)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "main", name: "Main", sortIndex: 1)
            try Self.insertStage(db, eventID: otherEventID, stageID: "other", name: "Other")
        }

        let stages = try await database.read { db in
            try StagesViewer.stagesQuery(eventID: selectedEventID).fetchAll(db)
        }

        #expect(stages.map(\.name) == ["Main", "Late"])
    }

    @Test
    func stageDetailFetchesStageForEvent() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let otherEventID = eventID("event-2")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertEvent(db, id: otherEventID, name: "Event Two")
            try Self.insertStage(db, eventID: selectedEventID, stageID: "main", name: "Main")
            try Self.insertStage(db, eventID: otherEventID, stageID: "main", name: "Other Main")
        }

        let stage = try await database.read { db in
            try StageDetail.stageQuery(
                stageID: stageLocalID("main"),
                eventID: selectedEventID
            )
            .fetchOne(db)
        }

        #expect(stage?.name == "Main")
    }

    @Test
    func stageDetailFiltersItsScheduleToTheSharedSelectedDay() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let friday = try #require(LocalDate("2026-08-07"))
        let saturday = try #require(LocalDate("2026-08-08"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One", timeZone: timeZone)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertStage(db, eventID: eventID, stageID: "forest", name: "Forest")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "friday", date: friday)
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "saturday", date: saturday)
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "meadow-friday",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(friday.at(hour: 18, in: timeZone)),
                endTime: try #require(friday.at(hour: 19, in: timeZone)),
                title: "Meadow Friday"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "forest-friday",
                stageID: "forest",
                scheduleID: "friday",
                startTime: try #require(friday.at(hour: 18, in: timeZone)),
                endTime: try #require(friday.at(hour: 19, in: timeZone)),
                title: "Forest Friday"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "meadow-saturday",
                stageID: "meadow",
                scheduleID: "saturday",
                startTime: try #require(saturday.at(hour: 18, in: timeZone)),
                endTime: try #require(saturday.at(hour: 19, in: timeZone)),
                title: "Meadow Saturday"
            )
        }

        var state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            StageDetail.State(stageID: stageLocalID("meadow"), eventID: eventID)
        }

        state.eventViewerState.selectedScheduleID = scheduleLocalID("friday")

        #expect(state.resolvedSelectedScheduleID == scheduleLocalID("friday"))
        #expect(state.selectedSchedulePerformances.map(\.title) == ["Meadow Friday"])

        state.eventViewerState.selectedScheduleID = scheduleLocalID("saturday")

        #expect(state.selectedSchedulePerformances.map(\.title) == ["Meadow Saturday"])

        state.eventViewerState.selectedScheduleID = scheduleLocalID("missing")

        #expect(state.resolvedSelectedScheduleID == scheduleLocalID("friday"))
    }

    @Test
    func stageDetailPerformanceTapPresentsPerformanceDetail() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let performanceID = performanceLocalID("meadow-friday")
        let friday = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One", timeZone: timeZone)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "friday", date: friday)
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "meadow-friday",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(friday.at(hour: 18, in: timeZone)),
                endTime: try #require(friday.at(hour: 19, in: timeZone)),
                title: "Meadow Friday"
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            Store(initialState: StageDetail.State(stageID: stageLocalID("meadow"), eventID: eventID)) {
                StageDetail()
            }
        }

        await store.send(.performanceButtonTapped(performanceID))?.value

        #expect(store.destination?.performanceDetail?.performanceID == performanceID)
    }

    @Test
    func scheduleViewerFetchesSchedulesForEventInOrder() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let otherEventID = eventID("event-2")
        let friday = try #require(LocalDate("2026-08-07"))
        let saturday = try #require(LocalDate("2026-08-08"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One", timeZone: timeZone)
            try Self.insertEvent(db, id: otherEventID, name: "Event Two", timeZone: timeZone)
            try Self.insertSchedule(
                db,
                eventID: selectedEventID,
                scheduleID: "friday-late",
                date: friday,
                startsAt: friday.at(hour: 20, in: timeZone),
                customTitle: "Friday Late"
            )
            try Self.insertSchedule(
                db,
                eventID: selectedEventID,
                scheduleID: "saturday",
                date: saturday,
                startsAt: saturday.at(hour: 12, in: timeZone),
                customTitle: "Saturday"
            )
            try Self.insertSchedule(
                db,
                eventID: selectedEventID,
                scheduleID: "friday-early",
                date: friday,
                startsAt: friday.at(hour: 18, in: timeZone),
                customTitle: "Friday Early"
            )
            try Self.insertSchedule(
                db,
                eventID: otherEventID,
                scheduleID: "other",
                date: friday,
                startsAt: friday.at(hour: 17, in: timeZone),
                customTitle: "Other"
            )
        }

        let schedules = try await database.read { db in
            try ScheduleViewer.schedulesQuery(eventID: selectedEventID).fetchAll(db)
        }

        #expect(schedules.map(\.id.scheduleID) == [
            scheduleLocalID("friday-early"),
            scheduleLocalID("friday-late"),
            scheduleLocalID("saturday"),
        ])
    }

    @Test
    func scheduleViewerFetchesPerformancesForSelectedScheduleInOrder() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let otherEventID = eventID("event-2")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One", timeZone: timeZone)
            try Self.insertEvent(db, id: otherEventID, name: "Event Two", timeZone: timeZone)
            try Self.insertStage(db, eventID: selectedEventID, stageID: "meadow", name: "Meadow")
            try Self.insertStage(db, eventID: otherEventID, stageID: "other-stage", name: "Other")
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "friday", date: date)
            try Self.insertSchedule(db, eventID: selectedEventID, scheduleID: "saturday", date: date)
            try Self.insertSchedule(db, eventID: otherEventID, scheduleID: "other", date: date)
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "closing",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 22, in: timeZone)),
                endTime: try #require(date.at(hour: 23, in: timeZone)),
                title: "Closing"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "opening",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 18, in: timeZone)),
                endTime: try #require(date.at(hour: 19, in: timeZone)),
                title: "Opening"
            )
            try Self.insertPerformance(
                db,
                eventID: selectedEventID,
                performanceID: "other-day",
                stageID: "meadow",
                scheduleID: "saturday",
                startTime: try #require(date.at(hour: 17, in: timeZone)),
                endTime: try #require(date.at(hour: 18, in: timeZone)),
                title: "Other Day"
            )
            try Self.insertPerformance(
                db,
                eventID: otherEventID,
                performanceID: "other-event",
                stageID: "other-stage",
                scheduleID: "other",
                startTime: try #require(date.at(hour: 16, in: timeZone)),
                endTime: try #require(date.at(hour: 17, in: timeZone)),
                title: "Other Event"
            )
        }

        let performances = try await database.read { db in
            try ScheduleViewer.performancesQuery(
                eventID: selectedEventID,
                scheduleID: scheduleLocalID("friday")
            )
            .fetchAll(db)
        }

        #expect(performances.map(\.title) == ["Opening", "Closing"])
    }

    @Test
    func scheduleTimelineCardsWrapPerformancesAndBuildBufferedRange() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let openingStart = try #require(date.at(hour: 18, in: timeZone))
        let openingEnd = try #require(date.at(hour: 19, in: timeZone))
        let closingStart = try #require(date.at(hour: 20, in: timeZone))
        let closingEnd = try #require(date.at(hour: 21, in: timeZone))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One", timeZone: timeZone)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "friday", date: date)
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "closing",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: closingStart,
                endTime: closingEnd,
                title: "Closing"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "opening",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: openingStart,
                endTime: openingEnd,
                title: "Opening"
            )
        }

        let performanceRows = try await database.read { db in
            try PerformanceRow.all(
                eventID: eventID,
                scheduleID: scheduleLocalID("friday")
            )
            .fetchAll(db)
        }
        let performances = performanceRows.map(\.performance)
        let cards = performances.map(SchedulePerformanceTimelineCard.init)
        let timeRange = try #require(
            ScheduleStageTimelinePage.timeRange(
                for: performances,
                buffer: 30 * 60
            )
        )

        #expect(cards.map(\.id) == [
            performanceLocalID("opening"),
            performanceLocalID("closing"),
        ])
        #expect(cards.first?.dateInterval.start == openingStart)
        #expect(cards.first?.dateInterval.end == openingEnd)
        #expect(timeRange.start == openingStart.addingTimeInterval(-30 * 60))
        #expect(timeRange.end == closingEnd.addingTimeInterval(30 * 60))
    }

    @Test
    func manyStagesTimelineCardsUseVisibleStageOrderAsLanes() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One", timeZone: timeZone)
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "friday", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "late", name: "Late", sortIndex: 2)
            try Self.insertStage(db, eventID: eventID, stageID: "main", name: "Main", sortIndex: 1)
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "late-set",
                stageID: "late",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 18, in: timeZone)),
                endTime: try #require(date.at(hour: 19, in: timeZone)),
                title: "Late Set"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "main-set",
                stageID: "main",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 20, in: timeZone)),
                endTime: try #require(date.at(hour: 21, in: timeZone)),
                title: "Main Set"
            )
        }

        let stages = try await database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }
        let performanceRows = try await database.read { db in
            try PerformanceRow.all(
                eventID: eventID,
                scheduleID: scheduleLocalID("friday")
            )
            .fetchAll(db)
        }
        let cards = ScheduleManyStagesAtOnceView.timelineCards(
            performanceRows: performanceRows,
            stages: stages
        )
        let laneByPerformanceID = Dictionary(
            uniqueKeysWithValues: cards.map { ($0.id, $0.groupWidth.lowerBound) }
        )

        #expect(stages.map(\.id.stageID) == [
            stageLocalID("main"),
            stageLocalID("late"),
        ])
        #expect(laneByPerformanceID[performanceLocalID("main-set")] == 0)
        #expect(laneByPerformanceID[performanceLocalID("late-set")] == 1)
        #expect(Set(cards.map(\.groupWidth.upperBound)) == Set([0, 1]))
    }

    @Test
    func `stages with performances are shown before empty stages`() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("sparse-friday")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Sparse Friday", timeZone: timeZone)
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "friday", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow", sortIndex: 1)
            try Self.insertStage(db, eventID: eventID, stageID: "amp", name: "Amp", sortIndex: 2)
            try Self.insertStage(db, eventID: eventID, stageID: "grove", name: "Grove", sortIndex: 3)
            try Self.insertStage(db, eventID: eventID, stageID: "lake", name: "Lake", sortIndex: 4)
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "amp-opening",
                stageID: "amp",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 18, in: timeZone)),
                endTime: try #require(date.at(hour: 19, in: timeZone)),
                title: "Amp Opening"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "lake-opening",
                stageID: "lake",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 19, in: timeZone)),
                endTime: try #require(date.at(hour: 20, in: timeZone)),
                title: "Lake Opening"
            )
        }

        // Friday opens at Amp and Lake, so those stages lead without losing their configured order.
        let stages = try await database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }
        let performances = try await database.read { db in
            try PerformanceRow.all(
                eventID: eventID,
                scheduleID: scheduleLocalID("friday")
            )
            .fetchAll(db)
            .map(\.performance)
        }
        let orderedStages = ScheduleViewer.orderedStages(
            stages,
            performances: performances
        )

        expectNoDifference(
            orderedStages.map(\.id.stageID),
            [
                stageLocalID("amp"),
                stageLocalID("lake"),
                stageLocalID("meadow"),
                stageLocalID("grove"),
            ]
        )
        expectNoDifference(
            ScheduleViewer.unavailableStageIDs(
                stages: orderedStages,
                performances: performances
            ),
            Set([stageLocalID("meadow"), stageLocalID("grove")])
        )

        // The empty-stage message names the schedule category, day, and stage exactly.
        let meadow = try #require(stages.first { $0.id.stageID == stageLocalID("meadow") })
        expectNoDifference(
            ScheduleViewer.emptyStageTitle(
                scheduleDivision: .schedule,
                scheduleTitle: "Friday",
                stage: meadow
            ),
            "No Schedule on Friday at Meadow"
        )
    }

    @Test
    func `empty schedule titles are friendly`() {
        expectNoDifference(
            ScheduleViewer.emptyScheduleTitle(
                scheduleDivision: .schedule,
                scheduleTitle: "Friday"
            ),
            "No Schedule on Friday"
        )
        expectNoDifference(
            ScheduleViewer.emptyScheduleTitle(
                scheduleDivision: .init(category: OMERecord.Stage.Category("workshop")),
                scheduleTitle: "Friday"
            ),
            "No Workshops on Friday"
        )
    }

    @Test
    func manyStagesTimelineGroupsKeepEmptyStageLanes() {
        #expect(ScheduleManyStagesAtOnceView.timelineGroups(stageCount: 4) == [0, 1, 2, 3])
    }

    @Test
    func manyStagesContentWidthShowsPartialLastStageOnCompactLayouts() {
        let width = ScheduleManyStagesAtOnceView.contentWidth(
            availableWidth: 393,
            stageCount: 3,
            minimumStageLaneWidth: 132,
            hourLabelsWidth: 43
        )

        #expect(width == 463)
    }

    @Test
    func manyStagesContentWidthDoesNotAddOverflowCueForSingleStage() {
        let width = ScheduleManyStagesAtOnceView.contentWidth(
            availableWidth: 393,
            stageCount: 1,
            minimumStageLaneWidth: 132,
            hourLabelsWidth: 43
        )

        #expect(width == 393)
    }

    @Test
    func manyStagesContentWidthDoesNotAddOverflowCueForTwoStages() {
        let width = ScheduleManyStagesAtOnceView.contentWidth(
            availableWidth: 393,
            stageCount: 2,
            minimumStageLaneWidth: 132,
            hourLabelsWidth: 43
        )

        #expect(width == 393)
    }

    @Test
    func manyStagesContentWidthKeepsMinimumLaneWidthWhenCompactTargetWouldShrinkLanes() {
        let width = ScheduleManyStagesAtOnceView.contentWidth(
            availableWidth: 320,
            stageCount: 4,
            minimumStageLaneWidth: 132,
            hourLabelsWidth: 43
        )

        #expect(width == 571)
    }

    @Test
    func manyStagesContentWidthDoesNotAddCompactStageRevealToWideLayouts() {
        let width = ScheduleManyStagesAtOnceView.contentWidth(
            availableWidth: 700,
            stageCount: 3,
            minimumStageLaneWidth: 132,
            hourLabelsWidth: 43
        )

        #expect(width == 700)
    }

    @Test
    func manyStagesHorizontalLaneHeightUsesAvailableHeight() {
        let laneHeight = ScheduleManyStagesAtOnceView.horizontalStageLaneHeight(
            availableHeight: 700,
            stageCount: 4,
            hourLabelsHeight: 32,
            minimumStageLaneHeight: 84
        )

        #expect(laneHeight == 167)
    }

    @Test
    func manyStagesHorizontalLaneHeightKeepsMinimumHeight() {
        let laneHeight = ScheduleManyStagesAtOnceView.horizontalStageLaneHeight(
            availableHeight: 300,
            stageCount: 4,
            hourLabelsHeight: 32,
            minimumStageLaneHeight: 84
        )

        #expect(laneHeight == 84)
    }

    @Test
    func scheduleViewerDefaultsToSingleStageKind() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            ScheduleViewer.State(eventID: eventID)
        }

        #expect(state.scheduleKind == .singleStageAtOnce)
    }

    @Test
    func scheduleViewerKindButtonChangesKind() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            TestStore(initialState: ScheduleViewer.State(eventID: eventID)) {
                ScheduleViewer()
            }
        }

        store.send(.scheduleKindButtonTapped(.allStagesAtOnce(.vertical)))

        #expect(store.state.scheduleKind == .allStagesAtOnce(.vertical))

        store.send(.scheduleKindButtonTapped(.list))

        #expect(store.state.scheduleKind == .list)
    }

    @Test
    func scheduleViewerKindButtonChangesManyStageOrientation() throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            TestStore(initialState: ScheduleViewer.State(eventID: eventID)) {
                ScheduleViewer()
            }
        }

        store.send(.scheduleKindButtonTapped(.allStagesAtOnce(.horizontal)))

        #expect(store.state.scheduleKind == .allStagesAtOnce(.horizontal))

        store.send(.scheduleKindButtonTapped(.allStagesAtOnce(.vertical)))

        #expect(store.state.scheduleKind == .allStagesAtOnce(.vertical))
    }

    @Test
    func addScheduleDefaultsToEventStartDate() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let eventStartDate = try #require(LocalDate("2026-08-07"))
        let today = try #require(LocalDate("2026-06-01"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(today.at(hour: 12, in: timeZone))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(
                db,
                id: eventID,
                name: "Event One",
                startDate: eventStartDate,
                timeZone: timeZone
            )
        }
        var state = withDependencies {
            $0.context = .test
            $0.date = .constant(now)
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.defaultEventTimeZone = timeZone
        } operation: {
            EventViewer.State(eventID: eventID)
        }
        state.selectedFeature = .contributors

        withDependencies {
            $0.context = .test
            $0.date = .constant(now)
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.defaultEventTimeZone = timeZone
        } operation: {
            state.handleEditingIntent(.addSchedule(eventID))
        }

        let editSchedule = try #require(state.destination?.scheduleForm)
        expectNoDifference(state.selectedFeature, .contributors)
        expectNoDifference(editSchedule.scheduleDate, eventStartDate)
        expectNoDifference(editSchedule.customTitle, "")
        expectNoDifference(editSchedule.inferredTitle, "Friday")
        expectNoDifference(editSchedule.sourceFileName, "2026-08-07")
    }

    @Test
    func scheduleNowDestinationPrefersSelectedCurrentScheduleAndActivePerformance() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("schedule-now-selected")
        let date = try #require(LocalDate("2026-08-07"))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Schedule Now")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "first", date: date)
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "selected", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "first-active",
                stageID: "meadow",
                scheduleID: "first",
                startTime: Date(timeIntervalSince1970: 100),
                endTime: Date(timeIntervalSince1970: 300),
                title: "First Active"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "selected-active",
                stageID: "meadow",
                scheduleID: "selected",
                startTime: Date(timeIntervalSince1970: 120),
                endTime: Date(timeIntervalSince1970: 320),
                title: "Selected Active"
            )
        }

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            ScheduleViewer.State(eventID: eventID)
        }
        let destination = state.currentTimeDestination(
            currentDate: Date(timeIntervalSince1970: 200),
            selectedScheduleID: scheduleLocalID("selected"),
            buffer: 3_600
        )

        expectNoDifference(destination?.scheduleID, scheduleLocalID("selected"))
        expectNoDifference(destination?.performanceID, performanceLocalID("selected-active"))
    }

    @Test
    func scheduleNowDestinationSwitchesSchedulesAndTargetsNextThenLastPerformance() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("schedule-now-switch")
        let date = try #require(LocalDate("2026-08-07"))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Schedule Now")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "past", date: date)
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "current", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "past-set",
                stageID: "meadow",
                scheduleID: "past",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Past Set"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "opening",
                stageID: "meadow",
                scheduleID: "current",
                startTime: Date(timeIntervalSince1970: 10_000),
                endTime: Date(timeIntervalSince1970: 11_000),
                title: "Opening"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "closing",
                stageID: "meadow",
                scheduleID: "current",
                startTime: Date(timeIntervalSince1970: 12_000),
                endTime: Date(timeIntervalSince1970: 13_000),
                title: "Closing"
            )
        }

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            ScheduleViewer.State(eventID: eventID)
        }
        let nextDestination = state.currentTimeDestination(
            currentDate: Date(timeIntervalSince1970: 9_000),
            selectedScheduleID: scheduleLocalID("past"),
            buffer: 3_600
        )
        let lastDestination = state.currentTimeDestination(
            currentDate: Date(timeIntervalSince1970: 15_500),
            selectedScheduleID: scheduleLocalID("past"),
            buffer: 3_600
        )

        expectNoDifference(nextDestination?.scheduleID, scheduleLocalID("current"))
        expectNoDifference(nextDestination?.performanceID, performanceLocalID("opening"))
        expectNoDifference(lastDestination?.scheduleID, scheduleLocalID("current"))
        expectNoDifference(lastDestination?.performanceID, performanceLocalID("closing"))
    }

    @Test
    func scheduleNowDestinationHandlesOvernightRangesAndHidesOutsideRenderedTime() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("schedule-now-overnight")
        let date = try #require(LocalDate("2026-08-07"))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Schedule Now")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "overnight", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "late-set",
                stageID: "meadow",
                scheduleID: "overnight",
                startTime: Date(timeIntervalSince1970: 86_000),
                endTime: Date(timeIntervalSince1970: 90_000),
                title: "Late Set"
            )
        }

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            ScheduleViewer.State(eventID: eventID)
        }
        let overnightDestination = state.currentTimeDestination(
            currentDate: Date(timeIntervalSince1970: 88_000),
            selectedScheduleID: nil,
            buffer: 3_600
        )
        let outsideDestination = state.currentTimeDestination(
            currentDate: Date(timeIntervalSince1970: 94_000),
            selectedScheduleID: nil,
            buffer: 3_600
        )
        let unavailableDestination = state.currentTimeDestination(
            currentDate: nil,
            selectedScheduleID: nil,
            buffer: 3_600
        )

        expectNoDifference(overnightDestination?.performanceID, performanceLocalID("late-set"))
        #expect(outsideDestination == nil)
        #expect(unavailableDestination == nil)
    }

    @Test
    func scheduleViewerStatePersistsModeAndStagePerDivision() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let workshopDivision = ScheduleViewer.ScheduleDivision(
            category: OMERecord.Stage.Category("workshop")
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            TestStore(initialState: ScheduleViewer.State(eventID: eventID)) {
                ScheduleViewer()
            }
        }

        await store.modify {
            $0.scheduleKind = .allStagesAtOnce(.horizontal)
            $0.selectedStageID = stageLocalID("main")
            $0.showStageNameLabels = true
        }?.value
        await store.dismount()

        let storedState = try await database.read { db in
            try ScheduleViewerStateRequest(
                eventID: eventID,
                scheduleDivision: .schedule
            )
            .fetch(db)
        }

        let restoredStore = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            TestStore(initialState: ScheduleViewer.State(eventID: eventID)) {
                ScheduleViewer()
            }
        }

        try await restoredStore.state.$persistedScheduleViewerState.load(
            ScheduleViewerState.rows(
                eventID: eventID,
                scheduleDivision: .schedule
            )
        )
        restoredStore.expect {
            $0.scheduleViewerState = storedState
        }

        let workshopState = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            ScheduleViewer.State(
                eventID: eventID,
                scheduleDivision: workshopDivision
            )
        }

        #expect(storedState.scheduleKind == .allStagesAtOnce(.horizontal))
        #expect(storedState.selectedStageID == stageLocalID("main"))
        #expect(storedState.showStageNameLabels)
        #expect(restoredStore.state.scheduleKind == .allStagesAtOnce(.horizontal))
        #expect(restoredStore.state.selectedStageID == stageLocalID("main"))
        #expect(restoredStore.state.showStageNameLabels)
        #expect(workshopState.scheduleKind == .singleStageAtOnce)
        #expect(workshopState.selectedStageID == nil)
        #expect(!workshopState.showStageNameLabels)
        await restoredStore.dismount()
    }

    @Test
    func scheduleViewerStatePersistenceMergesStaleFeatureChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        var storedState = ScheduleViewerState(
            eventID: eventID,
            scheduleDivision: .schedule
        )
        storedState.selectedStageID = stageLocalID("main")
        storedState.showStageNameLabels = true
        storedState.filteringFavorites = true
        storedState.scheduleKind = .allStagesAtOnce(.horizontal)
        storedState.syncScheduleKindStorage()
        let stateToStore = storedState
        try await database.write { db in
            try ScheduleViewerState.insert { stateToStore }.execute(db)
        }

        let staleState = ScheduleViewerState(
            eventID: eventID,
            scheduleDivision: .schedule
        )
        var changedState = staleState
        changedState.scheduleKind = .list
        let stateToPersist = changedState
        try await database.write { db in
            try ScheduleViewerState.persistChanges(
                from: staleState,
                to: stateToPersist,
                eventID: eventID,
                scheduleDivision: .schedule,
                in: db
            )
        }

        let mergedState = try await database.read { db in
            try ScheduleViewerStateRequest(
                eventID: eventID,
                scheduleDivision: .schedule
            )
            .fetch(db)
        }
        #expect(mergedState.selectedStageID == stageLocalID("main"))
        #expect(mergedState.showStageNameLabels)
        #expect(mergedState.filteringFavorites)
        #expect(mergedState.scheduleKind == .list)
    }

    @Test
    func scheduleViewerStateMigratesLegacyManyStageOrientation() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")

        try await database.write { db in
            try db.execute(
                sql: """
                INSERT INTO "scheduleViewerState" (
                  "organizerID",
                  "eventID",
                  "category",
                  "scheduleKind",
                  "manyStagesOrientation"
                )
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    String(describing: eventID.organizerID),
                    eventID.eventID.rawValue.rawValue,
                    ScheduleViewer.ScheduleDivision.schedule.id,
                    "allStagesAtOnce",
                    "horizontal",
                ]
            )
        }

        let state = try await database.read { db in
            try ScheduleViewerStateRequest(
                eventID: eventID,
                scheduleDivision: .schedule
            )
            .fetch(db)
        }

        #expect(state.scheduleKind == .allStagesAtOnce(.horizontal))
        #expect(state.legacyManyStagesOrientation == .horizontal)
    }

    @Test
    func scheduleViewerResolvedStageFallsBackToFirstOrderedStage() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(db, eventID: eventID, stageID: "late", name: "Late", sortIndex: 2)
            try Self.insertStage(db, eventID: eventID, stageID: "main", name: "Main", sortIndex: 1)
        }

        let stages = try await database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }

        #expect(
            ScheduleViewer.resolvedSelectedStageID(
                selectedStageID: nil,
                stages: stages
            ) == stageLocalID("main")
        )
        #expect(
            ScheduleViewer.resolvedSelectedStageID(
                selectedStageID: stageLocalID("missing"),
                stages: stages
            ) == stageLocalID("main")
        )
        #expect(
            ScheduleViewer.resolvedSelectedStageID(
                selectedStageID: stageLocalID("late"),
                stages: stages
            ) == stageLocalID("late")
        )
    }

    @Test
    func eventViewerNeedsStageDisambiguationOnlyWithMultipleStages() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(
                db,
                eventID: eventID,
                stageID: OMERecord.Stage.singletonID.rawValue.rawValue,
                name: OMERecord.Stage.singletonName,
                sortIndex: 1
            )
        }

        func state() -> EventViewer.State {
            withDependencies {
                $0.context = .test
                $0.defaultDatabase = database
                $0.defaultEventID = eventID
            } operation: {
                EventViewer.State(eventID: eventID)
            }
        }

        #expect(state().needsStageDisambiguation == false)

        try await database.write { db in
            try Self.insertStage(db, eventID: eventID, stageID: "main", name: "Main", sortIndex: 2)
        }

        #expect(state().needsStageDisambiguation)
    }

    @Test
    func scheduleViewerBuildsDivisionsFromStageCategories() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(db, eventID: eventID, stageID: "main", name: "Main", sortIndex: 1)
            try Self.insertStage(
                db,
                eventID: eventID,
                stageID: "workshop",
                name: "Workshop",
                category: OMERecord.Stage.Category("workshop"),
                sortIndex: 2
            )
            try Self.insertStage(
                db,
                eventID: eventID,
                stageID: "second-workshop",
                name: "Second Workshop",
                category: OMERecord.Stage.Category("workshop"),
                sortIndex: 3
            )
        }

        let stages = try await database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }
        let divisions = ScheduleViewer.scheduleDivisions(stages: stages)

        #expect(divisions.map(\.id) == ["schedule", "workshop"])
        #expect(divisions.map(\.title) == ["Schedule", "Workshops"])
    }

    @Test
    func scheduleViewerFiltersStagesAndPerformancesToDivision() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let workshopDivision = ScheduleViewer.ScheduleDivision(
            category: OMERecord.Stage.Category("workshop")
        )
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One", timeZone: timeZone)
            try Self.insertStage(db, eventID: eventID, stageID: "main", name: "Main", sortIndex: 1)
            try Self.insertStage(
                db,
                eventID: eventID,
                stageID: "workshop",
                name: "Workshop",
                category: OMERecord.Stage.Category("workshop"),
                sortIndex: 2
            )
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "friday", date: date)
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "concert",
                stageID: "main",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 18, in: timeZone)),
                endTime: try #require(date.at(hour: 19, in: timeZone)),
                title: "Concert"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "workshop",
                stageID: "workshop",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 20, in: timeZone)),
                endTime: try #require(date.at(hour: 21, in: timeZone)),
                title: "Workshop"
            )
        }

        let stages = try await database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }
        let performanceRows = try await database.read { db in
            try PerformanceRow.all(
                eventID: eventID,
                scheduleID: scheduleLocalID("friday")
            )
            .fetchAll(db)
        }
        let visibleStages = ScheduleViewer.visibleStages(
            stages: stages,
            division: workshopDivision
        )
        let visiblePerformances = ScheduleViewer.visiblePerformances(
            performanceRows: performanceRows,
            scheduleID: scheduleLocalID("friday"),
            stages: visibleStages
        )
        let timelineCards = ScheduleManyStagesAtOnceView.timelineCards(
            performanceRows: visiblePerformances,
            stages: visibleStages
        )

        #expect(visibleStages.map(\.id.stageID) == [stageLocalID("workshop")])
        #expect(visiblePerformances.map(\.title) == ["Workshop"])
        #expect(timelineCards.map(\.performance.title) == ["Workshop"])
        #expect(timelineCards.map(\.stage.id.stageID) == [stageLocalID("workshop")])
    }

    @Test
    func eventViewerBuildsScheduleDivisionTabsFromStageCategories() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let workshopDivision = ScheduleViewer.ScheduleDivision(
            category: OMERecord.Stage.Category("workshop")
        )
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(db, eventID: eventID, stageID: "main", name: "Main", sortIndex: 1)
            try Self.insertStage(
                db,
                eventID: eventID,
                stageID: "workshop",
                name: "Workshop",
                category: workshopDivision.category,
                sortIndex: 2
            )
        }
        let workspace = WorkspaceContext(
            id: EditingWorkspaceRecord.ID(localEventID: eventID),
            sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: database)
        )
        let grant = Shared<AuthoringGrant?>(
            value: AuthoringGrant(principal: .local, role: .owner, workspace: workspace)
        )

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.useWorkspaceContext(
                workspace.mounting(grant: SharedReader(grant))
            )
        } operation: {
            EventViewer.State(eventID: eventID)
        }

        #expect(Array(state.installedFeatures.prefix(2).map(\.description)) == [
            "schedule",
            "schedule:workshop",
        ])
        #expect(state.scheduleViewers.map { $0.state.scheduleDivision.id } == ["schedule", "workshop"])
        #expect(state.installedFeatures.contains(.workspace))
        #expect(state.installedFeatures.contains(.settings))
        #expect(state.eventWorkspace?.eventID == eventID)
        #expect(state.eventSettings?.eventID == eventID)
    }

    @Test
    func `empty stage links open another schedule category`() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("schedule-category-link")
        let workshopDivision = ScheduleViewer.ScheduleDivision(
            category: OMERecord.Stage.Category("workshop")
        )
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Category Links")
            try Self.insertStage(db, eventID: eventID, stageID: "main", name: "Main", sortIndex: 1)
            try Self.insertStage(
                db,
                eventID: eventID,
                stageID: "workshop",
                name: "Workshop",
                category: workshopDivision.category,
                sortIndex: 2
            )
        }

        // The attendee starts on the regular Schedule and taps the Workshops link below an empty stage.
        let store = withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            Store(initialState: EventViewer.State(eventID: eventID)) {
                EventViewer()
            }
        }
        let scheduleStore = try #require(
            store.spawn(\.scheduleViewers).first {
                $0.scheduleDivision == .schedule
            }
        )
        let singleStageStore = scheduleStore.spawn(\.singleStageAtOnce)

        await singleStageStore.send(
            .scheduleDivisionButtonTapped(workshopDivision)
        )?.value

        expectNoDifference(store.selectedFeature, .schedule(workshopDivision))

        await scheduleStore.spawn(\.manyStagesAtOnce).send(
            .scheduleDivisionButtonTapped(.schedule)
        )?.value

        expectNoDifference(store.selectedFeature, .schedule(.schedule))

        await scheduleStore.spawn(\.performanceList).send(
            .scheduleDivisionButtonTapped(workshopDivision)
        )?.value

        expectNoDifference(store.selectedFeature, .schedule(workshopDivision))
    }

    @Test
    func eventViewerStartsInAttendeeModeWhenAuthoringIsNotAllowed() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("attendee-mode-event")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Attendee Mode Event")
        }

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            EventViewer.State(eventID: eventID)
        }

        #expect(state.authoringAccess == .attendee)
        #expect(!state.installedFeatures.contains(.workspace))
        #expect(state.installedFeatures.contains(.settings))
        #expect(state.eventWorkspace == nil)
        #expect(state.eventSettings?.eventID == eventID)
    }

    @Test
    func eventViewerStatePersistsSelectedSchedulePerEvent() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let workshopDivision = ScheduleViewer.ScheduleDivision(
            category: OMERecord.Stage.Category("workshop")
        )

        let store = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: EventViewer.State(
                    eventID: eventID,
                    authoringGrant: SharedReader(value: nil),
                    features: [
                        .schedule(.schedule),
                        .schedule(workshopDivision),
                    ]
                )
            ) {
                EventViewer()
            }
        }

        await store.modify {
            $0.eventViewerState.selectedScheduleID = scheduleLocalID("thursday")
        }?.value
        await store.dismount()

        let storedState = try await database.read { db in
            try EventViewerStateRequest(eventID: eventID).fetch(db)
        }

        let restoredStore = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: EventViewer.State(
                    eventID: eventID,
                    authoringGrant: SharedReader(value: nil),
                    features: [
                        .schedule(.schedule),
                        .schedule(workshopDivision),
                    ]
                )
            ) {
                EventViewer()
            }
        }

        try await restoredStore.state.$persistedEventViewerState.load(
            EventViewerState.where { $0.id.eq(eventID) }
        )
        restoredStore.expect {
            $0.eventViewerState = storedState
        }

        #expect(store.state.scheduleViewers.map { $0.state.scheduleDivision.id } == ["schedule", "workshop"])
        #expect(storedState.selectedScheduleID == scheduleLocalID("thursday"))
        #expect(restoredStore.state.eventViewerState.selectedScheduleID == scheduleLocalID("thursday"))
        await restoredStore.dismount()
    }

    @Test
    func eventViewerStatePersistenceMergesStaleFeatureChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let userScheduleID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-00000000e001")
        )
        var storedState = EventViewerState(id: eventID)
        storedState.selectedScheduleID = scheduleLocalID("thursday")
        storedState.didInitializeUserSchedules = true
        let stateToStore = storedState
        try await database.write { db in
            try UserSchedule.insert {
                UserSchedule(
                    id: userScheduleID,
                    eventID: eventID,
                    title: "Favorites"
                )
            }
            .execute(db)
            try EventViewerState.insert { stateToStore }.execute(db)
        }

        let staleState = EventViewerState(id: eventID)
        var changedState = staleState
        changedState.selectedUserScheduleID = userScheduleID
        let stateToPersist = changedState
        try await database.write { db in
            try EventViewerState.persistChanges(
                from: staleState,
                to: stateToPersist,
                in: db
            )
        }

        let mergedState = try await database.read { db in
            try EventViewerStateRequest(eventID: eventID).fetch(db)
        }
        #expect(mergedState.selectedScheduleID == scheduleLocalID("thursday"))
        #expect(mergedState.selectedUserScheduleID == userScheduleID)
        #expect(mergedState.didInitializeUserSchedules)
    }

    @Test
    func scheduleViewerStageFallbackIsScopedToDivision() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let workshopDivision = ScheduleViewer.ScheduleDivision(
            category: OMERecord.Stage.Category("workshop")
        )
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(db, eventID: eventID, stageID: "main", name: "Main", sortIndex: 1)
            try Self.insertStage(
                db,
                eventID: eventID,
                stageID: "workshop",
                name: "Workshop",
                category: workshopDivision.category,
                sortIndex: 2
            )
        }

        var state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            var state = ScheduleViewer.State(
                eventID: eventID,
                scheduleDivision: workshopDivision
            )
            state.selectedStageID = stageLocalID("main")
            return state
        }

        #expect(state.visibleStages.map(\.id.stageID) == [stageLocalID("workshop")])
        #expect(state.resolvedSelectedStageID == stageLocalID("workshop"))
        #expect(state.selectedStageID == stageLocalID("workshop"))

        state.selectedStageID = stageLocalID("main")

        #expect(state.scheduleViewerState.selectedStageID == stageLocalID("workshop"))
    }

    @Test
    func singleStageScheduleSelectionBindingNormalizesToVisibleStage() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let workshopDivision = ScheduleViewer.ScheduleDivision(
            category: OMERecord.Stage.Category("workshop")
        )
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(db, eventID: eventID, stageID: "main", name: "Main", sortIndex: 1)
            try Self.insertStage(
                db,
                eventID: eventID,
                stageID: "workshop",
                name: "Workshop",
                category: workshopDivision.category,
                sortIndex: 2
            )
        }

        var state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            var state = ScheduleSingleStageAtOnce.State(
                eventID: eventID,
                scheduleDivision: workshopDivision
            )
            state.scheduleViewerState.selectedStageID = stageLocalID("main")
            return state
        }

        #expect(state.visibleStages.map(\.id.stageID) == [stageLocalID("workshop")])
        #expect(state.selectedStageID == stageLocalID("workshop"))
        #expect(state.resolvedSelectedStageID == stageLocalID("workshop"))
        #expect(state.scheduleViewerState.selectedStageID == stageLocalID("main"))

        state.selectedStageID = state.selectedStageID

        #expect(state.scheduleViewerState.selectedStageID == stageLocalID("workshop"))
    }

    @Test
    func scheduleViewerPerformanceTapPresentsDetail() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let performanceID = performanceLocalID("opening")
        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            let store = Store(initialState: ScheduleViewer.State(eventID: eventID)) {
                ScheduleViewer()
            }
            let scheduleStore: StoreOf<ScheduleSingleStageAtOnce> = store.spawn(\.singleStageAtOnce)

            await scheduleStore.send(.performanceButtonTapped(performanceID))?.value

            #expect(store.destination?.performanceDetail?.performanceID == performanceID)
        }
    }

    @Test
    func performanceDetailQueriesCoreFields() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let recordingURL = try #require(URL(string: "https://example.com/recording"))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One", timeZone: timeZone)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "friday", date: date)
            try Self.insertContributor(db, eventID: eventID, contributorID: "amy", name: "Amy")
            try Self.insertContributor(db, eventID: eventID, contributorID: "zara", name: "Zara")
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "opening",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 18, in: timeZone)),
                endTime: try #require(date.at(hour: 19, in: timeZone)),
                title: "Opening",
                description: "First set",
                recordings: [ExternalPlatform.Asset(url: recordingURL)]
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "opening",
                contributorID: "zara"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "opening",
                contributorID: "amy"
            )
        }

        let performance = try await database.read { db in
            try #require(
                try PerformanceDetail.performanceQuery(
                    performanceID: performanceLocalID("opening"),
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }
        let contributors = try await database.read { db in
            try PerformanceDetail.contributorsQuery(
                performanceID: performanceLocalID("opening"),
                eventID: eventID
            )
            .fetchAll(db)
        }
        let stages = try await database.read { db in
            try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
        }

        #expect(performance.title == "Opening")
        #expect(performance.description == "First set")
        #expect(performance.recordings.map(\.url) == [recordingURL])
        #expect(stages.first { $0.id.stageID == performance.stageID }?.name == "Meadow")
        #expect(contributors.map(\.name) == ["Amy", "Zara"])
    }

    @Test
    func performanceDetailDisplaysPrimaryContributorsAtStageAndSupportBelow() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One", timeZone: timeZone)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "friday", date: date)
            try Self.insertContributor(
                db,
                eventID: eventID,
                contributorID: "stylust",
                name: "STYLUST"
            )
            try Self.insertContributor(
                db,
                eventID: eventID,
                contributorID: "oodra",
                name: "Oodra Movement"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "stylust-set",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 18, in: timeZone)),
                endTime: try #require(date.at(hour: 19, in: timeZone)),
                title: "STYLUST"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "stylust-set",
                contributorID: "oodra",
                billing: .supporting,
                role: "dancer",
                sortIndex: 0
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "stylust-set",
                contributorID: "stylust",
                billing: .primary,
                role: "dj",
                sortIndex: 1
            )
        }

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.defaultEventTimeZone = timeZone
        } operation: {
            PerformanceDetail.State(
                performanceID: performanceLocalID("stylust-set"),
                eventID: eventID
            )
        }

        expectNoDifference(state.headlineContributors.map(\.name), ["STYLUST"])
        expectNoDifference(
            state.displayedContributors.map(\.name),
            ["STYLUST", "Oodra Movement"]
        )
        expectNoDifference(
            state.displayedContributorCredits.compactMap(\.roleTitle),
            ["DJ", "Dancer"]
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.defaultEventTimeZone = timeZone
        } operation: {
            TestStore(
                initialState: PerformanceDetail.State(
                    performanceID: performanceLocalID("stylust-set"),
                    eventID: eventID
                )
            ) {
                PerformanceDetail()
            }
        }
        store.send(.contributorButtonTapped(contributorLocalID("stylust")))
        #expect(
            store.state.destination?.contributorDetail?.contributorID
                == contributorLocalID("stylust")
        )
    }

    @Test
    func contributorDetailPerformanceTapPresentsPerformanceDetail() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let date = try #require(LocalDate("2026-08-07"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let contributorID = contributorLocalID("amy")
        let performanceID = performanceLocalID("opening")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One", timeZone: timeZone)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "friday", date: date)
            try Self.insertContributor(db, eventID: eventID, contributorID: "amy", name: "Amy")
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "opening",
                stageID: "meadow",
                scheduleID: "friday",
                startTime: try #require(date.at(hour: 18, in: timeZone)),
                endTime: try #require(date.at(hour: 19, in: timeZone)),
                title: "Opening"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "opening",
                contributorID: "amy"
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.defaultEventTimeZone = timeZone
        } operation: {
            TestStore(
                initialState: ContributorDetail.State(
                    contributorID: contributorID,
                    eventID: eventID
                )
            ) {
                ContributorDetail()
            }
        }

        store.send(.performanceButtonTapped(performanceID))

        #expect(store.state.destination?.performanceDetail?.performanceID == performanceID)
    }

    @Test
    func contributorDetailFallsBackToFestivalHeroAndLogo() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("festival")
        let contributorID = contributorLocalID("artist")
        let festivalHeroURL = try #require(URL(string: "https://example.com/festival-hero.jpg"))
        let festivalLogoURL = try #require(URL(string: "https://example.com/festival-logo.png"))
        let festivalHero = OMERecord.ImageAsset(
            source: .url(festivalHeroURL),
            role: .hero,
            renderKind: .fullImage,
            materializationPolicy: .prefetchOnOpen
        )
        let festivalLogo = OMERecord.ImageAsset(
            source: .url(festivalLogoURL),
            role: .icon,
            renderKind: .transparent,
            materializationPolicy: .prefetchOnOpen
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try OMERecord.Event.insert {
                OMERecord.Event.Draft(
                    id: eventID,
                    name: "Festival",
                    timeZone: .current,
                    imageURL: festivalHeroURL,
                    iconImageURL: festivalLogoURL
                )
            }
            .execute(db)
            try Self.insertContributor(
                db,
                eventID: eventID,
                contributorID: "artist",
                name: "Artist"
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: ContributorDetail.State(
                    contributorID: contributorID,
                    eventID: eventID
                )
            ) {
                ContributorDetail()
            }
        }

        let eventCacheContext = LocalImageCacheContext(eventID: eventID)
        expectNoDifference(
            store.state.heroImageSources,
            [
                .primaryImage(
                    DisplayImageAsset(
                        asset: festivalHero,
                        cacheContext: eventCacheContext
                    )
                ),
                .logo(
                    DisplayImageAsset(
                        asset: festivalLogo,
                        cacheContext: eventCacheContext
                    )
                ),
            ]
        )
    }

    @Test
    func editContributorSavesChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("artist-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertContributor(db, eventID: eventID, contributorID: "artist-1", name: "Old Name")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = EditContributor.State(contributorID: contributorID, eventID: eventID)
            state.hasLoadedDraft = true
            state.form.value.name = " New Name "
            state.form.value.bio = " Updated bio "
            state.imageURL = "https://example.com/image.jpg"
            state.logoURL = " "
            var link = EditableContributorLink()
            link.url = "https://example.com"
            link.platformRawValue = ExternalPlatform.website.rawValue
            state.form.value.links = [link]

            return TestStore(initialState: state) {
                EditContributor()
            }
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

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
        #expect(contributor.bio == "Updated bio")
        #expect(contributor.imageURL?.absoluteString == "https://example.com/image.jpg")
        #expect(contributor.logoURL == nil)
        #expect(contributor.links?.map(\.url.absoluteString) == ["https://example.com"])
        #expect(contributor.links?.map(\.platform) == [.website])
    }

    @Test
    func editContributorImagePickerImportAddsImageThroughParentDestination() async throws {
        let eventID = eventID("event-1")
        let image = ImportImages.Configuration.contributorPhoto.importedImage(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000c001")!,
            title: "Contributor Photo",
            sourceName: "contributor-photo.png",
            sourceURL: URL(fileURLWithPath: "/tmp/contributor-photo.png"),
            mimeType: "image/png",
            data: Data("contributor-photo".utf8)
        )

        @Bindable var store = Store(initialState: EditContributor.State(eventID: eventID)) {
            EditContributor()
        }

        store.send(.photoImagePicker(.addButtonTapped))
        let importStore = try #require(
            $store.scope(\.destination, action: \.destination).photoImportImages.wrappedValue
        )
        importStore.send(.imagesImported([image]))
        await importStore.send(.saveButtonTapped)?.value

        await waitUntil { store.destination == nil }
        expectNoDifference(store.photoImagePicker.images.map(\.importedImage), [image])
        #expect(store.logoImagePicker.images.isEmpty)
    }

    @Test
    func `image picker shows remote URL and local filename`() throws {
        let remoteURL = try #require(
            URL(
                string: "https://wickedwoods.festivalpro.com/?getPublicFile&ENCSTR=qgHiinSYLIbtusbFnwpO"
            )
        )
        let remoteImage = ImageAssetPicker.ImageValue(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000c002"),
            asset: OMERecord.ImageAsset(
                source: .url(remoteURL),
                role: .photo,
                renderKind: .fullImage,
                materializationPolicy: .lazy
            )
        )

        // The contributor's remote endpoint keeps its complete URL, including the query.
        expectNoDifference(remoteImage.displaySource, remoteURL.absoluteString)

        let localImage = ImageAssetPicker.ImageValue(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000c003"),
            asset: OMERecord.ImageAsset(
                source: .url(URL(fileURLWithPath: "/tmp/contributor-photo.png")),
                role: .photo,
                renderKind: .fullImage,
                materializationPolicy: .lazy
            )
        )

        // A local asset stays concise because its filename identifies it.
        expectNoDifference(localImage.displaySource, "contributor-photo.png")
    }

    @Test
    func editContributorSaveSurfacesUnderlyingError() async throws {
        let database = try defaultDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("artist-1")

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = EditContributor.State(contributorID: contributorID, eventID: eventID)
            state.hasLoadedDraft = true
            state.form.value.name = "New Name"

            return TestStore(initialState: state) {
                EditContributor()
            }
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.isPresented)
        #expect(store.state.errorMessage?.hasPrefix("Unable to save contributor: ") == true)
        #expect(store.state.errorMessage != "Unable to save contributor.")
    }

    @Test
    func editContributorStoreBindingsSaveChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("artist-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertContributor(db, eventID: eventID, contributorID: "artist-1", name: "Old Name")
        }

        @Bindable var store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EditContributor.State(contributorID: contributorID, eventID: eventID)) {
                EditContributor()
            }
        }

        #expect(store.hasLoadedDraft)
        #expect(store.form.value.name == "Old Name")

        $store.form.value.name.wrappedValue = "New Name"
        await store.send(.saveButtonTapped)?.value

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
    }

    @Test
    func eventViewerContributorEditIntentPresentsContributorEditor() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("artist-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertContributor(db, eventID: eventID, contributorID: "artist-1", name: "Old Name")
        }

        var state = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            EventViewer.State(eventID: eventID)
        }
        state.selectedFeature = .schedule(.schedule)

        state.handleEditingIntent(
            .editContributor(
                eventID: eventID,
                contributorID: contributorID
            )
        )

        let editContributor = try #require(state.destination?.contributorForm)
        #expect(state.selectedFeature == .schedule(.schedule))
        #expect(editContributor.eventID == eventID)
        #expect(editContributor.mode.contributorID == contributorID)
        #expect(!editContributor.hasLoadedDraft)
    }

    @Test
    func eventViewerContributorEditDestinationSpawnsEditorAndLoadsDraft() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("wicked-woods-ome-2025")
        let contributorID = contributorLocalID("[IVY]")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Wicked Woods")
            try Self.insertContributor(db, eventID: eventID, contributorID: "[IVY]", name: "IVY")
        }

        try await withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            @Bindable var store = Store(initialState: OpenMusicEventAppRoot.State()) {
                OpenMusicEventAppRoot()
            }
            await store.send(.handleNavigationRequest(.event(eventID, nil)))?.value
            let eventAuthoringStore = try #require(
                $store.scope(\.destination, action: \.destination).eventViewer.wrappedValue
            )
            let authoringStore = eventAuthoringStore.scope(
                \.content,
                action: \.content
            )
            @Bindable var eventViewerStore = authoringStore.scope(
                \.content,
                action: \.content
            )
            @Bindable var contributorsStore = try #require(
                eventViewerStore.spawn(\.contributorsViewer)
            )
            await contributorsStore.send(.contributorButtonTapped(contributorID))?.value
            let detailStore = try #require(
                $contributorsStore
                    .scope(\.destination, action: \.destination)
                    .contributorDetail
                    .wrappedValue
            )

            await detailStore.send(.editButtonTapped)?.value
            await waitUntil {
                eventViewerStore.destination?.contributorForm?.hasLoadedDraft == true
            }

            let editContributor = try #require(
                $eventViewerStore
                    .scope(\.destination, action: \.destination)
                    .contributorForm
                    .wrappedValue
            )

            #expect(editContributor.hasLoadedDraft)
            #expect(editContributor.form.value.name == "IVY")
            #expect(editContributor.mode.contributorID == contributorID)
        }
    }

    @Test
    func eventViewerContributorFormDestinationStoreRoutesChildActions() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("artist-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertContributor(db, eventID: eventID, contributorID: "artist-1", name: "Artist One")
        }

        var state = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            EventViewer.State(eventID: eventID)
        }
        state.handleEditingIntent(
            .editContributor(
                eventID: eventID,
                contributorID: contributorID
            )
        )

        @Bindable var store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            Store(initialState: state) {
                EventViewer()
            }
        }
        let destinationStore = try #require(store.scope(\.destination, action: \.destination))
        let editContributorStore: StoreOf<EditContributor>
        switch EventViewer.Destination.switch(store: destinationStore) {
        case let .contributorForm(store):
            editContributorStore = store
        default:
            Issue.record("Expected contributor form destination")
            return
        }

        #expect(editContributorStore.form.value.links.isEmpty)

        await editContributorStore.send(.addLinkButtonTapped)?.value

        #expect(editContributorStore.form.value.links.count == 1)
        #expect(store.destination?.contributorForm?.form.value.links.count == 1)
    }

    @Test
    func eventViewerContactInfoEditorSavesMultipleReportingLinksToDefaultDatabase() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
        }

        var state = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            EventViewer.State(eventID: eventID)
        }
        state.handleEditingIntent(.editContactInfo(eventID))

        @Bindable var store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            Store(initialState: state) {
                EventViewer()
            }
        }

        let destinationStore = try #require(store.scope(\.destination, action: \.destination))
        let contactInfoStore: StoreOf<EditContactInfo>
        switch EventViewer.Destination.switch(store: destinationStore) {
        case let .contactInfoForm(store):
            contactInfoStore = store
        default:
            Issue.record("Expected contact info form destination")
            return
        }

        await waitUntil {
            contactInfoStore.hasLoadedDraft
        }
        @Bindable var editableContactInfoStore = contactInfoStore
        await editableContactInfoStore.send(.addReportingLinkButtonTapped)?.value
        await editableContactInfoStore.send(.addReportingLinkButtonTapped)?.value
        $editableContactInfoStore.reportingLinks[0].name.wrappedValue = "Report an Incident"
        $editableContactInfoStore.reportingLinks[0].urlString.wrappedValue = "https://example.org/report"
        $editableContactInfoStore.reportingLinks[0].description.wrappedValue = "Event support form."
        $editableContactInfoStore.reportingLinks[1].name.wrappedValue = "Accessibility Help"
        $editableContactInfoStore.reportingLinks[1].urlString.wrappedValue = "https://example.org/accessibility"

        await editableContactInfoStore.send(.saveButtonTapped)?.value

        let expectedReportingLinks = [
            OMERecord.Event.ReportingLink(
                name: "Report an Incident",
                url: try #require(URL(string: "https://example.org/report")),
                description: "Event support form."
            ),
            OMERecord.Event.ReportingLink(
                name: "Accessibility Help",
                url: try #require(URL(string: "https://example.org/accessibility")),
                description: nil
            ),
        ]
        let savedReportingLinks = try await database.read { db in
            try #require(
                try OMERecord.Event
                    .where { $0.id.eq(eventID) }
                    .fetchOne(db)?
                    .reportingLinks
            )
        }

        expectNoDifference(savedReportingLinks, expectedReportingLinks)
    }

    @Test
    func eventViewerEditContributorEventSpawnsEditorAndLoadsDraft() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("artist-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertContributor(db, eventID: eventID, contributorID: "artist-1", name: "Artist One")
        }

        try await withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            @Bindable var store = Store(initialState: OpenMusicEventAppRoot.State()) {
                OpenMusicEventAppRoot()
            }
            await store.send(.handleNavigationRequest(.event(eventID, nil)))?.value
            let eventAuthoringStore = try #require(
                $store.scope(\.destination, action: \.destination).eventViewer.wrappedValue
            )
            let authoringStore = eventAuthoringStore.scope(
                \.content,
                action: \.content
            )
            @Bindable var eventViewerStore = authoringStore.scope(
                \.content,
                action: \.content
            )
            @Bindable var contributorsStore = try #require(
                eventViewerStore.spawn(\.contributorsViewer)
            )
            await contributorsStore.send(.contributorButtonTapped(contributorID))?.value
            let detailStore = try #require(
                $contributorsStore
                    .scope(\.destination, action: \.destination)
                    .contributorDetail
                    .wrappedValue
            )

            await detailStore.send(.editButtonTapped)?.value
            await waitUntil {
                eventViewerStore.destination?.contributorForm?.hasLoadedDraft == true
            }

            let editContributor = try #require(
                $eventViewerStore
                    .scope(\.destination, action: \.destination)
                    .contributorForm
                    .wrappedValue
            )

            #expect(editContributor.hasLoadedDraft)
            #expect(editContributor.form.value.name == "Artist One")
            #expect(editContributor.mode.contributorID == contributorID)
        }
    }

    @Test
    func eventViewerStageEditDestinationSpawnsEditorAndLoadsDraft() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let stageID = stageLocalID("meadow")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(
                db,
                eventID: eventID,
                stageID: "meadow",
                name: "Meadow",
                category: "main",
                sortIndex: 2
            )
        }

        try await withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            @Bindable var store = Store(initialState: OpenMusicEventAppRoot.State()) {
                OpenMusicEventAppRoot()
            }
            await store.send(.handleNavigationRequest(.event(eventID, nil)))?.value
            let eventAuthoringStore = try #require(
                $store.scope(\.destination, action: \.destination).eventViewer.wrappedValue
            )
            let authoringStore = eventAuthoringStore.scope(
                \.content,
                action: \.content
            )
            @Bindable var eventViewerStore = authoringStore.scope(
                \.content,
                action: \.content
            )
            @Bindable var stagesStore = try #require(eventViewerStore.spawn(\.stagesViewer))
            await stagesStore.send(.stageButtonTapped(stageID))?.value
            let detailStore = try #require(
                $stagesStore
                    .scope(\.destination, action: \.destination)
                    .stageDetail
                    .wrappedValue
            )

            await detailStore.send(.editButtonTapped)?.value
            await waitUntil {
                eventViewerStore.destination?.stageForm?.hasLoadedDraft == true
            }

            let editStage = try #require(
                $eventViewerStore
                    .scope(\.destination, action: \.destination)
                    .stageForm
                    .wrappedValue
            )

            #expect(editStage.hasLoadedDraft)
            #expect(editStage.form.value.name == "Meadow")
            #expect(editStage.form.value.category == "main")
            #expect(editStage.form.value.sortIndex == "2")
            #expect(editStage.mode.stageID == stageID)
        }
    }

    @Test
    func contributorDetailObservesSavedContributorChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("artist-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertContributor(db, eventID: eventID, contributorID: "artist-1", name: "Old Name")
        }

        @Bindable var detailStore = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: ContributorDetail.State(contributorID: contributorID, eventID: eventID)) {
                ContributorDetail()
            }
        }

        @Bindable var editStore = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EditContributor.State(contributorID: contributorID, eventID: eventID)) {
                EditContributor()
            }
        }

        #expect(editStore.hasLoadedDraft)
        #expect(editStore.form.value.name == "Old Name")
        $editStore.form.value.name.wrappedValue = "New Name"
        await editStore.send(.saveButtonTapped)?.value

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
        #expect(detailStore.contributor?.name == "New Name")
    }

    @Test
    func spawnedContributorDetailObservesSavedChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("artist-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertContributor(db, eventID: eventID, contributorID: "artist-1", name: "Old Name")
        }

        @Bindable var contributorsStore = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            Store(initialState: ContributorsViewer.State(eventID: eventID)) {
                ContributorsViewer()
            }
        }

        contributorsStore.send(.contributorButtonTapped(contributorID))
        @Bindable var detailStore = try #require(
            $contributorsStore
                .scope(\.destination, action: \.destination)
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

        @Bindable var editStore = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EditContributor.State(contributorID: contributorID, eventID: eventID)) {
                EditContributor()
            }
        }
        $editStore.form.value.name.wrappedValue = "New Name"
        await editStore.send(.saveButtonTapped)?.value
        for _ in 0..<100 {
            if await viewObservationRecorder.values == ["invalidated"] {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(await viewObservationRecorder.values == ["invalidated"])
        #expect(detailStore.contributor?.name == "New Name")
    }

    @Test
    func contributorDetailDerivesActorFromMatchingPerformanceContributors() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let actor = try #require(OMERecord.Contributor.Actor("alice.bsky.social"))
        let contributorID = contributorLocalID("speaker-1")
        let date = try #require(LocalDate("2026-08-07"))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "day-1", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: eventID,
                contributorID: "speaker-1",
                name: "Alice"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "day-1",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                contributorID: "speaker-1",
                contributorActor: actor
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: ContributorDetail.State(contributorID: contributorID, eventID: eventID)) {
                ContributorDetail()
            }
        }

        #expect(store.contributorActor == actor)
        #expect(store.actorProfileLoadRequest?.actor == actor)
        #expect(!store.usesActorProfileAsPrimary)
    }

    @Test
    func editContributorDoesNotUsePerformanceContributorActorFallback() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let actor = try #require(OMERecord.Contributor.Actor("alice.bsky.social"))
        let contributorID = contributorLocalID("speaker-1")
        let date = try #require(LocalDate("2026-08-07"))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "day-1", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: eventID,
                contributorID: "speaker-1",
                name: "Alice"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "day-1",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                contributorID: "speaker-1",
                contributorActor: actor
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EditContributor.State(contributorID: contributorID, eventID: eventID)) {
                EditContributor()
            }
        }

        #expect(store.hasLoadedDraft)
        #expect(store.contributorDID == nil)
        #expect(store.contributorActor == nil)
    }

    @Test
    func contributorProfilePrefersContributorDIDOverPerformanceContributorActor() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorDID = try #require(DID("did:plc:alice123"))
        let contributorActor = try #require(OMERecord.Contributor.Actor(contributorDID.description))
        let stalePerformanceActor = try #require(OMERecord.Contributor.Actor("bob.bsky.social"))
        let contributorID = contributorLocalID("speaker-1")
        let date = try #require(LocalDate("2026-08-07"))
        let contributorProfile = BlueskyActorProfile(
            did: contributorDID.description,
            handle: "alice.bsky.social",
            displayName: "Alice Profile",
            description: "Alice profile bio"
        )
        let staleProfile = BlueskyActorProfile(
            did: "did:plc:bob456",
            handle: "bob.bsky.social",
            displayName: "Bob Profile",
            description: "Bob profile bio"
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "day-1", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: eventID,
                contributorID: "speaker-1",
                name: "Local Alice",
                did: contributorDID
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "day-1",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                contributorID: "speaker-1",
                contributorActor: stalePerformanceActor
            )
            try BlueskyActorProfile.insert { contributorProfile }
                .execute(db)
            try BlueskyActorProfile.insert { staleProfile }
                .execute(db)
            try BlueskyActorProfileCacheEntry.insert {
                BlueskyActorProfileCacheEntry(
                    actor: contributorActor.description,
                    did: contributorProfile.did,
                    lastFetchedAt: Date(timeIntervalSince1970: 1_000),
                    lastFetchAttemptAt: Date(timeIntervalSince1970: 1_000)
                )
            }
            .execute(db)
            try BlueskyActorProfileCacheEntry.insert {
                BlueskyActorProfileCacheEntry(
                    actor: stalePerformanceActor.description,
                    did: staleProfile.did,
                    lastFetchedAt: Date(timeIntervalSince1970: 1_000),
                    lastFetchAttemptAt: Date(timeIntervalSince1970: 1_000)
                )
            }
            .execute(db)
        }

        let profile = try await database.read { db in
            try #require(
                try ContributorProfile
                    .one(
                        contributorID: contributorID,
                        eventID: eventID,
                        hydration: .bskyActorProfile
                    )
                    .fetchOne(db)
            )
        }

        #expect(profile.contributorActor == contributorActor)
        #expect(profile.handle == "alice.bsky.social")
        #expect(profile.name == "Local Alice")
        #expect(profile.bio == nil)
        #expect(profile.actorProfileLoadRequest?.actor == contributorActor)
    }

    @Test
    func editContributorInlineProfileSearchUsesTypeaheadUntilSubmitted() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("speaker-1")
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

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertContributor(
                db,
                eventID: eventID,
                contributorID: "speaker-1",
                name: "Alice"
            )
        }

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
    func editContributorActorPickerSavesSelectedDidToContributor() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let contributorID = contributorLocalID("speaker-1")
        let previousActor = try #require(OMERecord.Contributor.Actor("alice.bsky.social"))
        let selectedIdentity = ActorIdentity(
            did: try #require(DID("did:plc:alice123")),
            handle: Atmosphere.Account.Handle(rawValue: "alice.bsky.social"),
            displayName: "Alice",
            source: .canonicalResolution
        )
        let selectedActor = try #require(OMERecord.Contributor.Actor(selectedIdentity.did.description))
        let date = try #require(LocalDate("2026-08-07"))
        let requestRecorder = BlueskyProfileRequestRecorder()

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "day-1", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: eventID,
                contributorID: "speaker-1",
                name: "Alice"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "day-1",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk One"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "talk-2",
                stageID: "meadow",
                scheduleID: "day-1",
                startTime: Date(timeIntervalSince1970: 7_200),
                endTime: Date(timeIntervalSince1970: 10_800),
                title: "Talk Two"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                contributorID: "speaker-1",
                contributorActor: previousActor
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "talk-2",
                contributorID: "speaker-1",
                contributorActor: previousActor
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.blueskyActorProfileCache = BlueskyActorProfileCacheClient(
                cachedProfile: { _ in nil },
                refreshProfile: { requestedActor in
                    await requestRecorder.record(requestedActor)
                    return BlueskyActorProfile(
                        did: selectedActor.description,
                        handle: "alice.bsky.social"
                    )
                },
                refreshProfileIfNeeded: { requestedActor, _, _ in
                    await requestRecorder.record(requestedActor)
                    return BlueskyActorProfile(
                        did: selectedActor.description,
                        handle: "alice.bsky.social"
                    )
                }
            )
        } operation: {
            var state = EditContributor.State(contributorID: contributorID, eventID: eventID)
            state.hasLoadedDraft = true
            state.form.value.name = "Alice"
            return Store(initialState: state) {
                EditContributor()
            }
        }

        await store.send(.actorIdentityTapped(selectedIdentity))?.value
        await store.send(.saveButtonTapped)?.value

        let contributor = try await database.read { db in
            try #require(
                try ContributorDetail.contributorQuery(
                    contributorID: contributorID,
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }
        let actors = try await database.read { db in
            try OMERecord.Performance.Contributors.fetchAll(db)
                .compactMap(\.contributorActor?.description)
        }

        #expect(contributor.did == selectedIdentity.did)
        expectNoDifference(actors, [])

        #expect(await requestRecorder.actors == [selectedActor.description])
        #expect(store.contributorActor == selectedActor)
        #expect(store.actorSearchQuery == "")
        #expect(store.actorSearchSections.isEmpty)
        #expect(store.isSavingActor == false)
        #expect(store.actorSearchErrorMessage == nil)
    }

    @Test
    func createContributorActorPickerPrefillsBlankFieldsAndSavesDID() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
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
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
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
            Store(initialState: EditContributor.State(eventID: eventID)) {
                EditContributor()
            }
        }

        await store.send(.actorIdentityTapped(selectedIdentity))?.value

        #expect(store.contributorDID == selectedIdentity.did)
        #expect(store.form.value.name == "Alice Typeahead")
        #expect(store.form.value.bio == "ATProto builder")
        #expect(store.imageURL == "https://example.com/alice-avatar.jpg")

        await store.send(.saveButtonTapped)?.value

        let contributor = try await database.read { db in
            try #require(
                try ContributorDetail.contributorQuery(
                    contributorID: contributorLocalID("alice-typeahead"),
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }

        #expect(contributor.did == selectedIdentity.did)
        #expect(contributor.name == "Alice Typeahead")
        #expect(contributor.bio == "ATProto builder")
        #expect(contributor.images?.first?.url?.absoluteString == "https://example.com/alice-avatar.jpg")
    }

    @Test
    func createContributorActorPickerDoesNotOverwriteEnteredFields() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
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
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
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

    @Test(arguments: ["alice.bsky.social", "did:plc:alice123"])
    func generatedActorContributorDisplayUsesBlueskyProfileData(actorString: String) async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let actor = try #require(OMERecord.Contributor.Actor(actorString))
        let contributorID = contributorLocalID("schedule-actor-alice.bsky.social")
        let date = try #require(LocalDate("2026-08-07"))
        let profile = BlueskyActorProfile(
            did: "did:plc:alice123",
            handle: "alice.bsky.social",
            displayName: "Alice Example",
            description: "ATProto builder",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg"),
            banner: URL(string: "https://cdn.example/alice-banner.jpg")
        )
        let requestRecorder = BlueskyProfileRequestRecorder()
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "day-1", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: eventID,
                contributorID: "schedule-actor-alice.bsky.social",
                name: "alice.bsky.social"
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "day-1",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                contributorID: "schedule-actor-alice.bsky.social",
                contributorActor: actor
            )
        }

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
            Store(initialState: ContributorDetail.State(contributorID: contributorID, eventID: eventID)) {
                ContributorDetail()
            }
        }

        try await waitForBlueskyProfile(in: store)

        #expect(await requestRecorder.actors == [actor.description])
        #expect(store.contributorActor == actor)
        #expect(store.usesActorProfileAsPrimary)
        let contributorProfile = try #require(store.profile)
        #expect(contributorProfile.name == "Alice Example")
        #expect(contributorProfile.bio == "ATProto builder")
        #expect(contributorProfile.handle == "alice.bsky.social")
        #expect(contributorProfile.artworkAsset?.url?.absoluteString == "https://cdn.example/alice-avatar.jpg")
        #expect(contributorProfile.artworkCacheContext == nil)
    }

    @Test
    func explicitContributorDisplayDoesNotGetOverwrittenByBlueskyProfileData() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let actor = try #require(OMERecord.Contributor.Actor("alice.bsky.social"))
        let contributorID = contributorLocalID("speaker-1")
        let date = try #require(LocalDate("2026-08-07"))
        let explicitImageURL = try #require(URL(string: "https://example.com/explicit.jpg"))
        let profile = BlueskyActorProfile(
            did: "did:plc:alice123",
            handle: "alice.bsky.social",
            displayName: "Alice Example",
            description: "Bluesky bio",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg"),
            banner: URL(string: "https://cdn.example/alice-banner.jpg")
        )
        let requestRecorder = BlueskyProfileRequestRecorder()
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertSchedule(db, eventID: eventID, scheduleID: "day-1", date: date)
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
            try Self.insertContributor(
                db,
                eventID: eventID,
                contributorID: "speaker-1",
                name: "Explicit Alice",
                bio: "OME bio",
                imageURL: explicitImageURL
            )
            try Self.insertPerformance(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                stageID: "meadow",
                scheduleID: "day-1",
                startTime: Date(timeIntervalSince1970: 0),
                endTime: Date(timeIntervalSince1970: 3_600),
                title: "Talk"
            )
            try Self.insertPerformanceContributor(
                db,
                eventID: eventID,
                performanceID: "talk-1",
                contributorID: "speaker-1",
                contributorActor: actor
            )
        }

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
            Store(initialState: ContributorDetail.State(contributorID: contributorID, eventID: eventID)) {
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
        #expect(contributorProfile.artworkCacheContext == LocalImageCacheContext(contributorID: contributorProfile.contributor.id))
    }

    @Test
    func createContributorSavesNewContributor() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
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

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let contributorID = contributorLocalID("new-contributor")
        let contributor = try await database.read { db in
            try #require(
                try ContributorDetail.contributorQuery(
                    contributorID: contributorID,
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }

        #expect(contributor.name == "New Contributor")
        #expect(contributor.bio == "Bio")
    }

    @Test
    func createContributorRequiresValidComposableForm() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EditContributor.State(eventID: eventID)) {
                EditContributor()
            }
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented)
        #expect(
            store.state.form.validation[AnyHashable(\EditContributor.FormValue.name)]?.errors.map(\.message)
                == ["Enter a name."]
        )

        let contributors = try await database.read { db in
            try OMERecord.Contributor.fetchAll(db)
        }
        #expect(contributors.isEmpty)
    }

    @Test
    func stageDetailEditButtonEmitsEventStageEditorRequest() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let stageID = stageLocalID("meadow")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: StageDetail.State(stageID: stageID, eventID: eventID)) {
                StageDetail()
            }
        }

        let editTask = store.send(.editButtonTapped)
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(.editStage(eventID: eventID, stageID: stageID)),
            timeout: .seconds(1)
        )
        await editTask?.value
    }

    @Test
    func editStageSavesEventSnapshotChanges() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let stageID = stageLocalID("meadow")
        let lineupID = contributorLocalID("artist-1")
        let posterURL = try #require(URL(string: "https://example.com/poster.png"))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(
                db,
                eventID: eventID,
                stageID: "meadow",
                name: "Old Meadow",
                posterImageURL: posterURL,
                lineup: [lineupID]
            )
        }
        let existingStage = try await database.read { db in
            try #require(
                try StageDetail.stageQuery(
                    stageID: stageID,
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            var state = EditStage.State(stageID: stageID, eventID: eventID)
            state.hasLoadedDraft = true
            state.draft = OMERecord.Stage.Draft(
                id: existingStage.id,
                name: " New Meadow ",
                color: existingStage.color,
                category: existingStage.category,
                sortIndex: existingStage.sortIndex,
                images: existingStage.images,
                systemIconName: existingStage.systemIconName,
                iconShortCode: existingStage.iconShortCode,
                lineup: existingStage.lineup
            )
            state.category = " workshop "
            state.sortIndex = " 7 "
            state.colorHex = " #AABBCC "
            state.systemIconName = "sparkles"
            state.iconShortCode = " MD "
            state.logoURL = "https://example.com/logo.png"
            state.heroImageURL = "https://example.com/hero.png"

            return TestStore(initialState: state) {
                EditStage()
            }
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let stage = try await database.read { db in
            try #require(
                try StageDetail.stageQuery(
                    stageID: stageID,
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }

        #expect(stage.name == "New Meadow")
        #expect(stage.category == OMERecord.Stage.Category("workshop"))
        #expect(stage.sortIndex == 7)
        #expect(stage.color.rawValue == 0xAABBCC)
        #expect(stage.systemIconName == "sparkles")
        #expect(stage.iconShortCode == "MD")
        #expect(stage.iconImageURL?.absoluteString == "https://example.com/logo.png")
        #expect(stage.imageURL?.absoluteString == "https://example.com/hero.png")
        #expect(stage.posterImageURL?.absoluteString == "https://example.com/poster.png")
        #expect(stage.lineup == [lineupID])
    }

    @Test
    func stagesViewerAddButtonEmitsCreateStageEditorRequest() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: StagesViewer.State(eventID: eventID)) {
                StagesViewer()
            }
        }

        let addTask = store.send(.addButtonTapped)
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(.createStage(eventID)),
            timeout: .seconds(1)
        )
        await addTask?.value
    }

    @Test
    func communicationsViewerChannelQueryFiltersAndSortsEventChannels() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = eventID("event-1")
        let otherEventID = eventID("event-2")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertEvent(db, id: otherEventID, name: "Event Two")
            try Self.insertChannel(
                db,
                eventID: selectedEventID,
                channelID: "announcements",
                name: "Announcements",
                sortIndex: 2
            )
            try Self.insertChannel(
                db,
                eventID: selectedEventID,
                channelID: "general",
                name: "General",
                sortIndex: 1
            )
            try Self.insertChannel(
                db,
                eventID: selectedEventID,
                channelID: "late-news",
                name: "Late News"
            )
            try Self.insertChannel(
                db,
                eventID: otherEventID,
                channelID: "other",
                name: "Other",
                sortIndex: 0
            )
        }

        let channels = try await database.read { db in
            try CommunicationsViewer.channelsQuery(eventID: selectedEventID).fetchAll(db)
        }

        expectNoDifference(
            channels.map(\.id.channelID),
            [
                channelLocalID("general"),
                channelLocalID("announcements"),
                channelLocalID("late-news"),
            ]
        )
    }

    @Test
    func communicationsViewerRowsPreferStoredPreferenceBeforeChannelDefault() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertChannel(
                db,
                eventID: eventID,
                channelID: "general",
                name: "General",
                defaultNotificationState: .unsubscribed
            )
            try ChannelPreferences.insert {
                ChannelPreferences(
                    id: channelRecordID("general", eventID: eventID),
                    notificationState: .subscribed
                )
            }
            .execute(db)
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: CommunicationsViewer.State(eventID: eventID)) {
                CommunicationsViewer()
            }
        }

        expectNoDifference(
            store.state.channelRows.map(\.effectiveNotificationState),
            [.subscribed]
        )
    }

    @Test
    func communicationsViewerChannelTapPresentsChannelDetail() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let channelID = channelLocalID("general")
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: CommunicationsViewer.State(eventID: eventID)) {
                CommunicationsViewer()
            }
        }

        store.send(.channelButtonTapped(channelID))

        #expect(store.state.destination?.channelDetail?.state.channelID == channelID)
        #expect(store.state.destination?.channelDetail?.state.eventID == eventID)
    }

    @Test
    func communicationsChannelDetailNotifyMeWritesPreference() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let channelID = channelLocalID("general")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertChannel(
                db,
                eventID: eventID,
                channelID: "general",
                name: "General",
                defaultNotificationState: .unsubscribed
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: CommunicationChannelDetail.State(
                    channelID: channelID,
                    eventID: eventID
                )
            ) {
                CommunicationChannelDetail()
            }
        }

        let notifyTask = store.send(.notifyMeButtonTapped)
        await notifyTask?.value

        let preference = try await database.read { db in
            try ChannelPreferences
                .where { $0.id.eq(channelRecordID("general", eventID: eventID)) }
                .fetchOne(db)
        }

        #expect(preference?.notificationState == .subscribed)
    }

    @Test
    func communicationsChannelDetailStopNotifyingMeWritesPreference() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let channelID = channelLocalID("general")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertChannel(
                db,
                eventID: eventID,
                channelID: "general",
                name: "General",
                defaultNotificationState: .subscribed
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: CommunicationChannelDetail.State(
                    channelID: channelID,
                    eventID: eventID
                )
            ) {
                CommunicationChannelDetail()
            }
        }

        let notifyTask = store.send(.stopNotifyingMeButtonTapped)
        await notifyTask?.value

        let preference = try await database.read { db in
            try ChannelPreferences
                .where { $0.id.eq(channelRecordID("general", eventID: eventID)) }
                .fetchOne(db)
        }

        #expect(preference?.notificationState == .unsubscribed)
    }

    @Test
    func communicationsChannelDetailRequiredChannelDoesNotWriteUnsubscribePreference() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let channelID = channelLocalID("general")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertChannel(
                db,
                eventID: eventID,
                channelID: "general",
                name: "General",
                defaultNotificationState: .subscribed,
                notificationsRequired: true
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: CommunicationChannelDetail.State(
                    channelID: channelID,
                    eventID: eventID
                )
            ) {
                CommunicationChannelDetail()
            }
        }

        store.send(.stopNotifyingMeButtonTapped)

        let preference = try await database.read { db in
            try ChannelPreferences
                .where { $0.id.eq(channelRecordID("general", eventID: eventID)) }
                .fetchOne(db)
        }

        #expect(preference == nil)
    }

    @Test
    func communicationsChannelDetailFetchesSelectedChannelPosts() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let channelID = channelLocalID("general")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertChannel(db, eventID: eventID, channelID: "general", name: "General")
            try Self.insertChannel(db, eventID: eventID, channelID: "safety", name: "Safety")
            try Self.insertCommsPost(
                db,
                eventID: eventID,
                channelID: "general",
                postID: "arrival",
                title: "Arrival Info",
                contents: "Use the north gate.",
                sortIndex: 0
            )
            try Self.insertCommsPost(
                db,
                eventID: eventID,
                channelID: "general",
                postID: "welcome",
                title: "Welcome",
                contents: "Welcome to the event.",
                isPinned: true,
                sortIndex: 1
            )
            try Self.insertCommsPost(
                db,
                eventID: eventID,
                channelID: "safety",
                postID: "weather",
                title: "Weather",
                contents: "Bring layers.",
                sortIndex: 0
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(
                initialState: CommunicationChannelDetail.State(
                    channelID: channelID,
                    eventID: eventID
                )
            ) {
                CommunicationChannelDetail()
            }
        }

        expectNoDifference(store.state.pinnedPosts.map(\.title), ["Welcome"])
        expectNoDifference(store.state.recentPosts.map(\.title), ["Arrival Info"])
        #expect(store.state.shouldShowEmptyPostsFooter == false)
    }

    @Test
    func communicationsChannelDetailShowsEmptyPostsFooterWhenNoPosts() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let channelID = channelLocalID("general")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertChannel(db, eventID: eventID, channelID: "general", name: "General")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(
                initialState: CommunicationChannelDetail.State(
                    channelID: channelID,
                    eventID: eventID
                )
            ) {
                CommunicationChannelDetail()
            }
        }

        #expect(store.state.shouldShowEmptyPostsFooter == true)
        expectNoDifference(store.state.pinnedPosts, [])
        expectNoDifference(store.state.recentPosts, [])
    }

    @Test
    func communicationsChannelDetailPostTapPresentsPostDetail() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let channelID = channelLocalID("general")
        let postID = commsPostID("welcome", channelID: "general", eventID: eventID)
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertChannel(db, eventID: eventID, channelID: "general", name: "General")
            try Self.insertCommsPost(
                db,
                eventID: eventID,
                channelID: "general",
                postID: "welcome",
                title: "Welcome",
                contents: "Welcome to the event.",
                isPinned: true,
                sortIndex: 0
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: CommunicationChannelDetail.State(
                    channelID: channelID,
                    eventID: eventID
                )
            ) {
                CommunicationChannelDetail()
            }
        }

        store.send(.postButtonTapped(postID))

        #expect(store.state.destination?.postDetail?.state.post.id == postID)
        #expect(store.state.destination?.postDetail?.state.post.title == "Welcome")
    }

    @Test
    func createStageSavesNewEventStage() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(db, eventID: eventID, stageID: "new-meadow", name: "Old Meadow")
        }

        let store = withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            var state = EditStage.State(eventID: eventID)
            state.draft.name = " New Meadow "
            state.category = " workshop "
            state.sortIndex = " 4 "
            state.colorHex = "#123456"
            state.systemIconName = "music.mic"
            state.iconShortCode = "NM"
            state.logoURL = "https://example.com/new-logo.png"
            state.heroImageURL = "https://example.com/new-hero.png"

            return TestStore(initialState: state) {
                EditStage()
            }
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let stageID = stageLocalID("new-meadow-2")
        let stage = try await database.read { db in
            try #require(
                try StageDetail.stageQuery(
                    stageID: stageID,
                    eventID: eventID
                )
                .fetchOne(db)
            )
        }

        #expect(stage.name == "New Meadow")
        #expect(stage.category == OMERecord.Stage.Category("workshop"))
        #expect(stage.sortIndex == 4)
        #expect(stage.color.rawValue == 0x123456)
        #expect(stage.systemIconName == "music.mic")
        #expect(stage.iconShortCode == "NM")
        #expect(stage.iconImageURL?.absoluteString == "https://example.com/new-logo.png")
        #expect(stage.imageURL?.absoluteString == "https://example.com/new-hero.png")
        #expect(stage.posterImageURL == nil)
    }

    @Test
    func editStageImagePickerImportAddsImageThroughParentDestination() async throws {
        let eventID = eventID("event-1")
        let image = ImportImages.Configuration.stagePoster.importedImage(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000057a6")!,
            title: "Stage Poster",
            sourceName: "stage-poster.png",
            sourceURL: URL(fileURLWithPath: "/tmp/stage-poster.png"),
            mimeType: "image/png",
            data: Data("stage-poster".utf8)
        )

        @Bindable var store = Store(initialState: EditStage.State(eventID: eventID)) {
            EditStage()
        }

        store.send(.posterImagePicker(.addButtonTapped))
        let importStore = try #require(
            $store.scope(\.destination, action: \.destination).posterImportImages.wrappedValue
        )
        importStore.send(.imagesImported([image]))
        await importStore.send(.saveButtonTapped)?.value

        await waitUntil { store.destination == nil }
        expectNoDifference(store.posterImagePicker.images.map(\.importedImage), [image])
        #expect(store.heroImagePicker.images.isEmpty)
        #expect(store.logoImagePicker.images.isEmpty)
    }

    @Test
    func stagesViewerDeleteRemovesEventStage() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("event-1")
        let stageID = stageLocalID("meadow")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
            try Self.insertStage(db, eventID: eventID, stageID: "meadow", name: "Meadow")
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: StagesViewer.State(eventID: eventID)) {
                StagesViewer()
            }
        }

        await store.send(.deleteStages([stageID]))?.value

        #expect(store.state.errorMessage == nil)

        let stage = try await database.read { db in
            try StageDetail.stageQuery(
                stageID: stageID,
                eventID: eventID
            )
            .fetchOne(db)
        }
        #expect(stage == nil)
    }

    @Test
    func launchRestoreMountsEventViewer() async throws {
        let eventID = eventID("event-1")
        let database = try makePreparedDatabase()
        try await database.write { db in
            try AppState.update {
                $0.organizerID = #bind(eventID.organizerID)
                $0.eventID = #bind(eventID.eventID)
            }
            .execute(db)
        }

        let store = makeRootHarnessStore(
            database: database,
            eventID: eventID,
            selectedEventIDAtLaunch: eventID
        )
        #expect(store.state.root.eventViewer?.id == eventID)
        expectNoDifference(
            store.state.root.eventViewer?.content.content.pendingScheduleLaunchAction,
            .jumpToCurrentTime
        )
    }

    @Test
    func eventViewerDestinationBindingPresentsAndDismissesStore() throws {
        let eventID = eventID("event-1")
        let database = try makePreparedDatabase()
        @Bindable var store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            Store(initialState: OpenMusicEventAppRoot.State()) {
                OpenMusicEventAppRoot()
            }
        }

        store.send(.handleNavigationRequest(.event(eventID, nil)))

        let presentation = $store
            .scope(\.destination, action: \.destination)
            .eventViewer
        let eventViewerStore = try #require(presentation.wrappedValue)
        #expect(eventViewerStore.state.id == eventID)

        presentation.wrappedValue = nil

        #expect(store.eventViewer == nil)
    }

    @Test
    func sourceWorkspaceLaunchRestoreRemainsAttendeeWithoutExplicitEntry() async throws {
         let eventID = eventID("source-calendar-event")
         let database = try makePreparedDatabase()
         try await database.write { db in
             try Self.insertOrganizer(db, id: testOrganizerID)
             try Self.insertEvent(db, id: eventID, name: "Source Calendar Event")
             try AppState.update {
                 $0.organizerID = #bind(eventID.organizerID)
                 $0.eventID = #bind(eventID.eventID)
             }
             .execute(db)
         }
 
         let state = withDependencies {
             $0.context = .test
             $0.defaultDatabase = database
             $0.defaultEventID = eventID
         } operation: {
             OpenMusicEventAppRoot.State(selectedEventIDAtLaunch: eventID)
        }

        #expect(state.eventViewer?.content.content.eventID == eventID)
        #expect(state.eventViewer?.content.access == .attendee)
        #expect(
            state.eventViewer?.content.content.installedFeatures
                .contains(.workspace) == false
        )
    }

    @Test
    func launchRestoreMountsPersistedWorkspaceAuthoringSynchronously() async throws {
        let eventID = eventID("persisted-authoring-event")
        let database = try makePreparedDatabase()
        let workspace = EditingWorkspaceRecord(
            localEventID: eventID,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let activation = WorkspaceAuthoringActivationRecord(
            id: workspace.id,
            principal: .local,
            role: .owner,
            activatedAt: Date(timeIntervalSince1970: 2)
        )
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Persisted Authoring Event")
            try EditingWorkspaceRecord.insert { workspace }.execute(db)
            try EventEditingWorkspaceRecord.insert {
                EventEditingWorkspaceRecord(
                    id: eventID,
                    workspaceID: workspace.id
                )
            }
            .execute(db)
            try WorkspaceAuthoringActivationRecord.insert {
                activation
            }
            .execute(db)
        }

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0[WorkspaceAuthoringActivationClient.self] = .live
        } operation: {
            OpenMusicEventAppRoot.State(selectedEventIDAtLaunch: eventID)
        }

        expectNoDifference(
            state.eventViewer?.content.access,
            .authoring(.owner)
        )
        expectNoDifference(
            state.eventViewer?.content.grant?.principal,
            .local
        )
        expectNoDifference(
            state.eventViewer?.content.workspaceID,
            workspace.id
        )
    }

    @Test
    func launchRestoreRecoversPersistedWorkspaceFromSourceProvenance() async throws {
        let eventID = eventID("source-provenance-authoring-event")
        let database = try makePreparedDatabase()
        let source = sourceProvenance("source-provenance-authoring")
        let sourceBaselineID = SourceBaselineRecord.ID(source: source)
        let workspaceID = EditingWorkspaceRecord.ID(
            sourceBaselineID: sourceBaselineID
        )
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(
                db,
                id: eventID,
                name: "Source Provenance Authoring Event"
            )
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: source,
                importedAt: Date(timeIntervalSince1970: 1)
            )
            try EventSourceProvenanceRecord.insert {
                EventSourceProvenanceRecord(
                    id: eventID,
                    sourceBaselineID: sourceBaselineID,
                    sourceKind: source.kind,
                    sourceReference: source.reference,
                    ref: source.ref,
                    eventIDOrigin: .inferred,
                    sourceEventDirectory: eventID.eventID.rawValue.rawValue
                )
            }
            .execute(db)
            try WorkspaceAuthoringActivationRecord.insert {
                WorkspaceAuthoringActivationRecord(
                    id: workspaceID,
                    principal: .local,
                    role: .owner,
                    activatedAt: Date(timeIntervalSince1970: 2)
                )
            }
            .execute(db)
        }

        // The explicit event-to-workspace link is missing, but the installed source
        // provenance still identifies the workspace the user was authoring.
        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0[WorkspaceAuthoringActivationClient.self] = .live
        } operation: {
            OpenMusicEventAppRoot.State(selectedEventIDAtLaunch: eventID)
        }

        expectNoDifference(
            state.eventViewer?.content.workspaceID,
            workspaceID
        )
        expectNoDifference(
            state.eventViewer?.content.access,
            .authoring(.owner)
        )
    }

    @Test
    func launchRestoreDoesNotInventLocalWorkspaceWhenLookupFails() throws {
        let eventID = eventID("workspace-lookup-failure")
        let database = try makePreparedDatabase()
        try database.close()

        // A database failure is not evidence that this source-backed event is a
        // new local workspace. Keep the event closed and retain the real failure.
        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            OpenMusicEventAppRoot.State(selectedEventIDAtLaunch: eventID)
        }

        #expect(state.eventViewer == nil)
        let error = try #require(state.workspaceRestorationError)
        #expect(String(reflecting: error).contains("closed"))
    }

    @Test
    func appLaunchCarriesSelectedEventLookupFailureIntoRootRestoration() throws {
        let database = try makePreparedDatabase()
        try database.close()

        let restoration = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            OpenMusicEventApplicationRootView.selectedEventRestoration(
                for: .generic
            )
        }

        #expect(restoration.eventID == nil)
        let error = try #require(restoration.error)
        #expect(String(reflecting: error).contains("closed"))

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            OpenMusicEventAppRoot.State(
                workspaceRestorationErrorAtLaunch: error
            )
        }
        #expect(state.eventViewer == nil)
        #expect(state.workspaceRestorationError != nil)
    }

    @Test
    func eventViewerDismissClearsSelectedEvent() async throws {
        let eventID = eventID("event-1")
        let database = try makePreparedDatabase()
        try await database.write { db in
            try AppState.update {
                $0.organizerID = #bind(eventID.organizerID)
                $0.eventID = #bind(eventID.eventID)
            }
            .execute(db)
        }

        let store = makeRootHarnessStore(
            database: database,
            eventID: eventID,
            selectedEventIDAtLaunch: eventID
        )
        #expect(store.state.root.eventViewer?.content.content.eventID == eventID)

        await store.modify {
            $0.root.eventViewer = nil
        }?.value

        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }
        #expect(appState?.selectedEventID == nil)
    }

    @Test
    func launchRestoredEventViewerContributorEditDestinationSpawnsEditorAndLoadsDraft() async throws {
        let database = try makePreparedDatabase()
        let eventID = eventID("wicked-woods-ome-2025")
        let contributorID = contributorLocalID("[IVY]")
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Wicked Woods")
            try Self.insertContributor(db, eventID: eventID, contributorID: "[IVY]", name: "IVY")
            try AppState.update {
                $0.organizerID = #bind(eventID.organizerID)
                $0.eventID = #bind(eventID.eventID)
            }
            .execute(db)
        }

        try await withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            @Bindable var store = Store(
                initialState: OpenMusicEventAppRoot.State(selectedEventIDAtLaunch: eventID)
            ) {
                OpenMusicEventAppRoot()
            }

            let eventAuthoringStore = try #require(
                $store.scope(\.destination, action: \.destination).eventViewer.wrappedValue
            )
            let authoringStore = eventAuthoringStore.scope(
                \.content,
                action: \.content
            )
            @Bindable var eventViewerStore = authoringStore.scope(
                \.content,
                action: \.content
            )
            @Bindable var contributorsStore = try #require(
                eventViewerStore.spawn(\.contributorsViewer)
            )
            await contributorsStore.send(.contributorButtonTapped(contributorID))?.value
            let detailStore = try #require(
                $contributorsStore
                    .scope(\.destination, action: \.destination)
                    .contributorDetail
                    .wrappedValue
            )

            await detailStore.send(.editButtonTapped)?.value
            await waitUntil {
                eventViewerStore.destination?.contributorForm?.hasLoadedDraft == true
            }

            let editContributor = try #require(
                $eventViewerStore
                    .scope(\.destination, action: \.destination)
                    .contributorForm
                    .wrappedValue
            )

            #expect(editContributor.isPresented)
            #expect(editContributor.form.value.links.isEmpty)
            let addLinkTask = editContributor.send(.addLinkButtonTapped)
            #expect(addLinkTask != nil)
            await addLinkTask?.value
            #expect(editContributor.form.value.links.count == 1)
            #expect(eventViewerStore.destination?.contributorForm?.form.value.links.count == 1)

            await editContributor.send(.onAppear)?.value

            #expect(editContributor.hasLoadedDraft)
            #expect(editContributor.form.value.name == "IVY")
            #expect(editContributor.mode.contributorID == contributorID)
        }
    }

    @Test
    func normalEventViewerNavigationPersistsSelectedEvent() async throws {
        let eventID = eventID("event-1")
        let database = try makePreparedDatabase()
        let store = makeRootHarnessStore(database: database, eventID: eventID)

        store.send(.root(.handleNavigationRequest(.event(eventID, nil))))
        #expect(store.state.root.eventViewer?.id == eventID)

        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }
        #expect(appState?.selectedEventID == eventID)
    }

    @Test
    func whiteLabelWorkspaceContextCarriesIntoEventViewerNavigation() async throws {
        let eventID = eventID("event-1")
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("white-label-shared-context")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let workspaceID = EditingWorkspaceRecord.ID(sourceBaselineID: sourceBaselineID)
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Shared Context")
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 2_000)
            )
            try Self.insertEventSourceProvenance(
                db,
                eventID: eventID,
                sourceProvenance: sourceProvenance
            )
        }
        let grant = Shared<AuthoringGrant?>(
            value: AuthoringGrant(
                principal: .local,
                role: .owner,
                workspace: WorkspaceContext(
                    id: workspaceID,
                    sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: database)
                )
            )
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            var state = RootHarness.State()
            state.root = OpenMusicEventAppRoot.State(
                variant: .whiteLabel(
                    WhiteLabelAppConfiguration(
                        brand: WhiteLabelBrand(displayName: "Test Festival"),
                        organizerID: testOrganizerID
                    )
                )
            )
            state.root.whiteLabelRoot?.state.teamWorkspaceDetail = Spawn(
                WhiteLabelRoot.TeamWorkspace.State(
                    storage: OpenMusicEventOAuth.storage
                ) {
                    OpenMusicEventSourceEditing.Authoring<TeamWorkspaceDetail>.State(
                        workspaceID: workspaceID,
                        grant: grant
                    ) {
                        TeamWorkspaceDetail.State(sourceBaselineID: sourceBaselineID)
                    }
                }
            )

            return TestStore(initialState: state) {
                RootHarness()
            }
        }

        store.send(.root(.handleNavigationRequest(.event(eventID, nil))))

        #expect(
            store.state.root.eventViewer?.content.access
                == .authoring(.owner)
        )
        #expect(
            store.state.root.eventViewer?.content.content.installedFeatures
                .contains(.workspace) == true
        )

        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }
        #expect(appState?.selectedEventID == eventID)
    }

    @Test
    func whiteLabelEnterAuthoringPreparesSourceRepositoryBeforeShowingAuthoringControls() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("white-label-authoring-source")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let workspaceID = EditingWorkspaceRecord.ID(sourceBaselineID: sourceBaselineID)
        let authorizationRequests = Mutex<[EditingWorkspaceRecord.ID]>([])
        let preparationRequests = Mutex<[EditingWorkspaceRecord.ID]>([])
        try await database.write { db in
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 2_100)
            )
        }
        let configuration = WhiteLabelAppConfiguration(
            brand: WhiteLabelBrand(displayName: "Test Festival"),
            organizerID: testOrganizerID
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0[AuthoringPolicyClient.self] = AuthoringPolicyClient { requestedWorkspaceID in
                authorizationRequests.withLock { $0.append(requestedWorkspaceID) }
                return .granted(principal: .local, role: .owner)
            }
            $0[WorkspacePreparationClient.self] = WorkspacePreparationClient(
                open: { requestedWorkspaceID in
                    WorkspaceContext(
                        id: requestedWorkspaceID,
                        sourceWorkspaceDatabase: SourceWorkspaceDatabase(database: database)
                    )
                },
                prepareSource: { requestedWorkspaceID in
                    preparationRequests.withLock { $0.append(requestedWorkspaceID) }
                }
            )
        } operation: {
            var state = WhiteLabelRoot.State(configuration: configuration)
            state.teamWorkspaceDetail = Spawn(
                WhiteLabelRoot.TeamWorkspace.State(
                    storage: OpenMusicEventOAuth.storage
                ) {
                    OpenMusicEventSourceEditing.Authoring<TeamWorkspaceDetail>.State(
                        workspaceID: workspaceID
                    ) {
                        TeamWorkspaceDetail.State(sourceBaselineID: sourceBaselineID)
                    }
                }
            )
            state.loadingPhase = .preparing
            return TestStore(initialState: state) {
                WhiteLabelRoot()
            }
        }

        let authorizationTask = store.send(
            to: \.teamWorkspaceDetail!,
            .content(.enterButtonTapped)
        )
        await authorizationTask?.value
        #expect(
            store.state.teamWorkspaceDetail?.state.content.access
                == .authoring(.owner)
        )
        expectNoDifference(authorizationRequests.withLock { $0 }, [workspaceID])
        expectNoDifference(preparationRequests.withLock { $0 }, [workspaceID])
    }

    @Test
    func whiteLabelFirstDownloadStaysInAttendeeModeWhenLoggedIn() async throws {
        let database = try makePreparedDatabase()
        let sourceBaselineID = SourceBaselineRecord.ID(
            source: sourceProvenance("white-label-first-download-source")
        )
        let configuration = WhiteLabelAppConfiguration(
            brand: WhiteLabelBrand(displayName: "Test Festival"),
            organizerID: testOrganizerID
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0[AuthoringPolicyClient.self] = .authoring
        } operation: {
            var state = WhiteLabelRoot.State(configuration: configuration)
            state.loadingPhase = .preparing
            return TestStore(initialState: state) {
                WhiteLabelRoot()
            }
        }

        store.send(.loadDataSucceeded(.init(
            organizerID: testOrganizerID,
            sourceBaselineIDs: [sourceBaselineID]
        )))

        #expect(store.state.organizerID == testOrganizerID)
        #expect(store.state.teamWorkspaceDetail?.state.content.access == .attendee)
        #expect(
            store.state.teamWorkspaceDetail?.state.content.content.sourceBaselineID
                == sourceBaselineID
        )
    }

    @Test
    func whiteLabelLaunchRestoreMountsEventViewer() async throws {
        let eventID = eventID("event-1")
        let database = try makePreparedDatabase()

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            OpenMusicEventAppRoot.State(
                variant: .whiteLabel(
                    WhiteLabelAppConfiguration(
                        brand: WhiteLabelBrand(displayName: "Test Festival"),
                        organizerID: testOrganizerID
                    )
                ),
                selectedEventIDAtLaunch: eventID
            )
        }

        #expect(state.eventViewer?.content.content.eventID == eventID)
        expectNoDifference(
            state.eventViewer?.content.content.pendingScheduleLaunchAction,
            .jumpToCurrentTime
        )
    }

    @Test
    func whiteLabelLaunchRestoredEventViewerRemainsAttendeeWithoutExplicitEntry() async throws {
        let eventID = eventID("event-1")
        let database = try makePreparedDatabase()

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.whiteLabelSourceRegistry = WhiteLabelSourceRegistryClient { organizerID in
                #expect(organizerID == testOrganizerID)
                return WhiteLabelSourceDescriptor(
                    reference: .source("tangled.org/woody.fm/test-festival")
                )
            }
        } operation: {
            var state = RootHarness.State()
            state.root = OpenMusicEventAppRoot.State(
                variant: .whiteLabel(
                    WhiteLabelAppConfiguration(
                        brand: WhiteLabelBrand(displayName: "Test Festival"),
                        organizerID: testOrganizerID
                    )
                ),
                selectedEventIDAtLaunch: eventID
            )
            return TestStore(initialState: state) {
                RootHarness()
            }
        }

        #expect(store.state.root.eventViewer?.content.access == .attendee)
        #expect(
            store.state.root.eventViewer?.content.content.installedFeatures
                .contains(.workspace) == false
        )
    }

    @Test
    func whiteLabelLaunchRestoresPersistedWorkspaceAuthoring() async throws {
        let database = try makePreparedDatabase()
        let sourceProvenance = sourceProvenance("white-label-persisted-authoring")
        let sourceBaselineID = SourceBaselineRecord.ID(source: sourceProvenance)
        let workspaceID = EditingWorkspaceRecord.ID(
            sourceBaselineID: sourceBaselineID
        )
        try await database.write { db in
            try Self.insertSourceBaseline(
                db,
                sourceProvenance: sourceProvenance,
                importedAt: Date(timeIntervalSince1970: 1)
            )
            try WorkspaceAuthoringActivationRecord.insert {
                WorkspaceAuthoringActivationRecord(
                    id: workspaceID,
                    principal: .local,
                    role: .owner,
                    activatedAt: Date(timeIntervalSince1970: 2)
                )
            }
            .execute(db)
        }

        let state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0[WorkspaceAuthoringActivationClient.self] = .live
        } operation: {
            WhiteLabelRoot.State(
                configuration: WhiteLabelAppConfiguration(
                    brand: WhiteLabelBrand(displayName: "Test Festival"),
                    organizerID: testOrganizerID
                ),
                loadedRootAtLaunch: WhiteLabelRoot.LoadedRoot(
                    organizerID: testOrganizerID,
                    sourceBaselineIDs: [sourceBaselineID]
                )
            )
        }

        expectNoDifference(
            state.teamWorkspaceDetail?.state.content.access,
            .authoring(.owner)
        )
        #expect(state.showsAuthoringControls)
    }

    @Test
    func whiteLabelRestoredEventViewerAllowsWhiteLabelLoadToComplete() async throws {
        let eventID = eventID("event-1")
        let database = try makePreparedDatabase()
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertEvent(db, id: eventID, name: "Event One")
        }
        let configuration = WhiteLabelAppConfiguration(
            brand: WhiteLabelBrand(displayName: "Test Festival"),
            organizerID: testOrganizerID
        )

        try await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.whiteLabelSourceRegistry = WhiteLabelSourceRegistryClient { organizerID in
                #expect(organizerID == testOrganizerID)
                return WhiteLabelSourceDescriptor(
                    reference: .source("tangled.org/woody.fm/test-festival")
                )
            }
            $0.whiteLabelSourceImport = WhiteLabelSourceImportClient { organizerID, _ in
                #expect(organizerID == testOrganizerID)
                return [eventID]
            }
        } operation: {
            @Bindable var store = Store(
                initialState: OpenMusicEventAppRoot.State(
                    variant: .whiteLabel(configuration),
                    selectedEventIDAtLaunch: eventID
                )
            ) {
                OpenMusicEventAppRoot()
            }

            let eventViewerStore = try #require(
                $store.scope(\.destination, action: \.destination).eventViewer.wrappedValue
            )
            let whiteLabelStore = try #require(store.spawn(\.whiteLabelRoot))

            await whiteLabelStore.send(.task)?.value
            await waitUntil {
                whiteLabelStore.loadingPhase == .idle
                    && whiteLabelStore.organizerID == testOrganizerID
            }

            #expect(eventViewerStore.state.id == eventID)
            #expect(whiteLabelStore.errorMessage == nil)
        }
    }

    @Test
    func normalEventViewerDismissClearsSelectedEvent() async throws {
        let eventID = eventID("event-1")
        let database = try makePreparedDatabase()
        let store = makeRootHarnessStore(database: database, eventID: eventID)

        store.send(.root(.handleNavigationRequest(.event(eventID, nil))))
        #expect(store.state.root.eventViewer?.id == eventID)

        await store.modify {
            $0.root.eventViewer = nil
        }?.value

        let appState = try await database.read { db in
            try AppState.fetchOne(db)
        }
        #expect(appState?.selectedEventID == nil)
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

    private func makeFileBackedPreparedDatabase(
        at databaseURL: URL
    ) throws -> any DatabaseWriter {
        let database = try DatabasePool(path: databaseURL.path)
        var migrator = DatabaseMigrator()
        OMERecord.DatabaseMigrations.register(into: &migrator)
        BlueskyActorCacheMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }

    private func makeReferenceDatabase(
        at databaseURL: URL
    ) throws -> SourceBaselineDatabase {
        try SourceReferenceDatabaseClient.prepareReferenceDirectory(for: databaseURL)
        let database = try defaultBaselineDatabase(path: databaseURL.path)
        try SourceReferenceDatabaseMigrator.openMusicEvent.migrate(database)
        return database
    }

    private func makeCoreDatabase() throws -> any DatabaseWriter {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OMERecord.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }

    private func temporarySourceRepositoryURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ome-source-detail-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func temporaryDirectoryURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ome-navigation-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeMinimalSourceRepository(at repositoryURL: URL) throws {
        let eventURL = repositoryURL
            .appending(path: "events", directoryHint: .isDirectory)
            .appending(path: "imported-event", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: eventURL, withIntermediateDirectories: true)
        try """
        name: Imported Event
        status: planned
        mode: community.lexicon.calendar.event#inperson
        timeZone: America/Denver
        """
        .write(
            to: eventURL.appending(path: "event.yml"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func makeTeamWorkspaceDetailStore(
        sourceBaselineID: SourceBaselineRecord.ID,
        database: any DatabaseWriter
    ) throws -> TestStore<TeamWorkspaceDetail> {
        return withDependencies {
            $0.context = .test
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: TeamWorkspaceDetail.State(sourceBaselineID: sourceBaselineID)) {
                TeamWorkspaceDetail()
            }
        }
    }

    private nonisolated static func insertOrganizer(
        _ db: Database,
        id organizerID: OMERecord.Organizer.ID
    ) throws {
        try OMERecord.Organizer.insert {
            OMERecord.Organizer.Draft(id: organizerID)
        }
        .execute(db)
    }

    private nonisolated static func insertEvent(
        _ db: Database,
        id eventID: OMERecord.Event.ID,
        name: String,
        startDate: LocalDate? = nil,
        endDate: LocalDate? = nil,
        timeZone: TimeZone = .current
    ) throws {
        try OMERecord.Event.insert {
            CreateEvent.makeEventDraft(
                id: eventID,
                name: name,
                startDate: startDate,
                endDate: endDate,
                timeZone: timeZone
            )
        }
        .execute(db)
    }

    private nonisolated static func insertEventOrganizer(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        organizerID: OMERecord.Organizer.ID
    ) throws {
        try OMERecord.EventOrganizer.insert {
            OMERecord.EventOrganizer.Draft(
                id: .init(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    eventOrganizerID: organizerID
                )
            )
        }
        .execute(db)
    }

    private nonisolated static func insertCalendar(
        _ db: Database,
        id calendarID: OMERecord.Calendar.ID,
        name: String,
        description: String? = nil,
        images: [OMERecord.ImageAsset]? = nil
    ) throws {
        try OMERecord.Calendar.insert {
            OMERecord.Calendar.Draft(
                id: calendarID,
                name: name,
                description: description,
                images: images
            )
        }
        .execute(db)
    }

    private nonisolated static func insertCalendarEntry(
        _ db: Database,
        id entryID: OMERecord.CalendarEntry.ID,
        event: OMERecord.Event.Reference,
        createdAt: Date,
        note: String? = nil,
        pinned: Bool = false
    ) throws {
        try OMERecord.CalendarEntry.insert {
            OMERecord.CalendarEntry.Draft(
                id: entryID,
                event: event,
                createdAt: createdAt,
                note: note,
                pinned: pinned
            )
        }
        .execute(db)
    }

    private nonisolated static func insertSourceBaseline(
        _ db: Database,
        sourceProvenance: OMERecord.SourceDatabaseInsertion.SourceProvenance,
        databaseFileName: String = "baseline.sqlite",
        importedAt: Date
    ) throws {
        let sourceBaseline = SourceBaselineRecord(
            source: sourceProvenance,
            databaseFileName: databaseFileName,
            importedAt: importedAt
        )
        try SourceBaselineRecord.insert {
            sourceBaseline
        } onConflict: {
            $0.id
        }
        .execute(db)
        try EditingWorkspaceRecord.insert {
            EditingWorkspaceRecord(teamSourceBaseline: sourceBaseline)
        } onConflict: {
            $0.id
        }
        .execute(db)
    }

    private nonisolated static func insertEventSourceProvenance(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        sourceProvenance: OMERecord.SourceDatabaseInsertion.SourceProvenance
    ) throws {
        let workspaceID = EditingWorkspaceRecord.ID(
            sourceBaselineID: SourceBaselineRecord.ID(source: sourceProvenance)
        )
        try EventSourceProvenanceRecord.insert {
            EventSourceProvenanceRecord(
                id: eventID,
                sourceBaselineID: SourceBaselineRecord.ID(source: sourceProvenance),
                sourceKind: sourceProvenance.kind,
                sourceReference: sourceProvenance.reference,
                ref: sourceProvenance.ref,
                eventIDOrigin: .inferred,
                sourceEventDirectory: eventID.eventID.rawValue.rawValue
            )
        }
        .execute(db)
        try EventEditingWorkspaceRecord.insert {
            EventEditingWorkspaceRecord(id: eventID, workspaceID: workspaceID)
        } onConflict: {
            $0.id
        }
        .execute(db)
    }

    private nonisolated static func insertLiveWorkspaceSourceFixture(
        _ db: Database,
        organizerID: OMERecord.Organizer.ID,
        calendarID: OMERecord.Calendar.ID,
        eventID: OMERecord.Event.ID,
        sourceProvenance: OMERecord.SourceDatabaseInsertion.SourceProvenance,
        importedAt: Date
    ) throws {
        try insertOrganizer(db, id: organizerID)
        try insertEvent(db, id: eventID, name: "Wicked Woods")
        try insertCalendar(db, id: calendarID, name: "Wicked Woods")
        try insertSourceBaseline(
            db,
            sourceProvenance: sourceProvenance,
            importedAt: importedAt
        )
        try insertEventSourceProvenance(
            db,
            eventID: eventID,
            sourceProvenance: sourceProvenance
        )
    }

    private nonisolated static func insertContributor(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        contributorID: String,
        name: String,
        did: DID? = nil,
        bio: String? = nil,
        imageURL: URL? = nil,
        logoURL: URL? = nil,
        links: [ExternalPlatform.Link]? = nil
    ) throws {
        try OMERecord.Contributor.insert {
            OMERecord.Contributor.Draft(
                id: OMERecord.Contributor.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    contributorID: contributorLocalID(contributorID)
                ),
                name: name,
                did: did,
                bio: bio,
                imageURL: imageURL,
                logoURL: logoURL,
                links: links
            )
        }
        .execute(db)
    }

    private nonisolated static func insertPerformance(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        performanceID: String,
        stageID: String,
        scheduleID: String,
        startTime: Date,
        endTime: Date,
        title: String,
        description: String? = nil,
        recordings: [ExternalPlatform.Asset] = []
    ) throws {
        try OMERecord.Performance.insert {
            OMERecord.Performance.Draft(
                id: OMERecord.Performance.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    performanceID: performanceLocalID(performanceID)
                ),
                stageID: stageLocalID(stageID),
                scheduleID: scheduleLocalID(scheduleID),
                startTime: startTime,
                endTime: endTime,
                title: title,
                description: description,
                recordings: recordings
            )
        }
        .execute(db)
    }

    private nonisolated static func insertPerformanceContributor(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        performanceID: String,
        contributorID: String,
        contributorActor: OMERecord.Contributor.Actor? = nil,
        billing: OMERecord.Performance.Contributors.Billing = .primary,
        role: OMERecord.Performance.Contributors.Role? = nil,
        sortIndex: Int = 0
    ) throws {
        try OMERecord.Performance.Contributors.insert {
            OMERecord.Performance.Contributors.Draft(
                performanceID: OMERecord.Performance.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    performanceID: performanceLocalID(performanceID)
                ),
                contributorID: contributorLocalID(contributorID),
                anonymousName: nil,
                contributorActor: contributorActor,
                billing: billing,
                role: role,
                sortIndex: sortIndex
            )
        }
        .execute(db)
    }

    private nonisolated static func insertSchedule(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        scheduleID: String,
        date: LocalDate,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        customTitle: String? = nil
    ) throws {
        try OMERecord.Schedule.insert {
            OMERecord.Schedule.Draft(
                id: OMERecord.Schedule.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    scheduleID: scheduleLocalID(scheduleID)
                ),
                date: date,
                startsAt: startsAt,
                endsAt: endsAt,
                customTitle: customTitle
            )
        }
        .execute(db)
    }

    private nonisolated static func insertStage(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        stageID: String,
        name: String,
        color: OMEColor = 0x336699,
        category: OMERecord.Stage.Category? = nil,
        sortIndex: Int? = nil,
        iconImageURL: URL? = nil,
        systemIconName: String? = nil,
        iconShortCode: String? = nil,
        imageURL: URL? = nil,
        posterImageURL: URL? = nil,
        lineup: [OMERecord.ID<OMERecord.Contributor>]? = nil
    ) throws {
        try OMERecord.Stage.insert {
            OMERecord.Stage.Draft(
                id: OMERecord.Stage.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    stageID: stageLocalID(stageID)
                ),
                name: name,
                color: color,
                category: category,
                sortIndex: sortIndex,
                iconImageURL: iconImageURL,
                systemIconName: systemIconName,
                iconShortCode: iconShortCode,
                imageURL: imageURL,
                posterImageURL: posterImageURL,
                lineup: lineup
            )
        }
        .execute(db)
    }

    private nonisolated static func insertChannel(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        channelID: String,
        name: String,
        description: String? = nil,
        sortIndex: Int? = nil,
        defaultNotificationState: OMERecord.Channel.NotificationState = .unsubscribed,
        notificationsRequired: Bool = false
    ) throws {
        try OMERecord.Channel.insert {
            OMERecord.Channel.Draft(
                id: channelRecordID(channelID, eventID: eventID),
                name: name,
                description: description ?? "Updates from \(name).",
                iconImageURL: nil,
                headerImageURL: nil,
                sortIndex: sortIndex,
                defaultNotificationState: defaultNotificationState,
                notificationsRequired: notificationsRequired
            )
        }
        .execute(db)
    }

    private nonisolated static func insertCommsPost(
        _ db: Database,
        eventID: OMERecord.Event.ID,
        channelID: String,
        postID: String,
        title: String,
        contents: String,
        headerImageURL: URL? = nil,
        timestamp: Date? = nil,
        isPinned: Bool = false,
        sortIndex: Int
    ) throws {
        try CommsPost.insert {
            CommsPost(
                id: commsPostID(postID, channelID: channelID, eventID: eventID),
                title: title,
                contents: contents,
                headerImageURL: headerImageURL,
                timestamp: timestamp,
                isPinned: isPinned,
                sortIndex: sortIndex
            )
        }
        .execute(db)
    }

    private func waitForBlueskyProfile(
        in store: StoreOf<ContributorDetail>
    ) async throws {
        for _ in 0..<100 {
            if store.profile?.handle != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(store.profile?.handle != nil)
    }

    private func waitForContributorListBlueskyProfile(
        in store: StoreOf<ContributorsViewer>,
        contributorID: OMERecord.ID<OMERecord.Contributor>
    ) async throws {
        for _ in 0..<100 {
            if store.contributorRows.first(where: { $0.contributorID == contributorID })?
                .profile.handle != nil {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(
            store.contributorRows.first(where: { $0.contributorID == contributorID })?
                .profile.handle != nil
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Condition was not satisfied", sourceLocation: sourceLocation)
    }

    private func makeRootHarnessStore(
        database: any DatabaseWriter,
        eventID: OMERecord.Event.ID = eventID("event-1"),
        variant: OpenMusicEventAppVariant = .generic,
        selectedEventIDAtLaunch: OMERecord.Event.ID? = nil
    ) -> TestStore<RootHarness> {
        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
        } operation: {
            var state = RootHarness.State()
            state.root = OpenMusicEventAppRoot.State(
                variant: variant,
                selectedEventIDAtLaunch: selectedEventIDAtLaunch
            )
            return TestStore(initialState: state) {
                RootHarness()
            }
        }
    }

    private func makeEventViewerHarnessStore(
        eventID: OMERecord.Event.ID = eventID("event-1"),
        defaultEventID: OMERecord.Event.ID? = nil,
        database: (any DatabaseWriter)? = nil
    ) throws -> TestStore<EventViewerHarness> {
        let database = try database ?? makePreparedDatabase()
        return withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = defaultEventID ?? eventID
        } operation: {
            TestStore(initialState: EventViewerHarness.State(eventID: eventID)) {
                EventViewerHarness()
            }
        }
    }
}

@Feature
private struct RootHarness {
    struct State {
        @DebugSnapshotIgnored
        var root = OpenMusicEventAppRoot.State()
    }

    enum Action {
        case root(OpenMusicEventAppRoot.Action)
    }

    var body: some Feature {
        Scope(\.root, action: \.root) {
            OpenMusicEventAppRoot()
        }
    }
}

@Feature
private struct MyEventsEventHarness {
    struct State {
        var lastRequest: NavigationRequest?
        var myEvents = MyEvents.State()
    }

    enum Action {
        case myEvents(MyEvents.Action)
    }

    var body: some Feature {
        Scope(\.myEvents, action: \.myEvents) {
            MyEvents()
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}

@Feature
private struct OrganizerDetailHarness {
    struct State {
        init(organizerID: OMERecord.Organizer.ID) {
            self.organizerDetail = OrganizerDetail.State(organizerID: organizerID)
        }

        var lastRequest: NavigationRequest?
        @DebugSnapshotIgnored
        var organizerDetail: OrganizerDetail.State
    }

    enum Action {
        case organizerDetail(OrganizerDetail.Action)
    }

    var body: some Feature {
        Scope(\.organizerDetail, action: \.organizerDetail) {
            OrganizerDetail()
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}

@Feature
private struct TeamWorkspaceDetailHarness {
    struct State {
        init(sourceBaselineID: SourceBaselineRecord.ID) {
            self.teamWorkspaceDetail = TeamWorkspaceDetail.State(sourceBaselineID: sourceBaselineID)
        }

        var lastRequest: NavigationRequest?
        @DebugSnapshotIgnored
        var teamWorkspaceDetail: TeamWorkspaceDetail.State
    }

    enum Action {
        case teamWorkspaceDetail(TeamWorkspaceDetail.Action)
    }

    var body: some Feature {
        Scope(\.teamWorkspaceDetail, action: \.teamWorkspaceDetail) {
            TeamWorkspaceDetail()
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}

@Feature
private struct CalendarDetailHarness {
    struct State {
        init(calendarID: OMERecord.Calendar.ID) {
            self.calendarDetail = CalendarDetail.State(calendarID: calendarID)
        }

        var lastRequest: NavigationRequest?
        @DebugSnapshotIgnored
        var calendarDetail: CalendarDetail.State
    }

    enum Action {
        case calendarDetail(CalendarDetail.Action)
    }

    var body: some Feature {
        Scope(\.calendarDetail, action: \.calendarDetail) {
            CalendarDetail()
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}

@Feature
private struct EventInfoRefreshHarness {
    struct State {
        init(eventID: OMERecord.Event.ID) {
            self.eventInfo = EventInfoViewer.State(eventID: eventID)
        }

        @DebugSnapshotIgnored
        var eventInfo: EventInfoViewer.State
        var lastRefreshRequest: SourceDataRefreshRequest?
    }

    enum Action {
        case eventInfo(EventInfoViewer.Action)
    }

    var body: some Feature {
        Scope(\.eventInfo, action: \.eventInfo) {
            EventInfoViewer()
        }
        .onEvent(SourceDataRefreshRequested.self) { request, state in
            state.lastRefreshRequest = request
        }
    }
}

@Feature
private struct EventViewerHarness {
    struct State {
        init(eventID: OMERecord.Event.ID = eventID("event-1")) {
            self.eventViewer = EventViewer.State.route(
                eventID: eventID,
                target: nil
            )
        }

        var lastRequest: NavigationRequest?
        @DebugSnapshotIgnored
        var eventViewer: EventViewer.State

        var eventInfoViewer: Spawn<EventInfoViewer> {
            get { eventViewer.eventInfoViewer! }
            set { eventViewer.eventInfoViewer = newValue }
        }

        var eventWorkspace: Spawn<EventWorkspace> {
            get { eventViewer.eventWorkspace! }
            set { eventViewer.eventWorkspace = newValue }
        }
    }

    enum Action {
        case eventViewer(EventViewer.Action)
    }

    var body: some Feature {
        Scope(\.eventViewer, action: \.eventViewer) {
            EventViewer()
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}
