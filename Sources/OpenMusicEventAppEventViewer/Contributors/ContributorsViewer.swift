import ATProto
import BlueskyActorCache
import ComposableForms
import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventEditors
import OpenMusicEventImages
import SQLiteData
import SwiftUITabFeatures
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
        public var errorMessage: String?
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
        case deleteContributors([OMERecord.ID<OMERecord.Contributor>])
        case destination(Destination.Action)
        case contributorButtonTapped(OMERecord.ID<OMERecord.Contributor>)
    }

    @Feature
    public enum Destination {
        case contributorDetail(Spawn<ContributorDetail>)
    }

    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
    @Dependency(\.defaultDatabase) var database

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

            case let .deleteContributors(contributorIDs):
                let eventID = state.eventID
                store.addTask {
                    do {
                        try database.write { db in
                            for contributorID in contributorIDs {
                                let contributorRecordID = OMERecord.Contributor.ID(
                                    organizerID: eventID.organizerID,
                                    eventID: eventID.eventID,
                                    contributorID: contributorID
                                )
                                let recordURI = OMERecord.Relationship.RecordReference(
                                    contributorID: contributorRecordID
                                )
                                .uri.description

                                try db.execute(
                                    sql: #"""
                                    DELETE FROM "app.openmusicevent.relationship"
                                    WHERE json_extract("subject", '$.uri') = ?
                                       OR json_extract("object", '$.uri') = ?
                                    """#,
                                    arguments: [recordURI, recordURI]
                                )

                                try OMERecord.Contributor
                                    .where { $0.id.organizerID.eq(eventID.organizerID) }
                                    .where { $0.id.eventID.eq(eventID.eventID) }
                                    .where { $0.id.contributorID.eq(contributorID) }
                                    .delete()
                                    .execute(db)

                                try LocalImageBlob
                                    .where { $0.organizerID.eq(eventID.organizerID) }
                                    .where { $0.eventID.eq(eventID.eventID) }
                                    .where { $0.parentKind.eq(LocalImageBlob.ParentKind.contributor) }
                                    .where { $0.parentLocalID.eq(contributorID.rawValue.rawValue) }
                                    .delete()
                                    .execute(db)
                            }
                        }
                        try store.modify {
                            $0.errorMessage = nil
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to delete contributor."
                        }
                    }
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
    let showsAuthoringControls: Bool

    public init(
        store: StoreOf<ContributorsViewer>,
        showsAuthoringControls: Bool = true
    ) {
        self.store = store
        self.showsAuthoringControls = showsAuthoringControls
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
                List {
                    if let errorMessage = store.errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    ForEach(store.filteredContributorRows) { row in
                        ContributorListButton(row: row) { contributorID in
                            store.send(.contributorButtonTapped(contributorID))
                        }
                    }
                    .onDelete { offsets in
                        deleteContributors(at: offsets)
                    }
                    .deleteDisabled(!showsAuthoringControls)
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
            if showsAuthoringControls {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.addButtonTapped)
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add Contributor")
                    }
                }
            }
        }
        .navigationDestination(item: $store.scope(\.destination, action: \.destination).contributorDetail) { detailStore in
            ContributorDetailView(
                store: detailStore,
                showsAuthoringControls: showsAuthoringControls
            )
        }
        .accessibilityIdentifier(
            "view.contributors.\(store.eventID.eventID.rawValue.rawValue)"
        )
    }

    func deleteContributors(at offsets: IndexSet) {
        let contributorIDs = offsets.compactMap { offset in
            store.filteredContributorRows.indices.contains(offset)
                ? store.filteredContributorRows[offset].contributorID
                : nil
        }
        store.send(.deleteContributors(contributorIDs))
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
        .navigationLinkListRowStyle()
        .accessibilityIdentifier(
            "button.contributor.\(row.contributorID.rawValue.rawValue)"
        )
    }
}

struct ContributorsRowView: View {
    @Environment(\.needsStageDisambiguation) var needsStageDisambiguation
    let profile: ContributorProfile
    let stageContext: ContributorStageContext?
    let subtitle: String?

    init(
        profile: ContributorProfile,
        stageContext: ContributorStageContext? = nil,
        subtitle: String? = nil
    ) {
        self.profile = profile
        self.stageContext = stageContext
        self.subtitle = subtitle
    }

    init(
        contributor: OMERecord.Contributor,
        stageContext: ContributorStageContext? = nil,
        subtitle: String? = nil
    ) {
        self.profile = ContributorProfile(contributor: contributor)
        self.stageContext = stageContext
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack {
                ContributorArtworkView(
                    asset: profile.artworkAsset,
                    cacheContext: profile.artworkCacheContext,
                    size: 60
                )

                if needsStageDisambiguation {
                    Group {
                        if let stageContext, !stageContext.stages.isEmpty {
                            ContributorStageIndicatorView(
                                colors: stageContext.stages.map { $0.color.swiftUIColor }
                            )
                        } else {
                            Rectangle()
                                .fill(Color.clear)
                        }
                    }
                    .frame(width: 5, height: 60)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .lineLimit(1)

                if let subtitle = subtitle ?? profile.subtitle {
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
        var links: [EditableContributorLink] = []
        var name = ""

        init() {}

        init(contributor: OMERecord.Contributor) {
            bio = contributor.bio ?? ""
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
        var destination: Destination.State?
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
        case destination(Destination.Action)
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case logoImagePicker(ImageAssetPicker.Action)
        case photoImagePicker(ImageAssetPicker.Action)
        case removeLinkButtonTapped(UUID)
        case saveButtonTapped
        case saveFailed(String)
        case saveSucceeded
    }

    @Feature
    public enum Destination {
        case logoImageInfo(ImageInfo)
        case logoImportImages(Spawn<ImportImages>)
        case photoImageInfo(ImageInfo)
        case photoImportImages(Spawn<ImportImages>)
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
    @StoreTaskID var actorSearchTask

    public var body: some Feature {
//        let _ = Self._logChanges()
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
                    state.actorSearchErrorMessage = "The selected account is not a valid contributor identity."
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

            case .destination(.logoImageInfo(.saveButtonTapped)):
                guard case let .logoImageInfo(imageInfo) = state.destination else { return }
                state.logoImagePicker.updateImageInfo(
                    imageID: imageInfo.id,
                    asset: imageInfo.asset
                )

            case .destination(.photoImageInfo(.saveButtonTapped)):
                guard case let .photoImageInfo(imageInfo) = state.destination else { return }
                state.photoImagePicker.updateImageInfo(
                    imageID: imageInfo.id,
                    asset: imageInfo.asset
                )

            case .destination:
                break

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

            case .logoImagePicker(.addButtonTapped):
                state.destination = .logoImportImages(
                    Spawn(state.logoImagePicker.importImagesState())
                )

            case let .logoImagePicker(.imageInfoButtonTapped(id)):
                guard let imageInfoState = state.logoImagePicker.imageInfoState(for: id) else {
                    return
                }
                state.destination = .logoImageInfo(imageInfoState)

            case .logoImagePicker:
                break

            case .photoImagePicker(.addButtonTapped):
                state.destination = .photoImportImages(
                    Spawn(state.photoImagePicker.importImagesState())
                )

            case let .photoImagePicker(.imageInfoButtonTapped(id)):
                guard let imageInfoState = state.photoImagePicker.imageInfoState(for: id) else {
                    return
                }
                state.destination = .photoImageInfo(imageInfoState)

            case .photoImagePicker:
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
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
        .onEvent(ImportedImagesSubmitted.self) { images, state in
            switch state.destination {
            case .logoImportImages(_):
                state.logoImagePicker.append(images)
            case .photoImportImages(_):
                state.photoImagePicker.append(images)
            case .logoImageInfo(_), .photoImageInfo(_), nil:
                break
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
        EditContributorContent(
            store: store,
            focusedField: $focusedField
        )
        .disabled(store.isSaving)
        .onAppear {
            store.send(.onAppear)
        }
        .onChange(of: focusedField) { _, focusedField in
            syncStoreFocusedField(focusedField)
        }
        .onChange(of: store.form.focusedField) { _, focusedField in
            syncViewFocusedField(focusedField)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                EditContributorCancelButton(store: store)
            }
            ToolbarItem(placement: .confirmationAction) {
                EditContributorSaveButton(store: store)
            }
        }
        .navigationTitle(store.navigationTitle)
        .sheet(item: $store.scope(\.destination, action: \.destination).photoImportImages) { importStore in
            NavigationStack {
                ImportImagesView(store: importStore)
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).photoImageInfo) { imageInfoStore in
            NavigationStack {
                ImageInfoView(store: imageInfoStore)
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).logoImportImages) { importStore in
            NavigationStack {
                ImportImagesView(store: importStore)
            }
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).logoImageInfo) { imageInfoStore in
            NavigationStack {
                ImageInfoView(store: imageInfoStore)
            }
        }
    }

    private func syncStoreFocusedField(_ focusedField: AnyHashable?) {
        if store.form.focusedField != focusedField {
            $store.form.focusedField.wrappedValue = focusedField
        }
    }

    private func syncViewFocusedField(_ focusedField: AnyHashable?) {
        if self.focusedField != focusedField {
            self.focusedField = focusedField
        }
    }
}

struct EditContributorContent: View {
    let store: StoreOf<EditContributor>
    let focusedField: FocusState<AnyHashable?>.Binding

    var body: some View {
        if store.hasLoadedDraft {
            EditContributorLoadedForm(
                store: store,
                focusedField: focusedField
            )
        } else {
            ViewerPlaceholderView(
                title: store.navigationTitle,
                systemImage: "person.crop.circle",
                description: "This contributor could not be loaded."
            )
        }
    }
}

struct EditContributorLoadedForm: View {
    @Bindable var store: StoreOf<EditContributor>
    let focusedField: FocusState<AnyHashable?>.Binding

    init(
        store: StoreOf<EditContributor>,
        focusedField: FocusState<AnyHashable?>.Binding
    ) {
        self.store = store
        self.focusedField = focusedField
    }

    var body: some View {
        SwiftUI.Form {
            Section("Contributor") {
                nameField
            }

            EditContributorActorProfileSection(
                query: $store.actorSearchQuery,
                actor: store.contributorActor,
                sections: store.actorSearchSections,
                failures: store.actorSearchFailures,
                isLoading: store.actorSearchIsLoading,
                errorMessage: store.actorSearchErrorMessage,
                isSavingActor: store.isSavingActor,
                queryChanged: actorSearchQueryChanged,
                querySubmitted: actorSearchSubmitted,
                identityTapped: actorIdentityTapped
            )

            Section("Bio") {
                PortableTextField(
                    "Bio",
                    text: $store.form.value.bio,
                    axis: .vertical
                )
                    .portableLineLimit(4...8)
            }

            ImageAssetPickerSection(
                store: store.scope(\.photoImagePicker, action: \.photoImagePicker)
            )

            ImageAssetPickerSection(
                store: store.scope(\.logoImagePicker, action: \.logoImagePicker)
            )

            EditContributorLinkSections(store: store)

            EditContributorAddLinkSection(store: store)

            if let errorMessage = store.errorMessage {
                Section {
                    Text(verbatim: errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading) {
            TextField("Name", text: $store.form.value.name)
                .focused(focusedField, equals: EditContributorFormFieldID.name)
                .onSubmit {
                    store.send(.form(.fieldSubmitted(EditContributorFormFieldID.name)))
                }
            FormFieldValidationStatus(validation: store.form.validation[EditContributorFormFieldID.name])
        }
    }

    private func actorSearchQueryChanged(_ query: String) {
        store.send(.actorSearchQueryChanged(query))
    }

    private func actorSearchSubmitted() {
        store.send(.actorSearchSubmitted)
    }

    private func actorIdentityTapped(_ identity: ActorIdentity) {
        store.send(.actorIdentityTapped(identity))
    }
}

struct EditContributorCancelButton: View {
    let store: StoreOf<EditContributor>

    var body: some View {
        Button {
            store.send(.cancelButtonTapped)
        } label: {
            Label("Cancel", systemImage: "xmark")
                .labelStyle(.iconOnly)
        }
    }
}

struct EditContributorSaveButton: View {
    let store: StoreOf<EditContributor>

    var body: some View {
        SubmitButton(
            isInProgress: store.isSaving,
            isDisabled: !store.canSubmit
        ) {
            store.send(.saveButtonTapped)
        }
    }
}

struct EditContributorActorProfileSection: View {
    @Binding var query: String
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
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
        Section(showsTechnicalDetails ? "ATProto Identity" : "Account") {
            TextField("Search profiles", text: $query)
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

            if showsTechnicalDetails, let actor {
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
                Button(
                    showsTechnicalDetails
                        ? "Look up exact handle or DID"
                        : "Look up exact account"
                ) {
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

struct ExternalPlatformPickerOptions: View {
    var body: some View {
        ForEach(ExternalPlatform.allCases, id: \.rawValue) { platform in
            Text(verbatim: platform.name)
                .tag(platform.rawValue)
        }
    }
}

struct EditContributorLinkSections: View {
    @Bindable var store: StoreOf<EditContributor>

    init(store: StoreOf<EditContributor>) {
        self.store = store
    }

    var body: some View {
        ForEach($store.form.value.links) { $link in
            EditableContributorLinkSection(
                link: $link,
                removeButtonTapped: removeLinkButtonTapped
            )
        }
    }

    private func removeLinkButtonTapped(id: EditableContributorLink.ID) {
        store.send(.removeLinkButtonTapped(id))
    }
}

struct EditContributorAddLinkSection: View {
    let store: StoreOf<EditContributor>

    var body: some View {
        Section {
            Button("Add Link") {
                store.send(.addLinkButtonTapped)
            }
            FormFieldValidationStatus(validation: store.form.validation[EditContributorFormFieldID.links])
        }
    }
}

struct EditableContributorLinkSection: View {
    @Binding var link: EditableContributorLink
    let removeButtonTapped: (EditableContributorLink.ID) -> Void

    init(
        link: Binding<EditableContributorLink>,
        removeButtonTapped: @escaping (EditableContributorLink.ID) -> Void
    ) {
        self._link = link
        self.removeButtonTapped = removeButtonTapped
    }

    var body: some View {
        Section("Link") {
            TextField("URL", text: $link.url)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif

            Picker("Platform", selection: $link.platformRawValue) {
                Text("Auto").tag("")
                ExternalPlatformPickerOptions()
            }

            Button("Remove Link", role: .destructive) {
                removeButtonTapped(link.id)
            }
        }
    }
}

struct ContributorActorIdentityRow: View {
    let identity: ActorIdentity
    let isSelected: Bool
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        HStack(spacing: 12) {
            ContributorActorAvatar(identity: identity)

            VStack(alignment: .leading, spacing: 3) {
                Text(identity.displayTitle(showsTechnicalDetails: showsTechnicalDetails))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = identity.displaySubtitle(
                    showsTechnicalDetails: showsTechnicalDetails
                ) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
        CachedRemoteImage(
            url: identity.avatar,
            targetSize: CGSize(width: 44, height: 44)
        ) { phase in
            switch phase {
            case let .success(image, _):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)

            case .empty, .failure, .unavailable:
                ContributorActorAvatarPlaceholder(identity: identity)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }
}

struct ContributorActorAvatarPlaceholder: View {
    let identity: ActorIdentity
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails

    var body: some View {
        Circle()
            .fill(.secondary.opacity(0.18))
            .overlay {
                Text(identity.avatarInitials(showsTechnicalDetails: showsTechnicalDetails))
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

            ImageAssetAsyncImage(
                asset: asset,
                cacheContext: cacheContext,
                renderedImageSize: CGSize(width: size, height: size)
            ) {
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

                MappedSystemImage(systemName: "arrow.up.right")
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.secondary)
            }
            .portableContentShape(Rectangle())
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
            && !hasLinks
    }
}

extension ActorIdentity {
    var displayTitle: String {
        displayTitle(showsTechnicalDetails: false)
    }

    func displayTitle(showsTechnicalDetails: Bool) -> String {
        TechnicalDetails.identityTitle(
            displayName: displayName,
            handle: handle?.rawValue,
            technicalID: did.description,
            isVisible: showsTechnicalDetails
        )
    }

    func displaySubtitle(showsTechnicalDetails: Bool) -> String? {
        TechnicalDetails.identitySubtitle(
            displayName: displayName,
            handle: handle?.rawValue,
            technicalID: did.description,
            isVisible: showsTechnicalDetails
        )
    }

    func avatarInitials(showsTechnicalDetails: Bool) -> String {
        String(displayTitle(showsTechnicalDetails: showsTechnicalDetails).prefix(2)).uppercased()
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

private extension ExternalPlatform.Link {
    var destinationURL: URL {
        guard url.scheme == nil else { return url }
        return URL(string: "https://\(url.absoluteString)") ?? url
    }

    var displayName: String {
        platform?.name ?? url.host ?? url.absoluteString
    }
}
