import ComposableArchitecture2
import ComposableWorkspace
import Foundation

enum WorkspaceProposalDraftDismissed: FeatureEventKey<Void> {}

/// Presentation-only input for the first proposal.
///
/// Publication progress is intentionally absent. `ComposableWorkspace.Workspace` owns capture,
/// push, proposal recording, reference advancement, failure, and retry state.
@Feature
public struct WorkspaceProposalDraft {
    public init() {}

    public struct State {
        public init(
            groups: [SourceChangeGroup],
            recordComparisons: SourceRecordComparisons
        ) {
            self.groups = groups
            self.recordComparisons = recordComparisons
        }

        public var description = ""
        public let groups: [SourceChangeGroup]
        public let recordComparisons: SourceRecordComparisons
        public var title = ""

        public var proposalTitle: WorkspaceProposalTitle? {
            WorkspaceProposalTitle(title)
        }
    }

    public enum Action {
        case cancelButtonTapped
        case createProposalButtonTapped
        case descriptionChanged(String)
        case titleChanged(String)
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask {
                    let task = try store.post(
                        key: WorkspaceProposalDraftDismissed.self,
                        value: ()
                    )
                    await task?.value
                }

            case .createProposalButtonTapped:
                guard let title = state.proposalTitle else { return }
                let details = WorkspaceProposalDetails(
                    title: title,
                    description: state.description
                )
                store.addTask {
                    let publication = try store.post(
                        key: WorkspaceProposalCreationRequested.self,
                        value: details
                    )
                    await publication?.value
                    let dismissal = try store.post(
                        key: WorkspaceProposalDraftDismissed.self,
                        value: ()
                    )
                    await dismissal?.value
                }

            case let .descriptionChanged(description):
                state.description = description

            case let .titleChanged(title):
                state.title = title
            }
        }
    }
}
