import ATProto
import ComposableArchitecture2
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
    func `white label browses and installs through the ordinary event boundary`() async throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(
            OMERecord.Organizer.ID("did:plc:5df2u7ief6m6tn77jznicxob")
        )
        let eventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: OMERecord.ID<OMERecord.Event>(rawValue: "wicked-woods-ome-2026")
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

        await store.expect {
            $0.root.isLoading = false
            $0.lastRequest = .event(eventID, nil)
        }

        #expect(
            installations.withLock { $0 }
                == [OMERecord.Event.reference(id: eventID).uri]
        )
        #expect(gitOperations.snapshot.isEmpty)
        #expect(!store.root.isLoading)
        #expect(store.root.errorMessage == nil)
        await store.dismount(timeout: .seconds(1))
    }

    @Test
    func `white label handle resolution still uses the same browse and install flow`() async throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(
            OMERecord.Organizer.ID("did:plc:5df2u7ief6m6tn77jznicxob")
        )
        let eventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: OMERecord.ID<OMERecord.Event>(rawValue: "wicked-woods-ome-2026")
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

        await store.expect {
            $0.root.isLoading = false
            $0.lastRequest = .event(eventID, nil)
        }

        #expect(resolvedHandles.withLock { $0 } == ["wickedwoods.ca"])
        #expect(
            installations.withLock { $0 }
                == [OMERecord.Event.reference(id: eventID).uri]
        )
        #expect(store.root.errorMessage == nil)
        await store.dismount(timeout: .seconds(1))
    }

    @Test
    func `missing published event is visible and retryable without authoring state`() async throws {
        let database = try makePreparedDatabase()
        let missingOrganizerID = try #require(
            OMERecord.Organizer.ID("did:plc:missingwhitelabel")
        )
        let installations = Mutex<[ATProto.URI]>([])

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.calendarEvents = .openMusicEventAndAtmo(database: database)
            $0.omeEventInstallation = OMEEventInstallationClient { uri in
                installations.withLock { $0.append(uri) }
                throw WhiteLabelError.missingEvent(missingOrganizerID)
            }
        } operation: {
            TestStore(
                initialState: WhiteLabelStory.State(
                    configuration: WhiteLabelAppConfiguration(
                        brand: WhiteLabelBrand(displayName: "Missing Festival"),
                        organizerID: missingOrganizerID
                    )
                )
            ) {
                WhiteLabelStory()
            } changes: {
                $0.root.isLoading = true
            }
        }

        await store.expect {
            $0.root.isLoading = false
            $0.root.errorMessage = "Unable to load event."
            $0.lastErrorOperation = "white-label.load"
        }

        #expect(installations.withLock { $0 }.isEmpty)
        #expect(!store.root.isLoading)
        #expect(store.root.errorMessage == "Unable to load event.")
        await store.dismount(timeout: .seconds(1))
    }
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
