import ComposableArchitecture2
import ComposableWorkspace
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventComponents
import OpenMusicEventSourceEditing
import Sharing
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
        }

        public let workspace: SourceWorkspace
        @SharedReader(.defaultAuthoringGrant)
        public var authoringGrant: AuthoringGrant?
        @DebugSnapshotIgnored
        @Fetch public var summary: SourceWorkspaceEditSummary
        public var proposalDraft: WorkspaceProposalDraft.State?
        public var resetStatus: ResetStatus = .idle

        public var changeCount: Int {
            guard case .available = summary.availability else { return 0 }
            return summary.groups.reduce(0) { $0 + $1.totalCount }
        }

        public var badgeCount: Int? { changeCount == 0 ? nil : changeCount }

        public var authoringAccess: AuthoringAccess {
            guard authoringGrant?.workspaceID == workspace.id else { return .attendee }
            return authoringGrant?.access ?? .attendee
        }

        public var canInspectChanges: Bool {
            guard case .available = summary.availability else { return false }
            return true
        }

        public var canPropose: Bool {
            authoringAccess.canPropose
        }

        public var canPublish: Bool {
            // Direct publication is intentionally available anywhere proposal publication is.
            // This can narrow to merge-capable collaborators without changing form state.
            authoringAccess.canPropose
        }

        public var canResetChanges: Bool {
            authoringAccess.canEditContent
                && canInspectChanges
                && changeCount > 0
                && resetStatus != .resetting
        }
    }

    public enum Action {
        case discardConflictingChangesButtonTapped
        case proposalActionButtonTapped
        case proposalDraft(WorkspaceProposalDraft.Action)
        case resetChangesButtonTapped
    }

    @Dependency(\.eventWorkspaceResetter) var workspaceResetter
    @FeatureEnvironment(WorkspaceContext<SourceWorkspaceResource>.self)
    var workspace

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .discardConflictingChangesButtonTapped:
                guard case .conflicted = workspace.state.wrappedValue.reconciliation else {
                    return
                }
                store.addTask {
                    let discard = try store.post(
                        key: WorkspaceConflictingChangesDiscardRequested.self,
                        value: ()
                    )
                    await discard?.value
                }

            case .proposalActionButtonTapped:
                guard state.canPropose || state.canPublish,
                      state.changeCount > 0,
                      let session = workspace.session,
                      case .current = workspace.state.wrappedValue.reconciliation
                else { return }
                if session.baseline.branch.rawValue == state.workspace.defaultBranch {
                    state.proposalDraft = WorkspaceProposalDraft.State(
                        targetBranch: session.baseline.branch.rawValue,
                        canPropose: state.canPropose,
                        canPublish: state.canPublish,
                        groups: state.summary.groups,
                        fieldComparisons: state.summary.fieldComparisons,
                        recordComparisons: state.summary.recordComparisons
                    )
                }

            case .resetChangesButtonTapped:
                guard state.canResetChanges else { return }
                let workspace = state.workspace
                let referenceDatabase = self.workspace.session?.source.referenceDatabase
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
        .ifLet(\.proposalDraft) {
            WorkspaceProposalDraft()
        }
        .onEvent(WorkspaceProposalDraftDismissed.self) { _, state in
            state.proposalDraft = nil
            return .continue
        }
        .onChange(of: store.summary) { oldSummary, summary, state in
            guard oldSummary != summary else { return }
            guard state.proposalDraft?.publicationProgress.isActive != true else { return }
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
    let workspaceState: WorkspaceState<SourceWorkspaceResource>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    @State var isDiscardConfirmationPresented = false
    @State var isResetConfirmationPresented = false

    public init(
        store: StoreOf<WorkspaceChanges>,
        workspaceState: WorkspaceState<SourceWorkspaceResource>
    ) {
        self.store = store
        self.workspaceState = workspaceState
    }

    public var body: some View {
        Group {
            switch store.summary.availability {
            case .available:
                SourceChangePresentationSection(
                    presentation: store.summary.presentation,
                    emptyMessage: "No local changes.",
                    title: "Changes",
                    badgeCount: store.badgeCount
                )

            case .workspaceNeedsPreparation:
                Section("Changes") {
                    if case .preparing = workspaceState.availability {
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
                Section("Changes") {
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

            switch workspaceState.reconciliation {
            case .current:
                proposalActionSection

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

            case .reconciling:
                Section {
                    ProgressView("Checking for published changes")
                }

            case let .conflicted(conflict):
                Section("Update Required") {
                    Text(
                        "New published changes overlap with your workspace edits. Your edits are safe, but publishing is paused."
                    )
                    if showsTechnicalDetails {
                        ForEach(conflict.conflictingPaths, id: \.rawValue) { path in
                            Text(verbatim: path.rawValue)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Discard My Changes and Update", role: .destructive) {
                        isDiscardConfirmationPresented = true
                    }
                    .accessibilityIdentifier("workspace.reconciliation.discard")
                }
            }
        }
        .alert("Reset workspace changes?", isPresented: $isResetConfirmationPresented) {
            Button("Reset", role: .destructive) {
                store.send(.resetChangesButtonTapped)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This restores every source record to its reference copy and clears local proposal publication recovery. Remote proposals are not deleted."
            )
        }
        .alert(
            "Discard my changes and update?",
            isPresented: $isDiscardConfirmationPresented
        ) {
            Button("Discard My Changes", role: .destructive) {
                store.send(.discardConflictingChangesButtonTapped)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This discards every unpublished workspace change and installs the latest published branch. Remote proposals are not deleted."
            )
        }
    }

    @ViewBuilder
    var proposalActionSection: some View {
        if case .available = store.summary.availability,
           store.changeCount > 0,
           let baseline = workspaceState.baseline
        {
            if baseline.branch.rawValue == store.workspace.defaultBranch {
                Section("Publish") {
                    if store.canPropose || store.canPublish {
                        Button {
                            store.send(.proposalActionButtonTapped)
                        } label: {
                            Label("Publish Changes", mappedSystemImage: "arrow.triangle.pull")
                        }
                        .foregroundStyle(.primary)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("workspace.publication.create")
                    } else {
                        Text("You do not have permission to publish these changes.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("Proposal") {
                    Text("Go to main before publishing these changes.")
                        .foregroundStyle(.secondary)
                }
            }
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
