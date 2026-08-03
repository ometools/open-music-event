import ComposableArchitecture2
import ComposableAuthoring
import ComposableWorkspace
import Dependencies
import OpenMusicEventSourceEditing
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

    public enum Operation: Equatable, Sendable {
        case closing
        case deleting
        case failed(String)
        case merging

        var isRunning: Bool {
            switch self {
            case .closing, .deleting, .merging: true
            case .failed: false
            }
        }
    }

    public struct State {
        public init(workspace: SourceWorkspace) {
            self.workspace = workspace
        }

        public let workspace: SourceWorkspace
        public var locallyRemovedReviewIDs: Set<String> = []
        public var operations: [String: Operation] = [:]
        public var pendingCreatedReviewID: String?
        public var status: Status = .notLoaded

        public var reviews: [TangledPullReview] {
            guard case let .loaded(reviews) = status else { return [] }
            return reviews
        }

        public func canReview(authoringAccess: AuthoringAccess) -> Bool {
            authoringAccess.canMerge
        }

        mutating func remove(_ review: TangledPullReview) {
            locallyRemovedReviewIDs.insert(review.id)
            operations[review.id] = nil
            if case let .loaded(reviews) = status {
                status = .loaded(reviews.filter { $0.id != review.id })
            }
        }
    }

    public enum Action {
        case closeButtonTapped(TangledPullReview)
        case deleteButtonTapped(TangledPullReview)
        case mergeButtonTapped(TangledPullReview)
        case refreshButtonTapped
        case refreshSourceButtonTapped
    }

    @Dependency(\.tangledPullReviewClient) var reviewClient
    @FeatureEnvironment(ComposableAuthoring.AuthoringContext<AuthoringGrant>.self)
    var authoring

    public var body: some Feature {
        Update { state, action in
            switch action {
            case let .mergeButtonTapped(review):
                guard authoring.grant.wrappedValue?.role.canMerge == true,
                      state.operations[review.id]?.isRunning != true
                else { return }
                let target = OpenMusicEventSourceTarget(workspace: state.workspace)
                let reviewClient = reviewClient
                state.operations[review.id] = .merging
                store.addTask {
                    do {
                        try await reviewClient.merge(
                            OpenMusicEventTangledPullReviewMergeRequest(
                                target: target,
                                review: review
                            )
                        )
                        try store.modify { $0.remove(review) }
                        let reconciliation = try store.post(
                            key: WorkspaceProposalMerged.self,
                            value: WorkspaceProposalID(rawValue: review.id)
                        )
                        await reconciliation?.value
                    } catch {
                        try store.modify {
                            $0.operations[review.id] = .failed(String(describing: error))
                        }
                    }
                }

            case let .closeButtonTapped(review):
                guard state.operations[review.id]?.isRunning != true else { return }
                let reviewClient = reviewClient
                state.operations[review.id] = .closing
                store.addTask {
                    do {
                        try await reviewClient.close(review)
                        try store.modify { $0.remove(review) }
                    } catch {
                        try store.modify {
                            $0.operations[review.id] = .failed(String(describing: error))
                        }
                    }
                }

            case let .deleteButtonTapped(review):
                guard state.operations[review.id]?.isRunning != true else { return }
                let reviewClient = reviewClient
                state.operations[review.id] = .deleting
                store.addTask {
                    do {
                        try await reviewClient.delete(review)
                        try store.modify { $0.remove(review) }
                    } catch {
                        try store.modify {
                            $0.operations[review.id] = .failed(String(describing: error))
                        }
                    }
                }

            case .refreshButtonTapped:
                loadReviews(state: &state)

            case .refreshSourceButtonTapped:
                store.addTask {
                    let reconciliation = try store.post(
                        key: WorkspaceReconciliationRequested.self,
                        value: ()
                    )
                    await reconciliation?.value
                }
            }
        }
        .onMount { state in
            loadReviews(state: &state)
        }
    }

    private func loadReviews(state: inout State) {
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

public struct WorkspaceReviewsView: View {
    @Bindable var store: StoreOf<WorkspaceReviews>
    @Environment(\.openMusicEventWorkspacePhase) var phase
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    public init(store: StoreOf<WorkspaceReviews>) {
        self.store = store
    }

    public var body: some View {
        List {
            Section("Source") {
                LabeledContent("Repository", value: store.workspace.repository)
                LabeledContent("Branch", value: store.workspace.branch)
                LabeledContent("Organization", value: store.workspace.organizerID.description)

                Button("Reconcile with source") {
                    store.send(.refreshSourceButtonTapped)
                }
                .disabled(!phase.canRequestReconciliation)

                WorkspacePublicationStatusView(phase: phase)
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
                        WorkspaceReviewRow(
                            review: review,
                            operation: store.operations[review.id],
                            canMerge: true,
                            merge: { store.send(.mergeButtonTapped(review)) },
                            close: { store.send(.closeButtonTapped(review)) },
                            delete: { store.send(.deleteButtonTapped(review)) }
                        )
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
    }
}

struct WorkspaceReviewRow: View {
    let review: TangledPullReview
    let operation: WorkspaceReviews.Operation?
    let canMerge: Bool
    let merge: () -> Void
    let close: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(review.title).font(.headline)
            Text(review.author).font(.caption).foregroundStyle(.secondary)
            if let body = review.body, !body.isEmpty {
                Text(body).font(.caption)
            }
            if let operation {
                switch operation {
                case .merging: ProgressView("Merging")
                case .closing: ProgressView("Closing")
                case .deleting: ProgressView("Deleting")
                case let .failed(message):
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
            HStack {
                Button("Merge", action: merge)
                    .disabled(!canMerge || operation?.isRunning == true)
                Button("Close", action: close)
                    .disabled(operation?.isRunning == true)
                Button("Delete", role: .destructive, action: delete)
                    .disabled(operation?.isRunning == true)
            }
        }
    }
}
