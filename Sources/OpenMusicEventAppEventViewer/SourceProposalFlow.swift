import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventSourceEditing
import SourceEditing

public enum SourceProposalTarget: Equatable, Identifiable, Sendable {
    case calendar(OMERecord.Calendar.ID, SourceBaselineRecord.ID)
    case event(OMERecord.Event.ID)

    public var id: String {
        switch self {
        case let .calendar(calendarID, sourceBaselineID):
            "calendar:\(calendarID.ownerID):\(calendarID.calendarID.rawValue.rawValue):\(sourceBaselineID.rawValue)"
        case let .event(eventID):
            "event:\(eventID.organizerID):\(eventID.eventID.rawValue.rawValue)"
        }
    }

    var defaultTitle: String {
        switch self {
        case .calendar:
            "Update source calendar"
        case .event:
            "Update event source"
        }
    }
}

@Feature
public struct SourceProposalFlow {
    public init() {}

    public struct State: Identifiable {
        public init(
            target: SourceProposalTarget,
            sourceChangeGroups: [SourceChangeGroup] = [],
            sourceRecordComparisons: SourceRecordComparisons = .empty,
            patch: SourcePatch
        ) {
            self.target = target
            self.patch = patch
            self.sourceChangeGroups = sourceChangeGroups
            self.sourceRecordComparisons = sourceRecordComparisons
            self.title = target.defaultTitle
        }

        public init(
            eventID: OMERecord.Event.ID,
            workspaceSummary: EventWorkspaceSummary? = nil,
            patch: SourcePatch
        ) {
            self.init(
                target: .event(eventID),
                sourceChangeGroups: workspaceSummary?.groups ?? [],
                sourceRecordComparisons: workspaceSummary?.recordComparisons ?? .empty,
                patch: patch
            )
        }

        public var id: String { target.id }

        public var eventID: OMERecord.Event.ID? {
            guard case let .event(eventID) = target else { return nil }
            return eventID
        }

        public var description = ""
        public let patch: SourcePatch
        public var sourceChangeGroups: [SourceChangeGroup]
        public var sourceRecordComparisons: SourceRecordComparisons
        public var status: EventWorkspace.SourceProposalStatus = .composing
        public let target: SourceProposalTarget
        public var title: String
    }

    @CasePathable
    public enum Action {
        case createProposalButtonTapped
        case delegate(Delegate)
        case doneButtonTapped
    }

    public enum Delegate: Equatable, Sendable {
        case dismissed
    }

    @Dependency(\.openMusicEventSourcePatchLocationResolver) var sourcePatchLocationResolver
    @Dependency(\.openMusicEventCalendarSourcePatchLocationResolver) var calendarSourcePatchLocationResolver
    @Dependency(\.sourcePatchPublisher) var sourcePatchPublisher

    public var body: some Feature {
        let _ = Self._logChanges()
        Update { state, action in
            switch action {
            case .createProposalButtonTapped:
                guard !state.patch.isEmpty,
                      state.status.canCreateProposal
                else { return }

                let calendarSourcePatchLocationResolver = calendarSourcePatchLocationResolver
                let description = state.description.sourceProposalValue
                let patch = state.patch
                let sourcePatchLocationResolver = sourcePatchLocationResolver
                let sourcePatchPublisher = sourcePatchPublisher
                let target = state.target
                let title = state.title.sourceProposalValue

                state.status = .proposing
                store.addTask {
                    let publication = await store.withErrorHandling(
                        fallbackMessage: .sourceProposalPublishFailed,
                        operation: .sourceProposalPublish
                    ) {
                        let location = try await target.resolveLocation(
                            calendarSourcePatchLocationResolver: calendarSourcePatchLocationResolver,
                            sourcePatchLocationResolver: sourcePatchLocationResolver
                        )
                        return try await sourcePatchPublisher.publish(
                            SourcePatchPublishRequest(
                                description: description,
                                location: location,
                                patch: patch,
                                title: title
                            )
                        )
                    } cleanup: {
                        $0.status = .failed(
                            EventWorkspace.SourceProposalFailure(
                                SourceProposalPublishFailed()
                            )
                        )
                    }

                    guard let publication else {
                        if Task.isCancelled {
                            try store.modify {
                                $0.status = .composing
                            }
                        }
                        return
                    }

                    try store.modify {
                        $0.status = .created(publication)
                    }
                }

            case .delegate:
                break

            case .doneButtonTapped:
                store.addTask {
                    try store.send(.delegate(.dismissed))
                }
            }
        }
    }
}

private extension UserFacingText {
    static let sourceProposalPublishFailed = Self(
        "Unable to create proposal.",
        fallback: "Unable to create proposal."
    )
}

private extension ErrorOperation {
    static let sourceProposalPublish = Self("source.proposal.publish")
}

private struct SourceProposalPublishFailed: CustomStringConvertible, Error {
    var description: String {
        "Unable to create proposal."
    }
}

extension SourceProposalFlow.State {
    var canCreateSourceProposal: Bool {
        !patch.isEmpty && status.canCreateProposal
    }
}

private extension SourceProposalTarget {
    func resolveLocation(
        calendarSourcePatchLocationResolver: OpenMusicEventCalendarSourcePatchLocationResolver,
        sourcePatchLocationResolver: OpenMusicEventSourcePatchLocationResolver
    ) async throws -> SourcePatchLocation {
        switch self {
        case let .calendar(calendarID, sourceBaselineID):
            try await calendarSourcePatchLocationResolver.resolve(
                OpenMusicEventCalendarSourcePatchRequest(
                    calendarID: calendarID,
                    sourceBaselineID: sourceBaselineID
                )
            )

        case let .event(eventID):
            try await sourcePatchLocationResolver.resolve(
                OpenMusicEventSourcePatchRequest(eventID: eventID)
            )
        }
    }
}

private extension String {
    var sourceProposalValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
