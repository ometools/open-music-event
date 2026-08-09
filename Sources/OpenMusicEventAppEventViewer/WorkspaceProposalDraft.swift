import ComposableArchitecture2
import ComposableForms
import ComposableWorkspace
import Foundation
import OpenMusicEventComponents
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

enum WorkspaceProposalDraftDismissed: FeatureEventKey<Void> {}

@Feature
public struct WorkspaceProposalDraft {
    public init() {}

    public struct FormValue: Equatable, Sendable {
        public init(title: String = "", description: String = "") {
            self.title = title
            self.description = description
        }

        public var description: String
        public var title: String

        public var trimmedDescription: String? {
            let value = description.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        public var trimmedTitle: String {
            title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public typealias FormFeature = ComposableForms.Form<FormValue>

    public struct State {
        public init(
            targetBranch: String,
            groups: [SourceChangeGroup],
            fieldComparisons: SourceFieldComparisons,
            recordComparisons: SourceRecordComparisons
        ) {
            self.targetBranch = targetBranch
            self.groups = groups
            self.fieldComparisons = fieldComparisons
            self.recordComparisons = recordComparisons
            self.form = FormFeature.State(value: FormValue())
        }

        public let fieldComparisons: SourceFieldComparisons
        public var form: FormFeature.State
        public let groups: [SourceChangeGroup]
        public let recordComparisons: SourceRecordComparisons
        public let targetBranch: String
    }

    public enum Action {
        case cancelButtonTapped
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case proposeButtonTapped
    }

    public var body: some Feature {
        Scope(\.form, action: \.form) {
            FormFeature()
                .onSubmit { value in
                    try store.send(.formSubmitted(value))
                }
        }
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

            case .form:
                break

            case let .formSubmitted(value):
                guard state.form.canSubmit,
                      let title = WorkspaceProposalTitle(value.trimmedTitle)
                else { return }
                let details = WorkspaceProposalDetails(
                    title: title,
                    description: value.trimmedDescription
                )
                store.addTask {
                    let publication = try store.post(
                        key: WorkspaceProposalCreationRequested.self,
                        value: details
                    )
                    await publication?.value
                }

            case .proposeButtonTapped:
                store.addTask {
                    try store.send(.form(.submittedForm))
                }
            }
        }
    }
}

enum WorkspaceProposalFormFieldID {
    static var title: AnyHashable { AnyHashable(\WorkspaceProposalDraft.FormValue.title) }
}

extension WorkspaceProposalDraft.FormFeature {
    init() {
        self.init {
            Self.Field(\.title) {
                Validation(error: "Enter a proposal title.") { value in
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
        }
    }
}

public struct WorkspaceProposalDraftView: View {
    @Bindable var store: StoreOf<WorkspaceProposalDraft>
    let workspacePhase: WorkspacePhase<SourcePatch>

    public init(
        store: StoreOf<WorkspaceProposalDraft>,
        workspacePhase: WorkspacePhase<SourcePatch>
    ) {
        self.store = store
        self.workspacePhase = workspacePhase
    }

    public var publicationIsActive: Bool {
        switch workspacePhase {
        case .capturingSubmission, .publishing:
            true
        case .inactive, .preparingSource, .publicationFailed,
             .publicationInterrupted, .ready, .reconciling,
             .reconciliationFailed, .sourcePreparationFailed, .stale,
             .submissionCaptureFailed:
            false
        }
    }

    public var publicationStage: String? {
        switch workspacePhase {
        case .capturingSubmission:
            "Preparing proposal"
        case let .publishing(submission):
            switch submission.step {
            case .pushCommit:
                "Saving changes to the proposal branch"
            case .recordProposal:
                "Recording the proposal"
            case .updateReference:
                "Finalizing the local reference"
            }
        case .inactive, .preparingSource, .publicationFailed,
             .publicationInterrupted, .ready, .reconciling,
             .reconciliationFailed, .sourcePreparationFailed, .stale,
             .submissionCaptureFailed:
            nil
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Proposal") {
                    TextField("Title", text: $store.form.value.title)
                        .accessibilityIdentifier("workspace.proposal.title")
                        .onSubmit {
                            store.send(.form(.fieldSubmitted(WorkspaceProposalFormFieldID.title)))
                        }

                    FormFieldValidationStatus(
                        validation: store.form.validation[WorkspaceProposalFormFieldID.title]
                    )

                    PortableTextField(
                        "Description (optional)",
                        text: $store.form.value.description,
                        axis: .vertical
                    )
                    .accessibilityIdentifier("workspace.proposal.description")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Proposes changes to")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(store.targetBranch)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if let publicationStage {
                    Section("Publication") {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(publicationStage)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("workspace.proposal.progress")
                    }
                }

                SourceChangeSummarySection(
                    groups: store.groups,
                    fieldComparisons: store.fieldComparisons,
                    recordComparisons: store.recordComparisons,
                    emptyMessage: "No changes are waiting to be proposed."
                )
            }
            .disabled(publicationIsActive)
            .navigationTitle("Create Proposal")
            .interactiveDismissDisabled(publicationIsActive)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.send(.cancelButtonTapped) }
                        .disabled(publicationIsActive)
                        .accessibilityIdentifier("workspace.proposal.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    SubmitButton(
                        .propose,
                        isInProgress: publicationIsActive,
                        isDisabled: publicationIsActive || !store.form.canSubmit
                    ) {
                        store.send(.proposeButtonTapped)
                    }
                    .accessibilityIdentifier("workspace.proposal.submit")
                }
            }
        }
    }
}
