import ATProto
import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
import IssueReporting
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SourceEditing
import SQLiteData
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

private typealias OMERecord = OpenMusicEventLexicon.OpenMusicEvent

@MainActor
@Suite(.tcaExhaustivity(.off))
struct SourceManagementTests {
    @Test
    func generatesCalendarSourcePatch() async throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(OMERecord.Organizer.ID("did:plc:sourcemanagement"))
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let sourceBaselineID = SourceBaselineRecord.ID(rawValue: "source")
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "calendar.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] =
                SourcePatchGenerator { request in
                    #expect(
                        request == OpenMusicEventCalendarSourcePatchRequest(
                            calendarID: calendarID,
                            sourceBaselineID: sourceBaselineID
                        )
                    )
                    return patch
                }
        } operation: {
            TestStore(
                initialState: SourceManagement.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            ) {
                SourceManagement()
            }
        }

        let task = store.send(.generateSourcePatchButtonTapped) {
            $0.sourcePatchStatus = .generating
        }
        await store.receive(
            \.sourcePatchGenerationResponse,
            .equals(.success(patch)),
            timeout: .seconds(1)
        ) {
            $0.sourcePatchStatus = .generated(patch)
        }
        await task?.value
    }

    @Test
    func proposesCalendarSourcePatch() throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(OMERecord.Organizer.ID("did:plc:sourcemanagement"))
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let sourceBaselineID = SourceBaselineRecord.ID(rawValue: "source")
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "calendar.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = SourceManagement.State(
                sourceBaselineID: sourceBaselineID,
                calendarID: calendarID
            )
            state.sourcePatchStatus = .generated(patch)
            return TestStore(initialState: state) {
                SourceManagement()
            }
        }

        store.send(.proposeChangeButtonTapped) {
            $0.sourceProposalStatus = .composing
        }
        #expect(store.state.sourceProposal?.target == .calendar(calendarID, sourceBaselineID))
        #expect(store.state.sourceProposal?.sourceChangeGroups == [])
        #expect(store.state.sourceProposal?.patch == patch)
    }

    @Test
    func failedCalendarSourcePatchReportsEphemeralError() async throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(OMERecord.Organizer.ID("did:plc:sourcemanagement"))
        let calendarID = OMERecord.Calendar.ID(
            ownerID: organizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let sourceBaselineID = SourceBaselineRecord.ID(rawValue: "source")

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0[SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self] =
                SourcePatchGenerator { _ in
                    throw SourceManagementPatchFailure()
                }
        } operation: {
            TestStore(
                initialState: SourceManagementErrorHost.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            ) {
                SourceManagementErrorHost()
            }
        }

        await withIssueReporters([]) {
            await store.send(to: \.sourceManagement, .generateSourcePatchButtonTapped)?.value
        }

        guard case .failed = store.state.sourceManagement.state.sourcePatchStatus else {
            Issue.record("Expected source patch status to be failed.")
            return
        }
        let latestError = store.state.errorNotifications.state.latestError
        #expect(latestError?.kind == .unhandled)
        #expect(latestError?.message.fallback == "Unable to check source changes.")
        #expect(latestError?.operation == .sourcePatchGeneration)
    }
}

private func makePreparedDatabase() throws -> any DatabaseWriter {
    try withDependencies {
        $0.context = .test
    } operation: {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OMERecord.DatabaseMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }
}

private struct SourceManagementPatchFailure: Error {}

@Feature
private struct SourceManagementErrorHost {
    struct State {
        init(
            sourceBaselineID: SourceBaselineRecord.ID,
            calendarID: OMERecord.Calendar.ID
        ) {
            sourceManagement = Spawn(
                SourceManagement.State(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
            )
        }

        var errorNotifications = Spawn(ErrorNotifications.State())
        var sourceManagement: Spawn<SourceManagement>
    }

    enum Action {}

    var body: some Feature {
        Update { _, _ in }
            .spawn(\.sourceManagement) {
                SourceManagement()
            }
            .spawn(\.errorNotifications) {
                ErrorNotifications()
            }
            .onEvent(ErrorReported.self) { error, state in
                state.errorNotifications.state.report(error)
            }
    }
}
