import ComposableArchitecture2
import ComposableForms
import ErrorHandling
import Foundation
import GRDB
import Lexicon
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SourceEditing
import SQLiteData
import SwiftUI

public struct SourceWorkspaceSummary: Equatable, Sendable {
    public var availability: SourceChangesAvailability
    public var groups: [SourceChangeGroup]
    public var recordComparisons: SourceRecordComparisons
    public var target: SourceProposalTarget

    public init(
        target: SourceProposalTarget,
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
        target: SourceProposalTarget,
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
        target: SourceProposalTarget,
        sourceSummary: SourceEditSummary
    ) {
        self.init(
            target: target,
            availability: SourceChangesAvailability(sourceSummary.availability),
            groups: sourceSummary.groups,
            recordComparisons: sourceSummary.recordComparisons
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

    public var badgeCount: Int? {
        guard case .available = availability, totalCount > 0 else { return nil }
        return totalCount
    }

    static func initialValue(target: SourceProposalTarget) -> Self {
        switch target {
        case .event:
            Self(target: target, availability: .notInWorkspace, groups: [])
        case .calendar:
            Self(target: target, availability: .workspaceNeedsPreparation, groups: [])
        }
    }
}

public struct SourceWorkspaceSummaryRequest: FetchKeyRequest {
    public var target: SourceProposalTarget

    public init(target: SourceProposalTarget) {
        self.target = target
    }

    public func fetch(_ db: Database) throws -> SourceWorkspaceSummary {
        switch target {
        case let .event(eventID):
            return SourceWorkspaceSummary(
                target: target,
                eventSummary: try EventWorkspaceSummaryRequest(eventID: eventID).fetch(db)
            )

        case let .calendar(calendarID, sourceBaselineID):
            return SourceWorkspaceSummary(
                target: target,
                sourceSummary: try SourceEditSummaryRequest(
                    sourceBaselineID: sourceBaselineID,
                    calendarID: calendarID
                )
                .fetch(db)
            )
        }
    }
}

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

    public struct TangledPullReviewMergeFailure: Equatable, Error, Sendable {
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

        public init(target: SourceProposalTarget) {
            self.target = target
            self._sourceWorkspaceSummary = Fetch(
                wrappedValue: SourceWorkspaceSummary.initialValue(target: target),
                SourceWorkspaceSummaryRequest(target: target)
            )
            self._sourceProvenance = FetchOne(
                Self.sourceProvenanceQuery(target: target)
            )
            self._sourceBaseline = FetchOne(
                Self.sourceBaselineQuery(target: target)
            )
        }

        public let target: SourceProposalTarget
        public var id: String { target.id }
        @DebugSnapshotIgnored
        @Fetch public var sourceWorkspaceSummary: SourceWorkspaceSummary
        public var isPreparingSourceProposal = false
        public var isRefreshingSource = false
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
        public var mergingTangledPullReviewIDs: Set<String> = []
        public var pendingDeletedTangledPullReviews:
            [String: PendingDeletedTangledPullReview] = [:]
        public var tangledPullReviewCloseFailures: [String: TangledPullReviewCloseFailure] = [:]
        public var tangledPullReviewDeleteFailures: [String: TangledPullReviewDeleteFailure] = [:]
        public var tangledPullReviewMergeFailures: [String: TangledPullReviewMergeFailure] = [:]
        public var tangledPullReviewSemanticDiffs: [String: TangledPullReviewSemanticDiffStatus] = [:]
        @FetchOne public var sourceBaseline: SourceBaselineRecord?
        @FetchOne public var sourceProvenance: EventSourceProvenanceRecord?

        public var changeCount: Int? {
            sourceWorkspaceSummary.badgeCount
        }

        public var eventID: OMERecord.Event.ID {
            guard case let .event(eventID) = target else {
                preconditionFailure("Calendar source workspaces do not have one event ID.")
            }
            return eventID
        }

        public var sourceBaselineID: SourceBaselineRecord.ID? {
            switch target {
            case let .calendar(_, sourceBaselineID):
                sourceBaselineID
            case .event:
                sourceProvenance?.sourceBaselineID
            }
        }

        public var calendarID: OMERecord.Calendar.ID? {
            switch target {
            case let .calendar(calendarID, _):
                calendarID
            case .event:
                nil
            }
        }

        public var sourceChangesScope: SourceChangesScope {
            switch target {
            case let .calendar(calendarID, sourceBaselineID):
                .source(sourceBaselineID: sourceBaselineID, calendarID: calendarID)
            case let .event(eventID):
                if let sourceBaselineID {
                    .source(
                        sourceBaselineID: sourceBaselineID,
                        calendarID: OMERecord.Calendar.ID(
                            ownerID: eventID.organizerID,
                            calendarID: OMERecord.Calendar.defaultID
                        )
                    )
                } else {
                    .event(eventID)
                }
            }
        }

        public var workspaceSummary: EventWorkspaceSummary {
            EventWorkspaceSummary(
                eventID: eventID,
                availability: sourceWorkspaceSummary.availability.eventWorkspaceAvailability,
                groups: sourceWorkspaceSummary.groups,
                recordComparisons: sourceWorkspaceSummary.recordComparisons
            )
        }
    }

    public enum Action {
        case closeTangledPullReviewButtonTapped(TangledPullReview)
        case createEventButtonTapped
        case delegate(Delegate)
        case deleteTangledPullReviewForeverButtonTapped(TangledPullReview)
        case generateSourcePatchButtonTapped
        case mergeTangledPullReviewButtonTapped(TangledPullReview)
        case onAppear
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
        case tangledPullReviewMergeResponse(
            review: TangledPullReview,
            Result<Void, TangledPullReviewMergeFailure>
        )
        case tangledPullReviewsResponse(Result<[TangledPullReview], TangledPullReviewFailure>)
    }

    public enum Delegate: Equatable, Sendable {
        case createEventRequested(
            sourceBaselineID: SourceBaselineRecord.ID,
            calendarID: OMERecord.Calendar.ID
        )
    }

    @Dependency(\.eventWorkspaceResetter) var workspaceResetter
    @Dependency(\.sourceDataRefresh) var sourceDataRefresh
    @Dependency(SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self)
    var calendarSourcePatchGenerator
    @Dependency(\.sourcePatchInvalidations) var sourcePatchInvalidations
    @Dependency(\.tangledPullReviewClient) var tangledPullReviewClient
    @Dependency(\.tangledPullReviewSourceSnapshot) var tangledPullReviewSourceSnapshot

    private func refreshTangledPullReviews(
        target: SourceProposalTarget,
        state: inout State
    ) {
        guard state.sourceKind == .tangled else {
            state.tangledPullReviewStatus = .notLoaded
            return
        }

        let tangledPullReviewClient = tangledPullReviewClient
        state.tangledPullReviewStatus = .loading
        store.addTask {
            do {
                let reviews = try await tangledPullReviewClient.list(
                    OpenMusicEventTangledPullReviewRequest(target: target)
                )
                try store.send(.tangledPullReviewsResponse(.success(reviews)))
            } catch {
                await store.reportError(
                    error,
                    fallbackMessage: .tangledPullReviewLoadFailed,
                    operation: .tangledPullReviewLoad
                )
                try store.send(
                    .tangledPullReviewsResponse(
                        .failure(TangledPullReviewFailure(error))
                    )
                )
            }
        }
    }

    public var body: some Feature {
        let _ = Self._logChanges()
        Update { state, action in
            func generateSourcePatch(
                state: inout State
            ) {
                guard state.canReviewSourceProposal,
                      let sourcePatchRequest = state.workspaceSourcePatchRequest
                else { return }
                let calendarSourcePatchGenerator = calendarSourcePatchGenerator
                state.sourcePatchStatus = .generating
                store.addTask {
                    do {
                        let patch = try await calendarSourcePatchGenerator.generate(
                            sourcePatchRequest
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
                guard let sourceProvenance = state.sourceReviewProvenance,
                      let sourceBaselineID = state.sourceBaselineID
                else { return }
                let target = state.target
                let sourceSnapshot = tangledPullReviewSourceSnapshot
                state.tangledPullReviewSemanticDiffs[review.id] = .loading
                store.addTask {
                    do {
                        let diff = try await TangledPullReviewSemanticDiff.reviewBranchDiff(
                            target: target,
                            sourceBaselineID: sourceBaselineID,
                            review: review,
                            sourceProvenance: sourceProvenance,
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
                      !state.deletingTangledPullReviewIDs.contains(review.id),
                      !state.mergingTangledPullReviewIDs.contains(review.id)
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
                        await store.reportError(
                            error,
                            fallbackMessage: .tangledPullReviewCloseFailed,
                            operation: .tangledPullReviewClose
                        )
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
                      !state.closingTangledPullReviewIDs.contains(review.id),
                      !state.mergingTangledPullReviewIDs.contains(review.id)
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
                        await store.reportError(
                            error,
                            fallbackMessage: .tangledPullReviewDeleteFailed,
                            operation: .tangledPullReviewDelete
                        )
                        try store.send(
                            .tangledPullReviewDeleteResponse(
                                review: review,
                                .failure(TangledPullReviewDeleteFailure(error))
                            )
                        )
                    }
                }
            }

            func mergeTangledPullReview(
                _ review: TangledPullReview,
                state: inout State
            ) {
                guard !state.mergingTangledPullReviewIDs.contains(review.id),
                      !state.closingTangledPullReviewIDs.contains(review.id),
                      !state.deletingTangledPullReviewIDs.contains(review.id)
                else { return }

                let target = state.target
                let tangledPullReviewClient = tangledPullReviewClient
                state.mergingTangledPullReviewIDs.insert(review.id)
                state.tangledPullReviewMergeFailures[review.id] = nil
                store.addTask {
                    do {
                        try await tangledPullReviewClient.merge(
                            OpenMusicEventTangledPullReviewMergeRequest(
                                target: target,
                                review: review
                            )
                        )
                        try store.send(
                            .tangledPullReviewMergeResponse(review: review, .success(()))
                        )
                    } catch {
                        await store.reportError(
                            error,
                            fallbackMessage: .tangledPullReviewMergeFailed,
                            operation: .tangledPullReviewMerge
                        )
                        try store.send(
                            .tangledPullReviewMergeResponse(
                                review: review,
                                .failure(TangledPullReviewMergeFailure(error))
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
                state.tangledPullReviewMergeFailures[review.id] = nil
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
                state.tangledPullReviewStatus = .loaded(reviews.tangledPullReviewsSortedByDate)
            }

            switch action {
            case let .closeTangledPullReviewButtonTapped(review):
                closeTangledPullReview(review, state: &state)

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
                return

            case let .deleteTangledPullReviewForeverButtonTapped(review):
                deleteTangledPullReviewForever(review, state: &state)

            case .generateSourcePatchButtonTapped:
                generateSourcePatch(state: &state)
                refreshTangledPullReviews(target: state.target, state: &state)

            case let .mergeTangledPullReviewButtonTapped(review):
                mergeTangledPullReview(review, state: &state)

            case .onAppear:
                guard state.tangledPullReviewStatus == .notLoaded else { return }
                refreshTangledPullReviews(target: state.target, state: &state)

            case .refreshSourceButtonTapped:
                guard !state.isRefreshingSource else { return }
                switch state.target {
                case let .calendar(_, sourceBaselineID):
                    let sourceDataRefresh = sourceDataRefresh
                    state.isRefreshingSource = true
                    store.addTask {
                        let result: Void? = await store.withErrorHandling(
                            fallbackMessage: .sourceDataRefreshFailed,
                            operation: .sourceDataRefresh
                        ) {
                            try await sourceDataRefresh.refresh(sourceBaselineID)
                        } cleanup: {
                            $0.isRefreshingSource = false
                        }
                        guard result != nil else { return }
                        try store.modify {
                            $0.isRefreshingSource = false
                        }
                    }

                case let .event(eventID):
                    guard let sourceBaselineID = state.sourceProvenance?.sourceBaselineID else {
                        return
                    }
                    let request = SourceDataRefreshRequest(
                        eventID: eventID,
                        sourceBaselineID: sourceBaselineID
                    )
                    store.addTask {
                        try store.post(key: SourceDataRefreshRequested.self, value: request)
                    }
                }

            case .refreshTangledPullReviewsButtonTapped:
                refreshTangledPullReviews(target: state.target, state: &state)

            case .resetEditsButtonTapped:
                guard !state.isResettingEdits else { return }
                let target = state.target
                let workspaceResetter = workspaceResetter
                state.isResettingEdits = true
                state.resetEditsFailure = nil
                store.addTask {
                    do {
                        try workspaceResetter.resetSourceChanges(target)
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

            case .sourceProposal(.delegate(.created)):
                state.isPreparingSourceProposal = false
                state.dismissSourceProposal()
                refreshTangledPullReviews(target: state.target, state: &state)

            case .sourceProposal(.delegate(.dismissed)):
                state.isPreparingSourceProposal = false
                state.dismissSourceProposal()

            case .proposeChangeButtonTapped:
                guard state.canReviewSourceProposal else { return }
                guard case let .generated(patch) = state.sourcePatchStatus else {
                    state.isPreparingSourceProposal = true
                    generateSourcePatch(state: &state)
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

            case let .tangledPullReviewMergeResponse(review, .success):
                state.mergingTangledPullReviewIDs.remove(review.id)
                removeTangledPullReviewFromLoadedState(review, state: &state)

            case let .tangledPullReviewMergeResponse(review, .failure(failure)):
                state.mergingTangledPullReviewIDs.remove(review.id)
                state.tangledPullReviewMergeFailures[review.id] = failure

            case let .tangledPullReviewsResponse(.success(reviews)):
                state.tangledPullReviewStatus = .loaded(
                    reviews
                        .filter { !state.locallyRemovedTangledPullReviewIDs.contains($0.id) }
                        .tangledPullReviewsSortedByDate
                )

            case let .tangledPullReviewsResponse(.failure(failure)):
                state.tangledPullReviewStatus = .failed(failure)
            }
        }
        .onMount { state in
            let target = state.target
            store.addTask {
                for await invalidation in sourcePatchInvalidations.stream() {
                    guard await target.matches(invalidation: invalidation) else { continue }
                    try store.send(.sourcePatchInvalidationReceived(invalidation))
                }
            }
        }
        .ifLet(\.sourceProposal, action: \.sourceProposal) {
            SourceProposalFlow()
        }
        .onChange(of: store.sourceProposal?.status) { _, status, state in
            guard let status else { return }
            state.sourceProposalStatus = status
        }
    }
}

private extension UserFacingText {
    static let tangledPullReviewLoadFailed = Self(
        "Unable to load Tangled pull reviews.",
        fallback: "Unable to load Tangled pull reviews."
    )
    static let tangledPullReviewCloseFailed = Self(
        "Unable to close Tangled pull review.",
        fallback: "Unable to close Tangled pull review."
    )
    static let tangledPullReviewDeleteFailed = Self(
        "Unable to delete Tangled pull review.",
        fallback: "Unable to delete Tangled pull review."
    )
    static let tangledPullReviewMergeFailed = Self(
        "Unable to merge Tangled pull review.",
        fallback: "Unable to merge Tangled pull review."
    )
}

private extension ErrorOperation {
    static let tangledPullReviewLoad = Self("tangled.pull-review.load")
    static let tangledPullReviewClose = Self("tangled.pull-review.close")
    static let tangledPullReviewDelete = Self("tangled.pull-review.delete")
    static let tangledPullReviewMerge = Self("tangled.pull-review.merge")
}

public typealias SourceWorkspace = EventWorkspace
public typealias SourceWorkspaceView = EventWorkspaceView

public struct EventWorkspaceView: View {
    @Bindable var store: StoreOf<EventWorkspace>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    @State var selectedTab: EventWorkspaceTab

    public init(store: StoreOf<EventWorkspace>) {
        self.store = store
        self._selectedTab = State(initialValue: store.defaultWorkspaceTab)
    }

    public var body: some View {
        VStack(spacing: 0) {
            workspaceTabContent
        }
        .navigationTitle(navigationTitle)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .top, spacing: 0) {
            workspaceTopBarExtension
        }
        .sourceChangeRowStyle(OpenMusicEventSourceChangeRowStyle())
        .sheet(item: $store.scope(\.sourceProposal, action: \.sourceProposal)) { proposalStore in
            SourceProposalComposerView(store: proposalStore)
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
            if selectedTab == .review, store.sourceBaselineID != nil {
                ToolbarItem(placement: .secondaryAction) {
                    Button("Refresh Source", systemImage: "arrow.clockwise") {
                        store.send(.refreshSourceButtonTapped)
                    }
                }
            }
        }
        .onAppear {
            store.send(.onAppear)
        }
    }

    @ViewBuilder
    var workspaceTopBarExtension: some View {
        VStack(spacing: 0) {
            workspaceContextHeader
            workspaceTabPicker

            if selectedTab == .propose,
               store.sourceWorkspaceSummary.totalCount > 0,
               store.canReviewSourceProposal
            {
                HStack(spacing: 12) {
                    Label(
                        "Updates ready to propose",
                        systemImage: "square.and.pencil"
                    )
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                    Spacer(minLength: 8)

                    Button(store.sourcePatchStatus.proposeButtonTitle, systemImage: "paperplane") {
                        store.send(.proposeChangeButtonTapped)
                    }
                    .disabled(!store.canProposeLocalChanges)
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .background(.background)
        .overlay(alignment: .bottom) {
            Divider()
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
                    Text(store.sourceWorkspaceSummary.totalCount, format: .number)
                        .font(.title3)
                        .monospacedDigit()
                }

                Spacer()

                if let sourceContext = store.sourceContext {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(sourceContext.sourceKind.sourceIndicatorTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(sourceContext.detailTitle)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
            }

            if showsTechnicalDetails, let sourceContext = store.sourceContext {
                Text(sourceContext.sourceReference)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if store.sourceWorkspaceSummary.outOfTargetCount > 0 {
                let count = store.sourceWorkspaceSummary.outOfTargetCount
                Text(
                    count == 1
                        ? "1 change is outside this event."
                        : "\(count) changes are outside this event."
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if showsTechnicalDetails, let sourceContext = store.sourceContext {
                    DisclosureGroup("Technical details") {
                        WorkspaceTechnicalValueView(
                            label: "Source address",
                            value: sourceContext.sourceReference
                        )
                        WorkspaceTechnicalValueView(
                            label: "Provider",
                            value: sourceContext.sourceKind.rawValue
                        )
                        WorkspaceTechnicalValueView(
                            label: "Branch or ref",
                            value: sourceContext.sourceRefTitle
                        )

                        if selectedTab == .propose,
                           case let .generated(patch) = store.sourcePatchStatus,
                           !patch.isEmpty
                        {
                            Text("Files changed")
                                .font(.subheadline.weight(.semibold))
                                .padding(.top, 4)

                            ForEach(patch.fileChanges) { change in
                                SourcePatchFileChangeRow(change: change)
                            }
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var workspaceTabPicker: some View {
        Picker("Workspace", selection: $selectedTab) {
            ForEach(EventWorkspaceTab.allCases) { tab in
                Text(tab.title(for: store.target)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private var navigationTitle: Text {
        switch store.target {
        case .calendar:
            Text("Team Workspace")
        case .event:
            Text("Workspace")
        }
    }

    @ViewBuilder
    private var workspaceTabContent: some View {
        switch store.sourceWorkspaceSummary.availability {
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
        Section("Your changes") {
            HStack(alignment: .firstTextBaseline) {
                Label(
                    store.sourceWorkspaceSummary.totalCount == 0
                        ? "No updates to propose"
                        : "\(store.sourceWorkspaceSummary.totalCount) updates to propose",
                    systemImage: store.sourceWorkspaceSummary.totalCount == 0
                        ? "checkmark.circle"
                        : "square.and.pencil"
                )
                .font(.headline)

                Spacer(minLength: 12)
            }

            if store.sourceWorkspaceSummary.totalCount == 0 {
                Text("There are no updates to propose yet.")
                    .foregroundStyle(.secondary)
            } else if store.canReviewSourceProposal {
                if store.isPreparingSourceProposal {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Preparing proposal")
                    }
                    .foregroundStyle(.secondary)
                }

                SourceProposalStatusView(status: store.sourceProposalStatus)
                if store.sourcePatchStatus.requiresAttentionInChanges {
                    SourcePatchStatusView(status: store.sourcePatchStatus, mode: .proposal)
                }
            } else {
                Text("This workspace isn't ready to propose updates.")
                    .foregroundStyle(.secondary)
            }

            if store.sourceWorkspaceSummary.outOfTargetCount > 0 {
                let count = store.sourceWorkspaceSummary.outOfTargetCount
                Text(
                    count == 1
                        ? "1 change is for another event and won’t be included."
                        : "\(count) changes are for another event and won’t be included."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var semanticDiffSections: some View {

        SourceChangeSummarySection(groups: store.sourceWorkspaceSummary.groups)
    }

    @ViewBuilder
    private var sourceSection: some View {
        Section("Source") {
            if let sourceContext = store.sourceContext {
                SourceIndicatorView(sourceContext: sourceContext)

                Button {
                    store.send(.refreshSourceButtonTapped)
                } label: {
                    if store.isRefreshingSource {
                        HStack {
                            ProgressView()
                            Text("Refreshing Source")
                        }
                    } else {
                        Label("Refresh Source", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(store.sourceBaselineID == nil || store.isRefreshingSource)
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
        if store.sourceKind == .tangled {
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
        if store.sourceKind == .tangled {
            Section(title) {
                switch store.tangledPullReviewStatus {
                case let .failed(failure):
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Reviews could not be loaded", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        if showsTechnicalDetails {
                            Text(failure.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                case let .loaded(reviews):
                    if reviews.isEmpty {
                        Label("No open reviews", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(reviews) { review in
                            let isClosing = store.closingTangledPullReviewIDs.contains(review.id)
                            let isDeleting = store.deletingTangledPullReviewIDs.contains(review.id)
                            let isMerging = store.mergingTangledPullReviewIDs.contains(review.id)
                            let closeFailure = store.tangledPullReviewCloseFailures[review.id]
                            let deleteFailure = store.tangledPullReviewDeleteFailures[review.id]
                            let mergeFailure = store.tangledPullReviewMergeFailures[review.id]
                            let isBusy = isClosing || isDeleting || isMerging
                            NavigationLink {
                                TangledPullReviewDetailView(
                                    review: review,
                                    semanticDiffStatus: store.tangledPullReviewSemanticDiffs[review.id]
                                        ?? .notLoaded,
                                    isMerging: isMerging,
                                    isBusy: isBusy,
                                    mergeFailure: mergeFailure,
                                    onLoadSemanticDiff: {
                                        store.send(.reviewSemanticDiffButtonTapped(review))
                                    },
                                    onMerge: {
                                        store.send(.mergeTangledPullReviewButtonTapped(review))
                                    }
                                )
                            } label: {
                                TangledPullReviewRow(
                                    review: review,
                                    isClosing: isClosing,
                                    isDeleting: isDeleting,
                                    isMerging: isMerging,
                                    closeFailure: closeFailure,
                                    deleteFailure: deleteFailure,
                                    mergeFailure: mergeFailure
                                )
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    store.send(.mergeTangledPullReviewButtonTapped(review))
                                } label: {
                                    Text(isMerging ? "Applying" : "Approve")
                                }
                                .disabled(isBusy)
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    store.send(.deleteTangledPullReviewForeverButtonTapped(review))
                                } label: {
                                    Text(isDeleting ? "Deleting" : "Delete")
                                }
                                .disabled(isBusy)

                                Button {
                                    store.send(.closeTangledPullReviewButtonTapped(review))
                                } label: {
                                    Text(isClosing ? "Closing" : "Close")
                                }
                                .disabled(isBusy)
                                .tint(.orange)
                            }
                            .contextMenu {
                                Button {
                                    store.send(.mergeTangledPullReviewButtonTapped(review))
                                } label: {
                                    Text("Approve changes")
                                }
                                .disabled(isBusy)

                                Button(role: .destructive) {
                                    store.send(.closeTangledPullReviewButtonTapped(review))
                                } label: {
                                    Text("Close review")
                                }
                                .disabled(isBusy)

                                Button(role: .destructive) {
                                    store.send(.deleteTangledPullReviewForeverButtonTapped(review))
                                } label: {
                                    Text("Delete review permanently")
                                }
                                .disabled(isBusy)
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
                        if showsTechnicalDetails {
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
}

enum EventWorkspaceTab: String, CaseIterable, Identifiable {
    case propose
    case review

    var id: Self { self }

    func title(for target: SourceProposalTarget) -> String {
        switch self {
        case .propose:
            switch target {
            case .calendar:
                "Changes"
            case .event:
                "Propose"
            }
        case .review:
            "Review"
        }
    }
}

struct TangledPullReviewRow: View {
    let review: TangledPullReview
    var isClosing = false
    var isDeleting = false
    var isMerging = false
    var closeFailure: EventWorkspace.TangledPullReviewCloseFailure?
    var deleteFailure: EventWorkspace.TangledPullReviewDeleteFailure?
    var mergeFailure: EventWorkspace.TangledPullReviewMergeFailure?
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(review.title)
                    .font(.headline)
                    .lineLimit(2)
                    .layoutPriority(1)
                Spacer()
                TangledPullReviewStateChip(state: review.state)
            }

            Text(review.pullRequestMetadataTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(review.patchBlobCountTitle)
                Text(review.commentCountTitle)
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

            if isMerging {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Merging PR")
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
                    if showsTechnicalDetails {
                        Text(closeFailure.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            if let mergeFailure {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PR could not be merged")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    if showsTechnicalDetails {
                        Text(mergeFailure.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            if let deleteFailure {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PR could not be deleted")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    if showsTechnicalDetails {
                        Text(deleteFailure.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
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
        "Opened \(createdAt.tangledPullReviewCreatedAtTitle) for \(organizerDestinationTitle)"
    }

    var organizerDestinationTitle: String {
        targetBranch == "main" ? "Main organizer" : "\(targetBranch) organizer"
    }

    var patchBlobCountTitle: String {
        patchBlobs.count == 1 ? "1 patch" : "\(patchBlobs.count) patches"
    }

    var commentCountTitle: String {
        commentCount == 1 ? "1 comment" : "\(commentCount) comments"
    }
}

private extension Collection where Element == TangledPullReview {
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

struct TangledPullReviewDetailView: View {
    let review: TangledPullReview
    let semanticDiffStatus: EventWorkspace.TangledPullReviewSemanticDiffStatus
    var isMerging = false
    var isBusy = false
    var mergeFailure: EventWorkspace.TangledPullReviewMergeFailure?
    let onLoadSemanticDiff: () -> Void
    let onMerge: () -> Void
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        List {
            Section("Pull Request") {
                LabeledContent("State", value: review.state.tangledPullReviewStateTitle)
                LabeledContent("Author", value: review.author)
                LabeledContent("Created", value: review.createdAt)
                LabeledContent("Target branch", value: review.targetBranch)
            }

            if isMerging {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Merging PR")
                    }
                    .foregroundStyle(.secondary)
                }
            }

            if let mergeFailure {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PR could not be merged")
                            .foregroundStyle(.orange)
                        if showsTechnicalDetails {
                            Text(mergeFailure.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if let body = review.body, !body.isEmpty {
                Section("Description") {
                    Text(body)
                        .textSelection(.enabled)
                }
            }

            reviewSemanticDiffSections

            if showsTechnicalDetails {
                Section {
                    DisclosureGroup("Technical details") {
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

                DisclosureGroup("Patch blobs") {
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

                DisclosureGroup("Raw review") {
                    Text(review.rawReviewText)
                        .font(.caption)
                        .monospaced()
                        .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle(review.title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sourceChangeRowStyle(OpenMusicEventSourceChangeRowStyle())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onMerge()
                } label: {
                    Label(isMerging ? "Merging" : "Merge", systemImage: "arrow.triangle.merge")
                        .labelStyle(.iconOnly)
                }
                .disabled(isBusy)
            }
        }
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
                    if showsTechnicalDetails {
                        Text(failure.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
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

struct SourceWorkspaceSourceContext: Equatable, Sendable {
    var detailTitle: String
    var sourceKind: OMERecord.SourceDatabaseInsertion.SourceKind
    var sourceReference: String
    var sourceRefTitle: String

    init(
        detailTitle: String,
        sourceKind: OMERecord.SourceDatabaseInsertion.SourceKind,
        sourceReference: String,
        sourceRefTitle: String
    ) {
        self.detailTitle = detailTitle
        self.sourceKind = sourceKind
        self.sourceReference = sourceReference
        self.sourceRefTitle = sourceRefTitle
    }
}

struct SourceIndicatorView: View {
    let sourceContext: SourceWorkspaceSourceContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(sourceContext.sourceKind.sourceIndicatorTitle, systemImage: "folder")

            Text(sourceContext.sourceReference)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 2) {
                Text(sourceContext.sourceRefTitle)
                Text(sourceContext.detailTitle)
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
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

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
                Text(
                    mode == .proposal
                        ? "Couldn’t prepare this proposal"
                        : "Changes could not be checked"
                )
                if showsTechnicalDetails {
                    Text(failure.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
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
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

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
                if showsTechnicalDetails {
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
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    public init(store: StoreOf<SourceProposalFlow>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Title") {
                    TextField("Title", text: $store.form.value.title)
                        .onSubmit {
                            store.send(.form(.fieldSubmitted(SourceProposalFormFieldID.title)))
                        }
                    FormFieldValidationStatus(
                        validation: store.form.validation[SourceProposalFormFieldID.title]
                    )
                }

                Section("Description") {
                    TextField(
                        "Description",
                        text: $store.form.value.description,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                }

                SourceProposalStatusView(status: store.status)
                SourceProposalSummarySections(
                    groups: store.sourceChangeGroups,
                    recordComparisons: store.sourceRecordComparisons
                )

                if showsTechnicalDetails {
                    Section {
                        DisclosureGroup("Advanced") {
                            ForEach(store.patch.fileChanges) { change in
                                SourcePatchFileChangeRow(change: change)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Propose Change")
            .sourceChangeRowStyle(OpenMusicEventSourceChangeRowStyle())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        store.send(.doneButtonTapped)
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(store.status.isProposing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    SubmitButton(
                        .propose,
                        isInProgress: store.status.isProposing,
                        isDisabled: !store.canCreateSourceProposal
                    ) {
                        store.send(.createProposalButtonTapped)
                    }
                }
            }
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

struct SourceChangeSummarySection: View {
    let groups: [SourceChangeGroup]

    var body: some View {
        Section("Semantic Diff") {
            ForEach(groups.filter { $0.totalCount > 0 }) { group in
                SourceChangeGroupDisclosure(group: group)
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
        DisclosureGroup {
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

private extension SourceRecordChange {
    func matches(eventID: OMERecord.Event.ID) -> Bool {
        primaryKeyValues.first { $0.columnName == "organizerID" }?.value
            == String(describing: eventID.organizerID).databaseValue
            && primaryKeyValues.first { $0.columnName == "eventID" }?.value
                == eventID.eventID.rawValue.rawValue.databaseValue
    }
}

private extension Array where Element == SourceChangeGroup {
    func prioritizing(target: SourceProposalTarget) -> Self {
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
    static func sourceBaselineQuery(
        target: SourceProposalTarget
    ) -> some SelectStatementOf<SourceBaselineRecord> {
        switch target {
        case let .calendar(_, sourceBaselineID):
            SourceBaselineRecord.where { $0.id.eq(sourceBaselineID) }

        case let .event(eventID):
            SourceBaselineRecord.where { sourceBaseline in
                EventSourceProvenanceRecord
                    .where { $0.id.eq(eventID) }
                    .where { $0.sourceBaselineID.eq(sourceBaseline.id) }
                    .exists()
            }
        }
    }

    static func sourceProvenanceQuery(
        target: SourceProposalTarget
    ) -> some SelectStatementOf<EventSourceProvenanceRecord> {
        switch target {
        case let .calendar(calendarID, sourceBaselineID):
            EventSourceProvenanceRecord
                .where { $0.sourceBaselineID.eq(sourceBaselineID) }
                .where { $0.id.organizerID.eq(calendarID.ownerID) }

        case let .event(eventID):
            EventSourceProvenanceRecord.where { $0.id.eq(eventID) }
        }
    }

    var defaultWorkspaceTab: EventWorkspaceTab {
        switch target {
        case .calendar:
            .propose
        case .event:
            .propose
        }
    }

    var sourceContext: SourceWorkspaceSourceContext? {
        if let sourceBaseline {
            return SourceWorkspaceSourceContext(
                detailTitle: "Organizer source",
                sourceKind: sourceBaseline.sourceKind,
                sourceReference: sourceBaseline.sourceReference,
                sourceRefTitle: sourceBaseline.ref ?? "default ref"
            )
        }

        if let sourceProvenance {
            return SourceWorkspaceSourceContext(
                detailTitle: "events/\(sourceProvenance.sourceEventDirectory)",
                sourceKind: sourceProvenance.sourceKind,
                sourceReference: sourceProvenance.sourceReference,
                sourceRefTitle: sourceProvenance.sourceRefTitle
            )
        }

        return nil
    }

    var sourceKind: OMERecord.SourceDatabaseInsertion.SourceKind? {
        sourceBaseline?.sourceKind ?? sourceProvenance?.sourceKind
    }

    var sourceReviewProvenance: OMERecord.SourceDatabaseInsertion.SourceProvenance? {
        sourceBaseline?.sourceProvenance ?? sourceProvenance?.sourceProvenance
    }

    var workspaceSourcePatchRequest: OpenMusicEventCalendarSourcePatchRequest? {
        switch target {
        case let .calendar(calendarID, sourceBaselineID):
            OpenMusicEventCalendarSourcePatchRequest(
                calendarID: calendarID,
                sourceBaselineID: sourceBaselineID
            )

        case let .event(eventID):
            sourceBaselineID.map {
                OpenMusicEventCalendarSourcePatchRequest(
                    calendarID: OMERecord.Calendar.ID(
                        ownerID: eventID.organizerID,
                        calendarID: OMERecord.Calendar.defaultID
                    ),
                    sourceBaselineID: $0
                )
            }
        }
    }

    mutating func dismissSourceProposal() {
        let status = sourceProposal?.status ?? sourceProposalStatus
        sourceProposal = nil
        switch status {
        case .composing, .failed:
            sourceProposalStatus = .idle
        case .created, .idle, .proposing:
            sourceProposalStatus = status
        }
    }

    mutating func presentSourceProposal(for patch: SourcePatch) {
        guard !patch.isEmpty, canReviewSourceProposal else {
            sourceProposal = nil
            sourceProposalStatus = .idle
            return
        }

        sourceProposal = SourceProposalFlow.State(
            target: target,
            sourceChangeGroups: sourceWorkspaceSummary.groups,
            sourceRecordComparisons: sourceWorkspaceSummary.recordComparisons,
            patch: patch
        )
        sourceProposalStatus = .composing
    }

    var canResetEdits: Bool {
        guard !isResettingEdits,
              sourceWorkspaceSummary.totalCount > 0,
              case .available = sourceWorkspaceSummary.availability
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

    var canCreateEvent: Bool {
        guard case .calendar = target else { return false }
        return true
    }

    var canReviewSourceProposal: Bool {
        sourceBaselineID != nil
    }

    var canProposeLocalChanges: Bool {
        guard sourceWorkspaceSummary.totalCount > 0,
              canReviewSourceProposal,
              !sourcePatchStatus.isGenerating,
              !sourceProposalStatus.isProposing
        else { return false }
        return true
    }
}

private extension EventWorkspace.TangledPullReviewSemanticDiff {
    static func reviewBranchDiff(
        target: SourceProposalTarget,
        sourceBaselineID: SourceBaselineRecord.ID,
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
                organizerID: target.organizerID,
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
            let calendarID: OME.Calendar.ID
            switch target {
            case let .calendar(targetCalendarID, _):
                calendarID = targetCalendarID

            case let .event(eventID):
                calendarID = OME.Calendar.ID(
                    ownerID: eventID.organizerID,
                    calendarID: OME.Calendar.defaultID
                )
            }
            let baselineSchemaName = "review_source_baseline"
            try #sql(
                "ATTACH DATABASE \(bind: baselineDatabase.path) AS \(quote: baselineSchemaName)"
            )
            .execute(db)
            defer {
                try? #sql("DETACH DATABASE \(quote: baselineSchemaName)").execute(db)
            }
            return try openMusicEventSourceEditSummary(
                in: db,
                baselineSchemaName: baselineSchemaName,
                sourceBaselineID: sourceBaselineID,
                calendarID: calendarID
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

private extension SourceProposalTarget {
    func matches(invalidation: SourcePatchInvalidation) async -> Bool {
        @Dependency(\.defaultDatabase) var database
        switch self {
        case let .event(eventID):
            guard invalidation.eventID.organizerID == eventID.organizerID else {
                return false
            }
            do {
                return try await database.read { db in
                    guard let sourceBaselineID = try (
                        EventSourceProvenanceRecord
                            .where { $0.id.eq(eventID) }
                            .fetchOne(db)?
                            .sourceBaselineID
                    )
                    else {
                        return invalidation.eventID == eventID
                    }

                    return try EventSourceProvenanceRecord
                        .where { $0.id.eq(invalidation.eventID) }
                        .where { $0.sourceBaselineID.eq(sourceBaselineID) }
                        .fetchOne(db) != nil
                }
            } catch {
                reportIssue(error)
                return false
            }

        case let .calendar(calendarID, sourceBaselineID):
            guard invalidation.eventID.organizerID == calendarID.ownerID else {
                return false
            }
            do {
                return try await database.read { db in
                    try EventSourceProvenanceRecord
                        .where { $0.id.eq(invalidation.eventID) }
                        .where { $0.sourceBaselineID.eq(sourceBaselineID) }
                        .fetchOne(db) != nil
                }
            } catch {
                reportIssue(error)
                return false
            }
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
            "Merged"
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
                        .textSelection(.enabled)
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
