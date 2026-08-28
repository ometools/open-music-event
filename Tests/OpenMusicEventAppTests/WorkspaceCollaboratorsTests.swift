import ATProto
import Clocks
import ComposableArchitecture2
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
    struct DefaultAuthoringGrantConsumer {
        @SharedReader(.defaultAuthoringGrant)
        var grant: AuthoringGrant?
    }

    @Test
    func `default authoring grant resolves the scoped shared reader`() throws {
        let ownerID = try #require(DID("did:plc:owner"))
        let workspace = workspace(ownerID: ownerID)
        let firstEventID = OME.Event.ID(
            organizerID: ownerID,
            eventID: OME.ID<OME.Event>(rawValue: "first")
        )
        let secondEventID = OME.Event.ID(
            organizerID: ownerID,
            eventID: OME.ID<OME.Event>(rawValue: "second")
        )
        let ownerGrant = AuthoringGrant(
            principal: AuthoringPrincipal(actorID: ownerID),
            role: .owner,
            workspaceID: workspace.id
        )
        let storage = InMemoryStorage()

        let (firstGrant, firstConsumer) = withDependencies {
            $0.defaultEventID = firstEventID
            $0.defaultInMemoryStorage = storage
        } operation: {
            let grant = Shared<AuthoringGrant?>(.defaultAuthoringGrant)
            return (grant, DefaultAuthoringGrantConsumer())
        }
        let (_, secondConsumer) = withDependencies {
            $0.defaultEventID = secondEventID
            $0.defaultInMemoryStorage = storage
        } operation: {
            let grant = Shared<AuthoringGrant?>(.defaultAuthoringGrant)
            return (grant, DefaultAuthoringGrantConsumer())
        }

        expectNoDifference(firstConsumer.grant, nil)
        expectNoDifference(secondConsumer.grant, nil)

        firstGrant.withLock { $0 = ownerGrant }

        expectNoDifference(firstConsumer.grant, ownerGrant)
        expectNoDifference(secondConsumer.grant, nil)
    }

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
            let eventID = OME.Event.ID(
                organizerID: ownerID,
                eventID: OME.ID<OME.Event>(rawValue: "empty-workspace")
            )
            var state = withDependencies {
                $0.defaultEventID = eventID
            } operation: {
                let authoringGrant = Shared<AuthoringGrant?>(.defaultAuthoringGrant)
                authoringGrant.withLock { $0 = grant }
                return EventWorkspace.State(
                    workspace: workspace,
                    eventID: eventID,
                    workspacePhase: SharedReader(value: .inactive)
                )
            }

            withDependencies {
                $0.defaultEventID = eventID
            } operation: {
                state.updateAuthoringGrant(grant)
            }

            let collaborators = try #require(state.collaborators)
            expectNoDifference(collaborators.role, grant.role)
            #expect(collaborators.relationships.isEmpty)
            expectNoDifference(
                state.availablePages,
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
    func `a grant for another workspace does not expose authoring pages`() throws {
        try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            let ownerID = try #require(DID("did:plc:owner"))
            let workspace = workspace(ownerID: ownerID)
            let otherWorkspace = SourceWorkspace(
                organizerID: workspace.organizerID,
                repository: "tangled.org/owner/other-events",
                branch: "main"
            )
            let eventID = OME.Event.ID(
                organizerID: ownerID,
                eventID: OME.ID<OME.Event>(rawValue: "empty-workspace")
            )
            let state = withDependencies {
                $0.defaultEventID = eventID
            } operation: {
                let authoringGrant = Shared<AuthoringGrant?>(.defaultAuthoringGrant)
                authoringGrant.withLock {
                    $0 = AuthoringGrant(
                        principal: AuthoringPrincipal(actorID: ownerID),
                        role: .owner,
                        workspaceID: otherWorkspace.id
                    )
                }
                return EventWorkspace.State(
                    workspace: workspace,
                    eventID: eventID,
                    workspacePhase: SharedReader(value: .inactive)
                )
            }

            expectNoDifference(state.authoringAccess, .attendee)
            expectNoDifference(state.availablePages, [.changes])
            #expect(!state.changes.canPropose)
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
            let workspace = workspace(ownerID: ownerID)
            return withAuthoringGrant(workspace: workspace, role: .owner) {
                TestStore(
                    initialState: WorkspaceCollaborators.State(workspace: workspace)
                ) {
                    WorkspaceCollaborators()
                }
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
            return withAuthoringGrant(workspace: workspace, role: .owner) {
                TestStore(
                    initialState: WorkspaceCollaborators.State(workspace: workspace)
                ) {
                    WorkspaceCollaborators()
                }
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
        let workspace = workspace(ownerID: ownerID)
        let store = withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.defaultDatabase = database
        } operation: {
            return withAuthoringGrant(
                workspace: workspace,
                role: .collaborator([.merge])
            ) {
                TestStore(
                    initialState: WorkspaceCollaborators.State(workspace: workspace)
                ) {
                    WorkspaceCollaborators()
                }
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

    func withAuthoringGrant<Value>(
        workspace: SourceWorkspace,
        role: OME.WorkspaceRole,
        operation: () -> Value
    ) -> Value {
        let eventID = OME.Event.ID(
            organizerID: workspace.organizerID,
            eventID: OME.ID<OME.Event>(rawValue: "workspace-collaborators")
        )
        return withDependencies {
            $0.defaultEventID = eventID
        } operation: {
            let authoringGrant = Shared<AuthoringGrant?>(.defaultAuthoringGrant)
            authoringGrant.withLock {
                $0 = AuthoringGrant(
                    principal: AuthoringPrincipal(
                        actorID: DID(workspace.organizerID.description)!
                    ),
                    role: role,
                    workspaceID: workspace.id
                )
            }
            return operation()
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
