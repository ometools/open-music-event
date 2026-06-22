import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventAuthentication
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
            patch: SourcePatch
        ) {
            self.target = target
            self.patch = patch
            self.sourceChangeGroups = sourceChangeGroups
            self.sourceProposalTitle = target.defaultTitle
        }

        public init(
            eventID: OMERecord.Event.ID,
            editSummary: EventEditSummary? = nil,
            patch: SourcePatch
        ) {
            self.init(
                target: .event(eventID),
                sourceChangeGroups: editSummary?.groups ?? [],
                patch: patch
            )
        }

        public var id: String { target.id }

        public var eventID: OMERecord.Event.ID? {
            guard case let .event(eventID) = target else { return nil }
            return eventID
        }

        public let target: SourceProposalTarget
        public let patch: SourcePatch
        public var authorization = OpenMusicEventAuthorizationPresentation.State()
        public var sourceChangeGroups: [SourceChangeGroup]
        public var sourceProposalDescription = ""
        public var sourceProposalStatus: EditEvent.SourceProposalStatus = .composing
        public var sourceProposalTitle: String
    }

    @CasePathable
    public enum Action {
        case authorization(OpenMusicEventAuthorizationPresentation.Action)
        case createProposalButtonTapped
        case delegate(Delegate)
        case dismissButtonTapped
        case sourceProposalCancelled
        case sourceProposalDescriptionChanged(String)
        case sourceProposalResponse(Result<SourcePatchPublication, EditEvent.SourceProposalFailure>)
        case sourceProposalTitleChanged(String)
    }

    public enum Delegate: Equatable, Sendable {
        case dismissed
    }

    @Dependency(\.openMusicEventSourcePatchLocationResolver) var sourcePatchLocationResolver
    @Dependency(\.openMusicEventCalendarSourcePatchLocationResolver) var calendarSourcePatchLocationResolver
    @Dependency(\.sourcePatchPublisher) var sourcePatchPublisher

    public var body: some Feature {
        Features {
            Scope(\.authorization, action: \.authorization) {
                OpenMusicEventAuthorizationPresentation()
            }

            Update { state, action in
                func createSourceProposal(
                    target: SourceProposalTarget,
                    patch: SourcePatch,
                    description: String?,
                    title: String?
                ) {
                    let calendarSourcePatchLocationResolver = calendarSourcePatchLocationResolver
                    let sourcePatchLocationResolver = sourcePatchLocationResolver
                    let sourcePatchPublisher = sourcePatchPublisher
                    let authorizationPresenter = OpenMusicEventAuthorizationPresenter { request in
                        await Task.yield()
                        try store.send(.authorization(.present(request)))
                    }
                    store.addTask {
                        await Task.yield()
                        do {
                            let location = try await target.resolveLocation(
                                calendarSourcePatchLocationResolver: calendarSourcePatchLocationResolver,
                                sourcePatchLocationResolver: sourcePatchLocationResolver
                            )
                            let publication = try await withOpenMusicEventAuthorization(
                                presenter: authorizationPresenter
                            ) {
                                try await sourcePatchPublisher.publish(
                                    SourcePatchPublishRequest(
                                        description: description,
                                        location: location,
                                        patch: patch,
                                        title: title
                                    )
                                )
                            }
                            await Task.yield()
                            try store.send(.sourceProposalResponse(.success(publication)))
                        } catch is CancellationError {
                            await Task.yield()
                            try store.send(.sourceProposalCancelled)
                        } catch {
                            await Task.yield()
                            try store.send(
                                .sourceProposalResponse(
                                    .failure(EditEvent.SourceProposalFailure(error))
                                )
                            )
                        }
                    }
                }

                switch action {
                case .authorization:
                    break

                case .createProposalButtonTapped:
                    guard !state.patch.isEmpty,
                          state.sourceProposalStatus.canCreateProposal
                    else { return }
                    let description = state.sourceProposalDescription.sourceProposalDescriptionValue
                    let title = state.sourceProposalTitle.sourceProposalTitleValue
                    state.sourceProposalStatus = .proposing
                    createSourceProposal(
                        target: state.target,
                        patch: state.patch,
                        description: description,
                        title: title
                    )

                case .delegate:
                    break

                case .dismissButtonTapped:
                    store.addTask {
                        try store.send(.delegate(.dismissed))
                    }

                case .sourceProposalCancelled:
                    state.sourceProposalStatus = .composing

                case let .sourceProposalDescriptionChanged(description):
                    state.sourceProposalDescription = description

                case let .sourceProposalResponse(.success(publication)):
                    let status = EditEvent.SourceProposalStatus.created(publication)
                    state.sourceProposalStatus = status

                case let .sourceProposalResponse(.failure(failure)):
                    let status = EditEvent.SourceProposalStatus.failed(failure)
                    state.sourceProposalStatus = status

                case let .sourceProposalTitleChanged(title):
                    state.sourceProposalTitle = title
                }
            }
        }
    }
}

extension SourceProposalFlow.State {
    var canCreateSourceProposal: Bool {
        !patch.isEmpty && sourceProposalStatus.canCreateProposal
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
    var sourceProposalDescriptionValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var sourceProposalTitleValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
