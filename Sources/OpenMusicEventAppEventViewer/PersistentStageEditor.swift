import ATProto
import ATProtoTypes
import ComposableArchitecture2
import ComposableForms
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData

enum PersistentStageSaved: FeatureEventKey {
    typealias Value = Stage.ID
}

enum PersistentStageDeleted: FeatureEventKey {
    typealias Value = Stage.ID
}

@Feature
public struct EditPersistentStage {
    public init() {}

    public struct FormValue: Equatable {
        var name = ""
        var description = ""
        var links: [EditableLink] = []

        init() {}

        init(_ stage: Stage) {
            name = stage.name
            description = stage.description ?? ""
            links = (stage.links ?? []).map(EditableLink.init)
        }
    }

    public typealias FormFeature = ComposableForms.Form<FormValue>

    public struct State {
        public enum Mode: Equatable, Sendable {
            case create
            case edit(Stage.ID)

            var stageID: Stage.ID? {
                if case let .edit(id) = self { return id }
                return nil
            }
        }

        public init(eventID: Event.ID) {
            self.eventID = eventID
            mode = .create
            form = FormFeature.State(value: FormValue())
            heroImagePicker = ImageAssetPicker.State(
                configuration: .stageHero, recordImages: nil, recordID: eventID
            )
            logoImagePicker = ImageAssetPicker.State(
                configuration: .stageLogo, recordImages: nil, recordID: eventID
            )
            posterImagePicker = ImageAssetPicker.State(
                configuration: .stagePoster, recordImages: nil, recordID: eventID
            )
            hasLoadedDraft = true
        }

        public init(stageID: Stage.ID, eventID: Event.ID) {
            self.eventID = eventID
            mode = .edit(stageID)
            form = FormFeature.State(value: FormValue())
            heroImagePicker = ImageAssetPicker.State(
                configuration: .stageHero, recordImages: nil, recordID: eventID
            )
            logoImagePicker = ImageAssetPicker.State(
                configuration: .stageLogo, recordImages: nil, recordID: eventID
            )
            posterImagePicker = ImageAssetPicker.State(
                configuration: .stagePoster, recordImages: nil, recordID: eventID
            )
        }

        public let eventID: Event.ID
        public let mode: Mode
        var destination: Destination.State?
        var editingLinkID: EditableLink.ID?
        var errorMessage: String?
        var form: FormFeature.State
        var hasLoadedDraft = false
        var heroImagePicker: ImageAssetPicker.State
        var isSaving = false
        var logoImagePicker: ImageAssetPicker.State
        var originalImages: [OME.Image] = []
        var originalStage: Stage?
        var posterImagePicker: ImageAssetPicker.State
        var showsDeleteConfirmation = false

        var canSubmit: Bool {
            hasLoadedDraft && !isSaving && form.canSubmit && validationMessage == nil
        }

        var navigationTitle: String {
            mode.stageID == nil ? "New Stage Profile" : "Edit Stage Profile"
        }

        var validationMessage: String? {
            guard hasLoadedDraft else { return nil }
            if form.value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Enter a name."
            }
            return form.value.links.compactMap(\.validationMessage).first
        }

        mutating func load(_ stage: Stage) {
            form = FormFeature.State(value: FormValue(stage))
            originalStage = stage
            originalImages = (stage.media ?? []).compactMap { medium -> OME.Image? in
                guard case let .known(.image(image)) = medium,
                      image.role == .known(.logo)
                        || image.role == .known(.hero)
                        || image.role == .known(.poster),
                      image.displayImageAsset(recordID: eventID) != nil
                else { return nil }
                return image
            }
            heroImagePicker = ImageAssetPicker.State(
                configuration: .stageHero, recordImages: originalImages, recordID: eventID
            )
            logoImagePicker = ImageAssetPicker.State(
                configuration: .stageLogo, recordImages: originalImages, recordID: eventID
            )
            posterImagePicker = ImageAssetPicker.State(
                configuration: .stagePoster, recordImages: originalImages, recordID: eventID
            )
            hasLoadedDraft = true
            errorMessage = nil
        }

        fileprivate struct SaveRequest: Sendable {
            let eventID: Event.ID
            let mode: Mode
            let name: String
            let description: String?
            let links: [OME.Link]?
            let originalStage: Stage?
            let logoImages: [ImageAssetPicker.ImageValue]
            let heroImages: [ImageAssetPicker.ImageValue]
            let posterImages: [ImageAssetPicker.ImageValue]

            init(_ state: State) {
                eventID = state.eventID
                mode = state.mode
                name = state.form.value.name.trimmingCharacters(in: .whitespacesAndNewlines)
                description = state.form.value.description.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                let preparedLinks = state.form.value.links.compactMap(\.preparedLink)
                links = preparedLinks.isEmpty ? nil : preparedLinks
                originalStage = state.originalStage
                logoImages = state.logoImagePicker.images
                heroImages = state.heroImagePicker.images
                posterImages = state.posterImagePicker.images
            }

            func fields() throws -> PersistentStageRecordEditing.Fields {
                var fields = originalStage.map(PersistentStageRecordEditing.Fields.init)
                    ?? PersistentStageRecordEditing.Fields(name: name)
                fields.name = name
                fields.description = description
                fields.links = links
                fields.media = try preparedMedia()
                return fields
            }

            private func preparedMedia() throws -> [Open<OME.Media>]? {
                var logos = try logoImages.map { try preparedImage($0, role: .logo) }
                var heroes = try heroImages.map { try preparedImage($0, role: .hero) }
                var posters = try posterImages.map { try preparedImage($0, role: .poster) }
                var media: [Open<OME.Media>] = []
                for existing in originalStage?.media ?? [] {
                    switch existing {
                    case let .known(.image(image))
                        where image.role == .known(.logo)
                            && image.displayImageAsset(recordID: eventID) != nil:
                        if !logos.isEmpty { media.append(.known(.image(logos.removeFirst()))) }
                    case let .known(.image(image))
                        where image.role == .known(.hero)
                            && image.displayImageAsset(recordID: eventID) != nil:
                        if !heroes.isEmpty { media.append(.known(.image(heroes.removeFirst()))) }
                    case let .known(.image(image))
                        where image.role == .known(.poster)
                            && image.displayImageAsset(recordID: eventID) != nil:
                        if !posters.isEmpty { media.append(.known(.image(posters.removeFirst()))) }
                    default:
                        media.append(existing)
                    }
                }
                media.append(contentsOf: logos.map { .known(.image($0)) })
                media.append(contentsOf: heroes.map { .known(.image($0)) })
                media.append(contentsOf: posters.map { .known(.image($0)) })
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
    }

    public enum Action {
        case addLinkButtonTapped
        case cancelButtonTapped
        case deleteButtonTapped
        case deleteConfirmed
        case destination(Destination.Action)
        case editLinkButtonTapped(EditableLink.ID)
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case heroImagePicker(ImageAssetPicker.Action)
        case logoImagePicker(ImageAssetPicker.Action)
        case moveLinkButtonTapped(EditableLink.ID, Int)
        case posterImagePicker(ImageAssetPicker.Action)
        case removeLinkButtonTapped(EditableLink.ID)
        case saveButtonTapped
    }

    @Feature
    public enum Destination {
        case heroImageInfo(Spawn<ImageInfo>)
        case heroImportImages(Spawn<ImportImages>)
        case logoImageInfo(Spawn<ImageInfo>)
        case logoImportImages(Spawn<ImportImages>)
        case posterImageInfo(Spawn<ImageInfo>)
        case posterImportImages(Spawn<ImportImages>)
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date.now) var now

    public var body: some Feature {
        Scope(\.form) {
            FormFeature().onSubmit { value in
                try store.send(.formSubmitted(value))
            }
        }
        Scope(\.heroImagePicker) { ImageAssetPicker() }
        Scope(\.logoImagePicker) { ImageAssetPicker() }
        Scope(\.posterImagePicker) { ImageAssetPicker() }
        Update { state, action in
            switch action {
            case .addLinkButtonTapped:
                let link = EditableLink()
                state.form.value.links.append(link)
                state.editingLinkID = link.id

            case .cancelButtonTapped:
                store.addTask { try store.dismiss() }

            case .deleteButtonTapped:
                guard state.mode.stageID != nil else { return }
                state.showsDeleteConfirmation = true

            case .deleteConfirmed:
                guard let stageID = state.mode.stageID, !state.isSaving else { return }
                state.showsDeleteConfirmation = false
                state.isSaving = true
                let eventID = state.eventID
                store.addTask {
                    do {
                        try await database.write { db in
                            try PersistentStageRecordEditing.delete(
                                stageID, eventID: eventID, in: db
                            )
                        }
                        if let task = try store.post(key: PersistentStageDeleted.self, value: stageID) {
                            await task.value
                        }
                        try store.modify { $0.isSaving = false }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = (error as? PersistentStageRecordEditing.Error) == .stageInUse
                                ? "Unlink this stage from its event places before deleting it."
                                : "Unable to delete stage profile."
                            $0.isSaving = false
                        }
                    }
                }

            case .destination:
                break

            case let .editLinkButtonTapped(id):
                guard state.form.value.links.contains(where: { $0.id == id }) else { return }
                state.editingLinkID = id

            case .form:
                break

            case .formSubmitted:
                guard state.hasLoadedDraft, !state.isSaving else { return }
                if let validationMessage = state.validationMessage {
                    state.errorMessage = validationMessage
                    return
                }
                state.errorMessage = nil
                state.isSaving = true
                let request = State.SaveRequest(state)
                let createdAt = now
                store.addTask {
                    do {
                        let fields = try request.fields()
                        let id = try await database.write { db -> Stage.ID in
                            switch request.mode {
                            case .create:
                                return try PersistentStageRecordEditing.create(
                                    eventID: request.eventID,
                                    fields: fields,
                                    createdAt: createdAt,
                                    in: db
                                )
                            case let .edit(id):
                                try PersistentStageRecordEditing.update(
                                    id, eventID: request.eventID, fields: fields, in: db
                                )
                                return id
                            }
                        }
                        if let task = try store.post(key: PersistentStageSaved.self, value: id) {
                            await task.value
                        }
                        try store.modify { $0.isSaving = false }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to save stage profile."
                            $0.isSaving = false
                        }
                    }
                }

            case .heroImagePicker(.addButtonTapped):
                state.destination = .heroImportImages(
                    Spawn(state.heroImagePicker.importImagesState())
                )
            case let .heroImagePicker(.imageInfoButtonTapped(id)):
                guard let imageInfo = state.heroImagePicker.imageInfoState(for: id) else { return }
                state.destination = .heroImageInfo(Spawn(imageInfo))
            case .heroImagePicker:
                break

            case .logoImagePicker(.addButtonTapped):
                state.destination = .logoImportImages(
                    Spawn(state.logoImagePicker.importImagesState())
                )
            case let .logoImagePicker(.imageInfoButtonTapped(id)):
                guard let imageInfo = state.logoImagePicker.imageInfoState(for: id) else { return }
                state.destination = .logoImageInfo(Spawn(imageInfo))
            case .logoImagePicker:
                break

            case let .moveLinkButtonTapped(id, offset):
                guard let index = state.form.value.links.firstIndex(where: { $0.id == id }),
                      state.form.value.links.indices.contains(index + offset) else { return }
                state.form.value.links.swapAt(index, index + offset)

            case .posterImagePicker(.addButtonTapped):
                state.destination = .posterImportImages(
                    Spawn(state.posterImagePicker.importImagesState())
                )
            case let .posterImagePicker(.imageInfoButtonTapped(id)):
                guard let imageInfo = state.posterImagePicker.imageInfoState(for: id) else { return }
                state.destination = .posterImageInfo(Spawn(imageInfo))
            case .posterImagePicker:
                break

            case let .removeLinkButtonTapped(id):
                state.form.value.links.removeAll { $0.id == id }
                if state.editingLinkID == id { state.editingLinkID = nil }

            case .saveButtonTapped:
                guard state.canSubmit else { return }
                store.addTask { try store.send(.form(.submittedForm)) }
            }
        }
        .ifLet(\.destination) {
            EmptyFeature()
                .ifCaseLet(\.heroImportImages) { ImportImages() }
                .ifCaseLet(\.heroImageInfo) {
                    ImageInfo { id, image in
                        try store.modify {
                            $0.heroImagePicker.updateImageInfo(imageID: id, image: image)
                        }
                    }
                }
                .ifCaseLet(\.logoImportImages) { ImportImages() }
                .ifCaseLet(\.logoImageInfo) {
                    ImageInfo { id, image in
                        try store.modify {
                            $0.logoImagePicker.updateImageInfo(imageID: id, image: image)
                        }
                    }
                }
                .ifCaseLet(\.posterImportImages) { ImportImages() }
                .ifCaseLet(\.posterImageInfo) {
                    ImageInfo { id, image in
                        try store.modify {
                            $0.posterImagePicker.updateImageInfo(imageID: id, image: image)
                        }
                    }
                }
        }
        .onEvent(ImportedImagesSubmitted.self) { images, state in
            switch state.destination {
            case .heroImportImages(_): state.heroImagePicker.append(images)
            case .logoImportImages(_): state.logoImagePicker.append(images)
            case .posterImportImages(_): state.posterImagePicker.append(images)
            case .heroImageInfo(_), .logoImageInfo(_), .posterImageInfo(_), nil: break
            }
        }
        .onMount { state in
            guard !state.hasLoadedDraft, let stageID = state.mode.stageID else { return }
            do {
                if let stage = try database.read({ db in
                    try Stage.find(stageID).fetchOne(db)
                }), stage.id.authority == state.eventID.authority {
                    state.load(stage)
                } else {
                    state.errorMessage = "This stage profile could not be loaded."
                }
            } catch {
                state.errorMessage = "This stage profile could not be loaded."
            }
        }
    }
}

private extension EditPersistentStage.FormFeature {
    init() {
        self.init {
            Self.Field(\.name) {
                Validation(error: "Enter a name.") {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
