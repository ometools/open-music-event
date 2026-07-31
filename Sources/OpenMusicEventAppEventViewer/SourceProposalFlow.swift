import ComposableForms
import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventSourceEditing
import Sharing
import SourceEditing

public typealias SourceProposalTarget = OpenMusicEventSourceTarget

@Feature
public struct SourceProposalFlow {
    public init() {}

    public struct FormValue: Equatable, Sendable {
        var description = ""
        var title = ""
    }

    public typealias FormFeature = ComposableForms.Form<FormValue>

    public struct State: Identifiable {
        public init(
            target: SourceProposalTarget,
            sourceChangeGroups: [SourceChangeGroup] = [],
            sourceRecordComparisons: SourceRecordComparisons = .empty,
            sourceFileAttributions: [SourceFileAttribution] = [],
            patch: SourcePatch
        ) {
            self.target = target
            self.patch = patch
            self.sourceChangeGroups = sourceChangeGroups
            self.sourceRecordComparisons = sourceRecordComparisons
            self.sourceFileAttributions = sourceFileAttributions
            self.form = FormFeature.State(value: FormValue())
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

        public var form: FormFeature.State
        public let patch: SourcePatch
        public var sourceChangeGroups: [SourceChangeGroup]
        public var sourceFileAttributions: [SourceFileAttribution]
        public var sourceRecordComparisons: SourceRecordComparisons
        public var status: EventWorkspace.SourceProposalStatus = .composing
        public let target: SourceProposalTarget

        public var description: String {
            get { form.value.description }
            set { form.value.description = newValue }
        }

        public var title: String {
            get { form.value.title }
            set { form.value.title = newValue }
        }
    }

    @CasePathable
    public enum Action {
        case createProposalButtonTapped
        case delegate(Delegate)
        case doneButtonTapped
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
    }

    public enum Delegate: Equatable, Sendable {
        case created(SourcePatchPublication)
        case dismissed
    }

    @Dependency(\.openMusicEventSourcePatchLocationResolver) var sourcePatchLocationResolver
    @Dependency(\.openMusicEventCalendarSourcePatchLocationResolver) var calendarSourcePatchLocationResolver
    @Dependency(\.sourcePatchPublisher) var sourcePatchPublisher
    @Dependency(\.authoringGrant) var authoringGrant
    @Dependency(\.editingWorkspaceID) var editingWorkspaceID
    @Dependency(WorkspacePreparationClient.self) var workspacePreparation
    @Dependency(AuthoringPolicyClient.self) var authoringPolicy

    public var body: some Feature {
        let _ = Self._logChanges()
        Scope(\.form, action: \.form) {
            FormFeature()
                .onSubmit { value in
                    try store.send(.formSubmitted(value))
                }
        }
        Update { state, action in
            switch action {
            case .createProposalButtonTapped:
                guard !state.patch.isEmpty,
                      state.status.canCreateProposal
                else { return }

                store.addTask {
                    try store.send(.form(.submittedForm))
                }

            case let .formSubmitted(value):
                guard !state.patch.isEmpty,
                      state.status.canCreateProposal,
                      let title = value.title.sourceProposalValue
                else { return }

                let calendarSourcePatchLocationResolver = calendarSourcePatchLocationResolver
                let description = value.description.sourceProposalValue
                let patch = state.patch
                let sourcePatchLocationResolver = sourcePatchLocationResolver
                let sourcePatchPublisher = sourcePatchPublisher
                let target = state.target
                let workspaceID = editingWorkspaceID
                let workspacePreparation = workspacePreparation
                let authoringGrant = authoringGrant
                let authoringPolicy = authoringPolicy
                let store = store

                state.status = .proposing
                store.addTask {
                    switch await Self.revalidatedAuthoringAccess(
                        authoringGrant: authoringGrant,
                        authoringPolicy: authoringPolicy
                    ) {
                    case .current, .notMounted:
                        break
                    case .revoked:
                        await store.reportError(
                            AuthoringPolicyError.admissionDenied,
                            fallbackMessage: .authoringAccessChanged,
                            operation: .sourceProposalPublish
                        )
                        do {
                            let task = try store.post(
                                key: AuthoringAccessRevoked.self,
                                value: ()
                            )
                            await task?.value
                        } catch {}
                        return
                    case let .unavailable(error):
                        do {
                            try store.modify {
                                $0.status = .failed(
                                    EventWorkspace.SourceProposalFailure(
                                        SourceProposalPublishFailed()
                                    )
                                )
                            }
                        } catch {
                            return
                        }
                        await store.reportError(
                            error,
                            fallbackMessage: .sourceProposalPublishFailed,
                            operation: .sourceProposalPublish
                        )
                        return
                    }

                    if let workspaceID {
                        try await workspacePreparation.prepareSource(workspaceID)
                    }

                    do {
                        let location = try await target.resolveLocation(
                            calendarSourcePatchLocationResolver: calendarSourcePatchLocationResolver,
                            sourcePatchLocationResolver: sourcePatchLocationResolver
                        )
                        let publication = try await sourcePatchPublisher.publish(
                            SourcePatchPublishRequest(
                                description: description,
                                location: location,
                                patch: patch,
                                title: title
                            )
                        )
                        try store.modify {
                            $0.status = .created(publication)
                        }
                        try store.send(.delegate(.created(publication)))
                    } catch {
                        if Task.isCancelled {
                            try store.modify {
                                $0.status = .composing
                            }
                            return
                        }
                        if case .revoked = await Self.revalidatedAuthoringAccess(
                            authoringGrant: authoringGrant,
                            authoringPolicy: authoringPolicy
                        ) {
                            await store.reportError(
                                error,
                                fallbackMessage: .authoringAccessChanged,
                                operation: .sourceProposalPublish
                            )
                            do {
                                let task = try store.post(
                                    key: AuthoringAccessRevoked.self,
                                    value: ()
                                )
                                await task?.value
                            } catch {}
                        } else {
                            do {
                                try store.modify {
                                    $0.status = .failed(
                                        EventWorkspace.SourceProposalFailure(
                                            SourceProposalPublishFailed()
                                        )
                                    )
                                }
                            } catch {
                                return
                            }
                            await store.reportError(
                                error,
                                fallbackMessage: .sourceProposalPublishFailed,
                                operation: .sourceProposalPublish
                            )
                        }
                    }
                }

            case .delegate:
                break

            case .doneButtonTapped:
                store.addTask {
                    try store.send(.delegate(.dismissed))
                }

            case .form:
                break
            }
        }
    }

    enum RevalidatedAuthoringAccess {
        case current
        case notMounted
        case revoked
        case unavailable(any Error)
    }

    static func revalidatedAuthoringAccess(
        authoringGrant: SharedReader<AuthoringGrant?>,
        authoringPolicy: AuthoringPolicyClient
    ) async -> RevalidatedAuthoringAccess {
        guard let grant = authoringGrant.wrappedValue else {
            return .notMounted
        }
        do {
            let admission = try await authoringPolicy.admission(grant.workspaceID)
            guard case let .granted(principal, role) = admission,
                  principal == grant.principal,
                  role == grant.role
            else {
                return .revoked
            }
            return .current
        } catch {
            return .unavailable(error)
        }
    }

}

enum SourceProposalFormFieldID {
    static var title: AnyHashable { AnyHashable(\SourceProposalFlow.FormValue.title) }
}

private extension SourceProposalFlow.FormFeature {
    init() {
        self.init {
            Self.Field(\.title) {
                Validation(error: "Enter a title.") { value in
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }

            Self.Field(\.description)
        }
    }
}

private extension UserFacingText {
    static let authoringAccessChanged = Self(
        "Your authoring access changed. Your edits remain saved.",
        fallback: "Your authoring access changed. Your edits remain saved."
    )
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
        !patch.isEmpty
            && status.canCreateProposal
            && form.canSubmit
            && title.sourceProposalValue != nil
    }
}

private extension String {
    var sourceProposalValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
