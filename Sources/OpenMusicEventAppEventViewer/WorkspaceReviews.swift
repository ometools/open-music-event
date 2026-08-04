import ATProto
import BlueskyActorCache
import ComposableArchitecture2
import ComposableAuthoring
import ComposableWorkspace
import Dependencies
import Foundation
import GRDB
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventSourceEditing
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
            authoringAccess.canMerge
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
                    if let pending = $0.pendingCreatedReviewID,
                       reviews.contains(where: { $0.id == pending })
                    {
                        $0.pendingCreatedReviewID = nil
                    }
                }
            } catch {
                try store.modify { $0.status = .failed(String(describing: error)) }
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
        case failed(String)
        case idle
        case merging

        public var isRunning: Bool {
            switch self {
            case .closing, .deleting, .merging: true
            case .failed, .idle: false
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
        @DebugSnapshotIgnored
        @Fetch public var cachedActorIdentities: CachedActorIdentities
        @Trigger public var loadRawDiff
        @Trigger public var loadSemanticDiff
        public var canMerge = false
        public var operation: Operation = .idle
        public var rawDiffStatus: RawDiffStatus = .notLoaded
        public var semanticDiffStatus: SemanticDiffStatus = .notLoaded

        public var authorIdentity: ActorIdentity? {
            cachedActorIdentities[review.author]
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
    @FeatureEnvironment(ComposableAuthoring.AuthoringContext<AuthoringGrant>.self)
    var authoring

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .closeButtonTapped:
                guard !state.operation.isRunning else { return }
                let review = state.review
                let reviewClient = reviewClient
                state.operation = .closing
                store.addTask {
                    do {
                        try await reviewClient.close(review)
                        try store.post(key: WorkspaceReviewRemoved.self, value: review)
                    } catch {
                        try store.modify { $0.operation = .failed(String(describing: error)) }
                    }
                }

            case .deleteButtonTapped:
                guard !state.operation.isRunning else { return }
                let review = state.review
                let reviewClient = reviewClient
                state.operation = .deleting
                store.addTask {
                    do {
                        try await reviewClient.delete(review)
                        try store.post(key: WorkspaceReviewRemoved.self, value: review)
                    } catch {
                        try store.modify { $0.operation = .failed(String(describing: error)) }
                    }
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
                    do {
                        try await reviewClient.merge(request)
                        let reconciliation = try store.post(
                            key: WorkspaceProposalMerged.self,
                            value: WorkspaceProposalID(rawValue: review.id)
                        )
                        await reconciliation?.value
                        try store.post(key: WorkspaceReviewRemoved.self, value: review)
                    } catch {
                        try store.modify { $0.operation = .failed(String(describing: error)) }
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
        .onChange(of: authoring.grant.wrappedValue, initial: true) { _, grant, state in
            state.canMerge = grant?.role.canMerge == true
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
        List {
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
                    }

                case .notLoaded:
                    Text("Proposals have not been loaded")
                        .foregroundStyle(.secondary)
                }

                Button("Refresh proposals") {
                    store.send(.refreshButtonTapped)
                }
                .disabled(store.status == .loading)
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
                Text("Open review")
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

            operationSection

            if let body = store.review.body, !body.isEmpty {
                Section("Description") {
                    Text(body)
                        .selectableText()
                }
            }

            semanticDiffSections

            if case let .loaded(diff) = store.semanticDiffStatus,
               !diff.sourceFileAttributions.isEmpty
            {
                Section("Source files") {
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
            }

            if showsTechnicalDetails {
                technicalSections
            }
        }
        .navigationTitle(store.review.title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .portableSafeAreaTopInset(spacing: 0) {
            VStack(spacing: 0) {
                Button(store.operation == .merging ? "Merging changes" : "Merge changes") {
                    store.send(.mergeButtonTapped)
                }
                .disabled(!store.canMerge || store.operation.isRunning)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()
            }
            .background(.background)
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("Close proposal", role: .destructive) {
                        store.send(.closeButtonTapped)
                    }
                    .disabled(store.operation.isRunning)

                    Button("Delete proposal permanently", role: .destructive) {
                        isDeleteConfirmationPresented = true
                    }
                    .disabled(store.operation.isRunning)
                } label: {
                    Label("Proposal actions", systemImage: "ellipsis-horizontal")
                }
            }
        }
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
    var operationSection: some View {
        switch store.operation {
        case .closing:
            Section { ProgressView("Closing proposal") }
        case .deleting:
            Section { ProgressView("Deleting proposal") }
        case .merging:
            Section { ProgressView("Applying changes") }
        case let .failed(message):
            Section {
                Text("The proposal could not be updated")
                    .foregroundStyle(.orange)
                if showsTechnicalDetails {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .selectableText()
                }
            }
        case .idle:
            EmptyView()
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

        let session = try SourceEditingSession(
            mainDatabase: reviewDatabase,
            baselineDatabasePath: baselineURL.path
        )
        return try await session.database.read { db in
            let summary = try SourceWorkspaceEditSummary.query(workspace: workspace, in: db)
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
