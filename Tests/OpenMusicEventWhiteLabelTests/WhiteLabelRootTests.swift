import ATProto
import ComposableArchitecture2
import ComposableCalendarEvents
import Dependencies
import DependenciesTestSupport
import ErrorHandling
import Foundation
import IssueReporting
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import OpenMusicEventViewers
import SourceControlClient
import SQLiteData
import Synchronization
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventWhiteLabel

private typealias OMERecord = OpenMusicEventLexicon.OpenMusicEvent

@MainActor
@Suite
struct WhiteLabelRootTests {
    @Test
    func `white label opens the configured organization instead of an event`() async throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(
            OMERecord.Organizer.ID("did:plc:5df2u7ief6m6tn77jznicxob")
        )
        let eventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: OMERecord.ID<OMERecord.Event>(rawValue: "ome-workspace-2026")
        )
        let installations = Mutex<[ATProto.URI]>([])
        let gitOperations = GitOperationRecorder()

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.calendarEvents = .openMusicEventAndAtmo(database: database)
            $0.omeEventInstallation = OMEEventInstallationClient { uri in
                installations.withLock { $0.append(uri) }
                return eventID
            }
            recordUnexpectedGitOperations(in: &$0, recorder: gitOperations)
        } operation: {
            TestStore(
                initialState: WhiteLabelStory.State(
                    configuration: WickedWoodsWhiteLabel.configuration(
                        organizerID: organizerID
                    )
                )
            ) {
                WhiteLabelStory()
            } changes: {
                $0.root.isLoading = true
            }
        }

        try await whiteLabelWaitUntil {
            store.root.organizationDetail != nil
                && !store.root.isLoading
        }
        store.expect {
            $0.root.isLoading = false
            $0.root.organizationDetail = OrganizationDetail.State.DebugSnapshot(
                collection: OMERecord.Event.nsid,
                organizerID: organizerID
            )
        }

        #expect(store.lastRequest == nil)
        #expect(installations.withLock { $0 }.isEmpty)
        #expect(gitOperations.snapshot.isEmpty)
        #expect(!store.root.isLoading)
        #expect(store.root.errorMessage == nil)
        await store.dismount(timeout: .seconds(1))
    }

    @Test
    func `white label organization events open Event Detail without entering it`() async throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(
            OMERecord.Organizer.ID("did:plc:5df2u7ief6m6tn77jznicxob")
        )
        let eventURI = try #require(
            ATProto.URI(
                "at://did:plc:5df2u7ief6m6tn77jznicxob/app.openmusicevent.event/ome-workspace-2026"
            )
        )
        let selectedEvent = CalendarEvent(
            uri: eventURI,
            name: "Wicked Woods 2026",
            startsAt: Date(timeIntervalSince1970: 200),
            organizer: CalendarEvent.Organizer(id: organizerID),
            source: CalendarEvent.Source(collection: OMERecord.Event.nsid),
            timeZoneIdentifier: "America/Denver"
        )
        let eventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: OMERecord.ID<OMERecord.Event>(rawValue: "ome-workspace-2026")
        )
        let installations = Mutex<[ATProto.URI]>([])

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.calendarEvents = CalendarEventsClient(
                browse: { _ in CalendarEvent.Page(events: [selectedEvent]) },
                event: { _ in selectedEvent },
                organizer: { _ in selectedEvent.organizer }
            )
            $0.omeEventInstallation = OMEEventInstallationClient { uri in
                installations.withLock { $0.append(uri) }
                return eventID
            }
        } operation: {
            TestStore(
                initialState: WhiteLabelStory.State(
                    configuration: WickedWoodsWhiteLabel.configuration(
                        organizerID: organizerID
                    )
                )
            ) {
                WhiteLabelStory()
            } changes: {
                $0.root.isLoading = true
            }
        }

        try await whiteLabelWaitUntil {
            store.root.organizationDetail != nil
                && !store.root.isLoading
        }
        store.expect {
            $0.root.isLoading = false
            $0.root.organizationDetail = OrganizationDetail.State.DebugSnapshot(
                collection: OMERecord.Event.nsid,
                organizerID: organizerID
            )
        }

        let loadTask = store.send(to: \.root.organizationDetail, .task) {
            $0.root.organizationDetail?.isLoading = true
        }
        await loadTask?.value
        store.expect {
            $0.root.organizationDetail?.events = [selectedEvent]
            $0.root.organizationDetail?.isLoading = false
            $0.root.organizationDetail?.organizer = selectedEvent.organizer
        }

        let selectionTask = store.send(
            to: \.root.organizationDetail,
            .eventButtonTapped(eventURI)
        )
        await selectionTask?.value

        let eventDetail = try #require(store.root.organizationDetail?.eventDetail)
        #expect(eventDetail.event == selectedEvent)
        #expect(store.lastRequest == nil)
        #expect(installations.withLock { $0 }.isEmpty)
        await store.dismount(timeout: .seconds(1))
    }

    @Test
    func `white label handle resolution opens the same organization detail`() async throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(
            OMERecord.Organizer.ID("did:plc:5df2u7ief6m6tn77jznicxob")
        )
        let eventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: OMERecord.ID<OMERecord.Event>(rawValue: "ome-workspace-2026")
        )
        let resolvedHandles = Mutex<[String]>([])
        let installations = Mutex<[ATProto.URI]>([])

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.calendarEvents = .openMusicEventAndAtmo(database: database)
            $0.whiteLabelOrganizerIdentityResolver = .init { handle in
                resolvedHandles.withLock { $0.append(handle) }
                return organizerID
            }
            $0.omeEventInstallation = OMEEventInstallationClient { uri in
                installations.withLock { $0.append(uri) }
                return eventID
            }
        } operation: {
            TestStore(
                initialState: WhiteLabelStory.State(
                    configuration: WhiteLabelAppConfiguration(
                        brand: WhiteLabelBrand(displayName: "Wicked Woods"),
                        handle: WickedWoodsWhiteLabel.handle
                    )
                )
            ) {
                WhiteLabelStory()
            } changes: {
                $0.root.isLoading = true
            }
        }

        try await whiteLabelWaitUntil {
            store.root.organizationDetail != nil
                && !store.root.isLoading
        }
        store.expect {
            $0.root.isLoading = false
            $0.root.organizationDetail = OrganizationDetail.State.DebugSnapshot(
                collection: OMERecord.Event.nsid,
                organizerID: organizerID
            )
        }

        #expect(resolvedHandles.withLock { $0 } == ["wickedwoods.ca"])
        #expect(installations.withLock { $0 }.isEmpty)
        #expect(store.lastRequest == nil)
        #expect(store.root.errorMessage == nil)
        await store.dismount(timeout: .seconds(1))
    }

}

@MainActor
private func whiteLabelWaitUntil(
    _ condition: @escaping @MainActor () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(1))
    while clock.now < deadline {
        if condition() { return }
        try await clock.sleep(for: .milliseconds(1))
    }
    Issue.record(
        "Condition was not satisfied within one second.",
        sourceLocation: sourceLocation
    )
    try #require(condition())
}

@Feature
private struct WhiteLabelStory {
    struct State {
        init(configuration: WhiteLabelAppConfiguration) {
            self.root = WhiteLabelRoot.State(configuration: configuration)
        }

        var lastErrorOperation: ErrorOperation?
        var lastRequest: NavigationRequest?
        var root: WhiteLabelRoot.State
    }

    enum Action {
        case root(WhiteLabelRoot.Action)
    }

    var body: some Feature {
        Scope(\.root, action: \.root) {
            WhiteLabelRoot()
        }
        .onEvent(ErrorReported.self) { error, state in
            state.lastErrorOperation = error.operation
        }
        .onEvent(NavigationRequested.self) { request, state in
            state.lastRequest = request
        }
    }
}

private func makePreparedDatabase() throws -> any DatabaseWriter {
    let database = try SQLiteData.defaultDatabase()
    var migrator = DatabaseMigrator()
    OMERecord.DatabaseMigrations.register(into: &migrator)
    OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
    try migrator.migrate(database)
    return database
}

private func recordUnexpectedGitOperations(
    in dependencies: inout DependencyValues,
    recorder: GitOperationRecorder
) {
    struct UnexpectedGitOperation: Error {}

    dependencies.sourceControl.clone = { _ in
        recorder.append("clone")
        throw UnexpectedGitOperation()
    }
    dependencies.sourceControl.open = { _ in
        recorder.append("open")
        throw UnexpectedGitOperation()
    }
    dependencies.sourceControl.fetch = { _ in
        recorder.append("fetch")
        throw UnexpectedGitOperation()
    }
    dependencies.sourceControl.checkout = { _ in
        recorder.append("checkout")
        throw UnexpectedGitOperation()
    }
}

private final class GitOperationRecorder: Sendable {
    private let values = Mutex<[String]>([])

    var snapshot: [String] { values.withLock { $0 } }

    func append(_ operation: String) {
        values.withLock { $0.append(operation) }
    }
}
