import ComposableArchitecture2
import Dependencies
import ErrorHandling
import OpenMusicEventDatabase
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
        case publishRecordsButtonTapped
        case resetChangesButtonTapped
    }

    @Feature
    public enum Destination {
        case recordPublishing(EventRecordPublishing)
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case .publishRecordsButtonTapped:
                state.destination = .recordPublishing(EventRecordPublishing.State(
                    eventID: state.eventID, baseline: state.baseline
                ))

            case .resetChangesButtonTapped:
                guard !state.changes.isEmpty, !state.isResetting else { return }
                let eventID = state.eventID
                let baseline = state.baseline
                let changes = state.$changes
                let changeIDs = Set(state.changes.map(\.id))
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
                            referenceDatabase: baseline,
                            recordIDs: changeIDs
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

struct CanonicalChangesRequest: FetchKeyRequest {
    let eventID: Event.ID
    let baseline: SourceBaselineDatabase?

    func fetch(_ db: Database) throws -> [CanonicalWorkspaceRecordChange] {
        var changes = try baseline.map {
            try CanonicalWorkspaceRecordChanges.changes(eventID: eventID, in: db, referenceDatabase: $0)
        } ?? []
        let identities = try CanonicalSourceEventIdentity.all.fetchAll(db)
        let source = identities.first { $0.id == eventID }
        let locallyCreated = try LocallyCreatedEvent.find(eventID).fetchOne(db) != nil
        let eventIDs = Set(identities.filter {
            $0.source == source?.source && $0.publisher == source?.publisher
        }.map(\.id))
        let receipts = try EventRecordPublicationReceipt.all.fetchAll(db)
        if source != nil || locallyCreated || baseline == nil {
            let events = try Event.all.fetchAll(db).filter {
                source == nil ? $0.id == eventID : eventIDs.contains($0.id)
            }
            changes.removeAll { $0.collection == Event.tableName && $0.kind != .deleted }
            changes += try events.compactMap { event in
                try CanonicalWorkspaceRecordChange.event(event, receipt: receipts.first { $0.id == event.id })
            }
        }
        if source != nil || locallyCreated {
            changes.removeAll {
                $0.collection == Event.tableName && (source == nil ? $0.id != eventID : !eventIDs.contains($0.id))
            }
        }
        return changes.sorted { $0.id.description < $1.id.description }
    }
}

public struct CanonicalEventWorkspaceView: View {
    @Bindable var store: StoreOf<CanonicalEventWorkspace>
    @State var isResetConfirmationPresented = false
    public init(store: StoreOf<CanonicalEventWorkspace>) {
        self.store = store
    }

    public var body: some View {
        List {
            Section {
                Text("Edit content in the app, then review your changes here before publishing.")
                    .foregroundStyle(.secondary)
                Button("Publish Changes") {
                    store.send(.publishRecordsButtonTapped)
                }
                .disabled(!store.changes.contains(where: \.canPublish) || store.isResetting)
                .accessibilityIdentifier("workspace.publish")
            }
            WorkspaceChangeSummarySection(
                changes: store.changes.filter(\.canPublish),
                emptyMessage: store.changes.isEmpty ? "No local changes." : "No event changes to publish."
            )
            let deferred = store.changes.filter { !$0.canPublish }
            if !deferred.isEmpty {
                Section {
                    Text("Publishing currently supports event details and images. These other changes stay on this device; they will not be included.")
                }
                WorkspaceChangeSummarySection(changes: deferred, title: "Not included in publication")
            }
            if let error = store.$changes.loadError {
                Section("Changes could not be loaded") { Text(error.localizedDescription) }
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
        .sheet(item: $store.scope(\.destination).recordPublishing) { publishingStore in
            NavigationStack { EventRecordPublishingView(store: publishingStore) }
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
            Text("This restores published content to its last verified version, and unpublished content to its starting version. Your published content is not deleted.")
        }
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
