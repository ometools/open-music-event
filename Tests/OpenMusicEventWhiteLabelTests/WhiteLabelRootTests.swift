import ATProto
import ComposableArchitecture2
import ComposableCalendarEvents
import Dependencies
import DependenciesTestSupport
import Foundation
import Observation
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
            Store(
                initialState: WhiteLabelRoot.State(
                    configuration: WickedWoodsWhiteLabel.configuration(
                        organizerID: organizerID
                    )
                )
            ) {
                WhiteLabelRoot()
            }
        }

        await whiteLabelWaitUntil {
            store.organizationDetail != nil
                && !store.isLoading
        }

        #expect(store.organizationDetail?.state.organizerID == organizerID)
        #expect(store.organizationDetail?.state.collection == OMERecord.Event.nsid)
        #expect(installations.withLock { $0 }.isEmpty)
        #expect(gitOperations.snapshot.isEmpty)
        #expect(!store.isLoading)
        #expect(store.errorMessage == nil)
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
            Store(
                initialState: WhiteLabelRoot.State(
                    configuration: WickedWoodsWhiteLabel.configuration(
                        organizerID: organizerID
                    )
                )
            ) {
                WhiteLabelRoot()
            }
        }

        await whiteLabelWaitUntil {
            store.organizationDetail != nil
                && !store.isLoading
        }

        let organization = try #require(store.spawn(\.organizationDetail))
        let loadTask = organization.send(.task)
        await loadTask?.value
        #expect(organization.events == [selectedEvent])
        #expect(!organization.isLoading)
        #expect(organization.organizer == selectedEvent.organizer)

        let selectionTask = organization.send(.eventButtonTapped(eventURI))
        await selectionTask?.value

        let eventDetail = try #require(organization.eventDetail)
        #expect(eventDetail.state.event == selectedEvent)
        #expect(installations.withLock { $0 }.isEmpty)
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
            Store(
                initialState: WhiteLabelRoot.State(
                    configuration: WhiteLabelAppConfiguration(
                        brand: WhiteLabelBrand(displayName: "Wicked Woods"),
                        handle: WickedWoodsWhiteLabel.handle
                    )
                )
            ) {
                WhiteLabelRoot()
            }
        }

        await whiteLabelWaitUntil {
            store.organizationDetail != nil
                && !store.isLoading
        }

        #expect(resolvedHandles.withLock { $0 } == ["wickedwoods.ca"])
        #expect(installations.withLock { $0 }.isEmpty)
        #expect(store.organizationDetail?.state.organizerID == organizerID)
        #expect(store.organizationDetail?.state.collection == OMERecord.Event.nsid)
        #expect(store.errorMessage == nil)
    }

}

@MainActor
private func whiteLabelWaitUntil(
    _ condition: @escaping @MainActor () -> Bool
) async {
    while !condition() {
        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = condition()
            } onChange: {
                continuation.resume()
            }
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
