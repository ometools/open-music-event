import ATProto
import ATProtoTypes
import Bluesky
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import SwiftUI

@Feature
public struct RelationshipForm {
    public init() {}

    public enum SubjectKind: String, CaseIterable, Hashable, Sendable {
        case account
        case record
        case unsupported
    }

    public struct State {
        public init(eventID: Event.ID) {
            self.eventID = eventID
            self.recordID = nil
            self.subjectKind = .account
            self.canPropose = true
        }

        public init(eventID: Event.ID, relationship: OME.Relationship) {
            self.eventID = eventID
            self.recordID = relationship.id
            self.role = relationship.role.rawValue
            self.canPropose = relationship.capabilities?.contains(.propose) == true
            self.canMerge = relationship.capabilities?.contains(.merge) == true
            switch relationship.subject {
            case let .known(.identity(identity)):
                self.subjectKind = .account
                self.selectedIdentity = identity
            case let .known(.record(record)):
                self.subjectKind = .record
                self.subjectRecordURI = record.uri.description
            case .unknown:
                self.subjectKind = .unsupported
            }
        }

        public let eventID: Event.ID
        public let recordID: ATProto.URI?
        public var subjectKind: SubjectKind
        public var selectedIdentity: OME.Relationship.IdentityReference?
        public var subjectRecordURI = ""
        public var role = "collaborator"
        public var canPropose = false
        public var canMerge = false
        public var actorSearchQuery = ""
        public var actorSearchSections: [PredictiveSearchSection<ActorIdentity>] = []
        public var actorSearchFailures: [PredictiveSearchFailure] = []
        public var actorSearchIsLoading = false
        public var errorMessage: String?
        public var isSaving = false
        public var showsDeleteConfirmation = false

        public var navigationTitle: String {
            recordID == nil ? "Add Relationship" : "Edit Relationship"
        }

        public var preparedFields: RelationshipRecordEditing.Fields? {
            let subject: Open<OME.Relationship.Entity>
            switch subjectKind {
            case .account:
                guard let selectedIdentity else { return nil }
                subject = .known(.identity(selectedIdentity))
            case .record:
                let value = subjectRecordURI.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let uri = ATProto.URI(value),
                      case .did = uri.authority,
                      uri.collection != nil,
                      uri.rkey != nil
                else { return nil }
                subject = .known(.record(.init(uri: uri)))
            case .unsupported:
                return nil
            }
            let role = role.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !role.isEmpty else { return nil }
            let capabilities: [OME.WorkspaceRole.Capability]? = role == OME.Relationship.Role.collaborator.rawValue
                ? ([canPropose ? .propose : nil, canMerge ? .merge : nil].compactMap { $0 })
                : nil
            return RelationshipRecordEditing.Fields(
                subject: subject,
                role: OME.Relationship.Role(role),
                capabilities: capabilities
            )
        }

        public var canSubmit: Bool { !isSaving && preparedFields != nil }
    }

    public enum Action {
        case actorIdentityTapped(ActorIdentity)
        case actorSearchQueryChanged(String)
        case actorSearchResponse(PredictiveSearchResponse<ActorIdentity>)
        case actorSearchSubmitted
        case cancelButtonTapped
        case clearIdentityButtonTapped
        case deleteButtonTapped
        case deleteConfirmed
        case roleSelected(OME.Relationship.Role)
        case saveButtonTapped
    }

    @Dependency(\.date.now) var now
    @Dependency(\.defaultDatabase) var database
    @StoreTaskID var actorSearchTask

    public var body: some Feature {
        Update { state, action in
            switch action {
            case let .actorIdentityTapped(identity):
                state.selectedIdentity = OME.Relationship.IdentityReference(
                    did: identity.did,
                    handle: identity.handle?.rawValue,
                    displayName: identity.displayName
                )
                state.actorSearchQuery = ""
                state.actorSearchSections = []
                state.actorSearchFailures = []
                state.actorSearchIsLoading = false

            case let .actorSearchQueryChanged(query):
                state.actorSearchQuery = query
                search(query: query, exact: false, state: &state)

            case let .actorSearchResponse(response):
                guard response.query == state.actorSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return
                }
                state.actorSearchIsLoading = false
                state.actorSearchSections = response.sections
                state.actorSearchFailures = response.failures

            case .actorSearchSubmitted:
                search(query: state.actorSearchQuery, exact: true, state: &state)

            case .cancelButtonTapped:
                store.addTask { try store.dismiss() }

            case .clearIdentityButtonTapped:
                state.selectedIdentity = nil

            case .deleteButtonTapped:
                state.showsDeleteConfirmation = true

            case .deleteConfirmed:
                guard let recordID = state.recordID, !state.isSaving else { return }
                let eventID = state.eventID
                state.showsDeleteConfirmation = false
                state.isSaving = true
                store.addTask {
                    do {
                        try await database.write { db in
                            try RelationshipRecordEditing.delete(recordID, eventID: eventID, in: db)
                        }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "This relationship could not be deleted."
                            $0.isSaving = false
                        }
                    }
                }

            case let .roleSelected(role):
                state.role = role.rawValue

            case .saveButtonTapped:
                guard let fields = state.preparedFields, !state.isSaving else { return }
                let eventID = state.eventID
                let recordID = state.recordID
                let createdAt = now
                state.isSaving = true
                store.addTask {
                    do {
                        try await database.write { db in
                            if let recordID {
                                try RelationshipRecordEditing.update(
                                    recordID, eventID: eventID, fields: fields, in: db
                                )
                            } else {
                                _ = try RelationshipRecordEditing.create(
                                    eventID: eventID, fields: fields, createdAt: createdAt, in: db
                                )
                            }
                        }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "This relationship could not be saved."
                            $0.isSaving = false
                        }
                    }
                }
            }
        }
    }

    private func search(query: String, exact: Bool, state: inout State) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            state.actorSearchSections = []
            state.actorSearchFailures = []
            state.actorSearchIsLoading = false
            return
        }
        state.actorSearchIsLoading = true
        store.addTask(id: actorSearchTask) {
            let response = await (exact ? Self.exactActorSearch : Self.typeaheadActorSearch)
                .search(query)
            try Task.checkCancellation()
            try store.send(.actorSearchResponse(response))
        }
    }

    private static let exactActorSearch = PredictiveSearch(
        actorIdentitySources: [.exactActorIdentityLookup(title: "Exact match")],
        minimumQueryLength: 2
    )

    private static let typeaheadActorSearch = PredictiveSearch(
        actorIdentitySources: [.appBskyActorTypeahead(title: "Profiles", limit: 10)],
        minimumQueryLength: 2
    )
}

public struct RelationshipFormView: View {
    @Bindable var store: StoreOf<RelationshipForm>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    public init(store: StoreOf<RelationshipForm>) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Subject") {
                Picker("Kind", selection: $store.subjectKind) {
                    Text("Account").tag(RelationshipForm.SubjectKind.account)
                    Text("Record").tag(RelationshipForm.SubjectKind.record)
                    if store.subjectKind == .unsupported {
                        Text("Unsupported").tag(RelationshipForm.SubjectKind.unsupported)
                    }
                }

                switch store.subjectKind {
                case .account:
                    if let identity = store.selectedIdentity {
                        LabeledContent("Selected account", value: identity.displayName ?? identity.handle ?? identity.did.description)
                        Button("Change Account") { store.send(.clearIdentityButtonTapped) }
                    }
                    TextField("Search profiles", text: $store.actorSearchQuery)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit { store.send(.actorSearchSubmitted) }
                        .onChange(of: store.actorSearchQuery) { _, query in
                            store.send(.actorSearchQueryChanged(query))
                        }
                    if store.actorSearchIsLoading { ProgressView() }
                    ForEach(store.actorSearchSections) { section in
                        ForEach(section.results) { identity in
                            Button {
                                store.send(.actorIdentityTapped(identity))
                            } label: {
                                ContributorActorIdentityRow(identity: identity, isSelected: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if store.actorSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                        Button(showsTechnicalDetails ? "Look up exact handle or DID" : "Look up exact account") {
                            store.send(.actorSearchSubmitted)
                        }
                        .disabled(store.actorSearchIsLoading)
                    }
                    ForEach(store.actorSearchFailures, id: \.sourceID) { failure in
                        Text(failure.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .record:
                    TextField("Record URI", text: $store.subjectRecordURI)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif

                case .unsupported:
                    Text("This subject type cannot be edited here.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Role") {
                TextField("Role", text: $store.role)
                    .autocorrectionDisabled()
                Menu("Common roles") {
                    Button("Collaborator") { store.send(.roleSelected(.collaborator)) }
                    Button("Organizer") { store.send(.roleSelected(.organizer)) }
                    Button("Performer") { store.send(.roleSelected(.performer)) }
                    Button("Sponsor") { store.send(.roleSelected(.sponsor)) }
                }
                if store.role.trimmingCharacters(in: .whitespacesAndNewlines) == OME.Relationship.Role.collaborator.rawValue {
                    Toggle("Can propose changes", isOn: $store.canPropose)
                    Toggle("Can merge changes", isOn: $store.canMerge)
                }
            }

            if store.recordID != nil {
                Section {
                    Button("Delete Relationship", role: .destructive) {
                        store.send(.deleteButtonTapped)
                    }
                }
            }

            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .disabled(store.isSaving)
        .navigationTitle(store.navigationTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { store.send(.cancelButtonTapped) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { store.send(.saveButtonTapped) }
                    .disabled(!store.canSubmit)
                    .accessibilityIdentifier("relationship.save")
            }
        }
        .confirmationDialog("Delete this relationship?", isPresented: $store.showsDeleteConfirmation) {
            Button("Delete Relationship", role: .destructive) {
                store.send(.deleteConfirmed)
            }
        }
        .accessibilityIdentifier("view.relationship-form.\(store.eventID.description)")
    }
}
