import ATProto
import ComposableArchitecture2
import Foundation
import OpenMusicEventComponents
import SwiftUI

@Feature
public struct ContributorRelationshipPicker {
    public init() {}

    @StoreTaskID var actorSearchTask

    public struct ContributorOption: Equatable, Sendable {
        init(profile: ContributorProfile) {
            self.id = profile.contributorID
            self.name = profile.name
            self.subtitle = profile.subtitle
        }

        var id: OMERecord.ID<OMERecord.Contributor>
        var name: String
        var subtitle: String?
        var rawID: String { id.rawValue.rawValue }

        func matches(_ query: String) -> Bool {
            guard !query.isEmpty else { return true }
            return name.localizedStandardContains(query)
                || subtitle?.localizedStandardContains(query) == true
                || rawID.localizedStandardContains(query) == true
        }
    }

    public struct SelectedActorIdentity: Equatable, Sendable {
        public init(_ identity: ActorIdentity) {
            self.avatar = identity.avatar
            self.did = identity.did
            self.displayName = identity.displayName?.trimmedForContributorPicker.nilIfEmpty
            self.handle = identity.handle?.rawValue
        }

        public var avatar: URL?
        public var did: DID
        public var displayName: String?
        public var handle: String?

        public var actor: OMERecord.Contributor.Actor? {
            OMERecord.Contributor.Actor(did.description)
        }

        public var contributorName: String {
            displayName?.nilIfEmpty
                ?? handle?.nilIfEmpty
                ?? "Account"
        }

        public var subtitle: String? {
            handle.map { "@\($0)" }
        }
    }

    public enum Selection: Equatable, Sendable {
        case none
        case existingContributor(OMERecord.ID<OMERecord.Contributor>)
        case identityOnly(actor: OMERecord.Contributor.Actor, displayTitle: String?)
        case newContributor(name: String)
        case newContributorFromIdentity(SelectedActorIdentity)
        case performanceDisplayName(name: String)

        public var isNone: Bool {
            guard case .none = self else { return false }
            return true
        }
    }

    public struct State {
        public init(contributors: [ContributorProfile] = []) {
            self.contributors = contributors.map(ContributorOption.init)
        }

        @DebugSnapshotTracked
        var actorSearchErrorMessage: String?
        var actorSearchFailures: [PredictiveSearchFailure] = []
        var actorSearchIsLoading = false
        var actorSearchSections: [PredictiveSearchSection<ActorIdentity>] = []
        var contributors: [ContributorOption]
        @DebugSnapshotTracked
        var searchQuery = ""
        @DebugSnapshotTracked
        var selection = Selection.none

        var filteredContributors: [ContributorOption] {
            let query = searchQuery.trimmedForContributorPicker
            guard !query.isEmpty else { return [] }
            return contributors.filter { $0.matches(query) }
        }

        var hasManualOptions: Bool {
            searchQuery.trimmedForContributorPicker.count >= 2
        }

        var manualName: String? {
            searchQuery.trimmedForContributorPicker.nilIfEmpty
        }

        func selectedContributorOption(
            id: OMERecord.ID<OMERecord.Contributor>
        ) -> ContributorOption? {
            contributors.first { $0.id == id }
        }

        var selectedSummary: (title: String, subtitle: String?)? {
            summary(for: selection)
        }

        func summary(
            for selection: Selection,
            showsTechnicalDetails: Bool = false
        ) -> (title: String, subtitle: String?)? {
            switch selection {
            case .none:
                return nil

            case let .existingContributor(id):
                if let contributor = selectedContributorOption(id: id) {
                    return (contributor.name, contributor.subtitle)
                }
                return (
                    showsTechnicalDetails ? id.rawValue.rawValue : "Contributor",
                    showsTechnicalDetails ? "Contributor ID" : nil
                )

            case let .identityOnly(actor, displayTitle):
                return (
                    displayTitle?.nilIfEmpty
                        ?? (showsTechnicalDetails ? actor.description : "Account"),
                    "Identity only"
                )

            case let .newContributor(name):
                return (name, "New contributor")

            case let .newContributorFromIdentity(identity):
                return (identity.contributorName, identity.subtitle)

            case let .performanceDisplayName(name):
                return (name, "Performance only")
            }
        }

        mutating func resetSearch() {
            actorSearchErrorMessage = nil
            actorSearchFailures = []
            actorSearchIsLoading = false
            actorSearchSections = []
            searchQuery = ""
            selection = .none
        }
    }

    public enum Action {
        case actorSearchResponse(PredictiveSearchResponse<ActorIdentity>)
        case actorSearchSubmitted
        case clearSelectionButtonTapped
        case createContributorButtonTapped
        case existingContributorTapped(OMERecord.ID<OMERecord.Contributor>)
        case identityCreateContributorButtonTapped(ActorIdentity)
        case identityLinkOnlyButtonTapped(ActorIdentity)
        case performanceDisplayNameButtonTapped
        case searchQueryChanged(String)
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case let .actorSearchResponse(response):
                guard response.query == state.searchQuery.trimmedForContributorPicker else {
                    return
                }
                state.actorSearchIsLoading = false
                state.actorSearchFailures = response.failures
                state.actorSearchSections = response.sections

            case .actorSearchSubmitted:
                searchActorIdentities(
                    query: state.searchQuery,
                    includingExactLookup: true,
                    state: &state
                )

            case .clearSelectionButtonTapped:
                state.selection = .none

            case .createContributorButtonTapped:
                guard let name = state.manualName else { return }
                state.selection = .newContributor(name: name)

            case let .existingContributorTapped(contributorID):
                state.selection = .existingContributor(contributorID)

            case let .identityCreateContributorButtonTapped(identity):
                state.selection = .newContributorFromIdentity(
                    SelectedActorIdentity(identity)
                )
                state.actorSearchErrorMessage = nil

            case let .identityLinkOnlyButtonTapped(identity):
                guard let actor = OMERecord.Contributor.Actor(identity.did.description) else {
                    state.actorSearchErrorMessage = "The selected account is not a valid contributor identity."
                    return
                }
                state.selection = .identityOnly(
                    actor: actor,
                    displayTitle: identity.displayTitle
                )
                state.actorSearchErrorMessage = nil

            case .performanceDisplayNameButtonTapped:
                guard let name = state.manualName else { return }
                state.selection = .performanceDisplayName(name: name)

            case let .searchQueryChanged(query):
                state.searchQuery = query
                state.actorSearchErrorMessage = nil
                searchActorIdentities(
                    query: query,
                    includingExactLookup: false,
                    state: &state
                )
            }
        }
    }

    private func searchActorIdentities(
        query: String,
        includingExactLookup: Bool,
        state: inout State
    ) {
        let query = query.trimmedForContributorPicker
        guard query.count >= 2 else {
            state.actorSearchFailures = []
            state.actorSearchIsLoading = false
            state.actorSearchSections = []
            return
        }

        state.actorSearchIsLoading = true
        store.addTask(id: actorSearchTask) {
            let response = await (includingExactLookup ? Self.exactActorSearch : Self.typeaheadActorSearch)
                .search(query)
            try Task.checkCancellation()
            try store.send(.actorSearchResponse(response))
        }
    }

    private static let exactActorSearch = PredictiveSearch(
        actorIdentitySources: [
            .exactActorIdentityLookup(title: "Exact match"),
        ],
        minimumQueryLength: 2
    )

    private static let typeaheadActorSearch = PredictiveSearch(
        actorIdentitySources: [
            .appBskyActorTypeahead(title: "Profiles", limit: 10),
        ],
        minimumQueryLength: 2
    )
}

struct ContributorRelationshipPickerView: View {
    @Bindable var store: StoreOf<ContributorRelationshipPicker>
    let title: String

    init(
        store: StoreOf<ContributorRelationshipPicker>,
        title: String = "Contributor"
    ) {
        self.store = store
        self.title = title
    }

    var body: some View {
        Section(title) {
            ContributorRelationshipPickerRows(store: store)
        }
    }
}

struct ContributorRelationshipPickerRows: View {
    @Bindable var store: StoreOf<ContributorRelationshipPicker>
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        TextField("Search or add contributor", text: $store.searchQuery)
            .autocorrectionDisabled()
            #if !os(macOS)
            .textInputAutocapitalization(.never)
            #endif
            .onSubmit {
                store.send(.actorSearchSubmitted)
            }
            .onChange(of: store.searchQuery) { _, query in
                store.send(.searchQueryChanged(query))
            }

        if !store.filteredContributors.isEmpty {
            ContributorRelationshipGroupHeader(title: "Event contributors")
            ForEach(store.filteredContributors, id: \.rawID) { contributor in
                Button {
                    store.send(.existingContributorTapped(contributor.id))
                } label: {
                    ContributorRelationshipOptionRow(
                        title: contributor.name,
                        subtitle: contributor.subtitle,
                        accessory: isSelectedContributor(contributor.id) ? "Selected" : nil
                    )
                }
                .buttonStyle(.plain)
            }
        }

        if store.hasManualOptions,
           let manualName = store.manualName {
            ContributorRelationshipGroupHeader(title: "Manual")
            Button {
                store.send(.createContributorButtonTapped)
            } label: {
                ContributorRelationshipOptionRow(
                    title: "Create contributor",
                    subtitle: manualName
                )
            }
            .buttonStyle(.plain)

            Button {
                store.send(.performanceDisplayNameButtonTapped)
            } label: {
                ContributorRelationshipOptionRow(
                    title: "Use on this performance only",
                    subtitle: manualName
                )
            }
            .buttonStyle(.plain)
        }

        if store.actorSearchIsLoading {
            ProgressView()
        }

        ForEach(store.actorSearchSections) { section in
            ContributorRelationshipGroupHeader(title: section.title)
            ForEach(section.results) { identity in
                ContributorRelationshipActorRow(
                    identity: identity,
                    identityOnlyTapped: {
                        store.send(.identityLinkOnlyButtonTapped(identity))
                    },
                    createContributorTapped: {
                        store.send(.identityCreateContributorButtonTapped(identity))
                    }
                )
            }
        }

        if store.searchQuery.trimmedForContributorPicker.count >= 2 {
            Button(
                showsTechnicalDetails
                    ? "Look up exact handle or DID"
                    : "Look up exact account"
            ) {
                store.send(.actorSearchSubmitted)
            }
            .disabled(store.actorSearchIsLoading)
        }

        if let errorMessage = store.actorSearchErrorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
        }

        ForEach(store.actorSearchFailures, id: \.sourceID) { failure in
            VStack(alignment: .leading, spacing: 4) {
                Text(failure.title)
                Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func isSelectedContributor(
        _ contributorID: OMERecord.ID<OMERecord.Contributor>
    ) -> Bool {
        guard case let .existingContributor(selectedID) = store.selection else {
            return false
        }
        return selectedID == contributorID
    }
}

struct ContributorRelationshipSelectedRow: View {
    let title: String
    let subtitle: String?
    let clearButtonTapped: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Clear") {
                clearButtonTapped()
            }
        }
    }
}

struct ContributorRelationshipGroupHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

struct ContributorRelationshipOptionRow: View {
    let title: String
    let subtitle: String?
    let accessory: String?

    init(
        title: String,
        subtitle: String? = nil,
        accessory: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let accessory {
                Text(accessory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ContributorRelationshipActorRow: View {
    let identity: ActorIdentity
    let identityOnlyTapped: () -> Void
    let createContributorTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ContributorActorIdentityRow(identity: identity, isSelected: false)

            HStack {
                Button("Link identity only") {
                    identityOnlyTapped()
                }
                Button("Create/reuse contributor") {
                    createContributorTapped()
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var trimmedForContributorPicker: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
