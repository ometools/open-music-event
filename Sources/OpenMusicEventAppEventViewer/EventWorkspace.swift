import ComposableArchitecture2
import ComposableWorkspace
import Foundation
import GRDB
import OpenMusicEventComponents
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
import SourceEditing
import SwiftUITabFeatures
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

/// The application-facing details for the one organization source owned by Workspace.
/// `eventID` is only a viewer focus; changes, proposals, and context selection remain source-scoped.
@Feature
public struct EventWorkspace {
    public init() {}

    public struct State: Identifiable {
        public init(
            workspace: SourceWorkspace,
            eventID: OME.Event.ID,
            workspaceState: SharedReader<WorkspaceState<SourceWorkspaceResource>>,
            referenceDatabase: SourceBaselineDatabase? = nil
        ) {
            self.workspace = workspace
            self.eventID = eventID
            self._workspaceState = workspaceState
            self._pendingProposalRepair = Fetch(
                wrappedValue: nil,
                SourceWorkspaceProposalRepairRequest(workspaceID: workspace.id)
            )
            self.changes = WorkspaceChanges.State(
                workspace: workspace,
                referenceDatabase: referenceDatabase
            )
        }

        public let workspace: SourceWorkspace
        public let eventID: OME.Event.ID
        @SharedReader(.defaultAuthoringGrant)
        public var authoringGrant: AuthoringGrant?
        @SharedReader public var workspaceState: WorkspaceState<SourceWorkspaceResource>
        @DebugSnapshotIgnored
        @Fetch public var pendingProposalRepair: SourceWorkspaceProposalRepair?
        public var id: SourceWorkspace.ID { workspace.id }
        public var changes: WorkspaceChanges.State
        public var collaborators: WorkspaceCollaborators.State?
        public var reviews: WorkspaceReviews.State?
        public var requestedBranch = ""
        @StoreTaskID public var contextSelection

        public var changeCount: Int? { changes.badgeCount }

        public var workspaceIsReady: Bool {
            workspaceState.session != nil
        }

        public var selectedContext: WorkspaceEditingContext? {
            workspaceState.selectedContext
        }

        public var authoringAccess: AuthoringAccess {
            guard authoringGrant?.workspaceID == workspace.id else { return .attendee }
            return authoringGrant?.access ?? .attendee
        }

        mutating func updateAuthoringGrant(_ grant: AuthoringGrant?) {
            let scopedGrant = grant?.workspaceID == workspace.id ? grant : nil
            if var reviews {
                reviews.authoringGrant = scopedGrant
                if case var .reviewDetail(detail)? = reviews.destination {
                    detail.authoringGrant = scopedGrant
                    reviews.destination = .reviewDetail(detail)
                }
                self.reviews = reviews
            }

            guard scopedGrant != nil else {
                collaborators = nil
                changes.proposalDraft = nil
                return
            }
            if collaborators?.workspaceID != workspace.id {
                collaborators = WorkspaceCollaborators.State(
                    workspace: workspace
                )
            }
        }

        mutating func openProposalList(_ proposal: WorkspaceProposal? = nil) {
            let scopedGrant = authoringGrant?.workspaceID == workspace.id
                ? authoringGrant
                : nil
            var reviews = reviews ?? WorkspaceReviews.State(
                workspace: workspace,
                authoringGrant: scopedGrant
            )
            if let proposal {
                reviews.open(proposal)
            }
            self.reviews = reviews
        }
    }

    public enum Action {
        case changes(WorkspaceChanges.Action)
        case collaborators(WorkspaceCollaborators.Action)
        case switchToMainButtonTapped
        case reviews(WorkspaceReviews.Action)
        case proposalsRowTapped
        case sourcePreparationRetryButtonTapped
        case switchBranchButtonTapped
        case viewProposalButtonTapped
    }

    public var body: some Feature {
        Features {
            Update { state, action in
                switch action {
                case .proposalsRowTapped:
                    state.openProposalList()

                case .sourcePreparationRetryButtonTapped:
                    store.addTask {
                        let retry = try store.post(
                            key: SourceWorkspacePreparationRetryRequested.self,
                            value: ()
                        )
                        await retry?.value
                    }

                case .switchToMainButtonTapped:
                    guard state.authoringAccess.canEditContent,
                          let currentContext = state.selectedContext,
                          state.changeCount == nil,
                          !state.contextSelection.isRunning
                    else { return }
                    let requestedBranch = WorkspaceBranch(
                        rawValue: SourceWorkspace.normalizedBranch(state.workspace.defaultBranch)
                    )
                    if case let .published(reference) = currentContext,
                       reference.branch == requestedBranch
                    {
                        return
                    }
                    let contextSelection = state.contextSelection
                    store.addTask(id: contextSelection) {
                        let task = try store.post(
                            key: WorkspacePublishedRequested.self,
                            value: requestedBranch
                        )
                        await task?.value
                    }

                case .switchBranchButtonTapped:
                    guard state.authoringAccess.canEditContent,
                          let currentContext = state.selectedContext,
                          state.changeCount == nil,
                          !state.contextSelection.isRunning,
                          !state.requestedBranch.trimmingCharacters(
                              in: .whitespacesAndNewlines
                          ).isEmpty
                    else { return }
                    let requestedBranch = WorkspaceBranch(
                        rawValue: SourceWorkspace.normalizedBranch(state.requestedBranch)
                    )
                    guard requestedBranch != currentContext.selectedBranch else { return }
                    let contextSelection = state.contextSelection
                    store.addTask(id: contextSelection) {
                        let task = try store.post(
                            key: WorkspaceBranchRequested.self,
                            value: requestedBranch
                        )
                        await task?.value
                    }

                case .viewProposalButtonTapped:
                    guard let proposal = state.workspaceState.selectedProposal else { return }
                    state.openProposalList(proposal)

                case .changes, .collaborators, .reviews:
                    break
                }
            }
            Scope(\.changes, action: \.changes) { WorkspaceChanges() }
        }
        .ifLet(\.collaborators, action: \.collaborators) {
            WorkspaceCollaborators()
        }
        .ifLet(\.reviews, action: \.reviews) {
            WorkspaceReviews()
        }
        .onChange(of: store.authoringGrant, initial: true) { _, grant, state in
            state.updateAuthoringGrant(grant)
        }
    }
}

public struct EventWorkspaceView: View {
    @Bindable var store: StoreOf<EventWorkspace>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    @State var isBranchPromptPresented = false

    public init(store: StoreOf<EventWorkspace>) {
        self.store = store
    }

    public var body: some View {
        @Bindable var changesStore = store.scope(\.changes, action: \.changes)

        List {
            if store.pendingProposalRepair != nil {
                Section {
                    Text("Proposal published; finishing workspace refresh.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("workspace.proposal.repair-pending")
                }
            }

            WorkspaceContextSection(
                workspace: store.workspace,
                workspaceState: store.workspaceState,
                isSelectingContext: store.contextSelection.isRunning,
                canSwitchBranch: store.authoringAccess.canEditContent
                    && store.workspaceIsReady
                    && store.changeCount == nil,
                viewProposal: {
                    store.send(.viewProposalButtonTapped)
                },
                switchBranch: {
                    isBranchPromptPresented = true
                },
                switchToMain: {
                    store.send(.switchToMainButtonTapped)
                }
            )

            Section {
                Button {
                    store.send(.proposalsRowTapped)
                } label: {
                    Label("Proposals", mappedSystemImage: "arrow.triangle.pull")
                }
                .navigationLinkListRowStyle()
                .accessibilityIdentifier("workspace.proposals")

                if let collaborators = store.scope(\.collaborators, action: \.collaborators) {
                    NavigationLink {
                        WorkspaceCollaboratorsView(store: collaborators)
                    } label: {
                        Label("Collaborators", mappedSystemImage: "person.3")
                    }
                    .navigationLinkListRowStyle()
                    .accessibilityIdentifier("workspace.collaborators")
                }
            }

            WorkspaceChangesView(
                store: changesStore,
                workspaceState: store.workspaceState
            )

            if showsTechnicalDetails {
                WorkspaceTechnicalDetailsSection(
                    workspace: store.workspace,
                    eventID: store.eventID,
                    workspaceState: store.workspaceState
                )
            }
        }
        .navigationTitle("Workspace")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $store.scope(\.reviews, action: \.reviews)) { reviewsStore in
            WorkspaceReviewsView(store: reviewsStore)
        }
        .sheet(item: $changesStore.scope(\.proposalDraft, action: \.proposalDraft)) { draftStore in
            WorkspaceProposalDraftView(store: draftStore)
        }
        .alert("Switch branch", isPresented: $isBranchPromptPresented) {
            TextField("Branch name", text: $store.requestedBranch)
                .autocorrectionDisabled()
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                #endif
                .accessibilityIdentifier("workspace.branch.name")
            Button("Switch") {
                store.send(.switchBranchButtonTapped)
            }
            .disabled(
                store.requestedBranch.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            )
            .accessibilityIdentifier("workspace.branch.switch")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the branch to use as this workspace’s comparison reference.")
        }
    }
}

struct WorkspaceContextSection: View {
    let workspace: SourceWorkspace
    let workspaceState: WorkspaceState<SourceWorkspaceResource>
    let isSelectingContext: Bool
    let canSwitchBranch: Bool
    let viewProposal: () -> Void
    let switchBranch: () -> Void
    let switchToMain: () -> Void

    var contextTitle: String {
        switch workspaceState.selectedContext {
        case .published:
            "Published"
        case .branch:
            "Branch"
        case .proposal:
            "Proposal"
        case nil:
            switch workspaceState.availability {
            case .preparing:
                "Preparing workspace"
            case .inactive:
                "Workspace not prepared"
            case .preparationFailed, .ready:
                "Workspace unavailable"
            }
        }
    }

    var selectedBranch: String? {
        workspaceState.selectedContext?.selectedBranch.rawValue
    }

    var isPublishedMain: Bool {
        guard case let .published(reference)? = workspaceState.selectedContext else {
            return false
        }
        return reference.branch.rawValue == workspace.defaultBranch
    }

    var canSwitchToMain: Bool {
        canSwitchBranch && !isPublishedMain
    }

    var accessibilityLabel: String {
        guard let selectedBranch else { return contextTitle }
        let current = "Current workspace context: \(contextTitle), branch \(selectedBranch)"
        return isSelectingContext ? "\(current), switching" : current
    }

    var body: some View {
        Section {
            Menu {
                if workspaceState.selectedProposal != nil {
                    Button(action: viewProposal) {
                        Label("View proposal", mappedSystemImage: "arrow.triangle.pull")
                    }
                    .accessibilityIdentifier("workspace.proposal.view")
                }

                Button(action: switchBranch) {
                    Label("Switch branch…", mappedSystemImage: "arrow.triangle.branch")
                }
                .disabled(!canSwitchBranch)
                .accessibilityIdentifier("workspace.branch.prompt")

                Button(action: switchToMain) {
                    Label("Switch to main", mappedSystemImage: "arrow.uturn.backward")
                }
                .disabled(!canSwitchToMain)
                .accessibilityIdentifier("workspace.branch.main")
            } label: {
                HStack(spacing: 12) {
                    MappedSystemImage(systemName: "arrow.triangle.branch")
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: contextTitle)

                        if let selectedBranch {
                            WorkspaceBranchChip(branch: selectedBranch)
                        }
                    }

                    Spacer()

                    if isSelectingContext {
                        ProgressView()
                            .frame(width: 16, height: 16)
                    } else {
                        MappedSystemImage(systemName: "chevron.down")
                            .foregroundStyle(.secondary)
                            .frame(width: 12, height: 12)
                    }
                }
                .contentShape(Rectangle())
            }
            .disabled(isSelectingContext)
            .tint(.primary)
            .accessibilityLabel(Text(verbatim: accessibilityLabel))
            .accessibilityIdentifier("workspace.context")
        }
    }
}

struct WorkspaceBranchChip: View {
    let branch: String

    var body: some View {
        Text(verbatim: branch)
            .font(.caption.monospaced())
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Color.accentColor.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 5)
            )
    }
}

struct WorkspaceTechnicalDetailsSection: View {
    let workspace: SourceWorkspace
    let eventID: OME.Event.ID
    let workspaceState: WorkspaceState<SourceWorkspaceResource>

    var body: some View {
        Section("Technical details") {
            WorkspaceTechnicalValueView(label: "Repository", value: workspace.repository)
            WorkspaceTechnicalValueView(label: "Organization", value: workspace.organizerID.description)
            WorkspaceTechnicalValueView(label: "Event", value: eventID.eventID.rawValue.rawValue)
            if let selectedContext = workspaceState.selectedContext {
                WorkspaceTechnicalValueView(
                    label: "Selected revision",
                    value: selectedContext.revision.rawValue
                )
            }
            if let selectedProposal = workspaceState.selectedProposal {
                WorkspaceTechnicalValueView(
                    label: "Selected proposal",
                    value: selectedProposal.id.rawValue
                )
            }
            if let failure = workspaceState.preparationFailure {
                WorkspaceTechnicalValueView(label: "Diagnostic", value: failure.message)
            }
        }
    }
}

struct SourceChangeSummarySection: View {
    let groups: [SourceChangeGroup]
    let fieldComparisons: SourceFieldComparisons
    let recordComparisons: SourceRecordComparisons
    let emptyMessage: String

    init(
        groups: [SourceChangeGroup],
        fieldComparisons: SourceFieldComparisons,
        recordComparisons: SourceRecordComparisons,
        emptyMessage: String = "No changes"
    ) {
        self.groups = groups
        self.fieldComparisons = fieldComparisons
        self.recordComparisons = recordComparisons
        self.emptyMessage = emptyMessage
    }

    var body: some View {
        Section("What changed") {
            if groups.allSatisfy({ $0.totalCount == 0 }) {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            }
            ForEach(groups.filter { $0.totalCount > 0 }) { group in
                SourceChangeGroupDisclosure(
                    group: group,
                    fieldComparisons: fieldComparisons,
                    recordComparisons: recordComparisons
                )
            }
        }
    }
}

struct SourceChangePresentationSection: View {
    let presentation: OME.WorkspaceProposal.Presentation
    let emptyMessage: String
    let title: LocalizedStringKey

    init(
        presentation: OME.WorkspaceProposal.Presentation,
        emptyMessage: String,
        title: LocalizedStringKey = "What changed"
    ) {
        self.presentation = presentation
        self.emptyMessage = emptyMessage
        self.title = title
    }

    var body: some View {
        Section(title) {
            if presentation.totalCount == 0 {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            }
            ForEach(presentation.groups.filter { !$0.records.isEmpty }) { group in
                ProposalRecordGroupDisclosure(group: group)
            }
        }
    }
}

struct SourceChangeGroupDisclosure: View {
    let group: SourceChangeGroup
    let fieldComparisons: SourceFieldComparisons
    let recordComparisons: SourceRecordComparisons

    var body: some View {
        PortableDisclosureGroup {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(kinds, id: \.self) { kind in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(kind.sectionTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(records(for: kind)) { record in
                            SourceRecordChangeRow(
                                group: group,
                                record: record,
                                fieldComparisons: fieldComparisons,
                                comparison: recordComparisons[record]
                            )
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.displayName)
                    Text(group.totalCount == 1 ? "1 change" : "\(group.totalCount) changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                SourceChangeCountBadges(group: group)
            }
        }
    }

    var kinds: [SourceRecordChangeKind] {
        SourceRecordChangeKind.allCases.filter { kind in
            group.records.contains { $0.kind == kind }
        }
    }

    func records(for kind: SourceRecordChangeKind) -> [SourceRecordChange] {
        group.records.filter { $0.kind == kind }
    }
}

struct SourceChangeCountBadges: View {
    let group: SourceChangeGroup

    var body: some View {
        HStack(spacing: 6) {
            if group.added > 0 {
                SourceChangeCountBadge(kind: .added, count: group.added)
            }
            if group.modified > 0 {
                SourceChangeCountBadge(kind: .modified, count: group.modified)
            }
            if group.deleted > 0 {
                SourceChangeCountBadge(kind: .deleted, count: group.deleted)
            }
        }
    }
}

struct SourceChangeCountBadge: View {
    let kind: SourceRecordChangeKind
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Text(kind.shortTitle)
            Text(count, format: .number)
        }
        .font(.caption2.weight(.semibold))
        .portableMonospacedDigit()
        .foregroundStyle(kind.foregroundStyle)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(kind.backgroundStyle, in: Capsule())
        .portableAccessibilityElement()
        .accessibilityLabel("\(count) \(kind.sectionTitle.lowercased())")
    }
}

public struct SourceRecordComparisonStyleConfiguration<Record: Sendable> {
    public let group: SourceChangeGroup
    public let record: SourceRecordChange
    public let fieldComparisons: SourceFieldComparisons
    public let comparison: SourceRecordComparison<Record>

    public init(
        group: SourceChangeGroup,
        record: SourceRecordChange,
        fieldComparisons: SourceFieldComparisons,
        comparison: SourceRecordComparison<Record>
    ) {
        self.group = group
        self.record = record
        self.fieldComparisons = fieldComparisons
        self.comparison = comparison
    }
}

public struct SourceRecordComparisonStyle {
    typealias Row = @MainActor (
        SourceChangeGroup,
        SourceRecordChange,
        SourceFieldComparisons,
        AnySourceRecordComparison
    ) -> AnyView?

    var rowsByRecordType: [ObjectIdentifier: Row]

    public init() {
        self.rowsByRecordType = [:]
    }

    public mutating func set<Record: Sendable, Content: View>(
        for recordType: Record.Type,
        @ViewBuilder row: @escaping @MainActor (
            SourceRecordComparisonStyleConfiguration<Record>
        ) -> Content
    ) {
        rowsByRecordType[ObjectIdentifier(recordType)] = {
            group,
            record,
            fieldComparisons,
            comparison in
            guard let comparison = comparison.as(recordType) else { return nil }
            return AnyView(
                row(
                    SourceRecordComparisonStyleConfiguration(
                        group: group,
                        record: record,
                        fieldComparisons: fieldComparisons,
                        comparison: comparison
                    )
                )
            )
        }
    }

    public func overlaying(_ overrides: Self) -> Self {
        var result = self
        result.rowsByRecordType.merge(overrides.rowsByRecordType) { _, override in override }
        return result
    }

    @MainActor
    func row(
        group: SourceChangeGroup,
        record: SourceRecordChange,
        fieldComparisons: SourceFieldComparisons,
        comparison: AnySourceRecordComparison
    ) -> AnyView? {
        rowsByRecordType[comparison.recordTypeID]?(
            group,
            record,
            fieldComparisons,
            comparison
        )
    }
}

enum SourceRecordComparisonStyleKey: EnvironmentKey {
    static var defaultValue: SourceRecordComparisonStyle { SourceRecordComparisonStyle() }
}

public extension EnvironmentValues {
    var sourceRecordComparisonStyle: SourceRecordComparisonStyle {
        get { self[SourceRecordComparisonStyleKey.self] }
        set { self[SourceRecordComparisonStyleKey.self] = newValue }
    }
}

public extension SourceRecordComparisonStyle {
    @MainActor
    static var openMusicEvent: Self {
        var style = Self()
        style.set(for: OME.Contributor.self) { configuration in
            SourceSemanticRecordChangeRow(
                record: configuration.record,
                fieldComparisons: configuration.fieldComparisons,
                title: configuration.comparison.right?.name
                    ?? configuration.comparison.left?.name
                    ?? String(describing: OME.Contributor.self),
                recordTitle: "Contributor"
            )
        }
        return style
    }
}

struct SourceRecordChangeRow: View {
    let group: SourceChangeGroup
    let record: SourceRecordChange
    let fieldComparisons: SourceFieldComparisons
    let comparison: AnySourceRecordComparison?
    @Environment(\.sourceRecordComparisonStyle) var sourceRecordComparisonStyle

    @ViewBuilder
    var body: some View {
        if let comparison,
           let row = sourceRecordComparisonStyle.row(
               group: group,
               record: record,
               fieldComparisons: fieldComparisons,
               comparison: comparison
           ) {
            row
        } else {
            SourceSemanticRecordChangeRow(
                record: record,
                fieldComparisons: fieldComparisons,
                title: fallbackTitle,
                recordTitle: "Source record"
            )
        }
    }

    var fallbackTitle: String {
        comparison?.recordTypeDisplayName ?? group.displayName
    }
}

public struct SourceSemanticRecordChangeRow: View {
    let record: SourceRecordChange
    let fieldComparisons: SourceFieldComparisons
    let title: String
    let recordTitle: String
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    public init(
        record: SourceRecordChange,
        fieldComparisons: SourceFieldComparisons,
        title: String,
        recordTitle: String
    ) {
        self.record = record
        self.fieldComparisons = fieldComparisons
        self.title = title
        self.recordTitle = recordTitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SourceChangeKindBadge(kind: record.kind)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                    Text(recordTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if visibleFieldChanges.isEmpty, !record.fieldChanges.isEmpty {
                Text("Technical details changed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleFieldChanges) { change in
                    SourceFieldChangePresentationRow(
                        change: change,
                        comparison: fieldComparisons[record, change],
                        kind: record.kind
                    )
                }
            }

            if showsTechnicalDetails {
                WorkspaceTechnicalValueView(
                    label: "Record",
                    value: record.primaryKeySummary
                )

                if let recordDiff = record.recordDiff, !recordDiff.isEmpty {
                    PortableDisclosureGroup("Raw record diff") {
                        Text(recordDiff)
                            .font(.caption)
                            .monospaced()
                            .selectableText()
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    var visibleFieldChanges: [SourceFieldChange] {
        record.fieldChanges.filter { change in
            (showsTechnicalDetails || !change.columnName.isTechnicalSourceColumn)
                && change.sourcePresentation(
                    kind: record.kind,
                    comparison: fieldComparisons[record, change]
                ).isVisible
        }
    }
}

struct SourceChangeKindBadge: View {
    let kind: SourceRecordChangeKind

    var body: some View {
        Text(kind.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(kind.foregroundStyle)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(kind.backgroundStyle, in: Capsule())
    }
}

struct SourceFieldChangePresentationRow: View {
    let change: SourceFieldChange
    let comparison: AnySourceFieldComparison?
    let kind: SourceRecordChangeKind

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(change.columnName.sourceFieldTitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            switch change.sourcePresentation(kind: kind, comparison: comparison) {
            case let .added(value):
                SourceChangeValueView(
                    label: "Added",
                    value: value,
                    role: .added
                )

            case let .modified(before, after):
                SourceChangeValueView(
                    label: "Before",
                    value: before,
                    role: .removed
                )
                SourceChangeValueView(
                    label: "After",
                    value: after,
                    role: .added
                )

            case let .removed(value):
                SourceChangeValueView(
                    label: "Removed",
                    value: value,
                    role: .removed
                )

            case let .structuralDifference(difference):
                SourceStructuralDifferenceView(difference: difference)

            case .hidden:
                EmptyView()
            }
        }
    }
}

enum SourceFieldChangePresentation: Equatable {
    case added(String)
    case modified(before: String, after: String)
    case removed(String)
    case structuralDifference(String)
    case hidden

    var isVisible: Bool {
        self != .hidden
    }
}

extension SourceFieldChange {
    func sourcePresentation(
        kind: SourceRecordChangeKind,
        comparison: AnySourceFieldComparison?
    ) -> SourceFieldChangePresentation {
        switch kind {
        case .added:
            return .added(
                workingValue.sourceDisplayValue(columnName: columnName)
            )

        case .modified:
            let before = baselineValue.sourceDisplayValue(columnName: columnName)
            let after = workingValue.sourceDisplayValue(columnName: columnName)
            guard before == after else {
                return .modified(before: before, after: after)
            }
            guard let difference = comparison?.difference,
                  !difference.isEmpty
            else { return .hidden }
            return .structuralDifference(difference)

        case .deleted:
            return .removed(
                baselineValue.sourceDisplayValue(columnName: columnName)
            )
        }
    }
}

struct SourceStructuralDifferenceView: View {
    let difference: String

    var body: some View {
        let lines = difference.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 1) {
            ForEach(lines.indices, id: \.self) { index in
                let line = lines[index]
                Text(line)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(line.sourceDifferenceForegroundStyle)
            }
        }
        .selectableText()
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension String {
    var sourceDifferenceForegroundStyle: Color {
        let content = trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("-") {
            return .red
        }
        if content.hasPrefix("+") {
            return .green
        }
        return .secondary
    }
}

struct SourceChangeValueView: View {
    enum Role {
        case added
        case removed
    }

    let label: String
    let value: String
    let role: Role

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(role.foregroundStyle)
            Text(value)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(role.backgroundStyle, in: RoundedRectangle(cornerRadius: 8))
    }
}

extension SourceChangeValueView.Role {
    var backgroundStyle: Color {
        switch self {
        case .added:
            Color.green.opacity(0.12)
        case .removed:
            Color.red.opacity(0.10)
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .added:
            .green
        case .removed:
            .red
        }
    }
}

extension SourceRecordChangeKind {
    init(_ kind: OME.WorkspaceProposal.Presentation.Transition.Kind) {
        switch kind {
        case .added:
            self = .added
        case .modified:
            self = .modified
        case .deleted:
            self = .deleted
        }
    }

    var backgroundStyle: Color {
        switch self {
        case .added:
            Color.green.opacity(0.16)
        case .modified:
            Color.orange.opacity(0.18)
        case .deleted:
            Color.red.opacity(0.16)
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .added:
            .green
        case .modified:
            .orange
        case .deleted:
            .red
        }
    }

    var sectionTitle: String {
        switch self {
        case .added:
            "Added records"
        case .modified:
            "Modified records"
        case .deleted:
            "Deleted records"
        }
    }

    var shortTitle: String {
        switch self {
        case .added:
            "+"
        case .modified:
            "~"
        case .deleted:
            "−"
        }
    }

    var title: String {
        switch self {
        case .added:
            "Added"
        case .modified:
            "Modified"
        case .deleted:
            "Deleted"
        }
    }
}

extension SourceRecordChange {
    var primaryKeySummary: String {
        primaryKeyValues
            .map { "\($0.columnName)=\($0.value.sourceDisplayValue(columnName: $0.columnName))" }
            .joined(separator: ", ")
    }
}

extension String {
    var isTechnicalSourceColumn: Bool {
        hasSuffix("ID")
            || self == "contributorActor"
            || self == "did"
            || self == "object"
            || self == "owner"
            || self == "recordKey"
            || self == "sortIndex"
            || self == "subject"
            || self == "type"
    }

    var sourceFieldTitle: String {
        switch self {
        case "bio":
            "Biography"
        case "customTitle":
            "Title"
        case "categoryConfigs":
            "Stage categories"
        case "contactNumbers":
            "Contact numbers"
        case "defaultNotificationState":
            "Default notifications"
        case "endDate":
            "End date"
        case "endsAt", "endTime":
            "End time"
        case "iconImageURL":
            "Icon image"
        case "headerImageURL":
            "Header image"
        case "notificationsRequired":
            "Notifications required"
        case "reportingLinks":
            "Reporting links"
        case "startDate":
            "Start date"
        case "startsAt", "startTime":
            "Start time"
        case "systemIconName":
            "System icon"
        case "iconShortCode":
            "Icon shortcode"
        case "timeZone":
            "Time zone"
        case "uris":
            "Links"
        default:
            first?.uppercased().appending(String(dropFirst())) ?? self
        }
    }
}

extension Optional where Wrapped == DatabaseValue {
    func sourceDisplayValue(columnName: String) -> String {
        switch self {
        case .none:
            "Not set"
        case let .some(value):
            value.sourceDisplayValue(columnName: columnName)
        }
    }
}

extension DatabaseValue {
    func sourceDisplayValue(columnName: String) -> String {
        switch storage {
        case .null:
            "Not set"
        case let .int64(value):
            if columnName == "notificationsRequired" {
                value == 0 ? "No" : "Yes"
            } else {
                "\(value)"
            }
        case let .double(value):
            "\(value)"
        case let .string(value):
            value.sourceDisplayValue
        case let .blob(data):
            "Binary data (\(data.count) bytes)"
        }
    }
}

extension String {
    var sourceDisplayValue: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Empty" }

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data)
        {
            if let values = json as? [Any] {
                return values.count == 1 ? "1 item" : "\(values.count) items"
            }
            if let values = json as? [String: Any] {
                return values.count == 1 ? "1 detail" : "\(values.count) details"
            }
        }

        guard trimmed.count > 240 else { return trimmed }
        return "\(trimmed.prefix(240))…"
    }
}
