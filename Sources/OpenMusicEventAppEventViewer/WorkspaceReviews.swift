import ATProto
import BlueskyActorCache
import ComposableArchitecture2
import ComposableWorkspace
import Dependencies
import ErrorHandling
import Foundation
import IssueReporting
import GRDB
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventSourceEditing
import Sharing
import SourceEditing
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct WorkspaceReviews {
    public init() {}

    public enum Status: Equatable, Sendable {
        case failed(String)
        case loaded([TangledPullReview])
        case loading
        case notLoaded
    }

    public struct State {
        public init(workspace: SourceWorkspace) {
            self.workspace = workspace
            self._cachedActorIdentities = Fetch(
                wrappedValue: CachedActorIdentities(),
                CachedActorIdentitiesRequest()
            )
        }

        public let workspace: SourceWorkspace
        @DebugSnapshotIgnored
        @Fetch public var cachedActorIdentities: CachedActorIdentities
        public var destination: Destination.State?
        public var locallyRemovedReviewIDs: Set<String> = []
        public var pendingCreatedReviewID: String?
        public var status: Status = .notLoaded

        public var reviewAuthorReferences: [String] {
            Array(Set(reviews.map(\.author).filter { !$0.isEmpty })).sorted()
        }

        public var reviews: [TangledPullReview] {
            guard case let .loaded(reviews) = status else { return [] }
            return reviews
        }

        public func canReview(authoringAccess: AuthoringAccess) -> Bool {
            authoringAccess.canPropose || authoringAccess.canMerge
        }

        public mutating func openPendingReviewIfAvailable() {
            guard let pendingCreatedReviewID,
                  let review = reviews.first(where: { $0.id == pendingCreatedReviewID })
            else { return }
            destination = .reviewDetail(
                WorkspaceReviewDetail.State(workspace: workspace, review: review)
            )
            self.pendingCreatedReviewID = nil
        }

        mutating func remove(_ review: TangledPullReview) {
            locallyRemovedReviewIDs.insert(review.id)
            if case let .loaded(reviews) = status {
                status = .loaded(reviews.filter { $0.id != review.id })
            }
            destination = nil
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case refreshButtonTapped
        case reviewButtonTapped(TangledPullReview)
    }

    @Feature
    public enum Destination {
        case reviewDetail(WorkspaceReviewDetail)
    }

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
    @Dependency(\.tangledPullReviewClient) var reviewClient

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case .refreshButtonTapped:
                loadReviews(state: &state)

            case let .reviewButtonTapped(review):
                state.destination = .reviewDetail(
                    WorkspaceReviewDetail.State(
                        workspace: state.workspace,
                        review: review
                    )
                )
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .onEvent(WorkspaceReviewRemoved.self) { review, state in
            state.remove(review)
            return .continue
        }
        .onMount { state in
            loadReviews(state: &state)
        }
        .onChange(of: store.reviewAuthorReferences, initial: true) { _, authors, _ in
            guard !authors.isEmpty else { return }
            let blueskyActorProfileCache = blueskyActorProfileCache
            store.addTask {
                for author in authors {
                    do {
                        _ = try await blueskyActorProfileCache.refreshProfileIfNeeded(
                            author,
                            24 * 60 * 60,
                            15 * 60
                        )
                    } catch is CancellationError {
                        return
                    } catch {
                        continue
                    }
                }
            }
        }
    }

    func loadReviews(state: inout State) {
        guard state.status != .loading else { return }
        let target = OpenMusicEventSourceTarget(workspace: state.workspace)
        let reviewClient = reviewClient
        state.status = .loading
        store.addTask {
            do {
                let reviews = try await reviewClient.list(
                    OpenMusicEventTangledPullReviewRequest(target: target)
                )
                try store.modify {
                    let removed = $0.locallyRemovedReviewIDs
                    $0.status = .loaded(
                        reviews
                            .filter { !removed.contains($0.id) }
                            .sorted { $0.createdAt > $1.createdAt }
                    )
                    $0.openPendingReviewIfAvailable()
                }
            } catch {
                try store.modify { $0.status = .failed(String(describing: error)) }
                reportIssue(error)
            }
        }
    }
}

enum WorkspaceReviewRemoved: FeatureEventKey {
    typealias Value = TangledPullReview
}

@Feature
public struct WorkspaceReviewDetail {
    public init() {}

    public enum SemanticDiffStatus: Equatable, Sendable {
        case failed(String)
        case loaded(SemanticDiff)
        case loading
        case notLoaded
    }

    public enum RawDiffStatus: Equatable, Sendable {
        case failed(String)
        case loaded(String)
        case loading
        case notLoaded
    }

    public enum Operation: Equatable, Sendable {
        case closing
        case deleting
        case idle
        case merging

        public var isRunning: Bool {
            switch self {
            case .closing, .deleting, .merging: true
            case .idle: false
            }
        }
    }

    public struct SemanticDiff: Equatable, Sendable {
        public init(
            groups: [SourceChangeGroup],
            fieldComparisons: SourceFieldComparisons,
            recordComparisons: SourceRecordComparisons,
            sourceFileAttributions: [SourceFileAttribution]
        ) {
            self.groups = groups
            self.fieldComparisons = fieldComparisons
            self.recordComparisons = recordComparisons
            self.sourceFileAttributions = sourceFileAttributions
        }

        public var groups: [SourceChangeGroup]
        public var fieldComparisons: SourceFieldComparisons
        public var recordComparisons: SourceRecordComparisons
        public var sourceFileAttributions: [SourceFileAttribution]
        public var totalCount: Int { groups.reduce(0) { $0 + $1.totalCount } }
    }

    public struct State {
        public init(
            workspace: SourceWorkspace,
            review: TangledPullReview
        ) {
            self.workspace = workspace
            self.review = review
            self._cachedActorIdentities = Fetch(
                wrappedValue: CachedActorIdentities(),
                CachedActorIdentitiesRequest()
            )
        }

        public let workspace: SourceWorkspace
        public let review: TangledPullReview
        @SharedReader(.defaultAuthoringGrant)
        public var authoringGrant: AuthoringGrant?
        @DebugSnapshotIgnored
        @Fetch public var cachedActorIdentities: CachedActorIdentities
        @Trigger public var loadRawDiff
        @Trigger public var loadSemanticDiff
        public var operation: Operation = .idle
        public var rawDiffStatus: RawDiffStatus = .notLoaded
        public var semanticDiffStatus: SemanticDiffStatus = .notLoaded

        public var authorIdentity: ActorIdentity? {
            cachedActorIdentities[review.author]
        }

        public var canMerge: Bool {
            authoringGrant?.role.canMerge == true
        }
    }

    public enum Action {
        case closeButtonTapped
        case deleteButtonTapped
        case mergeButtonTapped
        case retryRawDiffButtonTapped
        case retrySemanticDiffButtonTapped
    }

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
    @Dependency(\.sourceWorkspaceStorage) var sourceWorkspaceStorage
    @Dependency(\.tangledPullReviewClient) var reviewClient
    @Dependency(\.tangledPullReviewSourceSnapshot) var sourceSnapshot
    @Dependency(\.uuid) var uuid

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .closeButtonTapped:
                guard state.canMerge, !state.operation.isRunning else { return }
                let review = state.review
                let reviewClient = reviewClient
                state.operation = .closing
                store.addTask {
                    let result: Void? = await store.withErrorHandling(
                        fallbackMessage: .workspaceReviewCloseFailed,
                        operation: .workspaceReviewClose
                    ) {
                        try await reviewClient.close(review)
                    } cleanup: {
                        $0.operation = .idle
                    }
                    guard result != nil else { return }
                    try store.post(key: WorkspaceReviewRemoved.self, value: review)
                }

            case .deleteButtonTapped:
                guard state.canMerge, !state.operation.isRunning else { return }
                let review = state.review
                let reviewClient = reviewClient
                state.operation = .deleting
                store.addTask {
                    let result: Void? = await store.withErrorHandling(
                        fallbackMessage: .workspaceReviewDeleteFailed,
                        operation: .workspaceReviewDelete
                    ) {
                        try await reviewClient.delete(review)
                    } cleanup: {
                        $0.operation = .idle
                    }
                    guard result != nil else { return }
                    try store.post(key: WorkspaceReviewRemoved.self, value: review)
                }

            case .mergeButtonTapped:
                guard state.canMerge, !state.operation.isRunning else { return }
                let request = OpenMusicEventTangledPullReviewMergeRequest(
                    target: OpenMusicEventSourceTarget(workspace: state.workspace),
                    review: state.review
                )
                let review = state.review
                let reviewClient = reviewClient
                state.operation = .merging
                store.addTask {
                    let result: Void? = await store.withErrorHandling(
                        fallbackMessage: .workspaceReviewMergeFailed,
                        operation: .workspaceReviewMerge
                    ) {
                        try await reviewClient.merge(request)
                    } cleanup: {
                        $0.operation = .idle
                    }
                    guard result != nil else { return }
                    do {
                        let reconciliation = try store.post(
                            key: WorkspaceProposalMerged.self,
                            value: WorkspaceProposalID(rawValue: review.id)
                        )
                        await reconciliation?.value
                        try store.post(key: WorkspaceReviewRemoved.self, value: review)
                    } catch {
                        reportIssue(error)
                    }
                }

            case .retryRawDiffButtonTapped:
                let loadRawDiff = state.loadRawDiff
                store.addTask { try loadRawDiff() }

            case .retrySemanticDiffButtonTapped:
                let loadSemanticDiff = state.loadSemanticDiff
                store.addTask { try loadSemanticDiff() }
            }
        }
        .onTrigger(store.loadRawDiff) { state in
            switch state.rawDiffStatus {
            case .loaded, .loading:
                return
            case .failed, .notLoaded:
                break
            }
            let review = state.review
            let reviewClient = reviewClient
            state.rawDiffStatus = .loading
            store.addTask {
                do {
                    let rawDiff = try await reviewClient.rawDiff(review)
                    try store.modify { $0.rawDiffStatus = .loaded(rawDiff) }
                } catch {
                    try store.modify {
                        $0.rawDiffStatus = .failed(String(describing: error))
                    }
                    reportIssue(error)
                }
            }
        }
        .onTrigger(store.loadSemanticDiff) { state in
            switch state.semanticDiffStatus {
            case .loaded, .loading:
                return
            case .failed, .notLoaded:
                break
            }
            let workspace = state.workspace
            let review = state.review
            let scratchID = uuid()
            let sourceSnapshot = sourceSnapshot
            let sourceWorkspaceStorage = sourceWorkspaceStorage
            state.semanticDiffStatus = .loading
            store.addTask {
                do {
                    let diff = try await SemanticDiff.load(
                        workspace: workspace,
                        review: review,
                        scratchID: scratchID,
                        sourceSnapshot: sourceSnapshot,
                        sourceWorkspaceStorage: sourceWorkspaceStorage
                    )
                    try store.modify { $0.semanticDiffStatus = .loaded(diff) }
                } catch {
                    try store.modify {
                        $0.semanticDiffStatus = .failed(String(describing: error))
                    }
                    reportIssue(error)
                }
            }
        }
        .onMount { state in
            let loadRawDiff = state.loadRawDiff
            let loadSemanticDiff = state.loadSemanticDiff
            let author = state.review.author
            let blueskyActorProfileCache = blueskyActorProfileCache
            store.addTask { try loadRawDiff() }
            store.addTask { try loadSemanticDiff() }
            guard !author.isEmpty else { return }
            store.addTask {
                do {
                    _ = try await blueskyActorProfileCache.refreshProfileIfNeeded(
                        author,
                        24 * 60 * 60,
                        15 * 60
                    )
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
    }
}

public struct WorkspaceReviewsView: View {
    @Bindable var store: StoreOf<WorkspaceReviews>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    public init(store: StoreOf<WorkspaceReviews>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if showsTechnicalDetails {
                Section("Source details") {
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
                }
            }

            Section("Open proposals") {
                if store.pendingCreatedReviewID != nil {
                    HStack(spacing: 10) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Opening your new proposal")
                            Text("Waiting for it to appear in the proposal list.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("workspace.proposals.pending")
                }

                switch store.status {
                case .loading:
                    ProgressView("Loading proposals")

                case let .failed(message):
                    Text(showsTechnicalDetails ? message : "Proposals could not be loaded")
                        .foregroundStyle(.secondary)

                case let .loaded(reviews):
                    if reviews.isEmpty {
                        Text("No open proposals")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(reviews) { review in
                        Button {
                            store.send(.reviewButtonTapped(review))
                        } label: {
                            WorkspaceReviewRow(
                                review: review,
                                authorIdentity: store.cachedActorIdentities[review.author]
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("workspace.proposal.row.\(review.id)")
                    }

                case .notLoaded:
                    Text("Proposals have not been loaded")
                        .foregroundStyle(.secondary)
                }

                Button {
                    store.send(.refreshButtonTapped)
                } label: {
                    Label("Refresh proposals", systemImage: "refresh")
                }
                .disabled(store.status == .loading)
                .accessibilityIdentifier("workspace.proposals.refresh")
            }
        }
        .navigationDestination(
            item: $store.scope(\.destination, action: \.destination).reviewDetail
        ) { detailStore in
            WorkspaceReviewDetailView(store: detailStore)
        }
    }
}

struct WorkspaceReviewRow: View {
    let review: TangledPullReview
    let authorIdentity: ActorIdentity?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(review.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(review.state.workspaceReviewStateTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(authorTitle)
                .font(.subheadline)
                .foregroundStyle(.primary)

            HStack(alignment: .firstTextBaseline) {
                Text(review.createdAt.workspaceReviewDateTitle)
                Spacer()
                Text(review.commentCount == 1 ? "1 comment" : "\(review.commentCount) comments")
                Image(systemName: "chevron-forward")
                    .accessibilityHidden(true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    var authorTitle: String {
        if let authorIdentity {
            return authorIdentity.displayTitle(showsTechnicalDetails: false)
        }
        return review.author.workspaceReviewFriendlyAuthorTitle
    }
}

public struct WorkspaceReviewDetailView: View {
    let store: StoreOf<WorkspaceReviewDetail>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    @State var isDeleteConfirmationPresented = false

    public init(store: StoreOf<WorkspaceReviewDetail>) {
        self.store = store
    }

    public var body: some View {
        List {
            Section("Proposal") {
                Text(store.review.title)
                    .font(.title3.weight(.semibold))
                if let authorIdentity = store.authorIdentity {
                    ContributorActorIdentityRow(
                        identity: authorIdentity,
                        isSelected: false
                    )
                } else {
                    LabeledContent(
                        "Submitted by",
                        value: store.review.author.workspaceReviewFriendlyAuthorTitle
                    )
                }
                LabeledContent(
                    "State",
                    value: store.review.state.workspaceReviewStateTitle
                )
                LabeledContent(
                    "Submitted",
                    value: store.review.createdAt.workspaceReviewDateTitle
                )
                LabeledContent(
                    "Discussion",
                    value: store.review.commentCount == 1
                        ? "1 comment"
                        : "\(store.review.commentCount) comments"
                )
            }

            Section("Branches") {
                WorkspaceBranchRelationshipView(
                    source: store.review.sourceBranch ?? "Unavailable",
                    target: store.review.targetBranch
                )
            }

            actionsSection

            if let body = store.review.body, !body.isEmpty {
                Section("Description") {
                    Text(body)
                        .selectableText()
                }
            }

            semanticDiffSections

            if showsTechnicalDetails {
                technicalSections
            }
        }
        .navigationTitle(store.review.title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog(
            "Delete this proposal permanently?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Proposal", role: .destructive) {
                store.send(.deleteButtonTapped)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    @ViewBuilder
    var actionsSection: some View {
        switch store.operation {
        case .closing:
            Section("Actions") {
                ProgressView("Closing proposal")
                    .accessibilityIdentifier("workspace.proposal.close.progress")
            }
        case .deleting:
            Section("Actions") {
                ProgressView("Deleting proposal")
                    .accessibilityIdentifier("workspace.proposal.delete.progress")
            }
        case .merging:
            Section("Actions") {
                ProgressView("Applying changes")
                    .accessibilityIdentifier("workspace.proposal.merge.progress")
            }
        case .idle:
            Section("Actions") {
                if store.canMerge {
                    Button("Merge Changes") {
                        store.send(.mergeButtonTapped)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("workspace.proposal.merge")

                    Button("Close Proposal") {
                        store.send(.closeButtonTapped)
                    }
                    .accessibilityIdentifier("workspace.proposal.close")

                    Button("Delete Proposal Permanently", role: .destructive) {
                        isDeleteConfirmationPresented = true
                    }
                    .accessibilityIdentifier("workspace.proposal.delete")
                } else {
                    Text("You can review this proposal, but only a workspace manager can change its state.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    var semanticDiffSections: some View {
        switch store.semanticDiffStatus {
        case let .failed(message):
            Section("What changed") {
                Text("Proposal changes could not be rendered")
                if showsTechnicalDetails {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .selectableText()
                }
                Button("Try Again") {
                    store.send(.retrySemanticDiffButtonTapped)
                }
            }

        case let .loaded(diff):
            SourceChangeSummarySection(
                groups: diff.groups,
                fieldComparisons: diff.fieldComparisons,
                recordComparisons: diff.recordComparisons
            )

        case .loading:
            Section("What changed") {
                ProgressView("Rendering proposal changes")
            }

        case .notLoaded:
            Section("What changed") {
                Button("Render proposal changes") {
                    store.send(.retrySemanticDiffButtonTapped)
                }
            }
        }
    }

    @ViewBuilder
    var technicalSections: some View {
        Section("Technical details") {
            WorkspaceTechnicalValueView(label: "Review URI", value: store.review.uri)
            WorkspaceTechnicalValueView(label: "Author ID", value: store.review.author)
            WorkspaceTechnicalValueView(label: "Created at", value: store.review.createdAt)
            WorkspaceTechnicalValueView(
                label: "Target branch",
                value: store.review.targetBranch
            )
            WorkspaceTechnicalValueView(
                label: "Target repository ID",
                value: store.review.targetRepositoryDID
            )
            if let sourceBranch = store.review.sourceBranch {
                WorkspaceTechnicalValueView(label: "Source branch", value: sourceBranch)
            }
            if let sourceRepositoryDID = store.review.sourceRepositoryDID {
                WorkspaceTechnicalValueView(
                    label: "Source repository ID",
                    value: sourceRepositoryDID
                )
            }

            PortableDisclosureGroup("Patch metadata") {
                if store.review.patchBlobs.isEmpty {
                    Text("No patch metadata")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.review.patchBlobs) { patchBlob in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Round \(patchBlob.index)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            WorkspaceTechnicalValueView(label: "Blob ID", value: patchBlob.cid)
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
                Text(store.review.rawReviewText)
                    .font(.caption)
                    .monospaced()
                    .selectableText()
            }

            if case let .loaded(diff) = store.semanticDiffStatus,
               !diff.sourceFileAttributions.isEmpty
            {
                PortableDisclosureGroup("Source files") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(diff.sourceFileAttributions) { attribution in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(attribution.filePath)
                                    .monospaced()
                                Text(
                                    attribution.recordChangeIDs.count == 1
                                        ? "1 rendered change"
                                        : "\(attribution.recordChangeIDs.count) rendered changes"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }

        Section("Raw source diff") {
            rawDiffContent
        }
    }

    @ViewBuilder
    var rawDiffContent: some View {
        switch store.rawDiffStatus {
        case let .failed(message):
            Text("Raw source changes could not be loaded")
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .selectableText()
            Button("Try Again") {
                store.send(.retryRawDiffButtonTapped)
            }

        case let .loaded(rawDiff):
            Text(rawDiff.isEmpty ? "No raw source changes" : rawDiff)
                .font(.caption)
                .monospaced()
                .selectableText()

        case .loading:
            ProgressView("Loading raw source changes")

        case .notLoaded:
            Button("Load raw source changes") {
                store.send(.retryRawDiffButtonTapped)
            }
        }
    }
}

extension UserFacingText {
    static let workspaceReviewCloseFailed = Self(
        "The proposal could not be closed.",
        fallback: "The proposal could not be closed."
    )
    static let workspaceReviewDeleteFailed = Self(
        "The proposal could not be deleted.",
        fallback: "The proposal could not be deleted."
    )
    static let workspaceReviewMergeFailed = Self(
        "The proposal could not be merged.",
        fallback: "The proposal could not be merged."
    )
}

extension ErrorOperation {
    static let workspaceReviewClose = Self("workspace.review.close")
    static let workspaceReviewDelete = Self("workspace.review.delete")
    static let workspaceReviewMerge = Self("workspace.review.merge")
}

private extension WorkspaceReviewDetail.SemanticDiff {
    static func load(
        workspace: SourceWorkspace,
        review: TangledPullReview,
        scratchID: UUID,
        sourceSnapshot: TangledPullReviewSourceSnapshotClient,
        sourceWorkspaceStorage: SourceWorkspaceStorage
    ) async throws -> Self {
        guard let sourceBranch = review.sourceBranch?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !sourceBranch.isEmpty else {
            throw WorkspaceReviewSemanticDiffError.missingSourceBranch
        }

        let scratchRootURL = FileManager.default.temporaryDirectory
            .appending(
                path: "ome-review-semantic-diff-\(scratchID.uuidString)",
                directoryHint: .isDirectory
            )
            .standardizedFileURL
        try FileManager.default.createDirectory(
            at: scratchRootURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: scratchRootURL) }

        let insertion = try await sourceSnapshot.insertion(
            TangledPullReviewSourceSnapshotRequest(
                organizerID: workspace.organizerID,
                ref: sourceBranch,
                sourceProvenance: workspace.sourceProvenance
            )
        )

        let reviewDatabase = try DatabasePool(
            path: scratchRootURL.appending(path: "review.sqlite").path
        )
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(reviewDatabase)

        try await withDependencies {
            $0.localImageFileStore = .reviewScratch(rootURL: scratchRootURL)
        } operation: {
            try await insertion.insert(into: reviewDatabase)
        }

        let baselineURL = try sourceWorkspaceStorage
            .location(workspace.id)
            .referenceDatabaseURL
        guard FileManager.default.fileExists(atPath: baselineURL.path) else {
            throw WorkspaceReviewSemanticDiffError.sourceBaselineMissing(baselineURL.path)
        }

        let referenceDatabase = try defaultBaselineDatabase(path: baselineURL.path)
        return try await reviewDatabase.read { db in
            let summary = try SourceWorkspaceEditSummary.query(
                workspace: workspace,
                in: db,
                referenceDatabase: referenceDatabase
            )
            guard case .available = summary.availability else {
                throw WorkspaceReviewSemanticDiffError.unavailable(summary.availability)
            }
            let sourceFileAttributions = try openMusicEventSourceFileAttributions(
                groups: summary.groups,
                recordComparisons: summary.recordComparisons,
                in: db
            )
            return Self(
                groups: summary.groups,
                fieldComparisons: summary.fieldComparisons,
                recordComparisons: summary.recordComparisons,
                sourceFileAttributions: sourceFileAttributions
            )
        }
    }
}

private enum WorkspaceReviewSemanticDiffError: Error, CustomStringConvertible {
    case missingSourceBranch
    case sourceBaselineMissing(String)
    case unavailable(SourceWorkspaceEditSummary.Availability)

    var description: String {
        switch self {
        case .missingSourceBranch:
            "The proposal does not identify a source branch."
        case let .sourceBaselineMissing(path):
            "The workspace source baseline is missing at \(path)."
        case let .unavailable(availability):
            "Proposal changes are unavailable: \(availability)."
        }
    }
}

private extension LocalImageFileStoreClient {
    static func reviewScratch(rootURL: URL) -> Self {
        Self { assetKey, data, _ in
            let imageRootURL = rootURL.appending(path: "images", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: imageRootURL,
                withIntermediateDirectories: true
            )
            let fileName = Data(assetKey.utf8)
                .base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            let imageURL = imageRootURL
                .appending(path: fileName.isEmpty ? "asset" : fileName)
                .appendingPathExtension("data")
            try data.write(to: imageURL, options: .atomic)
            return imageURL
        }
    }
}

private extension String {
    var workspaceReviewFriendlyAuthorTitle: String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "Profile unavailable" }
        if value.hasPrefix("did:") { return "Profile unavailable" }
        return value.hasPrefix("@") ? value : "@\(value)"
    }

    var workspaceReviewStateTitle: String {
        let value = replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        guard let first = value.first else { return "Unknown" }
        return first.uppercased() + value.dropFirst()
    }

    var workspaceReviewDateTitle: String {
        let standard = ISO8601DateFormatter()
        if let date = standard.date(from: self) {
            return DateFormatter.localizedString(
                from: date,
                dateStyle: .medium,
                timeStyle: .short
            )
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: self) {
            return DateFormatter.localizedString(
                from: date,
                dateStyle: .medium,
                timeStyle: .short
            )
        }
        return self
    }
}
