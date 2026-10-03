import ComposableArchitecture2
import Dependencies
import Foundation
import ATProto
import ATProtoTypes
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import Sharing
import SQLiteData
import SwiftUI

public struct SocialPostDraft: Equatable, Sendable {
    public var delivery: Social.Post.Delivery?
    public var markdown: String
    public var title: String

    public init(
        title: String = "",
        markdown: String = "",
        delivery: Social.Post.Delivery? = .standard
    ) {
        self.delivery = delivery
        self.markdown = markdown
        self.title = title
    }

    public var trimmedMarkdown: String {
        markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@Feature
public struct SocialPostForm {
    public init() {}

    public struct State {
        public init(
            eventID: Event.ID,
            categoryID: Social.Category.ID?,
            author: DID,
            draft: SocialPostDraft = SocialPostDraft()
        ) {
            self.eventID = eventID
            self.categoryID = categoryID
            self.author = author
            self.editingPost = nil
            self.draft = draft
            self.imagePicker = ImageAssetPicker.State(
                configuration: .communicationPostPhotos
            )
            self.externalCard = SocialPostExternalCard()
            self.hasLinkCard = false
            self.recordEmbed = SocialPostRecordEmbed()
            self.hasRecordEmbed = false
            self.facets = []
            self.editingFacetID = nil
            self.syndications = SocialPostSyndications.State(sources: [])
            self._categories = FetchAll(Social.Category.where { $0.event.eq(eventID) })
        }

        public init(post: Social.Post, eventID: Event.ID, author: DID) {
            self.eventID = eventID
            self.categoryID = post.category
            self.author = author
            self.editingPost = post
            let delivery: Social.Post.Delivery?
            if case let .some(.known(known)) = post.delivery {
                delivery = known
            } else {
                delivery = nil
            }
            self.draft = SocialPostDraft(
                title: post.title ?? "",
                markdown: post.text,
                delivery: delivery
            )
            self.recordEmbed = SocialPostRecordEmbed()
            self.hasRecordEmbed = false
            self.facets = (post.facets ?? []).map { SocialPostFacetEntry(facet: $0, in: post.text) }
            self.editingFacetID = nil
            self.syndications = SocialPostSyndications.State(sources: post.syndications ?? [])
            if let embed = post.embed {
                switch SocialPostEmbedContent(embed) {
                case let .images(images):
                    self.imagePicker = ImageAssetPicker.State(
                        configuration: .communicationPostPhotos,
                        recordImages: images,
                        recordID: post.id
                    )
                    self.externalCard = SocialPostExternalCard()
                    self.hasLinkCard = false
                case let .external(card):
                    self.imagePicker = ImageAssetPicker.State(
                        configuration: .communicationPostPhotos,
                        recordID: post.id
                    )
                    self.externalCard = card
                    self.hasLinkCard = true
                case .record:
                    self.imagePicker = ImageAssetPicker.State(
                        configuration: .communicationPostPhotos,
                        recordID: post.id
                    )
                    self.externalCard = SocialPostExternalCard()
                    if let record = SocialPostRecordEmbed(embed: embed) {
                        self.recordEmbed = record
                        self.hasRecordEmbed = true
                    }
                    self.hasLinkCard = false
                case .unsupported:
                    self.imagePicker = ImageAssetPicker.State(
                        configuration: .communicationPostPhotos,
                        recordID: post.id
                    )
                    self.externalCard = SocialPostExternalCard()
                    self.hasLinkCard = false
                }
            } else {
                self.imagePicker = ImageAssetPicker.State(
                    configuration: .communicationPostPhotos,
                    recordID: post.id
                )
                self.externalCard = SocialPostExternalCard()
                self.hasLinkCard = false
            }
            self._categories = FetchAll(Social.Category.where { $0.event.eq(eventID) })
        }

        public var eventID: Event.ID
        public var categoryID: Social.Category.ID?
        @FetchAll public var categories: [Social.Category]
        public var author: DID
        public var editingPost: Social.Post?
        public var destination: Destination.State?
        public var draft: SocialPostDraft
        public var errorMessage: String?
        var facets: [SocialPostFacetEntry]
        var editingFacetID: UUID?
        var externalCard: SocialPostExternalCard
        var hasLinkCard: Bool
        var recordEmbed: SocialPostRecordEmbed
        var hasRecordEmbed: Bool
        public var imagePicker: ImageAssetPicker.State
        public var isPreviewing = false
        public var isSaving = false
        public var removedEmbed = false
        var syndications: SocialPostSyndications.State

        public var canSubmit: Bool {
            (editingPost != nil || !draft.trimmedTitle.isEmpty)
                && (!draft.trimmedMarkdown.isEmpty
                    || !imagePicker.images.isEmpty
                    || hasLinkCard
                    || hasRecordEmbed
                    || hasRetainedEmbed)
                && (!hasLinkCard || externalCard.isValid)
                && (!hasRecordEmbed || recordEmbed.embed != nil)
                && syndications.draft == nil
                && editingFacetID == nil
                && facets.allSatisfy {
                    $0.validationMessage(in: effectiveText, originalText: editingPost?.text) == nil
                }
                && !isSaving
                && (draft.delivery != .emergency || canRequestEmergency)
        }

        var hasRetainedEmbed: Bool {
            guard let embed = editingPost?.embed, !removedEmbed,
                  !hasLinkCard, !hasRecordEmbed, imagePicker.images.isEmpty else { return false }
            switch SocialPostEmbedContent(embed) {
            case .record: return !hasRecordEmbed
            case .unsupported: return true
            case .images, .external: return false
            }
        }

        public var hasUnknownDelivery: Bool {
            guard let delivery = editingPost?.delivery else { return false }
            if case .unknown = delivery { return true }
            return false
        }

        public var canRequestEmergency: Bool {
            eventID.authority == .did(author)
        }

        var effectiveText: String {
            editingPost?.text == draft.markdown ? draft.markdown : draft.trimmedMarkdown
        }
    }

    public enum Action {
        case addFacetButtonTapped(SocialPostFacetEntry.Kind)
        case addLinkCardButtonTapped
        case addRecordEmbedButtonTapped
        case cancelButtonTapped
        case destination(Destination.Action)
        case editFacetButtonTapped(UUID)
        case finishFacetButtonTapped
        case imagePicker(ImageAssetPicker.Action)
        case removeFacetButtonTapped(UUID)
        case removeEmbedButtonTapped
        case removeLinkCardButtonTapped
        case removeRecordEmbedButtonTapped
        case saveButtonTapped
        case syndications(SocialPostSyndications.Action)
    }

    @Feature
    public enum Destination {
        case imageInfo(Spawn<ImageInfo>)
        case importImages(Spawn<ImportImages>)
    }

    @Dependency(\.date) var date
    @Dependency(\.defaultDatabase) var database

    private struct SaveRequest {
        let eventID: Event.ID
        let categoryID: Social.Category.ID?
        let author: DID
        let draft: SocialPostDraft
        let editingPost: Social.Post?
        let facets: [SocialPostFacetEntry]
        let images: [ImageAssetPicker.ImageValue]
        let externalCard: SocialPostExternalCard?
        let recordEmbed: SocialPostRecordEmbed?
        let removedEmbed: Bool
        let syndications: [Contributor.Source]
        let hasUnknownDelivery: Bool
        let timestamp: Date

        init(state: State, at timestamp: Date) {
            eventID = state.eventID
            categoryID = state.categoryID
            author = state.author
            draft = state.draft
            editingPost = state.editingPost
            facets = state.facets
            images = state.imagePicker.images
            externalCard = state.hasLinkCard ? state.externalCard : nil
            recordEmbed = state.hasRecordEmbed ? state.recordEmbed : nil
            removedEmbed = state.removedEmbed
            syndications = state.syndications.sources
            hasUnknownDelivery = state.hasUnknownDelivery
            self.timestamp = timestamp
        }

        func save(in db: Database) throws {
            let embed = try SocialPostForm.preparedEmbed(
                images: images,
                existing: editingPost?.embed,
                removed: removedEmbed,
                externalCard: externalCard,
                recordEmbed: recordEmbed
            )
            var fields = SocialPostRecordEditing.Fields(
                title: draft.trimmedTitle.isEmpty ? nil : draft.trimmedTitle,
                text: editingPost?.text == draft.markdown
                    ? draft.markdown : draft.trimmedMarkdown,
                delivery: draft.delivery,
                syndications: syndications.isEmpty ? nil : syndications
            )
            fields.embed = embed
            let preparedFacets = try facets.map {
                try $0.preparedFacet(in: fields.text, originalText: editingPost?.text)
            }
            fields.facets = preparedFacets.isEmpty ? nil : preparedFacets
            if let editingPost {
                if hasUnknownDelivery {
                    fields.delivery = editingPost.delivery
                }
                try SocialPostRecordEditing.update(
                    editingPost.id,
                    eventID: eventID,
                    categoryID: categoryID,
                    author: author,
                    fields: fields,
                    updatedAt: timestamp,
                    in: db
                )
            } else {
                _ = try SocialPostRecordEditing.create(
                    eventID: eventID,
                    categoryID: categoryID,
                    author: author,
                    fields: fields,
                    createdAt: timestamp,
                    in: db
                )
            }
        }
    }

    public var body: some Feature {
        Scope(\.imagePicker) {
            ImageAssetPicker()
        }
        Scope(\.syndications) {
            SocialPostSyndications()
        }
        Update { state, action in
            switch action {
            case let .addFacetButtonTapped(kind):
                let entry = SocialPostFacetEntry(kind: kind)
                state.editingFacetID = entry.id
                state.facets.append(entry)

            case let .editFacetButtonTapped(id):
                guard state.facets.contains(where: { $0.id == id && $0.isSupported }) else { return }
                state.editingFacetID = id

            case .finishFacetButtonTapped:
                guard let id = state.editingFacetID,
                      let entry = state.facets.first(where: { $0.id == id }),
                      entry.validationMessage(
                        in: state.effectiveText,
                        originalText: state.editingPost?.text
                      ) == nil else { return }
                state.editingFacetID = nil

            case let .removeFacetButtonTapped(id):
                state.facets.removeAll { $0.id == id }
                if state.editingFacetID == id { state.editingFacetID = nil }

            case .addLinkCardButtonTapped:
                state.imagePicker.images = []
                state.externalCard = SocialPostExternalCard()
                state.hasLinkCard = true
                state.recordEmbed = SocialPostRecordEmbed()
                state.hasRecordEmbed = false
                state.removedEmbed = false

            case .addRecordEmbedButtonTapped:
                state.imagePicker.images = []
                state.externalCard = SocialPostExternalCard()
                state.hasLinkCard = false
                state.recordEmbed = SocialPostRecordEmbed()
                state.hasRecordEmbed = true
                state.removedEmbed = false

            case .cancelButtonTapped:
                store.addTask { try store.dismiss() }

            case .destination:
                break

            case .imagePicker(.addButtonTapped):
                state.hasLinkCard = false
                state.hasRecordEmbed = false
                state.removedEmbed = false
                state.destination = .importImages(
                    Spawn(state.imagePicker.importImagesState())
                )

            case let .imagePicker(.imageInfoButtonTapped(id)):
                guard let imageInfoState = state.imagePicker.imageInfoState(for: id) else {
                    return
                }
                state.destination = .imageInfo(Spawn(imageInfoState))

            case .imagePicker:
                break

            case .removeEmbedButtonTapped:
                state.imagePicker.images = []
                state.hasLinkCard = false
                state.hasRecordEmbed = false
                state.removedEmbed = true

            case .removeLinkCardButtonTapped:
                state.externalCard = SocialPostExternalCard()
                state.hasLinkCard = false
                state.removedEmbed = true

            case .removeRecordEmbedButtonTapped:
                state.recordEmbed = SocialPostRecordEmbed()
                state.hasRecordEmbed = false
                state.removedEmbed = true

            case .syndications:
                break

            case .saveButtonTapped:
                guard state.canSubmit else { return }
                let request = SaveRequest(state: state, at: date())
                state.errorMessage = nil
                state.isSaving = true
                store.addTask {
                    do {
                        try await database.write { db in
                            try request.save(in: db)
                        }
                        try store.modify {
                            $0.errorMessage = nil
                            $0.isSaving = false
                        }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to save this post."
                            $0.isSaving = false
                        }
                    }
                }
            }
        }
        .ifLet(\.destination) {
            EmptyFeature()
                .ifCaseLet(\.importImages) {
                    ImportImages()
                }
                .ifCaseLet(\.imageInfo) {
                    ImageInfo { imageID, image in
                        try store.modify {
                            $0.imagePicker.updateImageInfo(
                                imageID: imageID,
                                image: image
                            )
                        }
                    }
                }
        }
        .onEvent(ImportedImagesSubmitted.self) { images, state in
            guard case .importImages = state.destination else { return }
            state.hasLinkCard = false
            state.hasRecordEmbed = false
            state.removedEmbed = false
            state.imagePicker.append(images)
        }
    }

    private enum EmbedError: Error {
        case imageUnavailable
    }

    private static func preparedEmbed(
        images: [ImageAssetPicker.ImageValue],
        existing: Social.Post.Embed?,
        removed: Bool,
        externalCard: SocialPostExternalCard?,
        recordEmbed: SocialPostRecordEmbed?
    ) throws -> Social.Post.Embed? {
        if let externalCard { return externalCard.embed }
        if let recordEmbed { return recordEmbed.embed }
        guard !images.isEmpty else {
            guard !removed, let existing else { return nil }
            switch SocialPostEmbedContent(existing) {
            case .record, .unsupported: return existing
            case .images, .external: return nil
            }
        }
        let originalEntries: [Lexicon.JSONValue]
        if let existing,
           existing.object["$type"]?.string == "app.bsky.embed.images",
           let imagesValue = existing.object["images"],
           case let .array(entries) = imagesValue {
            originalEntries = entries
        } else {
            originalEntries = []
        }
        let entries: [Lexicon.JSONValue] = try images.map { value in
            let blob: ATProto.Blob
            if let imported = value.importedImage {
                blob = try stageLocalImageBlob(
                    imported.data,
                    mimeType: ATProto.MIMEType(rawValue: imported.mimeType)
                )
            } else if case let .known(.blob(existingBlob)) = value.image.source {
                blob = existingBlob
            } else {
                throw EmbedError.imageUnavailable
            }
            var blobObject: [String: Lexicon.JSONValue] = [
                "$type": "blob",
                "ref": .object(["$link": .string(blob.ref.rawValue)]),
                "mimeType": .string(blob.mimeType.rawValue),
            ]
            if let size = blob.size { blobObject["size"] = .integer(Int64(size)) }
            let original = originalEntries.first { entry in
                guard let image = entry.object?["image"],
                      let candidate = try? image.decoded(as: ATProto.Blob.self) else {
                    return false
                }
                return candidate.ref == blob.ref
            }
            var entry = original?.object ?? [:]
            entry["alt"] = .string(value.image.alt?.rawValue ?? "")
            entry["image"] = .object(blobObject)
            return .object(entry)
        }
        var object: [String: Lexicon.JSONValue] = [:]
        if let existing, existing.object["$type"]?.string == "app.bsky.embed.images" {
            object = existing.object
        }
        object["$type"] = "app.bsky.embed.images"
        object["images"] = .array(entries)
        return Social.Post.Embed(object)
    }

}
