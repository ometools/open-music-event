import OpenMusicEventLexicon
import ATProto
import ATProtoTypes
import Bluesky
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

@Feature
public struct ContributorForm {
    public init() {}

    typealias MediaEntry = RecordMediaEditing.MediaEntry
    public typealias MediaDraft = RecordMediaEditing.MediaDraft

    public struct EditableRole: Equatable, Identifiable {
        public let id: UUID
        public var name: String

        public init(id: UUID = UUID(), name: String = "") {
            self.id = id
            self.name = name
        }

        init(_ role: Open<Contributor.Role>) {
            switch role {
            case let .known(value): self.init(name: value.rawValue)
            case let .unknown(value): self.init(name: value.string ?? "")
            }
        }

        var preparedRole: Open<Contributor.Role>? {
            let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            if let known = Contributor.Role(rawValue: value) { return .known(known) }
            return .unknown(.string(value))
        }
    }

    public struct FormValue: Equatable {
        var bio = ""
        var links: [EditableLink] = []
        var name = ""
        var roles: [EditableRole] = []

        init() {}

        init(contributor: Contributor) {
            bio = contributor.description ?? ""
            links = (contributor.links ?? []).map(EditableLink.init)
            name = contributor.name
            roles = (contributor.roles ?? []).map(EditableRole.init)
        }
    }

    public typealias FormFeature = ComposableForms.Form<FormValue>

    public struct State {
        public enum Mode: Equatable, Sendable {
            case create
            case edit(Contributor.ID)

            var contributorID: Contributor.ID? {
                switch self {
                case .create:
                    return nil
                case let .edit(contributorID):
                    return contributorID
                }
            }
        }

        public init(eventID: Event.ID) {
            self.eventID = eventID
            self.form = FormFeature.State(value: FormValue())
            self.hasLoadedDraft = true
            self.logoImagePicker = ImageAssetPicker.State(
                configuration: .contributorLogo, recordImages: nil, recordID: eventID
            )
            self.mode = .create
            self.photoImagePicker = ImageAssetPicker.State(
                configuration: .contributorPhoto, recordImages: nil, recordID: eventID
            )
        }

        public init(
            contributorID: Contributor.ID,
            eventID: Event.ID
        ) {
            self.eventID = eventID
            self.form = FormFeature.State(value: FormValue())
            self.logoImagePicker = ImageAssetPicker.State(
                configuration: .contributorLogo,
                recordImages: nil,
                recordID: eventID
            )
            self.mode = .edit(contributorID)
            self.photoImagePicker = ImageAssetPicker.State(
                configuration: .contributorPhoto,
                recordImages: nil,
                recordID: eventID
            )
        }

        public let eventID: Event.ID
        let mode: Mode

        public var actorSearchErrorMessage: String?
        public var actorSearchFailures: [PredictiveSearchFailure] = []
        public var actorSearchIsLoading = false
        public var actorSearchQuery = ""
        public var actorSearchSections: [PredictiveSearchSection<ActorIdentity>] = []
        public var contributorDID: DID?
        var destination: Destination.State?
        var editingLinkID: EditableLink.ID?
        @DebugSnapshotTracked var errorMessage: String?
        var form: FormFeature.State
        @DebugSnapshotTracked var hasLoadedDraft: Bool = false
        @DebugSnapshotTracked var isSaving: Bool = false
        public var isSavingActor = false
        var logoImagePicker: ImageAssetPicker.State
        var mediaEntries: [MediaEntry] = []
        var mediaDraft: MediaDraft?
        var originalContributor: Contributor?
        var originalImages: [OME.Image] = []
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
            hasLoadedDraft && !isSaving && !isSavingActor && mediaDraft == nil && form.canSubmit
        }

        var additionalMediaEntries: [MediaEntry] {
            mediaEntries.filter { !Self.isManagedImage($0.value, recordID: eventID) }
        }

        static func isManagedImage(_ value: Open<OME.Media>, recordID: Event.ID) -> Bool {
            guard case let .known(.image(image)) = value else { return false }
            return (image.role == nil || image.role == .known(.photo) || image.role == .known(.logo))
                && image.displayImageAsset(recordID: recordID) != nil
        }

        mutating func editMedia(_ id: UUID) {
            guard let entry = mediaEntries.first(where: { $0.id == id }) else { return }
            switch entry.value {
            case let .known(.external(external)):
                mediaDraft = MediaDraft(entryID: id, external: external)
            case let .known(.record(reference)):
                mediaDraft = MediaDraft(entryID: id, reference: reference)
            case .known(.image), .unknown:
                break
            }
        }

        mutating func saveMediaDraft() {
            guard let draft = mediaDraft, let value = draft.value() else { return }
            if let id = draft.entryID {
                guard let index = mediaEntries.firstIndex(where: { $0.id == id }) else { return }
                mediaEntries[index].value = value
            } else {
                mediaEntries.append(MediaEntry(value: value))
            }
            mediaDraft = nil
        }

        var contributorActor: DID? { contributorDID }

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
            let eventID: Event.ID
            let links: [OME.Link]?
            let logoImages: [ImageAssetPicker.ImageValue]
            let mode: Mode
            let name: String
            let originalContributor: Contributor?
            let mediaEntries: [MediaEntry]
            let photoImages: [ImageAssetPicker.ImageValue]
            let roles: [Open<Contributor.Role>]?

            init(state: State) {
                self.bio = state.form.value.bio.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                self.did = state.contributorDID
                self.eventID = state.eventID
                self.links = state.preparedLinks.nilIfEmpty
                self.logoImages = state.logoImagePicker.images
                self.mode = state.mode
                self.name = state.trimmedName
                self.originalContributor = state.originalContributor
                self.mediaEntries = state.mediaEntries
                self.photoImages = state.photoImagePicker.images
                let roles = state.form.value.roles.compactMap(\.preparedRole)
                self.roles = roles.isEmpty ? nil : roles
            }

            func fields() throws -> ContributorRecordEditing.Fields {
                var fields = originalContributor.map(ContributorRecordEditing.Fields.init)
                    ?? ContributorRecordEditing.Fields(name: name)
                fields.name = name
                fields.subject = did
                if originalContributor?.subject != did {
                    fields.source = nil
                }
                fields.description = bio
                fields.links = links
                fields.media = try preparedMedia()
                fields.roles = roles
                return fields
            }

            private func preparedMedia() throws -> [Open<OME.Media>]? {
                var photos = try photoImages.map { try preparedImage($0, role: .photo) }
                var logos = try logoImages.map { try preparedImage($0, role: .logo) }
                var media: [Open<OME.Media>] = []

                for entry in mediaEntries {
                    let existing = entry.value
                    switch existing {
                    case let .known(.image(image))
                        where image.role == .known(.logo)
                            && image.displayImageAsset(recordID: eventID) != nil:
                        if !logos.isEmpty { media.append(.known(.image(logos.removeFirst()))) }
                    case let .known(.image(image))
                        where (image.role == nil || image.role == .known(.photo))
                            && image.displayImageAsset(recordID: eventID) != nil:
                        if !photos.isEmpty { media.append(.known(.image(photos.removeFirst()))) }
                    default:
                        media.append(existing)
                    }
                }
                media.append(contentsOf: photos.map { .known(.image($0)) })
                media.append(contentsOf: logos.map { .known(.image($0)) })
                return media.isEmpty ? nil : media
            }

            private func preparedImage(
                _ value: ImageAssetPicker.ImageValue,
                role: OME.Image.Role
            ) throws -> OME.Image {
                var image = value.image
                if let importedImage = value.importedImage {
                    let blob = try stageLocalImageBlob(
                        importedImage.data,
                        mimeType: ATProto.MIMEType(rawValue: importedImage.mimeType)
                    )
                    image.source = .known(.blob(blob))
                }
                image.role = .known(role)
                return image
            }
        }

        var preparedLinks: [OME.Link] {
            form.value.links.compactMap(\.preparedLink)
        }

        mutating func resetImagePickers() {
            logoImagePicker = ImageAssetPicker.State(
                configuration: .contributorLogo,
                recordImages: originalImages,
                recordID: eventID
            )
            photoImagePicker = ImageAssetPicker.State(
                configuration: .contributorPhoto,
                recordImages: originalImages,
                recordID: eventID
            )
        }

        mutating func load(_ contributor: Contributor) {
            form = FormFeature.State(value: FormValue(contributor: contributor))
            contributorDID = contributor.subject
            originalContributor = contributor
            mediaEntries = (contributor.media ?? []).map { MediaEntry(value: $0) }
            let editableImages = (contributor.media ?? []).compactMap { medium -> OME.Image? in
                guard case let .known(.image(image)) = medium,
                      image.role == nil || image.role == .known(.photo) || image.role == .known(.logo),
                      image.displayImageAsset(recordID: eventID) != nil
                else { return nil }
                return image
            }
            originalImages = editableImages
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

        private var trimmedName: String {
            form.value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public enum Action {
        case onAppear
        case addExternalMediaButtonTapped
        case addLinkButtonTapped
        case addRecordMediaButtonTapped
        case addRoleButtonTapped
        case actorIdentityTapped(ActorIdentity)
        case actorSearchSubmitted
        case actorSearchQueryChanged(String)
        case actorSearchResponse(PredictiveSearchResponse<ActorIdentity>)
        case actorProfileResponse(BlueskyActorProfile?)
        case cancelButtonTapped
        case destination(Destination.Action)
        case editLinkButtonTapped(UUID)
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case logoImagePicker(ImageAssetPicker.Action)
        case mediaDeleteButtonTapped(UUID)
        case mediaDraftCancelButtonTapped
        case mediaDraftChanged(MediaDraft)
        case mediaDraftRemoveThumbnailButtonTapped
        case mediaDraftSaveButtonTapped
        case mediaEditButtonTapped(UUID)
        case mediaMoveButtonTapped(UUID, Int)
        case moveLinkButtonTapped(UUID, Int)
        case moveRoleButtonTapped(UUID, Int)
        case photoImagePicker(ImageAssetPicker.Action)
        case removeLinkButtonTapped(UUID)
        case removeRoleButtonTapped(UUID)
        case unlinkAccountButtonTapped
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
    @Dependency(\.date.now) var now
    @Dependency(\.blueskyActorProfileCache) var blueskyActorProfileCache
    @StoreTaskID var actorSearchTask

    public var body: some Feature {
//        let _ = Self._logChanges()
        Scope(\.form) {
            FormFeature()
                .onSubmit { value in
                    try store.send(.formSubmitted(value))
                }
        }
        Scope(\.logoImagePicker) {
            ImageAssetPicker()
        }
        Scope(\.photoImagePicker) {
            ImageAssetPicker()
        }
        Update { state, action in
            switch action {
            case .addExternalMediaButtonTapped:
                state.mediaDraft = MediaDraft(kind: .external)

            case .addLinkButtonTapped:
                let link = EditableLink()
                state.form.value.links.append(link)
                state.editingLinkID = link.id

            case .addRecordMediaButtonTapped:
                state.mediaDraft = MediaDraft(kind: .record)

            case .addRoleButtonTapped:
                state.form.value.roles.append(EditableRole())

            case .unlinkAccountButtonTapped:
                state.contributorDID = nil
                state.resetActorSearch()

            case let .actorIdentityTapped(identity):
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
                            identity.did.description
                        )
                        let refreshedProfile = try await blueskyActorProfileCache.refreshProfileIfNeeded(
                            identity.did.description,
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
                    image: imageInfo.image
                )

            case .destination(.photoImageInfo(.saveButtonTapped)):
                guard case let .photoImageInfo(imageInfo) = state.destination else { return }
                state.photoImagePicker.updateImageInfo(
                    imageID: imageInfo.id,
                    image: imageInfo.image
                )

            case .destination:
                break

            case let .editLinkButtonTapped(id):
                guard state.form.value.links.contains(where: { $0.id == id }) else { return }
                state.editingLinkID = id

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
                let createdAt = now

                store.addTask {
                    do {
                        let fields = try saveRequest.fields()
                        try await database.write { db in
                            switch saveRequest.mode {
                            case .create:
                                _ = try ContributorRecordEditing.create(
                                    eventID: saveRequest.eventID,
                                    fields: fields,
                                    createdAt: createdAt,
                                    in: db
                                )
                            case let .edit(contributorID):
                                try ContributorRecordEditing.update(
                                    contributorID,
                                    eventID: saveRequest.eventID,
                                    fields: fields,
                                    in: db
                                )
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

            case let .mediaDeleteButtonTapped(id):
                state.mediaEntries.removeAll { $0.id == id }
                if state.mediaDraft?.entryID == id { state.mediaDraft = nil }

            case .mediaDraftCancelButtonTapped:
                state.mediaDraft = nil

            case let .mediaDraftChanged(draft):
                guard state.mediaDraft != nil else { return }
                state.mediaDraft = draft

            case .mediaDraftRemoveThumbnailButtonTapped:
                state.mediaDraft?.removeThumbnail = true
                state.mediaDraft?.thumbnailURL = ""

            case .mediaDraftSaveButtonTapped:
                state.saveMediaDraft()

            case let .mediaEditButtonTapped(id):
                state.editMedia(id)

            case let .mediaMoveButtonTapped(id, offset):
                let visibleIDs = state.additionalMediaEntries.map(\.id)
                guard let visibleIndex = visibleIDs.firstIndex(of: id),
                      visibleIDs.indices.contains(visibleIndex + offset),
                      let index = state.mediaEntries.firstIndex(where: { $0.id == id }),
                      let otherIndex = state.mediaEntries.firstIndex(where: {
                          $0.id == visibleIDs[visibleIndex + offset]
                      }) else { return }
                state.mediaEntries.swapAt(index, otherIndex)

            case let .moveLinkButtonTapped(id, offset):
                guard let index = state.form.value.links.firstIndex(where: { $0.id == id }),
                      state.form.value.links.indices.contains(index + offset) else { return }
                state.form.value.links.swapAt(index, index + offset)

            case let .moveRoleButtonTapped(id, offset):
                guard let index = state.form.value.roles.firstIndex(where: { $0.id == id }),
                      state.form.value.roles.indices.contains(index + offset) else { return }
                state.form.value.roles.swapAt(index, index + offset)

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
                if state.editingLinkID == id { state.editingLinkID = nil }

            case let .removeRoleButtonTapped(id):
                state.form.value.roles.removeAll { $0.id == id }

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
        .ifLet(\.destination) {
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

private enum ContributorFormFormFieldID {
    static var links: AnyHashable { AnyHashable(\ContributorForm.FormValue.links) }
    static var name: AnyHashable { AnyHashable(\ContributorForm.FormValue.name) }
    static var roles: AnyHashable { AnyHashable(\ContributorForm.FormValue.roles) }
}

private extension ContributorForm.FormFeature {
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

            Self.Field(\.roles) {
                Validation { roles -> ValidationResult in
                    let names = roles.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
                    guard !names.contains("") else { return .invalid("Enter a role or delete the empty row.") }
                    guard Set(names).count == names.count else { return .invalid("A role can only appear once.") }
                    return .valid
                }
            }
        }
    }
}

public struct ContributorFormView: View {
    @Bindable var store: StoreOf<ContributorForm>
    @FocusState var focusedField: AnyHashable?

    public init(store: StoreOf<ContributorForm>) {
        self.store = store
    }

    public var body: some View {
        ContributorFormContent(
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
                ContributorFormCancelButton(store: store)
            }
            ToolbarItem(placement: .confirmationAction) {
                ContributorFormSaveButton(store: store)
            }
        }
        .navigationTitle(store.navigationTitle)
        .sheet(item: $store.scope(\.destination).photoImportImages) { importStore in
            NavigationStack {
                ImportImagesView(store: importStore)
            }
        }
        .sheet(item: $store.scope(\.destination).photoImageInfo) { imageInfoStore in
            NavigationStack {
                ImageInfoView(store: imageInfoStore)
            }
        }
        .sheet(item: $store.scope(\.destination).logoImportImages) { importStore in
            NavigationStack {
                ImportImagesView(store: importStore)
            }
        }
        .sheet(item: $store.scope(\.destination).logoImageInfo) { imageInfoStore in
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

struct ContributorFormContent: View {
    let store: StoreOf<ContributorForm>
    let focusedField: FocusState<AnyHashable?>.Binding

    var body: some View {
        if store.hasLoadedDraft {
            ContributorFormLoadedForm(
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

struct ContributorFormLoadedForm: View {
    @Bindable var store: StoreOf<ContributorForm>
    let focusedField: FocusState<AnyHashable?>.Binding

    init(
        store: StoreOf<ContributorForm>,
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

            ContributorFormActorProfileSection(
                query: $store.actorSearchQuery,
                actor: store.contributorActor,
                sections: store.actorSearchSections,
                failures: store.actorSearchFailures,
                isLoading: store.actorSearchIsLoading,
                errorMessage: store.actorSearchErrorMessage,
                isSavingActor: store.isSavingActor,
                unlinkAccount: { store.send(.unlinkAccountButtonTapped) },
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

            Section("Roles") {
                ForEach(store.form.value.roles) { role in
                    if let index = store.form.value.roles.firstIndex(where: { $0.id == role.id }) {
                        HStack {
                            TextField("Role", text: $store.form.value.roles[index].name)
                            Menu {
                                Button("Move Up") { store.send(.moveRoleButtonTapped(role.id, -1)) }
                                    .disabled(index == 0)
                                Button("Move Down") { store.send(.moveRoleButtonTapped(role.id, 1)) }
                                    .disabled(index == store.form.value.roles.count - 1)
                                Button("Delete", role: .destructive) {
                                    store.send(.removeRoleButtonTapped(role.id))
                                }
                            } label: {
                                Label("Role Actions", systemImage: "ellipsis.circle")
                                    .labelStyle(.iconOnly)
                            }
                        }
                    }
                }
                Button("Add Role") { store.send(.addRoleButtonTapped) }
                FormFieldValidationStatus(validation: store.form.validation[ContributorFormFormFieldID.roles])
            }

            ImageAssetPickerSection(
                store: store.scope(\.photoImagePicker)
            )

            ImageAssetPickerSection(
                store: store.scope(\.logoImagePicker)
            )

            additionalMediaSection

            ContributorFormLinkSections(store: store)

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
                .focused(focusedField, equals: ContributorFormFormFieldID.name)
                .onSubmit {
                    store.send(.form(.fieldSubmitted(ContributorFormFormFieldID.name)))
                }
            FormFieldValidationStatus(validation: store.form.validation[ContributorFormFormFieldID.name])
        }
    }

    private var additionalMediaSection: some View {
        Section("Additional Media") {
            ForEach(store.additionalMediaEntries) { entry in
                let visibleIDs = store.additionalMediaEntries.map(\.id)
                let index = visibleIDs.firstIndex(of: entry.id)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                        if let subtitle = entry.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Menu {
                        if entry.canEditLink {
                            Button("Edit") { store.send(.mediaEditButtonTapped(entry.id)) }
                        }
                        Button("Move Up") { store.send(.mediaMoveButtonTapped(entry.id, -1)) }
                            .disabled(index == 0)
                        Button("Move Down") { store.send(.mediaMoveButtonTapped(entry.id, 1)) }
                            .disabled(index == visibleIDs.count - 1)
                        Button("Delete", role: .destructive) {
                            store.send(.mediaDeleteButtonTapped(entry.id))
                        }
                    } label: {
                        Label("Media Actions", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                }
            }

            if store.mediaDraft == nil {
                Menu {
                    Button("External Link") { store.send(.addExternalMediaButtonTapped) }
                    Button("AT Protocol Record") { store.send(.addRecordMediaButtonTapped) }
                } label: {
                    Label("Add Media", systemImage: "plus")
                }
            }

            if let draft = store.mediaDraft {
                Text(draft.kind == .external ? "External Media" : "AT Protocol Record")
                    .font(.headline)
                TextField("URL", text: mediaDraftBinding.uri)
                    .accessibilityIdentifier("field.contributor-media.url")
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                if draft.kind == .external {
                    TextField("Title", text: mediaDraftBinding.title)
                        .accessibilityIdentifier("field.contributor-media.title")
                    PortableTextField(
                        "Description", text: mediaDraftBinding.description, axis: .vertical
                    )
                    .portableLineLimit(2...5)
                    TextField("Media Kind", text: mediaDraftBinding.mediaKind)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    TextField("Thumbnail URL", text: mediaDraftBinding.thumbnailURL)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    if !draft.removeThumbnail,
                       draft.thumbnail != nil || !draft.thumbnailURL.isEmpty {
                        TextField("Thumbnail Alt Text", text: mediaDraftBinding.thumbnailAlt)
                        Button("Remove Thumbnail", role: .destructive) {
                            store.send(.mediaDraftRemoveThumbnailButtonTapped)
                        }
                    }
                }
                if let validationMessage = draft.validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("Cancel") { store.send(.mediaDraftCancelButtonTapped) }
                    Spacer()
                    Button("Done") { store.send(.mediaDraftSaveButtonTapped) }
                        .accessibilityIdentifier("button.contributor-media.done")
                        .disabled(draft.validationMessage != nil)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var mediaDraftBinding: Binding<ContributorForm.MediaDraft> {
        Binding(
            get: { store.mediaDraft ?? ContributorForm.MediaDraft(kind: .external) },
            set: { store.send(.mediaDraftChanged($0)) }
        )
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

struct ContributorFormCancelButton: View {
    let store: StoreOf<ContributorForm>

    var body: some View {
        Button {
            store.send(.cancelButtonTapped)
        } label: {
            Label("Cancel", systemImage: "xmark")
                .labelStyle(.iconOnly)
        }
    }
}

struct ContributorFormSaveButton: View {
    let store: StoreOf<ContributorForm>

    var body: some View {
        SubmitButton(
            isInProgress: store.isSaving,
            isDisabled: !store.canSubmit
        ) {
            store.send(.saveButtonTapped)
        }
    }
}

struct ContributorFormActorProfileSection: View {
    @Binding var query: String
    @Environment(\.showsTechnicalDetails) var showsTechnicalDetails
    let actor: DID?
    let sections: [PredictiveSearchSection<ActorIdentity>]
    let failures: [PredictiveSearchFailure]
    let isLoading: Bool
    let errorMessage: String?
    let isSavingActor: Bool
    let unlinkAccount: () -> Void
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

            if let actor {
                LabeledContent(showsTechnicalDetails ? "Current DID" : "Linked account", value: actor.description)
                Button("Unlink Account", role: .destructive, action: unlinkAccount)
                    .disabled(isSavingActor)
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

struct ContributorFormLinkSections: View {
    @Bindable var store: StoreOf<ContributorForm>

    init(store: StoreOf<ContributorForm>) {
        self.store = store
    }

    var body: some View {
        Section("Links") {
            ForEach(store.form.value.links) { link in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(link.title.isEmpty ? (link.url.isEmpty ? "New Link" : link.url) : link.title)
                            .lineLimit(1)
                        if !link.title.isEmpty && !link.url.isEmpty {
                            Text(link.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Menu {
                        Button("Edit") { store.send(.editLinkButtonTapped(link.id)) }
                        Button("Move Up") { store.send(.moveLinkButtonTapped(link.id, -1)) }
                            .disabled(store.form.value.links.first?.id == link.id)
                        Button("Move Down") { store.send(.moveLinkButtonTapped(link.id, 1)) }
                            .disabled(store.form.value.links.last?.id == link.id)
                        Button("Delete", role: .destructive) {
                            store.send(.removeLinkButtonTapped(link.id))
                        }
                    } label: {
                        Label("Link Actions", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            Button("Add Link") {
                store.send(.addLinkButtonTapped)
            }
            FormFieldValidationStatus(validation: store.form.validation[ContributorFormFormFieldID.links])
        }
        if let index = store.form.value.links.firstIndex(where: { $0.id == store.editingLinkID }) {
            Section("Edit Link") {
                EditLinkFields(link: $store.form.value.links[index])
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

struct ContributorArtworkView: View {
    let image: DisplayImageAsset?
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.secondary.opacity(0.12))

            ImageAssetAsyncImage(
                image: image,
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
    let link: OME.Link

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

private extension Array where Element == OME.Link {
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

private extension OME.Link {
    var destinationURL: URL {
        guard url.scheme == nil else { return url }
        return URL(string: "https://\(url.absoluteString)") ?? url
    }

    var displayName: String {
        title ?? detectedPlatform.name
    }
}
