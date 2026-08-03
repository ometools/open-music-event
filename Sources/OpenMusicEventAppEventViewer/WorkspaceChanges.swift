import ComposableArchitecture2
import ComposableAuthoring
import ComposableWorkspace
import Dependencies
import Foundation
import OpenMusicEventSourceEditing
import SQLiteData
import SourceEditing
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct WorkspaceChanges {
    public init() {}

    public enum PatchStatus: Equatable, Sendable {
        case failed(String)
        case generated(SourcePatch)
        case generating
        case needsGeneration
        case notGenerated
    }

    public enum ResetStatus: Equatable, Sendable {
        case failed(String)
        case idle
        case resetting
    }

    public struct State {
        public init(workspace: SourceWorkspace) {
            self.workspace = workspace
            self._summary = Fetch(
                wrappedValue: SourceWorkspaceEditSummary(
                    workspaceID: workspace.id,
                    availability: .workspaceNeedsPreparation,
                    groups: []
                ),
                SourceWorkspaceEditSummaryRequest(workspace: workspace)
            )
        }

        public let workspace: SourceWorkspace
        @DebugSnapshotIgnored
        @Fetch public var summary: SourceWorkspaceEditSummary
        public var patchStatus: PatchStatus = .notGenerated
        public var proposalDraft: WorkspaceProposalDraft.State?
        public var resetStatus: ResetStatus = .idle

        public var changeCount: Int {
            guard case .available = summary.availability else { return 0 }
            return summary.groups.reduce(0) { $0 + $1.totalCount }
        }

        public var badgeCount: Int? { changeCount == 0 ? nil : changeCount }

        public var canInspectChanges: Bool {
            guard case .available = summary.availability,
                  patchStatus != .generating
            else { return false }
            return true
        }

        public var canResetChanges: Bool {
            canInspectChanges && changeCount > 0 && resetStatus != .resetting
        }
    }

    public enum Action {
        case checkChangesButtonTapped
        case proposalActionButtonTapped
        case proposalDraft(WorkspaceProposalDraft.Action)
        case resetChangesButtonTapped
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.eventWorkspaceResetter) var workspaceResetter
    @Dependency(SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self)
    var patchGenerator
    @FeatureEnvironment(ComposableAuthoring.AuthoringContext<AuthoringGrant>.self)
    var authoring
    @FeatureEnvironment(WorkspaceContext<SourceWorkspaceResource, SourcePatch>.self)
    var workspaceContext

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .checkChangesButtonTapped:
                guard state.canInspectChanges else { return }
                let request = SourceWorkspacePatchRequest(workspace: state.workspace)
                let patchGenerator = patchGenerator
                state.patchStatus = .generating
                store.addTask {
                    do {
                        let patch = try await patchGenerator.generate(request)
                        try store.modify { $0.patchStatus = .generated(patch) }
                    } catch {
                        try store.modify { $0.patchStatus = .failed(String(describing: error)) }
                    }
                }

            case .proposalActionButtonTapped:
                guard authoring.grant.wrappedValue?.access.canPropose == true,
                      state.changeCount > 0
                else { return }
                switch workspaceContext.phase.wrappedValue {
                case .ready(.canonical):
                    state.proposalDraft = WorkspaceProposalDraft.State(
                        groups: state.summary.groups,
                        recordComparisons: state.summary.recordComparisons
                    )

                case .ready(.proposal):
                    store.addTask {
                        let task = try store.post(
                            key: WorkspaceProposalUpdateRequested.self,
                            value: ()
                        )
                        await task?.value
                    }

                case .publicationFailed, .publicationInterrupted:
                    store.addTask {
                        let task = try store.post(
                            key: WorkspacePublicationRetryRequested.self,
                            value: ()
                        )
                        await task?.value
                    }

                case .reconciliationFailed, .stale:
                    store.addTask {
                        let task = try store.post(
                            key: WorkspaceReconciliationRequested.self,
                            value: ()
                        )
                        await task?.value
                    }

                case .capturingSubmission, .inactive, .preparingSource, .publishing,
                     .reconciling, .sourcePreparationFailed, .submissionCaptureFailed:
                    break
                }

            case .resetChangesButtonTapped:
                guard state.canResetChanges else { return }
                let workspace = state.workspace
                let workspaceResetter = workspaceResetter
                state.resetStatus = .resetting
                store.addTask {
                    do {
                        try workspaceResetter.resetWorkspace(workspace)
                        try store.modify {
                            $0.resetStatus = .idle
                            $0.patchStatus = .needsGeneration
                            $0.proposalDraft = nil
                        }
                    } catch {
                        try store.modify { $0.resetStatus = .failed(String(describing: error)) }
                    }
                }

            case .proposalDraft:
                break
            }
        }
        .ifLet(\.proposalDraft, action: \.proposalDraft) {
            WorkspaceProposalDraft()
        }
        .onEvent(WorkspaceProposalDraftDismissed.self) { _, state in
            state.proposalDraft = nil
            return .continue
        }
        .onEvent(AuthoringAccessRevoked.self) { _, state in
            state.proposalDraft = nil
            return .continue
        }
        .onChange(of: store.summary) { oldSummary, summary, state in
            guard oldSummary != summary else { return }
            switch state.patchStatus {
            case .generated, .generating:
                state.patchStatus = .needsGeneration
            case .failed, .needsGeneration, .notGenerated:
                break
            }
            state.proposalDraft = nil
        }
    }
}

private struct SourceWorkspaceEditSummaryRequest: FetchKeyRequest {
    var workspace: SourceWorkspace

    func fetch(_ db: Database) throws -> SourceWorkspaceEditSummary {
        try SourceWorkspaceEditSummary.query(workspace: workspace, in: db)
    }
}

public struct WorkspaceChangesView: View {
    @Bindable var store: StoreOf<WorkspaceChanges>
    @Environment(\.openMusicEventWorkspacePhase) var phase
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    @State var isResetConfirmationPresented = false

    public init(store: StoreOf<WorkspaceChanges>) {
        self.store = store
    }

    public var body: some View {
        List {
            SourceChangeSummarySection(
                groups: store.summary.groups,
                recordComparisons: store.summary.recordComparisons
            )

            Section("Workspace") {
                WorkspacePublicationStatusView(phase: phase)

                if store.changeCount == 0 {
                    Text("No local changes")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Check changes") {
                        store.send(.checkChangesButtonTapped)
                    }
                    .disabled(!store.canInspectChanges)

                    Button(phase.proposalActionTitle) {
                        store.send(.proposalActionButtonTapped)
                    }
                    .disabled(!phase.canRequestProposalAction)
                }

                switch store.patchStatus {
                case .generating:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Checking source changes")
                    }
                case let .failed(message):
                    if showsTechnicalDetails {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Changes could not be prepared")
                            .foregroundStyle(.secondary)
                    }
                case let .generated(patch) where patch.isEmpty:
                    Text("No source patch is needed")
                        .foregroundStyle(.secondary)
                case .generated, .needsGeneration, .notGenerated:
                    EmptyView()
                }
            }

            if store.canResetChanges || store.resetStatus != .idle {
                Section {
                    Button("Reset source changes", role: .destructive) {
                        isResetConfirmationPresented = true
                    }
                    .disabled(!store.canResetChanges)

                    switch store.resetStatus {
                    case .resetting:
                        ProgressView("Resetting source changes")
                    case let .failed(message):
                        Text(showsTechnicalDetails ? message : "Source changes could not be reset")
                            .foregroundStyle(.secondary)
                    case .idle:
                        EmptyView()
                    }
                }
            }
        }
        .sheet(item: $store.scope(\.proposalDraft, action: \.proposalDraft)) { draftStore in
            WorkspaceProposalDraftView(store: draftStore)
        }
        .alert("Reset all source changes?", isPresented: $isResetConfirmationPresented) {
            Button("Reset", role: .destructive) {
                store.send(.resetChangesButtonTapped)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores every record owned by this organization source to its reference copy.")
        }
    }
}

extension WorkspacePhase where ChangeSet == SourcePatch {
    var proposalActionTitle: String {
        switch self {
        case .ready(.canonical): "Create proposal"
        case .ready(.proposal): "Update proposal"
        case .publicationFailed, .publicationInterrupted: "Retry publication"
        case .reconciliationFailed, .stale: "Reconcile source"
        case .capturingSubmission, .inactive, .preparingSource, .publishing,
             .reconciling, .sourcePreparationFailed, .submissionCaptureFailed:
            "Working"
        }
    }

    var canRequestProposalAction: Bool {
        switch self {
        case .ready, .publicationFailed, .publicationInterrupted,
             .reconciliationFailed, .stale:
            true
        case .capturingSubmission, .inactive, .preparingSource, .publishing,
             .reconciling, .sourcePreparationFailed, .submissionCaptureFailed:
            false
        }
    }
}
