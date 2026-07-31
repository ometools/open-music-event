import ComposableArchitecture2
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventSource
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
public struct WorkspaceChanges {
    public init() {}

    public enum PatchPurpose: Equatable, Sendable {
        case checkChanges
        case proposeChanges
    }

    public enum SourcePatchStatus: Equatable, Sendable {
        case failed(PatchPurpose, SourcePatchGenerationFailure)
        case generated(SourceProposalPreparation)
        case generating(PatchPurpose)
        case needsGeneration
        case notGenerated
    }

    public struct SourcePatchGenerationFailure: Equatable, Error, Sendable {
        public var message: String

        public init(_ error: any Error) {
            self.message = String(describing: error)
        }

        public init(message: String) {
            self.message = message
        }
    }

    public struct SourceProposalPreparation: Equatable, Sendable {
        public var patch: SourcePatch
        public var sourceFileAttributions: [SourceFileAttribution]
        public var sourceWorkspaceSummary: SourceWorkspaceSummary

        public init(
            patch: SourcePatch,
            sourceFileAttributions: [SourceFileAttribution] = [],
            sourceWorkspaceSummary: SourceWorkspaceSummary
        ) {
            self.patch = patch
            self.sourceFileAttributions = sourceFileAttributions
            self.sourceWorkspaceSummary = sourceWorkspaceSummary
        }
    }

    public struct ResetEditsFailure: Equatable, Error, Sendable {
        public var message: String

        public init(_ error: any Error) {
            self.message = String(describing: error)
        }
    }

    public enum ResetStatus: Equatable, Sendable {
        case failed(ResetEditsFailure)
        case idle
        case resetting
    }

    public struct State {
        public init(target: SourceProposalTarget) {
            self._authoringGrant = Self.authoringGrant()
            self.target = target
            self._sourceWorkspaceSummary = Fetch(
                wrappedValue: SourceWorkspaceSummary.initialValue(target: target),
                SourceWorkspaceSummary.query(target: target)
            )
            self._sourceProvenance = FetchOne(
                Self.sourceProvenanceQuery(target: target)
            )
            self._sourceBaseline = FetchOne(
                Self.sourceBaselineQuery(target: target)
            )
        }

        public let target: SourceProposalTarget
        @SharedReader public var authoringGrant: AuthoringGrant?
        public var resetStatus: ResetStatus = .idle
        public var sourcePatchStatus: SourcePatchStatus = .notGenerated
        public var sourceProposal: SourceProposalFlow.State?
        @DebugSnapshotIgnored
        @FetchOne public var sourceBaseline: SourceBaselineRecord?
        @DebugSnapshotIgnored
        @FetchOne public var sourceProvenance: EventSourceProvenanceRecord?
        @DebugSnapshotIgnored
        @Fetch public var sourceWorkspaceSummary: SourceWorkspaceSummary
    }

    public enum Action {
        case checkChangesButtonTapped
        case proposeChangesButtonTapped
        case resetChangesButtonTapped
        case sourceProposal(SourceProposalFlow.Action)
    }

    @Dependency(SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self)
    var calendarSourcePatchGenerator
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.eventWorkspaceResetter) var workspaceResetter

    public var body: some Feature {
        let _ = Self._logChanges()
        Update { state, action in
            switch action {
            case .checkChangesButtonTapped:
                guard state.canGenerateSourcePatch,
                      let sourcePatchRequest = state.workspaceSourcePatchRequest
                else { return }

                let calendarSourcePatchGenerator = calendarSourcePatchGenerator
                let database = database
                let sourceWorkspaceSummary = state.sourceWorkspaceSummary
                state.sourcePatchStatus = .generating(.checkChanges)
                store.addTask {
                    do {
                        let patch = try await calendarSourcePatchGenerator.generate(
                            sourcePatchRequest
                        )
                        let sourceFileAttributions = try await database.read { db in
                            try openMusicEventSourceFileAttributions(
                                patch: patch,
                                groups: sourceWorkspaceSummary.groups,
                                recordComparisons: sourceWorkspaceSummary.recordComparisons,
                                in: db
                            )
                        }
                        let preparation = SourceProposalPreparation(
                            patch: patch,
                            sourceFileAttributions: sourceFileAttributions,
                            sourceWorkspaceSummary: sourceWorkspaceSummary
                        )
                        try store.modify {
                            guard $0.sourceWorkspaceSummary == sourceWorkspaceSummary else {
                                $0.sourcePatchStatus = .needsGeneration
                                return
                            }
                            $0.sourcePatchStatus = .generated(preparation)
                            $0.sourceProposal = nil
                        }
                    } catch {
                        try store.modify {
                            $0.sourcePatchStatus = .failed(
                                .checkChanges,
                                SourcePatchGenerationFailure(error)
                            )
                            $0.sourceProposal = nil
                        }
                    }
                }

            case .proposeChangesButtonTapped:
                guard state.canProposeChanges,
                      let sourcePatchRequest = state.workspaceSourcePatchRequest
                else { return }

                let calendarSourcePatchGenerator = calendarSourcePatchGenerator
                let database = database
                let sourceWorkspaceSummary = state.sourceWorkspaceSummary
                state.sourcePatchStatus = .generating(.proposeChanges)
                state.sourceProposal = nil
                store.addTask {
                    do {
                        let patch = try await calendarSourcePatchGenerator.generate(
                            sourcePatchRequest
                        )
                        let sourceFileAttributions = try await database.read { db in
                            try openMusicEventSourceFileAttributions(
                                patch: patch,
                                groups: sourceWorkspaceSummary.groups,
                                recordComparisons: sourceWorkspaceSummary.recordComparisons,
                                in: db
                            )
                        }
                        let preparation = SourceProposalPreparation(
                            patch: patch,
                            sourceFileAttributions: sourceFileAttributions,
                            sourceWorkspaceSummary: sourceWorkspaceSummary
                        )
                        try store.modify {
                            guard $0.sourceWorkspaceSummary == sourceWorkspaceSummary else {
                                $0.sourcePatchStatus = .needsGeneration
                                return
                            }
                            $0.sourcePatchStatus = .generated(preparation)
                            guard !patch.isEmpty,
                                  sourceWorkspaceSummary.totalCount > 0,
                                  case .available = sourceWorkspaceSummary.availability
                            else {
                                $0.sourceProposal = nil
                                return
                            }
                            $0.sourceProposal = SourceProposalFlow.State(
                                target: $0.target,
                                sourceChangeGroups: sourceWorkspaceSummary.groups,
                                sourceRecordComparisons: sourceWorkspaceSummary.recordComparisons,
                                sourceFileAttributions: sourceFileAttributions,
                                patch: patch
                            )
                        }
                    } catch {
                        try store.modify {
                            $0.sourcePatchStatus = .failed(
                                .proposeChanges,
                                SourcePatchGenerationFailure(error)
                            )
                            $0.sourceProposal = nil
                        }
                    }
                }

            case .resetChangesButtonTapped:
                guard state.canResetEdits else { return }
                let sourceWorkspaceSummary = state.sourceWorkspaceSummary
                let target = state.target
                let workspaceResetter = workspaceResetter
                state.resetStatus = .resetting
                store.addTask {
                    do {
                        try workspaceResetter.resetSourceChanges(target)
                        try store.modify {
                            $0.resetStatus = .idle
                            $0.sourcePatchStatus = .generated(
                                SourceProposalPreparation(
                                    patch: SourcePatch(),
                                    sourceWorkspaceSummary: sourceWorkspaceSummary
                                )
                            )
                            $0.sourceProposal = nil
                        }
                    } catch {
                        try store.modify {
                            $0.resetStatus = .failed(ResetEditsFailure(error))
                        }
                    }
                }

            case .sourceProposal:
                break
            }
        }
        .ifLet(\.sourceProposal, action: \.sourceProposal) {
            SourceProposalFlow()
        }
        .onEvent(SourceProposalDismissed.self) { _, state in
            state.sourceProposal = nil
            return .continue
        }
        .onEvent(AuthoringAccessRevoked.self) { _, state in
            state.sourceProposal = nil
        }
        .onChange(of: store.sourceWorkspaceSummary) { oldSummary, summary, state in
            guard oldSummary != summary else { return }
            switch state.sourcePatchStatus {
            case .generated, .generating:
                state.sourcePatchStatus = .needsGeneration
            case .failed, .needsGeneration, .notGenerated:
                break
            }
            state.sourceProposal = nil
        }
    }
}

extension WorkspaceChanges.State {
    static func authoringGrant() -> SharedReader<AuthoringGrant?> {
        @Dependency(\.authoringGrant) var authoringGrant
        return authoringGrant
    }

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

    public var workspaceSourcePatchRequest: OpenMusicEventCalendarSourcePatchRequest? {
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

    public var canGenerateSourcePatch: Bool {
        sourceBaselineID != nil && !sourcePatchStatus.isGenerating
    }

    public var canPublishSourceProposal: Bool {
        sourceKind == .tangled && sourceBaselineID != nil
    }

    public var canProposeChanges: Bool {
        sourceWorkspaceSummary.totalCount > 0
            && canPublishSourceProposal
            && authoringGrant?.role.canPropose == true
            && !sourcePatchStatus.isGenerating
            && sourceProposal == nil
    }

    public var canResetEdits: Bool {
        guard resetStatus != .resetting,
              sourceWorkspaceSummary.totalCount > 0,
              case .available = sourceWorkspaceSummary.availability
        else { return false }
        return true
    }
}

extension WorkspaceChanges.SourcePatchStatus {
    public var isGenerating: Bool {
        if case .generating = self { return true }
        return false
    }

    var preparation: WorkspaceChanges.SourceProposalPreparation? {
        guard case let .generated(preparation) = self else { return nil }
        return preparation
    }

    var proposeButtonTitle: String {
        switch self {
        case let .failed(purpose, _):
            purpose == .proposeChanges ? "Try Again" : "Propose"
        case .generating(.proposeChanges):
            "Preparing"
        case .generating(.checkChanges):
            "Checking"
        case .generated, .needsGeneration, .notGenerated:
            "Propose"
        }
    }

    var requiresAttention: Bool {
        switch self {
        case .failed, .generating:
            true
        case let .generated(preparation):
            preparation.patch.isEmpty
        case .needsGeneration, .notGenerated:
            false
        }
    }
}

public struct WorkspaceChangesView: View {
    @Bindable var store: StoreOf<WorkspaceChanges>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    @State var isResetConfirmationPresented = false

    public init(store: StoreOf<WorkspaceChanges>) {
        self.store = store
    }

    public var body: some View {
        List {
            SourceChangeSummarySection(
                groups: store.sourceWorkspaceSummary.groups,
                recordComparisons: store.sourceWorkspaceSummary.recordComparisons
            )

            if store.sourceWorkspaceSummary.totalCount == 0
                || !store.canPublishSourceProposal
                || store.sourcePatchStatus.requiresAttention
                || store.sourceProposal != nil
            {
                Section("Your changes") {
                    switch store.sourcePatchStatus {
                    case .generating(.proposeChanges):
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Preparing proposal")
                        }
                        .foregroundStyle(.secondary)

                    case .generating(.checkChanges):
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Checking changes")
                        }
                        .foregroundStyle(.secondary)

                    case let .failed(_, failure):
                        VStack(alignment: .leading, spacing: 4) {
                            Label(
                                "Changes could not be prepared",
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

                    case let .generated(preparation) where preparation.patch.isEmpty:
                        Text("No changes to send")
                            .foregroundStyle(.secondary)

                    case .generated:
                        if let status = store.sourceProposal?.status {
                            SourceProposalStatusView(status: status)
                        }

                    case .needsGeneration, .notGenerated:
                        if store.sourceWorkspaceSummary.totalCount == 0 {
                            Text("No local changes")
                                .foregroundStyle(.secondary)
                        } else if !store.canPublishSourceProposal {
                            Text("These changes stay on this device and won’t create a proposal.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if store.canResetEdits || store.resetStatus != .idle {
                Section {
                    switch store.resetStatus {
                    case .idle, .failed:
                        Button(role: .destructive) {
                            isResetConfirmationPresented = true
                        } label: {
                            Label("Reset changes", systemImage: "arrow.counterclockwise")
                        }
                        .disabled(!store.canResetEdits)

                    case .resetting:
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Resetting edits")
                        }
                    }

                    if case let .failed(failure) = store.resetStatus {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Edits could not be reset")
                            if showsTechnicalDetails {
                                Text(failure.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .selectableText()
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $store.scope(\.sourceProposal, action: \.sourceProposal)) {
            proposalStore in
            SourceProposalComposerView(store: proposalStore)
        }
        .alert(
            "Reset local changes?",
            isPresented: $isResetConfirmationPresented
        ) {
            Button("Reset changes", role: .destructive) {
                store.send(.resetChangesButtonTapped)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will discard all local changes in this workspace.")
        }
    }
}
