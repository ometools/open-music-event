import ComposableArchitecture2
import ComposableForms
import Dependencies
import Foundation
import Lexicon
import OpenMusicEventDatabase
import SQLiteData
import SwiftUI

@Feature
public struct EditEventPolicies {
    public init() {}

    public enum ContributorListingSelection: String, CaseIterable, Equatable, Sendable {
        case none
        case scheduleContributors
        case unsupported
    }

    public enum ContributorProfileSelection: String, CaseIterable, Equatable, Sendable {
        case none
        case actorProfiles
        case claimedArtistsOnly
        case unsupported
    }

    public struct FormValue: Equatable, Sendable {
        public init(policies: OMERecord.Event.Policies? = nil) {
            let contributors = policies?.contributors

            switch contributors?.listing {
            case nil:
                self.contributorListing = .none
            case .known(.scheduleContributors):
                self.contributorListing = .scheduleContributors
            case let .unknown(value):
                self.contributorListing = .unsupported
                self.preservedContributorListing = .unknown(value)
            }

            switch contributors?.profile {
            case nil:
                self.contributorProfile = .none
            case let .known(.actorProfiles(actorProfiles)):
                self.contributorProfile = .actorProfiles
                self.applyProfileProviders(actorProfiles.providers)
            case let .known(.claimedArtistsOnly(claimedArtistsOnly)):
                self.contributorProfile = .claimedArtistsOnly
                self.applyProfileProviders(claimedArtistsOnly.providers)
            case let .unknown(value):
                self.contributorProfile = .unsupported
                self.preservedContributorProfile = .unknown(value)
            }
        }

        public var contributorListing: ContributorListingSelection = .none
        public var contributorProfile: ContributorProfileSelection = .none
        public var preservedContributorListing: Open<OMERecord.Event.ContributorListingPolicy>?
        public var preservedContributorProfile: Open<OMERecord.Event.ContributorProfilePolicy>?
        public var preservedProfileProviders: [Open<OMERecord.Event.ContributorProfileProvider>] = []
        public var usesBlueskyActorProfile = false

        var hasProfileProviders: Bool {
            usesBlueskyActorProfile || !preservedProfileProviders.isEmpty
        }

        var hasValidProfileProviderSelection: Bool {
            switch contributorProfile {
            case .actorProfiles, .claimedArtistsOnly:
                hasProfileProviders
            case .none, .unsupported:
                true
            }
        }

        var preparedPolicies: OMERecord.Event.Policies? {
            let listing = preparedContributorListing
            let profile = preparedContributorProfile
            guard listing != nil || profile != nil else { return nil }
            return OMERecord.Event.Policies(
                contributors: .init(
                    listing: listing,
                    profile: profile
                )
            )
        }

        var preservedContributorListingDescription: String? {
            guard case let .unknown(value)? = preservedContributorListing else { return nil }
            return unsupportedValueDescription(value)
        }

        var preservedContributorProfileDescription: String? {
            guard case let .unknown(value)? = preservedContributorProfile else { return nil }
            return unsupportedValueDescription(value)
        }

        var preservedProfileProviderDescriptions: [String] {
            preservedProfileProviders.compactMap { provider in
                guard case let .unknown(value) = provider else { return nil }
                return unsupportedValueDescription(value)
            }
        }

        private var preparedContributorListing: Open<OMERecord.Event.ContributorListingPolicy>? {
            switch contributorListing {
            case .none:
                nil
            case .scheduleContributors:
                .known(.scheduleContributors)
            case .unsupported:
                preservedContributorListing
            }
        }

        private var preparedContributorProfile: Open<OMERecord.Event.ContributorProfilePolicy>? {
            switch contributorProfile {
            case .none:
                nil
            case .actorProfiles:
                .known(.actorProfiles(.init(providers: preparedProfileProviders)))
            case .claimedArtistsOnly:
                .known(.claimedArtistsOnly(.init(providers: preparedProfileProviders)))
            case .unsupported:
                preservedContributorProfile
            }
        }

        private var preparedProfileProviders: [Open<OMERecord.Event.ContributorProfileProvider>] {
            var providers = preservedProfileProviders
            if usesBlueskyActorProfile {
                providers.insert(.known(.bskyActorProfile), at: 0)
            }
            return providers
        }

        private mutating func applyProfileProviders(
            _ providers: [Open<OMERecord.Event.ContributorProfileProvider>]
        ) {
            self.usesBlueskyActorProfile = providers.contains {
                $0 == .known(.bskyActorProfile)
            }
            self.preservedProfileProviders = providers.filter { provider in
                guard case .unknown = provider else { return false }
                return true
            }
        }
    }

    public typealias FormFeature = ComposableForms.Form<FormValue>

    public struct State {
        public init(eventID: OMERecord.Event.ID) {
            self.draft = .placeholder
            self.eventID = eventID
            self.form = FormFeature.State(value: FormValue())
        }

        public let eventID: OMERecord.Event.ID

        var draft: OMERecord.Event.Draft
        var errorMessage: String?
        var form: FormFeature.State
        var hasLoadedDraft = false
        var isSaving = false

        var canSubmit: Bool {
            hasLoadedDraft
                && !isSaving
                && form.canSubmit
                && form.value.hasValidProfileProviderSelection
        }

        var navigationTitle: String {
            "Event Policies"
        }

        var preparedDraft: OMERecord.Event.Draft {
            var draft = draft
            draft.policies = form.value.preparedPolicies
            return draft
        }
    }

    public enum Action {
        case cancelButtonTapped
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case saveButtonTapped
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Scope(\.form, action: \.form) {
            FormFeature()
                .onSubmit { value in
                    try store.send(.formSubmitted(value))
                }
        }
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .form:
                break

            case let .formSubmitted(value):
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This event could not be loaded."
                    return
                }
                guard value.hasValidProfileProviderSelection else {
                    state.reportMissingProfileProvider()
                    return
                }

                state.errorMessage = nil
                state.isSaving = true
                let draft = state.preparedDraft

                store.addTask {
                    do {
                        try database.write { db in
                            try OMERecord.Event.upsert {
                                draft
                            }
                            .execute(db)
                        }
                        try store.modify {
                            $0.errorMessage = nil
                            $0.isSaving = false
                        }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to save event policies."
                            $0.isSaving = false
                        }
                    }
                }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This event could not be loaded."
                    return
                }
                guard state.form.value.hasValidProfileProviderSelection else {
                    state.reportMissingProfileProvider()
                    return
                }

                store.addTask {
                    try store.send(.form(.submittedForm))
                }
            }
        }
        .onMount { state in
            guard !state.hasLoadedDraft else { return }

            do {
                if let event = try database.read({ db in
                    try OMERecord.Event.where { $0.id.eq(state.eventID) }.fetchOne(db)
                }) {
                    state.draft = .init(event)
                    state.form = FormFeature.State(value: FormValue(policies: event.policies))
                    state.hasLoadedDraft = true
                    state.errorMessage = nil
                } else {
                    state.errorMessage = "This event could not be loaded."
                }
            } catch {
                state.errorMessage = "This event could not be loaded."
            }
        }
    }
}

private enum EditEventPoliciesFormFieldID {
    static var profileProviders: AnyHashable { "profileProviders" }
}

private extension EditEventPolicies.FormFeature {
    init() {
        self.init {
            Self.Field(
                id: EditEventPoliciesFormFieldID.profileProviders,
                value: \.hasValidProfileProviderSelection
            ) {
                Validation(error: "Choose at least one profile provider.") { $0 }
            }
        }
    }
}

public struct EditEventPoliciesView: View {
    @Bindable var store: StoreOf<EditEventPolicies>

    public init(store: StoreOf<EditEventPolicies>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasLoadedDraft {
                loadedForm
            } else {
                ViewerPlaceholderView(
                    title: store.navigationTitle,
                    systemImage: "slider.horizontal.3",
                    description: "This event could not be loaded."
                )
            }
        }
        .disabled(store.isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    store.send(.cancelButtonTapped)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if store.isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        store.send(.saveButtonTapped)
                    }
                    .disabled(!store.canSubmit)
                }
            }
        }
        .navigationTitle(store.navigationTitle)
    }

    private var loadedForm: some View {
        Form {
            contributorListingSection
            contributorProfileSection
            errorSection
        }
    }

    private var contributorListingSection: some View {
        Section("Contributor Listing") {
            Picker("Listing", selection: $store.form.value.contributorListing) {
                ForEach(store.form.value.contributorListing.availableSelections, id: \.self) { selection in
                    Text(selection.title).tag(selection)
                }
            }

            if store.form.value.contributorListing == .unsupported,
               let description = store.form.value.preservedContributorListingDescription {
                UnsupportedPolicyValueRow(title: "Unsupported listing", value: description)
            }
        }
    }

    private var contributorProfileSection: some View {
        Section("Contributor Profiles") {
            Picker("Profile", selection: $store.form.value.contributorProfile) {
                ForEach(store.form.value.contributorProfile.availableSelections, id: \.self) { selection in
                    Text(selection.title).tag(selection)
                }
            }

            if store.form.value.contributorProfile.usesProviders {
                Toggle(
                    "Bluesky Actor Profile",
                    isOn: $store.form.value.usesBlueskyActorProfile
                )

                ForEach(
                    Array(store.form.value.preservedProfileProviderDescriptions.enumerated()),
                    id: \.offset
                ) { _, provider in
                    UnsupportedPolicyValueRow(title: "Unsupported provider", value: provider)
                }

                FormFieldValidationStatus(
                    validation: store.form.validation[EditEventPoliciesFormFieldID.profileProviders]
                )
            }

            if store.form.value.contributorProfile == .unsupported,
               let description = store.form.value.preservedContributorProfileDescription {
                UnsupportedPolicyValueRow(title: "Unsupported profile", value: description)
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage = store.errorMessage {
            Section {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}

struct UnsupportedPolicyValueRow: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.secondary)
        } label: {
            Label(title, systemImage: "lock")
        }
    }
}

private extension EditEventPolicies.State {
    mutating func reportMissingProfileProvider() {
        let message = "Choose at least one profile provider."
        self.errorMessage = message
        self.form.validation[EditEventPoliciesFormFieldID.profileProviders] = .invalid(
            .init(message:  message)
        )
    }
}

private extension EditEventPolicies.ContributorListingSelection {
    var availableSelections: [Self] {
        self == .unsupported ? [.none, .scheduleContributors, .unsupported] : [.none, .scheduleContributors]
    }

    var title: String {
        switch self {
        case .none:
            "None"
        case .scheduleContributors:
            "Schedule Contributors"
        case .unsupported:
            "Unsupported"
        }
    }
}

private extension EditEventPolicies.ContributorProfileSelection {
    var availableSelections: [Self] {
        self == .unsupported
            ? [.none, .actorProfiles, .claimedArtistsOnly, .unsupported]
            : [.none, .actorProfiles, .claimedArtistsOnly]
    }

    var title: String {
        switch self {
        case .none:
            "None"
        case .actorProfiles:
            "Actor Profiles"
        case .claimedArtistsOnly:
            "Claimed Artists Only"
        case .unsupported:
            "Unsupported"
        }
    }

    var usesProviders: Bool {
        switch self {
        case .actorProfiles, .claimedArtistsOnly:
            true
        case .none, .unsupported:
            false
        }
    }
}

private extension OMERecord.Event.Draft {
    static var placeholder: Self {
        .init(
            id: .init(
                organizerID: OMERecord.Organizer.ID("did:web:example.com")!,
                eventID: .init("-1")
            ),
            name: "",
            description: nil,
            startDate: nil,
            endDate: nil,
            status: nil,
            mode: nil,
            locations: nil,
            uris: nil,
            timeZone: TimeZone.current,
            imageURL: nil,
            iconImageURL: nil,
            siteMapImageURL: nil,
            contactNumbers: nil,
            categoryConfigs: nil
        )
    }
}

private func unsupportedValueDescription<Known>(
    _ value: Open<Known>.PartialValue
) -> String {
    switch value {
    case let .string(string):
        string
    case let .object(object):
        object["type"]?.stringValue ?? "Object"
    case let .array(values):
        values.map(unsupportedValueDescription).joined(separator: ", ")
    case let .integer(integer):
        String(integer)
    case let .double(double):
        String(double)
    case let .bool(bool):
        bool ? "true" : "false"
    case .null:
        "null"
    }
}
