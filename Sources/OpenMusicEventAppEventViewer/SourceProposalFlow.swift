import ATProtoOAuth
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventSourceEditing
import Sharing
import SourceEditing
import TCATProtoAuthentication

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
            self._session = OpenMusicEventOAuth.session
            self._sessionStore = OpenMusicEventOAuth.sessionStore
        }

        public var id: OMERecord.Event.ID { eventID }

        public let eventID: OMERecord.Event.ID
        public let patch: SourcePatch
        public var authorization: AuthorizationFlow.State?
        @DebugSnapshotIgnored
        public var authorizationPresentationRequest: AuthorizationPresentationRequest?
        public var editSummary: EventEditSummary
        @Shared public var session: OAuth.Session?
        @Shared public var sessionStore: OAuth.SessionStore
        public var sourceProposalDescription = ""
        public var sourceProposalStatus: EditEvent.SourceProposalStatus = .composing
    }

    @CasePathable
    public enum Action {
        case authorization(AuthorizationFlow.Action)
        case createProposalButtonTapped
        case delegate(Delegate)
        case dismissButtonTapped
        case sourceProposalCancelled
        case sourceProposalDescriptionChanged(String)
        case sourceProposalResponse(Result<SourcePatchPublication, EditEvent.SourceProposalFailure>)
    }

    public enum Delegate: Equatable, Sendable {
        case dismissed
    }

    @Dependency(\.openMusicEventSourcePatchLocationResolver) var sourcePatchLocationResolver
    @Dependency(\.sourcePatchPublisher) var sourcePatchPublisher

    public var body: some Feature {
        Update { state, action in
            func createSourceProposal(
                eventID: OMERecord.Event.ID,
                patch: SourcePatch,
                description: String?
            ) {
                let sourcePatchLocationResolver = sourcePatchLocationResolver
                let sourcePatchPublisher = sourcePatchPublisher
                let authorizationPresenter = SourceProposalAuthorizationPresenter { request in
                    await Task.yield()
                    var didPresent = false
                    try store.modify { state in
                        guard state.sourceProposalStatus == .proposing else { return }
                        didPresent = true
                        state.authorizationPresentationRequest = request
                        state.authorization = OpenMusicEventOAuth.authorizationFlowState(
                            for: request,
                            session: state.session,
                            sessionStore: state.sessionStore
                        )
                    }
                    if !didPresent {
                        await request.responder.cancel()
                    }
                }
                store.addTask {
                    do {
                        let location = try await sourcePatchLocationResolver.resolve(
                            OpenMusicEventSourcePatchRequest(eventID: eventID)
                        )
                        let publication = try await withDependencies {
                            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { requirement in
                                try await authorizationPresenter.authorize(requirement)
                            }
                        } operation: {
                            try await sourcePatchPublisher.publish(
                                SourcePatchPublishRequest(
                                    description: description,
                                    location: location,
                                    patch: patch
                                )
                            )
                        }
                        try store.send(.sourceProposalResponse(.success(publication)))
                    } catch is CancellationError {
                        try store.send(.sourceProposalCancelled)
                    } catch {
                        try store.send(
                            .sourceProposalResponse(
                                .failure(EditEvent.SourceProposalFailure(error))
                            )
                        )
                    }
                }
            }

            switch action {
            case .authorization(.delegate(.succeeded)):
                state.$session.withLock {
                    $0 = state.sessionStore.selectedSession
                }
                let routedRequest = state.authorizationPresentationRequest
                state.authorizationPresentationRequest = nil
                state.authorization = nil
                store.addTask {
                    await routedRequest?.responder.succeed()
                }

            case .authorization(.delegate(.cancelled)):
                let routedRequest = state.authorizationPresentationRequest
                state.authorizationPresentationRequest = nil
                state.authorization = nil
                state.sourceProposalStatus = .composing
                store.addTask {
                    await routedRequest?.responder.cancel()
                }

            case .authorization(.delegate(.failed(let error))):
                let routedRequest = state.authorizationPresentationRequest
                state.authorizationPresentationRequest = nil
                state.authorization = nil
                store.addTask {
                    await routedRequest?.responder.fail(error)
                }

            case .authorization:
                break

            case .createProposalButtonTapped:
                guard !state.patch.isEmpty,
                      state.sourceProposalStatus.canCreateProposal
                else { return }
                let description = state.sourceProposalDescription.sourceProposalDescriptionValue
                state.sourceProposalStatus = .proposing
                createSourceProposal(
                    eventID: state.eventID,
                    patch: state.patch,
                    description: description
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
            }
        }
        .onMount { state in
            if let session = state.session, state.sessionStore.selectedSession == nil {
                state.$sessionStore.withLock {
                    $0.upsert(session)
                }
            }
            state.$session.withLock {
                $0 = state.sessionStore.selectedSession
            }
        }
        .onChange(of: store.session) { _, session, state in
            guard let session else { return }
            state.$sessionStore.withLock {
                $0.upsert(session)
            }
        }
        .ifLet(\.authorization, action: \.authorization) {
            AuthorizationFlow(sessionStore: store.$sessionStore)
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
}

private final class SourceProposalAuthorizationPresenter: @unchecked Sendable {
    private let present: (AuthorizationPresentationRequest) async throws -> Void

    init(present: @escaping (AuthorizationPresentationRequest) async throws -> Void) {
        self.present = present
    }

    func authorize(_ requirement: OAuth.AuthRequirement) async throws {
        let request = AuthorizationPresentationRequest(requirement: requirement)
        try await present(request)
        try await request.responder.wait()
    }
}
