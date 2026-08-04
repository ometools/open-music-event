import ComposableArchitecture2
import ComposableAuthoring
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
        Section("Source changes") {
            if groups.allSatisfy({ $0.totalCount == 0 }) {
                Text("No local changes").foregroundStyle(.secondary)
            }
            ForEach(groups.filter { $0.totalCount > 0 }) { group in
                HStack {
                    Text(group.displayName)
                    Spacer()
                    Text("+\(group.added)  ~\(group.modified)  −\(group.deleted)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
