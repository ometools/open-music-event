import ATProto
import Clocks
import ComposableArchitecture2
import ComposableAuthoring
import ComposableWorkspace
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
import Testing

@testable import OpenMusicEventAppEventViewer

@MainActor
@Suite("Workspace collaborators", .serialized, .tcaExhaustivity(.off))
struct WorkspaceCollaboratorsTests {
    @Test
    func `a proposer sees proposals and the read-only collaborator roster`() throws {
        try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            let ownerID = try #require(DID("did:plc:owner"))
            let memberID = try #require(DID("did:plc:member"))
            let workspace = workspace(ownerID: ownerID)
            let grant = AuthoringGrant(
                principal: AuthoringPrincipal(actorID: memberID),
                role: .collaborator([.propose]),
                workspaceID: workspace.id
            )
            var state = EventWorkspace.State(
                workspace: workspace,
                eventID: OME.Event.ID(
                    organizerID: ownerID,
                    eventID: OME.ID<OME.Event>(rawValue: "empty-workspace")
                ),
                workspacePhase: SharedReader(value: .inactive)
            )

            state.updateAuthoringGrant(grant)

            let collaborators = try #require(state.collaborators)
            expectNoDifference(collaborators.role, grant.role)
            #expect(collaborators.relationships.isEmpty)
            expectNoDifference(
                state.availablePages(authoringAccess: grant.access),
                EventWorkspace.Page.allCases
            )
            expectNoDifference(
                EventWorkspace.availablePages(
                    hasCollaborators: false,
                    authoringAccess: .attendee
                ),
                [.changes]
            )
            expectNoDifference(
                EventWorkspace.availablePages(
                    hasCollaborators: false,
                    authoringAccess: .authoring(.collaborator([.propose]))
                ),
                [.changes, .proposals]
            )
            expectNoDifference(
                EventWorkspace.availablePages(
                    hasCollaborators: false,
                    authoringAccess: .authoring(.collaborator([.merge]))
                ),
                [.changes, .proposals]
            )
        }
    }

    @Test
    func ownerFindsAndSelectsAProfileInTheAddForm() async throws {
        let database = try makePreparedDatabase()
        let ownerID = try #require(DID("did:plc:owner"))
        let identity = ActorIdentity(
            did: try #require(DID("did:plc:alice")),
            handle: .init(rawValue: "alice.example"),
            displayName: "Alice",
            source: .typeahead
        )
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
            $0.actorTypeaheadSearch.search = { query in
                expectNoDifference(query.normalizedText, "alice")
                return [identity]
            }
        } operation: {
            TestStore(
                initialState: WorkspaceCollaborators.State(
                    workspace: workspace(ownerID: ownerID),
                    role: .owner
                )
            ) {
                WorkspaceCollaborators()
            }
        }

        store.send(.addCollaboratorButtonTapped)
        let searchTask = store.modify {
            guard case var .collaboratorForm(form) = $0.destination else { return }
            form.form.value.actorQuery = " alice "
            $0.destination = .collaboratorForm(form)
        }
        await searchTask?.value

        try await waitUntil {
            guard case let .collaboratorForm(form)? = store.destination else { return false }
            return form.actorSearchSections.flatMap(\.results) == [identity]
        }

        store.send(.destination(.collaboratorForm(.actorIdentityTapped(identity))))
        guard case let .collaboratorForm(form)? = store.destination else {
            Issue.record("The add form must remain mounted after profile selection.")
            return
        }
        expectNoDifference(form.form.value.selectedActorIdentity, identity)
        expectNoDifference(form.form.value.actorQuery, "alice.example")
    }

    @Test
    func ownerAddsEditsAndRemovesOneRelationshipPerActor() async throws {
        let database = try makePreparedDatabase()
        let ownerID = try #require(DID("did:plc:owner"))
        let collaboratorID = try #require(DID("did:plc:collaborator"))
        let workspace = workspace(ownerID: ownerID)
        let identity = ActorIdentity(
            did: collaboratorID,
            handle: .init(rawValue: "alice.example"),
            displayName: "Alice",
            source: .canonicalResolution
        )
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 1_785_283_200)
        } operation: {
            TestStore(
                initialState: WorkspaceCollaborators.State(
                    workspace: workspace,
                    role: .owner
                )
            ) {
                WorkspaceCollaborators()
            }
        }

        store.send(.addCollaboratorButtonTapped)
        let validation = store.modify {
            guard case var .collaboratorForm(form) = $0.destination else { return }
            form.form.value.actorQuery = "alice.example"
            form.form.value.selectedActorIdentity = identity
            $0.destination = .collaboratorForm(form)
        }
        await validation?.value
        await store.send(
            .destination(
                .collaboratorForm(
                    .form(.fieldSubmitted(WorkspaceCollaboratorFormFieldID.actorQuery))
                )
            )
        )?.value
        await store.send(.destination(.collaboratorForm(.saveButtonTapped)))?.value

        try await waitUntil {
            try await relationship(
                workspaceID: workspace.id,
                actorID: collaboratorID,
                in: database
            ) != nil
        }

        var stored = try #require(
            try await relationship(
                workspaceID: workspace.id,
                actorID: collaboratorID,
                in: database
            )
        )
        #expect(stored.relationship.workspaceRole == .collaborator([.propose]))

        store.send(.collaboratorButtonTapped(stored.id))
        store.modify {
            guard case var .collaboratorForm(form) = $0.destination else { return }
            form.form.value.canMerge = true
            $0.destination = .collaboratorForm(form)
        }
        await store.send(.destination(.collaboratorForm(.saveButtonTapped)))?.value

        try await waitUntil {
            try await relationship(
                workspaceID: workspace.id,
                actorID: collaboratorID,
                in: database
            )?.relationship.workspaceRole == .collaborator([.propose, .merge])
        }

        stored = try #require(
            try await relationship(
                workspaceID: workspace.id,
                actorID: collaboratorID,
                in: database
            )
        )
        #expect(stored.relationship.workspaceRole == .collaborator([.propose, .merge]))

        store.send(.collaboratorButtonTapped(stored.id))
        await store.send(.destination(.collaboratorForm(.removeButtonTapped)))?.value
        try await waitUntil {
            try await relationship(
                workspaceID: workspace.id,
                actorID: collaboratorID,
                in: database
            ) == nil
        }
        #expect(
            try await relationship(
                workspaceID: workspace.id,
                actorID: collaboratorID,
                in: database
            ) == nil
        )
    }

    @Test
    func collaboratorRoleCannotMountMutationFormsOrWrite() async throws {
        let database = try makePreparedDatabase()
        let ownerID = try #require(DID("did:plc:owner"))
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: WorkspaceCollaborators.State(
                    workspace: workspace(ownerID: ownerID),
                    role: .collaborator([.merge])
                )
            ) {
                WorkspaceCollaborators()
            }
        }

        store.send(.addCollaboratorButtonTapped)
        #expect(store.destination.map { _ in true } == nil)
        let count = try await database.read { db in
            try WorkspaceRelationshipRecord.fetchCount(db)
        }
        #expect(count == 0)
    }

    func workspace(ownerID: DID) -> SourceWorkspace {
        SourceWorkspace(
            organizerID: OME.Organizer.ID(ownerID.description)!,
            repository: "tangled.org/\(ownerID.description)/events",
            branch: "main"
        )
    }

    func makePreparedDatabase() throws -> any DatabaseWriter {
        try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            @Dependency(\.defaultDatabase) var database
            return database
        }
    }

    func relationship(
        workspaceID: SourceWorkspace.ID,
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

    func waitUntil(
        _ condition: @escaping @MainActor () async throws -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while clock.now < deadline {
            if try await condition() { return }
            try await clock.sleep(for: .milliseconds(1))
        }
        Issue.record("Condition was not satisfied within one second.", sourceLocation: sourceLocation)
    }
}
