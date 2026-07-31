import ATProto
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SQLiteData
import Testing

@testable import OpenMusicEventAppEventViewer

@MainActor
@Suite("Workspace collaborators", .serialized)
struct WorkspaceCollaboratorsTests {
    @Test
    func ownerFindsCollaboratorsWithPredictiveSearchBeforeAddingThem() async throws {
        let database = try makePreparedDatabase()
        let identity = ActorIdentity(
            did: try #require(DID("did:plc:alice")),
            handle: .init(rawValue: "alice.example"),
            displayName: "Alice",
            source: .typeahead
        )
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.actorTypeaheadSearch.search = { query in
                expectNoDifference(query.normalizedText, "alice")
                return [identity]
            }
            $0.actorIdentityLookup.resolve = { _ in
                Issue.record(
                    "Predictive lookahead must not run exact identity lookup while typing."
                )
                throw ActorIdentityLookupError.emptyInput
            }
        } operation: {
            TestStore(
                initialState: WorkspaceCollaborators.State(
                    workspaceID: .init(rawValue: "team.workspace"),
                    role: .owner
                )
            ) {
                WorkspaceCollaborators()
            }
        }

        let searchTask = store.modify {
            $0.actorQuery = " alice "
        } changes: {
            $0.actorSearchIsLoading = true
        }

        await store.receive(\.actorSearchResponse) {
            $0.actorSearchIsLoading = false
            $0.actorSearchSections = [
                PredictiveSearchSection(
                    sourceID: "app.bsky.actor.searchActorsTypeahead",
                    title: "Profiles",
                    results: [identity]
                )
            ]
        }
        await searchTask?.value

        expectNoDifference(store.actorSearchSections.map(\.title), ["Profiles"])
        expectNoDifference(
            store.actorSearchSections.flatMap(\.results),
            [identity]
        )
        #expect(store.actorSearchFailures.isEmpty)
        #expect(store.actorSearchIsLoading == false)

        store.send(.actorIdentityTapped(identity)) {
            $0.actorQuery = ""
            $0.actorSearchSections = []
            $0.selectedActorIdentity = identity
        }
    }

    @Test
    func ownerAddsUpdatesAndRemovesOneRelationshipPerActor() async throws {
        let database = try makePreparedDatabase()
        let ownerID = try #require(DID("did:plc:owner"))
        let collaboratorID = try #require(DID("did:plc:collaborator"))
        let workspace = workspace(ownerID: ownerID)
        try await insert(workspace, into: database)
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 1_785_283_200)
            $0.actorIdentityLookup.resolve = { query in
                #expect(query == "alice.example")
                return ActorIdentity(
                    did: collaboratorID,
                    handle: .init(rawValue: "alice.example"),
                    displayName: "Alice",
                    source: .canonicalResolution
                )
            }
        } operation: {
            var initialState = WorkspaceCollaborators.State(
                workspaceID: workspace.id,
                role: .owner
            )
            initialState.actorQuery = "alice.example"
            return Store(initialState: initialState) {
                WorkspaceCollaborators()
            }
        }

        try await waitForCondition { store.workspace == workspace }
        await store.send(.addButtonTapped)?.value
        var stored = try #require(
            try await relationship(
                workspaceID: workspace.id,
                actorID: collaboratorID,
                in: database
            )
        )
        #expect(stored.recordKey == WorkspaceRelationshipRecord.recordKey(for: collaboratorID))
        #expect(stored.relationship.workspaceRole == .collaborator([.propose]))

        await store.send(.toggleCapability(stored.id, .merge))?.value
        stored = try #require(
            try await relationship(
                workspaceID: workspace.id,
                actorID: collaboratorID,
                in: database
            )
        )
        #expect(stored.relationship.workspaceRole == .collaborator([.propose, .merge]))

        await store.send(.removeButtonTapped(stored.id))?.value
        #expect(
            try await relationship(
                workspaceID: workspace.id,
                actorID: collaboratorID,
                in: database
            ) == nil
        )
    }

    @Test
    func collaboratorRoleCannotManageTheRoster() async throws {
        let database = try makePreparedDatabase()
        let ownerID = try #require(DID("did:plc:owner"))
        let workspace = workspace(ownerID: ownerID)
        try await insert(workspace, into: database)
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.actorIdentityLookup.resolve = { _ in
                Issue.record("A collaborator must not be able to resolve or add roster members.")
                throw ActorIdentityLookupError.emptyInput
            }
        } operation: {
            var initialState = WorkspaceCollaborators.State(
                workspaceID: workspace.id,
                role: .collaborator([.merge])
            )
            initialState.actorQuery = "alice.example"
            return Store(initialState: initialState) {
                WorkspaceCollaborators()
            }
        }

        try await waitForCondition { store.workspace == workspace }
        await store.send(.addButtonTapped)?.value
        let count = try await database.read { db in
            try WorkspaceRelationshipRecord.fetchCount(db)
        }
        #expect(count == 0)
    }

    private func workspace(ownerID: DID) -> EditingWorkspaceRecord {
        EditingWorkspaceRecord(
            id: .init(rawValue: "team.workspace"),
            kind: .team,
            referenceDatabaseFileName: "workspace.sqlite",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1),
            publicRecord: OME.Relationship.RecordReference(
                author: ownerID,
                collection: OME.SourceRecord.nsid,
                rkey: ATProto.Record.Key(rawValue: OME.SourceRecord.canonicalRecordKey)
            )
        )
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

    private func insert(
        _ workspace: EditingWorkspaceRecord,
        into database: any DatabaseWriter
    ) async throws {
        try await database.write { db in
            try EditingWorkspaceRecord.insert { workspace }.execute(db)
        }
    }

    private func relationship(
        workspaceID: EditingWorkspaceRecord.ID,
        actorID: DID,
        in database: any DatabaseWriter
    ) async throws -> WorkspaceRelationshipRecord? {
        try await database.read { db in
            try WorkspaceRelationshipRecord
                .where { $0.id.workspaceID.eq(workspaceID) }
                .where { $0.id.actorID.eq(actorID) }
                .fetchOne(db)
        }
    }

    private func waitForCondition(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }
}
