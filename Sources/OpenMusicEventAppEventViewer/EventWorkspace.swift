import ComposableArchitecture2
import Foundation
import GRDB
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
        public var isResettingEdits = false
        public var resetEditsFailure: ResetEditsFailure?
        public var sourcePatchStatus: SourcePatchStatus = .notGenerated
        public var sourceProposalStatus: SourceProposalStatus = .idle
        @DebugSnapshotIgnored
        public var sourceProposal: SourceProposalFlow.State?
        public var tangledPullReviewStatus: TangledPullReviewStatus = .notLoaded
        @FetchOne public var sourceProvenance: EventSourceProvenanceRecord?

        public var changeCount: Int? {
            workspaceSummary.badgeCount
        }

        public var sourceChangesScope: SourceChangesScope {
            .event(eventID)
        }
    }

    public enum Action {
        case generateSourcePatchButtonTapped
        case proposeChangeButtonTapped
        case refreshTangledPullReviewsButtonTapped
        case refreshSourceButtonTapped
        case resetEditsButtonTapped
        case resetEditsResponse(Result<ResetEditsSuccess, ResetEditsFailure>)
        case sourcePatchGenerationResponse(Result<SourcePatch, SourcePatchGenerationFailure>)
        case sourcePatchInvalidationReceived(SourcePatchInvalidation)
        case sourceProposal(SourceProposalFlow.Action)
        case tangledPullReviewsResponse(Result<[TangledPullReview], TangledPullReviewFailure>)
    }

    @Dependency(\.eventWorkspaceResetter) var workspaceResetter
    @Dependency(SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self) var sourcePatchGenerator
    @Dependency(\.sourcePatchInvalidations) var sourcePatchInvalidations
    @Dependency(\.tangledPullReviewClient) var tangledPullReviewClient
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

            switch action {
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
                state.resetEditsFailure = nil
                state.sourcePatchStatus = .generated(SourcePatch())
                state.sourceProposal = nil
                state.sourceProposalStatus = .idle

            case let .resetEditsResponse(.failure(failure)):
                state.isResettingEdits = false
                state.resetEditsFailure = failure

            case .sourceProposal(.delegate(.dismissed)):
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
                    generateSourcePatch(eventID: state.eventID, state: &state)
                    return
                }
                guard !patch.isEmpty else { return }
                state.updateSourceProposal(for: patch)

            case let .sourcePatchGenerationResponse(.success(patch)):
                state.sourcePatchStatus = .generated(patch)
                state.updateSourceProposal(for: patch)

            case let .sourcePatchGenerationResponse(.failure(failure)):
                state.sourcePatchStatus = .failed(failure)

            case let .sourcePatchInvalidationReceived(invalidation):
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

            case let .tangledPullReviewsResponse(.success(reviews)):
                state.tangledPullReviewStatus = .loaded(reviews)

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

    public init(store: StoreOf<EventWorkspace>) {
        self.store = store
    }

    public var body: some View {
        List {
            workspaceSection
            sourceSection

            switch store.workspaceSummary.availability {
            case .available:
                currentEditsSections
                sourceDiffSections
                sourceProposalSection
                tangledPullReviewsSection
                ExistingProposalsSection(state: .loaded([]))
                resetEditsSection

            case .workspaceNeedsPreparation:
                WorkspaceUnavailableSection(
                    title: "Workspace Needs Preparation",
                    message: "Prepare this workspace before reviewing source changes."
                )

            case .notInWorkspace:
                WorkspaceUnavailableSection(
                    title: "Not in a Workspace",
                    message: "Move this event into a workspace before proposing source changes."
                )

            case let .unavailable(reason):
                Section("Workspace") {
                    SourceChangeUnavailableView(reason: reason)
                }
            }
        }
        .navigationTitle("Workspace")
    }

    @ViewBuilder
    private var workspaceSection: some View {
        Section("Workspace") {
            HStack {
                Text("Current Edits")
                Spacer()
                Text(store.workspaceSummary.totalCount, format: .number)
                    .font(.headline)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var currentEditsSections: some View {
        if store.workspaceSummary.totalCount == 0 {
            Section("Current Edits") {
                Text("No current edits")
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(store.workspaceSummary.groups.filter { !$0.records.isEmpty }) { group in
                SourceChangeGroupSections(group: group)
            }
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
    private var sourceProposalSection: some View {
        if let sourceProposalStore = store.scope(\.sourceProposal, action: \.sourceProposal) {
            SourceProposalDraftSection(store: sourceProposalStore)
        }
    }

    @ViewBuilder
    private var tangledPullReviewsSection: some View {
        if store.sourceProvenance?.sourceKind == .tangled {
            Section("Tangled Reviews") {
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
                            NavigationLink {
                                TangledPullReviewDetailView(review: review)
                            } label: {
                                TangledPullReviewRow(review: review)
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

struct TangledPullReviewRow: View {
    let review: TangledPullReview

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
        }
        .padding(.vertical, 4)
    }
}

struct TangledPullReviewDetailView: View {
    let review: TangledPullReview

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
    let sourcePatchStatus: EventWorkspace.SourcePatchStatus
    let sourceProposalStatus: EventWorkspace.SourceProposalStatus
    let sourceSection: SourceSection

    public init(
        availability: SourceChangesAvailability,
        groups: [SourceChangeGroup],
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
                    SourceProposalSummarySections(groups: groups)
                }
            }

        case .workspaceNeedsPreparation:
            ContentUnavailableView(
                "Workspace Needs Preparation",
                systemImage: "externaldrive.badge.questionmark"
            )

        case .notInWorkspace:
            ContentUnavailableView(
                "Not in a Workspace",
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
                SourceProposalSummarySections(groups: store.sourceChangeGroups)

                Section {
                    DisclosureGroup("Advanced") {
                        ForEach(store.patch.fileChanges) { change in
                            SourcePatchFileChangeRow(change: change)
                        }
                    }
                }
            }
            .navigationTitle("Propose Change")
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
        Section("Changed Files") {
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
    let state: ExistingProposalsState

    var body: some View {
        Section("Other Proposed Changes") {
            switch state {
            case let .failed(message):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Other proposed changes couldn't be loaded")
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

            case let .loaded(proposals):
                if proposals.isEmpty {
                    Text("No other proposed changes")
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
                Text("Other proposed changes are unavailable.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

public struct SourceProposalSummarySections: View {
    let groups: [SourceChangeGroup]

    public init(groups: [SourceChangeGroup]) {
        self.groups = groups
    }

    init(summary: EventWorkspaceSummary) {
        self.groups = summary.groups
    }

    public var body: some View {
        if groups.contains(where: { !$0.records.isEmpty }) {
            ForEach(groups.filter { !$0.records.isEmpty }) { group in
                SourceChangeGroupSections(group: group)
            }
        } else {
            Section {
                Label("No edit summary available", systemImage: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
            }
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
    mutating func updateSourceProposal(for patch: SourcePatch) {
        guard !patch.isEmpty, canReviewSourceProposal else {
            sourceProposal = nil
            sourceProposalStatus = .idle
            return
        }

        let existingDescription = sourceProposal?.sourceProposalDescription
        let existingTitle = sourceProposal?.sourceProposalTitle
        var sourceProposal = SourceProposalFlow.State(
            eventID: eventID,
            workspaceSummary: workspaceSummary,
            patch: patch
        )
        if let existingTitle {
            sourceProposal.sourceProposalTitle = existingTitle
        }
        if let existingDescription {
            sourceProposal.sourceProposalDescription = existingDescription
        }

        self.sourceProposal = sourceProposal
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
}

private extension EventWorkspace.SourcePatchStatus {
    var reviewButtonTitle: String {
        switch self {
        case .failed:
            "Try Again"
        case .generating:
            "Checking Changes"
        case .generated:
            "Review Changes"
        default:
            "Review Changes"
        }
    }

    var isGenerating: Bool {
        self == .generating
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
            "Review changes before creating a proposal"
        case .workspace:
            "Review unpublished changes"
        }
    }

    var readyTitle: String {
        switch self {
        case .proposal:
            "Ready to propose"
        case .workspace:
            "Changes ready"
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

    var body: some View {
        ForEach(kinds, id: \.self) { kind in
            SourceChangeKindSection(
                title: "\(kind.title) \(group.displayName)",
                records: records(for: kind)
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
    let records: [SourceRecordChange]

    var body: some View {
        Section(title) {
            ForEach(records) { record in
                SourceRecordChangeRow(record: record)
            }
        }
    }
}

struct SourceRecordChangeRow: View {
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
}

private extension SourceRecordChange {
    var primaryKeySummary: String {
        primaryKeyValues
            .map { "\($0.columnName)=\($0.value.sourceDisplayValue)" }
            .joined(separator: ", ")
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
