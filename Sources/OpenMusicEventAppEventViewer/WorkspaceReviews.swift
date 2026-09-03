import ATProto
import BlueskyActorCache
import ComposableArchitecture2
import ComposableWorkspace
import Dependencies
import ErrorHandling
import Foundation
import IssueReporting
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventSourceEditing
import SQLiteData
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
        case loaded([OME.WorkspaceProposal.ListItem])
        case loading
        case notLoaded
    }

    public struct State {
        public init(
            workspace: SourceWorkspace,
            authoringGrant: AuthoringGrant? = nil
        ) {
            self.workspace = workspace
            self.authoringGrant = authoringGrant
            self._cachedActorIdentities = Fetch(
                wrappedValue: CachedActorIdentities(),
                CachedActorIdentitiesRequest()
            )
            self._publicationReceipts = Fetch(
                wrappedValue: [],
                SourceWorkspaceProposalReceiptsRequest(workspaceID: workspace.id)
            )
        }

        public let workspace: SourceWorkspace
        public var authoringGrant: AuthoringGrant?
        @DebugSnapshotIgnored
        @Fetch public var cachedActorIdentities: CachedActorIdentities
        @Fetch public var publicationReceipts: [WorkspaceProposal]
        public var destination: Destination.State?
        public var locallyRemovedProposalURIs: Set<String> = []
        public var status: Status = .notLoaded

        public var proposalAuthorReferences: [String] {
            Array(Set(proposals.map { $0.authorDID.description })).sorted()
        }

        public var proposals: [OME.WorkspaceProposal.ListItem] {
            guard case let .loaded(proposals) = status else { return [] }
            let pendingURIs = Set(publicationReceipts.map { $0.id.rawValue })
            return proposals.filter {
                !pendingURIs.contains($0.uri.description)
                    && !locallyRemovedProposalURIs.contains($0.uri.description)
            }
        }

        public var pendingProjectionReceipts: [WorkspaceProposal] {
            publicationReceipts.filter {
                !locallyRemovedProposalURIs.contains($0.id.rawValue)
            }
        }

        public var openProposalCount: Int? {
            guard case .loaded = status else { return nil }
            return proposals.count + pendingProjectionReceipts.count
        }

        public mutating func open(_ proposal: WorkspaceProposal) {
            guard let uri = ATProto.URI(proposal.id.rawValue) else { return }
            destination = .reviewDetail(
                WorkspaceReviewDetail.State(
                    workspace: workspace,
                    proposalURI: uri,
                    expectedProposal: proposal,
                    authoringGrant: authoringGrant
                )
            )
        }

        public mutating func open(_ proposal: OME.WorkspaceProposal.ListItem) {
            destination = .reviewDetail(
                WorkspaceReviewDetail.State(
                    workspace: workspace,
                    proposalURI: proposal.uri,
                    authoringGrant: authoringGrant
                )
            )
        }

        mutating func remove(_ proposalURI: ATProto.URI) {
            locallyRemovedProposalURIs.insert(proposalURI.description)
            if case let .loaded(proposals) = status {
                status = .loaded(proposals.filter { $0.uri != proposalURI })
            }
            destination = nil
        }
    }

    public enum Action {
        case destination(Destination.Action)
        case pendingProposalButtonTapped(WorkspaceProposal)
        case proposalButtonTapped(OME.WorkspaceProposal.ListItem)
        case didPullToRefresh
    }

    @Feature
    public enum Destination {
        case reviewDetail(WorkspaceReviewDetail)
    }

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.workspaceProposalClient) var proposalClient

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .destination:
                break

            case let .pendingProposalButtonTapped(proposal):
                state.open(proposal)

            case let .proposalButtonTapped(proposal):
                guard state.proposals.contains(where: { $0.uri == proposal.uri })
                else { return }
                state.open(proposal)

            case .didPullToRefresh:
                loadProposals(state: &state)
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .onEvent(WorkspaceProposalRemoved.self) { proposalURI, state in
            state.remove(proposalURI)
            return .continue
        }
        .onMount { state in
            loadProposals(state: &state)
        }
        .onChange(of: store.proposalAuthorReferences, initial: true) { _, authors, _ in
            guard !authors.isEmpty else { return }
            let blueskyActorProfileCache = blueskyActorProfileCache
            store.addTask {
                for author in authors {
                    do {
                        _ = try await blueskyActorProfileCache.refreshProfileIfNeeded(
                            author,
                            24 * 60 * 60,
                            15 * 60
                        )
                    } catch is CancellationError {
                        return
                    } catch {
                        continue
                    }
                }
            }
        }
    }

    func loadProposals(state: inout State) {
        guard state.status != .loading else { return }
        let request: OpenMusicEventWorkspaceProposalListRequest
        do {
            request = try OpenMusicEventWorkspaceProposalListRequest(workspace: state.workspace)
        } catch {
            state.status = .failed(String(describing: error))
            reportIssue(error)
            return
        }
        let receipts = state.publicationReceipts
        let receiptStore = SourceWorkspaceProposalReceiptStore(database: database)
        let proposalClient = proposalClient
        state.status = .loading
        store.addTask {
            do {
                let proposals = try await proposalClient.list(request)
                try WorkspaceProposalObservation.validate(
                    proposals,
                    request: request
                )
                var acknowledgedProposalIDs: [WorkspaceProposalID] = []
                for receipt in receipts {
                    guard let uri = ATProto.URI(receipt.id.rawValue) else {
                        reportIssue(WorkspaceProposalObservation.Error.invalidURI(receipt.id.rawValue))
                        continue
                    }
                    do {
                        let detail = try await proposalClient.detail(uri)
                        switch try WorkspaceProposalObservation.observe(
                            detail,
                            proposalURI: uri,
                            request: request,
                            expectedProposal: receipt
                        ) {
                        case .available, .deleted:
                            acknowledgedProposalIDs.append(receipt.id)
                        case .pending:
                            break
                        }
                    } catch WorkspaceProposalClientError.proposalNotFound {
                        continue
                    } catch {
                        reportIssue(error)
                    }
                }
                try store.modify {
                    let removed = $0.locallyRemovedProposalURIs
                    $0.status = .loaded(
                        proposals
                            .filter { !removed.contains($0.uri.description) }
                            .sorted { $0.updatedAt > $1.updatedAt }
                    )
                }
                do {
                    try await receiptStore.acknowledge(acknowledgedProposalIDs)
                } catch is CancellationError {
                    return
                } catch {
                    reportIssue(error)
                }
            } catch {
                try store.modify { $0.status = .failed(String(describing: error)) }
                reportIssue(error)
            }
        }
    }
}

enum WorkspaceProposalRemoved: FeatureEventKey {
    typealias Value = ATProto.URI
}

@Feature
public struct WorkspaceReviewDetail {
    public init() {}

    public enum Status: Equatable, Sendable {
        case failed(String)
        case loaded(OME.WorkspaceProposal.Detail)
        case loading
        case pending(OME.WorkspaceProposal.Detail?)
        case notLoaded
        case unavailable
    }

    public enum Operation: Equatable, Sendable {
        case closing
        case idle
        case merging

        public var isRunning: Bool {
            switch self {
            case .closing, .merging: true
            case .idle: false
            }
        }
    }

    public struct State {
        public init(
            workspace: SourceWorkspace,
            proposalURI: ATProto.URI,
            expectedProposal: WorkspaceProposal? = nil,
            authoringGrant: AuthoringGrant? = nil
        ) {
            self.workspace = workspace
            self.proposalURI = proposalURI
            self.expectedProposal = expectedProposal
            self.authoringGrant = authoringGrant
            self._cachedActorIdentities = Fetch(
                wrappedValue: CachedActorIdentities(),
                CachedActorIdentitiesRequest()
            )
        }

        public let workspace: SourceWorkspace
        public let proposalURI: ATProto.URI
        public let expectedProposal: WorkspaceProposal?
        public var authoringGrant: AuthoringGrant?
        @DebugSnapshotIgnored
        @Fetch public var cachedActorIdentities: CachedActorIdentities
        public var operation: Operation = .idle
        public var status: Status = .notLoaded

        public var proposal: OME.WorkspaceProposal.Detail? {
            switch status {
            case let .loaded(proposal), let .pending(.some(proposal)):
                proposal
            case .failed, .loading, .notLoaded, .pending(nil), .unavailable:
                nil
            }
        }

        public var validatedProposal: OME.WorkspaceProposal.Detail? {
            guard case let .loaded(proposal) = status else { return nil }
            return proposal
        }

        public var authorIdentity: ActorIdentity? {
            proposal.flatMap { cachedActorIdentities[$0.authorDID.description] }
        }

        public var proposalAuthorReference: String? {
            proposal?.authorDID.description
        }

        public var canClose: Bool {
            validatedProposal != nil && authoringGrantForWorkspace != nil
        }

        public var canMergeProposals: Bool {
            authoringGrantForWorkspace?.role.canMerge == true
        }

        public var canMerge: Bool {
            validatedProposal?.renderStatus == .ready
                && validatedProposal?.presentation != nil
                && canMergeProposals
                && targetBranch != nil
        }

        public var targetBranch: WorkspaceBranch? {
            guard let branch = validatedProposal?.targetBranch else { return nil }
            let value = SourceWorkspace.normalizedBranch(branch)
            return value.isEmpty ? nil : WorkspaceBranch(rawValue: value)
        }

        private var authoringGrantForWorkspace: AuthoringGrant? {
            guard let authoringGrant,
                  authoringGrant.workspaceID == workspace.id
            else { return nil }
            return authoringGrant
        }
    }

    public enum Action {
        case closeButtonTapped
        case mergeButtonTapped
        case retryButtonTapped
    }

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
    @Dependency(\.continuousClock) var clock
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.workspaceProposalClient) var proposalClient
    @Dependency(\.workspaceProposalProjectionRetryDelays) var projectionRetryDelays

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .closeButtonTapped:
                guard state.canClose,
                      let proposal = state.validatedProposal,
                      !state.operation.isRunning
                else { return }
                let proposalClient = proposalClient
                state.operation = .closing
                store.addTask {
                    let result: Void? = await store.withErrorHandling(
                        fallbackMessage: .workspaceReviewCloseFailed,
                        operation: .workspaceReviewClose
                    ) {
                        try await proposalClient.close(proposal.uri)
                    } cleanup: {
                        $0.operation = .idle
                    }
                    guard result != nil else { return }
                    try store.post(key: WorkspaceProposalRemoved.self, value: proposal.uri)
                }

            case .mergeButtonTapped:
                guard state.canMerge,
                      let proposal = state.validatedProposal,
                      !state.operation.isRunning
                else { return }
                let request = OpenMusicEventWorkspaceProposalMergeRequest(
                    target: OpenMusicEventSourceTarget(workspace: state.workspace),
                    proposal: proposal
                )
                let proposalClient = proposalClient
                state.operation = .merging
                store.addTask {
                    let result: Void? = await store.withErrorHandling(
                        fallbackMessage: .workspaceReviewMergeFailed,
                        operation: .workspaceReviewMerge
                    ) {
                        try await proposalClient.merge(request)
                    } cleanup: {
                        $0.operation = .idle
                    }
                    guard result != nil else { return }
                    do {
                        let selection = try store.post(
                            key: WorkspaceProposalMerged.self,
                            value: WorkspaceProposalID(rawValue: proposal.uri.description)
                        )
                        await selection?.value
                        try store.post(
                            key: WorkspaceProposalRemoved.self,
                            value: proposal.uri
                        )
                    } catch {
                        reportIssue(error)
                    }
                }

            case .retryButtonTapped:
                loadProposal(state: &state)
            }
        }
        .onMount { state in
            loadProposal(state: &state)
        }
        .onChange(of: store.proposalAuthorReference, initial: true) { _, author, _ in
            guard let author else { return }
            let blueskyActorProfileCache = blueskyActorProfileCache
            store.addTask {
                do {
                    _ = try await blueskyActorProfileCache.refreshProfileIfNeeded(
                        author,
                        24 * 60 * 60,
                        15 * 60
                    )
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
    }

    func loadProposal(state: inout State) {
        guard state.status != .loading else { return }
        let request: OpenMusicEventWorkspaceProposalListRequest
        do {
            request = try OpenMusicEventWorkspaceProposalListRequest(workspace: state.workspace)
        } catch {
            state.status = .failed(String(describing: error))
            reportIssue(error)
            return
        }
        let expectedProposal = state.expectedProposal
        let proposalURI = state.proposalURI
        let proposalClient = proposalClient
        let receiptStore = SourceWorkspaceProposalReceiptStore(database: database)
        let clock = clock
        let projectionRetryDelays = projectionRetryDelays
        state.status = .loading
        store.addTask {
            var retries = projectionRetryDelays.makeIterator()
            while !Task.isCancelled {
                do {
                    let detail = try await proposalClient.detail(proposalURI)
                    switch try WorkspaceProposalObservation.observe(
                        detail,
                        proposalURI: proposalURI,
                        request: request,
                        expectedProposal: expectedProposal
                    ) {
                    case .deleted:
                        try store.modify { $0.status = .unavailable }
                        if let expectedProposal {
                            do {
                                try await receiptStore.acknowledge([expectedProposal.id])
                            } catch is CancellationError {
                                return
                            } catch {
                                reportIssue(error)
                            }
                        }
                        return

                    case let .pending(detail):
                        try store.modify { $0.status = .pending(detail) }

                    case let .available(detail):
                        try store.modify { $0.status = .loaded(detail) }
                        guard expectedProposal == nil || detail.renderStatus != .pending else {
                            break
                        }
                        if let expectedProposal {
                            do {
                                try await receiptStore.acknowledge([expectedProposal.id])
                            } catch is CancellationError {
                                return
                            } catch {
                                reportIssue(error)
                            }
                        }
                        return
                    }
                } catch WorkspaceProposalClientError.proposalNotFound {
                    try store.modify { $0.status = .pending(nil) }
                } catch is CancellationError {
                    return
                } catch {
                    try store.modify { $0.status = .failed(String(describing: error)) }
                    reportIssue(error)
                    return
                }

                guard let retryDelay = retries.next() else { return }
                do { try await clock.sleep(for: retryDelay) } catch { return }
            }
        }
    }
}

extension DependencyValues {
    var workspaceProposalProjectionRetryDelays: [Duration] {
        get { self[WorkspaceProposalProjectionRetryDelaysKey.self] }
        set { self[WorkspaceProposalProjectionRetryDelaysKey.self] = newValue }
    }
}

private enum WorkspaceProposalProjectionRetryDelaysKey: DependencyKey {
    static let liveValue: [Duration] = [
        .seconds(1),
        .seconds(2),
        .seconds(4),
        .seconds(8),
        .seconds(8),
    ]
    static let testValue: [Duration] = []
}

public struct WorkspaceReviewsView: View {
    @Bindable var store: StoreOf<WorkspaceReviews>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    public init(store: StoreOf<WorkspaceReviews>) {
        self.store = store
    }

    public var body: some View {
        List {
            if showsTechnicalDetails {
                Section("Source details") {
                    WorkspaceTechnicalValueView(
                        label: "Repository",
                        value: store.workspace.repository
                    )
                    WorkspaceTechnicalValueView(
                        label: "Default branch",
                        value: store.workspace.defaultBranch
                    )
                    WorkspaceTechnicalValueView(
                        label: "Organization",
                        value: store.workspace.organizerID.description
                    )
                }
            }

            Section("Open proposals") {
                ForEach(store.pendingProjectionReceipts, id: \.id) { proposal in
                    Button {
                        store.send(.pendingProposalButtonTapped(proposal))
                    } label: {
                        HStack(spacing: 10) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Updating proposal")
                                Text("Waiting for its server projection.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if showsTechnicalDetails {
                                    Text(proposal.id.rawValue)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .selectableText()
                                }
                            }
                            Spacer()
                            MappedSystemImage(systemName: "chevron.forward")
                                .frame(width: 8, height: 12)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .portableAccessibilityElement()
                    .accessibilityIdentifier("workspace.proposals.pending")
                }

                switch store.status {
                case .loading:
                    ProgressView("Loading proposals")

                case let .failed(message):
                    Text(showsTechnicalDetails ? message : "Proposals could not be loaded")
                        .foregroundStyle(.secondary)

                case .loaded:
                    if store.proposals.isEmpty && store.pendingProjectionReceipts.isEmpty {
                        Text("No open proposals")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.proposals) { proposal in
                        Button {
                            store.send(.proposalButtonTapped(proposal))
                        } label: {
                            WorkspaceProposalRow(
                                proposal: proposal,
                                authorIdentity: store.cachedActorIdentities[
                                    proposal.authorDID.description
                                ]
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "workspace.proposal.row.\(proposal.uri.description)"
                        )
                    }

                case .notLoaded:
                    Text("Proposals have not been loaded")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Proposals")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(
            item: $store.scope(\.destination, action: \.destination).reviewDetail
        ) { detailStore in
            WorkspaceReviewDetailView(store: detailStore)
        }
        .refreshable {
            await store.send(.didPullToRefresh)?.value
        }
    }
}

struct WorkspaceProposalRow: View {
    let proposal: OME.WorkspaceProposal.ListItem
    let authorIdentity: ActorIdentity?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(proposal.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(proposal.status.rawValue.workspaceProposalStateTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(authorTitle)
                .font(.subheadline)
                .foregroundStyle(.primary)

            HStack(alignment: .firstTextBaseline) {
                Text(proposal.updatedAt.workspaceProposalDateTitle)
                Spacer()
                if proposal.renderStatus != .ready {
                    Text("Preparing changes")
                }
                MappedSystemImage(systemName: "chevron.forward")
                    .frame(width: 8, height: 12)
                    .accessibilityHidden(true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        #if !SKIP
        .contentShape(Rectangle())
        #endif
    }

    var authorTitle: String {
        if let authorIdentity {
            return authorIdentity.displayTitle(showsTechnicalDetails: false)
        }
        return proposal.authorDID.description.workspaceProposalFriendlyAuthorTitle
    }
}

public struct WorkspaceReviewDetailView: View {
    let store: StoreOf<WorkspaceReviewDetail>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    public init(store: StoreOf<WorkspaceReviewDetail>) {
        self.store = store
    }

    public var body: some View {
        List {
            if let proposal = store.proposal {
                proposalSection(proposal)
                changesSection
                if store.validatedProposal != nil {
                    reviewStatusSection
                }
                if showsTechnicalDetails {
                    technicalSection(proposal)
                }
            } else {
                loadStateSection
            }
        }
        .navigationTitle(store.proposal?.title ?? "Proposal")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    var loadStateSection: some View {
        switch store.status {
        case .failed(let message):
            Section("Proposal") {
                Text("Proposal details could not be loaded")
                if showsTechnicalDetails {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .selectableText()
                }
                Button("Try Again") {
                    store.send(.retryButtonTapped)
                }
            }

        case .loading:
            Section("Proposal") {
                ProgressView("Loading proposal")
            }

        case .pending:
            Section("Proposal status") {
                ProgressView("Waiting for the server projection")
                Text("The proposal was published successfully. Its details are still being prepared.")
                    .foregroundStyle(.secondary)
            }

        case .unavailable:
            Section("Proposal") {
                Text("This proposal is no longer available.")
                    .foregroundStyle(.secondary)
            }

        case .notLoaded:
            Section("Proposal") {
                Button("Load proposal") {
                    store.send(.retryButtonTapped)
                }
            }

        case .loaded:
            EmptyView()
        }
    }

    func proposalSection(_ proposal: OME.WorkspaceProposal.Detail) -> some View {
        let statusTitle = proposal.status.rawValue.workspaceProposalStateTitle
        let statusColor = proposalStatusColor(proposal.status)
        let authorTitle = store.authorIdentity?.displayTitle(showsTechnicalDetails: false)
            ?? proposal.authorDID.description.workspaceProposalFriendlyAuthorTitle
        let bylineTitle = proposal.createdAt.map {
            "\(authorTitle) · \($0.workspaceProposalDateTitle)"
        } ?? authorTitle
        let bylineAccessibilityLabel = proposal.createdAt.map {
            "Submitted by \(authorTitle), \($0.workspaceProposalDateTitle)"
        } ?? "Submitted by \(authorTitle)"

        return Section {
            if let title = proposal.title {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text(verbatim: statusTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(statusColor.opacity(0.14), in: Capsule())

                    if let sourceBranch = proposal.source?.branch,
                       !sourceBranch.isEmpty,
                       let targetBranch = proposal.targetBranch,
                       !targetBranch.isEmpty {
                        Text(verbatim: targetBranch)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Color.accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 6)
                            )

                        Text(verbatim: "←")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        Text(verbatim: sourceBranch)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Color.accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                }
            }
            .portableAccessibilityElementIgnoringChildren()
            .accessibilityLabel(
                Text(verbatim: proposalRelationshipAccessibilityLabel(proposal))
            )

            HStack(spacing: 10) {
                if let authorIdentity = store.authorIdentity {
                    ContributorActorAvatar(identity: authorIdentity)
                }

                Text(verbatim: bylineTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .portableAccessibilityElementIgnoringChildren()
            .accessibilityLabel(Text(verbatim: bylineAccessibilityLabel))

            if let body = proposal.body, !body.isEmpty {
                Text(body)
                    .fixedSize(horizontal: false, vertical: true)
                    .selectableText()
            }
        }
    }

    func proposalStatusColor(_ status: OME.WorkspaceProposal.Status) -> Color {
        switch status {
        case .open:
            .green
        case .closed:
            .red
        case .merged:
            .purple
        default:
            .secondary
        }
    }

    func proposalRelationshipAccessibilityLabel(
        _ proposal: OME.WorkspaceProposal.Detail
    ) -> String {
        let status = proposal.status.rawValue.workspaceProposalStateTitle
        guard let sourceBranch = proposal.source?.branch,
              !sourceBranch.isEmpty,
              let targetBranch = proposal.targetBranch,
              !targetBranch.isEmpty
        else { return "Status: \(status)" }

        return "Status: \(status). Changes from \(sourceBranch) into \(targetBranch)."
    }

    @ViewBuilder
    var reviewStatusSection: some View {
        switch store.operation {
        case .closing:
            Section("Status") {
                ProgressView("Closing proposal")
                    .accessibilityIdentifier("workspace.proposal.close.progress")
            }
        case .merging:
            Section("Status") {
                ProgressView("Merging proposal")
                    .accessibilityIdentifier("workspace.proposal.merge.progress")
            }
        case .idle:
            Section("Status") {
                if store.canMergeProposals, store.targetBranch != nil {
                    Button("Merge proposal") {
                        store.send(.mergeButtonTapped)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.canMerge)
                    .accessibilityIdentifier("workspace.proposal.merge")
                }

                if store.canClose {
                    Button("Close proposal") {
                        store.send(.closeButtonTapped)
                    }
                    .accessibilityIdentifier("workspace.proposal.close")
                }

                if !store.canClose && !store.canMergeProposals {
                    Text("You can review this proposal, but you do not have permission to change its state.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    var changesSection: some View {
        switch store.status {
        case let .loaded(proposal):
            switch proposal.renderStatus {
            case .awaitingInput:
                Section("Changes") {
                    Text("A change preview is not available for this proposal.")
                        .foregroundStyle(.secondary)
                }

            case .pending:
                Section("Changes") {
                    ProgressView("Preparing proposal changes")
                }

            case .ready:
                if let presentation = proposal.presentation {
                    SourceChangePresentationSection(
                        presentation: presentation,
                        emptyMessage: "No changes",
                        title: "Changes"
                    )
                }
            }

        case .pending:
            Section("Changes") {
                ProgressView("Preparing proposal changes")
            }

        case .failed, .loading, .notLoaded, .unavailable:
            EmptyView()
        }
    }

    @ViewBuilder
    func technicalSection(_ proposal: OME.WorkspaceProposal.Detail) -> some View {
        Section("Technical details") {
            WorkspaceTechnicalValueView(
                label: "Proposal URI",
                value: proposal.uri.description
            )
            WorkspaceTechnicalValueView(
                label: "Author ID",
                value: proposal.authorDID.description
            )
            if let canonicalSource = proposal.canonicalSource {
                WorkspaceTechnicalValueView(
                    label: "Canonical source",
                    value: canonicalSource.description
                )
            }
            if let targetRepositoryDID = proposal.targetRepositoryDID {
                WorkspaceTechnicalValueView(
                    label: "Target repository ID",
                    value: targetRepositoryDID.description
                )
            }
            if let source = proposal.source {
                if let sourceRepositoryDID = source.repositoryDID {
                    WorkspaceTechnicalValueView(
                        label: "Source repository ID",
                        value: sourceRepositoryDID.description
                    )
                }
                if let revision = source.revision {
                    WorkspaceTechnicalValueView(label: "Source revision", value: revision)
                }
            }
            WorkspaceTechnicalValueView(
                label: "Record availability",
                value: proposal.recordAvailability.rawValue
            )
            WorkspaceTechnicalValueView(
                label: "Render status",
                value: proposal.renderStatus.rawValue
            )
            if let recordCID = proposal.recordCID {
                WorkspaceTechnicalValueView(label: "Record CID", value: recordCID.rawValue)
            }
            if let pageURL = proposal.pageURL {
                Link("Open proposal page", destination: pageURL)
            }
            if let patchURL = proposal.patchURL {
                Link("Open patch", destination: patchURL)
            }
            if !sourceFiles(in: proposal).isEmpty {
                PortableDisclosureGroup("Source files") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sourceFiles(in: proposal), id: \.self) { file in
                            Text(file)
                                .monospaced()
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    func sourceFiles(in proposal: OME.WorkspaceProposal.Detail) -> [String] {
        Array(Set(proposal.presentation?.groups.flatMap(\.records).flatMap(\.sourceFiles) ?? []))
            .sorted()
    }
}

extension UserFacingText {
    static let workspaceReviewCloseFailed = Self(
        "The proposal could not be closed.",
        fallback: "The proposal could not be closed."
    )
    static let workspaceReviewMergeFailed = Self(
        "The proposal could not be merged.",
        fallback: "The proposal could not be merged."
    )
}

extension ErrorOperation {
    static let workspaceReviewClose = Self("workspace.review.close")
    static let workspaceReviewMerge = Self("workspace.review.merge")
}

private extension String {
    var workspaceProposalFriendlyAuthorTitle: String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "Profile unavailable" }
        if value.hasPrefix("did:") { return "Profile unavailable" }
        return value.hasPrefix("@") ? value : "@\(value)"
    }

    var workspaceProposalStateTitle: String {
        let component = split(separator: ".").last.map(String.init) ?? self
        let value = component.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        guard let first = value.first else { return "Unknown" }
        return first.uppercased() + value.dropFirst()
    }
}

private extension Date {
    var workspaceProposalDateTitle: String {
        DateFormatter.localizedString(
            from: self,
            dateStyle: .medium,
            timeStyle: .short
        )
    }
}
