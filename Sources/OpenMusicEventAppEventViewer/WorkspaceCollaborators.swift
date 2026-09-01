import ATProto
import BlueskyActorCache
import ComposableArchitecture2
import ComposableForms
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventComponents
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct WorkspaceCollaborators {
    public init() {}

    public struct State {
        public init(workspace: SourceWorkspace) {
            self.workspace = workspace
            self._cachedActorIdentities = Fetch(
                wrappedValue: CachedActorIdentities(),
                CachedActorIdentitiesRequest()
            )
            self._relationships = FetchAll(
                WorkspaceRelationshipRecord.where { $0.id.workspaceID.eq(workspace.id) }
            )
        }

        public let workspace: SourceWorkspace
        public var workspaceID: SourceWorkspace.ID { workspace.id }
        @SharedReader(.defaultAuthoringGrant)
        public var authoringGrant: AuthoringGrant?
        public var role: OME.WorkspaceRole {
            guard authoringGrant?.workspaceID == workspaceID else {
                return .collaborator([])
            }
            return authoringGrant?.role ?? .collaborator([])
        }
        @DebugSnapshotIgnored
        @Fetch public var cachedActorIdentities: CachedActorIdentities
        @FetchAll public var relationships: [WorkspaceRelationshipRecord]
        public var destination: Destination.State?

        public var collaboratorActorReferences: [String] {
            relationships.map { $0.id.actorID.description }.sorted()
        }
    }

    public enum Action {
        case addCollaboratorButtonTapped
        case collaboratorButtonTapped(WorkspaceRelationshipRecord.ID)
        case destination(Destination.Action)
    }

    @Feature
    public enum Destination {
        case collaboratorForm(WorkspaceCollaboratorForm)
    }

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addCollaboratorButtonTapped:
                guard state.role.canManageCollaborators else { return }
                state.destination = .collaboratorForm(
                    WorkspaceCollaboratorForm.State(
                        workspace: state.workspace,
                        role: state.role
                    )
                )

            case let .collaboratorButtonTapped(id):
                guard state.role.canManageCollaborators,
                      let relationship = state.relationships.first(where: { $0.id == id })
                else { return }
                state.destination = .collaboratorForm(
                    WorkspaceCollaboratorForm.State(
                        workspace: state.workspace,
                        role: state.role,
                        relationship: relationship
                    )
                )

            case .destination:
                break
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .onMount { state in
            refreshProfiles(state.collaboratorActorReferences)
        }
        .onChange(of: store.collaboratorActorReferences) { _, actors, _ in
            refreshProfiles(actors)
        }
    }

    func refreshProfiles(_ actors: [String]) {
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
                    continue
                }
            }
        }
    }
}

@Feature
public struct WorkspaceCollaboratorForm {
    public init() {}

    @StoreTaskID var actorSearchTask

    public struct FormValue: Equatable, Sendable {
        public init(
            actorQuery: String = "",
            selectedActorIdentity: ActorIdentity? = nil,
            canPropose: Bool = true,
            canMerge: Bool = false
        ) {
            self.actorQuery = actorQuery
            self.selectedActorIdentity = selectedActorIdentity
            self.canPropose = canPropose
            self.canMerge = canMerge
        }

        public var actorQuery: String
        public var canMerge: Bool
        public var canPropose: Bool
        public var selectedActorIdentity: ActorIdentity?

        public var trimmedActorQuery: String {
            actorQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public typealias FormFeature = ComposableForms.Form<FormValue>

    public struct State {
        public init(
            workspace: SourceWorkspace,
            role: OME.WorkspaceRole,
            relationship: WorkspaceRelationshipRecord? = nil
        ) {
            self.workspace = workspace
            self.role = role
            self.relationship = relationship
            let capabilities: Set<OME.WorkspaceRole.Capability>
            if let relationship,
               case let .collaborator(storedCapabilities) = relationship.relationship.workspaceRole
            {
                capabilities = storedCapabilities
            } else {
                capabilities = [.propose]
            }
            let identityQuery = relationship?.id.actorID.description ?? ""
            self.form = FormFeature.State(
                value: FormValue(
                    actorQuery: identityQuery,
                    canPropose: capabilities.contains(.propose),
                    canMerge: capabilities.contains(.merge)
                )
            )
        }

        public let workspace: SourceWorkspace
        public let role: OME.WorkspaceRole
        public let relationship: WorkspaceRelationshipRecord?
        public var form: FormFeature.State
        public var actorSearchFailures: [PredictiveSearchFailure] = []
        public var actorSearchIsLoading = false
        public var actorSearchSections: [PredictiveSearchSection<ActorIdentity>] = []
        public var isSaving = false

        public var isEditing: Bool { relationship != nil }
        public var canSubmit: Bool { role.canManageCollaborators && !isSaving && form.canSubmit }

        mutating func resetActorSearch() {
            actorSearchFailures = []
            actorSearchIsLoading = false
            actorSearchSections = []
        }
    }

    public enum Action {
        case actorIdentityTapped(ActorIdentity)
        case actorSearchResponse(PredictiveSearchResponse<ActorIdentity>)
        case cancelButtonTapped
        case clearSelectedActorButtonTapped
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case removeButtonTapped
        case saveButtonTapped
    }

    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Scope(\.form, action: \.form) {
            FormFeature()
                .onSubmit { value in
                    try store.send(.formSubmitted(value))
                }
        }
        Update { state, action in
            switch action {
            case let .actorIdentityTapped(identity):
                guard !state.isEditing, !state.isSaving else { return }
                state.form.value.selectedActorIdentity = identity
                state.form.value.actorQuery = identity.handle?.rawValue ?? identity.did.description
                state.resetActorSearch()

            case let .actorSearchResponse(response):
                guard response.query == state.form.value.trimmedActorQuery else { return }
                state.actorSearchFailures = response.failures
                state.actorSearchIsLoading = false
                state.actorSearchSections = response.sections

            case .cancelButtonTapped:
                guard !state.isSaving else { return }
                store.addTask { try store.dismiss() }

            case .clearSelectedActorButtonTapped:
                guard !state.isEditing, !state.isSaving else { return }
                state.form.value.actorQuery = ""
                state.form.value.selectedActorIdentity = nil
                state.resetActorSearch()

            case .form:
                break

            case let .formSubmitted(value):
                guard state.canSubmit else { return }
                let workspace = state.workspace
                let relationship = state.relationship
                let database = database
                let now = now
                state.isSaving = true
                store.addTask {
                    let result: Void? = await store.withErrorHandling(
                        fallbackMessage: relationship == nil
                            ? .workspaceCollaboratorAddFailed
                            : .workspaceCollaboratorEditFailed,
                        operation: relationship == nil
                            ? .workspaceCollaboratorAdd
                            : .workspaceCollaboratorEdit
                    ) {
                        let identity: ActorIdentity
                        if let existing = relationship {
                            identity = ActorIdentity(
                                did: existing.id.actorID,
                                source: .canonicalResolution
                            )
                        } else if let selected = value.selectedActorIdentity {
                            identity = selected
                        } else {
                            let response = await Self.exactActorSearch.search(value.trimmedActorQuery)
                            guard let resolved = response.results.first else {
                                throw WorkspaceCollaboratorError.identityNotFound
                            }
                            identity = resolved
                        }
                        guard identity.did != workspace.organizerID else {
                            throw WorkspaceCollaboratorError.ownerCannotBeCollaborator
                        }

                        var capabilities: Set<OME.WorkspaceRole.Capability> = []
                        if value.canPropose { capabilities.insert(.propose) }
                        if value.canMerge { capabilities.insert(.merge) }

                        let record: WorkspaceRelationshipRecord
                        if let existing = relationship {
                            var updatedRelationship = existing.relationship
                            updatedRelationship.role = .collaborator
                            updatedRelationship.capabilities = capabilities.sorted {
                                $0.rawValue < $1.rawValue
                            }
                            record = WorkspaceRelationshipRecord(
                                id: existing.id,
                                recordKey: existing.recordKey,
                                relationship: updatedRelationship
                            )
                        } else {
                            let sourceRecord = OME.Relationship.RecordReference(
                                author: workspace.organizerID,
                                collection: OME.SourceRecord.nsid,
                                rkey: ATProto.Record.Key(rawValue: OME.SourceRecord.canonicalRecordKey)
                            )
                            let newRelationship = OME.Relationship(
                                subject: .identity(
                                    did: identity.did,
                                    handle: identity.handle?.rawValue,
                                    displayName: identity.displayName
                                ),
                                role: .collaborator(capabilities),
                                object: .record(sourceRecord),
                                createdAt: ISO8601DateFormatter().string(from: now)
                            )
                            record = WorkspaceRelationshipRecord(
                                id: .init(workspaceID: workspace.id, actorID: identity.did),
                                recordKey: WorkspaceRelationshipRecord.recordKey(for: identity.did),
                                relationship: newRelationship
                            )
                        }
                        try await database.write { db in
                            try WorkspaceRelationshipRecord.insert { record }.execute(db)
                        }
                    } cleanup: {
                        $0.isSaving = false
                    }
                    guard result != nil else { return }
                    try store.modify { $0.isSaving = false }
                    try store.dismiss()
                }

            case .removeButtonTapped:
                guard state.role.canManageCollaborators,
                      !state.isSaving,
                      let relationship = state.relationship
                else { return }
                let database = database
                state.isSaving = true
                store.addTask {
                    let result: Void? = await store.withErrorHandling(
                        fallbackMessage: .workspaceCollaboratorRemoveFailed,
                        operation: .workspaceCollaboratorRemove
                    ) {
                        try await database.write { db in
                            try WorkspaceRelationshipRecord
                                .where { $0.id.workspaceID.eq(relationship.id.workspaceID) }
                                .where { $0.id.actorID.eq(relationship.id.actorID) }
                                .delete()
                                .execute(db)
                        }
                    } cleanup: {
                        $0.isSaving = false
                    }
                    guard result != nil else { return }
                    try store.modify { $0.isSaving = false }
                    try store.dismiss()
                }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                store.addTask { try store.send(.form(.submittedForm)) }
            }
        }
        .onChange(of: store.form.value.actorQuery) { _, rawQuery, state in
            guard !state.isEditing else { return }
            let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard state.role.canManageCollaborators,
                  state.form.value.selectedActorIdentity == nil,
                  query.count >= 2
            else {
                state.resetActorSearch()
                return
            }
            state.resetActorSearch()
            state.actorSearchIsLoading = true
            store.addTask(id: actorSearchTask) {
                let response = await Self.actorLookaheadSearch.search(query)
                try Task.checkCancellation()
                try store.send(.actorSearchResponse(response))
            }
        }
    }

    static let actorLookaheadSearch = PredictiveSearch(
        actorIdentitySources: [.appBskyActorTypeahead(title: "Profiles", limit: 10)],
        minimumQueryLength: 2
    )

    static let exactActorSearch = PredictiveSearch(
        actorIdentitySources: [.exactActorIdentityLookup(title: "Exact match")],
        minimumQueryLength: 2
    )
}

enum WorkspaceCollaboratorFormFieldID {
    static var actorQuery: AnyHashable {
        AnyHashable(\WorkspaceCollaboratorForm.FormValue.actorQuery)
    }
}

extension WorkspaceCollaboratorForm.FormFeature {
    init() {
        self.init {
            Self.Field(\.actorQuery) {
                Validation(error: "Select or enter a collaborator.") { value in
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
        }
    }
}

enum WorkspaceCollaboratorError: Error {
    case identityNotFound
    case ownerCannotBeCollaborator
}

public struct WorkspaceCollaboratorsView: View {
    @Bindable var store: StoreOf<WorkspaceCollaborators>

    public init(store: StoreOf<WorkspaceCollaborators>) {
        self.store = store
    }

    public var body: some View {
        List {
            if store.role.canManageCollaborators {
                Section {
                    Button {
                        store.send(.addCollaboratorButtonTapped)
                    } label: {
                        Label("Add Collaborator", mappedSystemImage: "person.3")
                    }
                    .accessibilityIdentifier("workspace.collaborator.add")
                }
            }

            Section("Collaborators") {
                if store.relationships.isEmpty {
                    ContentUnavailableView {
                        Label("No Collaborators", mappedSystemImage: "person.3")
                    } description: {
                        Text("No one else has access to propose or merge workspace changes.")
                    }
                }

                ForEach(store.relationships) { stored in
                    if store.role.canManageCollaborators {
                        Button {
                            store.send(.collaboratorButtonTapped(stored.id))
                        } label: {
                            WorkspaceCollaboratorRow(
                                stored: stored,
                                cachedIdentity: store.cachedActorIdentities[stored.id.actorID.description]
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "workspace.collaborator.row.\(stored.id.actorID.description)"
                        )
                    } else {
                        WorkspaceCollaboratorRow(
                            stored: stored,
                            cachedIdentity: store.cachedActorIdentities[stored.id.actorID.description]
                        )
                    }
                }
            }
        }
        .navigationTitle("Collaborators")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $store.scope(\.destination, action: \.destination).collaboratorForm) {
            formStore in
            NavigationStack {
                WorkspaceCollaboratorFormView(store: formStore)
            }
        }
    }
}

struct WorkspaceCollaboratorRow: View {
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    let stored: WorkspaceRelationshipRecord
    let cachedIdentity: ActorIdentity?

    var storedIdentity: OME.Relationship.IdentityReference? {
        guard case let .known(subject) = stored.relationship.subject else { return nil }
        return subject.identity
    }

    var capabilities: Set<OME.WorkspaceRole.Capability> {
        guard case let .collaborator(capabilities) = stored.relationship.workspaceRole else {
            return []
        }
        return capabilities
    }

    var identityDisplayName: String? {
        cachedIdentity?.displayName ?? storedIdentity?.displayName
    }

    var identityHandle: String? {
        cachedIdentity?.handle?.rawValue ?? storedIdentity?.handle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(TechnicalDetails.identityTitle(
                displayName: identityDisplayName,
                handle: identityHandle,
                technicalID: stored.id.actorID.description,
                isVisible: showsTechnicalDetails
            ))
            .font(.headline)

            if let subtitle = TechnicalDetails.identitySubtitle(
                displayName: identityDisplayName,
                handle: identityHandle,
                technicalID: stored.id.actorID.description,
                isVisible: showsTechnicalDetails
            ) {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(permissionSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    var permissionSummary: String {
        switch (capabilities.contains(.propose), capabilities.contains(.merge)) {
        case (true, true): "Can propose and merge changes"
        case (true, false): "Can propose changes"
        case (false, true): "Can merge changes"
        case (false, false): "Read-only access"
        }
    }
}

public struct WorkspaceCollaboratorFormView: View {
    @Bindable var store: StoreOf<WorkspaceCollaboratorForm>
    @State var isRemoveConfirmationPresented = false

    public init(store: StoreOf<WorkspaceCollaboratorForm>) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Collaborator") {
                if store.isEditing, let relationship = store.relationship {
                    Text(relationship.id.actorID.description)
                        .selectableText()
                } else if let selected = store.form.value.selectedActorIdentity {
                    ContributorActorIdentityRow(identity: selected, isSelected: true)
                    Button("Choose a different profile") {
                        store.send(.clearSelectedActorButtonTapped)
                    }
                    .disabled(store.isSaving)
                } else {
                    TextField("Search profiles", text: $store.form.value.actorQuery)
                        .autocorrectionDisabled()
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .accessibilityIdentifier("workspace.collaborator.search")

                    FormFieldValidationStatus(
                        validation: store.form.validation[WorkspaceCollaboratorFormFieldID.actorQuery]
                    )

                    if store.actorSearchIsLoading {
                        ProgressView("Searching")
                    }
                    ForEach(store.actorSearchSections) { section in
                        Text(section.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(section.results) { identity in
                            Button {
                                store.send(.actorIdentityTapped(identity))
                            } label: {
                                ContributorActorIdentityRow(identity: identity, isSelected: false)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("workspace.collaborator.result.\(identity.did.description)")
                        }
                    }
                    ForEach(store.actorSearchFailures, id: \.sourceID) { failure in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(failure.title)
                            Text(failure.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Permissions") {
                Toggle("Can propose changes", isOn: $store.form.value.canPropose)
                    .accessibilityIdentifier("workspace.collaborator.can-propose")
                Toggle("Can merge changes", isOn: $store.form.value.canMerge)
                    .accessibilityIdentifier("workspace.collaborator.can-merge")
            }

            if store.isEditing {
                Section {
                    Button("Remove Collaborator", role: .destructive) {
                        isRemoveConfirmationPresented = true
                    }
                    .disabled(store.isSaving)
                    .accessibilityIdentifier("workspace.collaborator.remove")
                }
            }
        }
        .disabled(store.isSaving)
        .navigationTitle(store.isEditing ? "Edit Collaborator" : "Add Collaborator")
        .interactiveDismissDisabled(store.isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { store.send(.cancelButtonTapped) }
                    .disabled(store.isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                SubmitButton(
                    isInProgress: store.isSaving,
                    isDisabled: !store.canSubmit
                ) {
                    store.send(.saveButtonTapped)
                }
                .accessibilityIdentifier("workspace.collaborator.save")
            }
        }
        .confirmationDialog(
            "Remove this collaborator?",
            isPresented: $isRemoveConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Collaborator", role: .destructive) {
                store.send(.removeButtonTapped)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will no longer be able to propose or merge changes in this workspace.")
        }
    }
}

extension UserFacingText {
    static let workspaceCollaboratorAddFailed = Self(
        "The collaborator could not be added.",
        fallback: "The collaborator could not be added."
    )
    static let workspaceCollaboratorEditFailed = Self(
        "The collaborator could not be updated.",
        fallback: "The collaborator could not be updated."
    )
    static let workspaceCollaboratorRemoveFailed = Self(
        "The collaborator could not be removed.",
        fallback: "The collaborator could not be removed."
    )
}

extension ErrorOperation {
    static let workspaceCollaboratorAdd = Self("workspace.collaborator.add")
    static let workspaceCollaboratorEdit = Self("workspace.collaborator.edit")
    static let workspaceCollaboratorRemove = Self("workspace.collaborator.remove")
}
