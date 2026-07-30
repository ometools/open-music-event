import ATProto
import BlueskyActorCache
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SQLiteData
import SwiftUI

@Feature
public struct WorkspaceCollaborators {
    public init() {}

    @StoreTaskID var actorSearchTask

    public struct State {
        public init(
            workspaceID: EditingWorkspaceRecord.ID,
            role: OME.WorkspaceRole
        ) {
            self.workspaceID = workspaceID
            self.role = role
            self._cachedActorIdentities = Fetch(
                wrappedValue: CachedActorIdentities(),
                CachedActorIdentitiesRequest()
            )
            self._workspace = FetchOne(
                EditingWorkspaceRecord.where { $0.id.eq(workspaceID) }
            )
            self._relationships = FetchAll(
                WorkspaceRelationshipRecord
                    .where { $0.id.workspaceID.eq(workspaceID) }
            )
        }

        public let workspaceID: EditingWorkspaceRecord.ID
        public let role: OME.WorkspaceRole
        @DebugSnapshotIgnored
        @Fetch public var cachedActorIdentities: CachedActorIdentities
        @FetchOne public var workspace: EditingWorkspaceRecord?
        @FetchAll public var relationships: [WorkspaceRelationshipRecord]
        public var actorQuery = ""
        public var actorSearchFailures: [PredictiveSearchFailure] = []
        public var actorSearchIsLoading = false
        public var actorSearchSections: [PredictiveSearchSection<ActorIdentity>] = []
        public var draftCanPropose = true
        public var draftCanMerge = false
        public var errorMessage: String?
        public var isSaving = false
        public var selectedActorIdentity: ActorIdentity?

        mutating func resetActorSearch() {
            actorSearchFailures = []
            actorSearchIsLoading = false
            actorSearchSections = []
        }

        public var collaboratorActorReferences: [String] {
            relationships
                .map { $0.id.actorID.description }
                .sorted()
        }
    }

    public enum Action {
        case addButtonTapped
        case actorIdentityTapped(ActorIdentity)
        case actorSearchResponse(PredictiveSearchResponse<ActorIdentity>)
        case clearSelectedActorButtonTapped
        case removeButtonTapped(WorkspaceRelationshipRecord.ID)
        case toggleCapability(
            WorkspaceRelationshipRecord.ID,
            OME.WorkspaceRole.Capability
        )
    }

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addButtonTapped:
                guard state.role.canManageCollaborators,
                      !state.isSaving,
                      let publicRecord = state.workspace?.publicRecord
                else { return }
                let query = state.actorQuery
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let selectedActorIdentity = state.selectedActorIdentity
                guard selectedActorIdentity != nil || !query.isEmpty else {
                    state.errorMessage = "Enter a collaborator handle or DID."
                    return
                }
                let workspaceID = state.workspaceID
                var capabilities: Set<OME.WorkspaceRole.Capability> = []
                if state.draftCanPropose { capabilities.insert(.propose) }
                if state.draftCanMerge { capabilities.insert(.merge) }
                let database = database
                let now = now
                state.errorMessage = nil
                state.isSaving = true
                store.addTask {
                    do {
                        let identity: ActorIdentity
                        if let selectedActorIdentity {
                            identity = selectedActorIdentity
                        } else {
                            let response = await Self.exactActorSearch.search(query)
                            guard let resolvedIdentity = response.results.first else {
                                throw WorkspaceCollaboratorError.identityNotFound
                            }
                            identity = resolvedIdentity
                        }
                        guard identity.did != publicRecord.author else {
                            throw WorkspaceCollaboratorError.ownerCannotBeCollaborator
                        }
                        let relationship = OME.Relationship(
                            subject: .identity(
                                did: identity.did,
                                handle: identity.handle?.rawValue,
                                displayName: identity.displayName
                            ),
                            role: .collaborator(capabilities),
                            object: .record(publicRecord),
                            createdAt: ISO8601DateFormatter().string(from: now)
                        )
                        let record = WorkspaceRelationshipRecord(
                            id: .init(
                                workspaceID: workspaceID,
                                actorID: identity.did
                            ),
                            recordKey: WorkspaceRelationshipRecord.recordKey(
                                for: identity.did
                            ),
                            relationship: relationship
                        )
                        try await database.write { db in
                            try WorkspaceRelationshipRecord.insert { record }.execute(db)
                        }
                        try store.modify {
                            $0.actorQuery = ""
                            $0.resetActorSearch()
                            $0.draftCanPropose = true
                            $0.draftCanMerge = false
                            $0.errorMessage = nil
                            $0.isSaving = false
                            $0.selectedActorIdentity = nil
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = WorkspaceCollaboratorError.message(for: error)
                            $0.isSaving = false
                        }
                    }
                }

            case let .actorIdentityTapped(identity):
                guard state.role.canManageCollaborators,
                      !state.isSaving
                else { return }
                state.actorQuery = ""
                state.resetActorSearch()
                state.selectedActorIdentity = identity

            case let .actorSearchResponse(response):
                guard response.query == state.actorQuery.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) else { return }
                state.actorSearchFailures = response.failures
                state.actorSearchIsLoading = false
                state.actorSearchSections = response.sections

            case .clearSelectedActorButtonTapped:
                guard !state.isSaving else { return }
                state.errorMessage = nil
                state.selectedActorIdentity = nil

            case let .removeButtonTapped(id):
                guard state.role.canManageCollaborators,
                      !state.isSaving
                else { return }
                let database = database
                state.errorMessage = nil
                state.isSaving = true
                store.addTask {
                    do {
                        try await database.write { db in
                            try WorkspaceRelationshipRecord
                                .where { $0.id.workspaceID.eq(id.workspaceID) }
                                .where { $0.id.actorID.eq(id.actorID) }
                                .delete()
                                .execute(db)
                        }
                        try store.modify {
                            $0.errorMessage = nil
                            $0.isSaving = false
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = WorkspaceCollaboratorError.message(for: error)
                            $0.isSaving = false
                        }
                    }
                }

            case let .toggleCapability(id, capability):
                guard state.role.canManageCollaborators,
                      !state.isSaving,
                      let stored = state.relationships.first(where: { $0.id == id }),
                      case var .collaborator(capabilities) = stored.relationship.workspaceRole
                else { return }
                if capabilities.contains(capability) {
                    capabilities.remove(capability)
                } else {
                    capabilities.insert(capability)
                }
                var relationship = stored.relationship
                relationship.role = .collaborator
                relationship.capabilities = capabilities.sorted { $0.rawValue < $1.rawValue }
                let updated = WorkspaceRelationshipRecord(
                    id: stored.id,
                    recordKey: stored.recordKey,
                    relationship: relationship
                )
                let database = database
                state.errorMessage = nil
                state.isSaving = true
                store.addTask {
                    do {
                        try await database.write { db in
                            try WorkspaceRelationshipRecord.insert { updated }.execute(db)
                        }
                        try store.modify {
                            $0.errorMessage = nil
                            $0.isSaving = false
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = WorkspaceCollaboratorError.message(for: error)
                            $0.isSaving = false
                        }
                    }
                }
            }
        }
        .onChange(of: store.actorQuery) { _, rawQuery, state in
            let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            state.errorMessage = nil

            guard state.role.canManageCollaborators,
                  query.count >= 2
            else {
                state.resetActorSearch()
                return
            }

            state.resetActorSearch()
            state.actorSearchIsLoading = true
            state.selectedActorIdentity = nil
            store.addTask(id: actorSearchTask) {
                let response = await Self.actorLookaheadSearch.search(query)
                try Task.checkCancellation()
                try store.send(.actorSearchResponse(response))
            }
        }
        .onMount { state in
            let actors = state.collaboratorActorReferences
            guard !actors.isEmpty else { return }
            let blueskyActorProfileCache = blueskyActorProfileCache
            store.addTask {
                for actor in actors {
                    do {
                        _ = try await blueskyActorProfileCache.refreshProfileIfNeeded(
                            actor,
                            24 * 60 * 60,
                            15 * 60
                        )
                    } catch is CancellationError {
                        return
                    } catch {
                    }
                }
            }
        }
        .onChange(of: store.collaboratorActorReferences) { _, actors, _ in
            guard !actors.isEmpty else { return }
            let blueskyActorProfileCache = blueskyActorProfileCache
            store.addTask {
                for actor in actors {
                    do {
                        _ = try await blueskyActorProfileCache.refreshProfileIfNeeded(
                            actor,
                            24 * 60 * 60,
                            15 * 60
                        )
                    } catch is CancellationError {
                        return
                    } catch {
                    }
                }
            }
        }
    }

    static let actorLookaheadSearch = PredictiveSearch(
        actorIdentitySources: [
            .appBskyActorTypeahead(title: "Profiles", limit: 10),
        ],
        minimumQueryLength: 2
    )

    static let exactActorSearch = PredictiveSearch(
        actorIdentitySources: [
            .exactActorIdentityLookup(title: "Exact match"),
        ],
        minimumQueryLength: 2
    )
}

private enum WorkspaceCollaboratorError: Error {
    case identityNotFound
    case ownerCannotBeCollaborator

    static func message(for error: any Error) -> String {
        if let error = error as? Self {
            switch error {
            case .identityNotFound:
                return "No matching account was found."
            case .ownerCannotBeCollaborator:
                return "The workspace owner already has full access."
            }
        }
        return "Unable to update workspace collaborators."
    }
}

public struct WorkspaceCollaboratorsView: View {
    @Bindable var store: StoreOf<WorkspaceCollaborators>

    public init(store: StoreOf<WorkspaceCollaborators>) {
        self.store = store
    }

    public var body: some View {
        List {
            Section("Add collaborator") {
                if let selectedActorIdentity = store.selectedActorIdentity {
                    ContributorActorIdentityRow(
                        identity: selectedActorIdentity,
                        isSelected: true
                    )

                    Button("Clear selection") {
                        store.send(.clearSelectedActorButtonTapped)
                    }
                    .disabled(store.isSaving)
                } else {
                    TextField("Search profiles", text: $store.actorQuery)
                        .autocorrectionDisabled()
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit {
                            store.send(.addButtonTapped)
                        }

                    if store.actorSearchIsLoading {
                        ProgressView()
                    }

                    ForEach(store.actorSearchSections) { section in
                        Text(section.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(section.results) { identity in
                            Button {
                                store.send(.actorIdentityTapped(identity))
                            } label: {
                                ContributorActorIdentityRow(
                                    identity: identity,
                                    isSelected: false
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isSaving)
                        }
                    }

                    ForEach(store.actorSearchFailures, id: \.sourceID) { failure in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(failure.title)
                            Text(failure.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Toggle("Can propose changes", isOn: $store.draftCanPropose)
                Toggle("Can merge changes", isOn: $store.draftCanMerge)

                Button {
                    store.send(.addButtonTapped)
                } label: {
                    if store.isSaving {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Saving")
                        }
                    } else {
                        Text("Add Collaborator")
                    }
                }
                .disabled(store.isSaving || store.workspace?.publicRecord == nil)

                if store.workspace?.publicRecord == nil {
                    Text("Collaborators require a published workspace identity.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Collaborators") {
                if store.relationships.isEmpty {
                    Text("No collaborators")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.relationships) { stored in
                    WorkspaceCollaboratorRow(
                        stored: stored,
                        cachedIdentity: store.cachedActorIdentities[
                            stored.id.actorID.description
                        ],
                        isDisabled: store.isSaving,
                        toggleCapability: { capability in
                            store.send(.toggleCapability(stored.id, capability))
                        },
                        remove: {
                            store.send(.removeButtonTapped(stored.id))
                        }
                    )
                }
            }
        }
    }

}

struct WorkspaceCollaboratorRow: View {
    let stored: WorkspaceRelationshipRecord
    let cachedIdentity: ActorIdentity?
    let isDisabled: Bool
    let toggleCapability: (OME.WorkspaceRole.Capability) -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(identityTitle)
                .font(.headline)
            if let subtitle = identitySubtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            capabilityButton("Can propose changes", capability: .propose)
            capabilityButton("Can merge changes", capability: .merge)

            Button("Remove Collaborator", role: .destructive, action: remove)
        }
        .disabled(isDisabled)
    }

    var storedIdentity: OME.Relationship.IdentityReference? {
        guard case let .known(subject) = stored.relationship.subject else { return nil }
        return subject.identity
    }

    var identityTitle: String {
        if let displayName = cachedIdentity?.displayName, !displayName.isEmpty {
            return displayName
        }
        if let displayName = storedIdentity?.displayName, !displayName.isEmpty {
            return displayName
        }
        if let handle = cachedIdentity?.handle?.rawValue, !handle.isEmpty {
            return "@\(handle)"
        }
        if let handle = storedIdentity?.handle, !handle.isEmpty {
            return "@\(handle)"
        }
        return stored.id.actorID.description
    }

    var identitySubtitle: String? {
        if let handle = cachedIdentity?.handle?.rawValue, !handle.isEmpty,
           cachedIdentity?.displayName?.isEmpty == false {
            return "@\(handle) · \(stored.id.actorID)"
        }
        if let handle = storedIdentity?.handle, !handle.isEmpty,
           storedIdentity?.displayName?.isEmpty == false {
            return "@\(handle) · \(stored.id.actorID)"
        }
        guard identityTitle != stored.id.actorID.description else { return nil }
        return stored.id.actorID.description
    }

    var capabilities: Set<OME.WorkspaceRole.Capability> {
        guard case let .collaborator(capabilities) = stored.relationship.workspaceRole else {
            return []
        }
        return capabilities
    }

    func capabilityButton(
        _ title: String,
        capability: OME.WorkspaceRole.Capability
    ) -> some View {
        Button {
            toggleCapability(capability)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(capabilities.contains(capability) ? "Allowed" : "Not allowed")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
