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

    public enum PublicationProgress: Equatable, Sendable {
        case idle
        case preparing
        case publishing
        case failed(String)

        public var isActive: Bool {
            switch self {
            case .preparing, .publishing: true
            case .idle, .failed: false
            }
        }
    }

    public enum PublicationMethod: Equatable, Sendable {
        case proposal
        case published
    }

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
            canPropose: Bool,
            canPublish: Bool,
            groups: [SourceChangeGroup],
            fieldComparisons: SourceFieldComparisons,
            recordComparisons: SourceRecordComparisons
        ) {
            self.targetBranch = targetBranch
            self.canPropose = canPropose
            self.canPublish = canPublish
            self.groups = groups
            self.fieldComparisons = fieldComparisons
            self.recordComparisons = recordComparisons
            self.form = FormFeature.State(value: FormValue())
        }

        public let fieldComparisons: SourceFieldComparisons
        public let canPropose: Bool
        public let canPublish: Bool
        public var form: FormFeature.State
        public let groups: [SourceChangeGroup]
        public var publicationProgress: PublicationProgress = .idle
        public var publicationMethod: PublicationMethod?
        public let recordComparisons: SourceRecordComparisons
        public let targetBranch: String
    }

    public enum Action {
        case cancelButtonTapped
        case form(FormFeature.Action)
        case formSubmitted(FormValue, PublicationMethod)
        case publishNowButtonTapped
        case proposeButtonTapped
    }

    public var body: some Feature {
        Scope(\.form) {
            FormFeature()
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

            case let .formSubmitted(value, method):
                guard state.form.canSubmit,
                      let title = WorkspaceProposalTitle(value.trimmedTitle),
                      !state.publicationProgress.isActive
                else { return }
                guard method == .proposal ? state.canPropose : state.canPublish else { return }
                state.publicationProgress = .preparing
                state.publicationMethod = method
                store.addTask {
                    switch method {
                    case .proposal:
                        let publication = try store.post(
                            key: WorkspaceProposalCreationRequested.self,
                            value: WorkspaceProposalDetails(
                                title: title,
                                description: value.trimmedDescription
                            )
                        )
                        await publication?.value
                    case .published:
                        let publication = try store.post(
                            key: WorkspaceChangesPublicationRequested.self,
                            value: WorkspacePublicationDetails(
                                title: title,
                                description: value.trimmedDescription
                            )
                        )
                        await publication?.value
                    }
                }

            case .proposeButtonTapped:
                let value = state.form.value
                store.addTask {
                    let validation = try store.send(.form(.submittedForm))
                    await validation?.value
                    let submission = try store.send(.formSubmitted(value, .proposal))
                    await submission?.value
                }

            case .publishNowButtonTapped:
                let value = state.form.value
                store.addTask {
                    let validation = try store.send(.form(.submittedForm))
                    await validation?.value
                    let submission = try store.send(.formSubmitted(value, .published))
                    await submission?.value
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
                Validation(error: "Enter a publication title.") { value in
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
        }
    }
}

public struct WorkspaceProposalDraftView: View {
    @Bindable var store: StoreOf<WorkspaceProposalDraft>

    public init(store: StoreOf<WorkspaceProposalDraft>) {
        self.store = store
    }

    @State var isPublishConfirmationPresented = false

    public var publicationIsActive: Bool {
        store.publicationProgress.isActive
    }

    public var publicationStage: String? {
        switch store.publicationProgress {
        case .preparing:
            "Preparing changes"
        case .publishing:
            store.publicationMethod == .published
                ? "Publishing changes"
                : "Publishing proposal"
        case .idle, .failed:
            nil
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Publication") {
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
                        Text("Publishes changes to")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(store.targetBranch)
                            .font(.body.monospaced())
                            .selectableText()
                    }
                }

                if let publicationStage {
                    Section("Publication") {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(publicationStage)
                        }
                        .portableAccessibilityElement()
                        .accessibilityIdentifier("workspace.proposal.progress")
                    }
                }

                if case let .failed(message) = store.publicationProgress {
                    Section("Changes not published") {
                        Text("Your changes and publication details are still here. You can try again.")
                        if !message.isEmpty {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospaced()
                        }
                    }
                }

                SourceChangeSummarySection(
                    groups: store.groups,
                    fieldComparisons: store.fieldComparisons,
                    recordComparisons: store.recordComparisons,
                    emptyMessage: "No changes are waiting to be published."
                )
            }
            .disabled(publicationIsActive)
            .navigationTitle("Publish Changes")
            .interactiveDismissDisabled(publicationIsActive)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.send(.cancelButtonTapped) }
                        .disabled(publicationIsActive)
                        .accessibilityIdentifier("workspace.proposal.cancel")
                }
                if store.canPropose {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Propose") {
                            store.send(.proposeButtonTapped)
                        }
                        .disabled(publicationIsActive || !store.form.canSubmit)
                        .accessibilityIdentifier("workspace.proposal.submit")
                    }
                }
                if store.canPublish {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Publish Now") {
                            isPublishConfirmationPresented = true
                        }
                        .disabled(publicationIsActive || !store.form.canSubmit)
                        .accessibilityIdentifier("workspace.publish.submit")
                    }
                }
            }
            .confirmationDialog(
                "Publish directly to \(store.targetBranch)?",
                isPresented: $isPublishConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Publish Now") {
                    store.send(.publishNowButtonTapped)
                }
            } message: {
                Text("This merges these changes immediately without creating a proposal.")
            }
        }
    }
}
