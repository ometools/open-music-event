import ATProto
import BlueskyActorCache
import ComposableArchitecture2
import ComposableAuthoring
import ComposableWorkspace
import ErrorHandling
import Foundation
import HTTPClient
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
import SourceEditing
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct WorkspaceReviews {
    public init() {}

    @Trigger var refreshReviews

    public struct ReviewFailure: CustomDebugStringConvertible, Equatable, Error, Sendable {
        public var message: String

        public var debugDescription: String { message }

        public init(_ error: any Error) {
            self.message = Self.message(for: error)
        }

        static func message(for error: any Error) -> String {
            guard case let HTTPError.httpError(status, body, _) = error else {
                return String(describing: error)
            }
            guard let bodyMessage = body.flatMap(httpResponseBodyMessage) else {
                return "HTTP \(status.code)"
            }
            return "HTTP \(status.code): \(bodyMessage)"
        }

        static func httpResponseBodyMessage(_ data: Data) -> String? {
            if let object = try? JSONSerialization.jsonObject(with: data),
               let json = object as? [String: Any]
            {
                let error = json["error"] as? String
                let message = json["message"] as? String
                switch (error?.isEmpty == false ? error : nil, message?.isEmpty == false ? message : nil) {
                case let (error?, message?):
                    return "\(error): \(message)"
                case let (error?, nil):
                    return error
                case let (nil, message?):
                    return message
                case (nil, nil):
                    break
                }
            }
            if let string = String(data: data, encoding: .utf8),
               !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return string
            }
            return nil
        }
    }

    public enum ReviewsStatus: Equatable, Sendable {
        case failed(ReviewFailure)
        case loaded([TangledPullReview])
        case loading
        case notLoaded
    }

    public enum ReviewOperationKind: Equatable, Sendable {
        case approve
        case close
        case delete
    }

    public enum ReviewOperation: Equatable, Sendable {
        case approving
        case closing
        case deleting
        case failed(ReviewOperationKind, ReviewFailure)
    }

    public struct SemanticDiffFailure: Equatable, Error, Sendable {
        public var message: String

        public init(_ error: any Error) {
            self.message = String(describing: error)
        }
    }

    public struct SemanticDiff: Equatable, Sendable {
        public var groups: [SourceChangeGroup]
        public var recordComparisons: SourceRecordComparisons
        public var sourceFileAttributions: [SourceFileAttribution]

        public init(
            groups: [SourceChangeGroup],
            recordComparisons: SourceRecordComparisons,
            sourceFileAttributions: [SourceFileAttribution] = []
        ) {
            self.groups = groups
            self.recordComparisons = recordComparisons
            self.sourceFileAttributions = sourceFileAttributions
        }

        public var totalCount: Int {
            groups.reduce(0) { $0 + $1.totalCount }
        }
    }

    public enum SemanticDiffStatus: Equatable, Sendable {
        case failed(SemanticDiffFailure)
        case loaded(SemanticDiff)
        case loading
        case notLoaded
    }

    public struct PendingDeletedReview: Equatable, Sendable {
        public var review: TangledPullReview
        public var index: Int

        public init(review: TangledPullReview, index: Int) {
            self.review = review
            self.index = index
        }
    }

    public enum SelectedReview: Equatable, Sendable {
        case loaded(TangledPullReview)

        public var id: String {
            switch self {
            case let .loaded(review):
                review.id
            }
        }

        public var review: TangledPullReview {
            switch self {
            case let .loaded(review):
                review
            }
        }
    }

    public struct State {
        public init(target: OpenMusicEventSourceTarget) {
            self._cachedActorIdentities = Fetch(
                wrappedValue: CachedActorIdentities(),
                CachedActorIdentitiesRequest()
            )
            self.target = target
            self._sourceBaseline = FetchOne(
                WorkspaceChanges.State.sourceBaselineQuery(target: target)
            )
            self._sourceProvenance = FetchOne(
                WorkspaceChanges.State.sourceProvenanceQuery(target: target)
            )
        }

        public let target: OpenMusicEventSourceTarget
        @DebugSnapshotIgnored
        @Fetch public var cachedActorIdentities: CachedActorIdentities
        public var locallyRemovedReviewIDs: Set<String> = []
        public var pendingCreatedReviewID: String?
        public var pendingDeletedReviews: [String: PendingDeletedReview] = [:]
        public var reviewOperations: [String: ReviewOperation] = [:]
        public var reviewsStatus: ReviewsStatus = .notLoaded
        public var selectedReview: SelectedReview?
        public var semanticDiffs: [String: SemanticDiffStatus] = [:]
        @DebugSnapshotIgnored
        @FetchOne public var sourceBaseline: SourceBaselineRecord?
        @DebugSnapshotIgnored
        @FetchOne public var sourceProvenance: EventSourceProvenanceRecord?
    }

    public enum Action {
        case approveButtonTapped(TangledPullReview)
        case closeButtonTapped(TangledPullReview)
        case deleteButtonTapped(TangledPullReview)
        case refreshButtonTapped
        case refreshSourceButtonTapped
        case reviewTapped(TangledPullReview)
        case showChangesButtonTapped(TangledPullReview)
    }

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
    @Dependency(\.tangledPullReviewClient) var tangledPullReviewClient
    @Dependency(\.tangledPullReviewSourceSnapshot) var tangledPullReviewSourceSnapshot
    @FeatureEnvironment(ComposableAuthoring.AuthoringContext<AuthoringGrant>.self)
    var authoring

    public var body: some Feature {
        let _ = Self._logChanges()
        Update { state, action in
            switch action {
            case let .approveButtonTapped(review):
                guard authoring.grant.wrappedValue?.role.canMerge == true,
                      state.reviewOperations[review.id]?.isRunning != true
                else { return }

                let target = state.target
                let tangledPullReviewClient = tangledPullReviewClient
                state.reviewOperations[review.id] = .approving
                store.addTask {
                    do {
                        try await tangledPullReviewClient.merge(
                            OpenMusicEventTangledPullReviewMergeRequest(
                                target: target,
                                review: review
                            )
                        )
                        try store.modify {
                            $0.reviewOperations[review.id] = nil
                            $0.remove(review)
                        }
                        let reconciliation = try store.post(
                            key: WorkspaceProposalMerged.self,
                            value: WorkspaceProposalID(rawValue: review.id)
                        )
                        await reconciliation?.value
                    } catch {
                        let failure = ReviewFailure(error)
                        await store.reportError(
                            failure,
                            fallbackMessage: .workspaceReviewApproveFailed,
                            operation: .workspaceReviewApprove
                        )
                        try store.modify {
                            $0.reviewOperations[review.id] = .failed(.approve, failure)
                        }
                    }
                }

            case let .closeButtonTapped(review):
                guard state.reviewOperations[review.id]?.isRunning != true else { return }
                let tangledPullReviewClient = tangledPullReviewClient
                state.reviewOperations[review.id] = .closing
                store.addTask {
                    do {
                        try await tangledPullReviewClient.close(review)
                        try store.modify {
                            $0.reviewOperations[review.id] = nil
                            $0.remove(review)
                        }
                    } catch {
                        let failure = ReviewFailure(error)
                        await store.reportError(
                            error,
                            fallbackMessage: .workspaceReviewCloseFailed,
                            operation: .workspaceReviewClose
                        )
                        try store.modify {
                            $0.reviewOperations[review.id] = .failed(.close, failure)
                        }
                    }
                }

            case let .deleteButtonTapped(review):
                guard state.reviewOperations[review.id]?.isRunning != true else { return }
                let tangledPullReviewClient = tangledPullReviewClient
                state.reviewOperations[review.id] = .deleting
                state.optimisticallyRemove(review)
                store.addTask {
                    do {
                        try await tangledPullReviewClient.delete(review)
                        try store.modify {
                            $0.reviewOperations[review.id] = nil
                            $0.pendingDeletedReviews[review.id] = nil
                        }
                    } catch {
                        let failure = ReviewFailure(error)
                        await store.reportError(
                            error,
                            fallbackMessage: .workspaceReviewDeleteFailed,
                            operation: .workspaceReviewDelete
                        )
                        try store.modify {
                            $0.restoreAfterFailedDelete(review)
                            $0.reviewOperations[review.id] = .failed(.delete, failure)
                        }
                    }
                }

            case .refreshButtonTapped:
                let refreshReviews = refreshReviews
                store.addTask {
                    try refreshReviews()
                }

            case .refreshSourceButtonTapped:
                store.addTask {
                    let reconciliation = try store.post(
                        key: WorkspaceReconciliationRequested.self,
                        value: ()
                    )
                    await reconciliation?.value
                }

            case let .reviewTapped(review):
                state.selectedReview = .loaded(review)

            case let .showChangesButtonTapped(review):
                switch state.semanticDiffs[review.id] {
                case .loaded, .loading:
                    return
                case .failed, .notLoaded, nil:
                    break
                }
                guard let sourceProvenance = state.sourceReviewProvenance else { return }

                let sourceSnapshot = tangledPullReviewSourceSnapshot
                let target = state.target
                state.semanticDiffs[review.id] = .loading
                store.addTask {
                    do {
                        let diff = try await SemanticDiff.reviewBranchDiff(
                            target: target,
                            review: review,
                            sourceProvenance: sourceProvenance,
                            sourceSnapshot: sourceSnapshot
                        )
                        try store.modify {
                            $0.semanticDiffs[review.id] = .loaded(diff)
                        }
                    } catch {
                        try store.modify {
                            $0.semanticDiffs[review.id] = .failed(SemanticDiffFailure(error))
                        }
                    }
                }
            }
        }
        .onMount { state in
            let refreshReviews = refreshReviews
            store.addTask {
                try refreshReviews()
            }
            if let actor = state.sourceContext?.ownerActorReference {
                let blueskyActorProfileCache = blueskyActorProfileCache
                store.addTask {
                    do {
                        _ = try await blueskyActorProfileCache.refreshProfileIfNeeded(
                            actor,
                            24 * 60 * 60,
                            15 * 60
                        )
                    } catch is CancellationError {
                    } catch {
                    }
                }
            }
        }
        .onTrigger(refreshReviews) { state in
            guard state.sourceKind == .tangled else {
                state.reviewsStatus = .notLoaded
                return
            }
            let target = state.target
            let tangledPullReviewClient = tangledPullReviewClient
            let blueskyActorProfileCache = blueskyActorProfileCache
            state.reviewsStatus = .loading
            store.addTask {
                do {
                    let reviews = try await tangledPullReviewClient.list(
                        OpenMusicEventTangledPullReviewRequest(target: target)
                    )
                    try store.modify {
                        let locallyRemovedReviewIDs = $0.locallyRemovedReviewIDs
                        let loadedReviews = reviews
                            .filter { !locallyRemovedReviewIDs.contains($0.id) }
                            .tangledPullReviewsSortedByDate
                        $0.reviewsStatus = .loaded(loadedReviews)
                        if let pendingReviewID = $0.pendingCreatedReviewID,
                           let review = loadedReviews.first(where: { $0.id == pendingReviewID })
                        {
                            $0.selectedReview = .loaded(review)
                            $0.pendingCreatedReviewID = nil
                        } else if let selectedReviewID = $0.selectedReview?.id,
                                  let review = loadedReviews.first(where: { $0.id == selectedReviewID })
                        {
                            $0.selectedReview = .loaded(review)
                        }
                    }
                    let authors = Set(reviews.map(\.author).filter { !$0.isEmpty })
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
                        }
                    }
                } catch {
                    await store.reportError(
                        error,
                        fallbackMessage: .workspaceReviewLoadFailed,
                        operation: .workspaceReviewLoad
                    )
                    try store.modify {
                        $0.reviewsStatus = .failed(ReviewFailure(error))
                    }
                }
            }
        }
    }
}

extension WorkspaceReviews.State {
    public func canReview(authoringAccess: AuthoringAccess) -> Bool {
        sourceKind == .tangled && authoringAccess.canMerge
    }

    public var sourceBaselineID: SourceBaselineRecord.ID? {
        switch target {
        case let .calendar(_, sourceBaselineID):
            sourceBaselineID
        case .event:
            sourceProvenance?.sourceBaselineID
        }
    }

    public var sourceKind: OMERecord.SourceDatabaseInsertion.SourceKind? {
        sourceBaseline?.sourceKind ?? sourceProvenance?.sourceKind
    }

    public var sourceReviewProvenance: OMERecord.SourceDatabaseInsertion.SourceProvenance? {
        sourceBaseline?.sourceProvenance ?? sourceProvenance?.sourceProvenance
    }

    var sourceContext: SourceWorkspaceSourceContext? {
        if let sourceBaseline {
            return SourceWorkspaceSourceContext(
                detailTitle: "Calendar source",
                sourceKind: sourceBaseline.sourceKind,
                sourceReference: sourceBaseline.sourceReference,
                sourceRefTitle: sourceBaseline.ref ?? "default version",
                ownerActorReference: sourceBaseline.sourceKind == .tangled
                    ? sourceBaseline.sourceReference.workspaceOwnerActorReference
                    : nil
            )
        }
        if let sourceProvenance {
            return SourceWorkspaceSourceContext(
                detailTitle: "Calendar source",
                sourceKind: sourceProvenance.sourceKind,
                sourceReference: sourceProvenance.sourceReference,
                sourceRefTitle: sourceProvenance.ref ?? "default version",
                ownerActorReference: sourceProvenance.sourceKind == .tangled
                    ? sourceProvenance.sourceReference.workspaceOwnerActorReference
                    : nil,
                technicalLocation: "events/\(sourceProvenance.sourceEventDirectory)"
            )
        }
        return nil
    }

    var workspaceOwnerIdentity: WorkspaceActorIdentity {
        guard let actor = sourceContext?.ownerActorReference,
              let identity = cachedActorIdentities[actor]
        else { return .unavailable }
        return .loaded(identity)
    }

    var reviewAuthorIdentities: [String: WorkspaceActorIdentity] {
        guard case let .loaded(reviews) = reviewsStatus else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: Set(reviews.map(\.author).filter { !$0.isEmpty })
                .map { author in
                    (
                        author,
                        cachedActorIdentities[author].map(WorkspaceActorIdentity.loaded)
                            ?? .unavailable
                    )
                }
        )
    }

    mutating func remove(_ review: TangledPullReview) {
        locallyRemovedReviewIDs.insert(review.id)
        reviewOperations[review.id] = nil
        semanticDiffs[review.id] = nil
        if selectedReview?.id == review.id {
            selectedReview = nil
        }
        if case let .loaded(reviews) = reviewsStatus {
            reviewsStatus = .loaded(reviews.filter { $0.id != review.id })
        }
    }

    mutating func optimisticallyRemove(_ review: TangledPullReview) {
        pendingDeletedReviews[review.id] = nil
        if case let .loaded(reviews) = reviewsStatus,
           let index = reviews.firstIndex(where: { $0.id == review.id })
        {
            pendingDeletedReviews[review.id] = WorkspaceReviews.PendingDeletedReview(
                review: reviews[index],
                index: index
            )
        }
        remove(review)
        reviewOperations[review.id] = .deleting
    }

    mutating func restoreAfterFailedDelete(_ review: TangledPullReview) {
        locallyRemovedReviewIDs.remove(review.id)
        let pendingRemoval = pendingDeletedReviews.removeValue(forKey: review.id)
        let restoredReview = pendingRemoval?.review ?? review
        guard case var .loaded(reviews) = reviewsStatus,
              !reviews.contains(where: { $0.id == restoredReview.id })
        else { return }
        let index = min(pendingRemoval?.index ?? reviews.count, reviews.count)
        reviews.insert(restoredReview, at: index)
        reviewsStatus = .loaded(reviews.tangledPullReviewsSortedByDate)
    }
}

extension Collection where Element == TangledPullReview {
    var tangledPullReviewsSortedByDate: [TangledPullReview] {
        sorted { lhs, rhs in
            switch (
                lhs.createdAt.tangledPullReviewCreatedAtDate,
                rhs.createdAt.tangledPullReviewCreatedAtDate
            ) {
            case let (.some(lhsDate), .some(rhsDate)):
                lhsDate > rhsDate
            case (.some(_), .none):
                true
            case (.none, .some(_)):
                false
            case (.none, .none):
                lhs.createdAt > rhs.createdAt
            }
        }
    }
}

extension WorkspaceReviews.ReviewOperation {
    var isRunning: Bool {
        switch self {
        case .approving, .closing, .deleting:
            true
        case .failed:
            false
        }
    }

    var failure: WorkspaceReviews.ReviewFailure? {
        guard case let .failed(_, failure) = self else { return nil }
        return failure
    }
}

extension WorkspaceReviews.ReviewsStatus {
    var isLoading: Bool {
        self == .loading
    }
}

extension String {
    var workspaceOwnerActorReference: String? {
        if hasPrefix("at://") {
            return String(dropFirst(5))
                .split(separator: "/", omittingEmptySubsequences: true)
                .first
                .map(String.init)
        }
        guard let repository = try? TangledRepositoryReference(parsing: self) else {
            return nil
        }
        let owner = repository.owner
        return owner.hasPrefix("@") ? String(owner.dropFirst()) : owner
    }
}

extension UserFacingText {
    static let workspaceReviewLoadFailed = Self(
        "Unable to load Tangled pull reviews.",
        fallback: "Unable to load Tangled pull reviews."
    )
    static let workspaceReviewCloseFailed = Self(
        "Unable to close Tangled pull review.",
        fallback: "Unable to close Tangled pull review."
    )
    static let workspaceReviewDeleteFailed = Self(
        "Unable to delete Tangled pull review.",
        fallback: "Unable to delete Tangled pull review."
    )
    static let workspaceReviewApproveFailed = Self(
        "Unable to merge Tangled pull review.",
        fallback: "Unable to merge Tangled pull review."
    )
}

extension ErrorOperation {
    static let workspaceReviewLoad = Self("tangled.pull-review.load")
    static let workspaceReviewClose = Self("tangled.pull-review.close")
    static let workspaceReviewDelete = Self("tangled.pull-review.delete")
    static let workspaceReviewApprove = Self("tangled.pull-review.merge")
}

public struct WorkspaceReviewsView: View {
    @Bindable var store: StoreOf<WorkspaceReviews>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    @Environment(\.openMusicEventWorkspacePhase) var workspacePhase

    public init(store: StoreOf<WorkspaceReviews>) {
        self.store = store
    }

    public var body: some View {
        List {
            Section("Source") {
                if let sourceContext = store.sourceContext {
                    SourceIndicatorView(sourceContext: sourceContext)

                    Button {
                        store.send(.refreshSourceButtonTapped)
                    } label: {
                        if workspacePhase.isReconciling {
                            HStack {
                                ProgressView()
                                Text("Refreshing Source")
                            }
                        } else {
                            Label("Refresh Source", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(
                        store.sourceBaselineID == nil
                            || !workspacePhase.canRequestReconciliation
                    )

                    if let failure = workspacePhase.reconciliationFailure,
                       showsTechnicalDetails
                    {
                        Text(failure.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .selectableText()
                    }
                } else {
                    Text("Open a shared workspace to review changes.")
                        .foregroundStyle(.secondary)
                }
            }

            if store.sourceKind == .tangled {
                Section("Reviews") {
                    switch store.reviewsStatus {
                    case let .failed(failure):
                        VStack(alignment: .leading, spacing: 4) {
                            Label(
                                "Reviews could not be loaded",
                                systemImage: "exclamationmark.triangle"
                            )
                            .foregroundStyle(.orange)
                            if showsTechnicalDetails {
                                Text(failure.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .selectableText()
                            }
                        }

                    case let .loaded(reviews):
                        if reviews.isEmpty {
                            Label("No open reviews", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(reviews) { review in
                                let operation = store.reviewOperations[review.id]
                                let isApproving = operation == .approving
                                let isClosing = operation == .closing
                                let isDeleting = operation == .deleting
                                let isBusy = operation?.isRunning == true
                                let failure = operation?.failure

                                NavigationLink {
                                    WorkspaceReviewDetailView(
                                        store: store,
                                        selectedReview: .loaded(review)
                                    )
                                } label: {
                                    TangledPullReviewRow(
                                        review: review,
                                        authorIdentity: store.reviewAuthorIdentities[review.author]
                                            ?? .unavailable,
                                        isClosing: isClosing,
                                        isDeleting: isDeleting,
                                        isMerging: isApproving,
                                        closeFailure: operation?.failure(for: .close),
                                        deleteFailure: operation?.failure(for: .delete),
                                        mergeFailure: operation?.failure(for: .approve)
                                    )
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        store.send(.approveButtonTapped(review))
                                    } label: {
                                        Text(isApproving ? "Applying" : "Approve")
                                    }
                                    .disabled(isBusy)
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        store.send(.deleteButtonTapped(review))
                                    } label: {
                                        Text(isDeleting ? "Deleting" : "Delete")
                                    }
                                    .disabled(isBusy)

                                    Button {
                                        store.send(.closeButtonTapped(review))
                                    } label: {
                                        Text(isClosing ? "Closing" : "Close")
                                    }
                                    .disabled(isBusy)
                                    .tint(.orange)
                                }
                                .contextMenu {
                                    Button {
                                        store.send(.approveButtonTapped(review))
                                    } label: {
                                        Text("Approve changes")
                                    }
                                    .disabled(isBusy)

                                    Button(role: .destructive) {
                                        store.send(.closeButtonTapped(review))
                                    } label: {
                                        Text("Close review")
                                    }
                                    .disabled(isBusy)

                                    Button(role: .destructive) {
                                        store.send(.deleteButtonTapped(review))
                                    } label: {
                                        Text("Delete review permanently")
                                    }
                                    .disabled(isBusy)
                                }

                                if let failure, showsTechnicalDetails {
                                    Text(failure.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .selectableText()
                                }
                            }
                        }

                    case .loading:
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading reviews")
                        }

                    case .notLoaded:
                        Text("Open reviews have not been loaded")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        store.send(.refreshButtonTapped)
                    } label: {
                        Label(
                            store.reviewsStatus.isLoading
                                ? "Loading Reviews"
                                : "Refresh Reviews",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(store.reviewsStatus.isLoading)
                }
            } else {
                ExistingProposalsSection(
                    title: "Reviews",
                    emptyTitle: "No changes waiting for review",
                    state: .loaded([])
                )
            }
        }
    }
}

public struct WorkspaceReviewDetailView: View {
    let store: StoreOf<WorkspaceReviews>
    let selectedReview: WorkspaceReviews.SelectedReview

    public init(
        store: StoreOf<WorkspaceReviews>,
        selectedReview: WorkspaceReviews.SelectedReview
    ) {
        self.store = store
        self.selectedReview = selectedReview
    }

    public var body: some View {
        let review = selectedReview.review
        let operation = store.reviewOperations[review.id]
        TangledPullReviewDetailView(
            review: review,
            authorIdentity: store.reviewAuthorIdentities[review.author] ?? .unavailable,
            semanticDiffStatus: store.semanticDiffs[review.id] ?? .notLoaded,
            isClosing: operation == .closing,
            isDeleting: operation == .deleting,
            isMerging: operation == .approving,
            isBusy: operation?.isRunning == true,
            mergeFailure: operation?.failure(for: .approve),
            onLoadSemanticDiff: {
                store.send(.showChangesButtonTapped(review))
            },
            onMerge: {
                store.send(.approveButtonTapped(review))
            },
            onClose: {
                store.send(.closeButtonTapped(review))
            },
            onDelete: {
                store.send(.deleteButtonTapped(review))
            }
        )
    }
}

extension WorkspaceReviews.ReviewOperation {
    func failure(
        for operation: WorkspaceReviews.ReviewOperationKind
    ) -> WorkspaceReviews.ReviewFailure? {
        guard case let .failed(failedOperation, failure) = self,
              failedOperation == operation
        else { return nil }
        return failure
    }
}
