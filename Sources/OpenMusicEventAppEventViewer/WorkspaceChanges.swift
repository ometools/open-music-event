import ComposableArchitecture2
import ComposableAuthoring
import ComposableWorkspace
import Dependencies
import ErrorHandling
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

    public enum ResetStatus: Equatable, Sendable {
        case idle
        case resetting
    }

    public struct State {
        public init(
            workspace: SourceWorkspace,
            referenceDatabase: SourceBaselineDatabase? = nil
        ) {
            self.workspace = workspace
            self._summary = Fetch(
                wrappedValue: SourceWorkspaceEditSummary(
                    workspaceID: workspace.id,
                    availability: .workspaceNeedsPreparation,
                    groups: []
                ),
                SourceWorkspaceEditSummaryRequest(
                    workspace: workspace,
                    referenceDatabase: referenceDatabase
                )
            )
            self._openProposal = Fetch(
                wrappedValue: nil,
                SourceWorkspaceOpenProposalRequest(workspaceID: workspace.id)
            )
        }

        public let workspace: SourceWorkspace
        @DebugSnapshotIgnored
        @Fetch public var summary: SourceWorkspaceEditSummary
        @DebugSnapshotIgnored
        @Fetch public var openProposal: WorkspaceProposal?
        public var proposalDraft: WorkspaceProposalDraft.State?
        public var resetStatus: ResetStatus = .idle

        public var changeCount: Int {
            guard case .available = summary.availability else { return 0 }
            return summary.groups.reduce(0) { $0 + $1.totalCount }
        }

        public var badgeCount: Int? { changeCount == 0 ? nil : changeCount }

        public var canInspectChanges: Bool {
            guard case .available = summary.availability else { return false }
            return true
        }

        public var canResetChanges: Bool {
            canInspectChanges && changeCount > 0 && resetStatus != .resetting
        }
    }

    public enum Action {
        case proposalActionButtonTapped
        case proposalDraft(WorkspaceProposalDraft.Action)
        case resetChangesButtonTapped
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.eventWorkspaceResetter) var workspaceResetter
    @FeatureEnvironment(ComposableAuthoring.AuthoringContext<AuthoringGrant>.self)
    var authoring
    @FeatureEnvironment(WorkspaceContext<SourceWorkspaceResource, SourcePatch>.self)
    var workspace

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .proposalActionButtonTapped:
                guard authoring.grant.wrappedValue?.access.canPropose == true,
                      state.changeCount > 0
                else { return }
                if state.openProposal == nil {
                    state.proposalDraft = WorkspaceProposalDraft.State(
                        targetBranch: state.workspace.branch,
                        groups: state.summary.groups,
                        fieldComparisons: state.summary.fieldComparisons,
                        recordComparisons: state.summary.recordComparisons
                    )
                } else {
                    store.addTask {
                        let task = try store.post(
                            key: WorkspaceProposalUpdateRequested.self,
                            value: ()
                        )
                        await task?.value
                    }
                }

            case .resetChangesButtonTapped:
                guard state.canResetChanges else { return }
                let workspace = state.workspace
                let referenceDatabase = self.workspace.source.wrappedValue?.referenceDatabase
                let workspaceResetter = workspaceResetter
                state.resetStatus = .resetting
                store.addTask {
                    let result: Void? = await store.withErrorHandling(
                        fallbackMessage: .workspaceResetFailed,
                        operation: .workspaceReset
                    ) {
                        guard let referenceDatabase else {
                            throw EventWorkspaceResetError.workspaceNeedsPreparation(workspace.id)
                        }
                        try workspaceResetter.resetWorkspace(workspace, referenceDatabase)
                    } cleanup: {
                        $0.resetStatus = .idle
                    }
                    guard result != nil else { return }
                    try store.modify {
                        $0.resetStatus = .idle
                        $0.proposalDraft = nil
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
            state.proposalDraft = nil
        }
    }
}

private struct SourceWorkspaceEditSummaryRequest: FetchKeyRequest {
    var workspace: SourceWorkspace
    var referenceDatabase: SourceBaselineDatabase?

    func fetch(_ db: Database) throws -> SourceWorkspaceEditSummary {
        try SourceWorkspaceEditSummary.query(
            workspace: workspace,
            in: db,
            referenceDatabase: referenceDatabase
        )
    }
}

public struct WorkspaceChangesView: View {
    @Bindable var store: StoreOf<WorkspaceChanges>
    let workspacePhase: WorkspacePhase<SourcePatch>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    @State var isResetConfirmationPresented = false

    public init(
        store: StoreOf<WorkspaceChanges>,
        workspacePhase: WorkspacePhase<SourcePatch>
    ) {
        self.store = store
        self.workspacePhase = workspacePhase
    }

    public var body: some View {
        Group {
            switch store.summary.availability {
            case .available:
                SourceChangeSummarySection(
                    groups: store.summary.groups,
                    fieldComparisons: store.summary.fieldComparisons,
                    recordComparisons: store.summary.recordComparisons,
                    emptyMessage: workspacePhase.proposal == nil
                        ? "No local changes."
                        : "No newer changes are waiting to be added to this proposal."
                )

            case .workspaceNeedsPreparation:
                Section("What changed") {
                    if case .preparingSource = workspacePhase {
                        HStack(spacing: 10) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Preparing workspace")
                                Text("Your changes will appear here when the source is ready.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Workspace source unavailable")
                        Text("Your changes will appear here when the source is ready.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

            case let .unavailable(reason):
                Section("What changed") {
                    Text("Changes couldn’t be compared")
                    Text("The workspace source does not match the app’s data model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if showsTechnicalDetails {
                        Text(String(describing: reason))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospaced()
                    }
                }
            }

            if store.canResetChanges || store.resetStatus != .idle {
                Section("Reset") {
                    Button("Reset changes", role: .destructive) {
                        isResetConfirmationPresented = true
                    }
                    .disabled(!store.canResetChanges)
                    .accessibilityIdentifier("workspace.changes.reset")

                    switch store.resetStatus {
                    case .resetting:
                        ProgressView("Resetting changes")
                    case .idle:
                        EmptyView()
                    }
                }
            }
        }
        .sheet(item: $store.scope(\.proposalDraft, action: \.proposalDraft)) { draftStore in
            WorkspaceProposalDraftView(
                store: draftStore,
                workspacePhase: workspacePhase
            )
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

extension UserFacingText {
    static let workspaceResetFailed = Self(
        "Changes could not be reset.",
        fallback: "Changes could not be reset."
    )
}

extension ErrorOperation {
    static let workspaceReset = Self("workspace.reset")
}
