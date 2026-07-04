import ATProto
import BlueskyActorCache
import ComposableForms
import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventEditors
import OpenMusicEventImages
import SQLiteData
import Tagged
import SwiftUI
import XRPCClient

@Feature
public struct ContributorsViewer {
    public init() {}

    public struct State {
        public init(
            eventID: OMERecord.Event.ID,
            destination: Destination.State? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            _contributorRows = FetchAll(
                ContributorsViewer.contributorRowsQuery(
                    eventID: eventID,
                    hydration: .bskyActorProfile
                )
            )
        }

        public let eventID: OMERecord.Event.ID
        public var destination: Destination.State?
        public var searchText = ""

        @DebugSnapshotIgnored
        @FetchAll var contributorRows: [ContributorListRow]

        var filteredContributorRows: [ContributorListRow] {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return contributorRows }

            return contributorRows.filter { $0.matchesSearch(query) }
        }

        var actorProfileLoadRequests: [ContributorProfile.ActorProfileLoadRequest] {
            contributorRows.map(\.profile).actorProfileLoadRequests
        }
    }

    public enum Action {
        case addButtonTapped
        case destination(Destination.Action)
        case contributorButtonTapped(OMERecord.ID<OMERecord.Contributor>)
    }

    @Feature
    public enum Destination {
        case contributorDetail(Spawn<ContributorDetail>)
    }

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache

    static func contributorProfilesQuery(
        eventID: OMERecord.Event.ID,
        hydration: ContributorProfile.Hydration = .none
    ) -> some Statement<ContributorProfile> {
        ContributorProfile.all(eventID: eventID, hydration: hydration)
    }

    static func contributorRowsQuery(
        eventID: OMERecord.Event.ID,
        hydration: ContributorProfile.Hydration = .none
    ) -> some Statement<ContributorListRow> {
        ContributorListRow.all(eventID: eventID, hydration: hydration)
    }

    static func performanceContributorsQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Performance.Contributors> {
        OMERecord.Performance.Contributors
            .where { $0.performanceID.organizerID.eq(eventID.organizerID) }
            .where { $0.performanceID.eventID.eq(eventID.eventID) }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addButtonTapped:
                let eventID = state.eventID
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .createContributor(eventID)
                    )
                    await task?.value
                }

            case .destination:
                break

            case let .contributorButtonTapped(contributorID):
                store.withDependencies {
                    state.destination = .contributorDetail(
                        Spawn(.init(contributorID: contributorID, eventID: state.eventID))
                    )
                }
            }
        }
        .onChange(of: store.actorProfileLoadRequests, initial: true) { _, requests, _ in
            guard !requests.isEmpty else { return }

            store.addTask {
                for request in requests {
                    do {
                        _ = try await blueskyActorProfileCache.refreshProfileIfNeeded(
                            request.actor.description,
                            24 * 60 * 60,
                            15 * 60
                        )
                    } catch is CancellationError {
                        return
                    } catch {
                    }
                }
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct ContributorsViewerView: View {
    @Bindable var store: StoreOf<ContributorsViewer>

    public init(store: StoreOf<ContributorsViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.contributorRows.isEmpty {
                ViewerPlaceholderView(
                    title: "Contributors",
                    systemImage: "person.3",
                    description: "No contributors have been added to this event yet."
                )
            } else if store.filteredContributorRows.isEmpty {
                ViewerPlaceholderView(
                    title: "No Results",
                    systemImage: "person.3",
                    description: "No contributors match your search."
                )
            } else {
                List(store.filteredContributorRows) { row in
                    ContributorListButton(row: row) { contributorID in
                        store.send(.contributorButtonTapped(contributorID))
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $store.searchText, prompt: "Search Contributors")
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .navigationTitle("Contributors")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.send(.addButtonTapped)
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel("Add Contributor")
                }
            }
        }
        .navigationDestination(item: $store.scope(\.destination, action: \.destination).contributorDetail) { detailStore in
            ContributorDetailView(store: detailStore)
        }
    }
}

struct ContributorListButton: View {
    let row: ContributorListRow
    let contributorButtonTapped: (OMERecord.ID<OMERecord.Contributor>) -> Void

    var body: some View {
        Button {
            contributorButtonTapped(row.contributorID)
        } label: {
            ContributorsRowView(
                profile: row.profile,
                stageContext: row.stageContext
            )
        }
        .buttonStyle(.plain)
    }
}

struct ContributorsRowView: View {
    let profile: ContributorProfile
    let stageContext: ContributorStageContext?

    init(
        profile: ContributorProfile,
        stageContext: ContributorStageContext? = nil
    ) {
        self.profile = profile
        self.stageContext = stageContext
    }

    init(
        contributor: OMERecord.Contributor,
        stageContext: ContributorStageContext? = nil
    ) {
        self.profile = ContributorProfile(contributor: contributor)
        self.stageContext = stageContext
    }

    var body: some View {
        HStack(spacing: 12) {
            ContributorArtworkView(
                asset: profile.artworkAsset,
                cacheContext: profile.artworkCacheContext,
                size: 60
            )

            if let stageContext, !stageContext.stages.isEmpty {
                ContributorStageIndicatorView(
                    colors: stageContext.stages.map { $0.color.swiftUIColor }
                )
                .frame(width: 5, height: 60)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .lineLimit(1)

                if let subtitle = profile.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .foregroundStyle(.primary)
    }
}

@Feature
public struct EditContributor {
    public init() {}

    public struct FormValue: Equatable {
        var bio = ""
        var kind = ""
        var links: [EditableContributorLink] = []
        var name = ""

        init() {}

        init(contributor: OMERecord.Contributor) {
            bio = contributor.bio ?? ""
            kind = contributor.kind?.rawValue ?? ""
            links = (contributor.links ?? []).map(EditableContributorLink.init)
            name = contributor.name
        }
    }

    public typealias FormFeature = ComposableForms.Form<FormValue>

    public struct State {
        public enum Mode: Equatable, Sendable {
            case create
            case edit(OMERecord.ID<OMERecord.Contributor>)

            var contributorID: OMERecord.ID<OMERecord.Contributor>? {
                switch self {
                case .create:
                    return nil
                case let .edit(contributorID):
                    return contributorID
                }
            }
        }

        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
            self.form = FormFeature.State(value: FormValue())
            self.hasLoadedDraft = true
            self.logoImagePicker = ImageAssetPicker.State(configuration: .contributorLogo, assets: nil)
            self.mode = .create
            self.photoImagePicker = ImageAssetPicker.State(configuration: .contributorPhoto, assets: nil)
        }

        public init(
            contributorID: OMERecord.ID<OMERecord.Contributor>,
            eventID: OMERecord.Event.ID
        ) {
            self.eventID = eventID
            self.form = FormFeature.State(value: FormValue())
            let cacheContext = LocalImageCacheContext(
                contributorID: OMERecord.Contributor.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    contributorID: contributorID
                )
            )
            self.logoImagePicker = ImageAssetPicker.State(
                configuration: .contributorLogo,
                assets: nil,
                cacheContext: cacheContext
            )
            self.mode = .edit(contributorID)
            self.photoImagePicker = ImageAssetPicker.State(
                configuration: .contributorPhoto,
                assets: nil,
                cacheContext: cacheContext
            )
        }

        public let eventID: OMERecord.Event.ID
        let mode: Mode

        public var actorSearchErrorMessage: String?
        public var actorSearchFailures: [PredictiveSearchFailure] = []
        public var actorSearchIsLoading = false
        public var actorSearchQuery = ""
        public var actorSearchSections: [PredictiveSearchSection<ActorIdentity>] = []
        public var contributorDID: DID?
        @DebugSnapshotTracked var errorMessage: String?
        var form: FormFeature.State
        @DebugSnapshotTracked var hasLoadedDraft: Bool = false
        @DebugSnapshotTracked var isSaving: Bool = false
        public var isSavingActor = false
        var logoImagePicker: ImageAssetPicker.State
        var originalImages: [OMERecord.ImageAsset] = []
        var photoImagePicker: ImageAssetPicker.State

        var imageURL: String {
            get { photoImagePicker.firstURLString }
            set { photoImagePicker.replaceURLString(newValue) }
        }

        var logoURL: String {
            get { logoImagePicker.firstURLString }
            set { logoImagePicker.replaceURLString(newValue) }
        }

        var canSubmit: Bool {
            hasLoadedDraft && !isSaving && !isSavingActor && form.canSubmit
        }

        var contributorActor: OMERecord.Contributor.Actor? {
            if let contributorDID,
               let actor = OMERecord.Contributor.Actor(contributorDID.description) {
                return actor
            }
            return nil
        }

        var navigationTitle: String {
            switch mode {
            case .create:
                return "New Contributor"
            case .edit:
                return "Edit Contributor"
            }
        }

        var submitButtonTitle: String {
            switch mode {
            case .create:
                return "Create"
            case .edit:
                return "Save"
            }
        }

        fileprivate struct SaveRequest: Sendable {
            let bio: String?
            let did: DID?
            let eventID: OMERecord.Event.ID
            let kind: OMERecord.Contributor.Kind?
            let links: [ExternalPlatform.Link]?
            let logoImages: [ImageAssetPicker.ImageValue]
            let mode: Mode
            let name: String
            let photoImages: [ImageAssetPicker.ImageValue]
            let preservedImages: [OMERecord.ImageAsset]

            init(state: State) {
                self.bio = state.form.value.bio.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                self.did = state.contributorDID
                self.eventID = state.eventID
                self.kind = state.form.value.kind.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    .map { OMERecord.Contributor.Kind($0) }
                self.links = state.preparedLinks.nilIfEmpty
                self.logoImages = state.logoImagePicker.images
                self.mode = state.mode
                self.name = state.trimmedName
                self.photoImages = state.photoImagePicker.images
                self.preservedImages = state.originalImages.filter {
                    $0.role != .photo && $0.role != .logo
                }
            }

            func contributorID(in db: Database) throws -> OMERecord.ID<OMERecord.Contributor> {
                if let contributorID = mode.contributorID {
                    return contributorID
                }

                let base = State.contributorIDBase(for: name)
                var candidate = base
                var suffix = 2

                while try ContributorDetail.contributorQuery(
                    contributorID: State.localID(candidate),
                    eventID: eventID
                )
                .fetchOne(db) != nil {
                    candidate = "\(base)-\(suffix)"
                    suffix += 1
                }

                return State.localID(candidate)
            }

            func contributorRecordID(
                contributorID: OMERecord.ID<OMERecord.Contributor>
            ) -> OMERecord.Contributor.ID {
                OMERecord.Contributor.ID(
                    organizerID: eventID.organizerID,
                    eventID: eventID.eventID,
                    contributorID: contributorID
                )
            }

            func preparedDraft(
                contributorID: OMERecord.ID<OMERecord.Contributor>
            ) throws -> (draft: OMERecord.Contributor.Draft, blobs: [LocalImageBlob]) {
                let contributorRecordID = contributorRecordID(contributorID: contributorID)
                let preparedImages = try preparedImages(
                    context: .init(contributorID: contributorRecordID)
                )
                return (
                    OMERecord.Contributor.Draft(
                        id: contributorRecordID,
                        name: name,
                        did: did,
                        bio: bio,
                        images: preparedImages.images.isEmpty ? nil : preparedImages.images,
                        kind: kind,
                        links: links
                    ),
                    preparedImages.blobs
                )
            }

            func clearLinkedPerformanceActors(
                contributorID: OMERecord.ID<OMERecord.Contributor>,
                in db: Database
            ) throws {
                guard did != nil else { return }

                try #sql("""
                    UPDATE "performanceContributors"
                    SET "contributorActor" = NULL
                    WHERE "organizerID" = \(eventID.organizerID)
                      AND "eventID" = \(eventID.eventID)
                      AND "contributorID" = \(contributorID)
                    """)
                    .execute(db)
            }

            private func preparedImages(
                context: LocalImageCacheContext
            ) throws -> (images: [OMERecord.ImageAsset], blobs: [LocalImageBlob]) {
                let photos = try ImageAssetPicker.State.materializedImages(
                    photoImages,
                    context: context
                )
                let logos = try ImageAssetPicker.State.materializedImages(
                    logoImages,
                    context: context
                )
                return (
                    preservedImages + photos.images + logos.images,
                    photos.blobs + logos.blobs
                )
            }
        }

        var preparedLinks: [ExternalPlatform.Link] {
            form.value.links.compactMap(\.preparedLink)
        }

        mutating func resetImagePickers() {
            let cacheContext = imageCacheContext
            logoImagePicker = ImageAssetPicker.State(
                configuration: .contributorLogo,
                assets: originalImages,
                cacheContext: cacheContext
            )
            photoImagePicker = ImageAssetPicker.State(
                configuration: .contributorPhoto,
                assets: originalImages,
                cacheContext: cacheContext
            )
        }

        mutating func load(_ contributor: OMERecord.Contributor) {
            form = FormFeature.State(value: FormValue(contributor: contributor))
            contributorDID = contributor.did
            originalImages = contributor.images ?? []
            resetImagePickers()
            hasLoadedDraft = true
            errorMessage = nil
        }

        mutating func prefillFromActorIdentity(_ identity: ActorIdentity) {
            prefillName(identity.displayTitle)
            prefillPhoto(identity.avatar)
        }

        mutating func prefillFromActorProfile(_ profile: BlueskyActorProfile) {
            prefillName(
                profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? profile.handle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? profile.did
            )
            prefillBio(profile.description)
            prefillPhoto(profile.avatar)
        }

        mutating func resetActorSearch() {
            actorSearchErrorMessage = nil
            actorSearchFailures = []
            actorSearchIsLoading = false
            actorSearchQuery = ""
            actorSearchSections = []
        }

        private mutating func prefillBio(_ value: String?) {
            guard form.value.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            else { return }

            form.value.bio = value
        }

        private mutating func prefillName(_ value: String?) {
            guard form.value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            else { return }

            form.value.name = value
        }

        private mutating func prefillPhoto(_ url: URL?) {
            guard photoImagePicker.images.isEmpty,
                  let url
            else { return }

            photoImagePicker.replaceURLString(url.absoluteString)
        }

        private var imageCacheContext: LocalImageCacheContext? {
            if let contributorID = mode.contributorID {
                return LocalImageCacheContext(
                    contributorID: OMERecord.Contributor.ID(
                        organizerID: eventID.organizerID,
                        eventID: eventID.eventID,
                        contributorID: contributorID
                    )
                )
            }
            return nil
        }

        private var trimmedName: String {
            form.value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func localID(_ string: String) -> OMERecord.ID<OMERecord.Contributor> {
            OMERecord.ID<OMERecord.Contributor>(.init(string))
        }

        private static func contributorIDBase(for name: String) -> String {
            let normalized = name
                .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
                .lowercased()
            let words = normalized
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }

            return words.isEmpty
                ? "contributor-\(UUID().uuidString.lowercased())"
                : words.joined(separator: "-")
        }
    }

    public enum Action {
        case onAppear
        case addLinkButtonTapped
        case actorIdentityTapped(ActorIdentity)
        case actorSearchSubmitted
        case actorSearchQueryChanged(String)
        case actorSearchResponse(PredictiveSearchResponse<ActorIdentity>)
        case actorProfileResponse(BlueskyActorProfile?)
        case cancelButtonTapped
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case logoImagePicker(ImageAssetPicker.Action)
        case photoImagePicker(ImageAssetPicker.Action)
        case removeLinkButtonTapped(UUID)
        case saveButtonTapped
        case saveFailed(String)
        case saveSucceeded
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
    @StoreTaskID var actorSearchTask

    public var body: some Feature {
        let _ = Self._logChanges()
        Scope(\.form, action: \.form) {
            FormFeature()
                .onSubmit { value in
                    try store.send(.formSubmitted(value))
                }
        }
        Scope(\.logoImagePicker, action: \.logoImagePicker) {
            ImageAssetPicker()
        }
        Scope(\.photoImagePicker, action: \.photoImagePicker) {
            ImageAssetPicker()
        }
        Update { state, action in
            switch action {
            case .addLinkButtonTapped:
                state.form.value.links.append(EditableContributorLink())

            case let .actorIdentityTapped(identity):
                guard let actor = OMERecord.Contributor.Actor(identity.did.description) else {
                    state.actorSearchErrorMessage = "The selected DID is not a valid contributor actor."
                    return
                }

                state.contributorDID = identity.did
                state.prefillFromActorIdentity(identity)
                state.resetActorSearch()
                state.isSavingActor = true
                store.addTask {
                    let profile: BlueskyActorProfile? = await store.withErrorHandling(
                        fallbackMessage: .contributorProfileLookupFailed,
                        operation: .contributorProfileLookup
                    ) {
                        let cachedProfile = try await blueskyActorProfileCache.cachedProfile(
                            actor.description
                        )
                        let refreshedProfile = try await blueskyActorProfileCache.refreshProfileIfNeeded(
                            actor.description,
                            24 * 60 * 60,
                            15 * 60
                        )
                        return refreshedProfile ?? cachedProfile
                    } ?? nil

                    try store.send(.actorProfileResponse(profile))
                }

            case let .actorSearchQueryChanged(query):
                state.actorSearchQuery = query
                state.actorSearchErrorMessage = nil
                searchActorIdentities(query: query, includingExactLookup: false, state: &state)

            case let .actorSearchResponse(response):
                guard response.query == state.actorSearchQuery.trimmedForActorSearch else {
                    return
                }

                state.actorSearchIsLoading = false
                state.actorSearchFailures = response.failures
                state.actorSearchSections = response.sections

            case .actorSearchSubmitted:
                searchActorIdentities(
                    query: state.actorSearchQuery,
                    includingExactLookup: true,
                    state: &state
                )

            case let .actorProfileResponse(profile):
                if let profile {
                    state.prefillFromActorProfile(profile)
                }
                state.isSavingActor = false

            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .form:
                break

            case let .formSubmitted(value):
                
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This contributor could not be loaded."
                    return
                }
                state.form.value = value

                guard state.form.canSubmit else {
                    state.errorMessage = "Fix the highlighted fields."
                    return
                }

                state.errorMessage = nil
                state.isSaving = true
                let saveRequest = State.SaveRequest(state: state)

                store.addTask {
                    do {
                        try await database.write { db in
                            let contributorID = try saveRequest.contributorID(in: db)
                            let preparedDraft = try saveRequest.preparedDraft(contributorID: contributorID)
                            try OMERecord.Contributor.upsert {
                                preparedDraft.draft
                            }
                            .execute(db)
                            try saveRequest.clearLinkedPerformanceActors(
                                contributorID: contributorID,
                                in: db
                            )
                            if !preparedDraft.blobs.isEmpty {
                                try LocalImageBlob.insert { preparedDraft.blobs }.execute(db)
                            }
                        }
                        try store.send(.saveSucceeded)
                    } catch {
                        try store.send(
                            .saveFailed("Unable to save contributor: \(error.editContributorSaveDescription)")
                        )
                    }
                }

            case .logoImagePicker, .photoImagePicker:
                break

            case let .removeLinkButtonTapped(id):
                state.form.value.links.removeAll { $0.id == id }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This contributor could not be loaded."
                    return
                }

                store.addTask {
                    try store.send(.form(.submittedForm))
                }

            case let .saveFailed(message):
                state.errorMessage = message
                state.isSaving = false

            case .saveSucceeded:
                state.errorMessage = nil
                state.isSaving = false
                store.addTask {
                    _ = try? store.dismiss()
                }
            case .onAppear:
                guard !state.hasLoadedDraft else { return }

                guard let contributorID = state.mode.contributorID else {
                    state.hasLoadedDraft = true
                    state.errorMessage = nil
                    return
                }

                do {
                    if let contributor = try database.read({ db in
                        try ContributorDetail.contributorQuery(
                            contributorID: contributorID,
                            eventID: state.eventID
                        )
                        .fetchOne(db)
                    }) {
                        state.load(contributor)
                    } else {
                        state.errorMessage = "This contributor could not be loaded."
                    }
                } catch {
                    state.errorMessage = "This contributor could not be loaded."
                }
            }
        }
        .onMount { state in
            guard !state.hasLoadedDraft else { return }

            guard let contributorID = state.mode.contributorID else {
                state.hasLoadedDraft = true
                state.errorMessage = nil
                return
            }

            do {
                if let contributor = try database.read({ db in
                    try ContributorDetail.contributorQuery(
                        contributorID: contributorID,
                        eventID: state.eventID
                    )
                    .fetchOne(db)
                }) {
                    state.load(contributor)
                } else {
                    state.errorMessage = "This contributor could not be loaded."
                }
            } catch {
                state.errorMessage = "This contributor could not be loaded."
            }
        }
    }

    private func searchActorIdentities(
        query: String,
        includingExactLookup: Bool,
        state: inout State
    ) {
        let query = query.trimmedForActorSearch
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

private enum EditContributorFormFieldID {
    static var links: AnyHashable { AnyHashable(\EditContributor.FormValue.links) }
    static var name: AnyHashable { AnyHashable(\EditContributor.FormValue.name) }
}

private extension EditContributor.FormFeature {
    init() {
        self.init {
            Self.Field(\.name) {
                Validation(error: "Enter a name.") {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }

            Self.Field(\.links) {
                Validation { links -> ValidationResult in
                    guard let message = links.compactMap(\.validationMessage).first else {
                        return .valid
                    }
                    return .invalid(message)
                }
            }
        }
    }
}

public struct EditContributorView: View {
    @Bindable var store: StoreOf<EditContributor>
    @FocusState var focusedField: AnyHashable?

    public init(store: StoreOf<EditContributor>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasLoadedDraft {
                SwiftUI.Form {
                    Section("Contributor") {
                        nameField
                        TextField("Kind", text: $store.form.value.kind)
                    }

                    EditContributorActorProfileSection(
                        query: $store.actorSearchQuery,
                        actor: store.contributorActor,
                        sections: store.actorSearchSections,
                        failures: store.actorSearchFailures,
                        isLoading: store.actorSearchIsLoading,
                        errorMessage: store.actorSearchErrorMessage,
                        isSavingActor: store.isSavingActor,
                        queryChanged: { query in
                            store.send(.actorSearchQueryChanged(query))
                        },
                        querySubmitted: {
                            store.send(.actorSearchSubmitted)
                        },
                        identityTapped: { identity in
                            store.send(.actorIdentityTapped(identity))
                        }
                    )

                    Section("Bio") {
                        TextField("Bio", text: $store.form.value.bio, axis: .vertical)
                            .lineLimit(4...8)
                    }

                    ImageAssetPickerSection(
                        store: store.scope(\.photoImagePicker, action: \.photoImagePicker)
                    )

                    ImageAssetPickerSection(
                        store: store.scope(\.logoImagePicker, action: \.logoImagePicker)
                    )

                    ForEach($store.form.value.links) { $link in
                        Section("Link") {
                            TextField("URL", text: $link.url)
                                #if os(iOS)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif

                            Picker("Platform", selection: $link.platformRawValue) {
                                Text("Auto").tag("")
                                ForEach(ExternalPlatform.allCases, id: \.rawValue) { platform in
                                    Text(platform.name).tag(platform.rawValue)
                                }
                            }

                            Button("Remove Link", role: .destructive) {
                                store.send(.removeLinkButtonTapped(link.id))
                            }
                        }
                    }

                    Section {
                        Button("Add Link") {
                            store.send(.addLinkButtonTapped)
                        }
                        FormFieldValidationStatus(validation: store.form.validation[EditContributorFormFieldID.links])
                    }

                    if let errorMessage = store.errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            } else {
                ViewerPlaceholderView(
                    title: store.navigationTitle,
                    systemImage: "person.crop.circle",
                    description: "This contributor could not be loaded."
                )
            }
        }
        .disabled(store.isSaving)
        .onAppear {
            store.send(.onAppear)
        }
        .onChange(of: focusedField) { _, focusedField in
            if store.form.focusedField != focusedField {
                $store.form.focusedField.wrappedValue = focusedField
            }
        }
        .onChange(of: store.form.focusedField) { _, focusedField in
            if self.focusedField != focusedField {
                self.focusedField = focusedField
            }
        }
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
                    Button(store.submitButtonTitle) {
                        store.send(.saveButtonTapped)
                    }
                    .disabled(!store.canSubmit)
                }
            }
        }
        .navigationTitle(store.navigationTitle)
    }

    private var nameField: some View {
        VStack(alignment: .leading) {
            TextField("Name", text: $store.form.value.name)
                .focused($focusedField, equals: EditContributorFormFieldID.name)
                .onSubmit {
                    store.send(.form(.fieldSubmitted(EditContributorFormFieldID.name)))
                }
            FormFieldValidationStatus(validation: store.form.validation[EditContributorFormFieldID.name])
        }
    }
}

struct EditContributorActorProfileSection: View {
    @Binding var query: String
    let actor: OMERecord.Contributor.Actor?
    let sections: [PredictiveSearchSection<ActorIdentity>]
    let failures: [PredictiveSearchFailure]
    let isLoading: Bool
    let errorMessage: String?
    let isSavingActor: Bool
    let queryChanged: (String) -> Void
    let querySubmitted: () -> Void
    let identityTapped: (ActorIdentity) -> Void

    var body: some View {
        Section("ATProto Identity") {
            TextField("Search Bluesky profiles", text: $query)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit {
                    querySubmitted()
                }
                .onChange(of: query) { _, value in
                    queryChanged(value)
                }

            if let actor {
                LabeledContent("Current DID", value: actor.description)
            }

            if isLoading {
                ProgressView()
            }

            ForEach(sections) { section in

                ForEach(section.results) { identity in
                    Button {
                        identityTapped(identity)
                    } label: {
                        ContributorActorIdentityRow(
                            identity: identity,
                            isSelected: identity.did.description == actor?.description
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSavingActor)
                }
            }

            if query.trimmedForActorSearch.count >= 2 {
                Button("Look up exact handle or DID") {
                    querySubmitted()
                }
                .disabled(isLoading || isSavingActor)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            if !failures.isEmpty {
                ForEach(failures, id: \.sourceID) { failure in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(failure.title)
                        Text(failure.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct ContributorActorIdentityRow: View {
    let identity: ActorIdentity
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ContributorActorAvatar(identity: identity)

            VStack(alignment: .leading, spacing: 3) {
                Text(identity.displayTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(identity.displaySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected {
                Text("Selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ContributorActorAvatar: View {
    let identity: ActorIdentity

    var body: some View {
        AsyncImage(url: identity.avatar) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)

            case .empty, .failure:
                ContributorActorAvatarPlaceholder(identity: identity)

            @unknown default:
                ContributorActorAvatarPlaceholder(identity: identity)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }
}

struct ContributorActorAvatarPlaceholder: View {
    let identity: ActorIdentity

    var body: some View {
        Circle()
            .fill(.secondary.opacity(0.18))
            .overlay {
                Text(identity.avatarInitials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
    }
}

public struct EditableContributorLink: Identifiable, Equatable {
    public var id = UUID()
    var platformRawValue = ""
    var url = ""

    init() {}

    init(_ link: ExternalPlatform.Link) {
        self.platformRawValue = link.platform?.rawValue ?? ""
        self.url = link.url.absoluteString
    }

    var preparedLink: ExternalPlatform.Link? {
        guard let url = URL(string: trimmedURL), !trimmedURL.isEmpty else { return nil }
        return ExternalPlatform.Link(
            url: url,
            platform: trimmedPlatformRawValue.nilIfEmpty.flatMap(ExternalPlatform.init(rawValue:))
        )
    }

    var validationMessage: String? {
        guard !trimmedURL.isEmpty else { return nil }

        if URL(string: trimmedURL) == nil {
            return "Enter a valid link URL."
        }

        if !trimmedPlatformRawValue.isEmpty, ExternalPlatform(rawValue: trimmedPlatformRawValue) == nil {
            return "Choose a valid link platform."
        }

        return nil
    }

    private var trimmedPlatformRawValue: String {
        platformRawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ContributorArtworkView: View {
    let asset: OMERecord.ImageAsset?
    let cacheContext: LocalImageCacheContext?
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.secondary.opacity(0.12))

            ImageAssetAsyncImage(asset: asset, cacheContext: cacheContext) {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.square")
            .font(.system(size: size * 0.42))
            .foregroundStyle(.secondary)
    }
}

struct ContributorLinkRow: View {
    let link: ExternalPlatform.Link

    var body: some View {
        Link(destination: link.destinationURL) {
            HStack(spacing: 12) {
                Text(link.displayName)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
    }
}

extension OMERecord.Contributor {
    var preferredArtworkAsset: OMERecord.ImageAsset? {
        images?.imageAsset(role: .photo)
        ?? images?.imageAsset(role: .logo)
    }

    var displayBio: String? {
        let bio = bio?.trimmingCharacters(in: .whitespacesAndNewlines)
        return bio?.isEmpty == false ? bio : nil
    }

    func isGeneratedScheduleActorContributor(
        actor: OMERecord.Contributor.Actor,
        actorProfileHandle: String? = nil
    ) -> Bool {
        let hasImages = images?.isEmpty == false
        let hasLinks = links?.isEmpty == false
        let normalizedName = name.normalizedGeneratedActorIdentity
        let actorProfileHandleMatchesName = actorProfileHandle
            .map { $0.normalizedGeneratedActorIdentity == normalizedName } == true
        let matchesActor = actor.description.normalizedGeneratedActorIdentity == normalizedName
            || actorProfileHandleMatchesName
        return id.contributorID.rawValue.rawValue.hasPrefix("schedule-actor-")
            && matchesActor
            && displayBio == nil
            && !hasImages
            && kind == nil
            && !hasLinks
    }
}

extension ActorIdentity {
    var displayTitle: String {
        displayName?.trimmedForActorSearch.nilIfEmptyForActorDisplay
            ?? handle?.rawValue
            ?? did.description
    }

    var displaySubtitle: String {
        if let handle {
            return "@\(handle.rawValue) - \(did.description)"
        }

        return did.description
    }

    var avatarInitials: String {
        let source = displayName?.trimmedForActorSearch.nilIfEmptyForActorDisplay
            ?? handle?.rawValue
            ?? did.description
        return String(source.prefix(2)).uppercased()
    }
}

private extension Array where Element == ExternalPlatform.Link {
    var nilIfEmpty: Self? {
        isEmpty ? nil : self
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var nilIfEmptyForActorDisplay: String? {
        isEmpty ? nil : self
    }

    var trimmedForActorSearch: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedGeneratedActorIdentity: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension Error {
    var editContributorSaveDescription: String {
        let description = String(describing: self)
        return description.isEmpty ? localizedDescription : description
    }
}

private extension UserFacingText {
    static let contributorProfileLookupFailed = Self(
        "Unable to load contributor profile.",
        fallback: "Unable to load contributor profile."
    )
}

private extension ErrorOperation {
    static let contributorProfileLookup = Self("contributor.profile.lookup")
}

extension OMERecord.Contributor.Kind {
    var displayName: String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension ExternalPlatform.Link {
    var destinationURL: URL {
        guard url.scheme == nil else { return url }
        return URL(string: "https://\(url.absoluteString)") ?? url
    }

    var displayName: String {
        platform?.name ?? url.host ?? url.absoluteString
    }
}
