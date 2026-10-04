import ComposableArchitecture2
import Dependencies
import ErrorHandling
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SQLiteData
import SourceEditing
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct CanonicalEventWorkspace {
    public init() {}

    public struct State: Identifiable {
        public init(eventID: Event.ID, baseline: SourceBaselineDatabase) {
            self.eventID = eventID
            self.baseline = baseline
            self._changes = Fetch(
                wrappedValue: [],
                CanonicalChangesRequest(eventID: eventID, baseline: baseline)
            )
        }

        public let eventID: Event.ID
        public let baseline: SourceBaselineDatabase
        @DebugSnapshotIgnored
        @Fetch public var changes: [CanonicalWorkspaceRecordChange]
        public var isResetting = false
        public var destination: Destination.State?

        public var id: Event.ID { eventID }
        public var badgeCount: Int? { changes.isEmpty ? nil : changes.count }
    }

    public enum Action {
        case destination(Destination.Action)
        case relationshipsButtonTapped
        case resetChangesButtonTapped
    }

    @Feature
    public enum Destination {
        case relationshipList(RelationshipList)
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case .relationshipsButtonTapped:
                state.destination = .relationshipList(RelationshipList.State(eventID: state.eventID))

            case .resetChangesButtonTapped:
                guard !state.changes.isEmpty, !state.isResetting else { return }
                let eventID = state.eventID
                let baseline = state.baseline
                let changes = state.$changes
                let database = database
                state.isResetting = true
                store.addTask {
                    let result: Void? = await store.withErrorHandling(
                        fallbackMessage: .workspaceResetFailed,
                        operation: .workspaceReset
                    ) {
                        try CanonicalWorkspaceRecordChanges.reset(
                            eventID: eventID,
                            in: database,
                            referenceDatabase: baseline
                        )
                        try await changes.load()
                    } cleanup: {
                        $0.isResetting = false
                    }
                    guard result != nil else { return }
                    try store.modify { $0.isResetting = false }
                }
            }
        }
        .ifLet(\.destination) {
            Destination.body
        }
    }
}

private struct CanonicalChangesRequest: FetchKeyRequest {
    let eventID: Event.ID
    let baseline: SourceBaselineDatabase

    func fetch(_ db: Database) throws -> [CanonicalWorkspaceRecordChange] {
        try CanonicalWorkspaceRecordChanges.changes(
            eventID: eventID,
            in: db,
            referenceDatabase: baseline
        )
    }
}

public struct CanonicalEventWorkspaceView: View {
    @Bindable var store: StoreOf<CanonicalEventWorkspace>
    @State var isResetConfirmationPresented = false
    let onEditEventInfo: () -> Void

    public init(store: StoreOf<CanonicalEventWorkspace>, onEditEventInfo: @escaping () -> Void) {
        self.store = store
        self.onEditEventInfo = onEditEventInfo
    }

    public var body: some View {
        List {
            Section("Records") {
                Button("Event Info", action: onEditEventInfo)
                    .accessibilityIdentifier("workspace.record.event-info")
                Button("Relationships") {
                    store.send(.relationshipsButtonTapped)
                }
                .accessibilityIdentifier("workspace.record.relationships")
            }

            Section("Changes") {
                if store.changes.isEmpty {
                    Text("No local changes.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.changes, id: \.id) { change in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(changeTitle(change))
                            Text(change.id.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !store.changes.isEmpty || store.isResetting {
                Section("Reset") {
                    Button("Reset changes", role: .destructive) {
                        isResetConfirmationPresented = true
                    }
                    .disabled(store.isResetting)
                    .accessibilityIdentifier("workspace.changes.reset")
                    if store.isResetting {
                        ProgressView("Resetting changes")
                    }
                }
            }
        }
        .navigationTitle("Workspace")
        .navigationDestination(item: $store.scope(\.destination).relationshipList) { listStore in
            RelationshipListView(store: listStore)
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Reset workspace changes?", isPresented: $isResetConfirmationPresented) {
            Button("Reset", role: .destructive) {
                store.send(.resetChangesButtonTapped)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores this organizer’s records to the local reference copy.")
        }
    }

    private func changeTitle(_ change: CanonicalWorkspaceRecordChange) -> String {
        let action: String
        switch change.kind {
        case .added: action = "Added"
        case .edited: action = "Edited"
        case .deleted: action = "Deleted"
        }
        let recordType = change.collection.split(separator: ".").last.map(String.init)
            ?? change.collection
        return "\(action) \(recordType)"
    }
}

extension UserFacingText {
    static let workspaceResetFailed = Self(
        "Changes could not be reset.",
        fallback: "Changes could not be reset."
    )
}

extension ErrorOperation {
    static let workspaceReset = Self("workspace.reset")
}
