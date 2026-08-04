import ComposableArchitecture2
import ComposableAuthoring
import Foundation
import GRDB
import OpenMusicEventComponents
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
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
        public init(workspace: SourceWorkspace, eventID: OME.Event.ID) {
            self.workspace = workspace
            self.eventID = eventID
            self.changes = WorkspaceChanges.State(workspace: workspace)
            self.reviews = WorkspaceReviews.State(workspace: workspace)
        }

        public let workspace: SourceWorkspace
        public let eventID: OME.Event.ID
        public var id: SourceWorkspace.ID { workspace.id }
        public var changes: WorkspaceChanges.State
        public var collaborators: WorkspaceCollaborators.State?
        public var reviews: WorkspaceReviews.State
        public var selectedPage: Page = .changes

        public var changeCount: Int? { changes.badgeCount }

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
    }

    @FeatureEnvironment(ComposableAuthoring.AuthoringContext<AuthoringGrant>.self)
    var authoring

    public var body: some Feature {
        Features {
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
        VStack(spacing: 0) {
            WorkspaceDetailsView(
                workspace: store.workspace,
                eventID: store.eventID
            )

            let pages = availablePages
            if pages.count > 1 {
                Picker("Workspace section", selection: $store.selectedPage) {
                    ForEach(pages) { page in
                        Text(page.title).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            switch store.selectedPage {
            case .changes:
                WorkspaceChangesView(store: store.scope(\.changes, action: \.changes))

            case .collaborators:
                if let collaborators = store.scope(\.collaborators, action: \.collaborators) {
                    WorkspaceCollaboratorsView(store: collaborators)
                }

            case .proposals:
                WorkspaceReviewsView(store: store.scope(\.reviews, action: \.reviews))
            }
        }
    }
}

struct WorkspaceDetailsView: View {
    let workspace: SourceWorkspace
    let eventID: OME.Event.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Organization workspace").font(.headline)
            Text(workspace.repository)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("Branch: \(workspace.branch) · Viewing: \(eventID.eventID.rawValue.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
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
                    TextField(
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
                    recordComparisons: recordComparisons
                )
            }
        }
    }
}

struct SourceChangeGroupDisclosure: View {
    let group: SourceChangeGroup
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

struct SourceRecordChangeRow: View {
    let group: SourceChangeGroup
    let record: SourceRecordChange
    let comparison: AnySourceRecordComparison?
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    @ViewBuilder
    var body: some View {
        if let comparison = comparison?.as(OME.Event.self) {
            semanticRow(
                title: comparison.right?.name ?? comparison.left?.name ?? "Event",
                recordTitle: "Event"
            )
        } else if let comparison = comparison?.as(OME.Calendar.self) {
            semanticRow(
                title: comparison.right?.name ?? comparison.left?.name ?? "Calendar",
                recordTitle: "Calendar"
            )
        } else if let comparison = comparison?.as(OME.Stage.self) {
            semanticRow(
                title: comparison.right?.name ?? comparison.left?.name ?? "Stage",
                recordTitle: "Stage"
            )
        } else if let comparison = comparison?.as(OME.Schedule.self) {
            semanticRow(
                title: comparison.right?.customTitle
                    ?? comparison.left?.customTitle
                    ?? comparison.right?.date.rawValue
                    ?? comparison.left?.date.rawValue
                    ?? "Schedule",
                recordTitle: "Schedule"
            )
        } else if let comparison = comparison?.as(OME.ScheduleItem.self) {
            semanticRow(
                title: comparison.right?.title ?? comparison.left?.title ?? "Schedule item",
                recordTitle: "Schedule item"
            )
        } else if comparison?.as(OME.ScheduleItem.PerformanceDetails.self) != nil {
            semanticRow(title: "Performance recordings", recordTitle: "Schedule item details")
        } else if let comparison = comparison?.as(OME.ScheduleItem.Contributor.self) {
            semanticRow(
                title: comparison.right?.anonymousName
                    ?? comparison.left?.anonymousName
                    ?? "Performance contributor",
                recordTitle: "Schedule item contributor"
            )
        } else if let comparison = comparison?.as(OME.Contributor.self) {
            semanticRow(
                title: comparison.right?.name ?? comparison.left?.name ?? "Contributor",
                recordTitle: "Contributor"
            )
        } else if let comparison = comparison?.as(OME.Channel.self) {
            semanticRow(
                title: comparison.right?.name ?? comparison.left?.name ?? "Channel",
                recordTitle: "Communication channel"
            )
        } else if let comparison = comparison?.as(OME.Poster.self) {
            semanticRow(
                title: comparison.right?.title ?? comparison.left?.title ?? "Poster",
                recordTitle: "Poster"
            )
        } else if let comparison = comparison?.as(WorkspaceRelationshipRecord.self) {
            semanticRow(
                title: showsTechnicalDetails
                    ? comparison.right?.id.actorID.description
                        ?? comparison.left?.id.actorID.description
                        ?? "Workspace collaborator"
                    : "Workspace collaborator",
                recordTitle: "Collaborator"
            )
        } else {
            semanticRow(title: group.displayName, recordTitle: "Source record")
        }
    }

    func semanticRow(title: String, recordTitle: String) -> some View {
        SourceSemanticRecordChangeRow(
            record: record,
            title: title,
            recordTitle: recordTitle
        )
    }
}

struct SourceSemanticRecordChangeRow: View {
    let record: SourceRecordChange
    let title: String
    let recordTitle: String
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
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
            showsTechnicalDetails || !change.columnName.isTechnicalSourceColumn
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
    let kind: SourceRecordChangeKind

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(change.columnName.sourceFieldTitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            switch kind {
            case .added:
                SourceChangeValueView(
                    label: "Added",
                    value: change.workingValue.sourceDisplayValue(
                        columnName: change.columnName
                    ),
                    role: .added
                )

            case .modified:
                SourceChangeValueView(
                    label: "Before",
                    value: change.baselineValue.sourceDisplayValue(
                        columnName: change.columnName
                    ),
                    role: .removed
                )
                SourceChangeValueView(
                    label: "After",
                    value: change.workingValue.sourceDisplayValue(
                        columnName: change.columnName
                    ),
                    role: .added
                )

            case .deleted:
                SourceChangeValueView(
                    label: "Removed",
                    value: change.baselineValue.sourceDisplayValue(
                        columnName: change.columnName
                    ),
                    role: .removed
                )
            }
        }
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
