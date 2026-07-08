import ComposableArchitecture2
import Foundation
import GRDB
import Lexicon
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SourceEditing
import SQLiteData
import SwiftUI

@Feature
public struct EventWorkspace {
    public init() {}

    public enum SourcePatchStatus: Equatable, Sendable {
        case failed(SourcePatchGenerationFailure)
        case generated(SourcePatch)
        case generating
        case needsGeneration(SourcePatchInvalidation)
        case notGenerated
    }

    public enum SourceProposalStatus: Equatable, Sendable {
        case composing
        case created(SourcePatchPublication)
        case failed(SourceProposalFailure)
        case idle
        case proposing
    }

    public enum TangledPullReviewStatus: Equatable, Sendable {
        case failed(TangledPullReviewFailure)
        case loaded([TangledPullReview])
        case loading
        case notLoaded
    }

    public enum TangledPullReviewSemanticDiffStatus: Equatable, Sendable {
        case failed(TangledPullReviewSemanticDiffFailure)
        case loaded(TangledPullReviewSemanticDiff)
        case loading
        case notLoaded
    }

    public struct SourcePatchGenerationFailure: Equatable, Error, Sendable {
        public var message: String

        public init(_ error: any Error) {
            self.message = String(describing: error)
        }
    }

    public struct SourceProposalFailure: Equatable, Error, Sendable {
        public var message: String

        public init(_ error: any Error) {
            self.message = String(describing: error)
        }
    }

    public struct ResetEditsFailure: Equatable, Error, Sendable {
        public var message: String

        public init(_ error: any Error) {
            self.message = String(describing: error)
        }
    }

    public struct TangledPullReviewFailure: Equatable, Error, Sendable {
        public var message: String

        public init(_ error: any Error) {
            self.message = String(describing: error)
        }
    }

    public struct TangledPullReviewCloseFailure: Equatable, Error, Sendable {
        public var message: String

        public init(_ error: any Error) {
            self.message = String(describing: error)
        }
    }

    public struct TangledPullReviewDeleteFailure: Equatable, Error, Sendable {
        public var message: String

        public init(_ error: any Error) {
            self.message = String(describing: error)
        }
    }

    public struct TangledPullReviewSemanticDiffFailure: Equatable, Error, Sendable {
        public var message: String

        public init(_ error: any Error) {
            self.message = String(describing: error)
        }
    }

    public struct TangledPullReviewSemanticDiff: Equatable, Sendable {
        public var groups: [SourceChangeGroup]
        public var recordComparisons: SourceRecordComparisons

        public init(
            groups: [SourceChangeGroup],
            recordComparisons: SourceRecordComparisons
        ) {
            self.groups = groups
            self.recordComparisons = recordComparisons
        }

        public var totalCount: Int {
            groups.reduce(0) { $0 + $1.totalCount }
        }
    }

    public struct PendingDeletedTangledPullReview: Equatable, Sendable {
        public var review: TangledPullReview
        public var index: Int

        public init(review: TangledPullReview, index: Int) {
            self.review = review
            self.index = index
        }
    }

    public struct ResetEditsSuccess: Equatable, Sendable {
        public init() {}
    }

    public struct State {
        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
            self._workspaceSummary = Fetch(
                wrappedValue: EventWorkspaceSummary(
                    eventID: eventID,
                    availability: .notInWorkspace,
                    groups: []
                ),
                EventWorkspaceSummaryRequest(eventID: eventID)
            )
            self._sourceProvenance = FetchOne(
                EventSourceProvenanceRecord.where { $0.id.eq(eventID) }
            )
        }

        public let eventID: OMERecord.Event.ID
        @DebugSnapshotIgnored
        @Fetch public var workspaceSummary: EventWorkspaceSummary
        public var isPreparingSourceProposal = false
        public var isResettingEdits = false
        public var resetEditsFailure: ResetEditsFailure?
        public var sourcePatchStatus: SourcePatchStatus = .notGenerated
        public var sourceProposalStatus: SourceProposalStatus = .idle
        @DebugSnapshotIgnored
        public var sourceProposal: SourceProposalFlow.State?
        public var tangledPullReviewStatus: TangledPullReviewStatus = .notLoaded
        public var locallyRemovedTangledPullReviewIDs: Set<String> = []
        public var closingTangledPullReviewIDs: Set<String> = []
        public var deletingTangledPullReviewIDs: Set<String> = []
        public var pendingDeletedTangledPullReviews:
            [String: PendingDeletedTangledPullReview] = [:]
        public var tangledPullReviewCloseFailures: [String: TangledPullReviewCloseFailure] = [:]
        public var tangledPullReviewDeleteFailures: [String: TangledPullReviewDeleteFailure] = [:]
        public var tangledPullReviewSemanticDiffs: [String: TangledPullReviewSemanticDiffStatus] = [:]
        @FetchOne public var sourceProvenance: EventSourceProvenanceRecord?

        public var changeCount: Int? {
            workspaceSummary.badgeCount
        }

        public var sourceChangesScope: SourceChangesScope {
            .event(eventID)
        }
    }

    public enum Action {
        case closeTangledPullReviewButtonTapped(TangledPullReview)
        case deleteTangledPullReviewForeverButtonTapped(TangledPullReview)
        case generateSourcePatchButtonTapped
        case proposeChangeButtonTapped
        case reviewSemanticDiffButtonTapped(TangledPullReview)
        case refreshTangledPullReviewsButtonTapped
        case refreshSourceButtonTapped
        case resetEditsButtonTapped
        case resetEditsResponse(Result<ResetEditsSuccess, ResetEditsFailure>)
        case sourcePatchGenerationResponse(Result<SourcePatch, SourcePatchGenerationFailure>)
        case sourcePatchInvalidationReceived(SourcePatchInvalidation)
        case sourceProposal(SourceProposalFlow.Action)
        case tangledPullReviewSemanticDiffResponse(
            reviewID: String,
            Result<TangledPullReviewSemanticDiff, TangledPullReviewSemanticDiffFailure>
        )
        case tangledPullReviewCloseResponse(
            review: TangledPullReview,
            Result<Void, TangledPullReviewCloseFailure>
        )
        case tangledPullReviewDeleteResponse(
            review: TangledPullReview,
            Result<Void, TangledPullReviewDeleteFailure>
        )
        case tangledPullReviewsResponse(Result<[TangledPullReview], TangledPullReviewFailure>)
    }

    @Dependency(\.eventWorkspaceResetter) var workspaceResetter
    @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var sourcePatchGenerator
    @Dependency(\.sourcePatchInvalidations) var sourcePatchInvalidations
    @Dependency(\.tangledPullReviewClient) var tangledPullReviewClient
    @Dependency(\.tangledPullReviewSourceSnapshot) var tangledPullReviewSourceSnapshot
    public var body: some Feature {
        Update { state, action in
            func generateSourcePatch(
                eventID: OMERecord.Event.ID,
                state: inout State
            ) {
                guard state.canReviewSourceProposal else { return }
                let sourcePatchGenerator = sourcePatchGenerator
                state.sourcePatchStatus = .generating
                store.addTask {
                    do {
                        let patch = try await sourcePatchGenerator.generate(
                            OpenMusicEventSourcePatchRequest(eventID: eventID)
                        )
                        try store.send(.sourcePatchGenerationResponse(.success(patch)))
                    } catch {
                        try store.send(
                            .sourcePatchGenerationResponse(
                                .failure(SourcePatchGenerationFailure(error))
                            )
                        )
                    }
                }
            }

            func refreshTangledPullReviews(
                eventID: OMERecord.Event.ID,
                state: inout State
            ) {
                guard state.sourceProvenance?.sourceKind == .tangled else {
                    state.tangledPullReviewStatus = .notLoaded
                    return
                }

                let tangledPullReviewClient = tangledPullReviewClient
                state.tangledPullReviewStatus = .loading
                store.addTask {
                    do {
                        let reviews = try await tangledPullReviewClient.list(
                            OpenMusicEventTangledPullReviewRequest(eventID: eventID)
                        )
                        try store.send(.tangledPullReviewsResponse(.success(reviews)))
                    } catch {
                        try store.send(
                            .tangledPullReviewsResponse(
                                .failure(TangledPullReviewFailure(error))
                            )
                        )
                    }
                }
            }

            func loadTangledPullReviewSemanticDiff(
                review: TangledPullReview,
                state: inout State
            ) {
                switch state.tangledPullReviewSemanticDiffs[review.id] {
                case .loaded, .loading:
                    return
                case .failed, .notLoaded, nil:
                    break
                }
                guard let sourceProvenance = state.sourceProvenance else { return }
                let eventID = state.eventID
                let sourceSnapshot = tangledPullReviewSourceSnapshot
                state.tangledPullReviewSemanticDiffs[review.id] = .loading
                store.addTask {
                    do {
                        let diff = try await TangledPullReviewSemanticDiff.reviewBranchDiff(
                            eventID: eventID,
                            review: review,
                            sourceProvenance: sourceProvenance.sourceProvenance,
                            sourceSnapshot: sourceSnapshot
                        )
                        try store.send(
                            .tangledPullReviewSemanticDiffResponse(
                                reviewID: review.id,
                                .success(diff)
                            )
                        )
                    } catch {
                        try store.send(
                            .tangledPullReviewSemanticDiffResponse(
                                reviewID: review.id,
                                .failure(TangledPullReviewSemanticDiffFailure(error))
                            )
                        )
                    }
                }
            }

            func closeTangledPullReview(
                _ review: TangledPullReview,
                state: inout State
            ) {
                guard !state.closingTangledPullReviewIDs.contains(review.id),
                      !state.deletingTangledPullReviewIDs.contains(review.id)
                else { return }

                let tangledPullReviewClient = tangledPullReviewClient
                state.closingTangledPullReviewIDs.insert(review.id)
                state.tangledPullReviewCloseFailures[review.id] = nil
                store.addTask {
                    do {
                        try await tangledPullReviewClient.close(review)
                        try store.send(
                            .tangledPullReviewCloseResponse(review: review, .success(()))
                        )
                    } catch {
                        try store.send(
                            .tangledPullReviewCloseResponse(
                                review: review,
                                .failure(TangledPullReviewCloseFailure(error))
                            )
                        )
                    }
                }
            }

            func deleteTangledPullReviewForever(
                _ review: TangledPullReview,
                state: inout State
            ) {
                guard !state.deletingTangledPullReviewIDs.contains(review.id),
                      !state.closingTangledPullReviewIDs.contains(review.id)
                else { return }

                let tangledPullReviewClient = tangledPullReviewClient
                state.deletingTangledPullReviewIDs.insert(review.id)
                optimisticallyRemoveDeletedTangledPullReview(review, state: &state)
                store.addTask {
                    do {
                        try await tangledPullReviewClient.delete(review)
                        try store.send(
                            .tangledPullReviewDeleteResponse(review: review, .success(()))
                        )
                    } catch {
                        try store.send(
                            .tangledPullReviewDeleteResponse(
                                review: review,
                                .failure(TangledPullReviewDeleteFailure(error))
                            )
                        )
                    }
                }
            }

            func optimisticallyRemoveDeletedTangledPullReview(
                _ review: TangledPullReview,
                state: inout State
            ) {
                state.pendingDeletedTangledPullReviews[review.id] = nil
                if case let .loaded(reviews) = state.tangledPullReviewStatus,
                   let index = reviews.firstIndex(where: { $0.id == review.id })
                {
                    state.pendingDeletedTangledPullReviews[review.id] =
                        PendingDeletedTangledPullReview(
                            review: reviews[index],
                            index: index
                        )
                }
                removeTangledPullReviewFromLoadedState(review, state: &state)
            }

            func removeTangledPullReviewFromLoadedState(
                _ review: TangledPullReview,
                state: inout State
            ) {
                state.locallyRemovedTangledPullReviewIDs.insert(review.id)
                state.tangledPullReviewCloseFailures[review.id] = nil
                state.tangledPullReviewDeleteFailures[review.id] = nil
                state.tangledPullReviewSemanticDiffs[review.id] = nil
                if case let .loaded(reviews) = state.tangledPullReviewStatus {
                    state.tangledPullReviewStatus = .loaded(
                        reviews.filter { $0.id != review.id }
                    )
                }
            }

            func restoreTangledPullReviewAfterFailedDelete(
                _ review: TangledPullReview,
                state: inout State
            ) {
                state.locallyRemovedTangledPullReviewIDs.remove(review.id)
                let pendingRemoval = state.pendingDeletedTangledPullReviews
                    .removeValue(forKey: review.id)
                let restoredReview = pendingRemoval?.review ?? review
                guard case var .loaded(reviews) = state.tangledPullReviewStatus,
                      !reviews.contains(where: { $0.id == restoredReview.id })
                else { return }

                let index = min(pendingRemoval?.index ?? reviews.count, reviews.count)
                reviews.insert(restoredReview, at: index)
                state.tangledPullReviewStatus = .loaded(reviews)
            }

            switch action {
            case let .closeTangledPullReviewButtonTapped(review):
                closeTangledPullReview(review, state: &state)

            case let .deleteTangledPullReviewForeverButtonTapped(review):
                deleteTangledPullReviewForever(review, state: &state)

            case .generateSourcePatchButtonTapped:
                generateSourcePatch(eventID: state.eventID, state: &state)
                refreshTangledPullReviews(eventID: state.eventID, state: &state)

            case .refreshSourceButtonTapped:
                guard let sourceBaselineID = state.sourceProvenance?.sourceBaselineID else {
                    return
                }
                let request = SourceDataRefreshRequest(
                    eventID: state.eventID,
                    sourceBaselineID: sourceBaselineID
                )
                store.addTask {
                    try store.post(key: SourceDataRefreshRequested.self, value: request)
                }

            case .refreshTangledPullReviewsButtonTapped:
                refreshTangledPullReviews(eventID: state.eventID, state: &state)

            case .resetEditsButtonTapped:
                guard !state.isResettingEdits else { return }
                let workspaceResetter = workspaceResetter
                let eventID = state.eventID
                state.isResettingEdits = true
                state.resetEditsFailure = nil
                store.addTask {
                    do {
                        try workspaceResetter.reset(eventID)
                        try store.send(.resetEditsResponse(.success(ResetEditsSuccess())))
                    } catch {
                        try store.send(
                            .resetEditsResponse(
                                .failure(ResetEditsFailure(error))
                            )
                        )
                    }
                }

            case .resetEditsResponse(.success):
                state.isResettingEdits = false
                state.isPreparingSourceProposal = false
                state.resetEditsFailure = nil
                state.sourcePatchStatus = .generated(SourcePatch())
                state.sourceProposal = nil
                state.sourceProposalStatus = .idle

            case let .resetEditsResponse(.failure(failure)):
                state.isResettingEdits = false
                state.resetEditsFailure = failure

            case .sourceProposal(.delegate(.dismissed)):
                state.isPreparingSourceProposal = false
                state.sourceProposal = nil
                switch state.sourceProposalStatus {
                case .composing, .failed:
                    state.sourceProposalStatus = .idle
                case .created, .idle, .proposing:
                    break
                }

            case .proposeChangeButtonTapped:
                guard state.canReviewSourceProposal else { return }
                guard case let .generated(patch) = state.sourcePatchStatus else {
                    state.isPreparingSourceProposal = true
                    generateSourcePatch(eventID: state.eventID, state: &state)
                    return
                }
                guard !patch.isEmpty else { return }
                state.presentSourceProposal(for: patch)

            case let .reviewSemanticDiffButtonTapped(review):
                loadTangledPullReviewSemanticDiff(review: review, state: &state)

            case let .sourcePatchGenerationResponse(.success(patch)):
                state.sourcePatchStatus = .generated(patch)
                if state.isPreparingSourceProposal {
                    state.isPreparingSourceProposal = false
                    state.presentSourceProposal(for: patch)
                } else {
                    state.sourceProposal = nil
                    state.sourceProposalStatus = .idle
                }

            case let .sourcePatchGenerationResponse(.failure(failure)):
                state.isPreparingSourceProposal = false
                state.sourcePatchStatus = .failed(failure)
                state.sourceProposal = nil
                state.sourceProposalStatus = .idle

            case let .sourcePatchInvalidationReceived(invalidation):
                state.isPreparingSourceProposal = false
                state.sourcePatchStatus = .needsGeneration(invalidation)
                state.sourceProposal = nil
                state.sourceProposalStatus = .idle

            case .sourceProposal(.createProposalButtonTapped):
                state.sourceProposalStatus = .proposing

            case .sourceProposal(.sourceProposalCancelled):
                state.sourceProposalStatus = .composing

            case let .sourceProposal(.sourceProposalResponse(.success(publication))):
                state.sourceProposalStatus = .created(publication)

            case let .sourceProposal(.sourceProposalResponse(.failure(failure))):
                state.sourceProposalStatus = .failed(failure)

            case .sourceProposal:
                break

            case let .tangledPullReviewSemanticDiffResponse(reviewID, .success(diff)):
                state.tangledPullReviewSemanticDiffs[reviewID] = .loaded(diff)

            case let .tangledPullReviewSemanticDiffResponse(reviewID, .failure(failure)):
                state.tangledPullReviewSemanticDiffs[reviewID] = .failed(failure)

            case let .tangledPullReviewCloseResponse(review, .success):
                state.closingTangledPullReviewIDs.remove(review.id)
                removeTangledPullReviewFromLoadedState(review, state: &state)

            case let .tangledPullReviewCloseResponse(review, .failure(failure)):
                state.closingTangledPullReviewIDs.remove(review.id)
                state.tangledPullReviewCloseFailures[review.id] = failure

            case let .tangledPullReviewDeleteResponse(review, .success):
                state.deletingTangledPullReviewIDs.remove(review.id)
                state.pendingDeletedTangledPullReviews[review.id] = nil

            case let .tangledPullReviewDeleteResponse(review, .failure(failure)):
                state.deletingTangledPullReviewIDs.remove(review.id)
                restoreTangledPullReviewAfterFailedDelete(review, state: &state)
                state.tangledPullReviewDeleteFailures[review.id] = failure

            case let .tangledPullReviewsResponse(.success(reviews)):
                state.tangledPullReviewStatus = .loaded(
                    reviews.filter { !state.locallyRemovedTangledPullReviewIDs.contains($0.id) }
                )

            case let .tangledPullReviewsResponse(.failure(failure)):
                state.tangledPullReviewStatus = .failed(failure)
            }
        }
        .onMount { state in
            let eventID = state.eventID
            store.addTask {
                for await invalidation in sourcePatchInvalidations.stream() {
                    guard invalidation.eventID == eventID else { continue }
                    try store.send(.sourcePatchInvalidationReceived(invalidation))
                }
            }
        }
        .ifLet(\.sourceProposal, action: \.sourceProposal) {
            SourceProposalFlow()
        }
    }
}

public struct EventWorkspaceView: View {
    @Bindable var store: StoreOf<EventWorkspace>
    @State var selectedTab: EventWorkspaceTab = .propose

    public init(store: StoreOf<EventWorkspace>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            workspaceContextHeader
            workspaceTabPicker
            workspaceTabContent
        }
        .navigationTitle("Workspace")
        .sourceChangeRowStyle(OpenMusicEventSourceChangeRowStyle())
        .sheet(item: $store.scope(\.sourceProposal, action: \.sourceProposal)) { proposalStore in
            SourceProposalComposerView(store: proposalStore)
        }
    }

    @ViewBuilder
    private var workspaceContextHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(store.workspaceSummary.totalCount, format: .number)
                        .font(.title3)
                        .monospacedDigit()
                }

                Spacer()

                if let sourceProvenance = store.sourceProvenance {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(sourceProvenance.sourceKind.sourceIndicatorTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(sourceProvenance.sourceEventDirectory)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
            }

            if let sourceProvenance = store.sourceProvenance {
                Text(sourceProvenance.sourceReference)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var workspaceTabPicker: some View {
        Picker("Workspace", selection: $selectedTab) {
            ForEach(EventWorkspaceTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var workspaceTabContent: some View {
        switch store.workspaceSummary.availability {
        case .available:
            switch selectedTab {
            case .propose:
                proposeList
            case .review:
                reviewList
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

    @ViewBuilder
    private var proposeList: some View {
        List {
            changesActionSection
            semanticDiffSections
            sourceDiffSections
            resetEditsSection
        }
    }

    @ViewBuilder
    private var reviewList: some View {
        List {
            sourceSection
            reviewSection
        }
    }

    @ViewBuilder
    private var changesActionSection: some View {
        Section {
            if store.workspaceSummary.totalCount == 0 {
                Text("No unpublished changes")
                    .foregroundStyle(.secondary)
            } else if store.canReviewSourceProposal {
                Button(store.sourcePatchStatus.proposeButtonTitle) {
                    store.send(.proposeChangeButtonTapped)
                }
                .disabled(!store.canProposeLocalChanges)

                SourceProposalStatusView(status: store.sourceProposalStatus)
                if store.sourcePatchStatus.requiresAttentionInChanges {
                    SourcePatchStatusView(status: store.sourcePatchStatus, mode: .proposal)
                }
            } else {
                Text("Team workspace required to propose changes.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var semanticDiffSections: some View {

        SourceChangeSummarySection(groups: store.workspaceSummary.groups)
        ForEach(store.workspaceSummary.groups.filter { !$0.records.isEmpty }) { group in
            SourceChangeGroupSections(
                group: group,
                recordComparisons: store.workspaceSummary.recordComparisons
            )
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        Section("Source") {
            if let sourceProvenance = store.sourceProvenance {
                SourceIndicatorView(sourceProvenance: sourceProvenance)

                Button {
                    store.send(.refreshSourceButtonTapped)
                } label: {
                    Label("Refresh Source", systemImage: "arrow.clockwise")
                }
                .disabled(sourceProvenance.sourceBaselineID == nil)
            } else {
                Text("Team workspace required")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var sourceDiffSections: some View {
        Section("Source Diff") {
            if store.canReviewSourceProposal {
                SourcePatchStatusView(status: store.sourcePatchStatus, mode: .proposal)

                if case let .generated(patch) = store.sourcePatchStatus {
                    if patch.isEmpty {
                        Text("No changes to propose")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button(store.sourcePatchStatus.reviewButtonTitle) {
                        store.send(.generateSourcePatchButtonTapped)
                    }
                    .disabled(store.sourcePatchStatus.isGenerating)
                }
            } else {
                Text("Team workspace required")
                    .foregroundStyle(.secondary)
            }
        }

        if case let .generated(patch) = store.sourcePatchStatus, !patch.isEmpty {
            SourcePatchFileChangesSection(patch: patch)
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        if store.sourceProvenance?.sourceKind == .tangled {
            tangledPullReviewsSection(title: "Review")
        } else {
            ExistingProposalsSection(
                title: "Review",
                emptyTitle: "No proposed changes to review",
                state: .loaded([])
            )
        }
    }

    @ViewBuilder
    private func tangledPullReviewsSection(title: String) -> some View {
        if store.sourceProvenance?.sourceKind == .tangled {
            Section(title) {
                switch store.tangledPullReviewStatus {
                case let .failed(failure):
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Reviews could not be loaded", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(failure.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                case let .loaded(reviews):
                    if reviews.isEmpty {
                        Label("No open reviews", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(reviews) { review in
                            let isClosing = store.closingTangledPullReviewIDs.contains(review.id)
                            let isDeleting = store.deletingTangledPullReviewIDs.contains(review.id)
                            let closeFailure = store.tangledPullReviewCloseFailures[review.id]
                            let deleteFailure = store.tangledPullReviewDeleteFailures[review.id]
                            NavigationLink {
                                TangledPullReviewDetailView(
                                    review: review,
                                    semanticDiffStatus: store.tangledPullReviewSemanticDiffs[review.id]
                                        ?? .notLoaded,
                                    onLoadSemanticDiff: {
                                        store.send(.reviewSemanticDiffButtonTapped(review))
                                    }
                                )
                            } label: {
                                TangledPullReviewRow(
                                    review: review,
                                    isClosing: isClosing,
                                    isDeleting: isDeleting,
                                    closeFailure: closeFailure,
                                    deleteFailure: deleteFailure
                                )
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    store.send(.deleteTangledPullReviewForeverButtonTapped(review))
                                } label: {
                                    Text(isDeleting ? "Deleting" : "Delete")
                                }
                                .disabled(isClosing || isDeleting)

                                Button {
                                    store.send(.closeTangledPullReviewButtonTapped(review))
                                } label: {
                                    Text(isClosing ? "Closing" : "Close")
                                }
                                .disabled(isClosing || isDeleting)
                                .tint(.orange)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.send(.closeTangledPullReviewButtonTapped(review))
                                } label: {
                                    Text("Close PR")
                                }
                                .disabled(isClosing || isDeleting)

                                Button(role: .destructive) {
                                    store.send(.deleteTangledPullReviewForeverButtonTapped(review))
                                } label: {
                                    Text("Delete PR Forever")
                                }
                                .disabled(isClosing || isDeleting)
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
                    store.send(.refreshTangledPullReviewsButtonTapped)
                } label: {
                    Label(
                        store.tangledPullReviewStatus.refreshButtonTitle,
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .disabled(store.tangledPullReviewStatus.isLoading)
            }
        }
    }

    @ViewBuilder
    private var resetEditsSection: some View {
        if store.canResetEdits || store.isResettingEdits || store.resetEditsFailure != nil {
            Section {
                if store.isResettingEdits {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Resetting edits")
                    }
                } else {
                    Button(role: .destructive) {
                        store.send(.resetEditsButtonTapped)
                    } label: {
                        Label("Reset Edits", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!store.canResetEdits)
                }

                if let failure = store.resetEditsFailure {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Edits could not be reset")
                        Text(failure.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

enum EventWorkspaceTab: String, CaseIterable, Identifiable {
    case propose
    case review

    var id: Self { self }

    var title: String {
        switch self {
        case .propose:
            "Propose"
        case .review:
            "Review"
        }
    }
}

struct TangledPullReviewRow: View {
    let review: TangledPullReview
    var isClosing = false
    var isDeleting = false
    var closeFailure: EventWorkspace.TangledPullReviewCloseFailure?
    var deleteFailure: EventWorkspace.TangledPullReviewDeleteFailure?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(review.title)
                    .font(.headline)
                Spacer()
                Text(review.state.tangledPullReviewStateTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(review.author)
                Text(review.createdAt)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if let body = review.body?.sourceReviewPreview, !body.isEmpty {
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Label("\(review.patchBlobs.count)", systemImage: "doc.zipper")
                Label("\(review.commentCount)", systemImage: "bubble.left")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if isClosing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Closing PR")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if isDeleting {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Deleting PR")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let closeFailure {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PR could not be closed")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(closeFailure.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let deleteFailure {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PR could not be deleted")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(deleteFailure.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct TangledPullReviewDetailView: View {
    let review: TangledPullReview
    let semanticDiffStatus: EventWorkspace.TangledPullReviewSemanticDiffStatus
    let onLoadSemanticDiff: () -> Void

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("State", value: review.state.tangledPullReviewStateTitle)
                LabeledContent("Author", value: review.author)
                LabeledContent("Created", value: review.createdAt)
                LabeledContent("Target", value: review.targetRepositoryDID)
                LabeledContent("Target branch", value: review.targetBranch)
                if let sourceBranch = review.sourceBranch {
                    LabeledContent("Source branch", value: sourceBranch)
                }
            }

            if let body = review.body, !body.isEmpty {
                Section("Description") {
                    Text(body)
                        .textSelection(.enabled)
                }
            }

            reviewSemanticDiffSections

            Section("Patch Blobs") {
                if review.patchBlobs.isEmpty {
                    Text("No patch blobs")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(review.patchBlobs) { patchBlob in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Round \(patchBlob.index)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(patchBlob.cid)
                                .font(.caption)
                                .monospaced()
                                .textSelection(.enabled)
                            Text(patchBlob.mimeType)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let size = patchBlob.size {
                                Text("\(size) bytes")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Raw Review") {
                Text(review.rawReviewText)
                    .font(.caption)
                    .monospaced()
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Review")
        .sourceChangeRowStyle(OpenMusicEventSourceChangeRowStyle())
        .onAppear {
            onLoadSemanticDiff()
        }
    }

    @ViewBuilder
    private var reviewSemanticDiffSections: some View {
        switch semanticDiffStatus {
        case let .failed(failure):
            Section("Semantic Diff") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review changes could not be loaded")
                    Text(failure.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button("Try Again") {
                    onLoadSemanticDiff()
                }
            }

        case let .loaded(diff):
            if diff.totalCount == 0 {
                Section("Semantic Diff") {
                    Text("No semantic changes")
                        .foregroundStyle(.secondary)
                }
            } else {
                SourceProposalSummarySections(
                    groups: diff.groups,
                    recordComparisons: diff.recordComparisons
                )
            }

        case .loading:
            Section("Semantic Diff") {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading review changes")
                }
            }

        case .notLoaded:
            Section("Semantic Diff") {
                Text("Review changes have not been loaded")
                    .foregroundStyle(.secondary)
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
}

public enum SourceChangesReviewMode: Equatable, Sendable {
    case proposal
    case workspace
}

public struct SourceChangesReviewPanel<SourceSection: View, AuxiliarySection: View>: View {
    let availability: SourceChangesAvailability
    let auxiliarySection: AuxiliarySection
    let groups: [SourceChangeGroup]
    let mode: SourceChangesReviewMode
    let onProposeChange: (() -> Void)?
    let onReviewChanges: () -> Void
    let recordComparisons: SourceRecordComparisons
    let sourcePatchStatus: EventWorkspace.SourcePatchStatus
    let sourceProposalStatus: EventWorkspace.SourceProposalStatus
    let sourceSection: SourceSection

    public init(
        availability: SourceChangesAvailability,
        groups: [SourceChangeGroup],
        recordComparisons: SourceRecordComparisons = .empty,
        mode: SourceChangesReviewMode,
        sourcePatchStatus: EventWorkspace.SourcePatchStatus,
        sourceProposalStatus: EventWorkspace.SourceProposalStatus = .idle,
        onReviewChanges: @escaping () -> Void,
        onProposeChange: (() -> Void)? = nil,
        @ViewBuilder sourceSection: () -> SourceSection,
        @ViewBuilder auxiliarySection: () -> AuxiliarySection
    ) {
        self.availability = availability
        self.auxiliarySection = auxiliarySection()
        self.groups = groups
        self.mode = mode
        self.onProposeChange = onProposeChange
        self.onReviewChanges = onReviewChanges
        self.recordComparisons = recordComparisons
        self.sourcePatchStatus = sourcePatchStatus
        self.sourceProposalStatus = sourceProposalStatus
        self.sourceSection = sourceSection()
    }

    public var body: some View {
        switch availability {
        case .available:
            List {
                sourceSection

                Section {
                    HStack {
                        Label(mode.sectionTitle, systemImage: mode.sectionSystemImage)
                        if let fileChangeCount = sourcePatchStatus.fileChangeCount {
                            Spacer()
                            Text(fileChangeCount, format: .number)
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                }

                Section {
                    SourcePatchStatusView(status: sourcePatchStatus, mode: mode)

                    if case let .generated(patch) = sourcePatchStatus {
                        if patch.isEmpty {
                            Label(mode.noChangesTitle, systemImage: "checkmark.circle")
                        } else if mode == .proposal, let onProposeChange {
                            Button {
                                onProposeChange()
                            } label: {
                                Label("Propose Change", systemImage: "paperplane")
                            }
                            .disabled(sourceProposalStatus.isProposing)
                        }
                    } else {
                        Button {
                            onReviewChanges()
                        } label: {
                            Label(
                                sourcePatchStatus.reviewButtonTitle,
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                        .disabled(sourcePatchStatus.isGenerating)
                    }

                    if mode == .proposal {
                        SourceProposalStatusView(status: sourceProposalStatus)
                    }
                }

                auxiliarySection

                if case let .generated(patch) = sourcePatchStatus, !patch.isEmpty {
                    SourceProposalSummarySections(
                        groups: groups,
                        recordComparisons: recordComparisons
                    )
                }
            }

        case .workspaceNeedsPreparation:
            ContentUnavailableView(
                "Workspace couldn't be loaded",
                systemImage: "externaldrive.badge.questionmark"
            )

        case .notInWorkspace:
            ContentUnavailableView(
                "Workspace unavailable",
                systemImage: "doc.badge.ellipsis"
            )

        case let .unavailable(reason):
            SourceChangeUnavailableView(reason: reason)
        }
    }
}

struct SourceIndicatorView: View {
    let sourceProvenance: EventSourceProvenanceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(sourceProvenance.sourceKind.sourceIndicatorTitle, systemImage: "folder")

            Text(sourceProvenance.sourceReference)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 2) {
                Text(sourceProvenance.sourceRefTitle)
                Text("events/\(sourceProvenance.sourceEventDirectory)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

public struct SourcePatchStatusView: View {
    let status: EventWorkspace.SourcePatchStatus
    let mode: SourceChangesReviewMode

    public init(
        status: EventWorkspace.SourcePatchStatus,
        mode: SourceChangesReviewMode = .proposal
    ) {
        self.status = status
        self.mode = mode
    }

    public var body: some View {
        switch status {
        case let .failed(failure):
            VStack(alignment: .leading, spacing: 4) {
                Text("Changes could not be checked")
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

        case let .generated(patch):
            HStack {
                Text(patch.isEmpty ? mode.noChangesTitle : mode.readyTitle)
                Spacer()
                Text(patch.fileChanges.count, format: .number)
                    .font(.headline)
                    .monospacedDigit()
            }

        case .generating:
            HStack(spacing: 8) {
                ProgressView()
                Text("Checking changes")
            }

        case let .needsGeneration(invalidation):
            VStack(alignment: .leading, spacing: 4) {
                Text("Changes need review")
                Text("\(invalidation.operation.title) \(invalidation.tableName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .notGenerated:
            Text(mode.notGeneratedTitle)
                .foregroundStyle(.secondary)
        }
    }
}

public struct SourceProposalStatusView: View {
    let status: EventWorkspace.SourceProposalStatus

    public init(status: EventWorkspace.SourceProposalStatus) {
        self.status = status
    }

    public var body: some View {
        switch status {
        case .composing, .idle:
            EmptyView()

        case let .created(publication):
            VStack(alignment: .leading, spacing: 8) {
                Label("Proposal Created", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                if let sourceChangeURL = publication.sourceChangeURL {
                    Link("Open Proposal", destination: sourceChangeURL)
                }
            }

        case let .failed(failure):
            VStack(alignment: .leading, spacing: 4) {
                Label("Proposal couldn't be created", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                DisclosureGroup("Details") {
                    Text(failure.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

        case .proposing:
            HStack(spacing: 8) {
                ProgressView()
                Text("Creating proposal")
            }
        }
    }
}

public struct SourceProposalComposerView: View {
    @Bindable var store: StoreOf<SourceProposalFlow>

    public init(store: StoreOf<SourceProposalFlow>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Title") {
                    TextField("Title", text: $store.sourceProposalTitle)
                        .onChange(of: store.sourceProposalTitle) { _, title in
                            store.send(.sourceProposalTitleChanged(title))
                        }
                }

                Section("Description") {
                    TextField(
                        "Description",
                        text: $store.sourceProposalDescription,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                    .onChange(of: store.sourceProposalDescription) { _, description in
                        store.send(.sourceProposalDescriptionChanged(description))
                    }
                }

                SourceProposalStatusView(status: store.sourceProposalStatus)
                SourceProposalSummarySections(
                    groups: store.sourceChangeGroups,
                    recordComparisons: store.sourceRecordComparisons
                )

                Section {
                    DisclosureGroup("Advanced") {
                        ForEach(store.patch.fileChanges) { change in
                            SourcePatchFileChangeRow(change: change)
                        }
                    }
                }
            }
            .navigationTitle("Propose Change")
            .sourceChangeRowStyle(OpenMusicEventSourceChangeRowStyle())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        store.send(.dismissButtonTapped)
                    }
                    .disabled(store.sourceProposalStatus.isProposing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Proposal") {
                        store.send(.createProposalButtonTapped)
                    }
                    .disabled(!store.canCreateSourceProposal)
                }
            }
        }
    }
}

struct SourceProposalDraftSection: View {
    @Bindable var store: StoreOf<SourceProposalFlow>

    init(store: StoreOf<SourceProposalFlow>) {
        self.store = store
    }

    var body: some View {
        Section("Proposal") {
            TextField("Title", text: $store.sourceProposalTitle)
                .onChange(of: store.sourceProposalTitle) { _, title in
                    store.send(.sourceProposalTitleChanged(title))
                }

            TextField(
                "Description",
                text: $store.sourceProposalDescription,
                axis: .vertical
            )
            .lineLimit(4...8)
            .onChange(of: store.sourceProposalDescription) { _, description in
                store.send(.sourceProposalDescriptionChanged(description))
            }

            SourceProposalStatusView(status: store.sourceProposalStatus)

            Button("Create Proposal") {
                store.send(.createProposalButtonTapped)
            }
            .disabled(!store.canCreateSourceProposal)
        }
    }
}

struct SourcePatchFileChangesSection: View {
    let patch: SourcePatch

    init(patch: SourcePatch) {
        self.patch = patch
    }

    var body: some View {
        DisclosureGroup("Changed Files") {
            ForEach(patch.fileChanges) { change in
                SourcePatchFileChangeRow(change: change)
            }
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
                        .textSelection(.enabled)
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
            ForEach(groups.filter { !$0.records.isEmpty }) { group in
                SourceChangeGroupSections(
                    group: group,
                    recordComparisons: recordComparisons
                )
            }
        } else {
            Section {
                Label("No edit summary available", systemImage: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SourceChangeSummarySection: View {
    let groups: [SourceChangeGroup]

    var body: some View {
        Section("Semantic Diff") {
            ForEach(groups.filter { $0.totalCount > 0 }) { group in
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
    }
}

struct SourceChangeCountBadges: View {
    let group: SourceChangeGroup

    var body: some View {
        HStack(spacing: 8) {
            if group.added > 0 {
                SourceChangeCountBadge(title: "A", count: group.added)
            }
            if group.modified > 0 {
                SourceChangeCountBadge(title: "M", count: group.modified)
            }
            if group.deleted > 0 {
                SourceChangeCountBadge(title: "D", count: group.deleted)
            }
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
}

struct SourceChangeCountBadge: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
            Text(count, format: .number)
        }
    }
}

struct SourcePatchFileChangeRow: View {
    let change: SourcePatchFileChange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(change.kind.title, systemImage: change.kind.systemImage)
                .font(.caption)
                .foregroundStyle(change.kind.tint)

            Text(change.path)
                .font(.caption)
                .monospaced()
                .textSelection(.enabled)

            if let oldContents = change.oldContents {
                SourcePatchFileContentsPreview(
                    title: "Old",
                    data: oldContents
                )
            }

            if let newContents = change.newContents {
                SourcePatchFileContentsPreview(
                    title: "New",
                    data: newContents
                )
            }
        }
        .padding(.vertical, 4)
    }
}

struct SourcePatchFileContentsPreview: View {
    let title: String
    let data: Data

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(data.sourcePatchPreview)
                .font(.caption)
                .monospaced()
                .lineLimit(12)
                .textSelection(.enabled)
        }
    }
}

private extension SourcePatchInvalidation.Operation {
    var title: String {
        switch self {
        case .delete:
            "Deleted"
        case .insert:
            "Inserted"
        case .update:
            "Updated"
        }
    }
}

private extension OMERecord.SourceDatabaseInsertion.SourceKind {
    var sourceIndicatorTitle: String {
        switch self {
        case .local:
            "Local Source"
        case .tangled:
            "Tangled Source"
        }
    }
}

private extension EventSourceProvenanceRecord {
    var sourceRefTitle: String {
        ref ?? "default ref"
    }
}

private extension EventWorkspace.State {
    mutating func presentSourceProposal(for patch: SourcePatch) {
        guard !patch.isEmpty, canReviewSourceProposal else {
            sourceProposal = nil
            sourceProposalStatus = .idle
            return
        }

        sourceProposal = SourceProposalFlow.State(
            eventID: eventID,
            workspaceSummary: workspaceSummary,
            patch: patch
        )
        sourceProposalStatus = .composing
    }

    var canResetEdits: Bool {
        guard !isResettingEdits,
              workspaceSummary.totalCount > 0,
              case .available = workspaceSummary.availability
        else { return false }
        return true
    }

    var canCreateSourceProposal: Bool {
        guard case let .generated(patch) = sourcePatchStatus,
              !patch.isEmpty,
              canReviewSourceProposal,
              sourceProposalStatus.canCreateProposal
        else { return false }
        return true
    }

    var canReviewSourceProposal: Bool {
        sourceProvenance?.sourceBaselineID != nil
    }

    var canProposeLocalChanges: Bool {
        guard workspaceSummary.totalCount > 0,
              canReviewSourceProposal,
              !sourcePatchStatus.isGenerating,
              !sourceProposalStatus.isProposing
        else { return false }
        return true
    }
}

private extension EventWorkspace.TangledPullReviewSemanticDiff {
    static func reviewBranchDiff(
        eventID: OME.Event.ID,
        review: TangledPullReview,
        sourceProvenance: OME.SourceDatabaseInsertion.SourceProvenance,
        sourceSnapshot: TangledPullReviewSourceSnapshotClient
    ) async throws -> Self {
        @Dependency(\.sourceReferenceDatabase) var sourceReferenceDatabase
        guard let baselineDatabase = try sourceReferenceDatabase.existing(sourceProvenance) else {
            throw TangledPullReviewSemanticDiffError.sourceBaselineMissing(sourceProvenance)
        }

        @Dependency(\.uuid) var uuid
        let scratchRootURL = FileManager.default.temporaryDirectory
            .appending(path: "ome-review-semantic-diff-\(uuid().uuidString)", directoryHint: .isDirectory)
            .standardizedFileURL
        try FileManager.default.createDirectory(
            at: scratchRootURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: scratchRootURL) }

        let insertion = try await sourceSnapshot.insertion(
            TangledPullReviewSourceSnapshotRequest(
                organizerID: eventID.organizerID,
                review: review,
                sourceProvenance: sourceProvenance
            )
        )

        let workingDatabaseURL = scratchRootURL
            .appending(path: "review.sqlite")
        let workingDatabase = try DatabasePool(path: workingDatabaseURL.path)
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(workingDatabase)

        try await withDependencies {
            $0.sourceReferenceDatabase = .scratch(rootURL: scratchRootURL)
            $0.sourceReferenceDatabaseMigrator = .openMusicEvent
            $0.localImageFileStore = .scratch(rootURL: scratchRootURL)
        } operation: {
            try await insertion.insert(into: workingDatabase)
        }

        let summary = try await workingDatabase.read { db in
            try SourceEditingComparer().summary(
                in: db,
                baselineDatabase: baselineDatabase,
                recordTypes: OME.sourceRecordTypes,
                scope: .openMusicEvent(eventID: eventID)
            )
        }
        switch summary.availability {
        case .available:
            return Self(
                groups: summary.groups,
                recordComparisons: summary.recordComparisons
            )

        case let .unavailable(reason):
            throw TangledPullReviewSemanticDiffError.unavailable(reason)
        }
    }
}

private enum TangledPullReviewSemanticDiffError: Error, CustomStringConvertible {
    case sourceBaselineMissing(OME.SourceDatabaseInsertion.SourceProvenance)
    case unavailable(SourceChangeSummary.UnavailableReason)

    var description: String {
        switch self {
        case let .sourceBaselineMissing(provenance):
            "Source baseline is missing for \(provenance.reference)."
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
                try SourceReferenceDatabaseClient.prepareReferenceDirectory(for: databaseURL)
                try SourceReferenceDatabaseClient.removeSQLiteDatabase(at: databaseURL)
                let database = try defaultBaselineDatabase(path: databaseURL.path)
                try SourceReferenceDatabaseMigrator.openMusicEvent.migrate(database)
                return database
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

private extension String {
    var sourceReviewScratchFileComponent: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let value = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return value.isEmpty ? UUID().uuidString : value
    }
}

private extension EventWorkspace.SourcePatchStatus {
    var reviewButtonTitle: String {
        switch self {
        case .failed:
            "Try Again"
        case .generating:
            "Checking Changes"
        case .generated:
            "Check Changes"
        default:
            "Check Changes"
        }
    }

    var isGenerating: Bool {
        self == .generating
    }

    var proposeButtonTitle: String {
        switch self {
        case .failed:
            "Try Proposing Again"
        case .generating:
            "Preparing Proposal"
        case .generated:
            "Propose Changes"
        case .needsGeneration, .notGenerated:
            "Propose Changes"
        }
    }

    var requiresAttentionInChanges: Bool {
        switch self {
        case .failed, .generating:
            true
        case let .generated(patch):
            patch.isEmpty
        case .needsGeneration, .notGenerated:
            false
        }
    }

    var fileChangeCount: Int? {
        guard case let .generated(patch) = self else { return nil }
        return patch.fileChanges.count
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
            "Check changes before creating a proposal"
        case .workspace:
            "Check unpublished changes"
        }
    }

    var readyTitle: String {
        switch self {
        case .proposal:
            "Proposal can be created"
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
            "Proposal"
        case .workspace:
            "Unpublished Changes"
        }
    }
}

public extension EventWorkspace.SourceProposalStatus {
    var canCreateProposal: Bool {
        switch self {
        case .composing, .failed, .idle:
            true
        case .created, .proposing:
            false
        }
    }

    var isProposing: Bool {
        self == .proposing
    }
}

private extension EventWorkspace.TangledPullReviewStatus {
    var isLoading: Bool {
        self == .loading
    }

    var refreshButtonTitle: String {
        switch self {
        case .failed:
            "Try Again"
        case .loaded, .notLoaded:
            "Refresh Reviews"
        case .loading:
            "Loading Reviews"
        }
    }
}

private extension SourcePatchFileChange.Kind {
    var systemImage: String {
        switch self {
        case .added:
            "plus.circle"
        case .deleted:
            "minus.circle"
        case .modified:
            "pencil.circle"
        }
    }

    var tint: Color {
        switch self {
        case .added:
            .green
        case .deleted:
            .red
        case .modified:
            .orange
        }
    }

    var title: String {
        switch self {
        case .added:
            "Added"
        case .deleted:
            "Deleted"
        case .modified:
            "Modified"
        }
    }
}

private extension String {
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
            "Merged"
        default:
            self
        }
    }
}

private extension Data {
    var sourcePatchPreview: String {
        guard let text = String(data: self, encoding: .utf8) else {
            return "<binary \(count) bytes>"
        }
        guard !text.isEmpty else { return "<empty>" }
        guard text.count > 1_200 else { return text }
        return "\(String(text.prefix(1_200)))\n..."
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(record.primaryKeySummary)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }

            if let recordDiff = record.recordDiff, !recordDiff.isEmpty {
                Text(recordDiff)
                    .font(.caption)
                    .monospaced()
                    .textSelection(.enabled)
            } else {
                ForEach(record.fieldChanges) { change in
                    SourceFieldChangeRow(change: change)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SourceEventChangeRow: View {
    let comparison: SourceRecordComparison<OME.Event>

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
                .init(title: "Owner", columnName: "owner", optionalKeyPath: \.owner) {
                    $0.description
                },
            ]
        )
    }

    private var title: String {
        comparison.right?.name ?? comparison.left?.name ?? comparison.change.primaryKeySummary
    }
}

struct SourceCalendarChangeRow: View {
    let comparison: SourceRecordComparison<OME.Calendar>

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
        comparison.right?.name ?? comparison.left?.name ?? comparison.change.primaryKeySummary
    }
}

struct SourceStageChangeRow: View {
    let comparison: SourceRecordComparison<OME.Stage>

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
        comparison.right?.name ?? comparison.left?.name ?? comparison.change.primaryKeySummary
    }
}

struct SourceScheduleChangeRow: View {
    let comparison: SourceRecordComparison<OME.Schedule>

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
            ?? comparison.change.primaryKeySummary
    }
}

struct SourcePerformanceChangeRow: View {
    let comparison: SourceRecordComparison<OME.Performance>

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
        comparison.right?.title ?? comparison.left?.title ?? comparison.change.primaryKeySummary
    }
}

struct SourceContributorChangeRow: View {
    enum Content {
        case comparison(SourceRecordComparison<OME.Contributor>)
        case record(SourceRecordChange)
    }

    let content: Content

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
        SourceComparisonValueRow(
            title: "DID",
            comparison: comparison,
            optionalKeyPath: \.did
        ) {
            $0.description
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
        SourceRecordValueRow(
            title: "DID",
            comparison: comparison,
            side: side,
            optionalKeyPath: \.did
        ) {
            $0.description
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
        SourceDatabaseFieldComparisonRow(
            title: "DID",
            record: record,
            columnName: "did"
        ) {
            $0.sourcePlainStringDisplayValue
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

        ForEach(undisplayedFieldChanges(in: record)) { change in
            SourceFieldChangeRow(change: change)
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
        SourceDatabaseFieldValueRow(
            title: "DID",
            record: record,
            columnName: "did",
            side: side
        ) {
            $0.sourcePlainStringDisplayValue
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

        ForEach(undisplayedFieldChanges(in: record)) { change in
            SourceDatabaseFieldValueRow(
                title: change.columnName,
                change: change,
                side: side
            )
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
            comparison.right?.name ?? comparison.left?.name ?? comparison.change.contributorTitleFallback
        case let .record(record):
            record.fieldChange(named: "name")?.displayValue
                ?? record.contributorTitleFallback
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
        comparison.right?.name ?? comparison.left?.name ?? comparison.change.primaryKeySummary
    }
}

struct SourcePosterChangeRow: View {
    let comparison: SourceRecordComparison<OME.Poster>

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
        comparison.right?.title ?? comparison.left?.title ?? comparison.change.primaryKeySummary
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
    var isChanged: (SourceRecordComparison<Record>) -> Bool
    var displayValue: (SourceRecordComparison<Record>, SourceRecordValueSide) -> String?

    init<Value: Equatable>(
        title: String,
        columnName: String,
        keyPath: KeyPath<Record, Value>,
        valueTitle: @escaping (Value) -> String = { String(describing: $0) }
    ) {
        self.title = title
        self.columnName = columnName
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
        valueTitle: @escaping (Value) -> String = { String(describing: $0) }
    ) {
        self.title = title
        self.columnName = columnName
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
        ForEach(fields) { field in
            if field.isChanged(comparison) {
                SourceComparisonDisplayRow(
                    title: field.title,
                    left: field.displayValue(comparison, .left) ?? "missing",
                    right: field.displayValue(comparison, .right) ?? "missing"
                )
            }
        }

        ForEach(undisplayedFieldChanges) { change in
            SourceFieldChangeRow(change: change)
        }
    }

    @ViewBuilder
    private func valueRows(side: SourceRecordValueSide) -> some View {
        ForEach(fields) { field in
            if let value = field.displayValue(comparison, side) {
                SourceRecordDisplayValueRow(
                    title: field.title,
                    value: value,
                    side: side
                )
            }
        }

        ForEach(undisplayedFieldChanges) { change in
            SourceDatabaseFieldValueRow(
                title: change.columnName,
                change: change,
                side: side
            )
        }
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
                .textSelection(.enabled)
        }
    }
}

private extension SourceRecordChangeKind {
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

    var contributorTitleFallback: String {
        primaryKeyValue(named: "contributorID")?.sourcePlainStringDisplayValue
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

    var body: some View {
        switch reason {
        case let .schemaMismatch(mismatches):
            List {
                Section {
                    Label("Schema Mismatch", systemImage: "exclamationmark.triangle")
                }

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
