import ATProto
import BlueskyActorCache
import ComposableArchitecture2
import ComposableAuthoring
import ComposableForms
import ComposableWorkspace
import Dependencies
import ErrorHandling
import Foundation
import GRDB
import HTTPClient
import Lexicon
import OpenMusicEventComponents
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import SourceEditing
import Sharing
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

public struct SourceWorkspaceSummary: Equatable, Sendable {
    public var availability: SourceChangesAvailability
    public var groups: [SourceChangeGroup]
    public var recordComparisons: SourceRecordComparisons
    public var target: OpenMusicEventSourceTarget

    public init(
        target: OpenMusicEventSourceTarget,
        availability: SourceChangesAvailability,
        groups: [SourceChangeGroup],
        recordComparisons: SourceRecordComparisons = .empty
    ) {
        self.target = target
        self.availability = availability
        self.groups = groups.prioritizing(target: target)
        self.recordComparisons = recordComparisons
    }

    public init(
        target: OpenMusicEventSourceTarget,
        eventSummary: EventWorkspaceSummary
    ) {
        self.init(
            target: target,
            availability: SourceChangesAvailability(eventSummary.availability),
            groups: eventSummary.groups,
            recordComparisons: eventSummary.recordComparisons
        )
    }

    public init(
        target: OpenMusicEventSourceTarget,
        sourceSummary: SourceEditSummary
    ) {
        self.init(
            target: target,
            availability: SourceChangesAvailability(sourceSummary.availability),
            groups: sourceSummary.groups,
            recordComparisons: sourceSummary.recordComparisons
        )
    }

    public init(
        target: OpenMusicEventSourceTarget,
        changeSummary: SourceChangeSummary
    ) {
        self.init(
            target: target,
            availability: SourceChangesAvailability(changeSummary.availability),
            groups: changeSummary.groups,
            recordComparisons: changeSummary.recordComparisons
        )
    }

    public var totalCount: Int {
        groups.reduce(0) { $0 + $1.totalCount }
    }

    public var focusedCount: Int {
        switch target {
        case .calendar:
            totalCount

        case let .event(eventID):
            groups.reduce(0) { total, group in
                total + group.records.filter { $0.matches(eventID: eventID) }.count
            }
        }
    }

    public var outOfTargetCount: Int {
        max(0, totalCount - focusedCount)
    }

    var outOfTargetInclusionDescription: String? {
        switch outOfTargetCount {
        case 0:
            nil
        case 1:
            "1 change from another event is included in this workspace."
        case let count:
            "\(count) changes from other events are included in this workspace."
        }
    }

    public var badgeCount: Int? {
        guard case .available = availability, totalCount > 0 else { return nil }
        return totalCount
    }

    static func initialValue(target: OpenMusicEventSourceTarget) -> Self {
        switch target {
        case .event:
            Self(target: target, availability: .notInWorkspace, groups: [])
        case .calendar:
            Self(target: target, availability: .workspaceNeedsPreparation, groups: [])
        }
    }
}

extension SourceWorkspaceSummary {
    static func query(
        target: OpenMusicEventSourceTarget,
        using database: any DatabaseReader
    ) throws -> Self {
        try database.read { db in
            try query(target: target, in: db)
        }
    }

    static func query(
        target: OpenMusicEventSourceTarget,
        in db: Database
    ) throws -> Self {
        switch target {
        case let .event(eventID):
            return SourceWorkspaceSummary(
                target: target,
                eventSummary: try EventWorkspaceSummary.query(eventID: eventID, in: db)
            )

        case let .calendar(_, sourceBaselineID):
            return SourceWorkspaceSummary(
                target: target,
                sourceSummary: try SourceEditSummary.query(
                    sourceBaselineID: sourceBaselineID,
                    in: db
                )
            )
        }
    }
}

struct SourceWorkspaceSummaryRequest: FetchKeyRequest {
    let target: OpenMusicEventSourceTarget

    func fetch(_ db: Database) throws -> SourceWorkspaceSummary {
        try SourceWorkspaceSummary.query(target: target, in: db)
    }
}

@Feature
public struct EventWorkspace {
    public init() {}

    public struct State: Identifiable {
        public init(eventID: OMERecord.Event.ID) {
            self.init(target: .event(eventID))
        }

        public init(
            sourceBaselineID: SourceBaselineRecord.ID,
            calendarID: OMERecord.Calendar.ID
        ) {
            self.init(target: .calendar(calendarID, sourceBaselineID))
        }

        public init(target: OpenMusicEventSourceTarget) {
            self.target = target
            self.changes = WorkspaceChanges.State(target: target)
            self.reviews = WorkspaceReviews.State(target: target)
        }

        public let target: OpenMusicEventSourceTarget
        public var id: String { target.id }
        public var changes: WorkspaceChanges.State
        public var collaborators: WorkspaceCollaborators.State?
        public var reviews: WorkspaceReviews.State
        public var selectedPage: Page = .changes
        public var account = Spawn(Account.State())

        public var changeCount: Int? {
            changes.sourceWorkspaceSummary.badgeCount
        }

        public var calendarID: OMERecord.Calendar.ID? {
            guard case let .calendar(calendarID, _) = target else { return nil }
            return calendarID
        }

        public var eventID: OMERecord.Event.ID? {
            guard case let .event(eventID) = target else { return nil }
            return eventID
        }

        public var sourceBaselineID: SourceBaselineRecord.ID? {
            switch target {
            case let .calendar(_, sourceBaselineID):
                sourceBaselineID
            case .event:
                changes.sourceProvenance?.sourceBaselineID
            }
        }

        public var canCreateEvent: Bool {
            guard case .calendar = target else { return false }
            return true
        }

        public func availablePages(authoringAccess: AuthoringAccess) -> [Page] {
            var pages: [Page] = [.changes]
            if collaborators != nil {
                pages.append(.collaborators)
            }
            if reviews.canReview(authoringAccess: authoringAccess) {
                pages.append(.reviews)
            }
            return pages
        }

        mutating func reloadCollaboratorsForAuthoringAccess(_ grant: AuthoringGrant?) {
            guard let grant,
                  case .actor = grant.principal,
                  grant.role.canManageCollaborators
            else {
                collaborators = nil
                if selectedPage == .collaborators {
                    selectedPage = .changes
                }
                return
            }
            guard collaborators?.workspaceID != grant.workspaceID else { return }
            collaborators = WorkspaceCollaborators.State(
                workspaceID: grant.workspaceID,
                role: grant.role
            )
        }

    }

    public enum Page: String, CaseIterable, Identifiable {
        case changes
        case collaborators
        case reviews

        public var id: Self { self }

        public func title(for target: OpenMusicEventSourceTarget) -> String {
            switch self {
            case .changes:
                switch target {
                case .calendar:
                    "Changes"
                case .event:
                    "Draft"
                }
            case .collaborators:
                "Collaborators"
            case .reviews:
                "Reviews"
            }
        }
    }

    public enum Action {
        case changes(WorkspaceChanges.Action)
        case collaborators(WorkspaceCollaborators.Action)
        case createEventButtonTapped
        case delegate(Delegate)
        case reviews(WorkspaceReviews.Action)
    }

    public enum Delegate: Equatable, Sendable {
        case createEventRequested(
            sourceBaselineID: SourceBaselineRecord.ID,
            calendarID: OMERecord.Calendar.ID
        )
    }

    @FeatureEnvironment(ComposableAuthoring.AuthoringContext<AuthoringGrant>.self)
    var authoring

    public var body: some Feature {
        Features {
            Scope(\.changes, action: \.changes) {
                WorkspaceChanges()
            }
            Scope(\.reviews, action: \.reviews) {
                WorkspaceReviews()
            }
            Update { state, action in
                switch action {
                case .changes, .collaborators, .reviews:
                    break

                case .createEventButtonTapped:
                    guard case let .calendar(calendarID, sourceBaselineID) = state.target else {
                        return
                    }
                    store.addTask {
                        try store.send(
                            .delegate(
                                .createEventRequested(
                                    sourceBaselineID: sourceBaselineID,
                                    calendarID: calendarID
                                )
                            )
                        )
                    }

                case .delegate:
                    break
                }
            }
        }
        .ifLet(\.collaborators, action: \.collaborators) {
            WorkspaceCollaborators()
        }
        .onChange(of: authoring.grant.wrappedValue, initial: true) { _, grant, state in
            state.reloadCollaboratorsForAuthoringAccess(grant)
            let access = grant?.access ?? .attendee
            if !state.availablePages(authoringAccess: access).contains(state.selectedPage) {
                state.selectedPage = .changes
            }
        }
        .spawn(\.account) {
            Account()
        }
    }
}

public typealias SourceWorkspace = EventWorkspace
public typealias SourceWorkspaceView = EventWorkspaceView

public struct EventWorkspaceView: View {
    @Bindable var store: StoreOf<EventWorkspace>
    @Bindable var accountStore: StoreOf<Account>
    let presentsAccountPresentation: Bool
    let authoringAccess: AuthoringAccess
    @Environment(\.openMusicEventWorkspacePhase) var workspacePhase
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    public init(
        store: StoreOf<EventWorkspace>,
        accountStore: StoreOf<Account>? = nil,
        authoringAccess: AuthoringAccess = .attendee
    ) {
        self.store = store
        self.authoringAccess = authoringAccess
        if let accountStore {
            self.accountStore = accountStore
            self.presentsAccountPresentation = false
        } else {
            self.accountStore = store.spawn(\.account)
            self.presentsAccountPresentation = true
        }
    }

    public var body: some View {
        let changesStore = store.scope(\.changes, action: \.changes)
        @Bindable var reviewsStore = store.scope(\.reviews, action: \.reviews)

        VStack(spacing: 0) {
            switch changesStore.sourceWorkspaceSummary.availability {
            case .available:
                switch store.selectedPage {
                case .changes:
                    WorkspaceChangesView(store: changesStore)

                case .collaborators:
                    if let collaboratorsStore = store.scope(
                        \.collaborators,
                        action: \.collaborators
                    ) {
                        WorkspaceCollaboratorsView(store: collaboratorsStore)
                    }

                case .reviews:
                    WorkspaceReviewsView(store: reviewsStore)
                }

            case .workspaceNeedsPreparation, .notInWorkspace:
                WorkspaceUnavailableView(
                    title: "Workspace couldn't be loaded",
                    message: "Refresh the event and try opening the workspace again."
                )

            case let .unavailable(reason):
                SourceChangeUnavailableView(reason: reason)
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
                            Text(
                                changesStore.sourceWorkspaceSummary.totalCount,
                                format: .number
                            )
                            .font(.title3)
                            .portableMonospacedDigit()
                        }

                        Spacer()

                        if let sourceContext = reviewsStore.sourceContext {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Workspace")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(sourceContext.sourceKind.workspaceTitle)
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                        }
                    }

                    if showsTechnicalDetails,
                       let sourceContext = reviewsStore.sourceContext
                    {
                        WorkspaceActorIdentityView(
                            label: "Workspace owner",
                            identity: reviewsStore.workspaceOwnerIdentity,
                            avatarSize: 32
                        )

                        PortableDisclosureGroup("Technical details") {
                            WorkspaceTechnicalValueView(
                                label: "Source address",
                                value: sourceContext.sourceReference
                            )
                            WorkspaceTechnicalValueView(
                                label: "Provider",
                                value: sourceContext.sourceKind.rawValue
                            )
                            WorkspaceTechnicalValueView(
                                label: "Version",
                                value: sourceContext.sourceRefTitle
                            )
                            if let ownerActorReference = sourceContext.ownerActorReference {
                                WorkspaceTechnicalValueView(
                                    label: "Owner actor ID",
                                    value: ownerActorReference
                                )
                            }
                            if let technicalLocation = sourceContext.technicalLocation {
                                WorkspaceTechnicalValueView(
                                    label: "Source path",
                                    value: technicalLocation
                                )
                            }
                        }
                        .font(.caption)
                    }

                    if let description =
                        changesStore.sourceWorkspaceSummary.outOfTargetInclusionDescription
                    {
                        Text(description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 6)

                let availablePages = store.state.availablePages(
                    authoringAccess: authoringAccess
                )
                if availablePages.count > 1 {
                    Picker("Workspace", selection: $store.selectedPage) {
                        ForEach(availablePages) { page in
                            Text(page.title(for: store.target)).tag(page)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                }

                if store.selectedPage == .changes,
                   changesStore.sourceWorkspaceSummary.totalCount > 0,
                   changesStore.canPublishSourceProposal
                {
                    Button {
                        changesStore.send(.proposeChangesButtonTapped)
                    } label: {
                        Label(
                            workspacePhase.proposalButtonTitle,
                            systemImage: "paperplane"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(
                        !changesStore.state.canProposeChanges(authoringAccess: authoringAccess)
                            || !workspacePhase.canRequestProposalAction
                    )
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
        .sourceChangeRowStyle(OpenMusicEventSourceChangeRowStyle())
        .navigationDestination(isPresented: $reviewsStore.selectedReview.isPresented) {
            if let selectedReview = reviewsStore.selectedReview {
                WorkspaceReviewDetailView(
                    store: reviewsStore,
                    selectedReview: selectedReview
                )
            }
        }
        .toolbar {
            if store.canCreateEvent {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.createEventButtonTapped)
                    } label: {
                        Label("Create Event", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            if store.selectedPage == .reviews, reviewsStore.sourceBaselineID != nil {
                ToolbarItem(placement: .secondaryAction) {
                    Button("Refresh Source", systemImage: "arrow.clockwise") {
                        reviewsStore.send(.refreshSourceButtonTapped)
                    }
                }
            }
        }
        .accountPickerToolbar(store: accountStore)
        .sheet(
            item: presentsAccountPresentation
                ? $accountStore.presentation
                : .constant(nil),
            onDismiss: { accountStore.send(.accountPresentationDismissed) }
        ) { _ in
            AccountPresentationView(store: accountStore)
        }
    }
}
struct TangledPullReviewRow: View {
    let review: TangledPullReview
    let authorIdentity: WorkspaceActorIdentity
    var isClosing = false
    var isDeleting = false
    var isMerging = false
    var closeFailure: WorkspaceReviews.ReviewFailure?
    var deleteFailure: WorkspaceReviews.ReviewFailure?
    var mergeFailure: WorkspaceReviews.ReviewFailure?
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(review.title)
                    .font(.headline)
                    .lineLimit(2)
                    .portableLayoutPriority(1)
                Spacer()
                TangledPullReviewStateChip(state: review.state)
            }

            Text(review.pullRequestMetadataTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            WorkspaceActorHandleView(
                identity: authorIdentity,
                avatarSize: 28
            )

            if isClosing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Closing review")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if isMerging {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Applying changes")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if isDeleting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Deleting review")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let closeFailure {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review could not be closed")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    if showsTechnicalDetails {
                        Text(closeFailure.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .selectableText()
                    }
                }
            }

            if let mergeFailure {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Changes could not be applied")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    if showsTechnicalDetails {
                        Text(mergeFailure.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .selectableText()
                    }
                }
            }

            if let deleteFailure {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review could not be deleted")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    if showsTechnicalDetails {
                        Text(deleteFailure.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .selectableText()
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct TangledPullReviewStateChip: View {
    let state: String

    var body: some View {
        Text(state.tangledPullReviewStateTitle)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(state.tangledPullReviewStateForegroundStyle)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(state.tangledPullReviewStateBackgroundStyle, in: Capsule())
    }
}

private extension TangledPullReview {
    var pullRequestMetadataTitle: String {
        "Submitted \(createdAt.tangledPullReviewCreatedAtTitle)"
    }

    var patchBlobCountTitle: String {
        patchBlobs.count == 1 ? "1 change set" : "\(patchBlobs.count) change sets"
    }

    var commentCountTitle: String {
        commentCount == 1 ? "1 comment" : "\(commentCount) comments"
    }
}

struct TangledPullReviewDetailView: View {
    let review: TangledPullReview
    let authorIdentity: WorkspaceActorIdentity
    let semanticDiffStatus: WorkspaceReviews.SemanticDiffStatus
    var isClosing = false
    var isDeleting = false
    var isMerging = false
    var isBusy = false
    var mergeFailure: WorkspaceReviews.ReviewFailure?
    let onLoadSemanticDiff: () -> Void
    let onMerge: () -> Void
    let onClose: () -> Void
    let onDelete: () -> Void
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    @State var isDeleteConfirmationPresented = false

    var body: some View {
        List {
            Section("Review") {
                WorkspaceActorIdentityView(
                    label: "Submitted by",
                    identity: authorIdentity,
                    avatarSize: 36
                )
                LabeledContent("State", value: review.state.tangledPullReviewStateTitle)
                LabeledContent("Created", value: review.createdAt)
            }

            if isMerging {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Applying changes")
                    }
                    .foregroundStyle(.secondary)
                }
            }

            if let mergeFailure {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Changes could not be applied")
                            .foregroundStyle(.orange)
                        if showsTechnicalDetails {
                            Text(mergeFailure.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .selectableText()
                        }
                    }
                }
            }

            if let body = review.body, !body.isEmpty {
                Section("Description") {
                    Text(body)
                        .selectableText()
                }
            }

            reviewSemanticDiffSections

            if showsTechnicalDetails {
                Section {
                    PortableDisclosureGroup("Technical details") {
                        WorkspaceTechnicalValueView(
                            label: "Review URI",
                            value: review.uri
                        )
                        WorkspaceTechnicalValueView(
                            label: "Author ID",
                            value: review.author
                        )
                        WorkspaceTechnicalValueView(
                            label: "Created at",
                            value: review.createdAt
                        )
                        WorkspaceTechnicalValueView(
                            label: "Target branch",
                            value: review.targetBranch
                        )
                        WorkspaceTechnicalValueView(
                            label: "Target repository ID",
                            value: review.targetRepositoryDID
                        )
                        if let sourceBranch = review.sourceBranch {
                            WorkspaceTechnicalValueView(
                                label: "Source branch",
                                value: sourceBranch
                            )
                        }
                        if let sourceRepositoryDID = review.sourceRepositoryDID {
                            WorkspaceTechnicalValueView(
                                label: "Source repository ID",
                                value: sourceRepositoryDID
                            )
                        }
                    }

                    PortableDisclosureGroup("Patch metadata") {
                        if review.patchBlobs.isEmpty {
                            Text("No patch metadata")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(review.patchBlobs) { patchBlob in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Round \(patchBlob.index)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    WorkspaceTechnicalValueView(
                                        label: "Blob ID",
                                        value: patchBlob.cid
                                    )
                                    WorkspaceTechnicalValueView(
                                        label: "Media type",
                                        value: patchBlob.mimeType
                                    )
                                    if let size = patchBlob.size {
                                        WorkspaceTechnicalValueView(
                                            label: "Size",
                                            value: "\(size) bytes"
                                        )
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    PortableDisclosureGroup("Raw review") {
                        Text(review.rawReviewText)
                            .font(.caption)
                            .monospaced()
                            .selectableText()
                    }
                }
            }

        }
        .navigationTitle(review.title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sourceChangeRowStyle(OpenMusicEventSourceChangeRowStyle())
        .portableSafeAreaTopInset(spacing: 0) {
            VStack(spacing: 0) {
                Button {
                    onMerge()
                } label: {
                    Label(isMerging ? "Merging" : "Merge", systemImage: "arrow.triangle.merge")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isBusy)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()
            }
            .background(.background)
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button(
                        isClosing ? "Closing review" : "Close review",
                        role: .destructive
                    ) {
                        onClose()
                    }
                    .disabled(isBusy)

                    Button(
                        isDeleting ? "Deleting review" : "Delete review permanently",
                        role: .destructive
                    ) {
                        isDeleteConfirmationPresented = true
                    }
                    .disabled(isBusy)
                } label: {
                    Label("Review actions", systemImage: "ellipsis.circle")
                }
                .disabled(isBusy)
            }
        }
        .confirmationDialog(
            "Delete this review permanently?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Review", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .onAppear {
            onLoadSemanticDiff()
        }
    }

    @ViewBuilder
    private var reviewSemanticDiffSections: some View {
        switch semanticDiffStatus {
        case let .failed(failure):
            Section("What changed") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review changes could not be loaded")
                    if showsTechnicalDetails {
                        Text(failure.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .selectableText()
                    }
                }

                Button("Try Again") {
                    onLoadSemanticDiff()
                }
            }

        case let .loaded(diff):
            if diff.totalCount == 0 {
                Section("What changed") {
                    Text("No semantic changes")
                        .foregroundStyle(.secondary)
                }
            } else {
                SourceProposalSummarySections(
                    groups: diff.groups,
                    recordComparisons: diff.recordComparisons
                )
                SourceFileAttributionSection(attributions: diff.sourceFileAttributions)
            }

        case .loading:
            Section("What changed") {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading review changes")
                }
            }

        case .notLoaded:
            Section("What changed") {
                Button("Load Review Changes") {
                    onLoadSemanticDiff()
                }
            }
        }
    }
}

struct WorkspaceUnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Text(title)
        } description: {
            Text(message)
        }
    }
}

struct WorkspaceUnavailableSection: View {
    let title: String
    let message: String

    var body: some View {
        Section("Workspace") {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

public enum SourceChangesScope: Equatable, Sendable {
    case event(OMERecord.Event.ID)
    case source(
        sourceBaselineID: SourceBaselineRecord.ID,
        calendarID: OMERecord.Calendar.ID
    )
}

public enum SourceChangesAvailability: Equatable, Sendable {
    case available
    case workspaceNeedsPreparation
    case notInWorkspace
    case unavailable(SourceChangeSummary.UnavailableReason)

    public init(_ availability: EventWorkspaceSummary.Availability) {
        switch availability {
        case .available:
            self = .available
        case .workspaceNeedsPreparation:
            self = .workspaceNeedsPreparation
        case .notInWorkspace:
            self = .notInWorkspace
        case let .unavailable(reason):
            self = .unavailable(reason)
        }
    }

    public init(_ availability: SourceEditSummary.Availability) {
        switch availability {
        case .available:
            self = .available
        case .missingBaseline:
            self = .workspaceNeedsPreparation
        case let .unavailable(reason):
            self = .unavailable(reason)
        }
    }

    public init(_ availability: SourceChangeSummary.Availability) {
        switch availability {
        case .available:
            self = .available
        case let .unavailable(reason):
            self = .unavailable(reason)
        }
    }

    var eventWorkspaceAvailability: EventWorkspaceSummary.Availability {
        switch self {
        case .available:
            .available
        case .workspaceNeedsPreparation:
            .workspaceNeedsPreparation
        case .notInWorkspace:
            .notInWorkspace
        case let .unavailable(reason):
            .unavailable(reason)
        }
    }
}

public enum SourceChangesReviewMode: Equatable, Sendable {
    case proposal
    case workspace
}

struct SourceWorkspaceSourceContext: Equatable, Sendable {
    var detailTitle: String
    var sourceKind: OMERecord.SourceDatabaseInsertion.SourceKind
    var sourceReference: String
    var sourceRefTitle: String
    var ownerActorReference: String?
    var technicalLocation: String?

    init(
        detailTitle: String,
        sourceKind: OMERecord.SourceDatabaseInsertion.SourceKind,
        sourceReference: String,
        sourceRefTitle: String,
        ownerActorReference: String? = nil,
        technicalLocation: String? = nil
    ) {
        self.detailTitle = detailTitle
        self.sourceKind = sourceKind
        self.sourceReference = sourceReference
        self.sourceRefTitle = sourceRefTitle
        self.ownerActorReference = ownerActorReference
        self.technicalLocation = technicalLocation
    }
}

public struct WorkspaceTechnicalValueView: View {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .selectableText()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SourceIndicatorView: View {
    let sourceContext: SourceWorkspaceSourceContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(sourceContext.sourceKind.workspaceTitle, systemImage: "folder")

            Text(sourceContext.detailTitle)
                .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            PortableDisclosureGroup("Technical details") {
                WorkspaceTechnicalValueView(
                    label: "Source address",
                    value: sourceContext.sourceReference
                )
                WorkspaceTechnicalValueView(
                    label: "Provider",
                    value: sourceContext.sourceKind.rawValue
                )
                WorkspaceTechnicalValueView(
                    label: "Version",
                    value: sourceContext.sourceRefTitle
                )
                if let ownerActorReference = sourceContext.ownerActorReference {
                    WorkspaceTechnicalValueView(
                        label: "Owner actor ID",
                        value: ownerActorReference
                    )
                }
                if let technicalLocation = sourceContext.technicalLocation {
                    WorkspaceTechnicalValueView(
                        label: "Source path",
                        value: technicalLocation
                    )
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }
}

public struct WorkspacePublicationStatusView: View {
    let phase: WorkspacePhase<SourcePatch>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    public init(phase: WorkspacePhase<SourcePatch>) {
        self.phase = phase
    }

    public var body: some View {
        switch phase {
        case .inactive, .ready(.canonical):
            EmptyView()

        case .ready(.proposal):
            Label("Proposal ready for more changes", systemImage: "checkmark.circle")
                .foregroundStyle(.green)

        case .preparingSource:
            progress("Preparing workspace")

        case .capturingSubmission:
            progress("Capturing current changes")

        case .publishing:
            progress("Sending changes for review")

        case .reconciling:
            progress("Reconciling source changes")

        case let .sourcePreparationFailed(failure),
             let .submissionCaptureFailed(_, _, failure),
             let .publicationFailed(_, failure),
             let .reconciliationFailed(_, failure):
            VStack(alignment: .leading, spacing: 4) {
                Label("Workspace operation failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                if showsTechnicalDetails {
                    Text(failure.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .selectableText()
                }
            }

        case .publicationInterrupted:
            Label("Sending was interrupted", systemImage: "pause.circle")
                .foregroundStyle(.orange)

        case .stale:
            Label("The source moved; reconcile before sending", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
        }
    }

    private func progress(_ title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(title)
        }
        .foregroundStyle(.secondary)
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
                Section("Title") {
                    TextField(
                        "Title",
                        text: Binding(
                            get: { store.title },
                            set: { store.send(.titleChanged($0)) }
                        )
                    )
                }

                Section("Description") {
                    PortableTextField(
                        "Description",
                        text: Binding(
                            get: { store.description },
                            set: { store.send(.descriptionChanged($0)) }
                        ),
                        axis: .vertical
                    )
                    .portableLineLimit(4...8)
                }

                SourceProposalSummarySections(
                    groups: store.groups,
                    recordComparisons: store.recordComparisons
                )
            }
            .navigationTitle("Send changes for review")
            .sourceChangeRowStyle(OpenMusicEventSourceChangeRowStyle())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        store.send(.cancelButtonTapped)
                    } label: {
                        Label("Close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    SubmitButton(
                        .propose,
                        isInProgress: false,
                        isDisabled: store.proposalTitle == nil
                    ) {
                        store.send(.createProposalButtonTapped)
                    }
                }
            }
        }
    }
}

private extension WorkspacePhase where ChangeSet == SourcePatch {
    var proposalButtonTitle: String {
        switch self {
        case .ready(.canonical):
            "Propose"
        case .ready(.proposal):
            "Update Proposal"
        case .publicationFailed, .publicationInterrupted:
            "Retry"
        case .reconciliationFailed, .stale:
            "Reconcile"
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

enum ExistingProposalsState: Equatable, Sendable {
    case failed(String)
    case loaded([ExistingProposalSummary])
    case unavailable
}

struct ExistingProposalSummary: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var subtitle: String?
}

struct ExistingProposalsSection: View {
    var title = "Other Proposed Changes"
    var emptyTitle = "No other proposed changes"
    let state: ExistingProposalsState

    var body: some View {
        Section(title) {
            switch state {
            case let .failed(message):
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(title) couldn't be loaded")
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .selectableText()
                }

            case let .loaded(proposals):
                if proposals.isEmpty {
                    Text(emptyTitle)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(proposals) { proposal in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(proposal.title)
                            if let subtitle = proposal.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

            case .unavailable:
                Text("\(title) are unavailable.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

public struct SourceProposalSummarySections: View {
    let groups: [SourceChangeGroup]
    let recordComparisons: SourceRecordComparisons

    public init(
        groups: [SourceChangeGroup],
        recordComparisons: SourceRecordComparisons = .empty
    ) {
        self.groups = groups
        self.recordComparisons = recordComparisons
    }

    init(summary: EventWorkspaceSummary) {
        self.groups = summary.groups
        self.recordComparisons = summary.recordComparisons
    }

    public var body: some View {
        if groups.contains(where: { !$0.records.isEmpty }) {
            Section("What will change") {
                ForEach(groups.filter { !$0.records.isEmpty }) { group in
                    SourceChangeGroupDisclosure(
                        group: group,
                        recordComparisons: recordComparisons
                    )
                }
            }
        } else {
            Section {
                Label("No edit summary available", systemImage: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SourceFileAttributionSection: View {
    let attributions: [SourceFileAttribution]
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        if !attributions.isEmpty {
            Section("Source files") {
                ForEach(attributions) { attribution in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Label {
                                Text(attribution.filePath)
                                    .lineLimit(2)
                                    .selectableText()
                            } icon: {
                                Image(systemName: "doc.text")
                            }

                            Spacer(minLength: 8)

                            Text(attribution.recordCountTitle)
                                .font(.caption)
                                .portableMonospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        if showsTechnicalDetails {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(attribution.recordChangeIDs, id: \.self) { recordChangeID in
                                    Text(String(describing: recordChangeID))
                                        .font(.caption2)
                                        .monospaced()
                                        .foregroundStyle(.secondary)
                                        .selectableText()
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private extension SourceFileAttribution {
    var recordCountTitle: String {
        if recordChangeIDs.count == 1 {
            return "1 record"
        }
        return "\(recordChangeIDs.count) records"
    }
}

struct SourceChangeSummarySection: View {
    let groups: [SourceChangeGroup]
    let recordComparisons: SourceRecordComparisons

    init(
        groups: [SourceChangeGroup],
        recordComparisons: SourceRecordComparisons = .empty
    ) {
        self.groups = groups
        self.recordComparisons = recordComparisons
    }

    var body: some View {
        Section("What changed") {
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

    init(
        group: SourceChangeGroup,
        recordComparisons: SourceRecordComparisons = .empty
    ) {
        self.group = group
        self.recordComparisons = recordComparisons
    }

    var body: some View {
        PortableDisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(kinds, id: \.self) { kind in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(kind.title)
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
            .padding(.top, 4)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.displayName)
                    Text(group.totalCount, format: .number)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                SourceChangeCountBadges(group: group)
            }
        }
    }

    private var kinds: [SourceRecordChangeKind] {
        SourceRecordChangeKind.allCases.filter { kind in
            group.records.contains { $0.kind == kind }
        }
    }

    private func records(for kind: SourceRecordChangeKind) -> [SourceRecordChange] {
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
        .foregroundStyle(kind.badgeForegroundStyle)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(kind.badgeBackgroundStyle, in: Capsule())
        .portableAccessibilityElement()
        .accessibilityLabel("\(count) \(kind.title)")
    }
}

private extension SourceRecordChange {
    func matches(eventID: OMERecord.Event.ID) -> Bool {
        primaryKeyValues.first { $0.columnName == "organizerID" }?.value
            == String(describing: eventID.organizerID).databaseValue
            && primaryKeyValues.first { $0.columnName == "eventID" }?.value
                == eventID.eventID.rawValue.rawValue.databaseValue
    }
}

private extension Array where Element == SourceChangeGroup {
    func prioritizing(target: OpenMusicEventSourceTarget) -> Self {
        switch target {
        case .calendar:
            self

        case let .event(eventID):
            map { group in
                var group = group
                let focusedRecords = group.records.filter { $0.matches(eventID: eventID) }
                let otherRecords = group.records.filter { !$0.matches(eventID: eventID) }
                group.records = focusedRecords + otherRecords
                return group
            }
        }
    }
}

private extension OMERecord.SourceDatabaseInsertion.SourceKind {
    var workspaceTitle: String {
        switch self {
        case .local:
            "Local source"
        case .tangled:
            "Shared source"
        }
    }
}

private extension EventSourceProvenanceRecord {
    var sourceRefTitle: String {
        ref ?? "default version"
    }
}

extension WorkspaceReviews.SemanticDiff {
    static func reviewBranchDiff(
        target: OpenMusicEventSourceTarget,
        review: TangledPullReview,
        sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance,
        sourceSnapshot: TangledPullReviewSourceSnapshotClient
    ) async throws -> Self {
        guard let sourceBranch = review.sourceBranch?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !sourceBranch.isEmpty else {
            throw TangledPullReviewSourceSnapshotError.missingSourceBranch(review.id)
        }

        let scratchRootURL = FileManager.default.temporaryDirectory
            .appending(
                path: "ome-review-semantic-diff-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            .standardizedFileURL
        try FileManager.default.createDirectory(
            at: scratchRootURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: scratchRootURL) }

        let targetInsertion = try await sourceSnapshot.insertion(
            TangledPullReviewSourceSnapshotRequest(
                organizerID: target.organizerID,
                ref: review.targetBranch,
                sourceProvenance: sourceProvenance
            )
        )
        let reviewInsertion = try await sourceSnapshot.insertion(
            TangledPullReviewSourceSnapshotRequest(
                organizerID: target.organizerID,
                ref: sourceBranch,
                sourceProvenance: sourceProvenance
            )
        )

        // These short-lived databases compare the proposal branch with its remote target branch.
        // A workspace may already have advanced its own reference to the proposal, so the live
        // workspace baseline cannot answer what the pull request changes.
        let targetDatabaseURL = scratchRootURL
            .appending(path: "target.sqlite")
        let targetDatabase = try DatabasePool(path: targetDatabaseURL.path)
        let reviewDatabaseURL = scratchRootURL
            .appending(path: "review.sqlite")
        let reviewDatabase = try DatabasePool(path: reviewDatabaseURL.path)
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(targetDatabase)
        try migrator.migrate(reviewDatabase)

        try await withDependencies {
            $0.sourceReferenceDatabase = .scratch(rootURL: scratchRootURL)
            $0.sourceReferenceDatabaseMigrator = .openMusicEvent
            $0.localImageFileStore = .scratch(rootURL: scratchRootURL)
        } operation: {
            try await targetInsertion.insert(into: targetDatabase)
            try await reviewInsertion.insert(into: reviewDatabase)
        }

        let reviewSession = try SourceEditingSession(
            mainDatabase: reviewDatabase,
            baselineDatabasePath: targetDatabaseURL.path
        )
        let semanticDiff = try await reviewSession.database.read { db in
            let summary = try openMusicEventSourceEditSummary(
                in: db,
                baselineSchemaName: SourceEditingSession.baselineSchemaName
            )
            switch summary.availability {
            case .available:
                let workspaceSummary = SourceWorkspaceSummary(
                    target: target,
                    changeSummary: summary
                )
                let sourceFileAttributions = try openMusicEventSourceFileAttributions(
                    groups: workspaceSummary.groups,
                    recordComparisons: workspaceSummary.recordComparisons,
                    in: db
                )
                return Self(
                    groups: workspaceSummary.groups,
                    recordComparisons: workspaceSummary.recordComparisons,
                    sourceFileAttributions: sourceFileAttributions
                )

            case let .unavailable(reason):
                throw TangledPullReviewSemanticDiffError.unavailable(reason)
            }
        }

        return semanticDiff
    }
}

private enum TangledPullReviewSemanticDiffError: Error, CustomStringConvertible {
    case unavailable(SourceChangeSummary.UnavailableReason)

    var description: String {
        switch self {
        case let .unavailable(reason):
            "Review changes are unavailable: \(reason)."
        }
    }
}

private extension SourceReferenceDatabaseClient {
    static func scratch(rootURL: URL) -> Self {
        Self(
            url: { provenance in
                scratchReferenceDatabaseURL(rootURL: rootURL, provenance: provenance)
            },
            prepareForImport: { provenance in
                let databaseURL = scratchReferenceDatabaseURL(
                    rootURL: rootURL,
                    provenance: provenance
                )
                return try SourceReferenceDatabaseClient.stagedImport(at: databaseURL)
            },
            existing: { provenance in
                let databaseURL = scratchReferenceDatabaseURL(
                    rootURL: rootURL,
                    provenance: provenance
                )
                guard FileManager.default.fileExists(atPath: databaseURL.path) else {
                    return nil
                }
                let database = try defaultBaselineDatabase(path: databaseURL.path)
                try SourceReferenceDatabaseMigrator.openMusicEvent.migrate(database)
                return database
            }
        )
    }
}

private extension LocalImageFileStoreClient {
    static func scratch(rootURL: URL) -> Self {
        Self { assetKey, data, _ in
            let imageRootURL = rootURL.appending(path: "images", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: imageRootURL,
                withIntermediateDirectories: true
            )
            let imageURL = imageRootURL
                .appending(path: assetKey.sourceReviewScratchFileComponent)
                .appendingPathExtension("data")
            try data.write(to: imageURL, options: .atomic)
            return imageURL
        }
    }
}

private func scratchReferenceDatabaseURL(
    rootURL: URL,
    provenance: OME.SourceDatabaseInsertion.SourceProvenance
) -> URL {
    let key = [
        provenance.kind.rawValue,
        provenance.reference,
        provenance.ref ?? "",
    ]
    .joined(separator: "\u{1F}")
    let encodedKey = Data(key.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return rootURL
        .appending(path: "references", directoryHint: .isDirectory)
        .appending(path: encodedKey)
        .appendingPathExtension("sqlite")
}

extension String {
    var sourceReviewScratchFileComponent: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let value = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return value.isEmpty ? UUID().uuidString : value
    }
}

private extension SourceChangesReviewMode {
    var noChangesTitle: String {
        switch self {
        case .proposal:
            "No changes to propose"
        case .workspace:
            "No changes"
        }
    }

    var notGeneratedTitle: String {
        switch self {
        case .proposal:
            "Check your changes before sending them for review"
        case .workspace:
            "Check your changes"
        }
    }

    var readyTitle: String {
        switch self {
        case .proposal:
            "Ready to send for review"
        case .workspace:
            "Changes checked"
        }
    }

    var sectionSystemImage: String {
        switch self {
        case .proposal:
            "doc.text"
        case .workspace:
            "folder"
        }
    }

    var sectionTitle: String {
        switch self {
        case .proposal:
            "For review"
        case .workspace:
            "Your changes"
        }
    }
}

extension String {
    var tangledPullReviewCreatedAtDate: Date? {
        ISO8601DateFormatter().date(from: self)
    }

    var tangledPullReviewCreatedAtTitle: String {
        guard let date = tangledPullReviewCreatedAtDate else { return self }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var sourceReviewPreview: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 180 else { return trimmed }
        return "\(String(trimmed.prefix(180)))..."
    }

    var tangledPullReviewStateTitle: String {
        switch self {
        case "open":
            "Open"
        case "closed":
            "Closed"
        case "merged":
            "Applied"
        default:
            self
        }
    }

    var tangledPullReviewStateBackgroundStyle: Color {
        switch self {
        case "open":
            Color.green.opacity(0.16)
        case "closed":
            Color.orange.opacity(0.18)
        case "merged":
            Color.blue.opacity(0.16)
        default:
            Color.secondary.opacity(0.12)
        }
    }

    var tangledPullReviewStateForegroundStyle: Color {
        switch self {
        case "open":
            .green
        case "closed":
            .orange
        case "merged":
            .blue
        default:
            .secondary
        }
    }
}

struct SourceChangeGroupSections: View {
    let group: SourceChangeGroup
    let recordComparisons: SourceRecordComparisons

    init(
        group: SourceChangeGroup,
        recordComparisons: SourceRecordComparisons = .empty
    ) {
        self.group = group
        self.recordComparisons = recordComparisons
    }

    var body: some View {
        ForEach(kinds, id: \.self) { kind in
            SourceChangeKindSection(
                title: "\(kind.title) \(group.displayName)",
                group: group,
                records: records(for: kind),
                recordComparisons: recordComparisons
            )
        }
    }

    private var kinds: [SourceRecordChangeKind] {
        SourceRecordChangeKind.allCases.filter { kind in
            group.records.contains { $0.kind == kind }
        }
    }

    private func records(for kind: SourceRecordChangeKind) -> [SourceRecordChange] {
        group.records.filter { $0.kind == kind }
    }
}

struct SourceChangeKindSection: View {
    let title: String
    let group: SourceChangeGroup
    let records: [SourceRecordChange]
    let recordComparisons: SourceRecordComparisons

    var body: some View {
        Section(title) {
            ForEach(records) { record in
                SourceRecordChangeRow(
                    group: group,
                    record: record,
                    comparison: recordComparisons[record]
                )
            }
        }
    }
}

struct SourceChangeRowStyleConfiguration {
    let group: SourceChangeGroup
    let record: SourceRecordChange
    let comparison: AnySourceRecordComparison?
}

protocol SourceChangeRowStyle {
    associatedtype Body: View

    @ViewBuilder
    func makeBody(configuration: SourceChangeRowStyleConfiguration) -> Body
}

struct AnySourceChangeRowStyle: @unchecked Sendable {
    private var body: (SourceChangeRowStyleConfiguration) -> AnyView

    init<Style: SourceChangeRowStyle>(_ style: Style) {
        self.body = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: SourceChangeRowStyleConfiguration) -> AnyView {
        body(configuration)
    }
}

private struct SourceChangeRowStyleKey: EnvironmentKey {
    static let defaultValue = AnySourceChangeRowStyle(DefaultSourceChangeRowStyle())
}

extension EnvironmentValues {
    var sourceChangeRowStyle: AnySourceChangeRowStyle {
        get { self[SourceChangeRowStyleKey.self] }
        set { self[SourceChangeRowStyleKey.self] = newValue }
    }
}

extension View {
    func sourceChangeRowStyle<Style: SourceChangeRowStyle>(_ style: Style) -> some View {
        environment(\.sourceChangeRowStyle, AnySourceChangeRowStyle(style))
    }
}

struct SourceRecordChangeRow: View {
    @Environment(\.sourceChangeRowStyle) var sourceChangeRowStyle

    let group: SourceChangeGroup
    let record: SourceRecordChange
    let comparison: AnySourceRecordComparison?

    var body: some View {
        sourceChangeRowStyle.makeBody(
            configuration: SourceChangeRowStyleConfiguration(
                group: group,
                record: record,
                comparison: comparison
            )
        )
    }
}

struct DefaultSourceChangeRowStyle: SourceChangeRowStyle {
    func makeBody(configuration: SourceChangeRowStyleConfiguration) -> some View {
        DefaultSourceRecordChangeRow(record: configuration.record)
    }
}

struct OpenMusicEventSourceChangeRowStyle: SourceChangeRowStyle {
    func makeBody(configuration: SourceChangeRowStyleConfiguration) -> some View {
        if let eventComparison = configuration.comparison?.as(OME.Event.self) {
            SourceEventChangeRow(comparison: eventComparison)
        } else if let calendarComparison = configuration.comparison?.as(OME.Calendar.self) {
            SourceCalendarChangeRow(comparison: calendarComparison)
        } else if let stageComparison = configuration.comparison?.as(OME.Stage.self) {
            SourceStageChangeRow(comparison: stageComparison)
        } else if let scheduleComparison = configuration.comparison?.as(OME.Schedule.self) {
            SourceScheduleChangeRow(comparison: scheduleComparison)
        } else if let performanceComparison = configuration.comparison?.as(OME.Performance.self) {
            SourcePerformanceChangeRow(comparison: performanceComparison)
        } else if let contributorComparison = configuration.comparison?.as(OME.Contributor.self) {
            SourceContributorChangeRow(content: .comparison(contributorComparison))
        } else if let channelComparison = configuration.comparison?.as(OME.Channel.self) {
            SourceChannelChangeRow(comparison: channelComparison)
        } else if let posterComparison = configuration.comparison?.as(OME.Poster.self) {
            SourcePosterChangeRow(comparison: posterComparison)
        } else if configuration.group.id == OME.Contributor.tableName {
            SourceContributorChangeRow(content: .record(configuration.record))
        } else {
            DefaultSourceChangeRowStyle().makeBody(configuration: configuration)
        }
    }
}

struct DefaultSourceRecordChangeRow: View {
    let record: SourceRecordChange
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showsTechnicalDetails {
                    Text(record.primaryKeySummary)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
            }

            if showsTechnicalDetails {
                if let recordDiff = record.recordDiff, !recordDiff.isEmpty {
                    Text(recordDiff)
                        .font(.caption)
                        .monospaced()
                        .selectableText()
                } else {
                    ForEach(record.fieldChanges) { change in
                        SourceFieldChangeRow(change: change)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SourceEventChangeRow: View {
    let comparison: SourceRecordComparison<OME.Event>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        SourceTypedRecordChangeRow(
            comparison: comparison,
            title: title,
            recordTitle: "Event",
            fields: [
                .init(title: "Name", columnName: "name", keyPath: \.name),
                .init(title: "Description", columnName: "description", optionalKeyPath: \.description),
                .init(title: "Start Date", columnName: "startDate", optionalKeyPath: \.startDate) {
                    $0.sourceChangeDisplayValue
                },
                .init(title: "End Date", columnName: "endDate", optionalKeyPath: \.endDate) {
                    $0.sourceChangeDisplayValue
                },
                .init(title: "Status", columnName: "status", optionalKeyPath: \.status) {
                    $0.sourceChangeDisplayValue
                },
                .init(title: "Mode", columnName: "mode", optionalKeyPath: \.mode) {
                    $0.sourceChangeDisplayValue
                },
                .init(title: "Time Zone", columnName: "timeZone", keyPath: \.timeZone) {
                    $0.identifier
                },
                .init(title: "Images", columnName: "images", optionalKeyPath: \.images) {
                    $0.sourceChangeImageCountValue
                },
                .init(title: "Locations", columnName: "locations", optionalKeyPath: \.locations) {
                    $0.sourceChangeCountValue(singular: "location", plural: "locations")
                },
                .init(title: "Links", columnName: "uris", optionalKeyPath: \.uris) {
                    $0.sourceChangeCountValue(singular: "link", plural: "links")
                },
                .init(title: "Contact Numbers", columnName: "contactNumbers", optionalKeyPath: \.contactNumbers) {
                    $0.sourceChangeCountValue(singular: "contact number", plural: "contact numbers")
                },
                .init(title: "Reporting Links", columnName: "reportingLinks", optionalKeyPath: \.reportingLinks) {
                    $0.sourceChangeCountValue(singular: "reporting link", plural: "reporting links")
                },
                .init(
                    title: "Owner",
                    columnName: "owner",
                    optionalKeyPath: \.owner,
                    isTechnical: true
                ) {
                    $0.description
                },
            ]
        )
    }

    private var title: String {
        comparison.right?.name
            ?? comparison.left?.name
            ?? comparison.change.titleFallback(
                "Event",
                showsTechnicalDetails: showsTechnicalDetails
            )
    }
}

struct SourceCalendarChangeRow: View {
    let comparison: SourceRecordComparison<OME.Calendar>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        SourceTypedRecordChangeRow(
            comparison: comparison,
            title: title,
            recordTitle: "Calendar",
            fields: [
                .init(title: "Name", columnName: "name", keyPath: \.name),
                .init(title: "Description", columnName: "description", optionalKeyPath: \.description),
                .init(title: "Images", columnName: "images", optionalKeyPath: \.images) {
                    $0.sourceChangeImageCountValue
                },
            ]
        )
    }

    private var title: String {
        comparison.right?.name
            ?? comparison.left?.name
            ?? comparison.change.titleFallback(
                "Calendar",
                showsTechnicalDetails: showsTechnicalDetails
            )
    }
}

struct SourceStageChangeRow: View {
    let comparison: SourceRecordComparison<OME.Stage>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        SourceTypedRecordChangeRow(
            comparison: comparison,
            title: title,
            recordTitle: "Stage",
            fields: [
                .init(title: "Name", columnName: "name", keyPath: \.name),
                .init(title: "Color", columnName: "color", keyPath: \.color) {
                    $0.sourceChangeDisplayValue
                },
                .init(title: "Category", columnName: "category", optionalKeyPath: \.category) {
                    $0.rawValue
                },
                .init(title: "Sort Index", columnName: "sortIndex", optionalKeyPath: \.sortIndex) {
                    "\($0)"
                },
                .init(title: "Images", columnName: "images", optionalKeyPath: \.images) {
                    $0.sourceChangeImageCountValue
                },
                .init(title: "System Icon", columnName: "systemIconName", optionalKeyPath: \.systemIconName),
                .init(title: "Icon Shortcode", columnName: "iconShortCode", optionalKeyPath: \.iconShortCode),
                .init(title: "Lineup", columnName: "lineup", optionalKeyPath: \.lineup) {
                    $0.sourceChangeCountValue(singular: "lineup artist", plural: "lineup artists")
                },
            ]
        )
    }

    private var title: String {
        comparison.right?.name
            ?? comparison.left?.name
            ?? comparison.change.titleFallback(
                "Stage",
                showsTechnicalDetails: showsTechnicalDetails
            )
    }
}

struct SourceScheduleChangeRow: View {
    let comparison: SourceRecordComparison<OME.Schedule>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        SourceTypedRecordChangeRow(
            comparison: comparison,
            title: title,
            recordTitle: "Schedule",
            fields: [
                .init(title: "Date", columnName: "date", keyPath: \.date) {
                    $0.sourceChangeDisplayValue
                },
                .init(title: "Starts", columnName: "startsAt", optionalKeyPath: \.startsAt) {
                    $0.sourceChangeTimeValue
                },
                .init(title: "Ends", columnName: "endsAt", optionalKeyPath: \.endsAt) {
                    $0.sourceChangeTimeValue
                },
                .init(title: "Title", columnName: "customTitle", optionalKeyPath: \.customTitle),
            ]
        )
    }

    private var title: String {
        comparison.right?.customTitle
            ?? comparison.left?.customTitle
            ?? comparison.right?.date.sourceChangeDisplayValue
            ?? comparison.left?.date.sourceChangeDisplayValue
            ?? comparison.change.titleFallback(
                "Schedule",
                showsTechnicalDetails: showsTechnicalDetails
            )
    }
}

struct SourcePerformanceChangeRow: View {
    let comparison: SourceRecordComparison<OME.Performance>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SourceChangeKindBadge(kind: comparison.change.kind)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                    Text("Performance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldRows
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var fieldRows: some View {
        switch comparison.change.kind {
        case .modified:
            SourceComparisonValueRow(
                title: "Title",
                comparison: comparison,
                keyPath: \.title
            )
            SourceComparisonValueRow(
                title: "Time",
                comparison: comparison,
                keyPath: \.sourcePerformanceTimeRange
            )
            SourceComparisonValueRow(
                title: "Stage",
                comparison: comparison,
                keyPath: \.stageID
            ) {
                $0.sourceChangeDisplayValue
            }
            SourceComparisonValueRow(
                title: "Schedule",
                comparison: comparison,
                optionalKeyPath: \.scheduleID
            ) {
                $0.sourceChangeDisplayValue
            }
            SourceComparisonValueRow(
                title: "Description",
                comparison: comparison,
                optionalKeyPath: \.description
            )
            SourceComparisonValueRow(
                title: "Recordings",
                comparison: comparison,
                keyPath: \.recordings
            ) {
                $0.sourceChangeCountValue
            }

        case .added:
            valueRows(side: .right)

        case .deleted:
            valueRows(side: .left)
        }
    }

    @ViewBuilder
    private func valueRows(side: SourceRecordValueSide) -> some View {
        SourceRecordValueRow(
            title: "Title",
            comparison: comparison,
            side: side,
            keyPath: \.title
        )
        SourceRecordValueRow(
            title: "Time",
            comparison: comparison,
            side: side,
            keyPath: \.sourcePerformanceTimeRange
        )
        SourceRecordValueRow(
            title: "Stage",
            comparison: comparison,
            side: side,
            keyPath: \.stageID
        ) {
            $0.sourceChangeDisplayValue
        }
        SourceRecordValueRow(
            title: "Schedule",
            comparison: comparison,
            side: side,
            optionalKeyPath: \.scheduleID
        ) {
            $0.sourceChangeDisplayValue
        }
        SourceRecordValueRow(
            title: "Description",
            comparison: comparison,
            side: side,
            optionalKeyPath: \.description
        )
        SourceRecordValueRow(
            title: "Recordings",
            comparison: comparison,
            side: side,
            keyPath: \.recordings
        ) {
            $0.sourceChangeCountValue
        }
    }

    private var title: String {
        comparison.right?.title
            ?? comparison.left?.title
            ?? comparison.change.titleFallback(
                "Performance",
                showsTechnicalDetails: showsTechnicalDetails
            )
    }
}

struct SourceContributorChangeRow: View {
    enum Content {
        case comparison(SourceRecordComparison<OME.Contributor>)
        case record(SourceRecordChange)
    }

    let content: Content
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SourceChangeKindBadge(kind: change.kind)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                    Text("Contributor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldRows
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var fieldRows: some View {
        switch content {
        case let .comparison(comparison):
            switch comparison.change.kind {
            case .modified:
                contributorComparisonRows(comparison)
            case .added:
                contributorValueRows(comparison, side: .right)
            case .deleted:
                contributorValueRows(comparison, side: .left)
            }

        case let .record(record):
            switch record.kind {
            case .modified:
                rawContributorComparisonRows(record)
            case .added:
                rawContributorValueRows(record, side: .right)
            case .deleted:
                rawContributorValueRows(record, side: .left)
            }
        }
    }

    @ViewBuilder
    private func contributorComparisonRows(
        _ comparison: SourceRecordComparison<OME.Contributor>
    ) -> some View {
        SourceComparisonValueRow(
            title: "Name",
            comparison: comparison,
            keyPath: \.name
        )
        if showsTechnicalDetails {
            SourceComparisonValueRow(
                title: "DID",
                comparison: comparison,
                optionalKeyPath: \.did
            ) {
                $0.description
            }
        }
        SourceComparisonValueRow(
            title: "Bio",
            comparison: comparison,
            optionalKeyPath: \.bio
        )
        SourceComparisonValueRow(
            title: "Images",
            comparison: comparison,
            optionalKeyPath: \.images
        ) {
            $0.sourceChangeImageCountValue
        }
        SourceComparisonValueRow(
            title: "Links",
            comparison: comparison,
            optionalKeyPath: \.links
        ) {
            $0.sourceChangeLinkCountValue
        }
    }

    @ViewBuilder
    private func contributorValueRows(
        _ comparison: SourceRecordComparison<OME.Contributor>,
        side: SourceRecordValueSide
    ) -> some View {
        SourceRecordValueRow(
            title: "Name",
            comparison: comparison,
            side: side,
            keyPath: \.name
        )
        if showsTechnicalDetails {
            SourceRecordValueRow(
                title: "DID",
                comparison: comparison,
                side: side,
                optionalKeyPath: \.did
            ) {
                $0.description
            }
        }
        SourceRecordValueRow(
            title: "Bio",
            comparison: comparison,
            side: side,
            optionalKeyPath: \.bio
        )
        SourceRecordValueRow(
            title: "Images",
            comparison: comparison,
            side: side,
            optionalKeyPath: \.images
        ) {
            $0.sourceChangeImageCountValue
        }
        SourceRecordValueRow(
            title: "Links",
            comparison: comparison,
            side: side,
            optionalKeyPath: \.links
        ) {
            $0.sourceChangeLinkCountValue
        }
    }

    @ViewBuilder
    private func rawContributorComparisonRows(_ record: SourceRecordChange) -> some View {
        SourceDatabaseFieldComparisonRow(
            title: "Name",
            record: record,
            columnName: "name"
        ) {
            $0.sourcePlainStringDisplayValue
        }
        if showsTechnicalDetails {
            SourceDatabaseFieldComparisonRow(
                title: "DID",
                record: record,
                columnName: "did"
            ) {
                $0.sourcePlainStringDisplayValue
            }
        }
        SourceDatabaseFieldComparisonRow(
            title: "Bio",
            record: record,
            columnName: "bio"
        ) {
            $0.sourcePlainStringDisplayValue
        }
        SourceDatabaseFieldComparisonRow(
            title: "Images",
            record: record,
            columnName: "images"
        ) {
            $0.sourceArrayCountDisplayValue(singular: "image", plural: "images")
        }
        SourceDatabaseFieldComparisonRow(
            title: "Links",
            record: record,
            columnName: "links"
        ) {
            $0.sourceArrayCountDisplayValue(singular: "link", plural: "links")
        }

        if showsTechnicalDetails {
            ForEach(undisplayedFieldChanges(in: record)) { change in
                SourceFieldChangeRow(change: change)
            }
        }
    }

    @ViewBuilder
    private func rawContributorValueRows(
        _ record: SourceRecordChange,
        side: SourceRecordValueSide
    ) -> some View {
        SourceDatabaseFieldValueRow(
            title: "Name",
            record: record,
            columnName: "name",
            side: side
        ) {
            $0.sourcePlainStringDisplayValue
        }
        if showsTechnicalDetails {
            SourceDatabaseFieldValueRow(
                title: "DID",
                record: record,
                columnName: "did",
                side: side
            ) {
                $0.sourcePlainStringDisplayValue
            }
        }
        SourceDatabaseFieldValueRow(
            title: "Bio",
            record: record,
            columnName: "bio",
            side: side
        ) {
            $0.sourcePlainStringDisplayValue
        }
        SourceDatabaseFieldValueRow(
            title: "Images",
            record: record,
            columnName: "images",
            side: side
        ) {
            $0.sourceArrayCountDisplayValue(singular: "image", plural: "images")
        }
        SourceDatabaseFieldValueRow(
            title: "Links",
            record: record,
            columnName: "links",
            side: side
        ) {
            $0.sourceArrayCountDisplayValue(singular: "link", plural: "links")
        }

        if showsTechnicalDetails {
            ForEach(undisplayedFieldChanges(in: record)) { change in
                SourceDatabaseFieldValueRow(
                    title: change.columnName,
                    change: change,
                    side: side
                )
            }
        }
    }

    private var change: SourceRecordChange {
        switch content {
        case let .comparison(comparison):
            comparison.change
        case let .record(record):
            record
        }
    }

    private var title: String {
        switch content {
        case let .comparison(comparison):
            comparison.right?.name
                ?? comparison.left?.name
                ?? comparison.change.contributorTitleFallback(
                    showsTechnicalDetails: showsTechnicalDetails
                )
        case let .record(record):
            record.fieldChange(named: "name")?.displayValue
                ?? record.contributorTitleFallback(
                    showsTechnicalDetails: showsTechnicalDetails
                )
        }
    }

    private static let displayedRawColumnNames: Set<String> = [
        "name",
        "did",
        "bio",
        "images",
        "links",
    ]

    private func undisplayedFieldChanges(in record: SourceRecordChange) -> [SourceFieldChange] {
        record.fieldChanges.filter {
            !Self.displayedRawColumnNames.contains($0.columnName)
        }
    }
}

struct SourceChannelChangeRow: View {
    let comparison: SourceRecordComparison<OME.Channel>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        SourceTypedRecordChangeRow(
            comparison: comparison,
            title: title,
            recordTitle: "Channel",
            fields: [
                .init(title: "Name", columnName: "name", keyPath: \.name),
                .init(title: "Description", columnName: "description", keyPath: \.description),
                .init(title: "Icon Image", columnName: "iconImageURL", optionalKeyPath: \.iconImageURL) {
                    $0.absoluteString
                },
                .init(title: "Header Image", columnName: "headerImageURL", optionalKeyPath: \.headerImageURL) {
                    $0.absoluteString
                },
                .init(title: "Sort Index", columnName: "sortIndex", optionalKeyPath: \.sortIndex) {
                    "\($0)"
                },
                .init(
                    title: "Default Notifications",
                    columnName: "defaultNotificationState",
                    keyPath: \.defaultNotificationState
                ) {
                    $0.sourceChangeDisplayValue
                },
                .init(
                    title: "Notifications Required",
                    columnName: "notificationsRequired",
                    keyPath: \.notificationsRequired
                ) {
                    $0.sourceChangeDisplayValue
                },
            ]
        )
    }

    private var title: String {
        comparison.right?.name
            ?? comparison.left?.name
            ?? comparison.change.titleFallback(
                "Channel",
                showsTechnicalDetails: showsTechnicalDetails
            )
    }
}

struct SourcePosterChangeRow: View {
    let comparison: SourceRecordComparison<OME.Poster>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        SourceTypedRecordChangeRow(
            comparison: comparison,
            title: title,
            recordTitle: "Poster",
            fields: [
                .init(title: "Title", columnName: "title", optionalKeyPath: \.title),
                .init(title: "Image", columnName: "image", keyPath: \.image) {
                    $0.sourceChangeDisplayValue
                },
            ]
        )
    }

    private var title: String {
        comparison.right?.title
            ?? comparison.left?.title
            ?? comparison.change.titleFallback(
                "Poster",
                showsTechnicalDetails: showsTechnicalDetails
            )
    }
}

struct SourceChangeKindBadge: View {
    let kind: SourceRecordChangeKind

    var body: some View {
        Text(kind.title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(kind.badgeForegroundStyle)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(kind.badgeBackgroundStyle, in: Capsule())
    }
}

struct SourceTypedRecordChangeRow<Record: Sendable>: View {
    let comparison: SourceRecordComparison<Record>
    let title: String
    let recordTitle: String
    let fields: [SourceRecordField<Record>]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SourceChangeKindBadge(kind: comparison.change.kind)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                    Text(recordTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            SourceRecordFieldRows(
                comparison: comparison,
                fields: fields
            )
        }
        .padding(.vertical, 6)
    }
}

struct SourceRecordField<Record: Sendable>: Identifiable {
    var id: String { columnName }

    var title: String
    var columnName: String
    var isTechnical: Bool
    var isChanged: (SourceRecordComparison<Record>) -> Bool
    var displayValue: (SourceRecordComparison<Record>, SourceRecordValueSide) -> String?

    init<Value: Equatable>(
        title: String,
        columnName: String,
        keyPath: KeyPath<Record, Value>,
        isTechnical: Bool = false,
        valueTitle: @escaping (Value) -> String = { String(describing: $0) }
    ) {
        self.title = title
        self.columnName = columnName
        self.isTechnical = isTechnical
        self.isChanged = { comparison in
            comparison.left.map { $0[keyPath: keyPath] }
                != comparison.right.map { $0[keyPath: keyPath] }
        }
        self.displayValue = { comparison, side in
            side.value(from: comparison, keyPath: keyPath).map(valueTitle)
        }
    }

    init<Value: Equatable>(
        title: String,
        columnName: String,
        optionalKeyPath: KeyPath<Record, Value?>,
        isTechnical: Bool = false,
        valueTitle: @escaping (Value) -> String = { String(describing: $0) }
    ) {
        self.title = title
        self.columnName = columnName
        self.isTechnical = isTechnical
        self.isChanged = { comparison in
            comparison.left.flatMap { $0[keyPath: optionalKeyPath] }
                != comparison.right.flatMap { $0[keyPath: optionalKeyPath] }
        }
        self.displayValue = { comparison, side in
            side.value(from: comparison, optionalKeyPath: optionalKeyPath).map(valueTitle)
        }
    }
}

struct SourceRecordFieldRows<Record: Sendable>: View {
    let comparison: SourceRecordComparison<Record>
    let fields: [SourceRecordField<Record>]
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch comparison.change.kind {
            case .modified:
                comparisonRows
            case .added:
                valueRows(side: .right)
            case .deleted:
                valueRows(side: .left)
            }
        }
    }

    @ViewBuilder
    private var comparisonRows: some View {
        ForEach(visibleFields) { field in
            if field.isChanged(comparison) {
                SourceComparisonDisplayRow(
                    title: field.title,
                    left: field.displayValue(comparison, .left) ?? "missing",
                    right: field.displayValue(comparison, .right) ?? "missing"
                )
            }
        }

        if showsTechnicalDetails {
            ForEach(undisplayedFieldChanges) { change in
                SourceFieldChangeRow(change: change)
            }
        }
    }

    @ViewBuilder
    private func valueRows(side: SourceRecordValueSide) -> some View {
        ForEach(visibleFields) { field in
            if let value = field.displayValue(comparison, side) {
                SourceRecordDisplayValueRow(
                    title: field.title,
                    value: value,
                    side: side
                )
            }
        }

        if showsTechnicalDetails {
            ForEach(undisplayedFieldChanges) { change in
                SourceDatabaseFieldValueRow(
                    title: change.columnName,
                    change: change,
                    side: side
                )
            }
        }
    }

    private var visibleFields: [SourceRecordField<Record>] {
        fields.filter { showsTechnicalDetails || !$0.isTechnical }
    }

    private var undisplayedFieldChanges: [SourceFieldChange] {
        let displayedColumnNames = Set(fields.map(\.columnName))
        return comparison.change.fieldChanges.filter {
            !displayedColumnNames.contains($0.columnName)
        }
    }
}

struct SourceComparisonValueRow<Record: Sendable, Value: Equatable>: View {
    let title: String
    let left: Value?
    let right: Value?
    let valueTitle: (Value) -> String

    init(
        title: String,
        comparison: SourceRecordComparison<Record>,
        keyPath: KeyPath<Record, Value>,
        valueTitle: @escaping (Value) -> String = { String(describing: $0) }
    ) {
        self.title = title
        self.left = comparison.left.map { $0[keyPath: keyPath] }
        self.right = comparison.right.map { $0[keyPath: keyPath] }
        self.valueTitle = valueTitle
    }

    init(
        title: String,
        comparison: SourceRecordComparison<Record>,
        optionalKeyPath: KeyPath<Record, Value?>,
        valueTitle: @escaping (Value) -> String = { String(describing: $0) }
    ) {
        self.title = title
        self.left = comparison.left.flatMap { $0[keyPath: optionalKeyPath] }
        self.right = comparison.right.flatMap { $0[keyPath: optionalKeyPath] }
        self.valueTitle = valueTitle
    }

    var body: some View {
        if left != right {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    SourceComparisonValuePill(value: displayValue(left), role: .left)
                    Text("->")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    SourceComparisonValuePill(value: displayValue(right), role: .right)
                }
            }
        }
    }

    private func displayValue(_ value: Value?) -> String {
        value.map(valueTitle) ?? "missing"
    }
}

struct SourceComparisonDisplayRow: View {
    let title: String
    let left: String
    let right: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                SourceComparisonValuePill(value: left, role: .left)
                Text("->")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                SourceComparisonValuePill(value: right, role: .right)
            }
        }
    }
}

struct SourceRecordDisplayValueRow: View {
    let title: String
    let value: String
    let side: SourceRecordValueSide

    var body: some View {
        if value != "missing" {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                SourceComparisonValuePill(
                    value: value,
                    role: side.pillRole
                )
            }
        }
    }
}

enum SourceRecordValueSide {
    case left
    case right

    func value<Record: Sendable, Value>(
        from comparison: SourceRecordComparison<Record>,
        keyPath: KeyPath<Record, Value>
    ) -> Value? {
        switch self {
        case .left:
            comparison.left.map { $0[keyPath: keyPath] }
        case .right:
            comparison.right.map { $0[keyPath: keyPath] }
        }
    }

    func value<Record: Sendable, Value>(
        from comparison: SourceRecordComparison<Record>,
        optionalKeyPath: KeyPath<Record, Value?>
    ) -> Value? {
        switch self {
        case .left:
            comparison.left.flatMap { $0[keyPath: optionalKeyPath] }
        case .right:
            comparison.right.flatMap { $0[keyPath: optionalKeyPath] }
        }
    }

    func value(from change: SourceFieldChange) -> DatabaseValue? {
        switch self {
        case .left:
            change.baselineValue
        case .right:
            change.workingValue
        }
    }

    var pillRole: SourceComparisonValuePill.Role {
        switch self {
        case .left:
            .left
        case .right:
            .right
        }
    }
}

struct SourceRecordValueRow<Record: Sendable, Value>: View {
    let title: String
    let value: Value?
    let valueTitle: (Value) -> String
    let side: SourceRecordValueSide

    init(
        title: String,
        comparison: SourceRecordComparison<Record>,
        side: SourceRecordValueSide,
        keyPath: KeyPath<Record, Value>,
        valueTitle: @escaping (Value) -> String = { String(describing: $0) }
    ) {
        self.title = title
        self.value = side.value(from: comparison, keyPath: keyPath)
        self.valueTitle = valueTitle
        self.side = side
    }

    init(
        title: String,
        comparison: SourceRecordComparison<Record>,
        side: SourceRecordValueSide,
        optionalKeyPath: KeyPath<Record, Value?>,
        valueTitle: @escaping (Value) -> String = { String(describing: $0) }
    ) {
        self.title = title
        self.value = side.value(from: comparison, optionalKeyPath: optionalKeyPath)
        self.valueTitle = valueTitle
        self.side = side
    }

    var body: some View {
        if let value {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                SourceComparisonValuePill(
                    value: valueTitle(value),
                    role: side.pillRole
                )
            }
        }
    }
}

struct SourceComparisonValuePill: View {
    enum Role {
        case left
        case right
    }

    let value: String
    let role: Role

    var body: some View {
        Text(value)
            .font(.caption)
            .lineLimit(2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 6))
    }

    private var backgroundStyle: Color {
        switch role {
        case .left:
            Color.red.opacity(0.12)
        case .right:
            Color.green.opacity(0.12)
        }
    }
}

struct SourceDatabaseFieldComparisonRow: View {
    let title: String
    let change: SourceFieldChange?
    let valueTitle: (DatabaseValue?) -> String

    init(
        title: String,
        record: SourceRecordChange,
        columnName: String,
        valueTitle: @escaping (DatabaseValue?) -> String = { $0.sourceDisplayValue }
    ) {
        self.title = title
        self.change = record.fieldChange(named: columnName)
        self.valueTitle = valueTitle
    }

    var body: some View {
        if let change {
            let leftValue = valueTitle(change.baselineValue)
            let rightValue = valueTitle(change.workingValue)

            if leftValue != "missing" || rightValue != "missing" {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        SourceComparisonValuePill(
                            value: leftValue,
                            role: .left
                        )
                        Text("->")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        SourceComparisonValuePill(
                            value: rightValue,
                            role: .right
                        )
                    }
                }
            }
        }
    }
}

struct SourceDatabaseFieldValueRow: View {
    let title: String
    let value: DatabaseValue?
    let valueTitle: (DatabaseValue?) -> String
    let side: SourceRecordValueSide

    init(
        title: String,
        record: SourceRecordChange,
        columnName: String,
        side: SourceRecordValueSide,
        valueTitle: @escaping (DatabaseValue?) -> String = { $0.sourceDisplayValue }
    ) {
        self.init(
            title: title,
            change: record.fieldChange(named: columnName),
            side: side,
            valueTitle: valueTitle
        )
    }

    init(
        title: String,
        change: SourceFieldChange?,
        side: SourceRecordValueSide,
        valueTitle: @escaping (DatabaseValue?) -> String = { $0.sourceDisplayValue }
    ) {
        self.title = title
        self.value = change.map { side.value(from: $0) } ?? nil
        self.valueTitle = valueTitle
        self.side = side
    }

    var body: some View {
        let displayValue = valueTitle(value)

        if displayValue != "missing" {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                SourceComparisonValuePill(
                    value: displayValue,
                    role: side.pillRole
                )
            }
        }
    }
}

struct SourceFieldChangeRow: View {
    let change: SourceFieldChange

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(change.columnName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(change.baselineValue.sourceDisplayValue) -> \(change.workingValue.sourceDisplayValue)")
                .font(.caption)
                .monospaced()
                .selectableText()
        }
    }
}

private extension SourceRecordChangeKind {
    var shortTitle: String {
        switch self {
        case .added:
            "A"
        case .modified:
            "M"
        case .deleted:
            "D"
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

    var badgeBackgroundStyle: Color {
        switch self {
        case .added:
            Color.green.opacity(0.16)
        case .modified:
            Color.orange.opacity(0.18)
        case .deleted:
            Color.red.opacity(0.16)
        }
    }

    var badgeForegroundStyle: Color {
        switch self {
        case .added:
            .green
        case .modified:
            .orange
        case .deleted:
            .red
        }
    }
}

private extension SourceRecordChange {
    var primaryKeySummary: String {
        primaryKeyValues
            .map { "\($0.columnName)=\($0.value.sourceDisplayValue)" }
            .joined(separator: ", ")
    }

    func titleFallback(
        _ genericTitle: String,
        showsTechnicalDetails: Bool
    ) -> String {
        showsTechnicalDetails ? primaryKeySummary : genericTitle
    }

    func contributorTitleFallback(showsTechnicalDetails: Bool) -> String {
        guard showsTechnicalDetails else { return "Contributor" }
        return primaryKeyValue(named: "contributorID")?.sourcePlainStringDisplayValue
            ?? primaryKeySummary
    }

    func fieldChange(named columnName: String) -> SourceFieldChange? {
        fieldChanges.first { $0.columnName == columnName }
    }

    private func primaryKeyValue(named columnName: String) -> DatabaseValue? {
        primaryKeyValues.first { $0.columnName == columnName }?.value
    }
}

private extension SourceFieldChange {
    var displayValue: String? {
        workingValue.sourcePlainStringValue
            ?? baselineValue.sourcePlainStringValue
            ?? workingValue.sourceDisplayValue
    }
}

private extension OME.Performance {
    var sourcePerformanceTimeRange: String {
        "\(startTime.sourceChangeTimeValue) - \(endTime.sourceChangeTimeValue)"
    }
}

private extension LocalDate {
    var sourceChangeDisplayValue: String {
        rawValue
    }
}

private extension OMEColor {
    var sourceChangeDisplayValue: String {
        String(format: "#%06X", rawValue & 0xFF_FFFF)
    }
}

private extension Open where Known == OME.Event.Status {
    var sourceChangeDisplayValue: String {
        switch self {
        case let .known(status):
            status.sourceChangeDisplayValue
        case let .unknown(value):
            value.stringValue ?? String(describing: value)
        }
    }
}

private extension OME.Event.Status {
    var sourceChangeDisplayValue: String {
        switch self {
        case .planned:
            "Planned"
        case .scheduled:
            "Scheduled"
        case .rescheduled:
            "Rescheduled"
        case .cancelled:
            "Cancelled"
        case .postponed:
            "Postponed"
        }
    }
}

private extension Open where Known == OME.Event.Mode {
    var sourceChangeDisplayValue: String {
        switch self {
        case let .known(mode):
            mode.sourceChangeDisplayValue
        case let .unknown(value):
            value.stringValue ?? String(describing: value)
        }
    }
}

private extension OME.Event.Mode {
    var sourceChangeDisplayValue: String {
        switch self {
        case .inPerson:
            "In Person"
        case .virtual:
            "Virtual"
        case .hybrid:
            "Hybrid"
        }
    }
}

private extension OME.Channel.NotificationState {
    var sourceChangeDisplayValue: String {
        switch self {
        case .subscribed:
            "Subscribed"
        case .unsubscribed:
            "Unsubscribed"
        }
    }
}

private extension Bool {
    var sourceChangeDisplayValue: String {
        self ? "Yes" : "No"
    }
}

private extension OME.ID<OME.Stage> {
    var sourceChangeDisplayValue: String {
        rawValue.rawValue
    }
}

private extension OME.ID<OME.Schedule> {
    var sourceChangeDisplayValue: String {
        rawValue.rawValue
    }
}

private extension Date {
    var sourceChangeTimeValue: String {
        formatted(date: .omitted, time: .shortened)
    }
}

private extension [ExternalPlatform.Asset] {
    var sourceChangeCountValue: String {
        sourceChangeCountValue(singular: "recording", plural: "recordings")
    }
}

private extension [OME.ImageAsset] {
    var sourceChangeImageCountValue: String {
        sourceChangeCountValue(singular: "image", plural: "images")
    }
}

private extension [ExternalPlatform.Link] {
    var sourceChangeLinkCountValue: String {
        sourceChangeCountValue(singular: "link", plural: "links")
    }
}

private extension Collection {
    func sourceChangeCountValue(singular: String, plural: String) -> String {
        switch count {
        case 1:
            "1 \(singular)"
        default:
            "\(count) \(plural)"
        }
    }
}

private extension OME.ImageAsset {
    var sourceChangeDisplayValue: String {
        switch source {
        case let .url(url):
            "\(role.rawValue) image: \(url.lastPathComponent)"
        case .blob:
            "\(role.rawValue) image"
        }
    }
}

private extension Optional where Wrapped == DatabaseValue {
    var sourceDisplayValue: String {
        switch self {
        case let .some(value):
            value.sourceDisplayValue
        case .none:
            "missing"
        }
    }

    var sourcePlainStringDisplayValue: String {
        sourcePlainStringValue ?? sourceDisplayValue
    }

    var sourcePlainStringValue: String? {
        guard case let .some(value) = self else { return nil }
        return value.sourcePlainStringValue
    }

    func sourceArrayCountDisplayValue(singular: String, plural: String) -> String {
        guard case let .some(value) = self else { return "missing" }
        return value.sourceArrayCountDisplayValue(singular: singular, plural: plural)
    }
}

private extension DatabaseValue {
    var sourceDisplayValue: String {
        switch storage {
        case .null:
            "NULL"
        case let .int64(value):
            "\(value)"
        case let .double(value):
            "\(value)"
        case let .string(value):
            value.sourceStringDisplayValue
        case let .blob(data):
            "<blob \(data.count) bytes>"
        }
    }

    var sourcePlainStringDisplayValue: String {
        guard !isNull else { return "missing" }
        return sourcePlainStringValue ?? sourceDisplayValue
    }

    var sourcePlainStringValue: String? {
        guard case let .string(value) = storage else { return nil }
        return value
    }

    func sourceArrayCountDisplayValue(singular: String, plural: String) -> String {
        guard !isNull else { return "missing" }
        guard let count = sourceArrayCount else {
            return sourceDisplayValue
        }
        switch count {
        case 1:
            return "1 \(singular)"
        default:
            return "\(count) \(plural)"
        }
    }

    var sourceArrayCount: Int? {
        guard case let .string(value) = storage,
              let data = value.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return nil }

        return array.count
    }

    private var isNull: Bool {
        switch storage {
        case .null:
            true
        case .int64, .double, .string, .blob:
            false
        }
    }
}

private extension String {
    var sourceStringDisplayValue: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isLikelyJSON {
            return "<json \(utf8.count) bytes>"
        }
        if count > 240 {
            return "\(String(prefix(160)).debugDescription) ... <\(utf8.count) bytes>"
        }
        return debugDescription
    }
}

private extension String {
    var isLikelyJSON: Bool {
        (hasPrefix("{") && hasSuffix("}"))
            || (hasPrefix("[") && hasSuffix("]"))
    }
}

struct SourceChangeUnavailableView: View {
    let reason: SourceChangeSummary.UnavailableReason
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        switch reason {
        case let .schemaMismatch(mismatches):
            List {
                Section {
                    Label(
                        showsTechnicalDetails ? "Schema Mismatch" : "Changes unavailable",
                        systemImage: "exclamationmark.triangle"
                    )
                }

                if showsTechnicalDetails {
                    Section("Missing Columns") {
                        ForEach(mismatches) { mismatch in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mismatch.tableName)
                                Text(mismatch.missingColumnNames.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
