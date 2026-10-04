import ATProto
import ComposableArchitecture2
import Dependencies
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import SwiftUI

@Feature
public struct RelationshipList {
    public init() {}

    public struct State {
        public init(eventID: Event.ID) {
            self.eventID = eventID
            self._relationships = FetchAll(OME.Relationship.all)
        }

        public let eventID: Event.ID
        @FetchAll public var relationships: [OME.Relationship]
        public var destination: Destination.State?
        public var pendingDeletionID: ATProto.URI?
        public var errorMessage: String?

        public var eventRelationships: [OME.Relationship] {
            relationships.filter { relationship in
                guard relationship.id != nil,
                      case let .some(.known(.record(object))) = relationship.object
                else { return false }
                return object.uri == eventID
            }
            .sorted { ($0.id?.description ?? "") < ($1.id?.description ?? "") }
        }
    }

    public enum Action {
        case addButtonTapped
        case deleteButtonTapped(ATProto.URI)
        case deleteCancelled
        case deleteConfirmed
        case destination(Destination.Action)
        case editButtonTapped(ATProto.URI)
    }

    @Feature
    public enum Destination {
        case relationshipForm(RelationshipForm)
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addButtonTapped:
                state.destination = .relationshipForm(RelationshipForm.State(eventID: state.eventID))

            case let .deleteButtonTapped(id):
                state.pendingDeletionID = id

            case .deleteCancelled:
                state.pendingDeletionID = nil

            case .deleteConfirmed:
                guard let id = state.pendingDeletionID else { return }
                let eventID = state.eventID
                state.pendingDeletionID = nil
                store.addTask {
                    do {
                        try await database.write { db in
                            try RelationshipRecordEditing.delete(id, eventID: eventID, in: db)
                        }
                        try store.modify { $0.errorMessage = nil }
                    } catch {
                        try store.modify { $0.errorMessage = "This relationship could not be deleted." }
                    }
                }

            case .destination:
                break

            case let .editButtonTapped(id):
                guard let relationship = state.eventRelationships.first(where: { $0.id == id }) else { return }
                state.destination = .relationshipForm(
                    RelationshipForm.State(eventID: state.eventID, relationship: relationship)
                )
            }
        }
        .ifLet(\.destination) {
            Destination.body
        }
    }
}

public struct RelationshipListView: View {
    @Bindable var store: StoreOf<RelationshipList>

    public init(store: StoreOf<RelationshipList>) {
        self.store = store
    }

    public var body: some View {
        List {
            if store.eventRelationships.isEmpty {
                Section {
                    Text("No relationships have been added to this event yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Relationships") {
                    ForEach(store.eventRelationships, id: \.id) { relationship in
                        if let id = relationship.id {
                            HStack {
                                Button {
                                    store.send(.editButtonTapped(id))
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(subjectTitle(relationship))
                                            .foregroundStyle(.primary)
                                        Text(relationship.role.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("relationship.row.\(id.description)")

                                Menu {
                                    Button("Edit") { store.send(.editButtonTapped(id)) }
                                    Button("Delete", role: .destructive) {
                                        store.send(.deleteButtonTapped(id))
                                    }
                                } label: {
                                    Label("Relationship Actions", systemImage: "ellipsis.circle")
                                        .labelStyle(.iconOnly)
                                }
                                .accessibilityIdentifier("relationship.actions.\(id.description)")
                            }
                        }
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
        .navigationTitle("Relationships")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.send(.addButtonTapped)
                } label: {
                    Label("Add Relationship", systemImage: "plus")
                }
                .accessibilityIdentifier("relationship.add")
            }
        }
        .sheet(item: $store.scope(\.destination).relationshipForm) { formStore in
            NavigationStack { RelationshipFormView(store: formStore) }
        }
        .confirmationDialog(
            "Delete this relationship?",
            isPresented: Binding(
                get: { store.pendingDeletionID != nil },
                set: { if !$0 { store.send(.deleteCancelled) } }
            )
        ) {
            Button("Delete Relationship", role: .destructive) {
                store.send(.deleteConfirmed)
            }
            Button("Cancel", role: .cancel) {
                store.send(.deleteCancelled)
            }
        }
        .accessibilityIdentifier("view.relationships.\(store.eventID.description)")
    }

    private func subjectTitle(_ relationship: OME.Relationship) -> String {
        switch relationship.subject {
        case let .known(.identity(identity)):
            identity.displayName ?? identity.handle ?? identity.did.description
        case let .known(.record(record)):
            record.uri.description
        case .unknown:
            "Unknown subject"
        }
    }
}
