import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventSourceEditing
import SourceEditing

@Feature
public struct SourceProposalFlow {
    public init() {}

    public struct State: Identifiable {
        public init(
            eventID: OMERecord.Event.ID,
            editSummary: EventEditSummary? = nil,
            patch: SourcePatch
        ) {
            self.eventID = eventID
            self.patch = patch
            self.editSummary = editSummary
                ?? EventEditSummary(
                    eventID: eventID,
                    availability: .notSourceBacked,
                    groups: []
                )
        }

        public var id: OMERecord.Event.ID { eventID }

        public let eventID: OMERecord.Event.ID
        public let patch: SourcePatch
        public var authorization = OpenMusicEventAuthorizationPresentation.State()
        public var editSummary: EventEditSummary
        public var sourceProposalDescription = ""
        public var sourceProposalStatus: EditEvent.SourceProposalStatus = .composing
        public var sourceProposalTitle = "Update event source"
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
    @Dependency(\.sourcePatchPublisher) var sourcePatchPublisher

    public var body: some Feature {
        Features {
            Scope(\.authorization, action: \.authorization) {
                OpenMusicEventAuthorizationPresentation()
            }

            Update { state, action in
                func createSourceProposal(
                    eventID: OMERecord.Event.ID,
                    patch: SourcePatch,
                    description: String?,
                    title: String?
                ) {
                    let sourcePatchLocationResolver = sourcePatchLocationResolver
                    let sourcePatchPublisher = sourcePatchPublisher
                    let authorizationPresenter = OpenMusicEventAuthorizationPresenter { request in
                        await Task.yield()
                        try store.send(.authorization(.present(request)))
                    }
                    store.addTask {
                        await Task.yield()
                        do {
                            let location = try await sourcePatchLocationResolver.resolve(
                                OpenMusicEventSourcePatchRequest(eventID: eventID)
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
                        eventID: state.eventID,
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
