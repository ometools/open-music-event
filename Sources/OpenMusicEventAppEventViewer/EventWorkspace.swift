import ComposableArchitecture2
import ComposableAuthoring
import ComposableWorkspace
import Foundation
import GRDB
import OpenMusicEventComponents
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import Sharing
import SourceEditing
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

/// The application-facing details for the one organization source owned by Workspace.
/// `eventID` is only a viewer focus; changes, proposals, and reconciliation remain source-scoped.
@Feature
public struct EventWorkspace {
    public init() {}

    public enum Page: String, CaseIterable, Equatable, Identifiable, Sendable {
        case changes
        case collaborators
        case proposals

        public var id: Self { self }

        public var title: String {
            switch self {
            case .changes: "Changes"
            case .collaborators: "Collaborators"
            case .proposals: "Proposals"
            }
        }
    }

    public struct State: Identifiable {
        public init(
            workspace: SourceWorkspace,
            eventID: OME.Event.ID,
            workspacePhase: SharedReader<WorkspacePhase<SourcePatch>>,
            referenceDatabase: SourceBaselineDatabase? = nil
        ) {
            self.workspace = workspace
            self.eventID = eventID
            self._workspacePhase = workspacePhase
            self.changes = WorkspaceChanges.State(
                workspace: workspace,
                referenceDatabase: referenceDatabase
            )
            self.reviews = WorkspaceReviews.State(workspace: workspace)
        }

        public let workspace: SourceWorkspace
        public let eventID: OME.Event.ID
        @SharedReader public var workspacePhase: WorkspacePhase<SourcePatch>
        public var id: SourceWorkspace.ID { workspace.id }
        public var changes: WorkspaceChanges.State
        public var collaborators: WorkspaceCollaborators.State?
        public var reviews: WorkspaceReviews.State
        public var selectedPage: Page = .changes

        public var changeCount: Int? { changes.badgeCount }

        public var workspaceStatus: WorkspaceStatus { workspacePhase.status }

        public var workspaceIsReady: Bool {
            guard case .ready = workspacePhase else { return false }
            return true
        }

        public func availablePages(authoringAccess: AuthoringAccess) -> [Page] {
            var pages: [Page] = [.changes]
            if collaborators != nil {
                pages.append(.collaborators)
            }
            if reviews.canReview(authoringAccess: authoringAccess) {
                pages.append(.proposals)
            }
            return pages
        }

        mutating func updateAuthoringGrant(_ grant: AuthoringGrant?) {
            guard let grant,
                  grant.workspaceID == workspace.id,
                  grant.role.canManageCollaborators
            else {
                collaborators = nil
                if selectedPage == .collaborators { selectedPage = .changes }
                return
            }
            if collaborators?.workspaceID != workspace.id {
                collaborators = WorkspaceCollaborators.State(
                    workspace: workspace,
                    role: grant.role
                )
            }
        }
    }

    public enum Action {
        case changes(WorkspaceChanges.Action)
        case collaborators(WorkspaceCollaborators.Action)
        case reviews(WorkspaceReviews.Action)
        case sourcePreparationRetryButtonTapped
    }

    @FeatureEnvironment(ComposableAuthoring.AuthoringContext<AuthoringGrant>.self)
    var authoring

    public var body: some Feature {
        Features {
            Update { _, action in
                switch action {
                case .sourcePreparationRetryButtonTapped:
                    store.addTask {
                        let retry = try store.post(
                            key: SourceWorkspacePreparationRetryRequested.self,
                            value: ()
                        )
                        await retry?.value
                    }

                case .changes, .collaborators, .reviews:
                    break
                }
            }
            Scope(\.changes, action: \.changes) { WorkspaceChanges() }
            Scope(\.reviews, action: \.reviews) { WorkspaceReviews() }
        }
        .ifLet(\.collaborators, action: \.collaborators) {
            WorkspaceCollaborators()
        }
        .onChange(of: authoring.grant.wrappedValue, initial: true) { _, grant, state in
            state.updateAuthoringGrant(grant)
            let access = grant?.access ?? .attendee
            if !state.availablePages(authoringAccess: access).contains(state.selectedPage) {
                state.selectedPage = .changes
            }
        }
    }
}

public struct EventWorkspaceView: View {
    @Bindable var store: StoreOf<EventWorkspace>
    let authoringAccess: AuthoringAccess
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    public init(
        store: StoreOf<EventWorkspace>,
        authoringAccess: AuthoringAccess = .attendee
    ) {
        self.store = store
        self.authoringAccess = authoringAccess
    }

    var availablePages: [EventWorkspace.Page] {
        var pages: [EventWorkspace.Page] = [.changes]
        if store.collaborators != nil {
            pages.append(.collaborators)
        }
        if authoringAccess.canMerge {
            pages.append(.proposals)
        }
        return pages
    }

    public var body: some View {
        let changesStore = store.scope(\.changes, action: \.changes)

        VStack(spacing: 0) {
            WorkspaceStatusView(
                status: store.workspaceStatus,
                retrySourcePreparation: {
                    store.send(.sourcePreparationRetryButtonTapped)
                }
            )

            switch store.selectedPage {
            case .changes:
                WorkspaceChangesView(
                    store: changesStore,
                    workspaceStatus: store.workspaceStatus
                )

            case .collaborators:
                if let collaborators = store.scope(\.collaborators, action: \.collaborators) {
                    WorkspaceCollaboratorsView(store: collaborators)
                }

            case .proposals:
                WorkspaceReviewsView(store: store.scope(\.reviews, action: \.reviews))
            }
        }
        .navigationTitle("Shared Workspace")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .portableSafeAreaTopInset(spacing: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your changes")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            switch changesStore.summary.availability {
                            case .available:
                                Text(changesStore.changeCount, format: .number)
                                    .font(.title3)
                                    .portableMonospacedDigit()
                            case .workspaceNeedsPreparation, .unavailable:
                                Text("—")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Workspace")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Organization workspace")
                                .font(.subheadline)
                        }
                    }

                    if showsTechnicalDetails {
                        PortableDisclosureGroup("Technical details") {
                            VStack(alignment: .leading, spacing: 8) {
                                WorkspaceTechnicalValueView(
                                    label: "Repository",
                                    value: store.workspace.repository
                                )
                                WorkspaceTechnicalValueView(
                                    label: "Branch",
                                    value: store.workspace.branch
                                )
                                WorkspaceTechnicalValueView(
                                    label: "Organization",
                                    value: store.workspace.organizerID.description
                                )
                                WorkspaceTechnicalValueView(
                                    label: "Event",
                                    value: store.eventID.eventID.rawValue.rawValue
                                )
                                if let proposal = changesStore.openProposal {
                                    WorkspaceTechnicalValueView(
                                        label: "Open proposal",
                                        value: proposal.id.rawValue
                                    )
                                }
                            }
                            .padding(.top, 8)
                        }
                        .font(.caption)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 6)

                let pages = availablePages
                if pages.count > 1 {
                    Picker("Workspace section", selection: $store.selectedPage) {
                        ForEach(pages) { page in
                            Text(page.title).tag(page)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                }

                if case .available = changesStore.summary.availability,
                   store.selectedPage == .changes,
                   changesStore.changeCount > 0,
                   authoringAccess.canPropose,
                   store.workspaceIsReady
                {
                    Button {
                        changesStore.send(.proposalActionButtonTapped)
                    } label: {
                        Label(
                            changesStore.openProposal == nil
                                ? "Create proposal"
                                : "Update proposal",
                            systemImage: "paperplane"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .background(.background)
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
    }
}

struct WorkspaceStatusView: View {
    let status: WorkspaceStatus
    let retrySourcePreparation: () -> Void
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var failure: WorkspaceFailure? {
        guard case let .failed(_, failure) = status else { return nil }
        return failure
    }

    var isPreparingSourceFailure: Bool {
        guard case .failed(operation: .sourcePreparation, failure: _) = status else {
            return false
        }
        return true
    }

    var message: String {
        switch status {
        case .activity(.capturingChanges):
            return "Collecting the current workspace changes."
        case .activity(.preparingSource):
            return "Opening the organization source."
        case .activity(.publishing(.pushCommit)):
            return "Saving the captured changes to the proposal branch."
        case .activity(.publishing(.recordProposal)):
            return "Recording the proposal for the saved branch revision."
        case .activity(.publishing(.updateReference)):
            return "Updating the settled workspace after recording the proposal."
        case .activity(.reconciling):
            return "Reconciling the organization source."
        case .failed(operation: .publication, failure: _),
             .failed(operation: .submissionCapture, failure: _):
            return "Your changes are still available. Further proposal publishing is unavailable until this failure is resolved."
        case .failed(operation: .reconciliation, failure: _):
            return "Your changes remain in the working database. The workspace is using its last settled source."
        case .failed(operation: .sourcePreparation, failure: _):
            return "Authoring remains active, but source-backed changes are unavailable until preparation succeeds."
        case .inactive:
            return "Enter authoring to prepare this organization source."
        case .interrupted(.publication):
            return "Your changes and the unfinished publication are preserved."
        case .interrupted(.reconciliation):
            return "Your changes remain available while the interrupted refresh is unresolved."
        case .interrupted(.sourcePreparation):
            return "Authoring remains active while source preparation is unresolved."
        case .interrupted(.submissionCapture):
            return "Your changes remain available while proposal preparation is unresolved."
        case .ready(.canonical):
            return "Source-backed editing and proposal creation are available."
        case .ready(.proposal):
            return "Source-backed editing is ready to update the open proposal."
        case .stale:
            return "The source changed while you were editing. Publishing is unavailable until reconciliation succeeds."
        }
    }

    var title: String {
        switch status {
        case .activity(.capturingChanges):
            return "Preparing proposal"
        case .activity(.preparingSource):
            return "Preparing workspace"
        case .activity(.publishing(.pushCommit)):
            return "Pushing proposal changes"
        case .activity(.publishing(.recordProposal)):
            return "Recording proposal"
        case .activity(.publishing(.updateReference)):
            return "Finalizing proposal"
        case .activity(.reconciling):
            return "Refreshing workspace"
        case .failed(operation: .publication, failure: _),
             .failed(operation: .submissionCapture, failure: _):
            return "Proposal failed"
        case .failed(operation: .reconciliation, failure: _):
            return "Workspace refresh failed"
        case .failed(operation: .sourcePreparation, failure: _):
            return "Workspace preparation failed"
        case .inactive:
            return "Workspace inactive"
        case .interrupted(.publication):
            return "Proposal interrupted"
        case .interrupted(.reconciliation):
            return "Workspace refresh interrupted"
        case .interrupted(.sourcePreparation):
            return "Workspace preparation interrupted"
        case .interrupted(.submissionCapture):
            return "Proposal preparation interrupted"
        case .ready(.canonical):
            return "Workspace ready"
        case .ready(.proposal):
            return "Proposal workspace ready"
        case .stale:
            return "Workspace source changed"
        }
    }

    var showsProgress: Bool {
        guard case .activity = status else { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if showsProgress {
                    ProgressView()
                }

                Text(title)
                    .font(.headline)
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            if showsTechnicalDetails, let failure {
                PortableDisclosureGroup("Technical details") {
                    WorkspaceTechnicalValueView(
                        label: "Error",
                        value: failure.message
                    )
                    .padding(.top, 8)
                }
                .font(.caption)
            }

            if isPreparingSourceFailure {
                Button("Retry preparation", action: retrySourcePreparation)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

public struct WorkspaceProposalDraftView: View {
    @Bindable var store: StoreOf<WorkspaceProposalDraft>

    public init(store: StoreOf<WorkspaceProposalDraft>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Proposal") {
                    TextField(
                        "Title",
                        text: Binding(
                            get: { store.title },
                            set: { store.send(.titleChanged($0)) }
                        )
                    )
                    PortableTextField(
                        "Description",
                        text: Binding(
                            get: { store.description },
                            set: { store.send(.descriptionChanged($0)) }
                        ),
                        axis: .vertical
                    )
                }
                SourceChangeSummarySection(
                    groups: store.groups,
                    fieldComparisons: store.fieldComparisons,
                    recordComparisons: store.recordComparisons
                )
            }
            .navigationTitle("Create proposal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.send(.cancelButtonTapped) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { store.send(.createProposalButtonTapped) }
                        .disabled(store.proposalTitle == nil)
                }
            }
        }
    }
}

struct SourceChangeSummarySection: View {
    let groups: [SourceChangeGroup]
    let fieldComparisons: SourceFieldComparisons
    let recordComparisons: SourceRecordComparisons

    var body: some View {
        Section("What changed") {
            if groups.allSatisfy({ $0.totalCount == 0 }) {
                Text("No changes")
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
